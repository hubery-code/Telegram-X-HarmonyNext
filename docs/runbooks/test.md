# Runbook：测试（Test）

> Phase 0 状态（2026-09-08 实测更新）：**本地单元测试已可通过 CLI 真实执行并出报告**；
> 设备测试待真机矩阵输入。

## 1. 本地单元测试（Hypium，已实测 ✅）

### 1.1 用例放哪里（重要）

本 hvigor 版本（6.26.4，API 26）的本地单元测试约定与旧教程不同：

- **本地单元测试用例放在 `entry/src/test/*.test.ets`**（如 `entry/src/test/List.test.ets`）。
  hvigor 生成的测试入口页以 `../../../src/test/List.test` 的相对路径引用它——放在
  `src/ohosTest/ets/test/` 会编译失败（`Could not resolve "../../../src/test/List.test"`，已实测）。
- `entry/src/ohosTest/` 保留为**设备测试壳**：TestAbility + OpenHarmonyTestRunner +
  testability 页面，供 on-device 测试使用（§3）。

### 1.2 运行

```bash
# 安装测试依赖（一次即可，需要网络）
/Applications/DevEco-Studio.app/Contents/tools/ohpm/bin/ohpm install

# 运行本地单元测试（真实执行 Hypium 用例）
/Applications/DevEco-Studio.app/Contents/tools/node/bin/node hvigorw test \
  --mode module -p module=entry@default -p product=default --no-daemon
```

实测结果（2026-09-08）：`BUILD SUCCESSFUL`，用例真实执行：

```text
# entry/.test/default/intermediates/test/coverage_data/test_result.txt
class=ListTest
test=assertContain
result=Success
Tests run: 1, Failure: 0, Error: 0, Pass: 1, Ignore: 0
```

HTML 报告：`entry/.test/default/outputs/test/reports/index.html`。
新增用例 = 在 `entry/src/test/` 下加 `*.test.ets`（命名必须 `.test.ets` 后缀）。

### 1.3 DevEco 内运行（等价方式）

`entry/src/test/List.test.ets` 右键 → Run 'List.test'；或 Run 窗口选择测试配置。
CLI 与 IDE 底层同为 hvigor `test` 任务，结果等价。

## 2. CI 全链路与测试执行规范

```bash
./tools/ci/ci.sh    # setup-check → secret-scan → check → 单测 → debug 构建 → release 构建
```

任何一步失败立即非 0 退出。GitHub Actions 模板见 `.github/workflows/ci.yml`
（self-hosted macOS runner + DevEco 检测，无 DevEco 则跳过并注明）。

> 🚨 **AI Agent 协同红线（详见根目录 `AGENTS.md`）**：
> 全量 CI 包含所有模块的 ArkTS coverage 编译与用例执行，耗时极长（20~30 分钟）。
> **除非用户在对话中明确要求全量跑 CI，否则常规任务、修复或提交后严禁私自触发全量 CI（`./tools/ci/ci.sh`）或全模块单测（`test_all_modules.py`）。**
> 日常仅需执行：
> 1. 秒级门禁：`python3 tools/ci/check_architecture.py` & `python3 tools/ci/check_codegen.py`
> 2. 仅跑当前修改模块的单测（如 `./hvigorw test --mode module -p module=<mod>@default --no-daemon`）


## 3. 设备测试与自动化部署（真机 / 模拟器）

前置：DEVICE_MATRIX.md 真机冻结；使用工具链自动发现（或直接使用快捷脚本）：

```bash
# 一键自动识别目标设备、推包并拉起 EntryAbility
./tools/ci/device-install.sh

# 或通过底层工具链：
source tools/ci/resolve-toolchain.sh
$HDC_PATH list targets
$HDC_PATH -t <TARGET> app install -r entry/build/default/outputs/default/entry-default-signed.hap
$HDC_PATH -t <TARGET> shell "power-shell wakeup"
$HDC_PATH -t <TARGET> shell aa start -a EntryAbility -b org.telegram.x.harmony
```

详细签名出包、无头截图诊断与常见报错（如锁屏 10106102、缺签名 9568320）见 [`docs/runbooks/build.md §7`](build.md)。
启用时验证 `hvigorw onDeviceTest`（ohosTest 壳的编译与执行路径），并补充截图基线流程。

## 4. 证据要求

- 测试结果按 §17.2/§17.3 模板绑定 commit 入库。
- 大体积产物放 CI 制品库，仓库只留清单与摘要。
- 截图基线不得由实现 AI 无说明自动更新（§12.2-5）。
- 注：`entry/.test/` 为测试构建产物（等价 build/ 输出），**应被 git 忽略**；
  当前 `.gitignore` 尚未包含（GOV-007 所有者在下次修订时补 `.test/`）。
