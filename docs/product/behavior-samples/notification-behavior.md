# 行为样本：通知行为（聚合、点击跳转、多账号、前后台）

> 截图/录屏：待真机采集。本文档基于 Android 参考实现代码分析（类路径与行号已核实），真机素材回填到本文件「证据」小节。
> 关联：计划 §3.1 P0「Push Kit token 端到端唤醒」「前后台」、§3.2 P1「Push、通知点击跳转、前后台恢复」；FEATURE_MATRIX `P0-FEAS-006`。

## 1. 场景总览

通知链路分两层：

1. **在线/后台存活**：TDLib 收到 `UpdateNewMessage` → `TdlibNotificationManager` 本地构建通知（按会话聚合、按 category 分组）。
2. **进程被杀**：Push（FCM/HMS）唤醒 → token 由 `RegisterDevice` 上报给 Telegram 后端 → 推送拉起服务 → 同一路通知构建逻辑。

通知的点击/回复/划掉动作全部通过 broadcast receiver 携带 `TdlibNotificationExtras`（account_id、chat_id、message_ids、notification_group_id 等）回到应用。

## 2. 场景步骤序列

### 2.1 通知生成与聚合

| # | 用户动作 | 系统事件 | UI 状态 |
|---|---|---|---|
| 1 | （对方发消息） | `UpdateNewMessage`（分发：`telegram/Tdlib.java:7509`）→ `notificationManager.onUpdateNewMessage`（:7518） | — |
| 2 | 通知管理器判定是否提醒 | 检查：当前账号是否激活、该聊天免打扰设置、是否正在前台浏览该聊天、Passcode 锁 | 前台且正看着该聊天 → 不弹通知；锁屏密码开启 → 内容隐藏 |
| 3 | 构建通知组 | `TdlibNotificationGroup` 按（account, category, chat）聚合单条 `TdlibNotification`；category 分组上限 `MAX_CATEGORY = CATEGORY_SECRET`（`telegram/TdlibNotificationGroup.java:37,214`） | 同一会话多条消息聚合为一条系统通知：标题 = 发送者/会话名，正文 = 最新消息或多行摘要 |
| 4 | 样式与动作 | `TdlibNotificationStyle` 构建：contentIntent = `TdlibNotificationUtils.newIntent(accountId, localChatId, targetMessageId)`（`telegram/TdlibNotificationStyle.java:594`，`telegram/TdlibNotificationUtils.java:231`）；动作按钮：回复（broadcast :365）、静音/取消静音 :412/:426、隐藏 :439 | 系统通知弹出：消息摘要、回复输入框（Android 内联回复）、划掉即隐藏 |

### 2.2 点击跳转

| # | 用户动作 | 系统事件 | UI 状态 |
|---|---|---|---|
| 1 | 点击通知 | PendingIntent 拉起 `MainActivity`，extras 含 `account_id`、`chat_id`、`message_ids`、`max_notification_id` | 冷启动：走完授权状态判断后直接开目标聊天；热启动：切账号（若通知属于非当前账号）→ `tdlib.ui().openChat(context, chatId, params)` 定位到对应消息（`MainActivity.java:751-777` 解析 extras、:1395 打开聊天） |
| 2 | 进入聊天 | `ViewMessages` 上报已读 → `UpdateChatReadInbox` | 该会话未读清零，对应通知被撤下 |
| 3 | 划掉通知 | broadcast → `receiver/TGRemoveReceiver.java`（`TdlibNotificationExtras.parse`） | 标记该组消息为「已隐藏」，不再重复弹出；历史消息本身不变 |
| 4 | 通知内回复 | broadcast → `receiver/TGBaseReplyReceiver.java` → `SendMessage` 到对应 chat | 回复发送后通知更新（剩余条数减少或撤下） |

### 2.3 多账号

| # | 用户动作 | 系统事件 | UI 状态 |
|---|---|---|---|
| 1 | 账号 B 来消息（当前在账号 A） | 同上通知链路，extras.account_id = B | 通知标题体现账号归属（多账号场景附加账号标识）；点击后先切换到账号 B 再开聊天 |
| 2 | 点击账号 B 的通知 | `MainActivity` 检测到非当前账号 → 激活账号 B（`telegram/TdlibManager.java` 切换） | 会话列表短暂加载后进入目标聊天 |
| 3 | Push 唤醒（账号 B 进程级） | 推送到达时若账号 B 未激活，`MainActivity.java:154` 逻辑：「Syncing other accounts, since user launched the app」——拉起后同步唤醒其他账号拉取消息 | 通知按各自账号正确归属弹出，不串号 |

### 2.4 Push token 注册

| # | 用户动作 | 系统事件 | UI 状态 |
|---|---|---|---|
| 1 | 登录成功/启动 | 平台 push token 获取 → `RegisterDevice(deviceToken, otherUserIds)`（`telegram/Tdlib.java:683`） | 无 UI；失败后台重试。Harmony 侧对应：Push Kit token 走同一 request 上报 Telegram 后端（P0-FEAS-006 的 Go/No-Go 验证点） |

### 2.5 前后台切换

| # | 用户动作 | 系统事件 | UI 状态 |
|---|---|---|---|
| 1 | App 退后台 | `TdlibNotificationManager implements UI.StateListener`（`telegram/TdlibNotificationManager.java:77`）：前台抑制解除 | 后台期间消息全部走通知 |
| 2 | App 回前台 | 同上状态回调：隐藏/抑制属于当前可见聊天的通知 | 当前聊天的通知消失；未打开的会话通知保留 |
| 3 | Passcode 锁 | `Passcode.LockListener`：锁定时通知内容替换为「你有一条新消息」类脱敏文案 | 锁屏不泄露发送者与内容 |

## 3. 关键 UI 状态汇总

- **通知摘要**：单条 = 发送者: 内容；多条聚合 = 最新 N 条多行或「N 条新消息」+ 最新消息。
- **脱敏**：免打扰会话不出声不震动（徽标仍计）；Passcode 锁开启时内容隐藏；秘密聊天 category 独立分组。
- **动作**：回复、静音（1 小时/8 小时/2 天/永久）、隐藏。
- **点击**：总是落到「正确账号 + 正确聊天 + 正确消息」。

## 4. Android 类（真实路径，相对 `org/thunderdog/challegram/`）

| 类 | 作用 |
|---|---|
| `telegram/TdlibNotificationManager.java` | 通知中枢：消息 update → 通知；实现 `UI.StateListener`、`Passcode.LockListener`、`:77` |
| `telegram/TdlibNotificationGroup.java` | 按会话聚合：`MAX_CATEGORY` :214 |
| `telegram/TdlibNotificationStyle.java` | 样式与动作构建：contentIntent :594、回复 :365、静音 :412/:426、隐藏 :439 |
| `telegram/TdlibNotificationUtils.java` | `newIntent(accountId, chatId, messageId)` :231 |
| `telegram/TdlibNotificationExtras.java` | extras 解析（account_id/chat_id/message_ids/notification_group_id 等）:82-112 |
| `telegram/TdlibNotificationSettings.java` / `LocalScopeNotificationSettings.java` | 全局/会话级免打扰与预览设置 |
| `receiver/TGMessageReceiver.java` | 通知点击入口（extras 解析 :47） |
| `receiver/TGBaseReplyReceiver.java` | 内联回复 :41 |
| `receiver/TGRemoveReceiver.java` / `TGRemoveAllReceiver.java` | 划掉隐藏（:27 / :27） |
| `MainActivity.java` | 点击跳转路由：extras 解析 :751-777、openChat :1395、多账号同步 :154 |
| `telegram/TdlibManager.java` | 多账号激活/切换 |
| `sync/TemporaryNotification.java` | 同步期间的临时前台通知（保活拉取） |

## 5. TDLib 事件对照

| request | 说明 |
|---|---|
| `RegisterDevice` | push token 上报（P0 关键验证点） |
| `SetNotificationSettings` / `SetScopeNotificationSettings` | 静音/免打扰修改（通知动作触发） |
| `SendMessage`（reply receiver 内） | 通知内回复 |
| `ViewMessages` | 点击进聊天后已读上报 |
| `GetPushReceiverId` | 校验 push 归属 |

| update | UI 影响 |
|---|---|
| `UpdateNewMessage` | 通知生成入口 |
| `UpdateChatReadInbox` | 已读后撤下对应通知 |
| `UpdateDeleteMessages` | 消息删除后通知内容更新 |
| `UpdateNotification` / `UpdateNotificationGroup` | TDLib 建议的通知变更（服务端聚合提示） |

## 6. Harmony 侧验收观察点

1. 通知点击必须落到正确账号 + 聊天 + 消息；冷启动与热启动行为一致。
2. 同会话多条消息聚合为一条；多账号通知归属正确，点击非当前账号通知时先完成账号切换。
3. 前台浏览该聊天时不弹通知；回前台后属于可见聊天的通知清除。
4. 锁屏（Harmony 侧对应应用锁场景）下通知内容脱敏。
5. 通知内快捷回复可直接发送；划掉通知 = 隐藏，消息未读数不受影响。
6. Push Kit token 经 `RegisterDevice` 上报后，进程被杀场景能收到端到端推送唤醒（P0 Go/No-Go）。
7. 免打扰会话：无声音无震动，徽标仍计数。
8. 通知跳转后触发 `ViewMessages`，会话列表未读同步清零（与 chat-list.md 联动验证）。

## 7. 证据（待回填）

- [ ] 单条/聚合通知截图（锁屏与解锁态各一）
- [ ] 点击通知跳转目标聊天录屏（含多账号切换场景）
- [ ] 通知内回复截图
- [ ] 免打扰会话通知样式截图
- [ ] Push 唤醒端到链路验证记录（P0-FEAS-006 验收时）
