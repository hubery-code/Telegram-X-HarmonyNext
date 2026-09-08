# 行为样本：基础媒体查看（图片消息 → 点击 → 全屏查看）

> 截图/录屏：待真机采集。本文档基于 Android 参考实现代码分析（类路径与行号已核实），真机素材回填到本文件「证据」小节。
> 关联：计划 §3.2 P1「基础媒体查看和播放」；FEATURE_MATRIX `P1-MEDIA-001`。

## 1. 场景总览

聊天内点击图片消息 → 进入全屏媒体查看器（`MediaViewController`，约 9.4k 行），按当前聊天媒体栈左右滑动浏览；未下载的原图边查看边下载（`DownloadFile` 进度），支持缩放手势、保存/转发/删除等操作菜单。本样本只锁定 P1 的「基础查看」路径，不含编辑、GIF/视频自动播放策略与后台音频。

## 2. 场景步骤序列

### 2.1 打开查看器

| # | 用户动作 | 系统事件 | UI 状态 |
|---|---|---|---|
| 1 | 在聊天页点击带图消息（或缩略图） | `MediaViewController.openFromMessage(TGMessage, MediaItem)`（`mediaview/MediaViewController.java:8394`；媒体容器重载 :8475） | 查看器以共享元素动画从缩略图位置放大展开；模式 = `MODE_MESSAGES`（:205，来自聊天的浏览模式） |
| 2 | 构建媒体栈 | `MediaStack`（`mediaview/data/MediaStack.java`）收集当前聊天可浏览媒体项（`MediaItem`，`mediaview/data/MediaItem.java`） | 打开位置定位到被点击项，底部指示器显示「3 / 12」类位置信息 |
| 3 | 小图已缓存 | TDLib 缩略图本地命中 | 立即显示清晰缩略图，顶部进度环短暂出现后消失 |
| 4 | 原图未下载 | `DownloadFile(fileId, priority, offset, limit, synchronous)` 按优先级发起 | 全屏先显示模糊缩略图占位，顶部细进度条显示下载百分比；完成后替换为原图 |

### 2.2 浏览与手势

| # | 用户动作 | 系统事件 | UI 状态 |
|---|---|---|---|
| 1 | 左右滑动 | 本地栈切换（`MediaStack` 前移/后移） | 上一张/下一张切换动画；若为视频项则显示播放按钮覆盖层 |
| 2 | 双指缩放 / 双击 | 本地手势（`MediaViewController` 内 `ZoomControl`） | 原图缩放平移；单击切换工具栏显隐（标题/发送者/时间/操作按钮淡出或淡入） |
| 3 | 下滑退出 | 关闭手势 | 查看器随手指下移缩小并透明，松手后回到聊天列表原缩略图位置（共享元素返回动画） |
| 4 | 点击「更多」菜单 | 本地操作菜单 | 选项：保存到相册、转发、删除、分享文件等（对应 `ForwardMessages` / `DeleteMessages`，与 send-text-message.md §2.3 共用链路） |

### 2.3 聊天内媒体消息的其他基础行为

| # | 用户动作 | 系统事件 | UI 状态 |
|---|---|---|---|
| 1 | 收到未下载图片消息 | `UpdateNewMessage`（photo 类型） | 气泡内显示压缩缩略图 + 大小/下载按钮覆盖层 |
| 2 | 点击下载按钮 | `DownloadFile` | 覆盖层变为环形进度；完成后图片清晰展示，覆盖层消失 |
| 3 | 发送方上传图片 | `SendMessage(InputMessagePhoto)` | 气泡内出现上传进度覆盖层；`UpdateMessageSendSucceeded` 后转正常态；失败显示重发标记（与 send-text-message.md §2.2 同规则） |
| 4 | 多图同发 | 每条消息独立气泡，连续排列 | 与文本连续消息同样的 header 压缩规则 |

## 3. 关键 UI 状态汇总

- **气泡态**：缩略图（圆角裁剪）、未下载时带「下载」覆盖层（大小标注）、下载中环形进度、发送中/失败态同文本消息规则。
- **查看器态**：全屏黑底、原图（未下载先模糊占位 + 顶部进度条）、位置指示、单击显隐工具栏、缩放/滑动/下拉退出。
- **下载策略**：缩略图（`thumbnail` file）优先展示，原图按需拉取；重复打开优先读缓存。

## 4. Android 类（真实路径，相对 `org/thunderdog/challegram/`）

| 类 | 作用 |
|---|---|
| `mediaview/MediaViewController.java` | 全屏查看器：打开入口 `openFromMessage` :8394/:8475、模式常量 `MODE_MESSAGES` :205 |
| `mediaview/data/MediaStack.java` | 浏览媒体栈（左右滑数据源） |
| `mediaview/data/MediaItem.java` | 媒体项抽象（photo/video 等） |
| `data/TGMessageMedia.java` | 聊天内媒体消息气泡（缩略图/进度/覆盖层） |
| `data/ComplexMediaItem.java` | 相册/复杂媒体组引用 |
| `data/TGMessage.java` | 气泡消息基类，点击路由到查看器 |
| `ui/MessagesController.java` | 聊天页（点击事件的宿主） |

## 5. TDLib 事件对照

| request | 说明 |
|---|---|
| `DownloadFile` | 原图/缩略图下载（priority 控制抢占） |
| `CancelDownloadFile` | 退出查看器时取消低优先级下载 |
| `SendMessage(InputMessagePhoto/Video/Document/Audio)` | 发送媒体 |
| `DeleteMessages` / `ForwardMessages` | 查看器菜单动作 |
| `GetRemoteFile` / `ReadFilePart`（仅流式场景） | P1 范围外，备查 |

| update | UI 影响 |
|---|---|
| `UpdateFile`（下载进度） | 进度条/环形进度刷新，完成后替换原图 |
| `UpdateMessageSendSucceeded` / `UpdateMessageSendFailed` | 发送态收敛（同文本消息） |
| `UpdateNewMessage` | 新媒体消息插入气泡 |

## 6. Harmony 侧验收观察点

1. 点击查看器有共享元素展开/返回动画（Harmony 侧用转场动画等价实现）；返回后落回聊天原滚动位置。
2. 未下载图片：先模糊占位 + 可见进度，完成后无感替换；退出查看器取消非必要下载。
3. 左右滑动浏览按聊天媒体栈顺序，位置指示正确。
4. 缩放、单击显隐工具栏、下拉退出三种手势可用。
5. 气泡态的下载/上传进度覆盖层与文本消息的发送/失败状态规则一致。
6. 发送图片（相册选择 → 发送）走 `InputMessagePhoto`，上传进度在气泡内可见，失败可重试。
7. P1 范围内视频只需「点击进入查看器 + 手动播放按钮」，自动播放策略属 P2+。

## 7. 证据（待回填）

- [ ] 气泡内未下载/下载中/已下载三态截图
- [ ] 查看器打开/滑动/缩放/下拉退出录屏
- [ ] 发送图片上传进度与失败重试截图
