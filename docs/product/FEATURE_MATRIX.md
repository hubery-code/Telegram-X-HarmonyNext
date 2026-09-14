# Feature Matrix（功能矩阵）

> 单一事实源（计划 §20）。本表登记**要做哪些功能**；与 Android 参考的**行为差距**登记在 PARITY_MATRIX.md。
> Android 参考根：`/Users/mbjpeng-yu01/androidProjects/Telegram-X/app/src/main/java/org/thunderdog/challegram/`
> 下表「Android 参考位置」均为已核实存在的真实路径（类级，含关键行号）。
> 状态机：`Backlog → Contract Ready → Implementing → Verifying → Accepted` / `Blocked / Deferred`。

列说明：

| 列 | 含义 |
|---|---|
| 功能 ID | 域前缀编码：FEAS=P0 可行性 / AUTH=授权 / ACC=多账号 / CHAT=会话列表 / MSG=消息流 / COMP=消息操作 / MEDIA=媒体 / SEARCH=搜索 / PUSH=Push 通知 / SET=设置 / UI=外观与本地化 |
| 优先级 | P0 可行性 / P1 MVP / P2 Beta / P3 高级 |
| Android 参考位置 | 相对 `org/thunderdog/challegram/` 的路径，引用到类级别 |
| TDLib 方法 | 主要 request / update；多个用 `,` 分隔 |
| Harmony 目标行为 | 一句话验收目标 |
| 平台能力/权限 | HarmonyOS Kit / 权限（计划 §20 要求项） |
| 状态 | 当前全部为 `Backlog` |
| 负责人 | 待分配（Phase 1 工作包下发时填写） |

---

## P0：可行性验证（计划 §3.1，不是产品版本）

| 功能 ID | 功能 | 优先级 | Android 参考位置 | TDLib 方法 | Harmony 目标行为 | 平台能力/权限 | 状态 | 负责人 |
|---|---|---|---|---|---|---|---|---|
| FEAT-FEAS-001 | TDLib 及最小依赖 HarmonyOS NDK arm64 Release `.so` 可复现构建 | P0 | `tdlib/`（Android 侧为 CMake/NDK 构建脚本，无 Java 类） | —（native） | 同一 commit 两次构建 `.so` 哈希一致 | NDK/CMake/Ninja | Accepted | 迁移组 |
| FEAT-FEAS-002 | Node-API 最小契约 create/send/receive/execute/close | P0 | `telegram/Tdlib.java`（Client 封装参考），`TDLib.java` | SetTdlibParameters（初始化） | ArkTS 侧可创建客户端、同步 execute、异步收 update、优雅 close | Node-API (NAPI) | Accepted | 迁移组 |
| FEAT-FEAS-003 | 真机垂直链路：授权→会话列表→打开聊天→收发文本→重启恢复 | P0 | `MainActivity.java`, `ui/ChatsController.java`, `ui/MessagesController.java` | SetAuthenticationPhoneNumber, GetChats, GetChatHistory, SendMessage, GetAuthorizationState | 真机一次会话内完成全链路，杀进程重启后状态自动恢复 | 网络 | Accepted | 迁移组 |
| FEAT-FEAS-004 | 数据目录隔离、数据库密钥保存、异常退出恢复 | P0 | `telegram/Tdlib.java`（updateAuthState, :1194），`BaseApplication.kt` | SetTdlibParameters（database_directory / encryption key） | 每账号独立目录，key 入 HUKS，kill -9 后无数据库损坏 | 文件、HUKS | Accepted | 迁移组 |
| FEAT-FEAS-005 | 前后台切换、断网重连、24 小时 update 事件 soak | P0 | `telegram/ConnectionListener.java`, `telegram/TdlibManager.java`, `core/WatchDog.java` | updateConnectionState（可订阅） | 24h 事件流无乱序/丢失/泄漏，断网自动重连 | 网络 | Verifying | 迁移组 |
| FEAT-FEAS-006 | Push Kit token 经 Telegram 后端端到端唤醒 | P0 | `telegram/Tdlib.java:683`（RegisterDevice）, `service/PushHandler.kt`, `service/PushProcessor.java` | RegisterDevice, updateNotification | 新 bundle 的 Push token 注册成功，杀进程后推送可达 | Push Kit | Blocked | ADR-003 |
| FEAT-FEAS-007 | tgcalls/WebRTC + OHAudio/Camera 双向音视频最小 PoC | P0 | `voip/TgCallsController.java`, `voip/VoIPController.java`, `voip/AudioRecordJNI.java`, `voip/AudioTrackJNI.java` | SetCall, DiscardCall | 真机双向通话 ≥60s，音频双向可听、视频帧可渲染 | Call Service Kit、OHAudio、Camera、麦克风/相机权限 | Deferred | ADR-004 |

## P1：核心聊天 MVP（计划 §3.2）

### 授权状态机

| 功能 ID | 功能 | 优先级 | Android 参考位置 | TDLib 方法 | Harmony 目标行为 | 平台能力/权限 | 状态 | 负责人 |
|---|---|---|---|---|---|---|---|---|
| FEAT-AUTH-001 | 手机号 + 国家码输入 | P1 | `ui/PhoneController.java`（SetAuthenticationPhoneNumber 唯一调用处）, `ui/CountryController.java`, `MainActivity.java:561`（generateUnauthorizedController） | SetAuthenticationPhoneNumber, updateAuthorizationState | 合法手机号提交后进入验证码页；非法格式本地拦截 | 网络 | Accepted | 迁移组 |
| FEAT-AUTH-002 | 验证码校验（含自动填充提示） | P1 | `ui/PasswordController.java`（MODE_CODE） | CheckAuthenticationCode | 正确验证码进入下一状态；错误码显示剩余重试次数 | 网络 | Accepted | 迁移组 |
| FEAT-AUTH-003 | 2FA 密码校验 | P1 | `ui/PasswordController.java`（MODE_LOGIN） | CheckAuthenticationPassword, ResetAuthenticationPassword | 密码错误提示与忘记密码入口可用 | 网络 | Accepted | 迁移组 |
| FEAT-AUTH-004 | 新用户注册（姓名） | P1 | `ui/EditNameController.java:361`（RegisterUser） | RegisterUser, updateAuthorizationState(WaitRegistration) | 新号完成姓名设置后进入 Ready | 网络 | Accepted | 迁移组 |
| FEAT-AUTH-005 | 二维码登录（扫码由其他设备确认） | P1 | `MainActivity.java:604`（TGX 明确不支持：`Should never come to TGX`）；状态处理见 `telegram/Tdlib.java` updateAuthState | RequestQrCodeAuthentication, updateAuthorizationState(WaitOtherDeviceConfirmation) | Harmony 侧为**新增能力**（无 Android 对等 UI）：展示二维码并轮询授权状态 | 网络 | Accepted | 迁移组 |
| FEAT-AUTH-006 | 登出 | P1 | `ui/SettingsLogOutController.java`, `telegram/Tdlib.java:1150`, `telegram/TdlibUi.java:4480` | LogOut, updateAuthorizationState(LoggingOut/LoggedOut) | 登出后回到未授权首页，本地数据按 TDLib 语义清理 | — | Accepted | 迁移组 |

### 多账号

| 功能 ID | 功能 | 优先级 | Android 参考位置 | TDLib 方法 | Harmony 目标行为 | 平台能力/权限 | 状态 | 负责人 |
|---|---|---|---|---|---|---|---|---|
| FEAT-ACC-001 | 多账号基础框架（每账号独立 Tdlib 实例） | P1 | `telegram/TdlibManager.java`, `telegram/TdlibAccount.java`, `BaseApplication.kt` | 每账号独立 SetTdlibParameters / GetAuthorizationState | 支持 ≥3 账号并存，实例生命周期互不干扰 | 文件、HUKS | Accepted | 迁移组 |
| FEAT-ACC-002 | 账号切换与快速切换 UI | P1 | `navigation/DrawerController.java:620`（账号项点击）, `:708`（onAccountSwitched）, `MainActivity.java:518`（onAuthorizationStateChanged） | updateAuthorizationState（按账号分发） | 切换后 1s 内展示目标账号会话列表，未读计数正确 | — | Backlog | |
| FEAT-ACC-003 | 单账号登出/添加账号入口 | P1 | `ui/SettingsLogOutController.java`, `navigation/DrawerController.java` | LogOut, GetAuthorizationState | 登出当前账号不影响其他账号在线状态 | — | Accepted | 迁移组 |

### 会话列表

| 功能 ID | 功能 | 优先级 | Android 参考位置 | TDLib 方法 | Harmony 目标行为 | 平台能力/权限 | 状态 | 负责人 |
|---|---|---|---|---|---|---|---|---|
| FEAT-CHAT-001 | 会话列表分页加载与排序 | P1 | `ui/ChatsController.java`, `telegram/Tdlib.java:1841`（LoadChats） | GetChats, LoadChats, updateNewChat, updateChatLastMessage | 冷启动首屏 ≤1s 出列表，滚动到底自动加载下一页 | — | Accepted | 迁移组 |
| FEAT-CHAT-002 | 会话置顶/取消置顶 | P1 | `ui/ChatsController.java:1457`（ToggleChatIsPinned） | ToggleChatIsPinned, updateChatPosition | 置顶会话固定于列表顶部并按 pin 时间排序 | — | Accepted | 迁移组 |
| FEAT-CHAT-003 | 归档/取消归档 | P1 | `ui/ChatsController.java:1766`（经 `telegram/TdlibUi.java` processChatAction, btn_archiveUnarchiveChat） | ChangeChatList（ChatListArchive ↔ ChatListMain）, updateNewChat | 归档会话移入归档区并可还原，归档未读可折叠计数 | — | Backlog | |
| FEAT-CHAT-004 | 未读数 / @提及计数 / 手动标未读 | P1 | `ui/ChatsController.java:2819`（onChatReadInbox）, `:3004`（onChatCounterChanged）, `telegram/Tdlib.java:1853`（ToggleChatIsMarkedAsUnread） | ToggleChatIsMarkedAsUnread, updateUnreadMessageCount, updateUnreadChatCount | 徽标数与 TDLib counter 一致，静音会话不计入全局角标 | — | Accepted | 迁移组 |
| FEAT-CHAT-005 | 输入草稿保存与展示 | P1 | `component/chat/InputView.java`, `ui/MessagesController.java` | SetChatDraftMessage, updateChatDraftMessage | 离开聊天后列表项显示草稿前缀样式，重进恢复输入 | — | Backlog | |

### 消息流

| 功能 ID | 功能 | 优先级 | Android 参考位置 | TDLib 方法 | Harmony 目标行为 | 平台能力/权限 | 状态 | 负责人 |
|---|---|---|---|---|---|---|---|---|
| FEAT-MSG-001 | 私聊消息流（气泡/时间/状态图标） | P1 | `ui/MessagesController.java`, `component/chat/MessagesAdapter.java`, `component/chat/MessageView.java` | GetChatHistory, updateNewMessage, updateMessageContent | 打开私聊即见最近历史，新消息实时插入并滚动 | — | Accepted | 迁移组 |
| FEAT-MSG-002 | 群组/频道消息流（含署名/管理员标签） | P1 | `ui/MessagesController.java`, `data/TGMessage.java`, `data/TGMessageGroup.java` | 同上 | 群组显示发送者头像与名称，频道显示频道署名 | — | Accepted | 迁移组 |
| FEAT-MSG-003 | 历史分页与跳转加载 | P1 | `component/chat/MessagesLoader.java`, `component/chat/MessagesManager.java` | GetChatHistory, GetMessage | 向上滚动触发分页，无重复/空洞，加载中有骨架提示 | — | Accepted | 迁移组 |
| FEAT-MSG-004 | 已读上报与已读回执 | P1 | `telegram/TdlibMessageViewer.java:769`（ViewMessages）, `ui/MessagesController.java` | ViewMessages, updateChatReadInbox, updateChatReadOutbox | 消息入屏即上报已读；私聊显示单勾/双勾/已读态 | — | Accepted | 迁移组 |

### 消息操作

| 功能 ID | 功能 | 优先级 | Android 参考位置 | TDLib 方法 | Harmony 目标行为 | 平台能力/权限 | 状态 | 负责人 |
|---|---|---|---|---|---|---|---|---|
| FEAT-COMP-001 | 发送文本消息 | P1 | `data/TD.java:3031`（SendMessage）, `component/chat/InputView.java`, `component/chat/ChatBottomBarView.java` | SendMessage, updateMessageSendSucceeded, updateMessageSendFailed | 发送后气泡立即上屏（pending），成功转 sent，失败可重试 | — | Accepted | 迁移组 |
| FEAT-COMP-002 | 链接识别与预览 | P1 | `data/TD.java`（InputMessageText + linkPreviewOptions）, `ui/MessagesController.java` | InputMessageText, GetWebPagePreview | 消息内 URL 可点击，发送时按设置生成链接预览 | 网络 | Backlog | |
| FEAT-COMP-003 | 回复消息 | P1 | `component/chat/ReplyComponent.java`, `ui/MessagesController.java` | SendMessage(replyTo), InputTextQuote | 引用条展示原文摘要，发出后气泡内嵌回复块 | — | Accepted | 迁移组 |
| FEAT-COMP-004 | 转发消息 | P1 | `data/TD.java:1788`（ForwardMessages）, `ui/ShareController.java:1900` | ForwardMessages, SendMessage(InputMessageForwarded) | 可多选消息转发到目标会话，支持隐藏来源选项 | — | Accepted | 迁移组 |
| FEAT-COMP-005 | 编辑消息 | P1 | `telegram/Tdlib.java:4843`（EditMessageText）, `telegram/MessageEditListener.java` | EditMessageText, updateMessageEdited | 自己的文本消息可编辑，气泡标注「已编辑」 | — | Accepted | 迁移组 |
| FEAT-COMP-006 | 删除消息 | P1 | `telegram/Tdlib.java:5764`（DeleteMessages）, `ui/MessageOptionsController.java` | DeleteMessages, updateDeleteMessages | 支持为己删除/双方删除，删除后列表即时移除 | — | Accepted | 迁移组 |
| FEAT-COMP-007 | 复制文本 | P1 | `ui/MessagesController.java`（剪贴板封装，无 TDLib 请求） | —（平台剪贴板） | 长按复制消息文本到系统剪贴板 | 剪贴板（pasteboard） | Accepted | 迁移组 |

### 媒体

| 功能 ID | 功能 | 优先级 | Android 参考位置 | TDLib 方法 | Harmony 目标行为 | 平台能力/权限 | 状态 | 负责人 |
|---|---|---|---|---|---|---|---|---|
| FEAT-MEDIA-001 | 图片消息上传/下载/进度 | P1 | `telegram/TdlibFilesManager.java:598`（DownloadFile）, `data/TD.java`（InputMessagePhoto）, `widget/FileProgressComponent.java` | SendMessage(InputMessagePhoto), DownloadFile, updateFile | 选图发送带进度圈，接收图片点击下载并可暂停 | 相册/图片权限 | Backlog | |
| FEAT-MEDIA-002 | 视频消息上传/下载 | P1 | `data/TD.java`（InputMessageVideo）, `telegram/TdlibFilesManager.java` | SendMessage(InputMessageVideo), DownloadFile, updateFile | 视频缩略图先展示，进度与失败重试可用 | 相册/视频权限 | Verifying | 迁移组 |
| FEAT-MEDIA-003 | 文件消息上传/下载 | P1 | `data/TD.java`（InputMessageDocument）, `ui/ShareController.java` | SendMessage(InputMessageDocument), DownloadFile, updateFile | 文件气泡显示名称/大小/下载态，完成可打开 | 文件读写 | Backlog | |
| FEAT-MEDIA-004 | 语音消息录制/发送/播放 | P1 | `component/chat/VoiceVideoButtonView.java:227`, `player/RecordAudioVideoController.java`, `data/TD.java`（InputMessageVoiceNote） | SendMessage(InputMessageVoiceNote), DownloadFile | 按住录音松开发送，波形展示，可播放 | 麦克风权限、音频焦点 | Backlog | |
| FEAT-MEDIA-005 | 传输失败重试/取消 | P1 | `telegram/TdlibFilesManager.java:817`（cancelDownloadOrUploadFile）, `ui/MessagesController.java` | CancelUploadFile, CancelDownloadFile, updateMessageSendFailed | 失败项一键重发/重新下载，取消后不留半成品 | — | Backlog | |
| FEAT-MEDIA-006 | 基础媒体查看/播放 | P1 | `mediaview/MediaViewController.java`, `mediaview/MediaView.java` | DownloadFile（原图） | 点击图片全屏查看，支持缩放与左右翻页；视频可播放 | — | Accepted | 迁移组 |

### 搜索

| 功能 ID | 功能 | 优先级 | Android 参考位置 | TDLib 方法 | Harmony 目标行为 | 平台能力/权限 | 状态 | 负责人 |
|---|---|---|---|---|---|---|---|---|
| FEAT-SEARCH-001 | 全局搜索（联系人/群组/频道/消息） | P1 | `component/dialogs/SearchManager.java:570`（SearchChats）, `:993`（SearchMessages） | SearchChats, SearchPublicChats, SearchMessages | 搜索页分组展示本地与云端结果，防抖加载 | — | Accepted | 迁移组 |
| FEAT-SEARCH-002 | 聊天内搜索 | P1 | `component/chat/MessagesSearchManager.java`, `component/chat/MessagesSearchManagerMiddleware.java`, `ui/MessagesController.java:112` | SearchMessages(chatId), SearchMessagesFilterText 等 | 聊天内关键字搜索，结果跳转定位到原消息 | — | Backlog | |

### Push 与通知

| 功能 ID | 功能 | 优先级 | Android 参考位置 | TDLib 方法 | Harmony 目标行为 | 平台能力/权限 | 状态 | 负责人 |
|---|---|---|---|---|---|---|---|---|
| FEAT-PUSH-001 | Push token 注册与消息推送接收 | P1 | `telegram/Tdlib.java:683`（RegisterDevice）, `service/PushHandler.kt`, `service/PushProcessor.java` | RegisterDevice, processPushNotification | 登录后自动注册；后台/杀进程状态推送可达 | Push Kit、通知权限 | Blocked | ADR-003 |
| FEAT-PUSH-002 | 通知聚合与点击跳转 | P1 | `telegram/TdlibNotificationManager.java`, `telegram/TdlibNotificationGroup.java`, `receiver/TGMessageReceiver.java`（点击路由） | updateNotification / updateNotificationGroup | 同会话消息聚合为单条通知，点击直达对应聊天 | 通知、WantAgent | Blocked | ADR-003 |
| FEAT-PUSH-003 | 前后台切换与连接恢复 | P1 | `MainActivity.java`（生命周期）, `telegram/ConnectionListener.java`, `core/WatchDog.java` | updateConnectionState, GetChats（恢复增量） | 回前台 2s 内同步离线期间消息，无重复推送 | — | Accepted | 迁移组 |

### 基础设置

| 功能 ID | 功能 | 优先级 | Android 参考位置 | TDLib 方法 | Harmony 目标行为 | 平台能力/权限 | 状态 | 负责人 |
|---|---|---|---|---|---|---|---|---|
| FEAT-SET-001 | 设置主列表 | P1 | `ui/SettingsController.java`（:104 类声明, :218 字号读取） | — | 设置页含账号信息、通知、存储、隐私等入口 | — | Accepted | 迁移组 |
| FEAT-SET-002 | 语言切换（中/英） | P1 | `ui/SettingsLanguageController.java`, `core/Lang.java`, `telegram/Tdlib.java:5912`（SetOption language_pack_id） | SetOption(language_pack_id) | 切换后 UI 立即生效且重启保持，TDLib 语言包同步 | — | Backlog | |
| FEAT-SET-003 | 通知设置入口 | P1 | `ui/SettingsNotificationController.java`, `telegram/LocalScopeNotificationSettings.java` | SetNotificationSettings, SetChatNotificationSettings | 全局/单会话通知开关生效并持久化 | 通知权限 | Backlog | |
| FEAT-SET-004 | 存储与缓存入口 | P1 | `ui/SettingsCacheController.java`, `telegram/TdlibSettingsManager.java` | GetStorageStatistics, OptimizeStorage | 展示缓存占用并支持一键清理，清理后媒体可重下 | 文件 | Backlog | |

### 外观与本地化

| 功能 ID | 功能 | 优先级 | Android 参考位置 | TDLib 方法 | Harmony 目标行为 | 平台能力/权限 | 状态 | 负责人 |
|---|---|---|---|---|---|---|---|---|
| FEAT-UI-001 | 深色/浅色主题 | P1 | `theme/ThemeManager.java:48`（DEFAULT_DARK_THEME = NIGHT_BLUE）, `theme/Theme.java` | —（平台侧） | 跟随系统/手动切换，关键页面（列表/聊天/设置）色值正确 | — | Accepted | 迁移组 |
| FEAT-UI-002 | 大字体（聊天字号调节） | P1 | `unsorted/Settings.java:791`（CHAT_FONT_SIZES）, `ui/SettingsController.java:218`（getChatFontSize） | —（平台侧） | 大字号模式下气泡/列表不截断不重叠 | 字体缩放 | Backlog | |
| FEAT-UI-003 | 中/英文案资源 | P1 | `core/Lang.java`, `ui/SettingsLanguageController.java` | — | 关键路径文案中英齐全，无硬编码遗漏 | — | Backlog | |

---

## P2：公开 Beta 完整度（计划 §3.3，仅列名）

| 功能 ID | 功能名 |
|---|---|
| FEAT-P2-001 | 联系人同步与新建会话 |
| FEAT-P2-002 | 群组/频道创建、成员、权限、邀请链接 |
| FEAT-P2-003 | 反应、投票、置顶消息、话题/论坛 |
| FEAT-P2-004 | Sticker、emoji、GIF、动画贴纸 |
| FEAT-P2-005 | CameraPicker、相册、文件选择、系统分享 |
| FEAT-P2-006 | 完整媒体查看器、后台音频、AVSession |
| FEAT-P2-007 | 代理、下载策略、缓存清理 |
| FEAT-P2-008 | Passcode、生物识别、活跃会话管理 |
| FEAT-P2-009 | 实时位置、地图 adapter |
| FEAT-P2-010 | `tg://`、`t.me` 深链与 Share Extension |
| FEAT-P2-011 | 平板/折叠屏双栏、无障碍与 RTL |

## P3：高级功能（计划 §3.4，仅列名）

| 功能 ID | 功能名 |
|---|---|
| FEAT-P3-001 | 一对一语音/视频通话 |
| FEAT-P3-002 | 群组通话和直播 |
| FEAT-P3-003 | Stories |
| FEAT-P3-004 | 视频压缩、裁剪、编辑 |
| FEAT-P3-005 | Instant View、Web App/Game |
| FEAT-P3-006 | 高级主题编辑、完整动画与特色手势 |
| FEAT-P3-007 | PC/2in1、穿戴等鸿蒙扩展场景 |

---

## 维护规则

- 每项变更必须绑定 work item 与 commit；「最后回归」在每次 Gate 后更新（见 PARITY_MATRIX.md 状态推进）。
- Android 参考位置在开工前必须重新 glob 核实；不存在的路径视为该工作包的 DoR 未满足。
- 状态推进顺序：`Backlog → Contract Ready → Implementing → Verifying → Accepted`；受阻项标 `Blocked` 并登记风险（计划 §3.5）。
