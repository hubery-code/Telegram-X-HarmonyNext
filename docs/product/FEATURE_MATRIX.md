# Feature Matrix（P0/P1 功能表骨架）

> 单一事实源（计划 §20）。Feature Matrix 与 Parity Matrix 的区别：本表登记**要做哪些功能**；
> Parity Matrix 登记**与 Android 参考的行为差距**。
> Android 参考根：`/Users/mbjpeng-yu01/androidProjects/Telegram-X/app/src/main/java/org/thunderdog/challegram/`
> 状态机：`Backlog → Contract Ready → Implementing → Verifying → Accepted` / `Blocked / Deferred`。

列说明（每项必填）：

| 列 | 含义 |
|---|---|
| ID | 功能编号（按 feature 域分配） |
| 优先级 | P0 可行性 / P1 MVP / P2 Beta / P3 高级 |
| Android 参考位置 | 相对 `org/thunderdog/challegram/` 的路径（已 glob 核实） |
| TDLib 方法 | 主要 request；多个用 `,` 分隔 |
| 平台能力/权限 | HarmonyOS Kit + 权限 |
| 测试 ID | 关联 TEST_MATRIX.md 用例 |
| 状态 | 上表状态机 |
| 首版/最后回归 | 引入版本 / 最后回归版本 |

## P0：可行性验证（不是产品版本）

| ID | 功能 | Android 参考位置 | TDLib 方法 | 平台能力/权限 | 测试 ID | 状态 | 首版 |
|---|---|---|---|---|---|---|---|
| P0-FEAS-001 | TDLib arm64 可复现构建 | `tdlib/`（NDK 构建） | —（native） | NDK/CMake/Ninja | INT-001 | Backlog | — |
| P0-FEAS-002 | 登录（手机号→验证码→密码） | `ui/AuthorizationController.java`, `telegram/TdApi` 调用 | `SetAuthenticationPhoneNumber`, `CheckAuthenticationCode`, `CheckAuthenticationPassword` | 网络 | E2E-001 | Backlog | — |
| P0-FEAS-003 | 消息收发（文本） | `ui/MessagesController.java`, `component/chat/` | `SendMessage`, `GetChats`, `GetChatHistory` | 网络 | E2E-002 | Backlog | — |
| P0-FEAS-004 | 数据库杀进程恢复 | `telegram/TdClient` 生命周期 | `GetAuthorizationState` | — | E2E-003 | Backlog | — |
| P0-FEAS-005 | NAPI update 24h 压测（无乱序/丢失/泄漏） | —（新架构） | — | Node-API | INT-002 | Backlog | — |
| P0-FEAS-006 | Push token → Telegram 后端闭环 | `push/`（FCM/HMS 抽象） | `RegisterDevice` | Push Kit | E2E-004 | Backlog | — |
| P0-FEAS-007 | tgcalls 最小双向音视频 PoC | `voip/TgCallsController.java` | `SetCall` 等 | Call Service Kit（真机） | E2E-005 | Backlog | — |

## P1：核心聊天 MVP

| ID | 功能 | Android 参考位置 | TDLib 方法 | 平台能力/权限 | 测试 ID | 状态 | 首版 |
|---|---|---|---|---|---|---|---|
| P1-CHAT-001 | 会话列表（头像/未读/置顶/文件夹） | `ui/ChatsController.java`, `ui/ChatFilter.java` | `GetChats`, `LoadChats`, `GetChat` | — | E2E-010 | Backlog | — |
| P1-CHAT-002 | 聊天页文本消息（气泡/时间/状态） | `ui/MessagesController.java`, `component/chat/` | `GetMessage`, `ViewMessages` | — | E2E-011 | Backlog | — |
| P1-CHAT-003 | 发送状态（发送中/失败重试） | `ui/MessagesController.java` | `EditMessageReplyMarkup`（状态） | — | E2E-012 | Backlog | — |
| P1-COMP-001 | 输入栏（草稿/引用/编辑/删除） | `component/chat/ChatBottomBarView.java` | `SendMessage`（edit/delete 变体） | 剪贴板 | E2E-020 | Backlog | — |
| P1-MEDIA-001 | 图片收发/查看 | `mediaview/`, `component/ComplexMediaItem.java` | `SendMessage`（photo）, `DownloadFile` | 相册/相机权限 | E2E-030 | Backlog | — |
| P1-MEDIA-002 | 语音消息录制/播放 | `component/AudioRecordJNI` 参考，平台层重写 | `SendMessage`（voiceNote） | 麦克风权限 | E2E-031 | Backlog | — |
| P1-CONTACT-001 | 联系人列表/同步开关 | `ui/ContactsController.java` | `ImportContacts`, `SearchContacts` | 通讯录权限（按需） | E2E-040 | Backlog | — |
| P1-SET-001 | 设置主列表 | `ui/SettingsController.java`（确认实际文件名待 GOV-004 细化） | `SetOption` | — | E2E-050 | Backlog | — |
| P1-ACC-001 | 多账号（≤3）与快速切换 | `BaseApplication.kt` 账号切换逻辑, `telegram/` 监听器 | `GetAuthorizationState` 每账号 | — | E2E-060 | Backlog | — |
| P1-SEARCH-001 | 全局搜索（消息/联系人/群组） | `ui/GlobalSearchController.java`（待确认） | `SearchMessages`, `SearchChats` | — | E2E-070 | Backlog | — |

## P2 / P3

P2（公开 Beta 完整度：贴纸/表情、频道管理、通知渠道、深浅色主题、消息多选转发、群管理）与 P3（高级：Stories、Web App、视频编辑、通话高级设置）在 GOV-004 中细化补齐，本文只锁 P0/P1 骨架。

## 维护规则

- 每项变更必须绑定 work item 与 commit；「最后回归」列在每次 Gate 后更新。
- Android 参考位置在开工前必须重新 glob 核实；不存在的路径视为该工作包的 DoR 未满足。
