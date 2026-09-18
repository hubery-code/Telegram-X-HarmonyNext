# CHANNEL-101 频道帖子评论页与音视频便签增强（FEAT-P2-002 / FEAT-P2-003 / FEAT-P2-006 延伸）

## 结果
- 状态：Accepted
- 特性编号：FEAT-P2-002 / FEAT-P2-003 / VIDEONOTE-101 / AUDIO-101
- 执行者：AI-Agent-Antigravity
- 运行验证设备：HarmonyOS NEXT 模拟器（`127.0.0.1:5555`）

---

## 核心工作与修改清单

### 1. 类型安全深链与路由定义 (`core/navigation`)
遵循 `NAV-001` 与单一事实源架构：
- **`Route.ets`**：
  - `RouteName` 联合类型新增 `'comments'`；
  - 新增 `CommentsRoute` 接口定义：`{ readonly name: 'comments'; readonly chatId: number; readonly messageId: number; }`；
  - 纳入 `AppRoute` 联合并注册深链模板 `ROUTE_DEFINITIONS: 'comments/:chatId/:messageId'`。
- **`RouteCodec.ets`**：
  - `buildFromParams` 与 `collectRouteParams` 补充 `comments` 路由序列化与反序列化解析。
- **`RouteCodec.test.ets`**：
  - 补充 `comments/1001/2002` 编解码 RoundTrip 单元测试。

### 2. 领域层讨论组与 Thread 协议支持 (`core/domain`)
- **`MessageProjection.ets`**：
  - 接入 TDLib 官方生成的 `GetMessageThread` 与 `GetMessageThreadHistory`；
  - 新增 `getMessageThread(messageId: number)`：解析频道帖子对应的关联讨论超级群（discussion supergroup）与 `message_thread_id`；
  - 新增 `getMessageThreadHistory(messageId, fromMessageId, offset, limit)`：拉取线程历史消息流。
- **`MessageProjection.test.ets`**：
  - 补充线程历史请求参数校验用例，确保 `chat_id`、`message_id`、`offset` 与 `limit` 组装正确。

### 3. 会话特性层评论 MVI 与音视频便签增强 (`feature/chat`)
- **`CommentsCoordinator.ets`（新建）**：
  - 遵循 `ARCH-001` 与 `ADR-007`，100% Kit-free 纯 ArkTS 协调器；
  - 支持频道帖子元数据（`GetMessage` / `GetChat`）并发解析；
  - 处理讨论超级群与 `message_thread_id` 自动定位与回退机制；
  - 支持 `sendComment(text)`：向关联讨论群以 `message_thread_id` 作为 `reply_to` 派发 `SendMessage`；
  - 本地乐观回显：发送瞬间乐观插入评论列表（带发送中中转态），并在回包时平滑更新状态。
- **`CommentsPage.ets`（新建 UI 组件）**：
  - 遵循 Telegram X 设计规范：
    - **顶栏导航**：返回键、评论总数标题与频道名副标题；
    - **吸顶主帖卡片**：展示被评论频道的原始帖子文本、发送时间与左侧主题色重音条；
    - **评论消息流**：展示评论者头像（字母及随机调色板配色）、名称、文本气泡、发送时间与发送中勾选指示；
    - **底部评论输入框**：圆角输入框与 Telegram 经典蓝色圆形发送按钮。
- **`ChatPage.ets`**：
  - **`AudioBubble` (AUDIO-101)**：
    - 接入 `PlayVoiceNote` 与 `PauseVoiceNote`，根据播放器当前播放状态实时切换播放/暂停图标；
    - 播放中实时展示细粒度线性 `Progress` 进度条与动态时间显示（`00:15 / 03:20`）。
  - **`VideoNoteBubble` (VIDEONOTE-101)**：
    - 增加 `@State activeVideoNoteId: number | null = null` 控制当前有声便签；
    - 视频便签点击时在有声与静音之间平滑切换（`.muted(this.activeVideoNoteId !== item.messageId)`）；
    - 左上角增加半透明悬浮扬声器角标（`ic_volume_up` / `ic_mute`），清晰提示当前声音状态。
- **`CommentsCoordinator.test.ets`（新建单元测试）**：
  - 覆盖默认初始状态、`start()` 关联请求派发、`setInputText` 响应式通知、`sendComment` 乐观追加以及 `destroy()` 取消订阅。

### 4. 资源支持与图标对齐
- 新增标准矢量图标 `ic_volume_up.svg`，同步补齐于：
  - `AppScope/resources/base/media/ic_volume_up.svg`
  - `entry/src/main/resources/base/media/ic_volume_up.svg`
  - `feature/chat/src/main/resources/base/media/ic_volume_up.svg`

### 5. 顶层入口与路由生命周期装配 (`entry`)
- **`entry/src/main/ets/pages/Index.ets`**：
  - 导入 `CommentsRoute`、`CommentsPage`、`CommentsCoordinator` 与 `CommentsUiState`；
  - 声明 `commentsUiState` 响应式状态与 `commentsCoordinator`；
  - 在 `openChat()` 的 `ChatCoordinator` 参数中注入 `onOpenComments` 回调；
  - 在 `onRouteChanged` 中监听 `comments` 路由，按需创建 `CommentsCoordinator` 并注入 `onBack`；在栈中无该路由时自动调用 `closeComments()` 销毁；
  - 在 `aboutToDisappear()` 中统一执行 `closeComments()` 清理；
  - 在 `build()` 中当 `this.currentRoute.name === 'comments'` 时条件渲染全屏 `CommentsPage`。

---

## 验证与测试报告

1. **局部受影响模块单元测试**：
   - `core_navigation`: **BUILD SUCCESSFUL** (6.5s)
   - `core_domain`: **BUILD SUCCESSFUL** (26.2s)
   - `feature_chat`: **BUILD SUCCESSFUL** (33.3s)
2. **四项秒级静态安全与架构防线**：
   - `python3 tools/ci/check_architecture.py`：OK（0 violations）
   - `python3 tools/ci/check_codegen.py`：OK（ALL CODEGEN CHECKS PASSED）
   - `python3 tools/ci/check_design_tokens.py`：OK（未发现未定义 token）
   - `python3 tools/ci/secret_scan.py`：OK（0 secrets detected）
3. **Signed Debug HAP 构建与模拟器安装**：
   - `./tools/ci/build-signed.sh debug` 构建出 `entry-default-signed.hap`；
   - 安装至鸿蒙 NEXT 模拟器 `127.0.0.1:5555` 并成功启动 `EntryAbility`。
