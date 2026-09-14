# ADR-007 系统 Kit 彻底解耦与平台 Ports/Adapters 隔离 (ARCH-001)

- 状态：Accepted（2026-09-14，ARCH-001）
- 决策者：迁移项目组与架构负责人
- 关联问题：P1-ARCH-001, P1-ARCH-002

## Context

早期业务协调器（如 `ChatCoordinator`, `SearchCoordinator` 等）直接 import `@kit.BasicServicesKit`, `@kit.ArkUI`, `@kit.PerformanceAnalysisKit`，甚至将搜索关键词等隐私敏感字段明文上报到 `hilog`。这导致业务层脱离 HarmonyOS 宿主后无法进行单元测试，且存在重大隐私数据泄漏隐患。

## Decision

1. **抽象平台接口与 Fake**：在 `platform/ports` 建立纯 ArkTS 抽象接口（`ClipboardPort`, `ToastPort`, `SecureRandomPort`）及全内存测试 Doubles（`FakeClipboard`, `FakeToast`）；
2. **装配层生产适配器**：在 `entry/src/main/ets/platform` 封装生产实现（`HarmonyClipboardAdapter`, `HarmonyToastAdapter`, `HarmonyLogSink`）；
3. **业务层 100% Kit-Free**：所有 Feature Coordinator 严禁直接引用系统 Kit，由装配层依赖注入；日志统一经 `core/observability` 的 `Logger` 并强制执行脱敏过滤器；
4. **CI 静态拦截防线**：在 `tools/ci/check_architecture.py` 中建立强制规则，对任何 Coordinator 引入 `@kit.*` / `@ohos.*` 进行构建级阻断。

## Consequences

- 业务逻辑纯洁可测，单测执行无需 ArkUI 运行时环境，大幅提高测试稳定性与执行速度；
- 隐私数据上报得到统一拦截，日志脱敏规范在架构级得到刚性约束。
