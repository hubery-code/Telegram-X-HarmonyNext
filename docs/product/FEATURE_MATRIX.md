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
| 状态 | 逐行登记实际状态（`Backlog` / `Contract Ready` / `Implementing` / `Verifying` / `Accepted` / `Blocked` / `Deferred`）。**2026-09-21 校准**：此前本列长期停滞、大批已交付项仍标 `Backlog`，已按 `work-items/accepted/` 逐项回填。 |
| 负责人 | 交付该行的**工作包编号**（如 `MSG-107` / `SET-105`），非人名——便于从矩阵反查证据报告 |

---

## P0：可行性验证（计划 §3.1，不是产品版本）

| 功能 ID | 功能 | 优先级 | Android 参考位置 | TDLib 方法 | Harmony 目标行为 | 平台能力/权限 | 状态 | 负责人 |
|---|---|---|---|---|---|---|---|---|
| FEAT-FEAS-001 | TDLib 及最小依赖 HarmonyOS NDK arm64 Release `.so` 可复现构建 | P0 | `tdlib/`（Android 侧为 CMake/NDK 构建脚本，无 Java 类） | —（native） | 同一 commit 两次构建 `.so` 哈希一致 | NDK/CMake/Ninja | Accepted | 迁移组 |
| FEAT-FEAS-002 | Node-API 最小契约 create/send/receive/execute/close | P0 | `telegram/Tdlib.java`（Client 封装参考），`TDLib.java` | SetTdlibParameters（初始化） | ArkTS 侧可创建客户端、同步 execute、异步收 update、优雅 close | Node-API (NAPI) | Accepted | 迁移组 |
| FEAT-FEAS-003 | 真机垂直链路：授权→会话列表→打开聊天→收发文本→重启恢复 | P0 | `MainActivity.java`, `ui/ChatsController.java`, `ui/MessagesController.java` | SetAuthenticationPhoneNumber, GetChats, GetChatHistory, SendMessage, GetAuthorizationState | 真机一次会话内完成全链路，杀进程重启后状态自动恢复 | 网络 | Accepted | 迁移组 |
| FEAT-FEAS-004 | 数据目录隔离、数据库密钥保存、异常退出恢复 | P0 | `telegram/Tdlib.java`（updateAuthState, :1194），`BaseApplication.kt` | SetTdlibParameters（database_directory / encryption key） | 每账号独立目录，key 入 HUKS，kill -9 后无数据库损坏 | 文件、HUKS | Accepted | 迁移组 |
| FEAT-FEAS-005 | 前后台切换、断网重连、24 小时 update 事件 soak | P0 | `telegram/ConnectionListener.java`, `telegram/TdlibManager.java`, `core/WatchDog.java` | updateConnectionState（可订阅） | 24h 事件流无乱序/丢失/泄漏，断网自动重连 | 网络 | Accepted | 迁移组 |
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
| FEAT-ACC-002 | 账号切换与快速切换 UI | P1 | `navigation/DrawerController.java:620`（账号项点击）, `:708`（onAccountSwitched）, `MainActivity.java:518`（onAuthorizationStateChanged） | updateAuthorizationState（按账号分发） | 切换后 1s 内展示目标账号会话列表，未读计数正确 | — | Accepted | 迁移组 |
| FEAT-ACC-003 | 单账号登出/添加账号入口 | P1 | `ui/SettingsLogOutController.java`, `navigation/DrawerController.java` | LogOut, GetAuthorizationState | 登出当前账号不影响其他账号在线状态 | — | Accepted | 迁移组 |

### 会话列表

| 功能 ID | 功能 | 优先级 | Android 参考位置 | TDLib 方法 | Harmony 目标行为 | 平台能力/权限 | 状态 | 负责人 |
|---|---|---|---|---|---|---|---|---|
| FEAT-CHAT-001 | 会话列表分页加载与排序 | P1 | `ui/ChatsController.java`, `telegram/Tdlib.java:1841`（LoadChats） | GetChats, LoadChats, updateNewChat, updateChatLastMessage | 冷启动首屏 ≤1s 出列表，滚动到底自动加载下一页 | — | Accepted | 迁移组 |
| FEAT-CHAT-002 | 会话置顶/取消置顶 | P1 | `ui/ChatsController.java:1457`（ToggleChatIsPinned） | ToggleChatIsPinned, updateChatPosition | 置顶会话固定于列表顶部并按 pin 时间排序 | — | Accepted | 迁移组 |
| FEAT-CHAT-003 | 归档/取消归档 | P1 | `ui/ChatsController.java:1766`（经 `telegram/TdlibUi.java` processChatAction, btn_archiveUnarchiveChat） | ChangeChatList（ChatListArchive ↔ ChatListMain）, updateNewChat | 归档会话移入归档区并可还原，归档未读可折叠计数 | — | Accepted | 迁移组 |
| FEAT-CHAT-004 | 未读数 / @提及计数 / 手动标未读 | P1 | `ui/ChatsController.java:2819`（onChatReadInbox）, `:3004`（onChatCounterChanged）, `telegram/Tdlib.java:1853`（ToggleChatIsMarkedAsUnread） | ToggleChatIsMarkedAsUnread, updateUnreadMessageCount, updateUnreadChatCount | 徽标数与 TDLib counter 一致，静音会话不计入全局角标 | — | Accepted | 迁移组 |
| FEAT-CHAT-005 | 输入草稿保存与展示 | P1 | `component/chat/InputView.java`, `ui/MessagesController.java` | SetChatDraftMessage, updateChatDraftMessage | 离开聊天后列表项显示草稿前缀样式，重进恢复输入 | — | Accepted | 迁移组 |

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
| FEAT-COMP-002 | 链接识别与预览 | P1 | `data/TD.java`（InputMessageText + linkPreviewOptions）, `ui/MessagesController.java` | InputMessageText, GetWebPagePreview | 消息内 URL 可点击，发送时按设置生成链接预览 | 网络 | Accepted | MSG-107 |
| FEAT-COMP-003 | 回复消息 | P1 | `component/chat/ReplyComponent.java`, `ui/MessagesController.java` | SendMessage(replyTo), InputTextQuote | 引用条展示原文摘要，发出后气泡内嵌回复块 | — | Accepted | 迁移组 |
| FEAT-COMP-004 | 转发消息 | P1 | `data/TD.java:1788`（ForwardMessages）, `ui/ShareController.java:1900` | ForwardMessages, SendMessage(InputMessageForwarded) | 可多选消息转发到目标会话，支持隐藏来源选项 | — | Accepted | 迁移组 |
| FEAT-COMP-005 | 编辑消息 | P1 | `telegram/Tdlib.java:4843`（EditMessageText）, `telegram/MessageEditListener.java` | EditMessageText, updateMessageEdited | 自己的文本消息可编辑，气泡标注「已编辑」 | — | Accepted | 迁移组 |
| FEAT-COMP-006 | 删除消息 | P1 | `telegram/Tdlib.java:5764`（DeleteMessages）, `ui/MessageOptionsController.java` | DeleteMessages, updateDeleteMessages | 支持为己删除/双方删除，删除后列表即时移除 | — | Accepted | 迁移组 |
| FEAT-COMP-007 | 复制文本 | P1 | `ui/MessagesController.java`（剪贴板封装，无 TDLib 请求） | —（平台剪贴板） | 长按复制消息文本到系统剪贴板 | 剪贴板（pasteboard） | Accepted | 迁移组 |

### 媒体

| 功能 ID | 功能 | 优先级 | Android 参考位置 | TDLib 方法 | Harmony 目标行为 | 平台能力/权限 | 状态 | 负责人 |
|---|---|---|---|---|---|---|---|---|
| FEAT-MEDIA-001 | 图片消息上传/下载/进度 | P1 | `telegram/TdlibFilesManager.java:598`（DownloadFile）, `data/TD.java`（InputMessagePhoto）, `widget/FileProgressComponent.java` | SendMessage(InputMessagePhoto), DownloadFile, updateFile | 选图发送带进度圈，接收图片点击下载并可暂停 | 相册/图片权限 | Accepted | 迁移组 |
| FEAT-MEDIA-002 | 视频消息上传/下载 | P1 | `data/TD.java`（InputMessageVideo）, `telegram/TdlibFilesManager.java` | SendMessage(InputMessageVideo), DownloadFile, updateFile | 视频缩略图先展示，进度与失败重试可用 | 相册/视频权限 | Accepted | MEDIA-106（接收）+MEDIA-105（发送）+MEDIA-107（进度/重试） |
| FEAT-MEDIA-003 | 文件消息上传/下载 | P1 | `data/TD.java`（InputMessageDocument）, `ui/ShareController.java` | SendMessage(InputMessageDocument), DownloadFile, updateFile | 文件气泡显示名称/大小/下载态，完成可打开 | 文件读写 | Accepted | 迁移组 |
| FEAT-MEDIA-004 | 语音消息录制/发送/播放 | P1 | `component/chat/VoiceVideoButtonView.java:227`, `player/RecordAudioVideoController.java`, `data/TD.java`（InputMessageVoiceNote） | SendMessage(InputMessageVoiceNote), DownloadFile | 按住录音松开发送，波形展示，可播放 | 麦克风权限、音频焦点 | Accepted | VOICE-101 |
| FEAT-MEDIA-005 | 传输失败重试/取消 | P1 | `telegram/TdlibFilesManager.java:817`（cancelDownloadOrUploadFile）, `ui/MessagesController.java` | CancelUploadFile, CancelDownloadFile, updateMessageSendFailed | 失败项一键重发/重新下载，取消后不留半成品 | — | Accepted | FILE-103 |
| FEAT-MEDIA-006 | 基础媒体查看/播放 | P1 | `mediaview/MediaViewController.java`, `mediaview/MediaView.java` | DownloadFile（原图） | 点击图片全屏查看，支持缩放与左右翻页；视频可播放 | — | Accepted | 迁移组 |

### 搜索

| 功能 ID | 功能 | 优先级 | Android 参考位置 | TDLib 方法 | Harmony 目标行为 | 平台能力/权限 | 状态 | 负责人 |
|---|---|---|---|---|---|---|---|---|
| FEAT-SEARCH-001 | 全局搜索（联系人/群组/频道/消息） | P1 | `component/dialogs/SearchManager.java:570`（SearchChats）, `:993`（SearchMessages） | SearchChats, SearchPublicChats, SearchMessages | 搜索页分组展示本地与云端结果，防抖加载 | — | Accepted | 迁移组 |
| FEAT-SEARCH-002 | 聊天内搜索 | P1 | `component/chat/MessagesSearchManager.java`, `component/chat/MessagesSearchManagerMiddleware.java`, `ui/MessagesController.java:112` | SearchMessages(chatId), SearchMessagesFilterText 等 | 聊天内关键字搜索，结果跳转定位到原消息 | — | Accepted | SEARCH-102 |

> 搜索域健壮性（失败/限流不再静默成「无结果」+ 查询节流）由 **SEARCH-103** 交付（commit `1fd1ada3`，`feature/search/SearchCoordinator` 引入 `SearchFailed` 意图与 750ms 节流、重试 UI），不单列功能 ID——属 FEAT-SEARCH-001/002 的质量补强。

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
| FEAT-SET-002 | 语言切换（中/英） | P1 | `ui/SettingsLanguageController.java`, `core/Lang.java`, `telegram/Tdlib.java:5912`（SetOption language_pack_id） | SetOption(language_pack_id) | 切换后 UI 立即生效且重启保持，TDLib 语言包同步 | — | Accepted | 迁移组 |
| FEAT-SET-003 | 通知设置入口 | P1 | `ui/SettingsNotificationController.java`, `telegram/LocalScopeNotificationSettings.java` | SetScopeNotificationSettings, SetChatNotificationSettings | 全局/单会话通知开关生效并持久化 | 通知权限 | Accepted | SET-106 |
| FEAT-SET-004 | 存储与缓存入口 | P1 | `ui/SettingsCacheController.java`, `telegram/TdlibSettingsManager.java` | GetStorageStatistics, OptimizeStorage | 展示缓存占用并支持一键清理，清理后媒体可重下 | 文件 | Accepted | 迁移组 |
| FEAT-SET-005 | 隐私和安全入口（可见范围规则） | P1 | `ui/PrivacySettingsActivity` + `TD_getPrivacySettingRules` | getUserPrivacySettingRules, setUserPrivacySettingRules | 8 项可见范围（最后上线/手机号/头像/简介/生日/通话/入群/被搜索）读真值、点一行即写回并回读确认 | — | Accepted | SELF-102 |

### 外观与本地化

| 功能 ID | 功能 | 优先级 | Android 参考位置 | TDLib 方法 | Harmony 目标行为 | 平台能力/权限 | 状态 | 负责人 |
|---|---|---|---|---|---|---|---|---|
| FEAT-UI-001 | 深色/浅色主题 | P1 | `theme/ThemeManager.java:48`（DEFAULT_DARK_THEME = NIGHT_BLUE）, `theme/Theme.java` | —（平台侧） | 跟随系统/手动切换，关键页面（列表/聊天/设置）色值正确 | — | Accepted | 迁移组 |
| FEAT-UI-002 | 大字体（聊天字号调节） | P1 | `unsorted/Settings.java:791`（CHAT_FONT_SIZES）, `ui/SettingsController.java:218`（getChatFontSize） | —（平台侧） | 大字号模式下气泡/列表不截断不重叠 | 字体缩放 | Accepted | SET-105 |
| FEAT-UI-003 | 中/英文案资源 | P1 | `core/Lang.java`, `ui/SettingsLanguageController.java` | — | 关键路径文案中英齐全，无硬编码遗漏 | — | Accepted | 迁移组 |
| FEAT-UI-004 | 抽屉主导航（≡ 账号头 + 联系人/通话/我的收藏/设置/邀请朋友/帮助 + 夜间模式开关） | P1 | `navigation/DrawerController.java`, `MainActivity.java` | —（平台侧） | 会话列表抽屉导航，账号头展示在线状态，入口路由正确 | — | Accepted | DRAWER-101 |

---

## P2：公开 Beta 完整度（计划 §3.3，仅列名）

> **2026-09-16 TGX 对齐提升（用户实拍 Telegram-X Android 截图×19 盘点，多 AI 可见；
> 此前按官方 Telegram 版的一版作废）**：FEAT-P2-001（联系人）、FEAT-P2-002（群/频道资料）、
> FEAT-P2-003 中的**置顶消息**部分**提前至 P1 执行**，已拆工作包：PROFILE-103（用户资料增强：
> 共享媒体 Tab/头部菜单）、PROFILE-102（群/频道资料页）、MSG-109（聊天头部信息区+聊天级 ⋮ 菜单）、
> MSG-108（置顶消息条）、CHANNEL-101（频道模式：评论/加入/反应 chips）、DRAWER-101（抽屉导航，
> 即 FEAT-UI-004）、CONTACT-101（联系人页）、SELF-101（我的资料页）；
> 执行顺序与并行泳道见 `PROGRESS.md`「TGX 对齐缺口」。反应投票话题/CameraPicker/深链维持 P2 原序；
> 通话/视频（FEAT-P3-001/002）、Stories/礼物维持 P3 不提前。
> **2026-09-24 进度**：PROFILE-103 的**共享内容四 Tab**（媒体/文件/链接/群组，含首屏自动拉取、失败态与点页签重试、共同群组行跳转聊天）已交付并在模拟器对着真实 TDLib 回包取证，
> 证据见 `PROGRESS.md`「已完成」表；该包的 ⋮ 头部菜单 / 通知行 / 封面大图头部仍未做。
> **同日追加（PROF-ENTRY-001）**：私聊头部标题直达「用户资料页」（peer `user_id` 取自 `getChat.type_.user_id`，非 chatId 顶替），
> 由此首次取到共享内容**非空条目**的设备证据，并修掉「缩略图未缓存时媒体条目被静默丢掉」的缺陷（改为占位瓦片）。
> **同日追加（PROFILE-NOTIF）**：通知行**真实态**交付 —— 原先 `notificationText` 是 state 里写死的 `'开启'`、行也不可点；
> 现在读 `getChat.notification_settings` 真值（TDLib 没给则显示 `—` 而不是猜「未静音」），点按经 `setChatNotificationSettings`
> 以回读快照为底本反向写入、写后 `getChat` 复核（无乐观更新），并订阅 `updateChatNotificationSettings` 实时同步；
> 静音纯模型 `isChatMuted / withChatMuteFor` 由 `feature/chat` 下沉到 `core/domain`，聊天 ⋮ 菜单与资料页通知行从此同源
> （实测两处对同一会话分别渲染为「静音」与「取消静音」）。
> **同日追加（PROFILE-MENU）**：⋮ 头部菜单**实化**交付 —— 原先六项里五项（分享联系人/屏蔽用户/隐私例外/重命名联系人/删除联系人）
> 是只打 hilog 的假入口，且「开始私密聊天」与页面底部 Message 按钮重复。现在只留三项真实动作：**发送消息**（`createPrivateChat` → 导航）、
> **开启密聊**（`createNewSecretChat`，回执 `secretChat.id` 即 `chat.id`，复用同一条 `onOpenChat` 导航，无需新路由）、
> **屏蔽用户 / 取消屏蔽**（本 schema 无 `blockUser`，走 `setMessageSenderBlockList`：屏蔽写 `blockListMain`、解除传 `null`；
> 真值取自那一次 `getChat` 的 `block_list`，读不到时菜单标「未读取」且点击 no-op，写后 `getChat` 复核，并订阅 `updateChatBlockList`）。
> 设备实证见 `PROGRESS.md`「已完成」表。
> **同日追加（PROFILE-COVER）**：**封面大图头部**交付，PROFILE-103 至此**全量完成** —— 头部不再是 56vp 小圆头像，而是对齐 Android
> `ProfileController.getHeaderHeight()`（56dp 收起 ↔ 234dp 展开）与 `ComplexHeaderView` 的 **`profile_photo.big` 全出血封面**：
> 无照片时落调色板纯色 + 大字母，上下两道遮罩**只在拿到真照片时才画**（同 Android `topShadow 0x77000000` / `bottomShadow 0x66000000`），
> 姓名/emoji 状态/在线态画在遮罩上，滚过 178vp 临界点后工具条转实心底、标题显形、图标由封面白切回主题 `icon` 色。
> 为此新增语义 token **`colors.textOnScrim`**（两主题恒白）—— 深色主题 `textOnAccent` 是黑色，压在照片上直接不可读，不能复用。
> 真机取证顺带抓出两个只有渲染才暴露的问题：`Scroll.align` 默认 `Alignment.Center` 把不足一屏的整页垂直居中（封面顶部空出白带、
> 白色工具条图标消失在白底），而第一版用 `constraintSize({minHeight:'100%'})` 修反而把封面压扁、页面失去滚动，正解是 `.align(Alignment.TopStart)`。
> **2026-09-24（CONTACT-101，FEAT-P2-001 联系人页）**：字母序 + 分组 + **右侧 A–Z 索引条**交付 —— 排序键与分段字母改由同一套
> 纯函数（`feature/contact/model/ContactsSections.ets`，对齐 Android `ContactsController.sortUsers()` 的 `Strings.clean` + 码元序 +
> 首码点大写）推出，分段随 `items` 一起进 `ContactsUiState.sections`，`ForEach` key 带上段起点，修掉「同一字母分两段时 key 撞车、
> 非拉丁名字塌进 `'#'`」两个缺陷；索引条按真实分组出字母、点一下跳到该段、当前段随滚动高亮。设备实测（模拟器）还校准出一处
> 只有真实渲染才暴露的偏差：`List.divider` 的 2vp 分隔线是**按组**占位的（单条组实测 94vp = 28 标题 + 64 行 + 2 分隔线），
> 跳转位移旧公式漏了它、越往后偏得越多，补 `groupGap` 后点 `M` 才真正齐顶。
> **2026-09-24（CONTACT-102，FEAT-P2-001 联系人页收尾）**：CONTACT-101 的遗留三项全部交付 ——
> ① 行副标题改显**电话号码**（对齐 Android `TGUser.updateStatus()` 的 `FLAG_CONTACT` 分支：联系人先显
> `Strings.formatPhone(phone_number)`，再才是 `@username` / last seen；号码格式只移植「留数字 + 补 `+`」，
> `TGPhoneFormat` 国家分组表刻意不移植），实测 `be hu` 副标题由 `@hu_bery` 变 `+447741417158`；
> ② 搜索从子串匹配改 Android 的**词首前缀**匹配（`Strings.anyWordStartsWith` + 用户名前缀，
> `ContactsController.java:901`），`e h` 不再命中 `be hu`（旧实现会命中）、`hu` 仍命中；
> ③ 索引条支持**按住上下拖连续换段**，并在条左侧浮出当前段字母气泡（`PanGesture` + `fingerList[0].localY`
> 走纯函数 `indexScrubAt` 换算；拖出上下沿夹到首/尾段；拖拽中不做补间动画才跟手；索引条高度改为「字母数 × 行高」
> 由 `Stack` 的 `Alignment.End` 居中，省掉留白换算也避免气泡把条挤偏）。
> 设备取证：真实账号只有 1 个联系人（索引条按规则不出现），故临时注入 26 字母合成分组取证拖拽与气泡后删除重建复验。
> `feature_contact` 43/43 PASS。遗留：号码未分组；`findUsernameByPrefix` 本端只比主用户名（`ContactsItem` 只存一个）。
> **2026-09-24（CHAN-SEND，FEAT-P2-002 频道权限）**：频道**发言权限真实态**交付，补掉 CHANNEL-101 的残留缺陷 ——
> 底栏旧分支把「频道成员」直接等价成「静音条」（`chatKind === 'channel' && isChannelMember → ChannelMuteBar()`），
> 结果**自己建的、有发帖权的频道也永远发不了言**。现在对齐 Android `Tdlib.canSendBasicMessage(chat)`
> （→ `canSendMessage(chat, RightId.SEND_BASIC_MESSAGES)`）读 `chat.permissions.can_send_basic_messages`：
> 有权限出正常输入栏（顺带修好「频道成员录不到语音便签」，`VoiceRecordingBar` 分支以前被静音条挡死），
> 只读频道才收成静音条；权限在同一次 `getChat` 里随 chatKind 一起回灌（先权限后 kind，避免底栏闪一下），
> 并订阅 `updateChatPermissions` 让管理员中途改权限即时生效。**一处刻意的保守方向**：`permissions` 缺失时按「可发言」处理 ——
> 读不到权限不等于没权限，收成静音条等于把人锁在输入栏外，发不出去自有 TDLib 报错条兜底。
> 设备实证：唯一真实频道（只读）日志 `can_send=false,permissions=read` 且底栏仍是 `静音`（无回归）、群聊 `can_send=true` 走输入栏；
> 「有发帖权的频道」账号内不存在，用一次性强制包取证（静音条换成 `[210,2494][892,2634]` 的 TextInput）后删除重建复验。
> `updateChatPermissions` 推送链只验证到订阅注册无报错（缺可管理频道，无法另一端改权限）。遗留两项：
> 有发帖权频道的输入栏左侧 🔔 静音位、`ChatPermissions` 其余 16 位驱动附件菜单可用性。
> **2026-09-24（CHATPROF-SHARED，FEAT-P2-002 群/频道资料页共享内容）**：共享内容分区**抽成组件并复用**到群/频道资料页 ——
> PROFILE-103 的四 Tab 原先以 `@Builder` 内联在 `ProfilePage`，PROFILE-102 要同一块内容，改成
> `feature/profile/components/SharedContentSection.ets`（`@Prop view` + 三个回调，`showGroupsTab` 决定三/四 Tab；
> 「共同群组」是私聊概念 `getGroupsInCommon`，群组/频道没有它），纯格式化助手与分页/过滤分别落
> `model/SharedContentFormat.ets`、`model/SharedContentSearch.ets`，两个资料页从此共用一份渲染。
> 真机取证抓出一个**只测逻辑测不出来的缺陷**：群资料页共享内容恒「加载失败」，根因是守卫写成 `chatId <= 0` /
> `next.chatId > 0`，把 TDLib 超级群组与频道的**负数规范 id**（实测 `-1001948393032`）判成非法会话；
> 修法统一为「未设置只看 0」，与 `feature/chat` 既有约定一致，并补 `coordinator_negativeSupergroupChatId_stillSearches` 回归用例。
> 设备实证：真实超级群组媒体首屏 20 条 + 触底自动连翻三页（游标递减）、文件 20 条带真实名与大小、链接 11 条站点卡片，
> 切 Tab 与返回后选中态和数据均保留不重复请求；私聊页四 Tab 与空态无回归。`feature_profile` 81/81 PASS。
> 遗留：群/频道页共享内容无按日期分组头；`shared_media_ok` 日志的 `placeholder=` 统计 `fileId === 0` 而非
> `localPath === null`，「下载中且缩略图未落盘」在日志上不可见。
> **2026-09-24（CHAN-SEND-2，FEAT-P2-002/005 附件菜单按发言权限实化）**：CHAN-SEND 的遗留两项处理如下 ——
> **① 「有发帖权频道输入栏左侧 🔔 静音位」判定为非缺口，删项**。读码：Android TGX 里非管理员频道成员**根本没有输入栏**，
> 底栏就是 Follow / Discuss / **ToggleMute** 三态按钮（`MessagesController.java:3162-3172`），而管理员/有发帖权成员的
> 输入栏左侧没有 🔔，静音在 ⋮ 菜单（`:4468`、`:5938`）。本端 ⋮ 与频道资料页均已有静音入口，所以「左侧 🔔」是凭空造 UI。
> **② `ChatPermissions` 其余位驱动附件菜单已落地**：`core/domain/chat/ChatSendRights.ets` 落九位发言权（一位一个
> `RightId`，映射表照 `data/TD.java:316-334` 的 `TD.checkRight`：basic/audios/documents/photos/videos/video_notes/
> voice_notes/polls/other_messages）+ 纯函数 `sendRightsFromPermissions` / `canSendAnyMedia` / `buildAttachmentEntries` /
> `canRecordVoice` / `attachmentRestrictionLabel`。放 `core/domain` 而不是 `feature/chat/model`：跨层共享且要能被
> `core_domain` 单测覆盖（先例 `chat/ChatMute.ets`）。`ChatUiState.canSendMessages: boolean` 换成整份 `sendRights`，
> 意图 `OnChatSendPermissionsChanged` 携带九位，reducer 用 `sameAs` 做到同值不动状态引用。
> **语义按原样：受限项置灰可见、点击弹限制提示，而不是消失**（Android `Tdlib.showRestriction`，受限条目保留在菜单里
> 让用户知道「有这功能但这里不让发」）；只有**八位媒体权限全禁**时才把输入栏的 📎 整个收掉（对齐 `canSendSendSomeMedia`
> 决定整行媒体入口的显隐，`basic` 不参与媒体判断）。语音按钮按 `can_send_voice_notes || can_send_video_notes` 决定，
> 禁录时点击给提示而不是起录音。权限读不到（null）仍按全放开，与 CHAN-SEND 同方向。
> 设备实证：真实数据只有「全放开」两端（群四格全亮、只读频道收成 `静音` 条 `Text [618,2529][737,2599]`），
> 中间态用一次性强制权限包取证后删除重建复验 —— 禁视频+投票时 `Video`/`Poll` 置灰（opacity .45）且点 `Video` 弹
> 「此会话不允许发送视频」；仅留 basic 时 📎 从输入栏消失、点麦克风弹「此会话不允许发送语音消息」。全程未向真实会话发送内容。
> `core_domain` 124/124（新增 8 例，含九位映射矩阵防位序写错）、`feature_chat` 281/281，三守卫 0 违规。
> 遗留：`can_send_other_messages` 尚未驱动 `EmojiBoard` 里的贴纸/GIF 页签；`can_send_audios` 本端附件菜单无「音乐」入口可置灰；
> 「可发言但禁部分媒体」的真实会话账号内不存在，受限态只有注入证据；`updateChatPermissions` 推送链仍未设备实证。

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
