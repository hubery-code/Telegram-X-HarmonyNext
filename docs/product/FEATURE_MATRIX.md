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
> 遗留：`can_send_other_messages` 尚未驱动 `EmojiBoard` 里的贴纸/GIF 页签；`can_send_audios` 本端附件菜单无「音乐」入口可置灰；
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
> 遗留：代理 ping 延迟副标题与连接态（Android `ProxyListController` 的 `pingProxy` + `updateConnectionState`）、
> "Switch automatically"、通话是否走代理、`tg://proxy` 分享链接的确认弹窗（`openProxyAlert`）、扫码导入、
> 多端改代理的实时推送（本端只订阅不到 `updateProxy`）；FEAT-P2-007 的**下载与自动缓存策略半边**当时未动（现已交付，见下方 AUTODL-101 追加段）。
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
