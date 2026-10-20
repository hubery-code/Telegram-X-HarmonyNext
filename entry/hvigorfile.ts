import { hapTasks } from '@ohos/hvigor-ohos-plugin';
import * as path from 'path';
import { execFileSync } from 'child_process';
import * as fs from 'fs';
import * as os from 'os';

/**
 * 凭据注入的 python 解析。
 *
 * 为什么不再直接写死 `python3`：本仓的主开发环境是 macOS（hvigorw 的候选路径
 * 全是 `/Applications/DevEco-Studio.app/...`），而 `python3` 这个可执行名在
 * Windows 上并不存在（那里只有 `python`，且常常是 Microsoft Store 的占位桩，
 * 跑起来退出码 9009）。结果是同一份代码在 macOS 上构建正常，换到 Windows
 * 上第一个 hvigorfile.ts 就炸，报错还指不回真正的原因。
 *
 * 三个层次，逐层放宽：
 *   ① `PYTHON` / `PYTHON3` 环境变量（CI 与本地都能显式指定，最高优先）；
 *   ② PATH 上的 `python3` / `python`；
 *   ③ 常见安装目录的绝对路径（Windows 的 Microsoft Store 桩、Scoop、官方
 *      Python.org、Anaconda；macOS 的 Homebrew 与 framework；Linux 的 /usr/bin）。
 *      要这一层是因为 **hvigor 的守护进程会重建 PATH**：DEVECO_HOME 与 PATH 在
 *      Windows 上常常只剩前者，shell 里临时 `export PATH=…python` 对已经起来的
 *      daemon 完全不生效（实测 daemon 里 PATH 只剩 DevEco jbr/bin + 系统目录），
 *      于是「shell 里明明能跑 python，构建却找不到」。
 */
function resolvePython(): string {
  const candidates: string[] = [];
  for (const envName of ['PYTHON', 'PYTHON3']) {
    const value = process.env[envName];
    if (value && value.trim().length > 0) {
      candidates.push(value.trim());
    }
  }
  candidates.push('python3', 'python');
  candidates.push(...commonPythonPaths());

  const tried: string[] = [];
  for (const candidate of candidates) {
    tried.push(candidate);
    try {
      execFileSync(candidate, ['--version'], { stdio: 'ignore' });
      return candidate;
    } catch (e) {
      // 候选不可用：继续找下一个。
    }
  }
  // 诊断：把现场留下来，否则报错指不回真正的原因。
  process.stdout.write(`[hvigor-entry] python 解析失败，已试 ${tried.length} 个候选\n`);
  process.stdout.write(`[hvigor-entry] PATH=${process.env.PATH}\n`);
  for (const envName of ['PYTHON', 'PYTHON3', 'DEVECO_HOME']) {
    process.stdout.write(`[hvigor-entry] ${envName}=${process.env[envName]}\n`);
  }
  throw new Error('[hvigor-entry] 找不到可用的 python 解释器。'
    + '请设置 PYTHON 环境变量指向 python 可执行文件的绝对路径。');
}

function commonPythonPaths(): string[] {
  const out: string[] = [];
  const home = os.homedir();
  // DevEco Studio 自带 python（`plugins/app-analyzer/lib/python/python.exe`）。
  // 优先用它：构建本来就跑在 DevEco 工具链里，这个解释器一定在场，且不依赖
  // 用户另外装一份 Python —— 本机实测系统里没有任何独立 Python 安装，
  // PATH 上只有 Microsoft Store 的零字节占位桩。
  const deveco = process.env.DEVECO_HOME;
  if (deveco && deveco.trim().length > 0) {
    for (const rel of [
      path.join('plugins', 'app-analyzer', 'lib', 'python', 'python.exe'),
      path.join('tools', 'python', 'python.exe'),
    ]) {
      const candidate = path.join(deveco.trim(), rel);
      if (fs.existsSync(candidate)) {
        out.push(candidate);
      }
    }
  }
  if (process.platform === 'win32') {
    const localAppData = process.env.LOCALAPPDATA || path.join(home, 'AppData', 'Local');
    const programFiles = process.env.ProgramFiles || 'C:\\Program Files';
    const bases = [
      path.join(localAppData, 'Programs', 'Python'),
      path.join(localAppData, 'Microsoft', 'WindowsApps'),
      path.join(programFiles, 'Python'),
      path.join(home, 'scoop', 'apps', 'python', 'current'),
      path.join(home, 'Anaconda3'),
      path.join(home, 'miniconda3'),
      'C:\\Python',
    ];
    for (const base of bases) {
      if (!fs.existsSync(base)) {
        continue;
      }
      for (const exe of ['python.exe', 'python3.exe']) {
        const direct = path.join(base, exe);
        if (fs.existsSync(direct)) {
          out.push(direct);
        }
        // Python.org 的安装目录带版本号子目录（Python39 / Python312）。
        try {
          for (const sub of fs.readdirSync(base)) {
            const nested = path.join(base, sub, exe);
            if (fs.existsSync(nested)) {
              out.push(nested);
            }
          }
        } catch (e) {
          // 目录读不到就跳过，不影响其它候选。
        }
      }
    }
  } else {
    out.push('/usr/bin/python3', '/usr/local/bin/python3', '/opt/homebrew/bin/python3');
  }
  return out;
}

function ensureCredentials(): void {
  const rootDir = path.resolve(__dirname, '..');
  const injectScript = path.resolve(rootDir, 'tools/ci/inject_credentials.py');
  const python = resolvePython();
  try {
    execFileSync(python, [injectScript], {
      cwd: rootDir,
      stdio: 'inherit'
    });
  } catch (e) {
    throw new Error(`[hvigor-entry] Failed to inject credentials (${python}). `
      + 'Check local.properties or environment variables.');
  }
}

ensureCredentials();

export default {
  system: hapTasks,
  plugins: []
};
