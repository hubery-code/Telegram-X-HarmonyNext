# MEDIA-104 实现报告：文件消息发送/下载与文件气泡渲染（FEAT-MEDIA-003）

## 结果
- 状态：Accepted
- 特性编号：FEAT-MEDIA-003
- 执行者：AI-Agent-Antigravity (Main Agent)

## 实际修改

### 1. `core/domain` 消息投影与底层文件消息发送契约
- `core/domain/src/main/ets/chat/MessageProjection.ets`：
  - 新增 `sendDocumentMessage(localPath: string, caption?: string, replyToMessageId?: number): Promise<Message>`；
  - 纯 ArkTS / Kit-free 实现，构建 TDLib 兼容的 `InputMessageDocument`、`InputDocument` 与 `InputFileLocal`；
  - 校验本地路径合法性，支持附带说明文本（caption）与消息引用（replyToMessageId）；
- `core/domain/src/test/chat/MessageProjection.test.ets`：
  - 新增 3 组针对文件消息发送投影的单元测试（完整参数包含回复与附言、空文件路径防护与边界参数校验）；
  - `core_domain` 模块单测达 67 / 67 PASS。

### 2. `feature/chat` 领域模型、意图与单向数据流（MVI）
- `feature/chat/src/main/ets/model/MediaAttachment.ets`：
  - 扩展文件元数据属性：`fileName: string`、`fileSize: number`、`mimeType: string`；
  - 提供纯函数工具方法 `formatFileSize(bytes: number): string`（支持 0 B, KB, MB, GB 精准换算与四舍五入）；
  - 更新 `copyWith` 与构造器入参，全面保持历史兼容；
- `feature/chat/src/main/ets/contract/ChatIntent.ets`：
  - 新增意图 `PickAndSendFile`（触发系统文件选择并发送文档消息）；
  - 新增意图 `CancelMediaUpload(messageId: number)`（取消并撤回上传中的文件消息）；
- `feature/chat/src/main/ets/contract/ChatEffect.ets`：
  - 新增副作用 `PickAndSendFileEffect(caption?: string, replyToMessageId?: number)`；
- `feature/chat/src/main/ets/reducer/ChatReducer.ets`：
  - 在 `reduce` 中增加对 `PickAndSendFile` 的处理：自动读取草稿文本作为文件附言，保留当前回复引用模式，发出 `PickAndSendFileEffect`；
  - 在 `reduce` 中增加对 `CancelMediaUpload` 的处理：产生 `DeleteMessagesEffect(chatId, [messageId], true)`，完成端到端撤回与清理；
- `feature/chat/src/main/ets/coordinator/ChatCoordinator.ets`：
  - 在 `resolveMediaAttachment` 中支持 `MessageDocument` 与 `Document` 类型解析；
  - 订阅本地/远程文件流与传输进度，动态更新文档下载/上传百分比；
  - 提供 `pickAndSendFile` 与 `cancelMediaDownload` 运行时方法；
- `feature/chat/src/main/ets/Index.ets`：
  - 导出 `PickAndSendFile`、`CancelMediaUpload`、`PickAndSendFileEffect` 与 `formatFileSize`。

### 3. `feature/chat` 交互组件与 DocumentBubble 视觉渲染
- `feature/chat/src/main/ets/pages/ChatPage.ets`：
  - 底部输入工具栏新增文件附件入口按钮 `📁`，点击分发 `PickAndSendFile`；
  - 在 `MessageBubble` 消息分发逻辑中增加文档类型分支，调用 `@Builder DocumentBubble(item, media)`；
  - 渲染左侧圆形控制按钮（根据状态展示：上传中/下载中显示 `LoadingProgress` 进度圈，点击上传中按钮分发 `CancelMediaUpload`；已下载完成展示 `📄` 文档图标；未下载展示 `⬇` 下载触发图标）；
  - 渲染右侧区域：文件名支持最大行数截断、副标题展示文件大小及实时下载/上传百分比进度；
  - 支持文件附言与引用消息联动布局；
  - 严格采用 Design Tokens（`T.colors.accent`、`T.colors.textOnAccent`、`T.radius.full`、`T.spacing.*` 等）；
  - 优化 `messageRowKey` 响应式指纹（加入 `uploadProgress`、`fileName` 与 `fileDownloaded`），确保异步文件状态平滑重绘。

### 4. 单元测试与测试套件接入
- `feature/chat/src/test/ChatFileSending.test.ets` [NEW]：
  - 覆盖文件选择并发送全生命周期、上传撤回意图验证、下载进度更新与异常捕获防护；
- `feature/chat/src/test/MediaAttachment.test.ets`：
  - 覆盖 `formatFileSize` 各数量级边界测试（0 B, 500 B, 1.5 KB, 10 MB, 2.5 GB）与不可变模型扩展测试；
- `feature/chat/src/test/List.test.ets`：
  - 注册新增单测文件；
  - `feature_chat` 模块单测达 139 / 139 PASS。

## 测试证据
- `core_domain` 模块测试：67 / 67 PASS；
- `feature_chat` 模块测试：139 / 139 PASS；
- 架构门禁校验：`python3 tools/ci/check_architecture.py` -> 0 违规；
- Token 门禁校验：`python3 tools/ci/check_design_tokens.py` -> 0 未定义 token；
- 自动化执行结果：`./hvigorw test -p module=core_domain@default,feature_chat@default --no-daemon` 全部 BUILD SUCCESSFUL。

## 修改文件清单
1. `core/domain/src/main/ets/chat/MessageProjection.ets`
2. `core/domain/src/test/chat/MessageProjection.test.ets`
3. `feature/chat/src/main/ets/model/MediaAttachment.ets`
4. `feature/chat/src/main/ets/contract/ChatIntent.ets`
5. `feature/chat/src/main/ets/contract/ChatEffect.ets`
6. `feature/chat/src/main/ets/reducer/ChatReducer.ets`
7. `feature/chat/src/main/ets/coordinator/ChatCoordinator.ets`
8. `feature/chat/src/main/ets/pages/ChatPage.ets`
9. `feature/chat/src/main/ets/Index.ets`
10. `feature/chat/src/test/ChatFileSending.test.ets` [NEW]
11. `feature/chat/src/test/MediaAttachment.test.ets`
12. `feature/chat/src/test/List.test.ets`
13. `work-items/accepted/MEDIA-104.md` [NEW]

## 自检确认
- [x] 未修改未授权目录（严格限定于 `core/domain/**`、`feature/chat/**` 及 `work-items/accepted/MEDIA-104.md`）
- [x] 未包含秘密或个人数据
- [x] 0 架构违规（check_architecture 0 违规）
- [x] 0 设计 token 违规（check_design_tokens 0 违规）
- [x] 未自行执行 git commit 或 git push（等待全仓联调完成统一提交）
