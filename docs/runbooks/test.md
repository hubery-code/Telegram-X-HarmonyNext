# Runbook：测试（Test）

> Phase 0 状态：本地单元测试骨架（QA-001 部分）已就绪；设备测试待真机矩阵输入。

## 1. 本地测试（Hypium，ohosTest）

骨架位置：`entry/src/ohosTest/`（TestAbility + OpenHarmonyTestRunner + `ets/test/ListTest.ets`）。

```bash
# 安装测试依赖（一次即可，需要网络）
/Applications/DevEco-Studio.app/Contents/tools/ohpm/bin/ohpm install

# 运行本地单元测试（构建 entry 测试目标并执行 ListTest 等用例）
/Applications/DevEco-Studio.app/Contents/tools/node/bin/node hvigorw test \
  --mode module -p module=entry@default -p product=default --no-daemon
```

> 说明：`test` 任务由 hvigor 自动注入测试默认参数（`unitTestMode=true` 等）。
> 若本地 runner 在 CLI 下不可用（部分版本仅 DevEco 内可跑），以 DevEco
> 「Run ListTest」为准；CI 门禁以 `tools/ci/check.sh`（ArkTS 类型检查 + 构建）兜底，
> 完整 on-device 测试接入排期见 QA-001 后续。

## 2. 质量检查（无真机时的 CI 替代）

```bash
./tools/ci/check.sh    # setup-check + codelinter（若存在）+ assembleHap（含 ArkTS 类型检查）
```

## 3. 设备测试（Hypium / DevEco Testing）

前置：DEVICE_MATRIX.md 中的真机与系统版本已冻结； hdc 可用：

```bash
/Applications/DevEco-Studio.app/Contents/sdk/default/openharmony/toolchains/hdc list targets
```

（G1 之后补充完整 on-device 测试命令与截图基线流程。）

## 4. 证据要求

- 测试结果按 §17.2/§17.3 模板绑定 commit 入库。
- 大体积产物放 CI 制品库，仓库只留清单与摘要。
- 截图基线不得由实现 AI 无说明自动更新（§12.2-5）。
