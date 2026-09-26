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
| FEAT-SET-005 | 隐私和安全入口（可见范围规则） | P1 | `ui/PrivacySettingsActivity` + `ui/SettingsPrivacyKeyController.java` + `TD_getPrivacySettingRules` | getUserPrivacySettingRules, setUserPrivacySettingRules | 8 项可见范围（最后上线/手机号/头像/简介/生日/通话/入群/被搜索）读真值；点一行进详情页：主档位单选 + Premium 勾 +「总是/从不允许」例外名单，名单支持**联系人与已加入群组的成员**（双分区多选器，频道不可选），**离开页面才写回并回读确认** | — | Accepted | SELF-102 → PRIVACY-101 → PRIVACY-102 |

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
> **2026-09-24 进度**：PROFILE-103 的**共享内容 Tab 组**（媒体/文件/链接/音乐/语音/群组，含首屏自动拉取、失败态与点页签重试、共同群组行跳转聊天）已交付并在模拟器对着真实 TDLib 回包取证，
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
> 遗留（两项已在 **CHAN-SEND-3** 结案，见本节末）：~~`can_send_other_messages` 尚未驱动 `EmojiBoard` 里的贴纸/GIF 页签~~
> → 改为**发送时否决**（Android 不禁页签）；~~`can_send_audios` 本端附件菜单无「音乐」入口可置灰~~ → 确认为**误报遗留**（删项）。
> 「可发言但禁部分媒体」的真实会话账号内不存在，受限态只有注入证据；`updateChatPermissions` 推送链仍未设备实证。
> **2026-09-24（CHATPROF-DATE，FEAT-P2-002/005 共享内容日期分组）**：共享内容三个 Tab 补上**按日期分组头**，并修掉
> CHATPROF-SHARED 记的 `placeholder=` 统计口径。分组规则照 Android `SharedBaseController.needDateSectionSplitting()`
> \+ `TD.getAnchorMode` + `TD.shouldSplitDatesByMonth`：**滚动 7 天内按天**（今天 / 昨天 / 星期全名，
> `Lang.getRelativeMonth(…, SECONDS, true)`）、**上一个自然周整段并成「上周」**、**再往前按自然月切**（`LLLL yyyy` →
> 「2026年9月」），首条必给头，分组头是 inline 行而非吸顶（`ListItem.TYPE_HEADER` 走 `SettingsAdapter`）。
> 纯函数 `sharedDateAnchorKey` / `sharedDateSectionKey` / `formatSharedDateHeader` / `splitSharedDateSpans`
> 落 `feature/profile/model/SharedContentFormat.ets`（`model/` 不在架构守卫的 Kit-free 范围内，且只用 `Date` 本地数学、不引 `intl`）。
> **关键一处不是「加个 UI」**：条目原先根本没带日期 —— 日期在 `Message.date` 上而解析器只收 `content`，整条链路丢掉，
> 所以三个条目类各加 `date`（末位可选参、老调用点不破）、`sharedMediaItemOf` / `linkItemOf` 补形参、searcher 传
> `found.messages[i].date`，并且 `withSharedMediaPath` 换真图时必须把 `date` 原样带过去，否则缩略图一回灌分组头就跳位（有用例守住）。
> 共同群组 Tab 不分段（对齐 `SharedChatsController.needDateSectionSplitting() = false`）。两处刻意偏离写进注释：周序号用「绝对周」
> 替代 Java 的 `WEEK_OF_YEAR + years == 0`（年末跨年会算错），并保留「本周的周日算上周」这一 Android 行为。
> 日志口径：`shared_media_ok` 的 `placeholder=` 原来数 `fileId === 0`，「fileId 有值但缩略图还没落盘」的下载中态根本不计，
> 改成 `localPath === null`。设备实证（真实数据、无需注入）：群资料页媒体 Tab 依次出 `星期一` / `上周` / `2026年9月` 三段宫格
> （`date_media.png`），文件 Tab 出 `2026年9月` + `Bcore.zip` 行、链接 Tab 出 `上周`；私聊资料页四 Tab 同样出
> `星期一` / `上周` 且群组 Tab 无头；日志 `page=20,kept=20,placeholder=20` 即新口径生效的直接证据。
> `feature_profile` 92/92 PASS（新增 10 例日期分段 + 1 例协调器端日期贯通）。遗留：共享内容仍无「音乐 / 语音」两个 Tab
> （TGX `SharedCommonController` 有 audio、voiceNote 两档）。
> **同日追加（SHARED-AUDIO，FEAT-P2-002/006 共享内容音乐与语音 Tab）**：那条遗留清掉 —— 两个资料页的共享内容补成
> **五个内容 Tab**（媒体/文件/链接/音乐/语音，私聊再多一个「群组」共六个），Tab 编号从 `model/SharedContentSearch.ets`
> 单点导出（`SHARED_TAB_*`），reducer、组件、用例都按常量走，不再各处写魔法数字；顺序照 Android
> `ProfileController.getFiltersOrder()`（PhotoAndVideo → Document → Url → Audio →（Animation 本端无）→ VoiceNote）。
> 行文案照 `TD.getTitle` / `TD.getSubtitle`：音乐标题 = `audio.title` 否则文件名去扩展名，副标题三条分支
> `performer - title` / 时长 / 文件大小；语音标题 = 发送者昵称，昵称没到时**自己发的显「我」**（直接用 `Message.is_outgoing`，
> 不必等 getMe），其余留空由组件回落「语音消息」—— 不印裸 user id。日期不重复写进副标题（CHATPROF-DATE 的段头已经说了）。
> 播放复用 VOICE-101 的 `AudioPlayerPort`：装配层把**同一个** `HarmonyAudioPlayerAdapter` 注入聊天页与两个资料页
> （一个 AVPlayer = 一条音频流，对齐 Android 的单例 AudioPlayer），切 Tab、点第二行、页面 destroy 都会 stop。
> **一处刻意的不对称**：解析阶段音频/语音走只查缓存的 `audioLocalPathOf`，媒体缩略图走带订阅的 `localPathOf`。
> 前者若复用后者，翻一次 Tab 会给整页 20 条音频同时下 —— 改成点按才下载，落盘后由 `onSharedFileReady` 续播等待中的 fileId。
> 设备实证（模拟器 127.0.0.1:5555，真实数据、未发送任何内容）：私聊资料页六 Tab 齐、语音 Tab 出 `我 / 0:25 · 48.6 KB`
> 与 `我 / 0:03 · 45 B` 两行并带 `星期一` 段头；点播放 → hilog `initialized → prepared → playing → completed`（25 秒整），
> 播放中该行圆形按钮翻成实心 accent + ⏸、另一行保持灰底 ▶；音乐 Tab 空态「暂无音乐文件」+ 引导文案；
> 群资料页（El CLUB）只有五个 Tab（无「群组」）且语音/音乐均走空态。`feature_profile` **105/105 PASS**
> （新增 `SharedAudioRows.test.ets` 5 例纯函数 + 协调器端 3 例：过滤器选型、行映射、点按下载→回灌→续播）。
> 遗留：语音行昵称晚到不回灌（下一页起才有名字）。
> **同日追加（AUDIO-BG-101，FEAT-P2-006 后台音频与 AVSession 播控）**：SHARED-AUDIO 记的那条遗留清掉。
> 「退后台不断音」在 HarmonyOS 上不是一个 API，而是两个必须成对的：AVSession（锁屏/控制中心播控卡片 + 系统通知）与
> `AUDIO_PLAYBACK` 长时任务（进程保活）。自 API 20 起，不接 AVSession 的音频长时任务会被系统直接回收
> （`SYSTEM_CANCEL_AUDIO_PLAYBACK_NOT_USE_AVSESSION`），所以 `platform/ports/AudioSessionPort.ets` 把两者收进一份契约
> （`AudioSessionPort` + `ContinuousTaskPort`），生命周期交给 entry 侧一个 Kit-free 的 `AudioSessionOrchestrator`：
> 首次播放 activate + 申请任务（并发 activate 合并成一次）、换曲只换元数据、播放态变化立刻上报而位置按 1s 节流
> （AVPlayer 的 `timeUpdate` 约 200ms 一次，逐条转给会话会把 IPC 打满）、stop / 页面 destroy 时 deactivate + 释放任务成对收尾。
> Kit 调用只留在 `HarmonyAVSessionAdapter` / `HarmonyContinuousTaskAdapter` 两个薄适配器里，由装配层 `pages/Index.ets`
> 注入 UIAbilityContext（沿用 VOICE-101 录音适配器的做法）。
> **元数据才是这一包的产品活**：锁屏卡片不能印裸落盘文件名 —— `audioSessionMetadata()` 把语音行映射成
> 「标题=发送者（空则「语音消息」）、副标题=会话名」，音乐行映射成「标题=`audio.title`、副标题=performer」，
> 时长秒→毫秒（AVSession 的 `elapsedTime`/`duration` 一律按毫秒计，别自作主张换算）；聊天页语音给「语音消息 / 会话标题」。
> **两处按文档收敛的取舍**：① 只注册 play/pause/stop/seek 四个监听 —— 新 SDK 已删 `availableCommands`，
> 卡片上有哪些键完全由注册了哪些回调决定，没有播放队列就不画上下曲；② `completed` 不销毁会话，卡片停在末尾，
> 锁屏按 ▶ 走 `seek(0)+resume` 重播，只有显式 stop / 页面 destroy 才整体收摊。
> **设备实测踩到的真缺陷**：`startBackgroundRunning` 报 `9800005 The sequence of backgroundTaskModes does not match the
> backgroundTaskSubmodes` —— 主/子类型必须按官方对照表配对：`MODE_AUDIO_PLAYBACK` 只配 `SUBMODE_NORMAL_NOTIFICATION`，
> `SUBMODE_AVSESSION_AUDIO_PLAYBACK` 挂在 `MODE_AV_PLAYBACK_AND_RECORD(12)` 下。改对后 `continuous task started: taskId=1`。
> 取证（模拟器 127.0.0.1:5555，真实数据、未发送内容）：播 0:25 语音 → `AVSession activated: sessionId=…` + 任务申请成功；
> 按 Home 退后台后 `playing 11:42:24 → completed 11:42:36` 整段在后台跑完；控制中心
> `control_center_media_card` 出现 `MCC_Text_title=语音消息 / MCC_Text_artist=be hu`（资料页语音行是 `我 / be hu`），
> 点卡片 ▶ 直接驱动播放器 `paused → playing`；离开页面 `stopped → AVSession deactivated and destroyed →
> continuous task stopped: taskId=1`，再播一次拿到新的 `taskId=2`（成对申请/释放的直接证据）。
> `module.json5` 补 `backgroundModes: ["audioPlayback"]` 与 `ohos.permission.KEEP_BACKGROUND_RUNNING`（normal 级，无需 reason/usedScene）。
> 测试：`entry` **41/41 PASS**（新增 `AudioSessionOrchestrator.test.ets` 12 例：activate 只一次、并发合并、1s 节流、
> 播放态翻转穿透节流、release 幂等、会话不可用时既不申请任务也不上报、命令路由、文件名兜底）、`platform_ports` 47/47、
> `feature_profile` **106/106**（+1 例元数据映射）、`feature_chat` 281/281；三守卫 0 违规。
> 遗留：真锁屏界面未取证（模拟器无锁屏，验到的是同一张 AVSession 控制中心卡片）；会话进度只上报、不回驱动应用内进度条。
> **同日追加（PROXY-101，FEAT-P2-007 代理半边）**：设置页「代理」行从假常量改成真实态 + 新增整屏 `ProxySubPage`。
> **建模先跟 TDLib 对齐**：「哪个代理生效」在协议里不是一个 active id 字段，而是每条 `AddedProxy.is_enabled`，
> 所以「不使用代理」不是第四条代理，而是**全部 `is_enabled` 为 false 时的呈现态** —— 用 `PROXY_NONE_ID = 0` 哨兵行表达，
> 点它发 `disableProxy()`；点普通行只在「当前未生效」时发 `enableProxy(id)`（已生效或未知 id 一律 no-op，避免反复重连）。
> **一条刻意的保守**：所有写操作（add/edit/enable/disable/remove）成功后**重新 `getProxies` 回读，不做乐观更新** ——
> 单选态只有 TDLib 知道真相（启用失败它自己回滚），行内转圈用单一忙碌令牌 `updatingProxyId`
> （`null` 空闲 / `0` 无代理行 / `-1` 新表单保存中 / 其余为行 id）。
> DTO 三处坑写进注释：生成类 `ProxyValue` 的类型字段叫 `type_`（`type` 被判别器占了）、未知 `@type` 落 `TdUnknownObject`、
> `proxyItemFromAdded` 对 `proxy === null` / 空 server / `type_ === null` / 未知判别器**返回 null 丢行**而不是渲染半截。
> 表单按 kind 裁字段：mtproto 只要十六进制 secret 并丢掉 username/password/httpOnly，socks5/http 反之；
> **密码不 trim**（两端空格可能是口令本身，trim 会把代理写成不可用），server 与 username 才 trim。
> **两个只有真跑设备才会暴露的缺陷**：① ArkUI 的 `TextInput` 在**挂载时就以初值回调一次 `onChange`**，
> 于是刚打开的添加表单顶着一行红字「Server address required」—— 改成 `markTouched(value)` 只在收到非空值时才算「碰过」；
> ② 行标题原样拼「类型名 + 地址:端口」，1256px 屏上被挤成 `SOCKS5 …`，地址完全看不见 ——
> `proxyTitle` 改成「没写备注就直接显地址:端口」，类型名让给副标题。
> 设备取证（模拟器 127.0.0.1:5555，真实 TDLib 往返）：`getProxies` 空列表 → 设置行副标题 `Tap to set up`；
> 添加 socks5 → 行出现且副标题变标题；选该行 → radio 落到行、设置行副标题同步；编辑 → 「Edit Proxy」+ Save + Enable 回填 ON；
> 「不使用代理」→ 生效态收回；删除 → 确认对话框 → 回到空态。校验反向证据两例（port `70000`、`700001080` 均报
> 「Port must be 1-65535」）。**收尾已恢复账号原状**：测试代理删除、无代理保持选中，设置行回到 `Tap to set up`。
> 测试：`feature_settings` **145/145 PASS**（新增 `ProxySettings.test.ets` 15 例纯模型 + reducer 17 例意图/效果 +
> `SettingsSection` 卡位 3 处），三守卫 0 违规。
> 遗留：代理 ping 延迟副标题与连接态（现已交付，见下方 PROXY-102 追加段）、
> "Switch automatically"、通话是否走代理（结案：无 VoIP，无对象）、`tg://proxy` 分享链接的确认弹窗（`openProxyAlert`）、扫码导入、
> 多端改代理的实时推送（本端只订阅不到 `updateProxy`，结案：1.8.67 schema 无此类型，只能靠回读）；FEAT-P2-007 的**下载与自动缓存策略半边**当时未动（现已交付，见下方 AUTODL-101 追加段）。
> **同日追加（AUTODL-101，FEAT-P2-007 下载与自动缓存策略半边）**：设置页新增整屏「自动媒体下载」子页，
> 聊天页 7 类入站媒体全部接上下载门，策略按账号持久化。
> **存储形状照 TGX 而不是照 UI**：Android 把这套策略存成一个整数 `settings_autodownload`
> （`TdlibFilesManager.java:990-998`）—— 7 个媒体标志位各自左移到 private/groups/channels 三段，
> 即「一个整数 = 三个分区 × 七类勾选」。本端 `core/domain/media/AutoDownloadPolicy.ets` 保持同一形状：
> `toStorageValues()` / `fromStorageValues()` 出 3 个掩码，兜底默认与 Android 逐位一致
> （照片 / 语音 / 视频便签 / 动图开，视频 / 文件 / 音乐关）。
> **为什么在 `core/domain`**：写策略的是设置页、读策略的是聊天页，`feature/*` 之间不许互相 import（分层红线），
> 所以策略与判定纯函数下沉共享（同 `ChatMute` / `ChatSendRights` 先例）。
> **尺寸闸门是产品判断**：视频 / 文件 / 音乐单条可到几百 MB，勾了自动下载不该让 2GB 附件在打开会话时悄悄开跑 ——
> 原先写死在聊天页的 10MB 收成 `isAutoDownloadSizeAllowed()`，且**服务端没给尺寸时放行**（不能因 `size` 缺省把用户勾了的类判死）。
> （该固定闸门在 AUTODL-103 已换成按网络档可配，见下方追加段。）
> **未知分区不阻塞**：`canAutoDownloadMedia()` 对 `private/group/channel` 之外的值或没设过策略返回放行 ——
> 策略是「省流量的额外约束」，不该变成「读不到就什么都不下」。
> 持久化按账号隔离：键 = `autodownload_<accountKey>:<scope>`，走 `@ohos.data.preferences` 同步读
> （`PersistentStorage.persistProp` 在本 SDK 上恢复不可靠），适配器落 `entry`；`current()` 只回缓存、
> 每账号每进程读一次盘（每条消息解析附件都要问一次策略，每条重算三键是纯浪费），`save()` 立刻刷新缓存 ——
> 设置页刚勾完，还开着的聊天页下一次同步就按新策略放行。
> 贴纸、头像、缩略图**不受策略管**（Android 同样无条件拉缩略图，那是占位渲染的必要材料）；
> 用户点下载按钮、点开播放器、自己发出的出站上传一律不走门 —— 那是请求，不是自动下载。
> **只有真跑设备才会暴露的缺陷**：`chatKind` 由 `getChat` 异步回包解析，而首轮投影通常早于它，
> 「未知分区即放行」等于**冷进会话的那一刻门是敞开的**，用户刚把某类关掉照样整屏下载 ——
> 改成 `canAutoDownload()` 在分区未解析时一律不放行，等 `chat_kind_resolved` 后的 `scheduleSyncFromProjection()` 再按真实分区判定。
> 设备取证（模拟器 127.0.0.1:5555，真实 TDLib，全程未发送内容）：拿同一条 93 B 文档做 A/B ——
> 私聊「文件」关（默认）+ 清理缓存 → 重进会话气泡仍是蓝底下载箭头、零下载请求；
> 勾上「文件」→ 同一气泡重进即变灰底已下载图标。设置侧：分区摘要随勾选实时写穿、
> 三类不一致时设置行显 `Varies by chat type`、强杀重开策略原样回读。
> **收尾已还原账号状态**：动过的私聊「视频」「文件」与频道「照片」全部改回，三分区摘要回到默认
> `Photos · Voice message · Video message · GIFs`，缓存回到 2.7 MB / 73 files 基线。
> 测试：`core_domain` **138/138 PASS**（位序矩阵、掩码往返、尺寸闸门两条边界、勾选与尺寸双条件）、
> `feature_settings` **166/166 PASS**（reducer 11 例 + `AutoDownloadRows` 9 例纯摘要 + `SettingsSection` 卡位）、
> `feature_chat` **281/281**；三守卫 0 违规。
> 遗留：省流量与网络类型条件（Android `DATASAVER_FLAG_ENABLED / _WHEN_MOBILE / _WHEN_ROAMING`，本端不分 Wi-Fi 与移动网络）、
> 10MB 上限不可配、没有按会话单独覆盖的入口、策略变更不追溯已下载内容（清理仍归「存储与缓存」那包）。
> FEAT-P2-007 的两半边（代理 + 下载与自动缓存策略）至此均已落地。
> **同日追加（MEDIA-VIEWER-101，FEAT-P2-006 完整媒体查看器剩余项）**：查看器从「能放大的一张缩略图」补成「能看原图」。
> **换档是这包的核心，不是缩放**：气泡沿用 `chooseDisplaySize()` 的 320–960px 档省流量，查看器再放大就是糊的；
> `ChatCoordinator.chooseFullSize()` 按**面积最大**取档（明确不信 `sizes` 下标，TDLib 不保证 `#big` 在末位），
> 只有大档 `fileId` 与显示档不同才构造 `MediaFullSource`，`ensureActiveViewerTier()` 在 `openMediaViewer` /
> `changeViewerIndex` 之后用**显式动作**优先级 32 拉大档 —— AUTODL-101 那道门管的是「没人看就偷偷下」，
> 用户点开查看器是请求，不该被门挡住。
> **换档必须让 ArkUI 看见**：`ForEach` 键不变 ⇒ 子节点不重建 ⇒ 大档下完画面不刷新。
> `mediaViewerItemKey()` 把 `localPath / isDownloaded / progress / 大档签名` 编进键，同时保留 `fileId`
> 让图集里共用 `messageId` 的兄弟项不撞键。
> **缩放与钳位是纯数学，全部下沉 `model/ViewerTransform.ets`**：1:1 像素档 = 屏幕像素 / 内容 vp，
> 密度取 `display.getDefaultDisplaySync().densityPixels`（`vp2px` 已 deprecated）；上限由真实像素推导
> （`VIEWER_NATIVE_HEADROOM` 留 1.5 倍余量、`VIEWER_MAX_SCALE_CAP` 封顶 8），不是拍脑袋常数；
> 偏移钳位 `(内容×scale − 视口)/2`，**某轴短于视口就把该轴钉 0**，放大后拖不出黑边；长宽比 ≥ 2 走长图路径。
> **两个只有真跑设备才会暴露的缺陷**：① MEDIA-103 的查看器根 `Stack` 用了 `HitTestMode.Block` ——
> 按 SDK 定义它连**子节点**一起挡掉，整个查看器点不动、捏不动、翻页不动，只剩系统 Back 能退，改 `Default`
> （挡住下层聊天页已经够用）；② 给 `Swiper` 加的 `priorityGesture` 把横滑翻页抢死，
> `onGestureJudgeBegin` 必须带 `!info.isSystemGesture` —— `Swiper` 内置滑动同样是 `PAN_GESTURE`
> （只是 `isSystemGesture` 为 true），一起判掉等于把翻页判死。
> 设备取证（模拟器 127.0.0.1:5555，真实 TDLib，全程只读未发送）：`viewer_tiers fileId=49,display=320x160,
> full=2560x1280#52,rendered=display` → 1.6 s 后 `media_download_completed fileId=52` → 翻走再翻回同一项
> `rendered=full`，2560×1280 横幅清晰可辨（另一样本 `display=320x100,full=1264x394` 的 3.2:1 横幅，
> 显示档只有 320px 宽，正是这包存在的理由）；缩放态拖拽按日志数值复核钳位：视口 `358.9x721.7`vp、内容
> `358.9x111.9`vp、`offsetX in=-255.7 → out=-179.4` 恰为 `(358.9×2−358.9)/2`，y 轴因内容短于视口被钉 0；
> 未放大态 `38 / 39 ↔ 39 / 39` 双向翻页正常，单击隐藏系统栏、双击 1:1、再双击回贴合。
> **摘掉临时日志重签重装后再跑一遍出厂包**：开图 → 翻页 → 双击放大 → 拖拽 → 双击还原 → 关闭，四帧互不相同且末帧回到贴合。
> 测试：`feature_chat` **302/302 PASS**（新增 `ViewerTransform.test.ets` 17 例：像素档换算、上限封顶、
> `clampViewerOffset` 短轴钉零、`viewerOffsetForZoom` 焦点保持、`isTallImage` 阈值；`MediaViewer` +3 例键唯一性、
> `MediaAttachment` +1 例 `fullSource` 经 `copyWith` 往返）；三守卫 0 违规。
> 遗留：`PinchGesture` 无法用 `uitest` 注入，捏合数学只有单测覆盖（设备侧靠双击档位验证）；
> 视频与 GIF 在查看器里仍是静态首帧；`HitTestMode.Block` 这类「浮层吃掉整屏命中」的隐患还没在其他浮层系统排查。
>
> **同日追加（MEDIA-VIEWER-102，FEAT-P2-006 收官）**：查看器里的视频与 GIF 从「静态首帧」变成播放器，动图容器判定换轨。
> **容器判定信 mime 不信文件名子串**：旧写法 `fileName.indexOf('.mp4') >= 0` 撞上 TDLib 的 GIF 转码产物
> `2176acbf..._hq.gif.mp4` —— 子串判定把 GIF 认成视频、真视频反被当成动图，两边一起错。
> `model/ViewerPlayback.ets` 的 `motionContainerOf()` 先读 `animation.mime_type` / `video.mime_type`
> （`image/gif` 精确匹配、`video/` 前缀匹配），mime 缺失才退到 `file_name`、再退到 `localPath` 的**尾缀**
> （`lastIndexOf('.')` 取最后一段，所以 `abc.gif.mp4` 是 `mp4`、`video.mp4.notes.txt` 是未知）；
> `ChatCoordinator` 为此把 `mime_type` / `file_name` / `file.size` 一路送进 `MediaAttachment`。
> **单播放器所有权**：`Swiper` 缓存相邻页，每页都挂 `Video({autoPlay:true})` 就是几条音轨同时响。
> 「是不是当前页」因此必须进 `ForEach` 的键 —— `mediaViewerItemKey(item, isActive)` 只给需要播放器的项追加
> `|player` / `|poster`，照片页保持稳定的键免得翻页时重新解码大图。四档渲染：`gif`（`Image` 原生逐帧，
> 不起播放器、天然无声循环）/ `player`（视频带控制条，动图静音循环）/ `poster`（缓存页只画封面）/
> `download`（本地无文件时出 `Download Video` / `Download GIF`；出站消息在 `isDownloaded` 之前靠
> `isUploading` 就能播）。缩放、拖拽、双击只对照片页开放，视频页手势连捏合一起在 `onGestureJudgeBegin` 判死，
> 热区留给播放器自己的控制条。
> **两个只有真跑设备才看得见的命中缺陷**：① 点击 / 双击挂在 `Swiper` 的 `priorityGesture` 上，而 priorityGesture
> 按 SDK 语义连**子节点**识别器一起压 —— `Video` 的播放键与进度条、`download` 档的下载按钮永远点不到
> （实测点播放键只翻工具栏、进度恒 `0.000000`）；点击改挂普通 `.gesture`（祖先识别器，子节点优先命中）后归位。
> ② 工具栏浮层根 `Column` 用 `HitTestMode.Transparent`（语义是「不阻塞兄弟**和祖先**的触摸测试」），
> 下层那台全屏 `Swiper` 于是和返回键抢同一次点击，`onClick` 永不派发、查看器关不掉；返回键热区加
> `HitTestMode.Block` 截断祖先链才解决。附带一条取证教训：查看器顶栏有 36vp 顶部内边距，返回键真实热区是
> `[28,262][182,416]`，沿用聊天页的 `(105,241)` 会点到栏外透传区，把好的修复读成没生效。
> 设备取证（模拟器 127.0.0.1:5555，真实 TDLib，全程只读未发送）：`dumpLayout` 里 `Video` 节点的 `text` 即其 src，
> 可直接数播放器 —— 视频页 `video:['VID_20260823_100342.mp4'], swiper:1`，右滑回照片页 `video:[]`（缓存页降级为封面、
> 播放器销毁），再滑回来重建为 1，末页继续左滑不越界；返回键关闭后 `swiper:0`、聊天列表恢复。
> **视频画面本身在这台模拟器上取不到，根因不是接线**：`media_service` 日志
> `KPI-TRACE: PlayerServer SetSource in(fd), fd: 14, offset: 0, size: 13791948` 证明 `Video` 已把
> `file://<bundleName>/data/storage/el2/base/haps/entry/files/tdlib/files/videos/....mp4` 解析成 fd 并读到真实大小
> （沙盒 URI 形态正确、文件可读），随后 `AVCodecListImpl: Get capability failed, mime: video/hevc` →
> `DecoderSurfaceFilter: Video size 1920x1080 not supported by both hw and sw decoder` →
> `onError 331350546 VID_DEC_ERR-unsupport interface`：这条 TDLib 视频是 H.265，模拟器镜像没带 HEVC 解码器，
> 而账号里可翻到的会话没有 H.264 视频消息可替换。真机可播；本端取证停在解码器边界。
> 测试：`feature_chat` **321/321 PASS**（新增 `ViewerPlayback.test.ets` 17 例覆盖 mime 优先级、尾缀回退、
> `needsPlayer` / `rendersPlayer` / `motionRender` 四档与出站态、`zoomable` 只给照片；`MediaViewer` +2 例键位）；
> 三守卫 0 违规。FEAT-P2-006（完整媒体查看器、后台音频、AVSession）至此收官。
> 遗留：HEVC 视频帧画面待真机或有 H.264 素材时复核；`gif` 档只有单测覆盖（本账号会话里没有 GIF 消息可点）；
> 视频页双击会翻一次工具栏（`Video` 控制条与祖先点击的仲裁待真机复核）。
> **追加（AUTODL-102，FEAT-P2-007 省流量半边）**：自动下载补上「省流量」这一维 —— 主开关 + 自动开启两档 + 聊天页硬否决。
> **否决排在门的第一句，照 Android 的求值顺序**：`canAutomaticallyDownloadFromServer()`（`TdlibFilesManager.java:1352-1411`）
> 第一行就是 `if (isDataSaverActive()) return false;`，在会话类型、媒体类型、尺寸上限**全部之前**；本端
> `ChatCoordinator.canAutoDownload()` 同构 —— 否则「省流量开着但媒体还是下了」会被解释成「你是不是又勾回去了」。
> **存储照 `settings_datasaver` 而不是照 UI**：一个整数三位（`:1000-1005`）`ENABLED=1` / `WHEN_MOBILE=1<<1` /
> `WHEN_ROAMING=1<<2`，默认**只勾漫游**（`:1192`），键 = `datasaver_<accountKey>`。Android 另外三位是 VoIP 省流量，
> 本端没有 VoIP 通话，**刻意不建模**（建了就是一排永远点不亮的死开关）；系统级省流量那条分支同样不移植 ——
> HarmonyOS 没给应用暴露系统数据节省状态（`connection.NetCap` 连 `NOT_ROAMING` 都没有），硬做只能读到恒 false。
> **漫游只能从电话侧异步拿**：`radio.getNetworkState().isRoaming`（权限 `GET_NETWORK_INFO`、syscap 用 `canIUse` 守卫、
> 异常回落 false），且 `mapCapabilities(raw, roaming)` 里 **`roaming && transport === 'cellular'` 才置位** ——
> 电话侧漫游态与「默认网络是蜂窝」是两次独立读取，Wi-Fi 挂着时读到 `true` 是陈旧值，照抄就会在用户连 Wi-Fi
> 时按「漫游」把自动下载判死；`roaming` 同时进 `sameSnapshot` 去重，否则进/出漫游根本不派发。
> **门读缓存快照，不自己订阅网络**：`ConnectivityKitSource` 一实例只服务一个订阅（SDK 无 `off`，`unregister` 摘全部），
> `ConnectivityAdapter.current()` 每次两趟同步 IPC，而聊天页每条附件都要问一次策略 —— 所以快照缓存在
> `LifecycleCoordinator`（全应用唯一网络观察者）的 `lastNetworkSnapshot`。**兜底方向是产品判断**：
> 读不到漫游按 `'mobile'`（只勾「移动网络」的用户仍被挡住，宁保守不越权）；连快照都没有按 `'none'`
> （只有主开关能否决），Wi-Fi 上已打开的聊天页不会因为网络信息晚到而整屏不下。
> 设备 A/B（模拟器 127.0.0.1:5555，真实 TDLib，全程只读未发送）：先清媒体缓存把状态归零，再进同一个群翻到
> 同一张海报照片 —— **Data Saver ON**：气泡仍是「缩略图 + 深色圆白色下载箭头」（显示档没下）；
> **OFF** 后重进同一会话：badge 消失、显示档自动落盘。唯一变量就是那一位。
> 测试：`core_domain` **138/138**（新增 `DataSaver.test.ets` 9 例，含 **8 档设置 × 5 种网络的否决真值表**、
> 非法掩码回落、`withFlag` 不可变、「Wi-Fi 上读到漫游」→ `wifi`）、`feature_settings` **178/178**（reducer 9 例含
> `dataSaverAndAutoDownload_doNotClobberEachOther` + `DataSaverRows` 3 例）、`platform_network` **19/19**、
> `entry` **42/42**（快照缓存生命周期）、`feature_chat` **321/321** 无回归；三守卫 0 违规。
> 遗留：provider 那两行 glue 无 coordinator 级单测（要伪造整条 `getMessages` 回包链，改由设备 A/B 覆盖）、
> 「自动开启」两档缺蜂窝/漫游可取证环境、省流量生效时不追溯取消已在途下载、per-network 尺寸上限
> （Android `settings_limit_*`）另立一包。
> **追加（AUTODL-103，FEAT-P2-007 按网络类型的下载限制）**：补上 AUTODL-102 遗留的那一包 ——
> 三档网络各自的「尺寸上限 + 不下载哪些类型」，插在聊天页下载门里 Android 的那个位置。
> **刻意不照抄 Android 的字节打包**：TGX 把一档网络的两个字段挤进一个 int —— `(exclude << 24) | size`
> （`TdlibFilesManager.java:1133`），存进 `settings_limit_wifi|mobile|roaming` 三个按账号键。本端一个账号
> × 一档网络 × 一个字段 = 一个键，共 3 × 2 = 6 个键（`medialimit_<accountKey>:<network>:<field>`）：
> 打包 int 唯一的收益是少两个键，代价是任何一个字段读脏就会连带毁掉另一格，而这里没有跨字段不变式要守。
> **门里的顺序照 Android 的求值顺序**：`canAutomaticallyDownloadFromServer()` 在会话类型之后、
> 分区勾选之前判 `settings_limit_*`，所以本端 `canAutoDownload()` 是
> 省流量硬否决 → 分区未解析不放行 → `isMediaWithinDownloadLimits(当前网络档)` → `canAutoDownloadMedia(分区勾选)`。
> **上限存的是「档位码」不是字节**：`DOWNLOAD_LIMIT_OPTIONS = [1,2,3,4,5,6,0]`（15/5/… 与 Android 的
> `MediaFileSource` 单选同序，`0` = 无上限末位），`downloadLimitBytes(code)` 才换算成字节，
> **未知码 → 无上限** —— 档位码读脏了宁可放行，不能把用户勾了的类判死。
> 尺寸缺省同样放行：`sizeBytes <= 0` 或非有限值（服务端还没给尺寸）不参与闸门，与 AUTODL-101 口径一致。
> **网络档复用 AUTODL-102 的快照映射，不新造一套**：`dataSaverNetworkOfSnapshot` 里
> `wifi|ethernet → 'wifi'`、蜂窝（含漫游）→ `roaming|mobile`，其余与读不到 → `'mobile'`；
> `DownloadLimitsByNetwork.of()` 对 `'other'/'none'` 同样回落移动档 —— 兜底方向是「宁保守不越权」。
> **排除位掩码与 AUTODL-101 同序**：`AUTO_DOWNLOAD_KINDS` 数组序取位，`fromStorageValues()` 里 `& 0x7f` 截断，
> 脏高位直接丢弃，所以偏好文件被改坏也不会多出第七类以外的幽灵勾选。
> **副标题四态照 `mediaDownloadDescription()`（`TdlibFilesManager.java:1413-1444`）**：全排除 → `Any media`；
> 有上限 → `Any media exceeding {0}`；无上限且无排除 → `No restrictions`；随后 `, ` 拼**裸类型名**
> （`Photos`，不是面板行标题那个 `No Photos`）—— 同一批词在两个位置是两种语法角色，翻译表分开登记。
> **面板与行的顺序都照 TGX，不按直觉**：`SettingsDataController.java:520-568` 的对话框是 7 个 `No …` 勾选**在前**、
> 尺寸单选在后；`:594-604` 三行是移动网络 → Wi-Fi → 漫游；`:1381` 让这三行排在三个分区卡**之前** ——
> 「先按网络挡一道，再谈分区勾了什么」正是门里的顺序，界面顺序与求值顺序一致用户才推得出来。
> 设备 A/B（模拟器 127.0.0.1:5555，真实 TDLib，全程只读未发送）：**唯一变量是 Wi-Fi 档上限** ——
> 频道分区勾上「视频」后，同一条 0:25 视频在 `1 MB` 档仍是深色遮罩 + 下载箭头，改成 `No limit` 重进即变播放三角（已自动下完）。
> 照片档不适合做这组 A/B：本账号会话里的照片在 AUTODL-101/102 取证时就已落盘，气泡直接渲染缓存、看不出闸门效果，
> 而视频是首次放行、状态干净。**收尾已还原账号原状**：三档回到默认（移动 15 MB / Wi-Fi 50 MB / 漫游 5 MB、排除全 0），
> 三分区摘要回到 `Photos · Voice message · Video message · GIFs`，设备偏好文件逐项核对一致。
> 测试：`core_domain` **157/157**（新增 `MediaDownloadLimits.test.ets` 13 例：档位码表与未知码回落、
> 默认 15/50/5 MB、`'other'/'none' → mobile`、`withNetwork` 只改一档、排除位序与 6 值存储往返、
> 脏值按档分别回落 + 掩码截断、`<=` 边界含等号、排除无视尺寸一票否决、尺寸缺省放行）、
> `feature_settings` **198/198**（新增 `DownloadLimitRows.test.ets` 8 例副标题四态 + reducer 10 例：
> 未加载时 no-op、同值 no-op、只写目标档、两字段互不覆盖、关子页不清已加载限制）；
> `feature_chat` **321/321**、`entry` **42/42** 无回归；三守卫 0 违规。
> 顺带修掉一个既有缺口：`core/domain/src/test/List.test.ets` 里 `dataSaverTest` 只 import 未注册，
> AUTODL-102 的 9 个用例其实从没跑过 —— 现已挂上。
> 遗留：移动网络与漫游两档缺可取证环境（模拟器只有以太网，恰好让 Wi-Fi 档成为设备上的活档）、
> 限制变更不追溯已在途下载、没有「按会话单独覆盖」的入口、Android 的「全部排除」快捷（本端只做逐类勾选，
> 常量 `DOWNLOAD_EXCLUDE_ALL_KINDS` 已备但没有对应 UI）。
> **同日追加（PROXY-102，FEAT-P2-007 代理半边的最后一项）**：代理行从「只有一个 radio 的清单」变成会报延迟和连接态的行 ——
> 每行一次 `pingProxy` + 全局一条 `updateConnectionState`，PROXY-101 记的第一条遗留清掉。
> **直连可证，靠的是 TDLib 的一个语义而不是代码技巧**：`pingProxy proxy:proxy = Seconds` 里
> **空 `proxy` 载荷探测的是直连通路**，所以「不使用代理」这一行根本不需要先配一个能用的代理才有得显 ——
> 本端把 `PROXY_NONE_ID = 0` 直接映射成「发空负载」，`pingRequest()` 对 0 号行返回 `null` 就是这个意思。
> 也正因为这条，这一整包的设备取证**在账号里零代理的状态下就完成了**，没有为了让界面动起来而往账号里留东西。
> **探测数据放在 `SettingsUiState` 的侧表里，不放进 `ProxyItem`**：`proxyPingMs: Map<number, number>` + `proxyConnection`。
> 两个理由：① PROXY-101 定的纪律是「每次写操作后重新 `getProxies` 回读」，行对象整批重建，把易变的探测值挂在行上
> 就等于每轮回读都把刚测出来的数丢掉；② 无代理行不是 `ProxyItem`（它是哨兵），侧表天然能容纳 id 0。
> 探测表写入仍是不可变替换，并按当前行集**剪枝**（`proxiesLoaded_prunesDeadRowsAndKeepsLiveProbeResults`）——
> 删掉的代理留下的幽灵延迟会让「重新添加同一条」开局显示一个不属于它的数。
> **三值哨兵，负数区互不重叠**：`PROXY_PING_UNSET = -1`（还没测）/ `LOADING = -2`（在途）/ `FAILED = -3`（测了且失败）。
> 不用 `undefined`/`0` 是因为 `0 ms` 是一个合法的邻近网络值，而「没有这一行」和「这一行失败」在界面上必须是两句话；
> 秒 → 毫秒取 `Math.round(seconds * 1000)`，非有限值或 `<= 0` 一律判 `FAILED` —— TDLib 返回 0 秒就是失败，不是「零延迟」。
> **行的状态句子是三个因子共同决定的，不能压成一个**：`proxyRowIsEffective(items, item)`（哪条承载了这条连接）、
> `connection`（`updateConnectionState` 的 5 个判别式）、`pingMs`（这一行自己的探测）。
> 刻意把「非生效行」和「连接态未知」分开：`proxyConnection` 初始 `'unknown'`，若拿它当「你不是当前通路」的依据，
> 那么**在第一条连接态推送到来之前**，所有行都会被误判成「不可用」并显出一个用户从没见过的句子；
> 反过来生效行的句子优先跟连接态（`Connecting...` / `Waiting for network...` / `Updating...`），
> 只有 `'ready'` 与 `'unknown'` 才把探测值端上来（`Connected · 226 ms` / `Available · 226 ms` / `Error`）。
> 非生效行永远只有探测结果可说 —— 它没在承载流量，说 `Connected` 是假话。
> **连接态订阅走 gateway 的过滤通道，不走 `scope.subscribeEvents`**：后者是**单槽**监听，装配层已经把它给了 auth 事件；
> 所以 `subscribeConnectionState()` 用 `subscribeUpdates({ clientId, types: ['updateConnectionState'] })` 自建一条，
> 整个协调器只建一次、`destroy()` 退订（这是本端继聊天页之后第二处用到该过滤订阅的地方）。
> **迟到的回包靠一个世代令牌拦**：`pingProxy` 在 TDLib 里没有取消接口，用户翻走页面、切代理、删行时
> 上一轮探测还在途。`handlePingProxies()` 每轮 `pingGeneration++`，回包时同时校验「世代没变」和「页面还开着」，
> 两条任一不成立就丢弃 —— 否则会出现「已经退回设置主页了，代理页的状态却在后台被改写」这种看不见来源的抖动。
> **连接态变化只在「断了又通」时补测一轮**：`unknown → ready`（首帧）**不发** `PingProxiesEffect`，
> 因为打开页面时那一轮已经在途，再发就是同一批请求排队两次；而 `waiting_for_network → ready` 要发 ——
> 断网期间的探测结果全是 `Error`，网络回来了不留一次重测，界面就永远停在一句过期的「不可用」上。
> **一句话记录为什么加了日志**：连接态是推过来的，不在任何一次点按的因果链上，光看界面无法证明订阅真的活着，
> 所以补一条 `proxy_connection <type>` info 日志（连同 `proxy_ping round=…,rows=…` 与 `proxy_ping_error id=…,kind=…`），
> 取证时「界面句子翻转」和「日志里那一帧」互相对上，才算两头都证明。
> 设备取证（模拟器 127.0.0.1:5555，真实 TDLib，账号里零代理）：进代理页 → 日志 `proxy_ping round=1,rows=1` →
> 无代理行先是 `Checking...` → 翻成 `Connected · 226 ms`；添加 socks5 `127.0.0.1:989` 且**不启用**
> （不让账号流量经过一个死主机）→ 该行 `SOCKS5 · Error`，与日志 `proxy_ping_error id=4,kind=tdlib` **同一帧**；
> 控制中心开飞行模式 → 连接态推 `connectionStateWaitingForNetwork`、生效行句子变「Waiting for network...」→
> 关闭飞行模式 → `connecting` → `ready` → **2 ms 后**日志出现 `proxy_ping round=3`（重测轮的直接证据），
> 行回到 `Connected · 228 ms`。**收尾已还原**：测试代理删除、`proxy_list_read count=0,skipped=0,enabled=0`、
> 设置行回到 `Tap to set up`、飞行模式关闭。
> 测试：`feature_settings` **219/219 PASS**（`ProxySettings.test.ets` +11 例纯模型：5 个 `ConnectionState` 判别式映射、
> 秒 → 毫秒与垃圾值拒绝、三哨兵互不相同、探测表不可变写入与剪枝、`pingProxy` 负载重建（0 号行返回 `null`）、
> 生效行判定、生效行跟连接态 / 非生效行只认探测值、` · 226 ms` 后缀只给正数、状态是值对象；
> +1 例 i18n 守卫：8 个状态句子在 zh 字典里全部命中 —— Lang 缺 key 时原样返回 key，所以「翻出来 != key」就是进过字典的证据，
> 这条纪律要抓的是「中文界面漏出一句 `Checking...`」；`SettingsReducer.test.ets` +10 例：`ProxiesLoaded` 现在发一轮探测、
> 关页清表不清行、回读剪枝、探测值写入且保留旧值、0 号行恒可写、死行回包丢弃、连接态去重、首帧不补测、
> 断后复通补测、关页后不补测、`copyWith` 缺省保留两个探测字段），`entry` 42/42、三守卫 0 违规。
> PROXY-101 的三条遗留在此**结案为「不可实现」而不是「没做」**：`setProxyOrder`（拖拽排序）与 `updateProxy`
> 在 TDLib 1.8.67 的 schema 里都不存在 —— 前者没有请求类型，后者没有推送类型，所以「多端改代理的实时推送」
> 本端只能靠回读；「通话是否走代理」依赖 VoIP 本身，本端没有 VoIP 通话，也就没有可接的对象。
> 遗留：错误态只说 `Error`，不给 TDLib 的原文（现已交付，见下方 PROXY-103 追加段 —— 交付的是**分类后的一句话**，
> 不是原文本身）；"Switch automatically" 与
> 最佳代理徽标要先有一个「路由选择器」，本端目前是单选语义；`tg://proxy` 分享链接的确认弹窗（`openProxyAlert`）
> 与扫码导入（前一项已由 DEEPLINK-102 的代理确认卡交付；扫码入口本端没有相机二维码识别，仍未做）；
> 本地没有探测超时（现已交付，见下方 PROXY-103 追加段）。
> **追加（DEEPLINK-101，FEAT-P2-010 深链半边）**：`t.me/…` 与 `tg://…` 从外部（系统选择器、`aa start -U`、
> 聊天气泡里的正文链接）进来到落会话，整条链路第一次打通；FEAT-P2-010 的另一半 Share Extension 另包。
> **解析权交给 TDLib，本端不写链接文法**：Android 的 `TdlibUi.openUrl:3172-3182` 是先 `openTelegramUrl`
> （内部就是 `TdApi.GetInternalLinkType` + `openInternalLinkType` 分发，`:3483-3610`），问不出名堂才
> `openExternalUrl`；TGX 里的 `parseTelegramUrl` 是**死代码**。所以 `entry/deeplink/AppLinkRouter.ets`
> 只做「拿到判别式之后往哪压栈」，`t.me/durov` 是公开会话、邀请还是代理，一律由 TDLib 说了算。
> **纯谓词层 `core/navigation/TelegramLink.ets` 只做「值不值得去问」**：host 白名单逐字对齐
> `TdConstants.TME_HOSTS`（`t.me,tx.me,telegram.me,telegram.dog`，单测把这条字符串钉住），
> `tg` / `telegram` 两个 scheme；`normalizeTelegramLink` 照 `preProcessTelegramUrl:3448-3477` 把
> `durov.telegram.me` 降一级成 `telegram.me/durov` —— **父域名原样保留，不统统换成 `t.me`**。
> 第一版单测按 `https://t.me/durov` 断言，是期望写错、实现是对的，改期望不改代码。
> 同一层里修掉一个真实缺陷：裸链 `t.me/durov`（没有 scheme）在 `splitUri` 里解析不出 authority，
> `host` 恒空 → `isTelegramLinkCandidate` 恒 false → 气泡里最常见的那种链接全部漏判；缺协议时先补 `//` 才对。
> **冷启动时序用一个显式队列解决，不用 AppStorage 兜**：`EntryAbility.onCreate(want)` 跑的时候页面还没
> `aboutToAppear`，而解析需要 `AccountScope` 与路由栈都在。`deeplink/DeepLinkQueue.ets` 是进程级队列，
> 三条纪律：去重只针对**还没交出去的那部分**（已交付过的链接再来一次是真想再去一趟）、`MAX_PENDING=8`
> 丢最旧（没消费者时不能无界攒着，否则恢复后一次性压出 N 层会话栈）、handler 抛异常逐条吞不卡队列。
> 页面 `hasRoute('home')` 时 attach、登出时 detach。装配层还有一条**自喂环**要防：`resolveAppLink` 拿到
> `not_ready` 时只有在「队列没挂 handler」的情况下才重新入队，否则 `enqueue` 会立即回调自己 → 无限递归。
> **气泡内链接不逃逸，用的是窄拦截而不是全量转发**：`ChatPage.openLink()` 只问一个 Kit-free 谓词，
> 命中才出 `OpenAppLink` 意图，coordinator 原样把 URL 交给装配层注入的回调 —— feature 不认识链接语义、
> 也不认识路由；非 Telegram 链接继续走原来那条已验证的浏览器路径，这样路由器出 bug 也不会打挂全部链接。
> **`domainVerify: false` 是刻意的**：置 `true` 需要 `scheme: "https"` 且**域名侧放 asset links**，
> 而我们不拥有 `t.me`；置 true 的结果是这条 skill 永远匹配不上。false 时应用出现在系统「打开方式」选择器里，
> `aa start -U` 也命中。`skills` 加第二条（`entity.system.browsable` + `ohos.want.action.viewData` +
> `tg` 与四个 https host）。
> **只有 `internalLinkTypePublicChat` 真落地**：`getInternalLinkType` → `searchPublicChat(username)`
> （TDLib 顺手把这个公开会话建进本地库，与 Android 点公开链接的行为一致）→ `routeForChat`
> （`open_profile` + 私聊/密聊 → `userProfile`，basic/supergroup → `chatInfo`，其余 `chat`）。
> 失败一律**不猜 chatId**、不用用户名去拼。`invite` / `proxy` / `message` 等判别式回 `unsupported` →
> 上层提示「暂不支持这种链接」，**绝不外溢浏览器**（那里只有登录墙，用户只会以为应用坏了）；
> TDLib 比生成码新、`@type` 不在解码表里时 `decodeTdInternalLinkType` 给 `TdUnknownObject`，
> 判别式原样透传、同样 fail-closed。自有 `tg://` 规则排在 TDLib 之前（一次 IPC 都不花），
> 代价由单测钉死：`https://t.me/chat/{chatId}` 会把「用户名字面上叫 chat 且第二段是数字」判成内部会话。
> **日志里没有链接正文**：链接可以携带邀请哈希（等同凭证），所以全链路只记 `length=`、判别式、chatId
> （`want uri from onCreate, length=18` / `outcome=routed chatId=-1001006503122`）。
> 设备取证（模拟器 127.0.0.1:5555，真实 TDLib，全程只读未发送）：**冷启动** `aa start -U https://t.me/durov`
> → `want uri from onCreate, length=18` → `AppLinkRouter outcome=routed chatId=-1001006503122`，
> `dumpLayout` 落在 Pavel Durov 会话正文（`Codeforces`、`10648974 位订阅者`）；**热启动** `https://t.me/telegram`
> → `want uri from onNewWant, length=21` → routed `-1001005640892` → 页面是 `Telegram News`；
> **内部规则** `tg://chat?chatId=-1001006503122` → `outcome=internal_route route=chat`，onNewWant 到压栈 3 ms、
> 零 TDLib IPC；**外链不回归** `https://example.com/q?a=1` 真的把 `com.huawei.hmos.browser` 拉了起来。
> 收尾 force-stop 浏览器、连按返回回 home（`dumpLayout` 见 `Chats` / `Search`），未发消息、未改账号。
> 测试：`entry` **66/66 PASS**（新增 `AppLinkRouter.test.ets` 14 例：空/not_ready 短路零 IPC、非候选不进
> TDLib、自有规则优先、`t.me/chat/{id}` 吞用户名会话、publicChat 两种调用序列、子域归一后进 TDLib 的链接形态、
> `open_profile` 分流、`routeForChat` 含 `type_ = null`、`unknownDeepLink` 是唯一外溢口、认得未实现不外溢、
> TDLib 报错与外来 `@type` 各自 fail-closed、`searchPublicChat` 失败不猜 id、空用户名先失败、`stripAtSign`
> 含 `@@durov`、在途去重（gate 住的 promise）、自定义规则表整体替换默认表；`DeepLinkQueue.test.ets` 8 例：
> 入队后 attach 按序冲刷、attach 后直投、去重只对未交付部分、空白拒收、上限丢最旧、handler 抛异常不连坐、
> detach→重投→reattach、`pendingUris()` 返回副本），`core_navigation` **54/54**（`TelegramLink.test.ets` 8 例：
> host 白名单逐字对齐、`nott.me` / `evil.com/t.me/…` / `mailto:` 判非、裸链与子域、`tg:settings`、
> `splitUri` 的 authority/path/query/fragment、`HTTPS://T.ME.:443/…` 大写带端口、`www.` / `m.` / 二级子域不改写），
> `feature_chat` **323/323**（`ChatAppLinkDispatch.test.ets` 2 例：URL 原样递出且不去重、空串不递、未注入不崩）；
> 三守卫 `check_architecture` / `check_codegen` / `check_design_tokens` 0 违规。两个 ArkTS 编译坑：
> 早退之后 `.value` 不收窄（改用 `getOrNull()`）、`{ ok: false, error }` 字面量不满足 `Result`（必须走 `err()`）。
> 遗留（→ DEEPLINK-102）：`internalLinkTypeChatInvite`（`checkChatInviteLink` → 确认弹窗 → `joinChatByInviteLink`）、
> `internalLinkTypeProxy`（→ `addProxy(enable: true)`，顺带结掉 PROXY-101 的 `tg://proxy` 遗留）、
> `internalLinkTypeMessage` / `Post`（→ `getMessage` 定位跳转）、`internalLinkTypeBotStart`（`addContact` + 开会话）、
> `tg://resolve?domain=`；Share Extension 另包；气泡内 `t.me` 链接的**真机点击**取证还缺一个可稳定命中的
> span 热区（判定与递出已由单测覆盖）。

> **追加（DEEPLINK-102，FEAT-P2-010 深链的另一半：其余 Telegram 链接类型）**：
> 邀请、代理、消息、bot start 四类判别式落地，DEEPLINK-101 那句「认得但没实现」的 `unsupported`
> 现在只剩贴纸包 / 语言包 / 语音聊天三类。
> **① 要问人的链接走端口，不走全局弹窗单例**：`entry/deeplink/AppLinkPrompt.ets` 只声明两条回调
> `confirmInvite(data) → boolean` 与 `chooseProxy(data) → 'enable' | 'save' | 'cancel'`
> （对标 Android `TdlibUi.openJoinDialog` 与 `openProxyAlert` 的两个 UI 触点），路由器因此仍是能在
> hypium 里跑的纯逻辑；ArkUI 状态（`@State promptVisible/promptCard`）全在装配层 `pages/Index.ets`。
> **没接弹窗时的兜底是「一律拒绝」**（`DECLINING_APP_LINK_PROMPT`）——加入会话与切代理都是账号级动作，
> 默认值绝不能替用户同意。
> **② 视图模型是从 TDLib DTO 里挑出来的标量**：`InvitePromptData` / `ProxyPromptData` 只带能显示的东西，
> 邀请哈希留在路由器手里，不进 UI 状态、不进日志。构卡函数（`invitePromptCard` / `proxyPromptCard`）
> 注入 `TranslateFn` 后完全 Kit-free，可单测；产出的 `PromptCard` 只有已经翻译好的三段文案 + 三个按钮，
> `secondaryLabel === ''` 表示「没有第二动作」——视图层不认识「邀请」「代理」这些业务概念，
> 也就不会出现「新加一类链接忘了加按钮」。
> **③ 代理链接的两个动作是同一条 `addProxy`**：「启用」与「稍后使用」只差 `enable` 这个 bool，
> 由 `proxyChoiceEnables(choice)` 单列出来（`cancel → null`），测试钉住「选了 save 绝不会 enable」；
> **不补发 `enableProxy`** —— PROXY-101 的口径是单选态只有 TDLib 知道真相，`addProxy(enable=true)` 已原子，
> 代理页下次回读自然显出这一行。TDLib 回 `proxy: null`（不支持的代理类型）时报 `unsupported` 且**先于弹窗**，
> 不问用户一个答不了的问题。
> **④ 邀请链接的两条捷径**：`checkChatInviteLink` 的 `chat_id !== 0` 表示「已经是成员」→ 直接导航，
> 不再问人；`creates_join_request` 的链接按钮换成「申请加入」，`joinChatByInviteLink` 回
> `chatJoinResultRequestSent` 时走新出口 `notified`（动作完成了但没有页面可去 → toast「加入申请已发送」）。
> `declined` / `guardbot` 一律 `failed`，不猜。
> **⑤ 消息链接复用既有路由**：本 TDLib 版本没有 `internalLinkTypePost`，帖子链接同样回
> `internalLinkTypeMessage`，统一交给 `getMessageLinkInfo`；`chat_id === 0` 是「本地没有这个会话」→
> `failed`，**不猜 chatId、不建会话**；`messageId > 0` 时压 `chat` 路由带 `messageId`（SEARCH-102 就有的字段，
> 会话页已会滚动定位并高亮），这里不另造路径。
> **⑥ bot start 先验真身**：`searchPublicChat` 拿到会话后还要 `getUser` 且 `type_ === 'userTypeBot'` 才导航
> （Android 直接 `addContact` 是因为它信任自己解析出来的 bot 名），非 bot 用户名回 `failed`；
> `sendBotStartMessage` 只在 `autostart && start_parameter.length > 0` 时发，且**不等回包**——
> 进会话已经成功，启动消息失败只留一行日志。
> **⑦ 三种结果三种表达**：`cancelled`（用户说了不）静默、`notified` 走 `appLinkReasonKey(reason)` 翻译后
> toast、`unsupported`/`failed` 各有兜底文案；认不出的 reason 回「Failed to open link」而不是把内部键名
> 印到用户脸上。
> **⑧ 每个终态必须留下一行日志**：设备实测 `https://t.me/durov?start=qoderx` 什么也没发生、日志里也查不到
> ——`fetchPublicChat` 失败静默返回 null，那几条早退的 `failed` 分支没人记账。修法是收口成一处：
> `handle()` 对解析出的结果统一走 `logTerminal()`，`failed`/`unsupported` 必留
> `outcome=… linkType=…,reason=…`，分支自己的 `stage=` 仍各自给；配套单测
> `failedOutcome_alwaysLeavesASummaryLine`（漏一条就红）。
> **⑨ 设备取证**（模拟器 127.0.0.1:5555，真实 TDLib，未加入任何会话、未发消息）：
> 消息深链指向 `Telegram News` 里 2019-01-22 的那条帖子（`Group Permissions, Undo Delete and More`），
> 落点页面仍显示「加入频道」，证明整趟是只读的；代理链接（`server=proxy.qoder.test`、`port=1080`）
> 在会话页之上弹出真卡片（`Connect to This Proxy?` / `Server: proxy.qoder.test` `Port: 1080` / `Enable` /
> `Save for Later` / `Cancel`），点 **Save for Later** → 弹窗关闭、**页面没动**、
> `outcome=notified stage=add_proxy,enable=false`；设置行随之变成 `Proxies · Disabled`（存了但没启用），
> 代理页里能看到那一行；**收尾已还原**：经 `ProxySubPage` 删除确认移除该代理，设置行回到 `Tap to set up`、
> 列表回到空态（跑之前本来就没有代理）。bot 守卫复测：三次触发同一链接，`hilog` 稳定给出
> `outcome=failed linkType=internalLinkTypeBotStart,reason=bot_not_found`，屏幕底部出
> 「Failed to open link」toast，`dumpLayout` 仍在 `Chats`（未导航）。
> **⑩ `tg://resolve?domain=` 不用写规则**（DEEPLINK-101 把它挂在遗留里，本轮实测直接通过）：
> `tg` scheme 本来就是候选链接，自有规则表没有 `resolve` 这一条 → 落到 `getInternalLinkType`，
> TDLib 解析成 `internalLinkTypePublicChat` → `outcome=routed chatId=-1001005640892,openProfile=false`，
> 落在 `Telegram News`。**这一类链接的正确处理是「不加代码」**，规则表只留真正不需要 IPC 的形态。
> **⑪ 测试**：`entry` **97/97 PASS**（`AppLinkRouter.test.ets` 38 例，较 DEEPLINK-101 的 14 例增 24：
> 邀请 7 例（已是成员不问、接受后入会并导航、拒绝零写入、未接端口默认拒绝、只发申请走 notified、
> check 失败 fail-closed、`invitePromptOf` 只留可显示标量）；代理 6 例（enable 与 save 各发**一次**
> `addProxy` 且只差 bool、cancel 零写入、未接端口零写入、不支持类型报 unsupported 且**不问**、
> `proxyPromptOf` 剥掉 ProxyType 前缀）；消息 3 例（带 messageId 导航、无 message 只进会话、
> 会话解析不出不猜）；bot 4 例（非 bot 用户名拒、验真后导航并递参数、无 start_parameter 绝不发、
> 非私聊会话拒）；外加终态日志与「日志里绝不出现链接正文」（真 `Logger` 收口断言）；
> 新增 `AppLinkPrompt.test.ets` 9 例：按钮/人数文案规则、邀请卡无第二动作、0 人时不出 footnote、
> 代理卡正文逐字符等于 `Server: …\nPort: …`、mtproto footnote 长于 socks5、`proxyChoiceEnables` 三态、
> `appLinkReasonKey` 三个 notified reason 全覆盖 + 兜底）。三守卫与 `secret_scan` 0 违规。
> 一个 ArkTS 坑：`arkts-no-untyped-obj-literals` 不接受「带方法的接口」的对象字面量实现，
> 端口两条回调必须写成 `readonly fn: (…) => Promise<…>` 函数属性（注入点与测试都用字面量）。
> **遗留（→ 下一包）**：四类之外仍有 52 个判别式回 `unsupported`（`Theme` / `StickerSet` /
> `LanguagePack` / `GroupCall`+`VideoChat` / `Invoice` / `Game` / `WebApp` / `Story` /
> `ChatFolderInvite` …，`tg://settings` 这类自有规则已经先接住）；邀请**弹窗**的真机取证缺一个可安全加入的
> 真实哈希（入会语义由单测覆盖，卡片渲染与代理卡共用同一视图层、已由代理卡证明）；
> `internalLinkTypeBotStartInGroup` / `attachmentMenuBot` 等 bot 家族其余入口未做；
> FEAT-P2-010 的另一半 Share Extension 另包。
> **追加（PROXY-103，FEAT-P2-007 代理半边的收官）**：PROXY-102 记的两条遗留一起清掉 ——
> 出错的那一行现在说得出**为什么**出错，而卡在 `Checking...` 的行有了本地兜底。
> **这一包的核心决定是「分类而不是转发」**：Android 的 `SettingsProxyController` 直接把 TDLib 原文印成
> `Error (code: message)`，本端的错误模型不允许这么干 —— `AppErrors.fromTdlibError` 刻意把原文只放进 `cause`
> （别的请求的原文里可能出现手机号、沙盒路径、mtproto 凭证），`message` 一律是诊断文案而不是用户文案，
> 而 `Logger.logError` 走的又是 `toLogString()`（只留 kind/code）。所以 `classifyProxyFailure()` 做的是
> **认得出的连接故障给对应的句子、认不出给一句通用的**，7 个自有 Lang key 收口（refused / timed out /
> 地址无法解析 / 网络不可用 / 握手失败 / 配置被拒绝 / 兜底）。界面拿到的永远是 key，原文只进
> `proxy_ping_error` 那一行日志。**形状借自 Android，内容是本端的**：`SOCKS5 · Error (Connection refused)`。
> **失败原因放在第二张侧表 `proxyPingFailure: Map<number, string>`，不把原因编进延迟那个负数哨兵**：
> `PROXY_PING_FAILED` 只有一个值，说不出是哪种失败，而这一行要说的恰恰是「为什么失败」；分开存还带来一条
> 必须成对写的纪律 —— 成功探测要把上一次的失败原因一起擦掉（`proxyFailuresWith(…, '')` 走删条目而不是写空串），
> 否则会出现「`Available · 230 ms` 后面挂着一句 (Connection refused)」。两张表用**同一个** `proxyAliveIds()`
> 剪枝、同一次 `closeProxyPage` 清空，口径不一致就会留下幽灵原因。
> `ProxyStatus.failureKey` 只在说那句「出错」时挂上：生效行的句子由连接态优先说话，那时负责解释的是连接，
> 不是那次已经过期的探测。
> **本地超时是补出来的，不是 TDLib 给的**：`pingProxy` 没有取消接口，挂在一个黑洞地址上可以几分钟不回包，
> 而那一行会一直停在 `Checking...` —— 用户读到「还在测」，真相是「没人在测」。协调器给每一行补一个
> `PROXY_PING_TIMEOUT_MS = 10s` 的 `setTimeout` 兜底。
> **设备取证抓出一个真实缺陷**：PROXY-102 的拦截靠 `generation` 世代令牌，而世代是**每轮**的、不是**每行**的 ——
> `127.0.0.1:989` 4 ms 就回了 `Connection refused`，10 s 后定时器照样到点，把已经落定的那句盖成了
> 「Connection timed out」。日志和界面同框对上了才看得见：`proxy_ping_error …reason=Connection refused,elapsed=4`
> 与行上的 `Error (Connection timed out)` 互相矛盾。修法不是加长超时，而是让定时器只对**还在途**的那一行说话
> （`proxyPingOf(…) !== PROXY_PING_LOADING` 直接返回）—— 超时的语义是「这行还没结果」，不是「这一轮过了一秒」。
> **耗时本身是一个信号，不只是日志字段**：黑洞地址 `10.255.255.1:8080` TDLib 自己在 **9.02 s** 回了一个 400，
> 抢在 10 s 兜底之前，而那句话里并不带 `timeout` 字样 —— 纯关键字分类掉进通用的「代理异常」。
> 于是加了 `PROXY_PING_SLOW_MS = 6000`：失败慢到这个程度就是超时，不需要 TDLib 亲口承认。
> 这条线是实测画出来的：拒连 2–4 ms、DNS 失败 4.0 s、黑洞 9.0 s、成功 ~225 ms，
> 6 s 既能接住挂死的连接，又不会把「查不到地址」误读成「等太久」。
> 测试：`feature_settings` **230/230 PASS**（+8 例模型：TDLib 原文 → 自有句子的六路分类表、
> 多关键字命中时取先手、慢失败读成超时（`elapsed = 6000` 是超时、`5999` 不是，而 4 s 的 DNS 失败仍归「地址无法解析」），
> 非 tdlib 类按 kind 兜底、数字码只给日志、原因表读/写/擦/剪、`failureKey` 只挂在那句「出错」上、
> 超时是有界等待且有自己那句话；+3 例 reducer：探测值与原因同口径写、关页清两张表、回读按同一规则剪枝；
> 另把 i18n 守卫从 8 句扩到 15 句 —— Lang 缺 key 会原样回显，「翻出来 != key」就是进过字典的证据），三守卫 0 违规。
> 设备取证（模拟器 127.0.0.1:5555，真实 TDLib，三条**都不启用**，不让账号流量经过死主机）：同一屏里三种原因
> 各自独立成句 —— `127.0.0.1:989 → SOCKS5 · Error (Connection refused)`（`elapsed=4`）、
> `ghost-node.qoder-invalid.test:1080 → Error (Address not found)`（`elapsed=4019`）、
> `10.255.255.1:8080 → Error (Connection timed out)`（`elapsed=9024`，改分类前这一行是 `Error (Proxy error)`），
> 而「不使用代理」行全程 `Connected · 225 ms` 不受影响。**收尾已还原**：三条测试代理逐个删除、
> `proxy_list_read count=0,skipped=0,enabled=0`、设置行回到 `Tap to set up`。
> 遗留：MTProto 与 HTTP 两类代理的失败原因没在设备上单独取过证（分类表是同一份，实测只覆盖 socks5 三种通路）；
> "Switch automatically" / 最佳代理徽标缺「路由选择器」（单选语义下没有可比的对象）；扫码导入缺相机识别入口。

> **2026-09-25（CHAN-SEND-3，FEAT-P2-002/004/005 贴纸与 GIF 的发言权否决）**：CHAN-SEND-2 的两条遗留结案，
> **但两条都不按原来写的方式做 —— 读码后都改了形状**。
> **① 遗留项本身写错了方向**：原文是「`can_send_other_messages` 尚未驱动 `EmojiBoard` 里的贴纸/GIF **页签**」，
> 照字面做就该把页签置灰或藏掉 —— 而 Android **从不**在面板上管这件事：`EmojiLayout.java` 全文零 `RightId` 引用，
> 贴纸与 GIF 页签任何时候都可点；否决发生在**选中要发出去那一张**时（`MessagesController.java:9230` sendSticker、
> `:9238` sendAnimation → `sendContent()` → `showRestriction(...)`，出句子 + 不发）。所以本端做成**发送时否决**：
> 页签照常、点一张被禁的贴纸/GIF 才弹提示，且**消息根本不会出去**（设备实证：会话仍是 `No messages yet`）。
> **② `can_send_audios` 的「音乐附件入口」确认为误报，删项**：Android 附件面板只有
> Contact / File / Gallery / Location / Poll（`MediaLayout.java:260-268`），**音乐是文件浏览器里的一行**
> （`MediaBottomFilesController.java:275-276`，点击时按 `isMusic ? SEND_AUDIO : SEND_DOCS` 否决），本端没有那个容器。
> 与 CHAN-SEND 首版「输入栏左侧 🔔」同一处理口径：**不为不存在的容器造 UI**。
> 落点：`core/domain/chat/ChatSendRights.ets` 加 `CONTENT_STICKER` / `CONTENT_GIF` 两个内容 key、
> `canSendContent(rights, key)` 判定表（六类内容一位一权，**未知 key 放行** —— 新入口忘了登记时，
> 让 TDLib 报错比本地误杀好查）、`sendVetoLabel(rights, key)` 统一否决入口；
> 原 `attachmentRestrictionLabel` 改为与它**共用同一张文案表** `restrictionSentence`（两处各抄一遍迟早写成两个句子）。
> 三处入口全接：表情板贴纸、表情板 GIF、**贴纸包预览**（`SendStickerFromPreview` 与 `SendSticker` 发的是同一个
> `SendStickerMessage`，漏接一处等于没 gate，而且预览那条还会顺手把贴纸记进最近使用）。
> **unicode 表情贴纸的豁免**是这里唯一的坑：内置贴纸包 fileId 1001–1045 实际由 coordinator 走
> `sendTextMessage` 当文本发（那是 emoji，受 `basic` 位管），把它们一起否决就会在禁贴纸的群里连一行 emoji 都发不出。
> 这条边界原先是**两处硬编码 magic number**（页面要跳过、coordinator 要认），现集中成
> `isUnicodeEmojiSticker(fileId)`，并有用例守住「内置贴纸全部落在豁免区间内、GIF 占位档全部落在区间外」——
> 区间一旦漂移（新增贴纸包用了 1046），提示语就会指错方向。
> 测试：`core_domain` **161/161**（+4 例：九位逐位点亮证明**只有** `otherMessages` 能否决贴纸与 GIF、
> 六类内容六句不同文案、未知 key 放行、置灰提示与发送否决同源）、`feature_chat` **326/326**（+3 例豁免区间），三守卫 0 违规。
> 设备取证（模拟器 127.0.0.1:5555，受限态用一次性强制权限包：`applyChatSendPermissions` 里把 `otherMessages`
> 写死 false，验完删除重建）—— ① GIF 页签点 `Thumbs Up` → `Toast 此会话不允许发送 GIF`，
> 同屏 Saved Messages 仍 `No messages yet`（否决是真的没发出去，不是发完再报错）；
> ② 同一包里贴纸页签点 🐼 → **照发**（豁免生效，emoji 走文本不受贴纸位管），随后长按删除回空态；
> ③ 还原成正常包后重跑同一步 GIF 点击 → 出 `🎬 Thumbs Up` 且无提示（证明否决只由权限驱动而不是无条件拦截），同样删除还原。
> 全程只在 Saved Messages 内操作，未向任何真实群/频道发送内容。
> 遗留：真实贴纸包与动图的**实际发送链路**（非占位 fileId）仍未接，这条否决目前吃到真内容的场景只有贴纸包预览；
> 受限态依旧只有注入证据（账号内不存在「可发言但禁贴纸」的会话）；`updateChatPermissions` 推送链仍未设备实证。

> **2026-09-25（STICKER-BOARD-101，FEAT-P2-004 贴纸页签接真实已装贴纸包）**：表情板的贴纸页签原先渲染的是
> `DEFAULT_STICKER_PACKS` 四包预置数据 + emoji 占位格 —— 也就是说**账号里装了哪些包，界面上永远看不出来**。
> **读码先纠正一处假设**：仓库里的 TDLib schema 比「1.8.67」新，`getStickerSets` **不存在**，
> 能用的只有 `getInstalledStickerSets(sticker_type)`（**必须给类型**，regular/mask/customEmoji 各一次）
> 与 `getTrendingStickerSets`；返回的 `stickerSetInfo` 只带 `covers`（**最多前 5 张**）+ `size`，
> 所以「整包还有多少张」只能靠 `size > covers.length` 差值说 —— 界面上那句「查看其余 N 张」吃的是这个差，
> 而不是再发一次 `getStickerSet`（一包一次请求，八个包就是八次往返，而用户大概率只看前两包）。
> **取图口径**：装盘只登记**缩略图**（包 thumbnail + 封面 thumbnail，全局预算 30），贴纸整图点了要发才下 ——
> 在 Wi-Fi 之外一次性拉 40 张贴纸整图是流量事故。
> **懒加载与失效**：请求只在页签可见时发（`OpenStickerBoard`），reducer 用 `isLoading || isLoaded` 去重
> （页签反复进出不会打爆 TDLib），而 `onStickerSetChanged` 把 `isLoaded` 打掉 ——
> 装/卸一包后下一次开板就该重读，否则新装的包要等到杀进程才看得见。
> **到货回灌**是这里唯一不显然的地方：格子上带的是**路径**不是 fileId（reducer 里按 id 补不了），
> 所以协调器留着原始 `StickerSetInfo[]` 和它登记过的 fileId 集合，某张缩略图下载完成时**重新映射整块板卡**
> （`refreshStickerBoardOnArrival`），`ForEach` 的键里带路径，图到货才会重建那一格。
> **三种空态说三种话**：正在读取 / 读取失败（带重试）/ 确实没装包 —— 把「请求失败」显示成「还没有安装贴纸包」
> 会把用户支去完全错误的方向；失败时**保留上一次的内容**、只清 `isLoading` 并把 `isLoaded` 留成 false，
> 于是这一屏不空、下一次进页签还会重试。
> 测试：`feature_chat` **346/346**（+12 例纯模型：DTO→包映射跳过无封面项、下载预算有界、缩略图取值顺序、
> 最近使用伪包在最前且不可点开整包、格子取图回退链、键随图到货变化；+5 例 reducer：去重、失败保包、
> 装卸包失效；+3 例 coordinator：只请求 regular 一次、只下缩略图不下整图、失败后下次重发），三守卫 0 违规。
> 设备取证（模拟器 127.0.0.1:5555，真实 TDLib）：本账号 `getInstalledStickerSets(regular)` 回
> `rows=0,total=0` → 负路径实证（页签只剩 Recent Stickers + 清空，四包假数据确实不在了）。
> **正路径用一次性取证包补证**（验完删除重建，不进提交）：把同一份映射喂给 `stickerTypeMask` 的已装包，
> 拿到 6 包真实数据 → 屏上出现 `Concerned Frog…`/`Lady Noir` 两行真包标题与「查看其余 20 张 / 15 张」，
> 封面格在缩略图到货后由 emoji 兜底变成**真贴纸图**（日志 `media_download_completed fileId=98/108/118/128/138`），
> 点一格发出**真 fileId** 的贴纸消息（Saved Messages 内，验完长按删除回 `No messages yet`）。
> 结案 CHAN-SEND-3 遗留 ①「真实贴纸包的实际发送链路未接」的一半：贴纸侧已通，GIF/动图侧仍全是占位 fileId
> （本端没有 GIF 数据源，TDLib 无 GIF API）。
> 遗留：① 板卡上**没有装包的入口** —— `tg://addstickers` 未接、trending 榜没露出，而账号恰好 0 个已装 regular 包，
> 于是真实用户在这里只能看到「还没有安装贴纸包」；② 最近使用仍来自 `DEFAULT_RECENT_STICKERS` 假数据
> （TDLib 的 `getRecentStickers` 尚未接）；③ 取证时看到发出的贴纸**气泡不出图**（整图没下、也没有占位），
> 属于贴纸消息渲染的独立缺口。

> **2026-09-26（STICKER-BOARD-102，FEAT-P2-004 热门贴纸包 + 装包入口，结掉 101 遗留 ①）**：
> 贴纸页签有了真实内容却没有「从哪里弄到包」的入口，等于把用户关在一个空房间里。
> **入口是榜，不是弹窗**：接 `getTrendingStickerSets(regular, 0, N)` 在页签底部出一段「热门贴纸包」，
> 每行一张封面 + 包名 + `size` 张数 + 一个动作，**点动作就地装/卸**（`changeStickerSet`），
> 不弹全屏、不跳浏览器 —— Android 那侧的 `tg://addstickers` 语义在应用内就是这一条写请求。
> **一行只登记那一张封面文件**（包 thumbnail → 各 cover 的 thumbnail，去重后取第一个可用项），
> 榜上一屏 6 行就是 6 路下载；这里若按 101 板卡的口径把 5 张 cover 全登记，
> 一次进页签就是三十几路并发 —— SHARED-AUDIO 那次的教训不能再犯一次。
> **热门行没有封面也要保留**：这一行的**用途是装包**，图只是装饰；
> 与板卡恰好相反（板卡上一格发不出去就不该出现在发送入口，所以无可用封面的包整包跳过）。
> 两处的判据分叉是刻意的，写成两条用例分别钉住，防止后来人「统一」成一个。
> **装完必须让板卡重读**：`onStickerSetChanged` 旧实现只在预览弹层开着时才失效，
> 于是从热门行装包 → 板卡停留在旧列表 → 用户以为没装上（101 时代就漏了这条，只是当时没有装包入口所以看不见）。
> 现在两条分支**一律**打掉 `isLoaded` 并补发 `FetchStickerBoard` + `FetchTrendingStickerSets`，
> 榜上那一行的「添加 / 已添加」也跟着 `is_installed` 翻 —— 行键里带 `isInstalled`，否则翻不动。
> **失败不抢错误槽**：`onTrendingFailed` 只把榜收起来，不写 `errorMessage`；
> 榜失败而板卡正常时，屏幕上不该出现一句和板卡无关的错。
> **设备上抓到第二个平台级事实（本轮最有价值的收获）**：第一段取证截图里热门行的封面**全是空白方块**，
> 而下载日志显示图片文件早就落盘了。落到沙盒里看文件名才看清：TDLib 把**动效贴纸（Lottie）包的缩略图**
> 直接落成 `.tgs`（gzip 过的 JSON），本端没有 rlottie/TgsPlayer 那样的解码器，
> ArkUI 的 `Image` 拿到这个路径就是**静默画一块空白** —— 看起来像「图没下下来」，真相是根本解不了。
> 据此在模型层加 `stickerPathIsRenderable(path)`：后缀命中动画/矢量容器格式（`.tgs/.json/.lottie/.mp4/…`）
> 一律当「没有图」，热门行换下一张候选封面、板卡退回包名首字母、格子退回贴纸自己的 emoji。
> **判据只能落在已下盘的本地路径上**：本端用的 TDLib `file` DTO 只有 `id/size/expected_size/local/remote`，
> **没有 `name`/`extension`**，下载前无从得知格式 —— 所以这是「拿到路径后再筛」，不是「挑着下」。
> 这条不只关乎贴纸板：任何把 `.tgs` 喂给 `Image` 的界面（**贴纸消息气泡**、贴纸包预览页）都是同一块空白，
> 因此「TGS/Lottie 渲染器」升级为剩余缺口中明确的一项。
> 测试：`feature_chat` **365/365**（+纯模型：`.tgs` 封面被跳过并取下一张候选、格式白名单只拒动画类
> （webp/JPG/无扩展名放行）、格子的 original 是 `.tgs` 时回退到可解码缩略图且**键里不含 `.tgs`**、
> 包缩略图不可解时不进缩略图取值链；+reducer：开板出两条 Effect、装卸无预览页也失效、`installingSetId`
> 置位与失败清除、`onTrendingLoaded` 不碰板卡槽位、`onTrendingFailed` 不写 `errorMessage`；
> +coordinator：榜回包只登记每行一张封面、已下过的那张不再登记），三守卫 0 违规。
> 设备取证（模拟器 127.0.0.1:5555，真实 TDLib）：进贴纸页签 → 日志 `sticker_trending_loaded rows=6,total=857`，
> 榜上六行真包名 + 张数、封面图**真实渲染**（`.tgs` 修复前是六块空白）；点第一行「添加」→
> 该行翻成「已添加」（`changeStickerSet` 的 `updateStickerSet` 推送回来），同一帧板卡重读
> `sticker_board_loaded rows=1,total=1`，新包**立刻**出现在页签里，块头带真封面、「查看其余 19 张」；
> 再点「已添加」→ 卸载 → `sticker_board_loaded rows=0,total=0`，**账号回到取证前的 0 个已装 regular 包**。
> 全程只在 Saved Messages 之外的表情板内操作，未向任何真实群/频道发送内容。
> 遗留：① 热门榜只取 regular 一类（mask / customEmoji 未露出，榜语义在 Android 是「与当前类型相关」）；
> ② 无 TGS/Lottie 解码器 → 动效贴纸包在板卡与**消息气泡**里都只有 emoji/字母兜底；
> ③ ~~最近使用仍吃 `DEFAULT_RECENT_STICKERS`（`getRecentStickers` 未接，101 遗留 ②）~~（**2026-09-26 已由 STICKER-RECENT-101 结案**，见后面那条注）；
> ④ 101 遗留 ③「贴纸气泡不出图」（**2026-09-26 已由 STICKER-MSG-101 结案**，见下一条注）。

> **2026-09-26（STICKER-MSG-101，FEAT-P2-004 贴纸消息气泡渲染档位，结掉 101 遗留 ③ / 102 遗留 ④）**：
> 上一条注里那句「任何把 `.tgs` 喂给 `Image` 的界面都是同一块空白」不是推测 —— 气泡正是最刺眼的那一处，
> 而且它比板卡更糟：板卡至少还知道退回字母，气泡是**整块什么都不画**。
> **复现链条是干净的**：Saved Messages 发出 Uni 包一张贴纸，`send_sticker_ok fileId=92` 与
> `media_download_completed fileId=92` 两条日志都在，屏上那个位置却只剩右下角那颗时间戳胶囊。
> `ls -lt tdlib/db/stickers` 看到 `1052321353216032834.tgs` 正是那一秒落盘的档 —— **同一个 fileId，
> 整档是 Lottie（画不开），缩略图是 `.webp`（画得开）**，而贴纸板里那格显示正常，就是因为板卡吃的是后者。
> **病灶是一行判据写错了对象**：旧 `StickerBubble` 写的是「有 `localPath` 且 `isDownloaded` → `Image(localPath)`」，
> 把**下载完成当成了可渲染**；`.tgs` 因此占住首选档，缩略图与 emoji 兜底两条分支永远轮不到，
> 于是「图下好了」和「屏上什么都没有」同时成立。
> **修法**：新增 Kit-free 纯函数 `model/StickerMessage.ets` → `stickerBubbleRender(media)`，
> 返回 `video / image / thumbnail / emoji` 四档，只问「本端到底画不画得开」：视频容器（`.mp4/.webm` 视频贴纸）
> 走 `Video`；位图（webp/png/jpg/gif）走整图；`.tgs/.json/.lottie` 或整档没下完 → 缩略图；两头都不行 → 贴纸自己的
> emoji（无 emoji 再退 ⭐️）。**缩略图本身也要过一遍可画判定** —— `thumbnails` 目录里同样躺着 `.tgs`
> （设备实测 `328260442013040644_1680977305.tgs`），拿它兜底等于再画一次空白。
> 顺带清掉两处旧写法：容器判定从 `localPath.indexOf('.webm') >= 0`（`a.webm.log` 也算命中）改成复用
> `motionContainerOf`（mime 优先、扩展名只认**结尾**）；兜底档原来画的是照片图标 `ic_photo`，换成贴纸语义。
> **有意不做**：不引入 TGS/Lottie 解码器 —— 那是独立缺口（第三方解码依赖 + 板卡/预览页/气泡三处要一起管）。
> 本包只保证「不再画空白，画不开就退到能画的」，代价是**动效贴纸在气泡里是静帧**（缩略图），不会逐帧动。
> 测试：`feature_chat` **373/373**（新 `StickerMessage.test.ets` +8：`.tgs` 已下完退 webp 缩略图、`.tgs` 无缩略图退 emoji、
> `.tgs` 缩略图不算兜底、位图与无扩展名走整图、视频容器且扩展名只看结尾、未下完优先缩略图、空 emoji 仍出兜底档），
> 三守卫 0 违规。设备对照取证（127.0.0.1:5555，同一条消息、换 HAP 前后各一张）：修复后气泡画出独角兽，
> `dumpLayout` 对应 `Image` 节点 `[570,496][1200,1126]`（180vp 见方）；随后长按删除该测试消息（回 `No messages yet`）、
> 卸载 Uni 包（`sticker_board_loaded rows=0,total=0`），**账号回到取证前原状**，全程未向任何群/频道发送内容。
> 遗留：① 动效贴纸无逐帧动画（等 TGS/Lottie 渲染器，届时气泡/板卡/预览页三处一起换）；
> ② ~~贴纸包预览页的 `.tgs` 格子仍空白（`stickerPathIsRenderable` 已可复用，纯接线活）~~（**2026-09-26 已由 STICKER-PREVIEW-101 接上同一取值链**，见下一条注）；
> ③ ~~最近使用仍吃 `DEFAULT_RECENT_STICKERS`（`getRecentStickers` 未接）~~（**2026-09-26 已由 STICKER-RECENT-101 结案**，见 PREVIEW-101 之后那条注）。

> **2026-09-26（STICKER-PREVIEW-101，FEAT-P2-004 贴纸包预览弹层，结掉上一条遗留 ②）**：
> 接线活本身两行：`StickerSetPreviewSheet` 的格子原来写 `item.localPath ?? item.thumbnailPath` 直接进 `Image`，
> 换成板卡与气泡共用的那条 `stickerCellImagePath(item)` —— 动效包的整图和缩略图**都能**是 `.tgs`
> （设备实测 `thumbnails/…_1680977305.tgs`），两条都画不开就退回这颗贴纸自己的 emoji，`ForEach` 键带上路径。
> **真正的收获是撞出一个此前没人走过的坑**：为了验这两行，第一次把「整包取数」在真实账号上跑到底，
> 结果预览弹层对**任何**一包都停在错误分支。取出数字码 → `getStickerSet(set_id)` 回
> `406 STICKERSET_INVALID`；换 `searchStickerSet(短名, ignore_cache=true)`（即 `inputStickerSetShortName`，
> 与 Telegram X `loadStickerSet(shortName)` 同一条路）**同一个包仍回 406**。
> 三条反证排除了「包不存在/短名算错」：`ConcernedFroge` 在 t.me 公开页可访问；它的 `id + access_hash`
> 走 `changeStickerSet` **装包成功**（榜上翻「已添加」、`rows=1,total=1`）；装完本地已有这一包，再开预览两条路各回一次 406。
> 读 vendored TDLib 对上机制：`get_sticker_set` 与 `search_sticker_set` **都不是本地查表**，最终都落到
> `GetStickerSetQuery → messages.getStickerSet`（`StickersManager.cpp:719-769`、`:5002-5019`、`:5540-5575`），
> 而 `STICKERSET_INVALID` 全仓库只被 `update_load_requests` 当作「包大概已被删」用于清短名映射
> （`:3968-3972`），**没有本地合成这条错误的地方** → 服务端否决，ArkTS 侧修不了，
> 要 native 继续查 TL 层 / `hash` 语义 / DC 路由（本端 `.so` 是预构建 + 补丁，重编 TDLib 不在本包预算内）。
> **因此取数交付的形状是「按 id → 短名依次兜底」**：`stickerSetShortNameOf(groups, setId)`（Kit-free）从板卡与
> 热门榜两组 DTO 缓存里取短名，按 id 失败且有短名就再问一次；本地没见过这一包（消息气泡那个入口只有
> `stickerSetId`）就只剩按 id 的一次机会。另修一处话术：弹层直接把 TDLib 的英文兜底串 `TDLib request failed`
> 画在屏幕上，改成「贴纸包加载失败，请稍后重试」，原文继续只进 `AppError.cause`。
> 测试：`feature_chat` **375/375**（+2：`.tgs` 双路径必须返回 null；`stickerSetShortNameOf` 跨组/同组命中与
> 未命中、`name` 为空回空串），三守卫 0 违规。设备取证（127.0.0.1:5555，`.hvigor/outputs/sp101b/`）：
> 热门行进弹层出「贴纸包详情 / 贴纸包加载失败，请稍后重试 / 重试 / 添加贴纸包」，点一次重试
> `ChatCoordinator error` 计数 2 → 4（兜底链真的重发了两条请求），`name=ConcernedFroge` 确认走的是短名；
> 取证期间装的 `ConcernedFroge` 收尾卸回（`sticker_board_loaded rows=0,total=0`），**账号回到取证前原状**，
> 全程未向任何群/频道发送内容。**弹层网格在 406 解决前无法目视验图**，这一半只有单测覆盖。
> 遗留：① **整包预览需 native 侧解掉 `messages.getStickerSet` 的 406**（不解决则预览页与整包页签恒空）；
> ② 取数失败时弹层的 `isInstalled` 恒 false（真实态在 `stickerSetInfo.is_installed`，本可先行显示），
> 装/卸按钮因此可能对已装包重复写；③ `tg://addstickers` 与 `internalLinkTypeStickerSet` 仍未接（DEEPLINK 收尾）。

> **2026-09-26（STICKER-RECENT-101，FEAT-P2-004 表情板「最近使用」接真实数据，结掉 101 遗留 ② / 102 遗留 ③ / MSG-101 遗留 ③）**：
> 这一行从 101 起就是**假的** —— `DEFAULT_RECENT_STICKERS` 四包预设贴纸常驻，屏上永远看不出「这个账号刚才用过什么」，
> 也没有任何一条日志能证明读过 TDLib。而它偏偏是发消息时最常用的一格入口。
> **语义先定案，再动手**：最近使用是**服务端记账**的列表 —— 本端 `MessagesManager` 发出贴纸后从不回调 StickersManager
> 拼条目，TDLib 也**没有** `addRecentSticker` 这种请求，所以客户端只有三种合法动作：
> **读**（`getRecentStickers(is_attached=false)`）、**显式清空**（`clearRecentStickers(false)`）、**收到 `updateRecentStickers` 重读**；
> 自己合成条目就等于造出第二份真相。Android 完全同形
> （`ui/EmojiMediaListController.java:1051` 读、`:309` + `ui/EmojiLayout.java:141` 清空、`:1252-1260` 的 `onRecentStickersUpdated`）。
> **三条判据照板卡、不另起一套**：① **顺序不自作** —— TDLib 回的就是「最近 → 最早」，客户端再排一次只会和另一端打架；
> ② **上限落在登记下载之前** —— `STICKER_BOARD_RECENT_MAX = 20`，`recentStickersFromStickers()`（Kit-free）超过上限的格子
> **连 `downloadFile` 都不登记**（`Grid` 一次性建出全部子节点，先截断才有预算可言），有意不照 Android 的「先 10 张 + 展开」；
> ③ **无文件句柄的不排进发送入口** —— 与板卡同一条丢弃规则。去重闩 `recentRequested` 与 `trendingRequested` 同口径，
> `openStickerBoard` 一次问齐三路（板卡 / 热门榜 / 最近使用）各源独立；`onRecentStickersFailed` **不占 `errorMessage`**
> （那个槽说的是「你自己的包没读到」，最近使用没有就是没有）。**清空是两段**：本地立刻撤（Android 同序）+ 写回服务端，
> **写失败重读真实列表**收敛 —— 否则留下「看着清了、下次打开又全在」的假象。
> **本轮最有价值的一条来自取证，而且是渲染层不是数据层**：`EmojiBoard` 板卡整行的 `ForEach` 键只写 `pack.setId`
> → ArkUI 对同键项**沿用旧子树、不重跑 itemBuilder**，缩略图到货后那一行永远停在首帧的 emoji 兜底，
> 而**同一帧**的包条（键里含路径）已经正常画图 —— 屏上同时出现「栏里是独角兽、行里是 😂」这种自相矛盾的画面。
> 修法是新增纯函数 `stickerBoardPackKey(pack)` = `setId` + 每格 `stickerCellKey`（当前渲染路径）。
> **热门榜那一行在 102 就吃过这个亏**（`stickerTrendingKey` 含 `coverPath`），板卡行是漏网的那一处：
> 只要「数据后到 + 键不含后到的那个字段」，ArkUI 就会把那一格冻在首帧。
> 测试另踩出一个可复用的坑：**coordinator 的订阅注册在 `start()` 里而不是构造函数**
> （`subscribeChatNotificationSettings` / `subscribeChatPermissions` / `subscribeRecentStickers` 都在 `start()`），
> 断言推送行为的单测必须先 `coordinator.start()`，否则表现是「推送发了、状态没翻」的 `expect 1 equals 2`。
> 测试：`feature_chat` **390/390**（375 → 388：模型 +3（标题就是那一句 UI 文案、原序与丢不可发、上限即停止登记下载）、
> reducer +4（只欠最近使用时只发那一条 Effect、初始态为空、`onRecentStickersLoaded` 整段替换、失败保列表保闩）、
> coordinator +6（`is_attached=false` 只问一次、回包填行且只登记缩略图、失败静默不重试、推送只在开板后重读且忽略 attached、
> 清空写回、写失败重读）；388 → 390：`packKey` 到货变键 / 稳定且不撞键），三守卫 0 违规。
> 设备取证（127.0.0.1:5555，`.hvigor/outputs/sr101/`，**全程零写入账号**：没发任何消息、没装任何包，
> `sticker_board_loaded rows=0,total=0` 且 Saved Messages 仍 `No messages yet`）：`sticker_recent_loaded rows=2` 出现两次
> （第二次是缩略图到货后从 DTO 缓存重算）、真推送 `sticker_recent_update attached=0` → 立刻重读同一条请求；
> `dumpLayout` 对照记录同一格从 `Text '😂'` 变成 `Image [25,2277][221,2473]` / `[278,2277][474,2473]`，
> 截图里画出独角兽与那只绿青蛙。**没有点「清空」** —— 那一下会把 `clearRecentStickers` 写到真实账号上且**不可还原**
> （这两条是账号原有数据，不是本次探针留下的），清空那两条分支只有单测覆盖。
> 遗留：① 单条移除（Android 长按删一条，TDLib `removeRecentSticker`）未接；② `getFavoriteStickers`（收藏贴纸）未接；
> ③ TDLib 无 `limit` 参数（列表上限 200 在 `StickersManager.h:1115`），20 只是本端显示口径；
> ④ 发出贴纸后本地乐观前插（cap 32）与权威回灌（cap 20）并存，观感是「先看到自己那张、随后被服务端列表整段替换」；
> ⑤ 动效贴纸无逐帧动画（等 TGS/Lottie 渲染器，届时这一行与板卡/预览页/气泡一起换）。


> **追加（APPLOCK-101，FEAT-P2-008 Passcode 半边）**：四位本地 PIN + 自动锁定档位 + 后台回锁 + 连错冷却。
> **对标 Android `Passcode.java` 的判定表，偏离三条且都写明理由**：
> ① 存放与派生换掉 —— Android 是 SharedPreferences 里「双重 MD5 + 全局固定盐」，对 10⁴ 空间的 4 位数字
> 等于没加盐（一次查表全解），本端存 `salt(16) ‖ sha256(salt ‖ utf8(pin))(32)` 共 48 字节进 Asset Store
> （`ACCESSIBILITY=DEVICE_UNLOCKED`、`SYNC_TYPE=NEVER`），盐一事一生成；
> ② 冷启动**只要设过 PIN 就锁**（Android 不锁）——遮罩必须在 `loadContent` 之前决定，否则解锁前闪一帧主界面；
> ③ 超时从**后台时长**算而不是最后交互时间（用户停在会话页不算在用）。
> 冷却表照抄：level 1 → 30 s，其后 `min(300, 30 + 15*(level-1))`，**每 4 次错误**才进一档；
> `INSTANT = 170ms`、`NEVER = -1` 两个哨兵位保持 Android 数值语义。
> **`set()` 必须是原子的（写完立刻读回、用同一 PIN 重派生并恒定时间比对，不匹配就抹掉回滚成「未设置」）**：
> 本仓不允许卸载重装清数据（TDLib 会话要短信码），所以「写进去一个解不开的锁」是**不可恢复损失** ——
> 宁可设置失败让用户重试，也不能留半个坏秘密。这道防线本轮真的救了一次（见下）。
> **保密边界是这套代码的硬约束**：PIN / 盐 / 摘要不进 `UiState`、不进日志、不进 `AppError`；
> 「确认密码」的比对放在 coordinator 而不是 reducer，正是因为要比的两个值里有一个是密码而 reducer 只看得到 state；
> 摘要比较走恒定时间循环不做前缀短路；`PasscodeStorePort` 不提供任何把盐或摘要读出来的方法。
> **设备取证逼出两个单测结构上抓不到的真 bug**（这是本轮最值得留档的部分）：
> ① `SettingsCoordinator.setAppLockStore()` **声明了、全仓零调用点** —— 于是每一次写入都走 `store === null`
> 分支，屏上永远是一句「Secure storage is unavailable on this device.」。单测抓不到是结构性的：
> fake store 是测试自己 `new` 出来注入的，「装配层忘了注入」这件事只发生在真进程里。修在 `Index.openSettings()`
> 里 `coordinator.setAppLockStore(appLockStore())`，且必须在 `start()` **之前**（`start()` 立刻发 `loadPasscodeState` 读盘）。
> ② `HarmonyPasscodeStore.set()` **只写了 32 字节摘要、没前缀盐** —— `matches()` 只能从这一条资产里取盐，
> 于是每次校验都在拿随机盐和旧摘要比，永远对不上。这条正是上面那道写后读回防线逮住的：
> 回 `passcode-roundtrip-mismatch` 并回滚，**没有留下一个会把用户下次冷启动永久锁在外面的 PIN**。
> **教训（会反复用到）**：界面文案**不分档**时不能作为诊断依据 —— `appLockNoticeKeyForError` 把除
> `passcode-secret-corrupt` 之外的**所有**错误塌成同一句 store 话术，所以「没注入 store」和「资产真读不到」
> 在屏上长得一模一样，一度得出「模拟器没有安全存储」的错误结论（实际 `asset_service` 好好在跑）。
> 字节长度不是秘密值，取证时**临时打印写入/读回长度**是安全的（`32` vs 期望 `48` 一句话定案），用完删掉。
> 设备取证（模拟器 127.0.0.1:5555，`.hvigor/outputs/al101/`，全程未发消息、未动账号数据）：
> 设 PIN → `passcode-inline-notice 'Passcode set.'` + `passcode-toggle-state 'On'`；退后台回前台**回锁**；
> 连错 4 次进冷却并倒计时 `'Too many attempts. Try again in 29s'`，**冷却期内输入正确 PIN 仍拒**（短路在触盘之前）；
> 冷却到期正确 PIN 解锁；`aa force-stop` 冷启动直接是遮罩；档位循环六档且**重启后仍在**；
> 切到 `'After 5 minutes'` 后 3 秒后台**不锁**（证明计时用的是档位而不是常量）；移除 PIN →
> `'Passcode removed.'` + `'Off'`，冷启动无遮罩。收尾已把本机状态还原（PIN 已移除、档位回 `'Immediately'`、隐私页 `Screen Lock` 行读回 Off）。
> 测试：应用锁四份用例文件 **60** 条（`core_domain` AppLock 11 + PasscodeFlow 5、`feature_settings` PasscodeReducer 24、
> `entry` AppLockGate 20），模块全量 `core_domain` **177/177**、`feature_settings` **254/254**、`entry` **117/117**，
> 三守卫 + secret_scan 0 违规。**`platform/keystore` 没有 `src/test` 目录**，因此该模块 `hvigorw test` 结构上跑不起来
> （Rollup 找不到 `src/test/List.test`）—— 这一层是 Kit 相关代码，本轮由设备取证覆盖。
> 遗留：① FEAT-P2-008 的**生物识别**与**活跃会话管理**两半未做；② 无「显示输入中的密码」小眼睛（Android 有）；
> ③ 遮罩是应用内 overlay，不是系统级锁屏，拔电池/刷机不在防护范围；④ sha256 单次迭代不抗取证，
> 强度与 Android 同级（换 PBKDF2/HMAC 需要同时定档迭代数与首启耗时）；⑤ 改密码中途退出不锁死（秘密尚未变更，已按此设计）。


> **追加（A11Y-101，FEAT-P2-011 无障碍半边）**：全仓**只有图标、没有文字**的可按控件补无障碍标签 —— 本轮之前
> 这样的控件全仓 **56 处零标签**，屏幕朗读下聊天页头部一排按钮念出来是「按钮」两字，用户不知道哪个是搜索、哪个是附件。
> **口径**：ArkUI 的 `.accessibilityText(value)` 才是 Android `setContentDescription` 的对应物（覆盖控件自身文本、
> 供读屏单独播报）；`accessibilityDescription` 是「补充描述」，语义上对应 Android 的 `contentDescription` 之外的 hint，
> 所以本包统一走 `accessibilityText`。
> **一条实测的取证边界（很重要，别再重复走一遍）**：`uitest dumpLayout` **根本不导出 `accessibilityText`** ——
> 本轮在同一份布局上做过对照：临时给一个控件挂 `accessibilityDescription('A11YDESC-PROBE')`，dump 里以 `description`
> 字段如实出现；而同页 20+ 处 `accessibilityText(...)` **一个字段都没有**。也就是说这类改动
> **不能靠 dumpLayout 做 A/B 自证**（打开屏幕朗读同样在 dump 里看不出差别），可强制的防线只剩**静态守卫 + 词典级单测**；
> 设备侧能自证的只有「没把页面点崩」（本轮收尾重跑了一次：会话列表 107 节点、文案与上一轮一致）。
> 附带两条工具事实：dumpLayout 想稳定拿单一窗口要加 `-b <bundleName>`（否则系统窗口和 SR 的引导气泡会混进来）；
> `-p /dev/stdout` 不支持，落盘到 `/data/local/tmp` 再 `file recv`；屏幕朗读关不掉时用
> `aa force-stop com.huawei.hmos.screenreader`（比在设置页里双击切换可靠，`client num: 0` 才算真关掉）。
> **标签不许散落写字符串**：`tools/ci/generate_a11y_labels.py` 里的 `LABELS` 是**唯一清单**（42 个槽位，
> 每项带 key / 英文 / 中文），同一个脚本生成 `core/common/A11y.ets`（槽位类 + `A11Y_SLOTS` + `a11y()`）
> **并把词条注入 `Lang.ets` 的中英文两张表**（`A11Y-101 BEGIN/END` 标记之间）——「表里有 = 词典里有」是构造出来的，
> 不靠人记。页面写法固定 `a11y(A11y.SLOT[, args])`，带参槽位（`Open profile, {1}`、`{1} sticker`）走 `Lang.getString` 的变参。
> **守卫 `tools/ci/check_accessibility_labels.py`（CI 第 6 步 / 共 10 步）三条规则**：
> R1 覆盖（图标控件必须有标签）、R2 路由（参数必须以 `a11y(` 开头并引用 `A11y.X`，禁止字面量）、R3 翻译（声明的槽位中英都要有）。
> R2 有一处例外要写清：媒体气泡的标签随下载/播放态变化，这条判定抽成纯函数
> `feature/chat/model/MediaA11y.ets:mediaCircleA11ySlot()`（失败 > 上传中 > 下载中 > 未下载 > 不可播 > 播放/暂停），
> 守卫放行白名单内的槽位来源函数，函数体由单测断言而不是由正则断言。
> 测试：`core_common` 新增 2 条（**42 个槽位在中英两种语言下都能取到非空、且不等于 key**；带参槽位的实参真替换进去）、
> `feature_chat` 新增 6 条（优先级六分支）。**一条反直觉的坑**：EN 表以英文句子本身为 key，
> 所以复用通用文案时（`A11y.CANCEL = 'Cancel'`）`getString('Cancel','en')` **合法地回显 key**，
> 「回显即缺翻译」的启发式只对 `A11y*` 前缀的 key 和 ZH 表成立。
> 遗留：① RTL（FEAT-P2-011 的另一半）与平板双栏未做；② `accessibilityLevel`/焦点顺序未管（读屏下的遍历次序还是布局次序）；
> ③ 系统 dumpLayout 看不到 `accessibilityText`，若将来要在设备上验证播报内容，只能靠真机 SR 听或 `hilog` 的 SR 文本，
> 本轮 1.1MB `sr_hilog.txt` 里没找到可用的应用侧播报行。

> **追加（APPLOCK-102，FEAT-P2-008 的「显示输入中的密码」半边 + `platform/keystore` 进 CI）**：
> **先纠正上一段自己写的口径**：Android 的 `pc_visible` **不是输入框上的「小眼睛」按钮**（`PasscodeView` 里没有任何
> 切换控件），而是「屏幕锁定」子页里的一条**持久设置行**。本端因此做的是一行 **Show Typed Passcode**，
> 不是键盘上的图标 —— 上一段把它写成「小眼睛」会让人去找一个 Android 里根本不存在的按钮。
> **明文档照 Android 的三档语义**，抽成 `core/domain` 纯函数 `passcodeStageReveal(stage, visiblePref)`：
> `enter` **恒明文**（`PasscodeController.java:663`）、`confirm` **恒圆点**（`PasscodeView.java:238-240` 配一句「重复一遍」）、
> 其余阶段（验旧密码、锁屏遮罩）跟随偏好。理由：正在定的密码看不见等于给自己埋坑；比对步明文则让「抄上一步」
> 和「真的记得」看起来一样。**偏好落点**：`entry/store/AppLockStore` 的 `appLockPinVisible`（0/1 整数，取不到按 `=== 1`
> 判为关）→ `PasscodePort.passcodeVisible()/setPasscodeVisible()`（端口里**没有任何把密码读出来的方法**，这条不是秘密值）
> → 设置页与 `AppLockGate.passcodeVisible()` **读同一份缓存**，所以「设置里说明文、锁屏上按圆点」这种两套真相结构上不可能。
> reducer 走乐观翻转 + `PersistPasscodeVisibleEffect`，写盘失败由 `PasscodeVisibleRejected` 回滚。
> **键盘侧** `@Prop reveal`：明文位只在 `slot < entry.length` 时渲染数字，空位仍是圆点 —— 不暴露「输了几位」之外的信息；
> 节点 id `passcode-reveal-<n>` 是本轮取证的可观察点。
> **`platform/keystore` 第一次进 CI**：把 Kit-free 的判定从两个 adapter 里抽出来 —— `core/PasscodeSecret.ets`
> （长度常量、`isAsciiDigits`/`validatePin`/`pinBytes`、`packSecret`/`unpackSecret`（48 字节 = 盐 16 + 摘要 32，
> 长度不符回 `passcode-secret-corrupt` 且**消息里只带字节数**）、`constantTimeEquals`）与 `core/AssetErrorMap.ets`
> （alias 前缀、`ASSET_*` 码表、`isRetryableAssetCode`、`mapAssetFailure`、`probeAvailability`），两个 adapter 只剩 Kit
> 调用与 catch 分支；`tools/ci/test_all_modules.py` 撤掉 `platform_keystore` 豁免（现在只剩 `platform_files` 一项）。
> **生物识别拆到 APPLOCK-103，理由是环境不是工作量**：装机 SDK 里只有 OpenHarmony 的 `@ohos.userIAM.userAuth`
> （没有 HMS 生物识别 Kit），本快照的 `@ohos.security.asset` **没有** `AUTH_ACCESS`/`ACCESS_WHEN_LOCKED` 标签
> （HUKS 侧倒是有 `HUKS_TAG_USER_AUTH_TYPE`/`AUTH_TIMEOUT`/`AUTH_TOKEN`/`KEY_AUTH_PURPOSE`，即「鉴权绑定密钥」
> 这条路在 HUKS 成立、在 asset 不成立），且模拟器没有指纹/人脸传感器 —— 写了也验不了。顺带记 Android 的真相：
> `pc_finger_hash = MD5(MD5(0 + SALT_OLD))` 是个**常量**、不绑定任何生物特征模板，那套生物识别本身就是安全剧场；
> 本端要做就做 HUKS auth-bound key，不做「存个哈希当开关」。
> **设备取证**（`.hvigor/outputs/applock102/`，127.0.0.1:5555，全程只在设置页内、未发消息）：A/B 覆盖四条分支 ——
> `enter` 在偏好 Off 时仍出 `passcode-reveal-0='4'`/`-1='2'`（证明恒明文不受偏好影响）、`confirm` 恒 4 个 Column 圆点、
> `verify-change` 在偏好 Off 时是圆点、偏好 On 时验旧密码出明文；点行让 `passcode-visible-state` 在 `'Off'`↔`'On'`
> 之间翻转，且 `aa force-stop` 冷启动后**仍是 On**（落盘成功），冷启动遮罩在偏好 On 时渲染 `passcode-reveal-0='4'`、
> 偏好 Off 时渲染 4 个圆点且**零** `passcode-reveal-*` 节点（「设置页与遮罩共用同一份偏好」至此得证）；
> 两条分支各用正确 PIN 解锁成功。收尾还原：PIN 移除（`'Passcode removed.'` + `passcode-toggle-state 'Off'`）、
> 档位 `'Immediately'`。**残留一处**：`appLockPinVisible` 停在 `1`（移除 PIN 后该行不再显示，偏好惰化，无可见状态差异）。
> **一条工具事实（本轮为它绕了远路）**：`hdc shell uitest uiInput click $xy` 在 zsh 下**不做词分割** ——
> `xy="217 1633"` 会作为**一个**参数送进去，uitest 回 `No Error` 却什么都没点。表现是「键盘吞输入」，
> 一度以为组件有 bug（`busy` 卡死 / `entry` 被清空）。循环里发 uiInput 要么写死两个参数，要么 `${=xy}` 强制分割。
> 测试：`platform_keystore` **16/16**（该模块首套用例）、`core_domain` **178/178**（`passcodeStageReveal` 五分支）、
> `feature_settings` **258/258**（偏好回读 / 乐观翻转 / 回滚 / 不触碰密码流 4 条）、`entry` **117/117**
> （fake store 补齐端口新增的两方法），四守卫 + secret_scan 0 违规。
> 遗留：① 生物识别（APPLOCK-103，需真机 + HUKS auth-bound key 设计）；② 改密码中途退出不锁死已按此设计、
> sha256 单次迭代不抗取证（与 Android 同级）；③ 移除 PIN 时不清 `appLockPinVisible`（本端认为「偏好属于用户，
> 不属于这条秘密值」，Android 同样保留 `pc_visible`）。

> **追加（PRIVACY-101，FEAT-SET-005 的隐私项详情页半边）**：把 SELF-102 那套「点一行=循环写回」换成 Android 的
> `SettingsPrivacyKeyController` 结构 —— 独立详情页 = 主档位单选 + Premium 勾 +「总是允许 / 从不允许」两条例外名单
> + 联系人多选器。三条语义从 Android 抄死：**提交时机**是离开页面（`onBlur()` 里的 `saveChanges()`），页内改多少下
> 都不落盘，且 `nothingChanged()` 时连写都不发（设备取证第二轮复原路径上 `write` 那一行**根本没出现**）；
> **`allowAll`/`restrictAll` 是终止规则**，命中即停止扫描、也停止收集 id，所以「所有人 + 例外某人」的可观察口径是
> 主档位仍为 Everybody 而名单非空；**例外改写**是新选名单 `unshift` 到最前、同 id 从对侧剥掉、剥空的那条规则整条删除。
> 例外行的值照 `Lang.plural(xUsers)`：0 → `Add Users`、1 → `1 User`、n → `N Users`（原先自造 `No Exceptions` 与
> `1 Users` 已换掉）。**不做乐观更新**：写后一律以回读为准，因为服务端会归一化 —— 实测写
> `[allowUsers, allowContacts, restrictAll]` 读回 `[allowUsers, allowContacts]`（尾部 `restrictAll` 被 TDLib 丢掉），
> 解析结果仍是 `contacts`，所以本端不能假设"写进去的就是读出来的"。
> 一处**守卫口径缺陷**顺带修掉：`tools/ci/check_design_tokens.py` 原先只认 `T.<ns>.<name>`，而详情页写的是
> `this.getTheme().typography.title3`（`title3` 不存在），正则看不见这种接收者 → 装真机一开选择器就
> `TypeError: Cannot read property fontSize of undefined` 被 ArkUI 记成 JsError **杀进程**。改成不限定接收者
> （`\.(typography|colors|spacing|radius)\.\w+`），并用一次性探针文件验过 A/B（能抓到、清理后 0 误报）。
> 契约侧：原来 3 条一次性 intent 被 12 条（进页/选档/勾 Premium/开合选择器/勾选/完成/离开…）替代，规则模型
> `PrivacyRules`（有序数组 + 档位解析）与视图模型 `PrivacyDetail`（例外行 + 选择器种子）都是 `core` 内 Kit-free 纯函数。
> 测试：`feature_settings` **286/286**、`core_common` **52/52**（Lang 键替换），四守卫 0 违规。
> 设备取证（127.0.0.1:5555，`.hvigor/outputs/privacy101/`）：基线 `rules=[allowAll]` → 简介项（`show_bio`，挑的是
> 影响最小的一键）改 contacts（Premium + 两条例外行同时出现）→ 选 `be hu` → Done → `1 User` → 离开 → `write <- [allowUsers, allowContacts, restrictAll]` →
> 读回 `[allowUsers, allowContacts]` → 列表行 **My Contacts** → 重开（选择正确回灌）→ 取消勾选 → Everybody →
> 离开 → `write <- [allowAll]` → 读回 `rules=[allowAll]` → 列表行 **Everybody**，**账号状态已还原**，其余 7 项隐私键未碰。
> 遗留：① 例外名单只支持"人"（Android 还能选已加入的群/频道成员，本端 `allowChatMembers` 只读不回写）；
> ② `PrivacySettingsActivity` 里 `btn_togglePermission` 那一类布尔开关项（自动删除、通话允许联系人等）尚未拆包。

> **追加（PRIVACY-102，FEAT-SET-005 上一条遗留 ①）**：例外名单现在装得下**会话成员**，选择器从一列联系人变成
> 「我的联系人 / 群聊」两个分区。四件事照 Android `PrivacySettings` 钉死，各自都有非显然的根据：
> ① **写的是会话本身的 id**（`allowChatMembers` / `restrictChatMembers` 的 `chat_ids`），生效范围是"该会话的全体成员"，
> 所以名单里一条会话在语义上等于几百个人 —— 因此候选会话只取 `getChats(chat_list=null)` 与规则里已引用的 id 的并集
> （30 条上限，**不接 `searchChatMessages`**：Android 那个搜索框查的是"人"，为会话做全库搜索会误导）；
> ② **频道不可选**（`privacyChatSelectable`：basic group 恒可选，supergroup 仅在 `is_channel=false` 时可选，
> 照 `FLAG_NO_CHANNELS`；private 会话是"人"，归联系人分区）；
> ③ **插入位置按方向不对称** —— Android `withExceptions`（790-925）里 allow 侧往前扫到"终结/一般规则"才停，
> 于是新会话规则落在 `allowContacts` **之后**、`restrictAll` 之前；restrict 侧把 premium/bots/会话成员都算"一般规则"，
> 于是新会话规则**紧跟用户规则**。同向剥离另一侧时**保留那条规则自己的方向**（不是照抄新名单的方向），剥空则整条丢弃；
> 偏离 Android 两处并留档：bots 规则原样不动、分类读的是 `newRules` 而不是 Android 那个边写边循环的过期 `rules` 字段；
> ④ **例外行的计数是成员数，不是会话条数**（`getPlusTotalCount`）：一条 5756 人的群在行末就写 `5756 Users`，
> 成员数取不到时按 0 计（宁可少报不猜），来源是 `core/domain` 的 `GroupRegistry`（懒建 + `destroy()` 时 `stop()`）。
> 另外把 Android 的三项**逐键门控**补齐：`allow_find_by_phone` 没有「没有人」档位、也**根本没有例外名单**
> （整块卡片不渲染，留空卡等于承诺一个不可编辑的功能）；`show_last_seen` 的两行读「Always/Never **Share With**」，
> 其余项读「Always/Never Allow」—— 且**选择器标题沿用打开它的那一行的标题**（取证时逼出这一处：Bio 页面上一行写
> `Never Allow`、点进去标题写死 `Never Share With`，同屏两套话术）。
> 测试：`feature_settings` **304/304**（286 → 304：会话成员规则的插入顺序/方向剥离/计数、选择器双分区勾选互不污染、
> 三项门控），四守卫 0 违规。
> 设备取证（127.0.0.1:5555，`.hvigor/outputs/privacy102/`）：`privacy_chats candidates=2,withMemberCount=2` →
> 简介项（`show_bio`，仍是影响最小的一键）基线 `rules=[allowAll]` → 「从不允许」选择器两个分区都在（`be hu` /
> `El CLUB · 5756 members` / 另一群 647 人）→ 勾群 → Done → 行末 `5756 Users` → 离开 →
> `write <- [restrictChatMembers, allowAll]` → **读回同一形状**（服务端接受会话成员规则）→ 重开选择器**已勾选正确回灌** →
> 取消勾选 → Done → 离开 → `write <- [allowAll]` → 读回 `[allowAll]`，**账号状态已还原**；另实证「无改动离开」
> 一条 `write` 都不发，`allow_find_by_phone` 只有两档无例外卡，`show_last_seen` 行与标题都读 `Never Share With`。
> 遗留：例外名单里**会话名靠 `getChat` 现取**，退群后那条规则仍在（Android 同样不清理）；
> `btn_togglePermission` 一类布尔开关项仍未拆包。


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
