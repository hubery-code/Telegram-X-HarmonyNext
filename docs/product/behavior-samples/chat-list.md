# 行为样本：会话列表（排序 / 置顶 / 归档 / 未读徽标）

> 截图/录屏：待真机采集。本文档基于 Android 参考实现代码分析（类路径与行号已核实），真机素材回填到本文件「证据」小节。
> 关联：计划 §3.2 P1「会话列表分页、置顶、归档、未读状态」；FEATURE_MATRIX `P1-CHAT-001`。

## 1. 场景总览

会话列表的数据源完全来自 TDLib：每个 `TdApi.Chat` 携带 `positions`（`ChatPosition` 数组，含 `order`、`isPinned`、`list`），列表 UI（`ui/ChatsController.java`）按 `order` 降序排列，不维护本地排序副本。归档、置顶、未读徽标、草稿均由对应 update 增量刷新。

## 2. 场景步骤序列

### 2.1 冷启动加载与会话排序

| # | 用户动作 | 系统事件 | UI 状态 |
|---|---|---|---|
| 1 | 授权完成进入主页 | 页面创建，`chatList()` 取 `ChatPosition.CHAT_LIST_MAIN`（`ui/ChatsController.java:209-215`） | 空列表 + 顶部加载指示 |
| 2 | 自动触发首屏分页 | `LoadChats(chatList, limit)`（`telegram/Tdlib.java:1841`）；TDLib 推 `UpdateNewChat` / 已有缓存直出 | 会话项按 `ChatPosition.order` 降序插入（数值越大越靠前），头像/标题/最后一条消息摘要/时间 |
| 3 | 滚动接近底部 | 再次 `LoadChats` 追加下一页；返回 `Chats` 空数组表示没有更多 | 追加到底部，无更多时停止触发 |
| 4 | 收到新消息 | `UpdateChatLastMessage`（`telegram/Tdlib.java:7876`）+ `UpdateChatPosition`（:8064） | 该会话项移动到顶部，摘要/时间刷新；若在列表内则原地更新不重排整个列表 |
| 5 | 会话被移出主列表（归档/删除） | `UpdateChatPosition` 中该 chat 在 MAIN list 的位置消失（`ChatPosition.findPosition` 返回 null，过滤逻辑 `ui/ChatsController.java:159`） | 该项带动画移除 |

### 2.2 置顶

| # | 用户动作 | 系统事件 | UI 状态 |
|---|---|---|---|
| 1 | 长按会话 → 置顶 | `ToggleChatIsPinned(chatList, chatId, true)` | `ChatPosition.isPinned=true`，置顶区在该 list 内排在最前（按 order 排序自然置顶）；取消置顶后回落到按 order 的位置 |
| 2 | 新消息进入置顶会话 | `UpdateChatPosition` | 会话保持在置顶区顶部，不落入普通区 |

### 2.3 归档

| # | 用户动作 | 系统事件 | UI 状态 |
|---|---|---|---|
| 1 | 长按会话 → 归档 | `AddChatToList(chatId, ChatListArchive)`（经 `UpdateChatPosition` 反映） | 主列表该项移除 |
| 2 | 主列表顶部出现「已归档会话」行 | TDLib 以 archive 会话（`ChatListArchive`）承载汇总，含未读计数 | 折叠态固定于列表顶部（`ui/ChatsController.java:445` 处理 `archiveCollapsed` 布局）；点开展示归档列表 |
| 3 | 归档会话来新消息 | `UpdateChatLastMessage` / `UpdateChatUnreadCount` | 「已归档」行未读数增加；归档列表内该会话上浮 |

### 2.4 未读徽标与已读

| # | 用户动作 | 系统事件 | UI 状态 |
|---|---|---|---|
| 1 | 新消息到达（私聊） | `UpdateChatUnreadCount`（未读数）、`UpdateChatLastMessage` | 会话项右侧显示未读数徽标（静音会话徽标弱化显示） |
| 2 | 打开该聊天并停留在底部 | `ViewMessages(chatId, messageIds, …)` 上报已读 → `UpdateChatReadInbox`（`telegram/Tdlib.java:8312`，lastReadInboxMessageId 前进） | 徽标消失；其他设备同步已读 |
| 3 | 在别处（另一设备）已读 | `UpdateChatReadInbox` / `UpdateChatUnreadCount` 归零 | 徽标实时消失 |
| 4 | 手动标记未读 | `ToggleChatIsMarkedAsUnread`（`UpdateChatIsMarkedAsUnread`，`telegram/Tdlib.java:8460`） | 徽标以「未读标记」样式显示（区别于真实未读） |
| 5 | 被 @ | `UpdateChatUnreadMentionCount`（:7831） | 会话项显示 @ 标记 |
| 6 | 输入草稿后退出聊天 | `UpdateChatDraftMessage`（:8361） | 摘要位置显示「草稿：…」（草稿优先级高于最后一条消息展示） |

## 3. 关键 UI 状态汇总

- **会话项组成**：头像（含在线状态点）、标题、最后消息摘要（含发送者前缀、媒体类型占位文案）、时间/星期/日期格式、未读徽标、静音图标、置顶指示、已验证标记、草稿标记、@ 标记。
- **时间格式**：当天显示时刻，本周内显示星期，更早显示日期（列表内消息时间统一由 TDLib `Message.date` 派生）。
- **空态**：无会话时显示空态插画与说明文案。
- **归档行**：主列表顶部折叠条，展示归档未读合计；展开为独立 `ChatsController` 实例（list = `ChatListArchive`）。
- **错误/断网**：列表已缓存内容继续展示，顶部出现连接状态提示（`UpdateConnectionState`，`telegram/Tdlib.java:8972`）。

## 4. Android 类（真实路径，相对 `org/thunderdog/challegram/`）

| 类 | 作用 |
|---|---|
| `ui/ChatsController.java` | 会话列表页；`chatList()` :209-215、`ChatPosition.findPosition` 过滤 :159、归档折叠布局 :445 |
| `telegram/ChatFilter.java` | 会话过滤（文件夹/筛选条件） |
| `tgx.td.ChatPosition`（buildSrc 生成源码，非 `src/main`） | `CHAT_LIST_MAIN` 常量、`findPosition`、order/isPinned 读取 |
| `telegram/Tdlib.java` | update 分发：`updateChatLastMessage` :7876、`updateChatPosition` :8064、`updateChatReadInbox` :8312、`updateChatUnreadMentionCount` :7831、`updateChatDraftMessage` :8361、`updateChatIsMarkedAsUnread` :8460、`updateConnectionState` :8972、`LoadChats` 封装 :1841 |

## 5. TDLib 事件对照

| request | 说明 |
|---|---|
| `LoadChats(chatList, limit)` | 分页加载；空 `Chats` 结果 = 到底 |
| `ToggleChatIsPinned` / `AddChatToList` / `ToggleChatIsMarkedAsUnread` | 置顶 / 归档 / 手动未读 |
| `ViewMessages` | 打开聊天上报已读 |

| update | UI 影响 |
|---|---|
| `UpdateNewChat` / `UpdateChatLastMessage` | 插入/更新会话项，可能触发重排 |
| `UpdateChatPosition` | 排序、置顶归属、归档移入移出 |
| `UpdateChatUnreadCount` / `UpdateChatReadInbox` | 徽标增减/清零 |
| `UpdateChatUnreadMentionCount` | @ 标记 |
| `UpdateChatDraftMessage` | 草稿摘要 |
| `UpdateChatIsMarkedAsUnread` | 手动未读样式 |
| `UpdateConnectionState` | 顶部连接状态条 |

## 6. Harmony 侧验收观察点

1. 排序唯一事实源是 `ChatPosition.order`，Harmony 侧不得自建排序算法覆盖 TDLib 顺序。
2. 分页：滚动触底触发 `LoadChats`，空结果停止；快速滚动不重复请求、不乱序插入。
3. 新消息到达时仅重排受影响会话项，不全量刷新列表（大列表下不得闪屏）。
4. 置顶区在各自 chat list 内固定最前；归档行固定顶部，含归档未读合计。
5. 徽标：未读数、静音弱化、@ 标记、草稿摘要、手动未读样式五种状态可区分。
6. 已读同步：本端 `ViewMessages` 上报后徽标消失；其他端已读后本端实时消失。
7. 断网时列表可继续浏览缓存内容，并有可见连接状态提示。
8. 进入列表到首屏渲染的延迟与 Android 参考同量级（真机采集时记录基线）。

## 7. 证据（待回填）

- [ ] 会话列表首屏截图（含置顶、未读、静音、草稿各一例）
- [ ] 归档折叠/展开截图
- [ ] 新消息到达会话上浮录屏
- [ ] 已读徽标消失录屏（本端与跨端各一）
