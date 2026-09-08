# 行为样本目录（GOV-005）

> 结构化行为样本：以 Android 参考实现（`org.thunderdog/challegram`）的代码分析为依据，描述核心场景的事件序列、UI 状态与 TDLib 事件。
>
> **截图/录屏：待真机采集。** 本文档不含任何截图与录屏；真机采集后在本目录补充 `screenshots/`、`recordings/`，并在各文件「证据」小节回填素材链接。
>
> Android 参考根：`/Users/mbjpeng-yu01/androidProjects/Telegram-X/app/src/main/java/org/thunderdog/challegram/`
> 脱敏规则：禁止记录任何真实手机号、用户名、消息正文、聊天标题；示例一律使用占位符（如 `+86 1xx-xxxx-xxxx`、`<用户名>`）。

## 文件清单

| 文件 | 场景 | 对应计划范围 |
|---|---|---|
| [login-flow.md](login-flow.md) | 手机号 → 验证码 → 2FA/二维码登录状态机 | §3.2 P1 授权状态机 |
| [chat-list.md](chat-list.md) | 会话列表排序/置顶/归档/未读徽标 | §3.2 P1 会话列表 |
| [send-text-message.md](send-text-message.md) | 文本消息发送状态流转与已读态 | §3.2 P1 消息流 |
| [notification-behavior.md](notification-behavior.md) | 通知聚合、点击跳转、多账号 | §3.2 P1 Push/通知 |
| [media-basic.md](media-basic.md) | 图片消息点击查看的基础行为 | §3.2 P1 基础媒体查看 |

## 每个样本的固定结构

1. **场景步骤序列**：按时间顺序的编号步骤（用户动作 → 系统事件 → UI 变化）。
2. **关键 UI 状态**：每一步可见/可交互的状态描述。
3. **Android 类**：真实存在的相对路径（已 glob/grep 核实，引用到类与方法行号）。
4. **TDLib 事件**：request / update 的准确类名。
5. **Harmony 验收观察点**：实现完成后必须在真机上逐项核对的行为清单。
