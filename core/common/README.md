# core/common（CORE-001）

纯 ArkTS 基础层：Result、AppError、Clock、IdGenerator。无 ArkUI / Ability / Kit / TDLib / Node-API 依赖，全部为纯单测覆盖（`src/test/*.test.ets`）。

## 内容

| 文件 | 说明 |
|---|---|
| `src/main/ets/Result.ets` | `Result<T, E>` 判别联合（Ok/Err），map / flatMap / mapError / getOrElse / getOrNull / fold 组合子。用法：函数声明返回 `Result<T, AppError>`，用 `ok(v)` / `err(e)` 构造，类型参数由返回类型上下文推断。 |
| `src/main/ets/AppError.ets` | 稳定错误结构，与计划 §7 统一错误模型对齐：kind（network/tdlib/storage/parameter/platform/internal/unknown）+ 稳定 code + message（诊断，禁止直接当用户文案）+ messageKey（本地化映射，可选）+ cause（原始诊断，可选）。`AppErrors.fromTdlibError` 把 TDLib 数字错误码映射为稳定分类，原始 message 只允许进 cause。`toLogString()` 输出脱敏稳定分类串。 |
| `src/main/ets/Clock.ets` | `Clock` 接口（nowMillis / monotonicMillis）+ `SystemClock`（生产）+ `ManualClock`（测试 fake）。domain 代码只依赖接口。 |
| `src/main/ets/Id.ets` | `IdGenerator` 接口（nextRequestId）+ `RandomIdGenerator`（可注入 random source 做确定性测试）+ `SequentialIdGenerator`（测试 fake）。 |

## 交接说明 / 已知限制

1. **单调时钟**：纯 ArkTS 层没有可移植的单调时钟 API。`SystemClock.monotonicMillis()` 目前以 `Date.now()` 近似。需要真单调语义的路径（超时、序列号、事件排序）必须由 platform 适配层注入单调实现后再启用——已登记为 PLAT 后续工作包事项。
2. **AppError 对齐口径**：计划 §7 的示意模型含 business/permission 等 kind；本实现按任务要求收敛为 network/tdlib/storage/parameter/platform/internal/unknown 七大类，business 语义由 tdlib + messageKey 承载。若后续契约审查要求回贴计划原文模型，需走契约变更流程。
3. **模块注册**：已作为静态共享模块（har）注册进 `build-profile.json5`（modules 数组追加 `core_common`）。消费方（core_domain 等）在各自 oh-package.json5 中以 `"@tgx/core-common": "file:../common"` 形式依赖。

## 测试

```bash
./hvigorw test --mode module -p module=core_common@default -p product=default --no-daemon
```
