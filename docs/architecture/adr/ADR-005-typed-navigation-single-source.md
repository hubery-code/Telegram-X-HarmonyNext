# ADR-005 单一强类型导航栈与页面驱动规范 (NAV-001)

- 状态：Accepted（2026-09-14，NAV-001）
- 决策者：迁移项目组与架构负责人
- 关联问题：P1-ARCH-003, G2/G3 前置阻断项

## Context

早期 `entry/src/main/ets/pages/Index.ets` 使用 4 个互相竞争的布尔标志（`showChatList`, `showSettings`, `showSearch`）和 nullable `currentChatId` 控制渲染。当页面存在二级跳转、深链（Deep Link）或转发弹层覆盖时，该模式极易产生非法状态组合，且返回栈难以维护。

## Decision

1. **确立单一类型化事实源**：使用 `EntryNavigationController` 封装 `core/navigation` 的 `NavigationStack` 与 `RouteCodec`；
2. **状态机驱动渲染**：`Index.ets` 仅保留 `@State currentRoute: AppRoute`，`build()` 中基于 `currentRoute.name` 判别联合进行分支渲染；
3. **返回栈生命周期对齐**：
   - Coordinator 随路由压栈按需拉起，仅当路由从整栈彻底移除时才执行销毁；
   - 支持 `search → chat → back → search` 状态保持（搜索词与结果不丢）；
   - 支持深链（Deep Link）安全解析压栈与导航栈序列化冷启动恢复。

## Consequences

- 根治了路由状态竞争与弹层返回栈错乱缺陷；
- 页面与协调器职责彻底解耦，为 G2/G3 交互闭环奠定坚实基础。
