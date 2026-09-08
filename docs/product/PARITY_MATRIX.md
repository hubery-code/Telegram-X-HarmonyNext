# Parity Matrix（Android ↔ HarmonyOS 行为对等矩阵）

> 单一事实源（计划 §20）。记录**行为差异**，不是功能清单（功能清单见 FEATURE_MATRIX.md）。
> 方法论：Android 参考行为以脱敏录屏/截图/结构化样本为证据（GOV-005），
> HarmonyOS 侧以相同场景的输出对比。差分测试（计划 §12.2-4）用此表驱动。

## 状态定义

| 状态 | 含义 |
|---|---|
| `Not Started` | 尚未采集 Android 基线 |
| `Baseline Captured` | Android 行为样本已入库（test/fixtures + GOV-005 证据） |
| `Dev Match` | HarmonyOS 实现与基线一致（自动化差分通过） |
| `Deviation` | 有意差异：必须在「差异与理由」列说明并获批准 |
| `Gap` | 无意差异 / 未实现：P0/P1 项即为缺陷 |

## 对比项骨架

| ID | 对比域 | Android 参考位置 | 基线证据 | HarmonyOS 实现 | 状态 | 差异与理由 |
|---|---|---|---|---|---|---|
| PAR-001 | 消息气泡布局（时间/状态/tail） | `component/chat/`（如 `MessageView.java`，开工时核实） | — | — | Not Started | — |
| PAR-002 | 会话列表排序（置顶/未读/草稿态） | `ui/ChatsController.java` | — | — | Not Started | — |
| PAR-003 | 未读数与 @ 提及计数 | `ui/ChatsController.java` + `telegram/ChatListener` | — | — | Not Started | — |
| PAR-004 | entity（粗体/链接/提及）渲染 | `component/chat/` entity 处理 | — | — | Not Started | — |
| PAR-005 | 日期/时间格式（含 RTL） | `util/` 格式化工具（开工时核实） | — | — | Not Started | — |
| PAR-006 | 发送失败重试交互 | `ui/MessagesController.java` | — | — | Not Started | — |
| PAR-007 | 图片查看器手势/缩放 | `mediaview/` | — | — | Not Started | — |
| PAR-008 | 通知点击跳转目标会话 | `receiver/` 通知路由 | — | — | Not Started | — |
| PAR-009 | 离线后消息补发顺序 | `telegram/` 连接恢复逻辑 | — | — | Not Started | — |
| PAR-010 | 深色主题色值 | `theme/` | — | — | Not Started | — |

## 使用规则

1. 每个 P0/P1 工作包开工前，先把涉及行推进到 `Baseline Captured`（GOV-005 证据）。
2. `Deviation` 必须包含：理由、批准人、失效日期（最长一个里程碑，见计划 §16）。
3. `Gap` 在 P0/P1 范围即为 P1/P2 级缺陷，进入风险登记册。
