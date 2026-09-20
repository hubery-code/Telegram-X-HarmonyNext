# EMOJI-101 输入栏表情面板（FEAT-P2-005）

## 结果
- 状态：Accepted
- 特性编号：FEAT-P2-005 / EMOJI-101
- 执行者：AI-Agent-Antigravity
- 运行验证设备：HarmonyOS NEXT 模拟器（`127.0.0.1:5555`）

---

## 核心工作与修改清单

### 1. 契约层扩充 (`feature/chat/src/main/ets/contract`)
- **`ChatUiState.ets`**：
  - 导出 `DEFAULT_RECENT_EMOJIS: readonly string[]`（包含 👍, ❤️, 🔥, 🎉, 👏, 😂, 😍, 🤔, 🙏, 😊, 🥰, 😎, 🥳, 😭, ✨, 💯 等 16 个高频项）；
  - `ChatUiStateOptions` 与 `ChatUiState` 增加 `recentEmojis: readonly string[] = DEFAULT_RECENT_EMOJIS`；
  - 完善 `constructor`、`static initial()` 与 `copyWith()` 状态不可变副本构造。
- **`ChatIntent.ets`**：
  - 新增 `ClearRecentEmojis` 意图契约类；
  - 将 `ClearRecentEmojis` 纳入 `ChatIntent` 联合类型。
- **`feature/chat/src/main/ets/Index.ets`**：
  - 统一导出 `DEFAULT_RECENT_EMOJIS` 与 `ClearRecentEmojis`。

### 2. Reducer 状态流增强 (`feature/chat/src/main/ets/reducer/ChatReducer.ets`)
- **表情插入与置顶去重 (`case 'insertEmoji'`)**：
  - 输入框正文追加该表情；
  - 最近使用列表动态置顶：先过滤排除当前表情，再将该表情置于数组首位，且上限截断至 32 个；
- **清空最近使用记录 (`case 'clearRecentEmojis'`)**：
  - 将 `recentEmojis` 重置为空数组 `[]`；
- **返回层级消费链 (`case 'backToChatList'`)**：
  - 在退出聊天前优先拦截 `if (state.showEmojiBoard)`，当表情面板开启时仅收起面板（`showEmojiBoard: false`），不退出当前会话。

### 3. UI 交互与视觉对齐 (`feature/chat/src/main/ets/pages`)
- **`EmojiBoard.ets`**（对标 Telegram X `EmojiSection.java` 规格）：
  - 扩充 8 大分类：`🕒 Recent`, `😀 Smileys`, `🖐 Gestures`, `🐶 Animals`, `🍔 Food`, `🚗 Travel`, `💡 Objects`, `🏁 Flags`；
  - 顶部分类导航条支持横向滚动，选中项具有 28vp accent 高亮指示下划线；
  - 分类 0 具备双模渲染：
    - 有记录时展示 Section 标题行（"Recent" 标题 + "Clear" 按钮）及 8 列表情网格；
    - 空记录时展示居中时钟图标、"No Recent Emojis" 标题与副标题提示；
  - 底部控制栏保留 Emoji / Sticker / GIF 三 Tab 及右侧退格（Backspace）按键。
- **`ChatPage.ets`**：
  - 为 `EmojiBoard` 接入 `recentEmojis: this.uiState.recentEmojis.slice()` 与 `onClearRecent: () => this.dispatch(new ClearRecentEmojis())`；
  - `TextInput` 增加 `.onFocus` 监听，输入框聚焦调起系统软键盘时自动收起表情面板，避免遮挡冲突。

### 4. 自动化单元测试 (`feature/chat/src/test/ChatReducer.test.ets`)
- `insertEmoji_updatesRecentEmojis_prependsAndDedupes`：测试表情置顶插入并去重；
- `insertEmoji_capsRecentEmojisAt32`：测试最近使用记录上限截断至 32 项；
- `clearRecentEmojis_clearsRecentList`：测试清空最近使用记录；
- `backToChatList_closesEmojiBoard_whenOpen`：测试物理返回键优先收起表情面板。

---

## 验证与合规记录

### 1. 局部单元测试（严格遵守 AGENTS.md，未触发全量 CI）
- `feature_chat`：
  ```bash
  ./hvigorw test --mode module -p module=feature_chat@default --no-daemon
  # 结果：BUILD SUCCESSFUL
  ```

### 2. 秒级架构与代码生成防线
- `python3 tools/ci/check_architecture.py`：OK: 0 architectural boundary violations in core domain, reducers, and coordinators (100% Kit-free)
- `python3 tools/ci/check_codegen.py`：ALL CODEGEN CHECKS PASSED
- `python3 tools/ci/secret_scan.py`：OK: 0 secrets detected in tracked files

### 3. 模拟器端到端实测取证
- `emoji_01_chat_page.jpeg`：进入聊天页，展示底部输入栏笑脸按钮与消息气泡；
- `emoji_02_board_opened.jpeg`：点击笑脸按钮展开表情面板，8 大分类条（🕒 Recent 选中）、Recent 表情网格、底部栏与退格键完整呈现；
- `emoji_03_insert_party.jpeg`：点击 `🎉`，输入栏正文实时追加 `🎉`，Send 按钮亮起，Recent 列表中 `🎉` 动态置顶至第一项；
- `emoji_04_category_smileys.jpeg`：切换至 😀 Smileys 分类，高亮滑块移动，展示完整笑脸表情网格；
- `emoji_05_insert_angel.jpeg`：在笑脸分类中点击 `😇`，输入栏内容更新为 `🎉😇`；
- `emoji_06_recent_updated.jpeg`：切回 🕒 Recent 分类，`😇` 与 `🎉` 依序位于最近使用首两位；
- `emoji_07_backspace.jpeg`：点击右下角退格按钮，正文末尾 `😇` 被准确删除，保留 `🎉`；
- `emoji_08_clear_recent.jpeg`：点击 Recent 标题右侧 "Clear" 按钮，列表清空并显示 "No Recent Emojis" 优雅空态；
- `emoji_09_board_closed.jpeg`：点击输入框左侧键盘切换按钮，表情面板平滑收起，输入框保留内容并回到屏幕底栏。
