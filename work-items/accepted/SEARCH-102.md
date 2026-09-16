# SEARCH-102 实现报告：聊天内搜索 + 结果跳转定位（FEAT-SEARCH-002）

## 结果
- 状态：Accepted
- 特性编号：FEAT-SEARCH-002
- 执行者：主会话（DSH）
- 完成日期：2026-09-16

## 背景与范围

前一包 INTEG-002 已把全局搜索（SEARCH-101）接入 entry 导航，并把「消息结果的 messageId
已透传到 entry 但未用于定位」列为**已知边界**——现有 `ChatPage.scrollToMessageId` 只对
**已加载**的消息有效，跨页跳转需「围绕该消息拉历史」。SEARCH-102 补齐这条链路，并新增
**聊天内搜索**本身（FEAT-SEARCH-002）：在单个会话内按关键词检索并跳转定位到原消息。

Android 参考：`component/chat/MessagesSearchManager.java`、`MessagesController.java:112`，
TDLib API：`SearchChatMessages → FoundChatMessages`。

## 实际修改

### 1. 领域层（core/domain，Kit-free）
- `core/domain/src/main/ets/chat/MessageProjection.ets`：
  - 新增 `searchMessages(query, fromMessageId = 0, limit = 30)`：组 `SearchChatMessages`
    （`chat_id` 固定在投影所在会话），`searchChatMessages` 单会话检索对齐 FEAT-SEARCH-002；
    **空关键词/纯空白**直接判 `parameter/invalid/query` 不发起请求。
  - 新增 `loadHistoryAround(messageId, radius = 30)`：围绕目标消息拉一段历史——复用私有
    `requestHistory`，`from_message_id=目标` + **负 offset**（`-radius`），TDLib 语义保证返回
    目标消息本身及其邻近（limit=`2*radius` 使目标居中）；正在加载返回 null（复用既有守卫）。
  - 引 `SearchChatMessages` / `FoundChatMessages` / `encodeSearchChatMessages` /
    `decodeFoundChatMessages` 于 `@tgx/core-td-api-generated`。纯 ArkTS / Kit-free 不变。

### 2. 特性层模型与契约（feature/chat）
- `feature/chat/src/main/ets/model/ChatSearchResultItem.ets` **[NEW]**：纯 ArkTS 不可变模型，
  封装 `messageId`、`textSnippet`（原文摘要）、`dateText`（当天 HH:mm / 跨天 dd.MM）、
  `jumpable`（该消息是否已被投影缓存）。
- `feature/chat/src/main/ets/Index.ets`：导出 `ChatSearchResultItem` 及新增意图/效应。
- `feature/chat/src/main/ets/contract/ChatUiState.ets`：`ChatUiState` 扩展
  `showSearch` / `searchQuery` / `searchResults` / `isSearching` / `jumpToMessageId`，
  `ChatUiStateOptions` / `initial()` / `copyWith()` 全链同步。
- `feature/chat/src/main/ets/contract/ChatIntent.ets`：新增意图
  `OpenChatSearch` / `CloseChatSearch` / `ChatSearchQueryChanged` / `PerformChatSearch` /
  `OnChatSearchLoaded` / `OnChatSearchFailed` / `JumpToSearchResult` /
  `OnJumpToMessageReady` / `ClearJumpToMessage`，并入 `ChatIntent` union。
- `feature/chat/src/main/ets/contract/ChatEffect.ets`：新增效应
  `FetchChatSearch(chatId, query, fromMessageId)` / `JumpToMessage(messageId)`，
  并入 `ChatEffect` union。

### 3. Reducer（纯函数 MVI）
- `feature/chat/src/main/ets/reducer/ChatReducer.ets`：
  - `openChatSearch`：展开搜索面板并清空在途/结果/跳转标记；
  - `closeChatSearch`：收起并复位；
  - `chatSearchQueryChanged`：只更新 `searchQuery` 并清跳转标记；
  - `performChatSearch`：trim 后非空且不在途 → `isSearching=true` + `FetchChatSearch`；
  - `onChatSearchLoaded`：停止在途 + 回灌结果；
  - `onChatSearchFailed`：停止在途 + `errorMessage` 细条（`error.message`）；
  - `jumpToSearchResult`：id 有效且未在跳转 → 关面板 + 置 `jumpToMessageId` +
    `JumpToMessage` 效应；
  - `onJumpToMessageReady`：历史拉取完成后回灌目标 id；
  - `clearJumpToMessage`：UI 完成滚动后清标记。

### 4. 协调调度（ChatCoordinator）
- `feature/chat/src/main/ets/coordinator/ChatCoordinator.ets`：
  - `executeEffect` 新增 `fetchChatSearch`：调投影 `searchMessages`，回包
    `decodeFoundChatMessages`，逐条 `messageContentText` 取摘要 + `formatSearchResultDate`
    取日期，`projection.getMessageById` 判断 jumpable，回灌 `OnChatSearchLoaded`；失败回灌
    `OnChatSearchFailed`（统一走 AppErrors，不透传原始 message）。
  - `executeEffect` 新增 `jumpToMessage`：调投影 `loadHistoryAround`；拉完回灌
    `OnJumpToMessageReady`；正在加载返回 null 时静默跳过（目标消息会经既有投影同步自然入视图）。
  - 顶部新增 `CHAT_SEARCH_LIMIT=30` / `HISTORY_AROUND_RADIUS=30` 常量与
    `formatSearchResultDate` / `pad2` 私有助手。
  - 日志只记 `fetch_chat_search` / `chat_search_ok` / `jump_to_message` 稳定分类，不记正文。

### 5. UI 渲染与交互（ChatPage）
- `feature/chat/src/main/ets/pages/ChatPage.ets`：
  - 顶栏标题右侧新增 `🔍` 搜索入口（`SEARCH_BUTTON_SIZE`），非多选态显示，点击派发
    `OpenChatSearch`。
  - 根 Stack 新增 `SearchPanel` 覆盖层（`showSearch=true` 时）：顶部返回 `✕`（收搜）
    + `TextInput`（300ms 防抖自动执行 `PerformChatSearch`）；中部三态——
    `isSearching` → 加载指示；无结果 → 「No results」；有结果 → `List + ForEach`
    （`List` 用独立 `searchScroller`，`ForEach` 迭代 `searchResults.slice()` 满足可变数组）：
    每行原文摘要 + 日期，`jumpable=false` 时附「Tap to load」提示；点击行派发
    `JumpToSearchResult` 定位。
  - `onUiStateChanged` 顶部新增跳转逻辑：`jumpToMessageId > 0` 时在 `messages` 中查找该目标
    → `scrollToIndex(i, true, ScrollAlign.CENTER)` 居中定位并派发 `ClearJumpToMessage`，
    避免重复滚动（围绕历史已由 loadHistoryAround 拉好，目标此刻必在列表内）。
  - 新增 `@State`/私有字段 `searchScroller`、`searchDebounceTimer`。

## 自动化测试

### 领域层（core_domain）
`core/domain/src/test/chat/MessageProjection.test.ets` 新增 5 组用例：
1. `searchMessages_withEmptyQuery_rejectsParameterWithoutRequest`（纯空白不发起请求）；
2. `searchMessages_assemblesSearchChatMessagesForChat`（`searchChatMessages` 组包：
   `chat_id/query/from_message_id/limit/offset`）；
3. `searchMessages_withFromMessageId_keepsPaginationCursor`（分页游标透传）；
4. `loadHistoryAroundSendsGetChatHistoryAroundTarget`（`getChatHistory`：
   `chat_id=42`、`from_message_id=5000`、**负 offset=-30**、`limit=60`）；
5. `loadHistoryAroundWhenLoadingReturnsNullWithoutRequest`（在途守卫：返回 null 不发请求）。

### 特性层（feature_chat）
`feature/chat/src/test/ChatReducer.test.ets` 新增 11 组用例：
- 开/关（含重复开 `isNoOp`）、query 变化、空 query `isNoOp`、
  非空 query 出 `FetchChatSearch`（trim 后 query）、在途中 `isNoOp`、
  success 回灌（含 jumpable 透传）、failure 回灌 errorMessage、
  jump（关面板 + `jumpToMessageId` + `JumpToMessage` 效应）、
  invalid/already-jumping `isNoOp`、`onJumpToMessageReady`、`clearJumpToMessage`。

### 门禁验证
- `feature_chat` 单测 **155 → 169** 全 PASS；`core_domain` 单测 **73 → 78** 全 PASS。
- 全仓 **19 模块单测 922/922 项 100% 全部通过**（此前基线 903）。
- `./tools/ci/check_design_tokens.py`：Design Token 0 违规（新 UI 全用 token，
  `backgroundSecondary` 等均真实存在）。
- `./tools/ci/check_architecture.py`：0 架构边界违规（core 层/reducer/coordinator 无
  ArkUI/Kit import，domain 全 Kit-free）。
- `./tools/ci/check_codegen.py`：GEN-002/GEN-004 全过（新模型为手工纯 ArkTS，非生成代码）。
- `hvigorw test --mode module`：BUILD SUCCESSFUL。

## 模拟器实测（2026-09-16，AI 代操作首次验证）
> 目标：DevEco 本地模拟器 `127.0.0.1:5555`（aarch64，API 24/LTS 6.1.1）。unsigned debug HAP
> 一次 `hdc install -r` 安装成功，`aa start` 启动到前台。会话列表 → 点入 `be hu` 会话 → ChatPage。
> 以下是布局/hilog 实测证据（AI 用 `uitest uiInput` 代操作完成首次验证，按真机验证约定仍鼓励用户复测）。

| 步骤 | 预期 | 实测结果 |
|---|---|---|
| 会话顶栏 | 右侧出现 `🔍` 搜索入口 | ✅ layout 见 `🔍 [1046,164][1200,318]` |
| 点 `🔍` | 弹出搜索面板（`✕` + 输入框） | ✅ layout 见 `✕ [28,164][182,318]` + `TextInput [182,171][1256,311]` |
| 面板空态 | 未输入时显示「No results」 | ✅ layout 见 `No results [491,1471][765,1541]` |
| 输入 `github` | 300ms 防抖自动搜索，出结果行（摘要+日期） | ✅ layout 见结果 `https://github.com` + 日期 `15.09` |
| hilog 搜索路径 | `fetch_chat_search … from=0` → `chat_search_ok … hits=1` | ✅ `ChatCoordinator fetch_chat_search chatId=6846163203,from=0`；`chat_search_ok chatId=…,hits=1` |
| 点结果行 | 面板收起 + 列表定位到该消息并居中 | ✅ 点击后 panel 消失（`✕`/`TextInput` 均不在 layout）；`https://github.com` 消息在会话列表内居中可见 |
| hilog 跳转路径 | `jump_to_message` → `jump_to_message_ok`（loadHistoryAround 拉取成功） | ✅ `jump_to_message messageId=60817408`；`jump_to_message_ok messageId=60817408` |

## 追加修复（2026-09-16，用户反馈「点搜索结果进会话没定位」）

### 现象
在**全局搜索**里搜 `aaa` 能出结果，点消息结果进入会话后**没有定位到那条消息**（停在会话最新消息处）。
用户问「是没做还是有 bug」——答案是**两者都有**：跨页那条链路没做，会话内那条有隐患。

### 根因
1. **没做（主因，对应用户现象）**：`feature/search` 一路把 `messageId` 传了出来
   （`SearchPage.handleMessageClick → onNavigateToChat(chatId, messageId)`），entry 的
   `navigateToChatFromSearch` 也确实收到了，但 `ChatRoute` 只有 `chatId/threadId`，
   `navigateTo({ name: 'chat', chatId })` 把 `messageId` **直接丢掉**，会话页无从知道要定位谁。
   SEARCH-102 首版只实现了「会话内搜索 → 定位」，这条「搜索结果跨页进会话 → 定位」漏了。
2. **隐患：跳转会被自动定位覆盖**。`ChatPage.onUiStateChanged` 的「首屏未读定位 / 尾部新消息跟随」
   是 40–50ms 的**延迟**滚动；目标需要 `loadHistoryAround` 拉取时 `messages` 会变，两个滚动撞在
   一起时后者覆盖前者 → 表现为「点了结果却停在最新消息处」。
3. **隐患：延迟滚动用了过期下标**。跳转滚动延迟执行，这期间投影前插更早历史会让数组下标整体位移，
   用状态变更那一刻算好的下标会滚到**别的**消息上。

### 修复
- `core/navigation`：`ChatRoute` 增加可选 `messageId`；`ROUTE_DEFINITIONS` 补
  `spec('messageId','int',false,1)`；`RouteCodec` 编解码 `chat/{id}?messageId=N`
  （不带该字段的既有形态、深链规则保持不变 → 向后兼容）。
- `entry/src/main/ets/pages/Index.ets`：`navigateToChatFromSearch` 把 `messageId` 带进路由；
  路由观察分支把 `messageId` 交给 `openChat(chatId, title, jumpTo)`；同一会话内的再次跳转走
  `requestChatJump`（按 `chatId:messageId` 去重——路由订阅每次栈变化都回调，否则会重复滚动）。
- `feature/chat/ChatCoordinator`：新增 `requestJumpToMessage(messageId)` 统一两条入口
  （装配层进会话 / 会话内结果点击）。投影忙（首屏/翻页在飞）时**排队**而不是放弃，等
  `syncFromProjection` 空闲时再拉围绕历史；已缓存直接回灌 `OnJumpToMessageReady`；消息不可达
  则放弃（不做无限重试）。原 `jumpToMessage` effect 改为复用该通道。
- `feature/chat/ChatPage`：跳转**独占优先**（命中目标即落位并 return，不再落入自动定位分支）；
  滚动时刻**重新解析下标**（`indexOfMessageId`）；新增 `jumpAnchorLock` 锚定锁抑制落位后的
  自动定位（用户手动滑动列表即释放）；搜索面板空关键词不再显示 `No results`，改为引导文案
  `Search messages in this chat`。

### 模拟器实测（`127.0.0.1:5555`，AArch64 / API 24，AI 代操作）
| 场景 | 关键证据 | 结果 |
|---|---|---|
| **全局搜索 `aaa` → 点消息结果进会话**（用户报的场景） | hilog：`navigate from search chatId=… messageId=26214400` → `chat jump requested` → `jump_to_message` → `jump_to_message_ok`；目标 `aaa` 行 [1322,1504] 中心 ≈1413 = 列表正中，更新的消息在其**下方** | ✅ 定位到历史中间（非末尾） |
| **会话内搜索唯一词 `foxiteu` → 点结果** | `chat_jump_scroll messageId=9437184 index=3 total=32`；目标行 [1097,1730] 中心 ≈1413，上方是更早的链接消息、下方是更新的 `hello_from_harmony` | ✅ 精确居中（index 3/32） |
| **会话内搜索 `aaa`（多条命中）→ 点结果** | `chat_jump_scroll messageId=29360128 index=19 total=32`，居中行即 `aaa` | ✅ |
| 面板空态 | 打开面板显示 `Search messages in this chat` | ✅ |
| 回归：点结果后按返回 | 返回落回会话消息视图（面板已收起） | ✅ |

> 排查备注：中途一度误判「跳转失败」，原因是把搜索结果里的 `dd.MM` 标签（`11.09`）当成了
> 「很久以前」——该会话 9月12日 无消息，所以 9月11日 那组之后直接跟 9月13日 分隔符，
> 看起来像落到了别处。用**唯一关键词**（`foxiteu`）复核后确认定位精确命中。

### 本次门禁
- `core_navigation` 单测 37 → **42**（新增 chat 路由 `messageId` 往返/编码/解析/非法类型/缺省 5 例）。
- `feature_chat` 单测 169 → **172**（新增 `ChatSearchJump.test.ets`：首屏在飞时排队、非法 id 忽略、destroy 后忽略）。
- 全量 19 模块单测 **930/930** PASS；design-token / architecture / codegen 静态守卫 0 违规；`assembleHap` BUILD SUCCESSFUL。

### 追加修复 2（同日，用户复测「搜索 aaa → 选 be hu 还是不跳」）

复测结论：**跳转本身是通的**（模拟器上用最新包按用户路径实测：`navigate from search … messageId=29360128`
→ `chat jump requested` → `jump_to_message` → `jump_to_message_ok` → `chat_jump_scroll index=19 total=32`，
目标 `aaa`(14:49) 行中心 ≈1413 = 列表正中）。但暴露了一个**真实体验缺陷**：

- **跳转后目标消息没有任何视觉标识**。be hu 这类短会话（32 条）里，跳转前后画面差别很小，
  用户根本看不出"跳到哪了"，主观上就等于"没跳"。首版 PROGRESS 写的是"定位并高亮"，
  实际只实现了定位——本次补齐高亮。
- 顺带把首屏锚点（`aboutToAppear` 里的未读/末尾定位）也纳入让位逻辑：从搜索进会话时
  它与跳转几乎同时发生，原先只有 `jumpAnchorLock`（跳转后才置位）挡不住它。

修复：
- `ChatPage` 新增 `highlightedMessageId`（@State）+ `highlightTarget()`：落位后目标行整行着色
  `T.colors.chatOutgoing`（浅色 `#FFD9F1FF` / 深色 `#FF1D3D52`，两套主题都是明显蓝色调），
  持续 `JUMP_HIGHLIGHT_MS = 4000ms` 后自动消失；用户手动滑动列表立即结束高亮。
  > 首版试过中性灰 `T.colors.surfaceVariant`（`#FFF0F0F0`）——实测在浅色主题上几乎看不出，
  > 用户依然反馈"看不出跳了"，故换成蓝色调并延长时长。
- 高亮态纳入 `messageRowKey`（第三个参数），保证 LazyForEach 只重绘该行。
- `autoScrollUnlessJumped` 增加判据：`jumpAnchorLock || uiState.jumpToMessageId > 0` 时一律
  不执行自动定位；`aboutToAppear` 的首屏锚点也改走该助手。

**用户第二轮反馈（附截图，圈出 be hu 14:22）："点这个还是不跳，上面那个 aaa 可以跳"** —— 逐条复现后确认：
**两条其实都跳**，只是**看不出来**。同一会话（be hu，仅 32 条消息）里两条命中仅相隔 3 条消息：

| 点击目标 | 日志 | 落位 | 画面变化 |
|---|---|---|---|
| be hu `aaa` **14:49**（messageId 29360128） | `chat_jump_scroll index=19 total=32` | 目标行中心 1413 = 列表中心 | 视窗从会话顶部移到 11:27 起 |
| be hu `aaa` **14:22**（messageId 26214400） | `chat_jump_scroll index=16 total=32` | 目标行 [1322,1504] 中心 1413 = 列表中心 | 视窗移到 10:47 起（与上一次仅差 3 行） |

即：两次跳转都生效且都居中，但短会话 + 相邻命中导致"跳了跟没跳一样"。
这正说明**没有视觉标识时用户无法判断**——蓝色高亮就是为了解决它。

实测证据（布局 dump 直接带背景色）：
| 检查 | 证据 | 结果 |
|---|---|---|
| 落位居中 | `chat_jump_scroll messageId=26214400 index=16 total=32`；目标行 [1322,1504]，中心 ≈1413 = 列表中心 | ✅ |
| 目标行高亮 | dump 中 `Column [0,1322][1256,1504] backgroundColor=#FFD9F1FF`（= `chatOutgoing`），同帧其它消息行均为 `#00000000` | ✅ |
| 高亮自动消失 | 超时后同一行恢复 `#00000000` | ✅ |

> 复现/取证提示：`uitest dumpLayout` 的 JSON 里带 `backgroundColor` 属性，可直接用颜色验证高亮；
> 但 dump 有时延，需在点击后 ~1.5s 抓（早于跳转完成会拍到跳转前画面）。

### 观察到的待跟进问题（不属本次修复范围）
- **长时间反复搜索后全局搜索返回 0 条**：连续多次改词搜索（`aaa`→`a`→`foxiteu`→`aaaaaa`→`aaa`）后，
  同样的 `aaa` 查询返回 `No results found for "aaa"`，杀进程重开后立即恢复正常（7 条）。
  怀疑是 TDLib `searchMessages` 的 flood 限制或 provider 把错误静默吞成空数组
  （`SearchCoordinator.searchMessages` 在 `decodeFoundMessages === null` 时返回 `[]` 且无日志），
  建议独立小包：给搜索失败加显式错误路径 + 节流，避免"看起来没结果"。归 **SEARCH-103**（待认领）。

### 追加修复 3（同日，**真正的用户可见根因**：快路径下跳转被 @Watch 时序吃掉）

用户澄清操作路径：**在会话列表页点 Search 行 → 全局搜索 `aaa` → 点结果**，进入会话后不定位。
抓设备日志后发现关键差异——同为"点了结果"，日志分成两种：

| 路径 | 日志 | 是否滚动 |
|---|---|---|
| 目标**不在**首屏缓存（需拉历史，约 100ms） | `jump_to_message` → `jump_to_message_ok` → `chat_jump_scroll` | ✅ 正常 |
| 目标**命中**首屏缓存（约 3ms 内跑完） | `jump_to_message_ok …,cached=true` → **再无下文** | ❌ **完全不滚动** |

```
13:44:53.206 navigate from search … messageId=26214400
13:44:53.210 jump_to_message_ok messageId=26214400,cached=true
（之后没有任何 chat_jump_scroll —— 界面从未滚动）
```

**根因**：目标命中首屏缓存时，`打开会话 → 首屏 getChatHistory 回包 → OnJumpToMessageReady`
整条链路可能在 **3ms 内**全部完成，比 ChatPage 首帧创建还早。ArkUI 的 `@Prop @Watch`
只在**组件创建之后**的属性变化上触发，因此这次 `jumpToMessageId: 0 → N` 的跃迁被整段跳过，
滚动逻辑从未执行；标记又一直挂着，用户看到的就是"点了完全没反应"。
此前我自己的验证恰好都命中"目标未缓存"的慢路径（页面已存在，Watch 正常触发），
所以一直没能复现——**这是本次排查的关键盲点**。

修复（`ChatPage`）：
- 抽出 `armJumpScroll(targetMessageId)` 统一落位逻辑（置锚定锁 → 延迟 80ms 居中滚动 →
  高亮 → 清标记；下标在滚动时刻重新解析）。
- `onUiStateChanged` 的跳转分支改调该助手（常规路径）。
- **`aboutToAppear` 补一次同样调用**（首帧路径）：若 `jumpToMessageId > 0` 且目标已在数组里，
  直接补跳并记 `chat_jump_from_first_frame`；目标尚未进数组则留给后续状态变更。

实测（用户原始路径，`cached=true` 快路径）：
| 点击目标 | 日志 | 落位 |
|---|---|---|
| be hu `aaa` **14:49**（29360128） | `jump_to_message_ok cached=true` → `chat_jump_from_first_frame` → `chat_jump_scroll index=17 total=30` → `chat_jump_highlight` | 目标行 [1316,1510] 中心 1413 = 列表中心 |
| be hu `aaa` **14:22**（26214400，用户截图圈出） | 同上 → `chat_jump_scroll index=14 total=30` | 目标行 [1322,1504] 中心 1413 = 列表中心 |

两条均：滚动生效 + 目标行蓝色高亮 `#FFD9F1FF`（dump 验色）。修复前同一路径**没有**
`chat_jump_scroll` 任何输出。

## 已知偏差 / 后续
- 搜索结果暂不接「上一条/下一条」逐条切换（Telegram X 有 prev/next 导航）；本包只回灌
  单跳定位，连续翻找可后续补 `from_message_id` 分页联动。
- `jumpable` 提示仅在结果缓存判断；跨很远历史的目标经 `loadHistoryAround` 拉取后立即可跳，
  无需用户二次确认。
- 深链（`tg://chat?…`）暂未开放 `messageId` 参数（只走应用内路由），需要时在
  `defaultDeepLinkRules` 白名单里补一行即可。
- 跳转后 `jumpAnchorLock` 会让「新消息自动跟随到底」暂停，直到用户手动滑动列表——
  这是刻意行为（对齐 Telegram：正在翻历史时不被新消息拽走）。

## 真机验证清单（交给用户）
- [x] 进入某会话 → 顶栏右侧出现 `🔍` 入口。（模拟器已验）
- [x] 点 `🔍` → 弹出覆盖搜索面板：顶部 `✕` + 输入框，空态引导文案。（模拟器已验）
- [x] 输入关键词 → 停顿 300ms 出现结果行（摘要 + 日期）。（模拟器已验）
- [x] 输入无命中词 → 显示 `No results`；未输入 → 引导文案。（模拟器已验）
- [x] 点某条结果 → 面板收起，列表滚动到**该消息**并居中。（模拟器已验，含 index/总数字证）
- [x] **全局搜索点消息结果 → 进会话并定位到该消息**。（本次修复，模拟器已验）
- [x] 点结果后按返回键 → 回到会话消息视图（而非会话列表）。（模拟器已验）
- [ ] 建议你在自己的账号上复测一次上面的「全局搜索 → 消息结果 → 定位」链路（数据量更大时更直观）。

