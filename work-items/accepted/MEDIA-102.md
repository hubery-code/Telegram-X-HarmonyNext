# MEDIA-102 实现报告：相册选图与发送图片消息（FEAT-MEDIA-001）

## 结果
- 状态：Accepted
- 特性编号：FEAT-MEDIA-001
- 执行者：AI-Agent-Antigravity (Main Agent)

## 业务背景与目标
- 用户在聊天界面点击附件按钮或相册入口，调起系统相册选择图片；
- 选图完成后自动将输入框文字作为图片说明（caption），保留引用上下文（reply_to_message_id）；
- 调用 TDLib `SendMessage(InputMessagePhoto)` 发送图片；
- 支持上传进度跟踪与上传状态展示；支持取消上传（`cancelMediaUpload`，底层调用撤回/删除）。

## 架构与核心实现

### 1. `platform/ports` 抽象契约与测试桩
- `platform/ports/src/main/ets/MediaPickerPort.ets`：
  - 定义纯契约接口 `MediaPickerPort`：
    - `pickPhoto(options?: PhotoPickerOptions): Promise<PhotoPickerResult>`；
    - `pickFile(options?: FilePickerOptions): Promise<FilePickerResult>`；
  - 100% Kit-free，隔绝系统底层 SDK；
- `platform/ports/src/main/ets/fakes/FakeMediaPicker.ets`：
  - 内存桩实现，支持可配置的 `nextPhotosToReturn` 与异常模拟，记录调用计数 `pickPhotoCalls`；
- `platform/ports/src/test/MediaPickerPort.test.ets`：
  - 新增 4 组用例验证 Fake 返回、多选限制与空选取逻辑。

### 2. `core/domain` 领域能力拓展
- `core/domain/src/main/ets/chat/MessageProjection.ets`：
  - 实现 `sendPhotoMessage(localPath, caption?, replyToMessageId?, width?, height?)`；
  - 构造 `SendMessage` 与 `InputMessagePhoto`（`InputFileLocal`、`FormattedText`），发送成功后返回 `Message` 对象；
- `core/domain/src/main/ets/file/FileRegistry.ets`：
  - 新增上传态查询函数：
    - `isUploading(fileId: number): boolean`
    - `isUploaded(fileId: number): boolean`
    - `getUploadProgress(fileId: number): number`（根据 `uploadedSize / expectedSize` 动态计算百分比）；
- `core/domain/src/test/`：
  - 补充 `MessageProjection.test.ets`（3 组图片发送组包与边界测试）与 `FileRegistry.test.ets`（上传进度与状态测试）。

### 3. `feature/chat` MVI 状态与 Coordinator 协调
- `feature/chat/src/main/ets/model/MediaAttachment.ets`：
  - 增加 `isUploading` 与 `uploadProgress` 字段，支持 `copyWith`；
- `feature/chat/src/main/ets/contract/ChatIntent.ets` & `ChatEffect.ets`：
  - 引入 `PickAndSendPhoto` intent 与 `PickAndSendPhotoEffect` effect；
- `feature/chat/src/main/ets/reducer/ChatReducer.ets`：
  - 处理 `pickAndSendPhoto`：将当前输入框内容作为 caption，保留 replyMode 上下文，派发 `PickAndSendPhotoEffect`；
- `feature/chat/src/main/ets/coordinator/ChatCoordinator.ets`：
  - 构造时接收注入的 `MediaPickerPort`（默认回退到 `FakeMediaPicker`，保证测试零配置）；
  - `pickAndSendPhoto()` / `handlePickAndSendPhoto()` 协调图库选取与 `MessageProjection.sendPhotoMessage` 调度；
  - `cancelMediaUpload(messageId)`：撤回并删除正在上传的消息；
  - `resolveMediaAttachment`：当消息附件文件处于上传状态时，自动提取本地文件路径并计算上传进度。
- `feature/chat/src/main/ets/pages/ChatPage.ets`：
  - 输入框左侧添加 `📎` 选图发送按钮，触发 `pickAndSendPhoto`；
  - `MediaBubble` 渲染组件支持上传中半透明遮罩与圆环进度百分比展示，以及支持加载本地路径图片。
- `feature/chat/src/test/`：
  - 新增 `ChatPhotoSending.test.ets`：包含选取发送流程、取消上传流程、用户取消选取 3 大完整用例；
  - 补充 Reducer 与 Model 测试。

### 4. `entry` 适配层装配
- `entry/src/main/ets/platform/HarmonyMediaPickerAdapter.ets`：
  - 基于 HarmonyOS `@kit.MediaLibraryKit` 的 `photoAccessHelper.PhotoViewPicker` 实现生产级相册选择；
  - 基于 `@kit.CoreFileKit` 实现文件选择；
  - 捕获取消与失败异常，返回规范的 `PhotoPickerResult`；
- `entry/src/main/ets/pages/Index.ets`：
  - 初始化 `HarmonyMediaPickerAdapter` 并通过 `ChatCoordinatorOptions` 注入给 `ChatCoordinator`。

## 验证与测试证据
- 模块测试全量通过：
  - `core_domain`: 64 / 64 PASS
  - `platform_ports`: 14 / 14 PASS
  - `feature_chat`: 130 / 130 PASS
- 门禁校验：
  - `python3 tools/ci/check_architecture.py` -> 0 架构违规（core/domain 与 feature/chat 保持 100% Kit-free）；
  - `python3 tools/ci/check_design_tokens.py` -> 0 未定义 token。

## 修改文件清单
1. `platform/ports/src/main/ets/MediaPickerPort.ets` [NEW]
2. `platform/ports/src/main/ets/fakes/FakeMediaPicker.ets` [NEW]
3. `platform/ports/src/main/ets/Index.ets`
4. `platform/ports/src/test/MediaPickerPort.test.ets` [NEW]
5. `platform/ports/src/test/List.test.ets`
6. `core/domain/src/main/ets/chat/MessageProjection.ets`
7. `core/domain/src/main/ets/file/FileRegistry.ets`
8. `core/domain/src/test/chat/MessageProjection.test.ets`
9. `core/domain/src/test/file/FileRegistry.test.ets`
10. `feature/chat/src/main/ets/model/MediaAttachment.ets`
11. `feature/chat/src/main/ets/contract/ChatIntent.ets`
12. `feature/chat/src/main/ets/contract/ChatEffect.ets`
13. `feature/chat/src/main/ets/reducer/ChatReducer.ets`
14. `feature/chat/src/main/ets/coordinator/ChatCoordinator.ets`
15. `feature/chat/src/main/ets/pages/ChatPage.ets`
16. `feature/chat/src/main/ets/Index.ets`
17. `feature/chat/src/test/MediaAttachment.test.ets`
18. `feature/chat/src/test/ChatReducer.test.ets`
19. `feature/chat/src/test/ChatPhotoSending.test.ets` [NEW]
20. `feature/chat/src/test/List.test.ets`
21. `entry/src/main/ets/platform/HarmonyMediaPickerAdapter.ets` [NEW]
22. `entry/src/main/ets/pages/Index.ets`
23. `work-items/accepted/MEDIA-102.md` [NEW]
