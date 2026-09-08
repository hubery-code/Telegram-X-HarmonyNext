# 行为样本：发送文本消息（pending → sent → failed 状态流转、时间戳与已读态）

> 截图/录屏：待真机采集。本文档基于 Android 参考实现代码分析（类路径与行号已核实），真机素材回填到本文件「证据」小节。
> 关联：计划 §3.1 P0「收发文本」、§3.2 P1「文本、链接、回复、转发、编辑、删除、复制」；FEATURE_MATRIX `P0-FEAS-003`、`P1-CHAT-002`、`P1-CHAT-003`、`P1-COMP-001`。

## 1. 场景总览

发送方发消息时 TDLib 先返回一条本地消息（`sendingState = MessageSendingStatePending`，id 为临时负值或本地 id），UI 立即插入气泡并显示「发送中」态；随后两条路径收敛：

- 成功：收到 quick ack 后仍保持发送中图标 → `UpdateMessageSendSucceeded`（临时 id 替换为服务端 id）→ 时钟图标变单勾。
- 失败：`UpdateMessageSendFailed`（`sendingState = MessageSendingStateFailed`，含 `canRetry`/`errorMessage`）→ 气泡显示失败标记，点击可重发或删除。

已读态与勾的绘制规则集中在 `data/TGMessage.java`（约 1 万行，消息渲染核心类）。

## 2. 场景步骤序列

### 2.1 正常发送

| # | 用户动作 | 系统事件 | UI 状态 |
|---|---|---|---|
| 1 | 在输入框键入文本，点发送 | `SendMessage(chatId, replyTo, options, InputMessageText(text, linkPreviewOptions))` | 输入框清空；气泡**立即**出现在列表底部（本地消息，发送中） |
| 2 | 本地消息建立 | TDLib 返回带 `MessageSendingStatePending` 的消息对象 | 气泡显示时钟图标；`isSending()` = `sendingState is Pending && !qack`（`data/TGMessage.java:4984-4985`，qack 见 `telegram/TdlibQuickAckManager.java`） |
| 3 | 服务端确认（quick ack 先行） | `TdlibQuickAckManager` 标记 ack | 时钟图标仍显示（TGX 在 ack 后仍等最终 update 换 id） |
| 4 | 发送成功 | `UpdateMessageSendSucceeded`（oldMessageId → 服务端 messageId）（分发：`telegram/Tdlib.java:7535`） | 临时 id 就地替换，**气泡不跳动**；时钟图标变为单勾（已发送） |
| 5 | 对方已读（私聊） | `UpdateChatReadOutbox`（`telegram/Tdlib.java:8333`，lastReadOutboxMessageId 越过本消息） | 单勾变双勾（已读） |
| 6 | 群聊/频道 | 无对方已读概念；频道显示浏览量计数 | 群聊仅单勾（或按 TDLib 规则无勾变化）；频道气泡下显示 eye + 浏览数 |

### 2.2 发送失败与重试

| # | 用户动作 | 系统事件 | UI 状态 |
|---|---|---|---|
| 1 | 断网状态点发送 | `SendMessage` 发出；TDLib 本地排队或快速失败 | 气泡保持发送中；连接恢复后 TDLib 自动续传 |
| 2 | TDLib 判定失败 | `UpdateMessageSendFailed`（分发：`telegram/Tdlib.java:7556`），`sendingState = MessageSendingStateFailed{errorCode, errorMessage, canRetry, needAnotherSender}` | `isFailed()`（`data/TGMessage.java:5065-5066`）：气泡显示失败感叹号/红色标记，时间旁出现「！」 |
| 3 | 点击失败气泡 | `canRetry=true` → `ResendMessages(chatId, [messageId])`（`telegram/Tdlib.java:4799`）；`canRetry=false` 仅提示错误文案 | 弹层提供「重发 / 删除」；重发后回到发送中态 |
| 4 | 选择删除 | `DeleteMessages(chatId, [messageId], revoke)`（`telegram/Tdlib.java:5763`；确认弹窗走 `deleteMessagesIfOk` :5767） | 气泡移除 |

### 2.3 编辑 / 删除 / 复制 / 回复 / 转发

| # | 用户动作 | 系统事件 | UI 状态 |
|---|---|---|---|
| 1 | 长按已发送消息 → 编辑 | `EditMessageText(chatId, messageId, InputMessageText, linkPreview)`（`telegram/Tdlib.java:4836`） | 输入框进入编辑模式（预填原文、出现「编辑消息」标题与完成按钮）；发送后气泡就地更新并标注「已编辑」 |
| 2 | 编辑完成 | `UpdateMessageEdited`（分发 :7603） | 气泡内容替换，时间旁出现已编辑标记 |
| 3 | 长按 → 删除（可多选） | `DeleteMessages(chatId, messageIds, revoke)`；撤回确认弹窗（24h 限制等提示由 TDLib error 反馈） | `UpdateDeleteMessages`（分发 :7686）后气泡消失；对方侧按 revoke 决定可见性 |
| 4 | 长按 → 复制 | 纯本地：写入剪贴板 | Toast「已复制」；无 TDLib 事件 |
| 5 | 输入框左滑/长按消息 → 回复 | `SendMessage(chatId, replyTo, …)`，`replyTo = InputMessageReplyToMessage(chatId, messageId, quote)`（`quote` 为选中文案的 `InputTextQuote`，可空） | 输入框上方出现引用条（发送者 + 摘要），可取消 |
| 6 | 长按 → 转发 | `ForwardMessages(chatId, fromChatId, messageIds, options)`（经分享页选择目标会话 `ui/ShareController.java`） | 目标聊天出现转发气泡（标注来源），发送状态同 2.1 |

### 2.4 时间戳与气泡细节

- 每条气泡右下角显示时间；当天与历史消息的分隔条显示日期（`TGMessage` 内日期 header 逻辑）。
- 连续同方向消息压缩间距并合并头像（header 规则 `data/TGMessage.java:820`：发送中/未读状态变化会强制 header 重绘）。
- 勾与时钟绘制：`data/TGMessage.java:2148-2159`（频道 header 计数、发送中/失败/未读三种 tick 状态分支）与 :4082-4094。
- 链接消息：`InputMessageText` 带 `linkPreviewOptions`，气泡内联展示链接预览卡片。

## 3. 关键 UI 状态汇总

- 发送中：时钟图标，气泡颜色略淡（可配置主题下为半透明遮罩）。
- 已发送：单勾。
- 已读：双勾（私聊）。
- 失败：红色「！」标记，点击出重发/删除弹层。
- 已编辑：时间旁「已编辑」。
- 回复：气泡顶部引用条；转发：来源标注。
- 草稿、@、链接预览等见 chat-list.md 与 media-basic.md 交叉引用。

## 4. Android 类（真实路径，相对 `org/thunderdog/challegram/`）

| 类 | 作用 |
|---|---|
| `ui/MessagesController.java` | 聊天页（约 12.8k 行）：输入栏、发送动作、长按菜单、滚动与已读上报 |
| `component/chat/ChatBottomBarView.java` | 输入栏（草稿/引用/编辑模式 UI） |
| `data/TGMessage.java` | 气泡渲染与发送状态判定：`isSending` :4984、`isFailed` :5065、`isUnread` :5187、tick 绘制 :2148-2159、:4082-4094 |
| `telegram/Tdlib.java` | `resendMessages` :4799、`editMessageText` :4836、`deleteMessages` :5763、`updateMessageSendSucceeded` :7535、`updateMessageSendFailed` :7556、`updateMessageEdited` :7603、`updateMessagesDeleted` :7686、`updateChatReadOutbox` :8333 |
| `telegram/TdlibQuickAckManager.java` | quick ack 跟踪（影响 isSending 判定） |
| `ui/ShareController.java` | 转发目标选择 |

## 5. TDLib 事件对照

| request | 说明 |
|---|---|
| `SendMessage` / `EditMessageText` / `DeleteMessages` / `ResendMessages` / `ForwardMessages` | 发送与修改族 |
| `ViewMessages` | 打开聊天/滚动到底上报已读 |

| update | UI 影响 |
|---|---|
| `UpdateMessageSendSucceeded` | 临时 id → 服务端 id 就地替换，时钟 → 单勾 |
| `UpdateMessageSendFailed` | 失败标记 + 重发/删除入口 |
| `UpdateMessageEdited` | 内容替换 + 「已编辑」标记 |
| `UpdateDeleteMessages` | 气泡移除 |
| `UpdateChatReadOutbox` | 单勾 → 双勾（私聊已读） |
| `UpdateNewMessage`（自己其他端） | 本端发送的消息从其他设备发出时同步插入 |

## 6. Harmony 侧验收观察点

1. 发送即插入本地气泡（发送中态），不得等网络往返。
2. `UpdateMessageSendSucceeded` 的就地替换不得引起气泡位置跳动或闪烁。
3. 三种状态图标（时钟/单勾/双勾/失败！）齐全；失败气泡点击必须给出重发与删除两个动作，`canRetry=false` 时重发不可见。
4. 编辑：输入框预填、取消编辑、发送后气泡就地更新并显示「已编辑」。
5. 删除：支持多选与撤回确认；`UpdateDeleteMessages` 到达后气泡移除。
6. 回复引用条与转发来源标注可显示可取消。
7. 复制为纯本地动作，剪贴板写入有成功反馈。
8. 断网期间发送进入发送中排队态，恢复网络后自动续传成功（对应 P0「断网重连」）。
9. 跨端一致性：同一账号其他设备发出的消息在本端聊天内正确插入并去重。

## 7. 证据（待回填）

- [ ] 发送中 → 单勾 → 双勾录屏
- [ ] 失败气泡与重发/删除弹层截图
- [ ] 编辑消息前后截图
- [ ] 回复引用条与转发气泡截图
