# ADR-002 单 Entry HAP + HAR 模块化策略

- 状态：Accepted（2026-09-08，GOV-001/GOV-003）
- 决策者：迁移项目组（Phase 0 主会话 AI，待架构负责人确认）

## Context

计划 §4.2 的依赖图要求 feature/core/platform 分层隔离，但仓库首期只有一个空壳 entry 可构建。过早把每个页面拆成 HAR 会导致构建配置噪音和跨 HAR 编译变慢；过晚拆分又会让 Android 单体技术债（巨型类、跨层 import、全局单例）在新代码里复制。

## Decision

- **单 Entry HAP**：只有一个 entry HAP 产物；`feature_*`、`core_*`、`platform_*` 逐步以 **HAR** 模块挂到 hvigor。
- **骨架先建、注册后置**：目录骨架（core/*、platform/*、feature/*、native/*）Phase 0 全部创建但不注册进 `build-profile.json5`；每个 HAR 在其首个工作包落地时才注册。
- **Feature HAR 对应稳定业务边界，不是页面数量**（计划 §4.3）：如 `feature/chat` 包含聊天页 + 消息列表组件，而不是每页一 HAR。
- `native/tdcore` 以 native HAR/.so 形式被 `core/td_gateway` 依赖（G1 工作包验证）。
- 模块依赖方向由 CI 检查强制（G2 的 GOV-006 扩展项），检查规则 = ARCHITECTURE.md §2 七条。

## Alternatives

1. **多 HAP（feature 各一个 HAP）**：应用内多 HAP 适用于超大独立功能，Telegram X 单体内聚度高，多 HAP 只会增加安装与版本协调成本。放弃。
2. **HSP 共享包**：运行时共享适合多应用共享；同应用内 HAR 编译期链接更简单、无版本对齐问题。后期如包体需要再评估。放弃（现阶段）。
3. **不做模块拆分，单 module 内分 package**：零构建成本，但无法强制依赖方向，Android 技术债复制风险最高。放弃。

## Consequences

- 构建配置集中在根 `build-profile.json5`；新增 HAR 时必须同步登记 modules 与依赖。
- 目录已存在但未注册的模块**不进入构建**，防止空模块拖慢构建或误被引用。
- 代码评审 + 后续 CI 依赖检查共同保证不出现跨层 import。

## Validation

- Phase 0：根 build-profile.json5 仅含 entry；`./tools/ci/build.sh debug|release` 通过。
- G2 退出条件：依赖方向检查在 CI 可运行（GOV-006 后续工作包）。

## Rollback

拆除 HAR 回归单 module：把 HAR 源码移回 entry/src/main/ets 下并重写 import。已在目录结构上保留 entry 主导航能力，回滚成本 = 一次移动 + import 重写；越早做越便宜。
