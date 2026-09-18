# FOLDERS-101 会话分组标签栏与归档箱（FEAT-CHATLIST-003）

## 结果
- 状态：Accepted
- 特性编号：FEAT-CHATLIST-003 / FOLDERS-101
- 执行者：AI-Agent-Antigravity
- 运行验证设备：HarmonyOS NEXT 模拟器（`127.0.0.1:5555`）

---

## 核心工作与修改清单

### 1. 模型与契约层扩展 (`feature/chat_list`)
遵循 `ARCH-001` 与单一事实源规范，100% Kit-free 保持：
- **`ChatListItem.ets`**：
  - 导出 `ChatCategory = 'private' | 'group' | 'channel'`；
  - 实体类新增只读属性 `category: ChatCategory`（默认 `'private'`）；
  - 更新 `chatRowKey` 散列，增加 `category` 维度的差异化缓存标识。
- **`ChatListUiState.ets`**：
  - 定义 `ChatFolderTab` 接口：`{ readonly id: string; readonly title: string; readonly unreadCount: number; }`；
  - 提供 `DEFAULT_CHAT_FOLDERS` 预设集合（`All` / `Personal` / `Groups` / `Channels` / `Unread`）；
  - 提供纯函数 `filterChatsByFolder(items, folderId)`，准确区分私聊/密聊、群组、频道与未读过滤；
  - `ChatListUiState` 新增 `selectedFolderId: string = 'all'` 与 `folders: readonly ChatFolderTab[]`，通过 `copyWith()` 支持不可变派生。
- **`ChatListIntent.ets`**：
  - 新增 `SelectChatFolder(readonly folderId: string)`；
  - 扩展 `OnChatsLoaded` 接收可选 `folders?: readonly ChatFolderTab[]`；
  - 纳入 `ChatListIntent` 联合类型。
- **`ChatListReducer.ets`**：
  - 实现 `selectChatFolder`：若选中项未变返回原引用（纯函数幂等性），否则更新 `selectedFolderId`；
  - `onChatsLoaded` 回灌 `intent.folders`。
- **`ChatListCoordinator.ets`**：
  - 会话类型映射：精准判断 TDLib `chat.type_`，利用 `ChatTypeSupergroup.is_channel` 准确区分普通群组、超级群与广播频道；
  - 在 `syncFromProjection` 中动态汇算各 Tab 未读会话数，随 `OnChatsLoaded` 实时通知 UI。
- **`MockChatData.ets`**：
  - 在模拟数据构造中按比例分配 `private`、`group` 与 `channel` 类别，确保无网络测试数据完整。

### 2. UI 组件与交互实现 (`feature/chat_list/src/main/ets/pages/ChatListPage.ets`)
- **Folder 标签栏 (`FolderTabBar`)**：
  - 位于搜索框下方、会话列表上方；
  - 使用水平滚动 `Scroll` 容器，子项通过底部 3vp border 绘制高亮指示线，消除固定宽度撑满视口问题；
  - 当前选中项标题及未读角标胶囊（Unread Badge Pill）均呈现 Telegram X 主题色高亮。
- **手势横向切换 (`PanGesture Horizontal`)**：
  - 会话列表整体挂载水平 PanGesture（阈值 30vp）；
  - 向左滑动手势自动切换至下一 Tab，向右滑动手势自动切换至上一 Tab，平滑响应。
- **数据源动态联动**：
  - `getFilteredItems()` 结合 `filterChatsByFolder` 动态驱动 `LazyForEach` 局部刷新。
- **归档箱入口约束与归档视图**：
  - `ArchivedChatsRow` 严格限制在 `uiState.listKind === 'main' && uiState.selectedFolderId === 'all'` 时显示；
  - 归档列表视图中隐藏 `FolderTabBar`，顶栏呈现返回按钮与 "Archived Chats" 标题。
- **分类空状态视图 (`FolderEmptyView`)**：
  - 各分类无匹配会话时，呈现定制矢量图标、分类标题与指引文案。

### 3. 单元测试 (`feature/chat_list/src/test/ChatListReducer.test.ets`)
- 新增 4 组针对 Tab 切换、幂等性、自定义 folders 回灌及纯函数过滤的断言用例；
- 运行 `./hvigorw test --mode module -p module=feature_chat_list@default --no-daemon`，全部用例通过（`BUILD SUCCESSFUL in 24 s 770 ms`）。

### 4. 架构与合规验证
- `python3 tools/ci/check_architecture.py`：0 违规，Kit-free 100%；
- `python3 tools/ci/check_codegen.py`：ALL CODEGEN CHECKS PASSED；
- `python3 tools/ci/secret_scan.py`：0 secrets detected；
- 遵循 `AGENTS.md`：未触发全量 CI，仅对受影响模块运行快速测试与静态扫描。
