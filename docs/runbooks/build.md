# Runbook：构建（Build）

> 本机已验证命令（2026-09-08，macOS + DevEco 内置 hvigor 6.26.4）。
> 所有命令在仓库根 `/Users/mbjpeng-yu01/androidProjects/Telegram-X-HarmonyNext` 执行。

## 0. 前置（每次新机器/新环境先跑）

```bash
./tools/ci/setup-check.sh        # 校验 SDK/NDK/hvigor/node 与 tools/toolchain-versions.json 一致；不一致退出非 0
```

## 1. 构建

```bash
./tools/ci/build.sh debug        # Debug HAP
./tools/ci/build.sh release      # Release HAP
```

等价裸命令（build.sh 内部即此）：

```bash
/Applications/DevEco-Studio.app/Contents/tools/node/bin/node hvigorw \
  assembleHap --mode module \
  -p module=entry@default \
  -p product=default \
  -p buildMode=debug \
  --no-daemon
```

产物（无 signingConfigs，输出 unsigned hap）：

```text
entry/build/default/outputs/default/entry-default-unsigned.hap
```

> 如需 signed hap：在根 `build-profile.json5` 的 `signingConfigs` 配置 debug 签名材料
> （`.p12/.cer/.p7b` 等，均被 `.gitignore` 排除），并在 product 上指定 `signingConfig`。
> 签名材料永不入库（GOV-007）。

## 2. hvigor 离线机制（重要）

- 仓库 `hvigorw` 是**薄 wrapper**：直接调用 DevEco 内置 hvigor wrapper
  （`/Applications/DevEco-Studio.app/Contents/tools/hvigor/bin/hvigorw.js`），
  不联网下载 hvigor 引擎。
- `hvigor/hvigor-config.json5` 的 `dependencies` **必须保持为空**：内置 wrapper 会据此把
  内置 `@ohos/hvigor` / `@ohos/hvigor-ohos-plugin` 软链进项目工作区
  （`~/.hvigor/project_caches/<hash>/node_modules`）。一旦在 dependencies 里声明版本，
  就会走 pnpm/npm 下载，离线环境立即失败。
- `hvigorw` 同时是 shell/JS polyglot：`./hvigorw` 与 `node hvigorw` 均可执行
  （Phase 0 验收要求后者）。
- `--version` 自检：`node hvigorw --version` → `6.26.4`。

## 3. SDK 路径陷阱

hvigor 的 SDK 扫描要求 `DEVECO_SDK_HOME` 指向 **SDK 实例目录的父目录**
（它扫描 `<DEVECO_SDK_HOME>/<subdir>/sdk-pkg.json`）。因此 wrapper 导出：

```text
DEVECO_SDK_HOME=/Applications/DevEco-Studio.app/Contents/sdk     # 不是 …/sdk/default/openharmony
```

指向 `…/sdk/default/openharmony` 会报 `00303312 Cannot find the corresponding SDK version`。

## 4. CI 全链路（GOV-006）

```bash
./tools/ci/ci.sh    # setup-check → secret-scan → lint/typecheck → 单测 → debug 构建 → release 构建
```

任何一步失败立即非 0 退出；单步调试可直接调用 `tools/ci/` 下对应脚本。
GitHub Actions 模板见 `.github/workflows/ci.yml`（self-hosted macOS runner，
job 开头检测 DevEco 路径，不存在则跳过并注明——SDK 与签名均为本机特定）。

## 5. 常见问题

| 现象 | 原因 | 处理 |
|---|---|---|
| `00303312 Cannot find the corresponding SDK version` | DEVECO_SDK_HOME 层级错 | 见 §3，用 wrapper 默认导出值 |
| wrapper 停在 Installing dependencies | hvigor-config.json5 声明了 dependencies | 清空 dependencies（见 §2） |
| `modelVersion` 相关 schema 报错 | SDK/hvigor 升级后 modelVersion 未同步 | modelVersion = SDK platformVersion（当前 `26.0.0`），根 oh-package.json5 与 hvigor-config.json5 必须一致 |
| 用了系统 node（v23/v24）跑 hvigor | 环境变量/手滑 | 统一用 `tools/ci/build.sh` 或 DevEco node 绝对路径 |
| ArkTS 编译报缺 `@ohos/hypium` | oh_modules 未安装 | `…/tools/ohpm/bin/ohpm install`（需要一次网络） |
| `hvigorw test` 报 `Could not resolve "../../../src/test/List.test"` | 本地单测用例放错位置 | 本 hvigor 版本要求 `entry/src/test/*.test.ets`，不是 `src/ohosTest/ets/test/`（见 runbooks/test.md §1.1） |

## 6. 清理

```bash
rm -rf entry/build entry/.test .hvigor   # 本工程构建与测试产物
# hvigor 工作区缓存（一般不用清）：rm -rf ~/.hvigor/project_caches/*
```

## 故障排除（实测）

### “compatibleSdkVersion 和 releaseType 与设备不匹配”（2026-09-08 实测）
- 设备 API 版本查询：`hdc shell "param get const.ohos.apiversion; param get const.ohos.releasetype"`
- API 24 对应平台版本串是 `6.1.1(24)`（映射表在 hvigor 的 `hos-sdkmanager-common/build/res/hos-config.json`）；本工程已设 `compatibleSdkVersion/targetSdkVersion = "6.1.1(24)"`，`compileSdkVersion = "26.0.0"`。
- HarmonyOS 工程 API 10–25 的 sdkVersion 必须写成 `平台版本(API)` 字符串格式，纯数字串会报 00306042。

### 签名
- 仓库 `build-profile.json5` 默认保持无秘密模板（`signingConfigs: []`），构建产物默认为 unsigned hap。
- 本地真机调试：参考 `build-profile.signing.json5.template`，或在 DevEco Studio 中配置，签名证书与口令严禁提交入库。

### Telegram API 凭据
- 必须通过仓库根 `local.properties`（已 gitignore，参考 `local.properties.template`）或环境变量 `TELEGRAM_API_ID` 与 `TELEGRAM_API_HASH` 配置。
- 构建时由 `tools/ci/inject_credentials.py` 动态校验并安全注入生成 `entry/src/main/ets/config/AppCredentials.ets`（0600 权限，已 gitignore）。
- 缺少凭据时，构建命令将立即退出并提示配置方式，禁止在日志中泄露凭据值。
