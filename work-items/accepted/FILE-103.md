# FILE-103 实现报告：传输失败重试/取消 UI 路径（FEAT-MEDIA-005）

## 结果
- 状态：Accepted
- 特性编号：FEAT-MEDIA-005
- 执行者：AI-Agent-Antigravity (Main Agent)

## 实际修改

### 1. 契约与领域状态机扩展
- `feature/chat/src/main/ets/contract/ChatIntent.ets`：
  - 新增 `CancelMediaDownload(readonly fileId: number)`（取消媒体/文件下载）；
  - 新增 `ResendFailedMessage(readonly messageId: number)`（重试发送失败的消息）；
  - 联合类型 `ChatIntent` 纳入两项新意图；
- `feature/chat/src/main/ets/contract/ChatEffect.ets`：
  - 新增 `CancelMediaDownloadEffect(readonly fileId: number)` 并纳入 `ChatEffect` 联合类型；
- `feature/chat/src/main/ets/contract/ChatUiState.ets`：
  - `MessageActionMenuState` 扩展 `readonly showResend: boolean = false`；
- `feature/chat/src/main/ets/reducer/ChatReducer.ets`：
  - 处理长按菜单加载（`onMessageActionMenuLoaded`）：当 `item.sendState === 'failed'` 时展开 `showResend: true` 与 `showDelete: true`，隐藏 `showReply: false`；
  - 处理 `resendFailedMessage`：收起菜单并产生 `ResendMessage(state.chatId, messageId)` 副作用；
  - 处理 `cancelMediaDownload`：产生 `CancelMediaDownloadEffect(fileId)` 副作用；
- `feature/chat/src/main/ets/coordinator/ChatCoordinator.ets`：
  - `executeEffect` 中处理 `cancelMediaDownload`：调度 `fileRegistry.cancelDownloadFile(fileId)`，清理 `requestedFileIds` 缓存并立即调用 `scheduleSyncFromProjection()` 促发 UI 及时重绘；
- `feature/chat/src/main/ets/Index.ets`：
  - 导出 `CancelMediaDownload`、`ResendFailedMessage` 与 `CancelMediaDownloadEffect`。

### 2. UI 渲染与交互闭环
- `feature/chat/src/main/ets/pages/ChatPage.ets`：
  - `DocumentBubble`：增加 `isFailed` 参数。失败态显示红底重试圆钮（`↻`）与 `Failed · Tap to retry`；下载中点击圆钮派发 `CancelMediaDownload(fileId)`；未下载点击 `⬇` 派发 `RequestMediaDownload(fileId)`；
  - `MediaBubble`：增加 `isFailed` 参数。失败态居中显示红底重试圆钮（`↻`）；上传中点击圆钮派发 `CancelMediaUpload(messageId)`；下载中点击圆钮派发 `CancelMediaDownload(fileId)`；外层 `onClick` 增加阻断守卫（上传中/下载中/未下载/失败态严格阻断，防止误打开全屏媒体查看器）；
  - `ActionMenuSheet`：当 `menu.showResend === true` 时在顶部置顶渲染 `Resend` 选项；
  - 严格采用 Design Tokens（`T.colors.destructive`、`T.colors.textOnAccent`、`T.radius.full`、`T.spacing.*` 等）。

### 3. 单元测试与端到端验证
- `feature/chat/src/test/ChatReducer.test.ets`：
  - 新增 4 组单元测试（`cancelMediaDownload` 派发 effect、失败消息菜单 `showResend` 与禁用 reply、`resendFailedMessage` 派发重试并关菜单、非失败消息忽略）；
- `feature/chat/src/test/ChatFileSending.test.ets`：
  - 新增 `dispatch CancelMediaDownload sends cancelDownloadFile to bridge` 端到端验证；
- `feature_chat` 模块测试：150 / 150 PASS；
- 全量 19 模块单测：896 / 896 PASS；
- 架构合规校验（Kit-free）：0 违规；
- Design Tokens 校验：0 违规；
- Secret Scan：0 泄露。
