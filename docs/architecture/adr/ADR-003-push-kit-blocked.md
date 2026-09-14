# ADR-003 Push Kit 状态裁决与 MVP-Core 交付边界 (PUSH-001)

- 状态：Accepted（2026-09-14，GOV-008 / PUSH-001）
- 决策者：迁移项目组与架构负责人
- 关联问题：P1-GOV-001, FEAT-FEAS-006, 审计报告 §7 第 10 项

## Context

Telegram 官方推送系统依赖 Google FCM、Apple APNs 以及部分特定厂商推送服务（如小米、三星）。华为 Push Kit 需通过特定的服务凭据在 Telegram 后端配置注册。
当前 Telegram-X-HarmonyNext 使用独立 Bundle 标识，缺少 Telegram 官方服务器对第三方鸿蒙 Push Kit 凭据的直连网关通道。若强行要求后台唤醒，会导致项目停滞并掩盖核心聊天功能的就绪度。

## Decision

1. **正式将 FEAT-FEAS-006 (Push Kit 端到端推送唤醒) 状态标记为 `Blocked`**，禁止保留“待做”或“进行中”的模糊状态；
2. **确立阶段交付边界：MVP-Core 里程碑**：
   - MVP-Core 定义为**受控前台长连接通信**：应用前台运行时，由 TDLib 长连接（TCP/TLS MTProto）保证 100% 实时收发；
   - 依赖系统后台任务与前台保活服务维系在线，不承诺断进程级 Push 唤醒；
   - 后续在 Release Candidate 里程碑视官方网关或自建 MTProto Push Proxy 就绪情况解封。

## Consequences

- 团队资源聚焦于核心聊天体验（消息收发、撤回、编辑、媒体、搜索与安全数据管理）；
- 避免因外部后端不支持而反复进行无意义的客户端 Push Token 联调；
- 用户与测试团队明确知晓在 MVP-Core 阶段的后台消息接收预期。
