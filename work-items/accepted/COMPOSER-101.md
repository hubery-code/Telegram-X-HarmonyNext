# COMPOSER-101 实现报告：草稿持久化与列表草稿红色前缀（FEAT-CHAT-005）

## 结果
- 状态：Accepted
- 特性编号：FEAT-CHAT-005
- 执行者：AI-Agent-Antigravity (Main Agent)

## 实际修改

### 1. `core/domain` 领域层草稿管理与投影
- `core/domain/src/main/ets/chatlist/ChatListProjection.ets`：
  - 订阅并监听 TDLib 推送事件 `updateChatDraftMessage`；
  - 动态更新 `chat.draft_message` 并按 `chat.positions` 重新排序投影会话列表；
- `core/domain/src/main/ets/chat/MessageProjection.ets`：
  - 增加 `setChatDraftMessage(text, replyToMessageId)` 组装 `SetChatDraftMessage` 请求，支持草稿文本与回复目标；
  - 增加 `clearChatDraftMessage()` 清除当前草稿；
  - 增加 `getInitialDraft()` 与 `setOnDraftLoaded(listener)` 支持草稿就绪与增量推送通知；
  - 在 `handleUpdate` 监听 `updateChatDraftMessage` 并驱动 `draftListener`；
- `core/domain/src/test/` 单元测试：
  - `ChatListProjection.test.ets`：补充 `updateChatDraftMessage` 驱动与列表重排测试；
  - `MessageProjection.test.ets`：补充 `setChatDraftMessage` 组包、`clearChatDraftMessage` 清除及 `updateChatDraftMessage` 响应回灌测试。

### 2. `feature/chat_list` 会话列表草稿状态展示
- `feature/chat_list/src/main/ets/model/ChatListItem.ets`：
  - 扩展 `draftText: string | null = null` 属性；
- `feature/chat_list/src/main/ets/coordinator/ChatListCoordinator.ets`：
  - 在 `mapChatsToItems` 中解析 `chat.draft_message`，提取 `DraftMessageContentText` 规范化单行预览；
- `feature/chat_list/src/main/ets/pages/ChatListPage.ets`：
  - `chatRowKey` 引入 `draftText` 哈希，支持草稿增删时列表项即时差量重绘；
  - `ChatRow` 组件在存在草稿时，使用高亮加粗红色 `Draft: ` 前缀取代常规最后一条消息预览。

### 3. `feature/chat` 会话输入框草稿恢复与离开保存
- `feature/chat/src/main/ets/contract/ChatIntent.ets`：
  - 新增 `RestoreDraft(draftText, replyToMessageId)` intent；
- `feature/chat/src/main/ets/reducer/ChatReducer.ets`：
  - 处理 `restoreDraft`：输入框为空时恢复草稿文本；若携带 `replyToMessageId` 则安全组装 `ComposerReplyMode`；
  - `onMessagesLoaded` 中补充对恢复草稿回复模式的作者和内容摘要动态补全；
- `feature/chat/src/main/ets/coordinator/ChatCoordinator.ets`：
  - `start()` 注册 `projection.setOnDraftLoaded` 并检测 `getInitialDraft()`，自动回灌草稿；
  - 增加 `saveDraftNow()`，在 `destroy()` 退出离开会话时将输入框未发出内容安全保存至 TDLib；
  - 在 `sendTextMessage` 与 `handlePickAndSendPhoto` 成功发送时自动清理草稿；
- `feature/chat/src/test/ChatReducer.test.ets`：
  - 增加 4 组针对草稿恢复、防覆盖、未载入消息回复退化、晚到消息摘要补全的完整单元测试。

## 测试证据
- 全仓回归：`python3 tools/ci/test_all_modules.py` -> 19 模块 861/861 用例全绿 PASS；
- `core_domain` 模块测试：68 / 68 PASS；
- `feature_chat` 模块测试：134 / 134 PASS；
- `feature_chat_list` 模块测试：15 / 15 PASS；
- 架构门禁校验：`python3 tools/ci/check_architecture.py` -> 0 违规；
- Token 门禁校验：`python3 tools/ci/check_design_tokens.py` -> 0 未定义 token。

## 修改文件清单
1. `core/domain/src/main/ets/chatlist/ChatListProjection.ets`
2. `core/domain/src/main/ets/chat/MessageProjection.ets`
3. `core/domain/src/test/chatlist/ChatListProjection.test.ets`
4. `core/domain/src/test/chat/MessageProjection.test.ets`
5. `feature/chat_list/src/main/ets/model/ChatListItem.ets`
6. `feature/chat_list/src/main/ets/coordinator/ChatListCoordinator.ets`
7. `feature/chat_list/src/main/ets/pages/ChatListPage.ets`
8. `feature/chat/src/main/ets/contract/ChatIntent.ets`
9. `feature/chat/src/main/ets/Index.ets`
10. `feature/chat/src/main/ets/reducer/ChatReducer.ets`
11. `feature/chat/src/main/ets/coordinator/ChatCoordinator.ets`
12. `feature/chat/src/test/ChatReducer.test.ets`
13. `work-items/accepted/COMPOSER-101.md` [NEW]
