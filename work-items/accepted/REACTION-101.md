# REACTION-101 消息表情回应（FEAT-P2-001）

## 结果
- 状态：Accepted
- 特性编号：FEAT-P2-001 / REACTION-101
- 执行者：AI-Agent-Antigravity
- 运行验证设备：HarmonyOS NEXT 模拟器（`127.0.0.1:5555`）

---

## 核心工作与修改清单

### 1. 领域模型与事件流接入 (`core/domain`)
- **`MessageProjection.ets`**：
  - 引入 `UpdateMessageInteractionInfo`；
  - 在 `handleUpdate(update: TdUpdate)` 中补充 `updateMessageInteractionInfo` 分支；
  - 当 `interactionUpdate.chat_id === this.chatId` 时，通过 `messagesById` 获取内存中的 `Message`，增量刷新 `existing.interaction_info = interactionUpdate.interaction_info`，并调用 `this.notifyStateChanged()` 实时通知上层状态；
  - 维持 `addMessageReaction` 与 `removeMessageReaction` 完整可用，100% Kit-free。

### 2. 状态契约与 Reducer 修复 (`feature/chat`)
- **`ChatUiState.ets`**：
  - `MessageActionMenuState` 扩充 `availableReactions: string[]`（默认 `['👍', '❤️', '🔥', '🎉', '👏', '😂']`）与 `chosenReactions: string[]`（默认空数组）；
- **`ChatReducer.ets`**：
  - **长按菜单已选表情提取**：在 `onMessageActionMenuRequested` 中，读取目标消息 `item.reactionChips.filter(c => c.isChosen).map(c => c.emoji)` 注入 `chosenReactions`；
  - **反选计数归零清理**：修复反选导致表情计数降为 0 时残留空 Chip 的缺陷；在 `toggleMessageReaction` 中执行 `.filter((chip: ReactionChip) => chip.count > 0)`，计数为 0 的 chip 立即彻底移出消息气泡；
  - **同步菜单状态**：若菜单当前处于展开态，同步更新 `state.actionMenu.chosenReactions`。

### 3. UI 交互与视觉反馈 (`feature/chat/src/main/ets/pages/ChatPage.ets`)
- **ActionMenuSheet 快捷表情栏**：
  - 动态使用 `menu.availableReactions` 驱动渲染；
  - 当前消息中已被自己点选的表情呈现 2vp accent 高亮边框与主题色指示；
  - 点击表情分发 `ToggleMessageReaction` 并自动关闭菜单；
- **气泡底部 Reaction Chips 胶囊**：
  - 选中态呈现 `T.colors.accent` 背景与高对比白色文字；未选态呈现 `T.colors.surfaceVariant`；
  - 点击任意 Reaction Chip 即可直接切换反应，计数与高亮即时联动；
  - 反选降为 0 时胶囊无缝消失。

### 4. 自动化单元测试
- **`core/domain/src/test/chat/MessageProjection.test.ets`**：
  - 新增 `updateMessageInteractionInfo_updatesInteractionInfoAndNotifiesState` 测试用例，断言 TDLib 增量推送到达时消息 `interaction_info` 成功覆盖并派发状态通知；
- **`feature/chat/src/test/ChatReducer.test.ets`**：
  - 新增 `toggleMessageReaction_countDropsToZero_removesChipFromList` 测试用例；
  - 新增 `toggleMessageReaction_syncsActionMenuChosenReactions` 测试用例；
  - 新增 `onMessageActionMenuLoaded_populatesChosenReactionsFromMessage` 测试用例。

---

## 验证与合规记录

### 1. 局部单元测试（严格遵守 AGENTS.md，未触发全量 CI）
- `core_domain`：
  ```bash
  ./hvigorw test --mode module -p module=core_domain@default --no-daemon
  # 结果：BUILD SUCCESSFUL in 29 s 15 ms
  ```
- `feature_chat`：
  ```bash
  ./hvigorw test --mode module -p module=feature_chat@default --no-daemon
  # 结果：BUILD SUCCESSFUL in 39 s 770 ms
  ```

### 2. 秒级架构与代码生成防线
- `python3 tools/ci/check_architecture.py`：OK: 0 architectural boundary violations in core domain, reducers, and coordinators
- `python3 tools/ci/check_codegen.py`：ALL CODEGEN CHECKS PASSED
- `python3 tools/ci/secret_scan.py`：OK: 0 secrets detected in tracked files

### 3. 模拟器端到端实测取证
- `reaction_01_chat_page.jpeg`：进入聊天页，展示气泡底部既有反应胶囊 `👍 5` 与已选高亮 `🔥 3`；
- `reaction_02_action_menu.jpeg`：长按消息呼出菜单，顶部快捷反应栏精准显示 `🔥` 带有 accent 选中指示环；
- `reaction_03_unselected_fire.jpeg`：点击已选 `🔥`，菜单关闭，气泡底部 `🔥` 计数减为 2 且高亮褪去变为未选灰底；
- `reaction_04_chip_reselected.jpeg`：点击气泡底部 `🔥 2` 胶囊，直接反转状态，计数恢复为 3 且高亮恢复；
- `reaction_05_party_added.jpeg`：呼出菜单点选新表情 `🎉`，气泡底部即时增加 `🎉 1` 高亮胶囊；
- `reaction_06_zero_count_removed.jpeg`：再次点击 `🎉 1` 取消点赞，计数降为 0，胶囊直接消失，不留 0 计数空 Chip。
