# MEDIA-105 实现报告：视频消息上传/下载（FEAT-MEDIA-002）

> 状态：**Implementing → Verifying**（实现完成、单测/构建/模拟器入口已验证；真机/含视频素材设备上的「选择→缩略图→上传进度→发送」整链待补验）
> 日期：2026-09-21　执行：主会话（DSH）

## 结果

**FEAT-MEDIA-002 的缺口只在「发送侧」。** 动手前先做了现状核对，避免重复实现：

| 能力 | 位置 | 现状（本工作包之前） |
|---|---|---|
| 接收侧：解析 `messageVideo` → 缩略图优先下载（priority 2）、≤10MB 自动下载、宽高/时长/剧透 | `ChatCoordinator.resolveMediaAttachment`（`messageVideo` 分支） | **已完整** |
| 接收侧 UI：封面/首帧、下载环（可取消）、下载钮、播放钮、右下角时长角标 | `ChatPage.MediaBubble`（`kind === 'video'`） | **已完整** |
| 接收侧端到端 | MEDIA-106（2026-09-11 Accepted） | **已交付** |
| **发送侧**：选视频、元数据、缩略图、`InputMessageVideo`、上传进度 | — | **全空白**（`MediaPickerPort` 只有 `pickPhoto`/`pickFile`；`core/domain` 无任何 video 代码） |

因此本包只补发送侧，复用接收侧既有渲染，不重写。

## 实际修改

### 1. 端口契约（platform/ports）

`MediaPickerPort.ets`
- 新增 `pickVideo(maxSelectNumber?)`；新增实现者必须补齐（仓库内仅 `FakeMediaPicker` 与 `HarmonyMediaPickerAdapter` 两处，均已在本次补齐）。
- `PickedMedia` 扩展 6 个可选字段：`duration` / `width` / `height` / `thumbnailPath` / `thumbnailWidth` / `thumbnailHeight`。
  刻意把 `thumbnailWidth/Height`（**缩略图**尺寸）与 `width/height`（**视频**尺寸）分开——TDLib `inputThumbnail.width/height` 要的是前者，混用会让 TDLib 拒收。

`fakes/FakeMediaPicker.ets`：补 `pickVideo` / `nextVideosToReturn` / `setVideosToReturn` / `pickVideoCalls`，`reset()` 一并复位。

### 2. 领域层（core/domain）

`MessageProjection.sendVideoMessage(localPath, caption?, replyToMessageId, durationSec, width, height, thumbnailPath?, thumbnailWidth, thumbnailHeight)`
- 组 `InputMessageVideo` → `InputVideo`：`video = InputFileLocal(沙箱物理路径)`，可选 `InputThumbnail`（`InputFileLocal` + 宽高）。
- `supports_streaming = true`（对齐 TGX；接收端可边下边播）。
- **0 值不覆盖**：`duration/width/height` 为 0 时不写入 DTO，交给 TDLib 自行探测，避免用假 0 盖掉服务端可推断的真实值。
- 空路径判 `parameter/missing` 且不发请求（与 `sendPhotoMessage`/`sendDocumentMessage` 同构）。
- `inputThumbnail` 只接受真文件、不支持按 `file_id` 复用（TDLib 文档），故传本地物理路径。

### 3. MVI 三层（feature/chat）

- `ChatIntent.PickAndSendVideo` + 联合成员；`ChatEffect.PickAndSendVideoEffect` + 联合成员；`Index.ets` 导出。
- `ChatReducer`：`pickAndSendVideo` 分支与选图/选文件同构——带出回复目标与当前草稿作为 caption，并收起附件面板。
- `ChatCoordinator`：
  - `pickAndSendVideo()` 公开入口；`pickAndSendVideoEffect` 分派；`handlePickAndSendVideo()` 实现。
  - 缩略图登记进新增的 `pendingVideoThumbnails: Map<视频沙箱路径, 本地缩略图路径>`。
  - **补上视频分支缺失的上传态**：`resolveMediaAttachment` 的 `messageVideo` 分支此前只算下载态，没有 `isUploading`/`uploadProgress`，也没订阅上传进度（图片分支有）。已按图片分支同构补齐，并在上传完成时清掉本地缩略图缓存、让位给服务端官方缩略图。
  - **出站本地缩略图回退**：服务端缩略图就绪前 `messageVideo.video.thumbnail` 一直是 null，气泡会退化成「Video 首帧占位」；现在用发送前本地抽的首帧顶上，实现「缩略图先展示」在发送侧也成立。
  - 出站 `localPath` 兜底：注册表未收录时直接取 `file.local.path`，保证气泡立刻有本地源可渲染。

### 4. UI（feature/chat）

- `ChatPage.AttachmentMenuSheet`：在 Gallery 与 File 之间新增 **Video** 入口（此前 COMPOSER-102 只有 Gallery/File）。
- `ChatPage.MediaBubble`（`kind === 'video'`）：新增**上传态分支并置于最前**。这是必须的——出站视频的本地文件天然 `isDownloaded = true`，若沿用原有「先判 isDownloaded」的顺序会直接显示播放钮，上传进度永远不可见。上传中显示进度环 + 百分比 + 点击取消（`CancelMediaUpload`）。
- 新增图标 `ic_video.svg`，按既有惯例在 `feature/chat` 与 `entry` 两个资源目录各放一份（`ic_photo`/`ic_file` 同为双份）。

### 5. 平台适配器（entry）

`HarmonyMediaPickerAdapter.pickVideo` + `enrichVideo`
- `PhotoViewPicker` + `PhotoViewMIMETypes.VIDEO_TYPE` 选视频，虚拟 URI → 沙箱物理路径复用 FIX-002 的 `copyUriToCache`（零拷贝 fd）。
- `enrichVideo` 在**适配器层**补齐元数据与缩略图，业务层保持 Kit-free（ARCH-001）：
  - `media.createAVMetadataExtractor()` 读 `duration` / `videoWidth` / `videoHeight`（均为字符串，解析失败即留空）；
  - `media.createAVImageGenerator()` 的 `fetchFrameByTime(0, AV_IMAGE_QUERY_CLOSEST_SYNC, params)` 抽首帧；
  - `image.createImagePacker().packToFile(pixelMap, fd, {format:'image/jpeg', quality:80})` 落盘。
- 取帧尺寸按已知宽高**等比**缩到长边 ≤320 后传 `PixelMapParams`，避免直接用 320×320 拉伸画面；宽高未知时传 0/0（按 `PixelMapParams` 语义即为不缩放、返回原始分辨率）。
- **全程尽力而为**：元数据或抽帧任一步失败只记 `hilog` 并把对应字段留空，返回已拿到的部分，绝不抛给调用方——模拟器缺编解码器时发送不被阻断，气泡退化为首帧占位。

## 验证与证据

### 单元测试：427/427 PASS（0 Failure / 0 Error）

| 模块 | 用例数 | 结果 | 本次新增 |
|---|---|---|---|
| platform_ports | 47 | 全绿 | +3（`pickVideo` 回传+上限、拒绝、`reset` 复位视频态） |
| core_domain | 109 | 全绿 | +3（`inputMessageVideo`+`inputThumbnail` 线格式、空路径拒绝、最小参数不覆盖 0 值） |
| feature_chat | 242 | 全绿 | +2（`pickAndSendVideo` 收起面板、携带 caption/reply 目标） |
| entry | 29 | 全绿 | 0（适配器编译经由本模块与签名构建覆盖） |
| **合计** | **427** | **427 PASS** | +8 |

新增用例已确认实际执行（按 `test_result.txt` 中 `test=` 名称逐条核对，非仅看构建结论）。
领域层用例断言的是**真实 TDLib wire 形状**：`inputMessageVideo` → `inputVideo`（duration/width/height/`supports_streaming`）→ `inputFileLocal.path`，以及 `inputThumbnail` 的 width/height 与嵌套 `inputFileLocal`。

### 静态守卫：三道全绿

- `check_architecture.py`：0 违规（业务层与 reducer 仍 100% Kit-free——AVImageGenerator/AVMetadataExtractor 全在 entry 适配器内）
- `check_codegen.py`：DTO/union 与 `schema.ir.json` 字节一致（classes=3205 / unions=743）
- `check_design_tokens.py`：0 个未定义 token

### 构建：签名 HAP BUILD SUCCESSFUL

`./tools/ci/build-signed.sh debug` → `entry-default-signed.hap`（55.0 MB）。
适配器有 3 条 `The system capacity of this api 'media' is not supported on all devices` 告警（`createAVMetadataExtractor` / `createAVImageGenerator` / `fetchFrameByTime`），属 syscap 跨设备类型提示，**与既有 `HarmonyAudioPlayerAdapter` / `HarmonyAudioRecorderAdapter` 同类告警一致**，非本次回归。

### 模拟器实测（127.0.0.1:5555，登录态真实账号）

| # | 场景 | 操作 | 实测现象 | 截图 |
|---|---|---|---|---|
| 1 | 启动 | force-stop + `aa start` | 会话列表正常，登录态完好 | `00_launch.jpeg` |
| 2 | 进会话 | 点 `be hu` | 聊天页正常（置顶条/链接预览/反应/GIF/贴纸消息齐全） | `01_chat.jpeg` |
| 3 | **附件面板三入口** | 点 📎 | 面板渲染 **Gallery / Video / File** 三项，`ic_video` 摄像机图标正确上色 | `02_attach_menu.jpeg` |
| 4 | **视频选择器 + 类型过滤** | 点 Video | 系统相册以 **「所有视频」** 标签打开（`VIDEO_TYPE` 生效），底部提示「仅可访问所选视频」 | `03_video_picker.jpeg` |
| 5 | **取消选择** | 系统返回 | 选择器关闭 → 回到聊天页 → 附件面板收起 → 会话内容无变化 → 进程存活、无 `pick_video_error`、未发出任何消息 | `06_cancel_back.jpeg` |

场景 4 同时证明了「点 Video 确实派发到 `PickAndSendVideo` → 协调器调用 `mediaPickerPort.pickVideo`」——只有 `pickVideo` 会打开带视频过滤的系统选择器。

### 未验证项（明确登记）

**「选到真实视频 → 本地缩略图先展示 → 上传进度 → 发送成功」整链未在模拟器跑通**，原因是**该模拟器镜像相册内没有任何视频素材**：

- 系统选择器以「所有视频」打开后为空，只有「拍摄」瓦片；
- 点「拍摄」瓦片无任何响应（该瓦片在本镜像不可用），因此无法就地录制素材；
- 相册原始目录 `/storage/media/100/local/files/{Photo,Videos}` 对 shell 为 Permission denied（SELinux），无法从宿主注入素材；
- 同一现象连续三次截图字节完全一致，确认画面未被其它操作干扰。

另外：日志中出现的 `PickerUIExtensionAbility` / `PickerSheetContent: State variable 'isShow' has changed during render` 报错来自**系统相册选择器自身**的实现，与本工程代码无关，登记为环境侧已知噪声。

补齐该链需要：一台相册内有视频的设备（真机或已注入视频的模拟器），按下方清单逐条勾选即可。

## 联调追加：2026-09-21 主人实测（含一处真实缺陷修复）

主人实测「视频上传」后给出截图，反馈气泡形态与预期不符。**先定性，再改代码。**

### 定性：本次发送走的是「文件」入口，不是「视频」入口

hilog 中的一对人证（同一秒内）：

```
09-21 18:38:20.818 HarmonyMediaPickerAdapter: copied uri=file://docs/storage/Users/currentUser/Download/com.huawei.hmos.browser/mda-sfu7agt3ezntdrd8.mp4
                          → destPath=.../cache/uploads/1789987100759_8836_mda-sfu7agt3ezntdrd8.mp4, size=29872738
09-21 18:38:20.849 ChatCoordinator: send_document_message_ok chatId=6846163203
```

`send_document_message_ok` 在**生产代码中只有一个调用点**——`ChatCoordinator.ets:3129`，位于 `handlePickAndSendFile` 内（`sendVideoMessage` 同样只有一处调用点：3187，位于 `handlePickAndSendVideo`）。因此本次发送链路确定为：

```
附件面板「文件」→ pickFile(DocumentViewPicker) → sendDocumentMessage → InputMessageDocument
→ messageDocument → ChatPage 走 DocumentBubble
```

**这是设计内的行为，与 Telegram 一致**：走「文件」的媒体一律按文档发送。截图中的蓝色圆形图标正是 `DocumentBubble` 的上传态（`LoadingProgress` + `accent` 底色），副标题 `Uploading 46%` 出自 `documentSubtitle`。

**为什么没能走「视频」入口**：该 mp4 是浏览器下载物，落在**文件区** `/storage/media/100/local/files/Docs/Download/com.huawei.hmos.browser/`，不在相册媒体库里。而「视频」入口走 `PhotoViewPicker` + `VIDEO_TYPE`，只能看见媒体库内的视频。同一原因也解释了 MEDIA-105 首轮验证时相册为空的阻塞——两次是同一个环境限制。媒体库目录对 shell 为 SELinux 拒绝，`mediatool` 该镜像版本又不提供导入子命令，故无法从宿主注入素材。

### 缺陷与修复：沙箱缓存名泄漏到气泡标题

截图里标题显示 `1789987100759_8836_…`，这是 `copyUriToCache` 的**内部缓存文件名**，不应出现在 UI 上。

- **根因**：TDLib 的 `inputDocument` 与 `inputVideo` **都没有 `file_name` 字段**（已核对 `td_api_generated` DTO：`InputDocument{document, thumbnail, disable_content_type_detection}`；`InputVideo{video, thumbnail, cover, start_timestamp, added_sticker_file_ids, duration, width, height, supports_streaming}`）。它是拿 `InputFileLocal` 路径的 **basename** 反推 `file_name` 的。而原实现在文件名上拼了 `${Date.now()}_${rand}_` 前缀，于是这个前缀被 TDLib 当成真名回灌，直接显示到气泡标题。
- **修复**（根因处，非显示层打补丁）：唯一性改由**父目录**承担，最后一段保留原始文件名——
  `.../cache/uploads/1789987100759_8836/mda-sfu7agt3ezntdrd8.mp4`
  这样既保证不重名，`document.file_name` / `video.file_name` 又都恢复成用户看到的原名。文件见 `entry/src/main/ets/platform/HarmonyMediaPickerAdapter.ets`（`copyUriToCache`）。
- **影响面**：文档气泡标题（本次截图）、视频气泡的 `file_name`（同为 basename 推导）一并修正；图片不受影响（`messagePhoto` 不展示文件名）。
- **注意**：修复只对**新发送**生效。TDLib 已落库的旧消息 `file_name` 仍是带前缀的旧值，属历史数据，不做回改。

### 本次联调未覆盖

「视频」入口的**整链**仍未跑通（选到真实视频 → 缩略图先展示 → 上传进度 → 发送成功），原因同上：此设备相册内无视频素材。因此 MEDIA-105 状态保持 **Verifying**，验证清单见文末。

## 环境发现：模拟器不接受签名 HAP 替换安装

本次踩到一个**会持续影响后续所有模拟器验证**的坑，值得单独记录：

- 设备上已装的 `org.telegram.x.harmony` 是**未签名**安装的（`bm dump` 显示 `appSignType: "none"`、`appId` 开发者后缀为空）。
- 因此 `entry-default-signed.hap` 无论用 `hdc install` 还是 `hdc install -r`，都会被拒：
  `error: failed to install bundle. code:9568332 error: install sign info inconsistent`。
- **正确做法**：推送 `entry-default-unsigned.hap` 后用设备端 `bm` 替换安装——

  ```
  hdc file send entry/build/default/outputs/default/entry-default-unsigned.hap /data/local/tmp/tgx.hap
  hdc shell "bm install -r -p /data/local/tmp/tgx.hap"
  ```

  实测 `install bundle successfully.`，且**应用数据（含登录态）完整保留**（重启后会话列表与账号仍在），无需重新走短信验证码登录。
- 本次若按签名包路径直接 `uninstall + install`，会把登录态清掉且无法自行恢复（需要主人的短信验证码），故该结论对后续验证很关键。

另：`tools/ci/resolve-toolchain.sh` 是 **bash 脚本**，当前 shell 为 zsh 时 `source` 会因 `BASH_SOURCE` 未定义而提前退出、环境变量不导出。需以 `bash -c 'source tools/ci/resolve-toolchain.sh && ./hvigorw ...'` 方式调用。

## 文件清单

**新增**
- `feature/chat/src/main/resources/base/media/ic_video.svg`
- `entry/src/main/resources/base/media/ic_video.svg`

**修改**
- `platform/ports/src/main/ets/MediaPickerPort.ets`
- `platform/ports/src/main/ets/fakes/FakeMediaPicker.ets`
- `platform/ports/src/test/MediaPickerPort.test.ets`
- `core/domain/src/main/ets/chat/MessageProjection.ets`
- `core/domain/src/test/chat/MessageProjection.test.ets`
- `feature/chat/src/main/ets/contract/ChatIntent.ets`
- `feature/chat/src/main/ets/contract/ChatEffect.ets`
- `feature/chat/src/main/ets/reducer/ChatReducer.ets`
- `feature/chat/src/main/ets/coordinator/ChatCoordinator.ets`
- `feature/chat/src/main/ets/pages/ChatPage.ets`
- `feature/chat/src/main/ets/Index.ets`
- `feature/chat/src/test/ChatReducer.test.ets`
- `entry/src/main/ets/platform/HarmonyMediaPickerAdapter.ets`
- `PROGRESS.md`、`docs/product/FEATURE_MATRIX.md`（含治理文档漂移修正）

## 待主人勾选的验证清单（需含视频素材的设备）

| # | 操作步骤 | 预期现象 | ☐ |
|---|---|---|---|
| 1 | 进任一私聊/群聊 → 点 📎 | 弹出 Attach 面板，含 Gallery / Video / File 三项 | ☐ |
| 2 | 点 Video | 系统相册以「所有视频」打开，且**只列出视频**（无图片） | ☐ |
| 3 | 选一段视频 | 聊天页立即出现视频气泡，**缩略图即刻可见**（非黑块、非空白首帧） | ☐ |
| 4 | 观察气泡 | 中央出现上传进度环 + 百分比；右下角显示时长角标（如 `0:12`） | ☐ |
| 5 | 点进度环 | 该消息被撤回，不留半成品 | ☐ |
| 6 | 对端（另一账号）查看 | 收到视频消息，**未点开即可见缩略图**，可播放 | ☐ |
| 7 | 断网后重发一条视频 | 气泡转失败态；点击失败钮 → 菜单出现 Resend；Resend 后能成功 | ☐ |
| 8 | 发送时带输入框文字 | 文字作为 caption 附在视频下（非独立文本消息） | ☐ |
| 9 | 先回复某条消息再发视频 | 视频气泡内嵌回复引用块，指向被回复消息 | ☐ |

## 联调追加 2：气泡几何缺陷修复（2026-09-21 晚）

主人在真机实测截图（红框标注）报三处现象，排查后确认**同一根因**：

1. 文档气泡左侧圆形图标「被截取了一截」；
2. 视频气泡的上传进度圈「没有居中」，且进度条要等一会才出现；
3. 上传时界面「一闪一闪」。

### 根因

气泡容器（`ChatRow` 里那个 `Column`）带 `padding({ left/right: spacing.md })`，
但宽度只由 `constraintSize({ maxWidth: '78%' })` 限制——**是百分比、不是确定值**。
当内容比内容区更宽时，ArkUI 按「边框宽 − 右内边距」给子节点算可用宽度，
再按 `alignItems(HorizontalAlign.End)` 右对齐摆放：子节点整体**向左溢出 `spacing.md`**，
被容器的 `.clip(true)` 一刀切掉。

对 360vp 屏（模拟器密度 3.4889）实测 uinode 树：

| 节点 | 缺陷态 | 正确值 |
|---|---|---|
| 气泡容器 | 892px = 255.7vp（78% × 328） | — |
| 内容区（应） | 808px = 231.7vp | — |
| 文档气泡内容行 `Row` | **850px，左边缘 308px** | 809px，左边缘 350px |
| 44vp 图标 `Stack` | **108×154px（椭圆）** | 154×154px |
| 图标内白色箭头 `Image` | 66×70 @ x308（贴容器左缘） | 70×70 且居中于圆心 |
| 视频卡片 `Stack` | **840px，左边缘 318px** | 809px，左边缘 350px |
| 视频遮罩圆（56vp） | 圆心 738 ≠ 气泡中心 754 | 圆心 == 气泡中心 |
| 语音气泡播放钮（40vp） | **108×154px（椭圆）** | 140×140px |

三个放大因素：
- `mediaCardWidth()` **硬编码 240vp** > 内容区 231.7vp；
- 文档/语音/音频行的文字列带 `layoutWeight(1)`，在过度约束的 `Row` 里**先占满自己的理想宽度**
  （长文件名可达 200vp），反过来把定宽图标挤到剩余空间——44vp → 31vp；
- `Row` 的 `constraintSize({ maxWidth: 260 })` 也没扣掉气泡的左右内边距。

### 修复

| 改动 | 位置 |
|---|---|
| 新增 `contentMaxVp()`：气泡内容区宽度上限（屏宽 − 2×screenInset，×78%，再 − 2×md） | `ChatPage.ets` |
| 新增 `rowTextMaxVp(iconBox, iconGap)`：横排文字列宽度上限 | `ChatPage.ets` |
| `mediaCardWidth/Height` 收敛到 `mediaCardBaseVp() = min(240, contentMaxVp())`，宽高比以 base 为基准 | `ChatPage.ets` |
| `DocumentBubble` / `VoiceNoteBubble` / `AudioBubble`：`Row.maxWidth` 改 `contentMaxVp()`；文字列加 `constraintSize({ maxWidth })`；定宽圆钮加 `flexShrink(0)` + 锁定 `constraintSize` | `ChatPage.ets` |
| 上传进度：视频/图片上传态判据只留 `isUploading`（原先还要求 `uploadProgress < 1`），百分比不再等首字节 | `ChatPage.ets` |
| **闪烁**：`MessageListDataSource.setItems(items, keys)` 改为**按行签名差分**，长度不变时只对变化的行发 `onDataChange`，不再无脑 `onDataReloaded()` | `ChatPage.ets` |
| 行签名真源统一为 `ChatPage.rowKeyAt()`，LazyForEach 的 keyGenerator 与差分共用一份 | `ChatPage.ets` |

**「一闪一闪」的机理**：上传进度每 200ms（coordinator `scheduleThrottledSync`）推一次新 items，
原实现每次都 `onDataReloaded()` → 整张列表的 `ListItem` 全部销毁重建、图片与视频重新解码。
改为逐行 `onDataChange` 后只有进度真正推进的那一行重绘。

### 验证（模拟器 127.0.0.1:5555，uinode 树 + 屏幕像素双重取证）

- 文档气泡内容行 `809px @ x350..1159`；图标 `154×154px`；箭头 `70×70` 居中于圆心；
- 「Huawei Share.txt」第二个文档气泡同规格；
- 语音气泡播放钮 `140×140px`，`Row @ x458`（= 容器 416 + 42）；
- 视频卡片 `809px @ x350..1159`，遮罩圆圆心 **754.5** vs 气泡中心 **754.0**；
- 屏幕截图直接量测：文档图标 bbox **154×154px**（正圆，非椭圆）。
