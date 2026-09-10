# Telegram X → HarmonyOS NEXT 迁移 — 工作协调看板

> 本文件是多 AI 并行协作的**单一协调入口**。开始任何工作包前，必须先在「进行中」登记；完成后移到「已完成」并写明证据（构建命令、commit、测试结果）。
>
> 状态机：`Backlog → Contract Ready → Implementing → Verifying → Accepted`，或 `Blocked / Deferred`。
> 规则来源：`/Users/mbjpeng-yu01/Downloads/Telegram-X-HarmonyOS-NEXT-迁移实施计划.md`（下称「计划」）。
>
> ⚠️ 目录约定：计划中的 `harmony/` 前缀由用户指定取消——**本仓库根目录即 HarmonyOS 工程根**（对应计划的 `harmony/` 内容），Android 参考工程仍在 `/Users/mbjpeng-yu01/androidProjects/Telegram-X`。

## 环境基线（已锁定，GOV-002）

| 项目 | 版本 / 路径 |
|---|---|
| DevEco Studio | `/Applications/DevEco-Studio.app` |
| HarmonyOS SDK (OpenHarmony) | API 26 / platform 26.0.0.105，路径 `…/sdk/default/openharmony` |
| Native (NDK/clang) | 同上 `native/` 子目录，API 26 |
| Hvigor | DevEco 内置 `…/tools/hvigor/hvigor`（wrapper 已拷入仓库 `hvigorw`） |
| Node（构建用） | DevEco 内置 `…/tools/node/bin/node`（勿用系统 node 23 跑 hvigor） |
| 设备 | Phone / arm64 优先（D-009）；x86_64 仅模拟器/CI |

## 进行中（Implementing）

| 工作包 | 负责人(AI) | 开始时间 | 说明 |
|---|---|---|---|
| MSG-101 富文本实体渲染 | 主会话(Kimi) | 2026-09-10 | formattedText entities → span 渲染，气泡+列表预览共用 |

> ⚠️ 并行约定：**不要执行 git commit**，完成后报告文件清单由主会话统一提交。core/account 禁止 import ArkUI/Kit。项目内有 `.agents/skills/harmony-next/` 离线参考（API 12-23 快照），编码遇 API 问题可查。

## 待认领（Backlog）

> Phase 0–3 工作包全部完成（见「已完成」表）。以下为按 **计划 §9.6** 从 Phase 4/5 Epic 拆出的工作包（0.5–3 天/包，非生成代码 ≤800–1200 行），范围对齐 `docs/product/FEATURE_MATRIX.md` 的 P1 缺口。依赖列空=现在可做。

### MSG Epic（富文本实体、转发、已读、反应等；回复/编辑/删除已由 CHAT-004 完成）

| 工作包 | 依赖 | 一句话 |
|---|---|---|
| MSG-101 | — | 富文本实体渲染：formattedText entities → Text span（bold/italic/underline/strike/code/pre/spoiler/mention/url/textUrl），气泡与会话列表预览共用提取逻辑 |
| MSG-102 | — | UserRegistry（core/domain）：getUser 缓存 + updateUser 订阅；群消息显示发送者名/彩色头像（FEAT-MSG-002） |
| MSG-103 | MSG-101 | 日期分隔条 + 未读消息分隔线（按 date 计算插入位置） |
| MSG-104 | — | 已读上报 viewMessages（入屏上报）+ 发出消息单勾/双勾/已读态（updateChatReadOutbox）+ 失败气泡点击重试（FEAT-MSG-004） |
| MSG-105 | MSG-101 | 复制文本到系统剪贴板 + url/textUrl 可点击打开（FEAT-COMP-007） |
| MSG-106 | — | 转发：多选消息 → 会话选择器 → forwardMessages（FEAT-COMP-004） |
| MSG-107 | MSG-101 | 链接预览：发送带 linkPreviewOptions + 气泡渲染 linkPreview 卡片（FEAT-COMP-002） |
| MSG-108 | — | 置顶/取消置顶会话（FEAT-CHAT-002）+ 手动标未读（FEAT-CHAT-004 部分） |

### FILE Epic（下载/上传基础设施，MEDIA 全部依赖）

| 工作包 | 依赖 | 一句话 |
|---|---|---|
| FILE-101 | — | FileRegistry（core/domain）：file 状态单一事实源、updateFile 订阅、DownloadFile/CancelDownloadFile 请求、本地路径解析 |
| FILE-102 | FILE-101 | FileStore：并发上限、优先级、暂停/恢复、断网挂起重试 |
| FILE-103 | FILE-101 | 传输失败重试/取消 UI 路径（FEAT-MEDIA-005） |

### MEDIA Epic（图片/视频/文件/语音）

| 工作包 | 依赖 | 一句话 |
|---|---|---|
| MEDIA-101 | FILE-101 | 图片消息气泡：缩略图自动下载渲染、宽高比占位、进度圈（FEAT-MEDIA-001 收侧） |
| MEDIA-102 | MEDIA-101 | 图片发送：photoViewPicker 选图 → SendMessage(InputMessagePhoto) + 上传进度（FEAT-MEDIA-001 发侧） |
| MEDIA-103 | MEDIA-101 | 图片全屏 viewer：缩放/左右翻页（FEAT-MEDIA-006 图片部分） |
| MEDIA-104 | FILE-101 | 文件消息气泡（名称/大小/下载态）+ 完成可打开（FEAT-MEDIA-003） |
| MEDIA-105 | MEDIA-103 | 视频消息：缩略图 + 下载 + 播放（FEAT-MEDIA-002） |
| MEDIA-106 | FILE-101 | 语音消息录制/发送/播放、波形（FEAT-MEDIA-004，~2 天） |

### COMPOSER / SEARCH / NOTIF / ACC / SETTINGS Epic

| 工作包 | 依赖 | 一句话 |
|---|---|---|
| COMPOSER-101 | — | 草稿：SetChatDraftMessage + 离开保存/重进恢复 + 列表草稿前缀（FEAT-CHAT-005） |
| COMPOSER-102 | MEDIA-102 | 附件面板（相册/文件/拍摄入口） |
| SEARCH-101 | — | 全局搜索页：SearchChats/SearchPublicChats/SearchMessages 分组 + 防抖（FEAT-SEARCH-001） |
| SEARCH-102 | SEARCH-101 | 聊天内搜索 + 结果跳转定位（FEAT-SEARCH-002） |
| NOTIF-101 | AGC 配置 | Push Kit token → RegisterDevice 闭环（FEAT-PUSH-001；AGC/签名配置需用户确认） |
| NOTIF-102 | NOTIF-101 | 通知聚合 + 点击路由直达聊天（FEAT-PUSH-002） |
| ACC-101 | CORE-003 | 多账号切换 UI + 添加账号入口（FEAT-ACC-002/003；框架已有） |
| SET-101 | — | 设置主页：账号信息 + 通知/存储/语言入口（FEAT-SET-001）+ 登出（FEAT-AUTH-006） |
| SET-102 | SET-101 | 深色/浅色主题跟随系统/手动切换（FEAT-UI-001；design token 已有） |
| SET-103 | SET-101 | 中/英语言切换 + 关键路径文案资源化（FEAT-SET-002/UI-003） |
| SET-104 | FILE-101 | 存储占用展示 + 一键清理（FEAT-SET-004） |

### P2 及以后（Phase 5 Beta，暂不拆包）

GROUP / PROFILE / SHARE / A11Y / ADAPTIVE Epic 及 FEATURE_MATRIX P2/P3 项：Phase 4（G4 核心聊天 MVP）不启动，进入 Phase 5 前再拆。

> 认领规则：一次只认领一个工作包；认领时把行移到「进行中」并注明你的身份和计划开始的内容。禁止修改未授权目录。

## 已完成（Accepted 或有保留）

| 工作包 | 完成日期 | 证据 |
|---|---|---|
| E2E-001 G3 核心场景端到端验收 | 2026-09-10 ✅（有保留） | 真机 VYG-AL00 实测 G3 全链路（计划 §739：启动→登录→会话列表→打开聊天→收发文本→断网恢复→杀进程重启恢复）：启动/登录/会话列表/打开聊天/收发文本分别由 AUTH-E2E-001/CHATLIST-003/CHAT-001~003 验证记录覆盖；**断网恢复**（本轮实测）：用户关 VPN+移动数据 → 会话列表本地缓存正常渲染（6 会话）→ 进 be hu 发 "offline_test" → 气泡上屏带 pending "18:25 ..." → 恢复网络 → TDLib 自动重发 → "..." 消失变正常气泡（时间 18:27）；**杀进程重启**（本轮实测）：`aa force-stop` + 冷启动 → 直接进会话列表（首会话 be hu 预览 offline_test），无登录页残留；错误路径：editMessageText 超时 → `network/timeout/retryable=true` 回灌 errorMessage 细条；权限拒绝：CHAT-004 验证对方消息菜单无 Edit。**保留项**：空数据路径（EmptyView）未现场演示（账号无零消息会话）；取消路径已由 CHAT-004 编辑/回复 X 取消覆盖 |
| CHAT-004 回复/编辑/删除基础动作 | 2026-09-10 ✅ | 子agent-54 + 主会话真机验证（commit `573791e`）：长按气泡→getMessageProperties（离线）拉权限位→reducer 过滤（回复恒可/编辑仅己方文本且 canBeEdited/删除需 canBeDeleted 之一）→底部动作面板；composer 回复/编辑预览条（编辑暂存草稿、取消/返回恢复）；发送按模式分流 reply_to/editMessageText；删除 revoke=canBeDeletedForAllUsers + 响应 ok 乐观本地移除；editMessageText 响应本体 upsert 落本地（不依赖 update 推送时序）；气泡 "edited" 标记与 "↪ 摘要" 引用行；失败统一回灌 errorMessage 细条；21 个 reducer 纯单测全过。真机（VYG-AL00）：对方消息菜单无 Edit ✓；己方三键齐全 ✓；编辑预览条/取消恢复 ✓；be hu 编辑 editMessageText ok + 重进确认新文本+edited ✓；删除即时消失 ✓；回复 0reply_ok 带 ↪hello_from_harmony 引用行上屏 ✓；Wallet 官方通知会话编辑超时（服务器不响应，会话特例）；期间 VPN 抖动出现 network/timeout 错误回灌正常 |
| CHAT-003 composer + send text | 2026-09-10 ✅ | 子agent-50 + 主会话真机验证：`MessageProjection.sendTextMessage`（inputMessageText 组包 sendMessage，空文本参数拒绝）+ 补 `updateMessageSendSucceeded/Failed` 结算（删临时 id、upsert 正式/失败态）；feature/chat MVI 三新 intent + SendTextMessage effect，reducer 发送即清 composerText；ChatPage 底部 ComposerBar（圆角输入框+激活态圆形发送钮、受控输入、回车可发、失败细条不挡列表、气泡 pending '…'/failed '!'）；4 个 reducer 纯单测全过；`assembleHap` BUILD SUCCESSFUL。真机：be hu 私聊发送 hello_from_harmony → sendMessage ok、气泡即刻上屏、输入框清空；他端消息经 updateNewMessage 实时进列表。commit 见 git log |
| CHAT-001 会话消息页 + CHAT-002 文本气泡基础 | 2026-09-10 ✅ | 子agent-35：`core/domain` 新增 `chat/MessageProjection.ets`——单会话消息投影：openChat/closeChat 生命周期、订阅 updateNewMessage/updateMessageContent/updateMessageEdited/updateDeleteMessages（仅本 chatId）、`loadInitialMessages`（from=0, offset=-limit+1）与 `loadOlderMessages`（from=最旧 id, offset=-1，Map 按 id 去重、按 id 升序、回包不足一页或无新增判定到顶）；新建 `feature/chat` har 模块（`@tgx/feature-chat`）：MessageItem/ChatUiState/ChatIntent/ChatEffect/chatReducer（纯函数 MVI）+ ChatCoordinator（桥接 projection，setTimeout(0) 合并同步，Message→MessageItem 文本提取，多媒体 `[Photo]` 占位）+ ChatPage（LazyForEach 气泡：发出右对齐 chatOutgoing/收到左对齐 chatIncoming、HH:mm 时间戳、onReachStart 翻页、首屏/新消息滚到底、空/加载/错误三态、返回箭头）；ChatListCoordinator 构造器加可选 `onNavigateToChat(chatId, chatTitle)` 回调（缺省 no-op，NavigateToChat effect 从 registry 取标题后回调）；entry `Index.ets` 加 currentChatId 导航态，回调里创建/订阅/销毁 ChatCoordinator 并在 ChatListPage/ChatPage 间切换渲染；根 build-profile 追加 feature_chat 模块、entry oh-package 加 @tgx/feature-chat 依赖与 oh_modules 符号链接；`./hvigorw assembleHap --mode module -p module=entry@default -p product=default -p buildMode=debug --no-daemon` BUILD SUCCESSFUL（22s，产物 entry-default-signed.hap）；`./hvigorw test --mode module -p module=core_domain@default` BUILD SUCCESSFUL 不回归；真机验证待主会话 |
| CHATLIST-003 chat list 接入真实 TDLib 数据 | 2026-09-10 ✅ | 子agent-33：`core/domain` ChatListProjection 新增 `setOnStateChanged` 变更回调（setChatPosition/loadNextPage 各路径触发）+ `updateChatLastMessage`（刷新 last_message 并按携带 positions 重排）与 `updateChatReadInbox`（未读数）处理；新建 `feature/chat_list/coordinator/ChatListCoordinator.ets`——桥接 projection 与 MVI：dispatch 经 chatListReducer、FetchChatList→`loadNextPage`，projection 变更经 setTimeout(0) 合并后映射 Chat→ChatListItem 并回灌 OnChatsLoaded（messageText 取原文去换行，多媒体按类型出 `[Photo]` 等占位标签）；投影列表标识用 `new ChatListMain()`（chatListEquals 对 null 恒不等，传 null 永不匹配）；entry `Index.ets` 占位文本替换为 `ChatListPage`，auth `ready` 时用 `BootstrapResult.scope` 创建/订阅/销毁 coordinator；`feature/chat_list` oh-package 增加 core-account/core-domain/core-td-api-generated 依赖并补 oh_modules 符号链接；`./hvigorw assembleHap --mode module -p module=entry@default -p product=default -p buildMode=debug --no-daemon` BUILD SUCCESSFUL（14s，产物 entry-default-signed.hap）；`./hvigorw test --mode module -p module=core_domain@default` BUILD SUCCESSFUL 不回归；真机验证待主会话 |
| AUTH-E2E-001 真机扫码登录与登录态恢复 | 2026-09-10 ✅ | Codex + 用户真机验证：通过 TDLib QR 登录完成真实账号授权，授权页切换到 `chat_list`；随后执行 `aa force-stop org.telegram.x.harmony` 并从桌面图标冷启动，应用未再次显示登录页，直接恢复到 `Chat list placeholder`，证明 TDLib 授权数据库和账号恢复链路生效。当前后续缺口明确为 Entry 会话列表占位尚未接入真实 TDLib chat 数据。 |
| ENTRY-ICON-001 桌面图标启动入口修复 | 2026-09-10 ✅ | Codex：定位桌面图标原先解析到 `AppDetailAbility`（系统应用详情页），而 HDC 显式启动才进入 `EntryAbility`；在 `entry/src/main/module.json5` 为 EntryAbility 补齐 `entity.system.home` + `ohos.want.action.home` skills。`entry assembleHap` BUILD SUCCESSFUL，真机覆盖安装后从桌面图标点击，日志确认 `EntryAbility.onCreate`、bootstrap、setTdlibParameters 成功，页面显示手机号与 QR 登录入口。 |
| AUTH-QR-001 reCAPTCHA 阻塞兜底与二维码登录 | 2026-09-09 ✅ | Codex：确认 `updateApplicationRecaptchaVerificationRequired` 仅面向受支持的官方移动端集成，移除把 Android 移动端 key 塞入 WebView 的无效实现；收到 challenge 后以空 token 调 `setApplicationVerificationToken` 明确结束挂起验证，并接入 TDLib `requestQrCodeAuthentication` + `authorizationStateWaitOtherDeviceConfirmation.link` + ArkUI `QRCode`。新增 5 个 reducer/coordinator 用例；`feature_auth test`、`assembleHar`、`entry assembleHap` 全部 BUILD SUCCESSFUL。真机 6XE0225A27023538 安装成功，日志确认 `VERIFICATION_FAILED` 被安全释放、`requestQrCodeAuthentication` 执行且 QR link 到达，页面实际显示可扫描二维码；commit `1c9dc5c`。 |
| LIFE-001 EntryAbility 前后台协调 | 2026-09-09 ✅ | AI-Agent-Antigravity：`entry/lifecycle`（LifecycleCoordinator：restoreAll 杀进程恢复与兜底建号、onForeground/onBackground 状态流转、NetworkStatePort.observe 动态网络监听、mapSnapshotToNetworkType 映射 SetNetworkType 广播至各活跃 scope、onDestroy 退订与关闭）；EntryAbility 回调（onForeground/onBackground/onDestroy）全链路接通；Bootstrap 装配 ConnectivityAdapter；`assembleHap` BUILD SUCCESSFUL（生成 entry-default-signed.hap 51MB）；commit `dab01fd` |
| CHATLIST-001 chat list domain projection | 2026-09-09 ✅ | AI-Agent-Antigravity：新建 `core/domain` 模块（`@tgx/core-domain`）；ChatRegistry 单一事实源 + ChatListProjection（order 64位 BigInt 降序排列、(order, chat.id) 比较、增量位置更新、loadNextPage 分页）；`assembleHar` BUILD SUCCESSFUL；commit `75e8613`+`63f75b7` |
| CHATLIST-002 chat list ArkUI | 2026-09-09 ✅ | 子agent-27：`feature/chat_list` har 模块（`@tgx/feature-chat-list`）；ChatListPage LazyForEach 列表（头像彩色圆+首字母、标题、预览截断、时间戳、未读角标）+ MVI contract（ChatListUiState/ChatListIntent/ChatListEffect/chatListReducer）+ MockChatData 50 条确定性 mock；`assembleHar` BUILD SUCCESSFUL；commit `eec44b1` |
| PLAT-003 HUKS 安全密钥存储 | 2026-09-09 ✅ | 子agent-28：`platform/keystore` har 模块（`@tgx/platform-keystore`）；HarmonySecureKeyStore 实现 SecureKeyStorePort（Asset Store Kit：put/get/remove/getStatus，DEVICE_UNLOCKED 可达性、OVERWRITE 冲突、NEVER 同步、稳定错误码映射）；`assembleHar` BUILD SUCCESSFUL；commit `eec44b1` |
| BRG-005 TDLib close/shutdown 生命周期 | 2026-09-09 ✅ | 子agent-29：TdCoreBridge 状态机（idle→active→closing→closed），close() 幂等、迟到回调丢弃计数、createClient 快速重建；TdGateway close()（stop + registry.close()，新请求拒绝 GATEWAY_CLOSED_ORIGIN）；RequestRegistry.close() 批量取消 pending；AccountScope.close() 级联 gateway.close()；3 模块 `assembleHar` + `assembleHap` 全 BUILD SUCCESSFUL，既有测试不回归；commit `eec44b1` |
| SPIKE-001 真机授权登录垂直切片 | 2026-09-09 ✅ | 真机端到端验证 PASS：`EntryAbility.onCreate → bootstrap() → AccountScope.open(startActive=true) → gateway.start() → TDLib setTdlibParameters 成功 → authorizationStateWaitPhoneNumber → AuthCoordinator → AuthRootPage "Your Phone" 渲染`。修复两个问题：① TDLib 初始事件在 eventListener 注册前被丢弃 → `executeCoreEffectsForState` 补发 core effects；② `setTdlibParameters` 被调两次（补发 + 事件到达）→ `tdlibParamsSent`/`dbKeySent` 防重标志。新模块：`platform/files`（`HarmonyAppFilesAdapter` 实现 AppFilesPort，@kit.CoreFileKit 原子写入/路径安全）；`entry/ScopeAuthAdapter.ets`（适配 AccountScope → AuthAccountScopeLike）。日志：`setTdlibParameters succeeded` + 页面渲染 "Your Phone"（China +86，输入框，Continue 按钮）；commit `ab62b8c` |
| AUTH-001 授权页面壳与 Reducer 对接 | 2026-09-09 ✅ | AI-Agent-Antigravity：`feature/auth` 注册为 har 模块（modules 追加 `feature_auth`，包名 `@tgx/feature-auth`）；基于 UI-003 MVI 范式（UiState/Intent/Effect/Reducer）+ CORE-005 授权状态机；AuthUiState（11 步骤、电话格式化、验证码位数自适应、2FA 密码显隐、姓名注册、loading/error 状态，copyWith 不可变派生）+ 17 种 AuthIntent + 9 种 AuthEffect + 纯函数 authReducer + AuthCoordinator（异步 effect 驱动、TDLib updateAuthorizationState 解析与状态同步、倒计时调度）+ 5 个 ArkUI 组件（AuthRootView / AuthPhoneView / AuthCodeView / AuthPasswordView / AuthRegistrationView）；纯单测 36 用例全 Success（CountryCode 3 + AuthReducer 28 + AuthCoordinator 5）：`./hvigorw test --mode module -p module=feature_auth@default -p product=default --no-daemon`；`assembleHar` BUILD SUCCESSFUL |
| GEN-003 codec fixture round-trip | 2026-09-09 ✅ | AI-Agent-J：22 个全合成脱敏 fixture（TDLib 官方仓库无静态 JSON 样本，字段结构派生自 td_api.tl；13 个授权状态机 + 4 个 updateNewMessage 内容类型 + error/ok `@extra` 关联 + vector&lt;int64&gt; 大数 + 2 个未知类型 raw 回传；来源/脱敏规则/加 fixture 流程见 `core/td_api_generated/fixtures/README.md`）；每 fixture 独立用例 `decodeTdObject→encodeTdObject→canonicalJson 语义等价→二次 decode 稳定`，未知类型断言 `TdUnknownObject` 无损；`FixtureData.ets` 由 `fixtures/sync_fixtures.py` 从 json 确定性生成；`./hvigorw test --mode module -p module=core_td_api_generated@default -p product=default --no-daemon` `Tests run: 48, Failure: 0, Error: 0, Pass: 48`（既有 20 例不回归）；期间定位并清除损坏的 533MB `init_coverage.json` 构建缓存（00308018 假错误，`.test/` 产物非源码） |
| GOV-001 空工程 | 2026-09-08 | Debug/Release 构建均 BUILD SUCCESSFUL，产出 `entry/build/default/outputs/default/entry-default-unsigned.hap`（212 KB）；commit `7fe266b` |
| GOV-002 工具链锁定 | 2026-09-08 | `tools/toolchain-versions.json` + `tools/ci/setup-check.sh` 退出码 0（SDK 26.0.0.105 / hvigor 6.26.4）；版本不匹配会明确失败 |
| GOV-003 文档控制面 | 2026-09-08 | `docs/`（ARCHITECTURE、ADR-001/002、Feature/Parity、quality 五件、runbooks 三件）+ `work-items/templates/`（§17.1/17.2 原文模板） |
| GOV-007 秘密管理 | 2026-09-08 | `.gitignore` 覆盖签名/p12/cer/local_properties/api_hash；`tools/ci/secret-scan.sh` 已接入 ci.sh（PEM 私钥、api_hash 模式阳性 fixture 验证通过）；commit `7fe266b`+`b94e5a6` |
| GOV-004 Feature/Parity Matrix | 2026-09-08 | FEATURE_MATRIX：7 项 P0 + 38 项 P1（含真实 Android 类级路径+行号、TDLib 方法）、P2/P3 一行表；PARITY_MATRIX 45 行对齐骨架；commit `b94e5a6` |
| GOV-005 Android 行为样本 | 2026-09-08 | `docs/product/behavior-samples/` 5 份（登录/会话列表/发文本/通知/媒体）+ README，全部脱敏、含 TDLib 事件与 Harmony 验收观察点；截图/录屏待真机；commit `b94e5a6` |
| GOV-006 CI 最小流水线 | 2026-09-08 | `tools/ci/ci.sh` 6 步全链路实测通过（工具链闸→secret scan→lint/typecheck→单测→debug→release 构建）；`.github/workflows/ci.yml` self-hosted 模板；commit `b94e5a6` |
| QA-001 测试骨架 | 2026-09-08 | `hvigorw test` 真实执行通过：1 用例 Success（注意：本 hvigor 6.26.4 单测须放 `entry/src/test/*.test.ets`，ohosTest 壳留作设备测试）；commit `b94e5a6` |
| SEC-001 威胁模型 v0 | 2026-09-08 | `docs/architecture/threat-model-v0.md`：数据流图+6 信任边界、9 资产、16 威胁（账号/消息/文件/Push/bridge/存储全覆盖）、7 秘密管理规则、§18 风险映射；commit `b94e5a6` |
| TDN-001 依赖构建矩阵 | 2026-09-08 | `native/tdcore/README.md`：OpenSSL 3.5.8（必须，TD CMake 硬依赖）/ zlib 1.3.1（NDK sysroot）/ SQLite 3.31.0（TD 自带 amalgamation）/ TDLib d1085f9ce，各带版本、来源、hash、许可证；commit `0dd04ef` |
| TDN-002 最小依赖构建 | 2026-09-08 ✅ | OHOS NDK 交叉编译产出 `libtdjson.so`（arm64，strip 后 45.9MB，build-id 7b9c054b）+ `libcrypto.so.3`；musl 补丁 0001；**真机应用内 smoke PASS**：TDLib 1.8.67，execute(getTextEntities) 正常返回（hdc shell 域禁 exec ELF 的绕过方案见 runbook） |
| BRG-001/002 Node-API 桥 | 2026-09-08 ✅ | `libtdcore_napi.so` 导出 getVersion/execute/createClient/send（契约对照 §5.2，错误安全）；真机验证：页面显示 `TDLib 版本: 1.8.67` + textEntities JSON；证据 `native/tdcore/napibridge/EVIDENCE.md` + 设备截图；commit `c93ebd5` |
| BRG-003/004 receive+队列 | 2026-09-09 ✅ | receive 线程 → 有界队列 → TSFN → ArkTS 全管线；真机端到端 PASS：getOption 异步响应按序到达（seq #1-#4 单调），dropped=0，force-stop 重启无崩溃；证据 `napibridge/EVIDENCE.md` + 两张设备截图；commit `62b71a2` |
| 结构骨架 | 2026-09-08 | core×9 / platform×14 / feature×12 / native×3 / tools×4 / test×4 目录已建（仅 .gitkeep，未注册构建，符合 ADR-002） |
| GEN-001 schema IR | 2026-09-08 ✅ | AI-Agent-C：`tools/td_api_codegen/td_api_ir.py`（纯 python3 无依赖）解析 td_api.tl（16313 行）→ `core/td_api_generated/schema.ir.json` + golden 快照 `tools/td_api_codegen/snapshot/td_api.ir.json`；schemaHash `7fbae70a…c5929`（SHA-256，仅随 schema 内容变）；stats types=743 / constructors=3214（objects=2192+functions=1022）/ fields=6997；入口 `python3 tools/td_api_codegen/td_api_ir.py verify`（CI 用，不写文件）——重复运行字节级一致，故意改输入（加字段）verify/generate 均退出码 1、恢复后通过；README 含 GEN-002 交接说明 |
| GEN-002 ArkTS DTO/union 全量生成 | 2026-09-09 ✅ | AI-Agent-F：`tools/td_api_codegen/td_api_arkts.py` 从 schema.ir.json 生成全量 ArkTS（classes=3205、unions=743、49 个 .ets）：每构造器一个类（判别属性 `type`、`@extra` 载体、int64→string）+ 每抽象类型判别联合（恒含 `TdUnknownObject`）+ decode/encode + `TdResponseMap` 请求返回映射 + `decodeTdObject`/`encodeTdObject`；decode 永不抛错（未知 `@type`→`TdUnknownObject` 保 raw 可回传、未知字段忽略、缺字段取默认）；命名规则/避让（`type_`/`extra_`、`DateValue`/`ErrorValue`/`ProxyValue`、`TdJsonRaw`）与 panda index 上限分块约束（`TdUnions_<A-Z>` + `TdEntries`）见 README；`generate`/`verify` 双入口、重复生成字节级一致（shasum 两次相同）；har 模块 `core_td_api_generated`（`@tgx/td-api-generated`）`assembleHar` BUILD SUCCESSFUL；单测 20 用例全 Success（codec round-trip/未知 `@type` 与未知字段 fallback/int64 精度/`@extra`/响应映射）`./hvigorw test --mode module -p module=core_td_api_generated@default -p product=default --no-daemon`；首版生成物曾被 BRG-003/004 的 commit `032cdfa` 顺带提交（CI 需要），本轮为重构后最终版 |
| CORE-001 Result/AppError/Clock/Id | 2026-09-08 ✅ | AI-Agent-E：`core/common` 注册为 har 模块（build-profile.json5 modules 追加 `core_common`，未动 entry/signing）；Result 判别联合（map/flatMap/mapError/getOrElse/getOrNull/fold）+ AppError 七类稳定错误（含 fromTdlibError 稳定映射、toLogString 脱敏）+ Clock（System/Manual）+ IdGenerator（Random 可注入/Sequential fake）；纯单测 27 用例全 Success：`./hvigorw test --mode module -p module=core_common@default -p product=default --no-daemon`（全工程 `hvigorw test --no-daemon` 亦 BUILD SUCCESSFUL，entry 1 用例回归通过）；`assembleHar` BUILD SUCCESSFUL；交接说明见 `core/common/README.md`（单调时钟需 platform 注入） |
| UI-001 Design token/theme | 2026-09-08 ✅ | AI-Agent-G：`core/design_system` 注册为 har 模块（build-profile.json5 modules **仅追加** `core_design_system`）；19 个语义色 token 深浅两套（LightColors/DarkColors）+ 9 档字阶排版 + 间距/圆角/动画 token（曲线存贝塞尔控制点保持 Kit-free）；`Theme`/`createTheme(mode, fontScale)` + `resolveToken(theme, dottedName)` 五命名空间解析入口（未知名返回 undefined）；fontScale 适配 clamp [0.85,2.0] + 最小可读字号 11vp 下限；纯单测 25 用例全 Success（深浅色映射完整且互异、WCAG 对比度断言、fontScale 五边界、token 存在性/有序性）；`assembleHar` BUILD SUCCESSFUL；命名规范/加 token 流程/ArkUI 接入说明见 `core/design_system/README.md` |
| PLAT-001 Platform Port 契约 | 2026-09-08 ✅ | AI-Agent-H：`platform/ports` 注册为 har 模块（modules **仅追加** `platform_ports`，包名 `@tgx/platform-ports`，依赖 `@tgx/core-common` file: 引用）；5 个端口契约（PreferencesPort flush 派发/同 key 合并/通配事件、SecureKeyStorePort 锁屏/不可用语义 + 稳定平台错误码、NetworkStatePort 快照去重/初始值语义、AppFilesPort 路径越界拒绝/配额、MonotonicClockPort 单调不减）+ 5 个 Fake + `src/test/contract/` 同套参数化契约测试（生产 adapter 复用同一函数）；同套契约 36 用例全 Success（`Tests run: 36, Failure: 0, Error: 0, Pass: 36`），`assembleHar` BUILD SUCCESSFUL；语义约定/交接见 `platform/ports/README.md`；本地 har 依赖用 `oh_modules/@tgx/core-common → ../../../../core/common` 符号链接（gitignored） |
| UI-002 Typed navigation | 2026-09-08 ✅ | AI-Agent-I：`core/navigation` 注册为 har 模块（modules **仅追加** `core_navigation`，包名 `@tgx/core-navigation`，依赖 `@tgx/core-common`）；`AppRoute` discriminated union（8 路由）+ `ParamSpec` 参数 schema（int 限 safe-integer 范围/string maxLength+pattern/boolean）+ RouteRegistry（name↔path 模板互转、重复注册与非法模板拒绝）+ RouteCodec（parse/encode round-trip、缺失必填/类型错误/越界/未知路由/未知与重复参数/非法百分号编码全部 Err 不抛异常；parseDeepLink 白名单规则 scheme/host/query 映射，未知 URI 安全拒绝，junk query 忽略）+ NavigationStack（push/replace/pop/popToRoot、serialize/restore round-trip、连续重复去重、任一非法项整体拒绝）；纯单测 37 用例全 Success（`Tests run: 37, Failure: 0, Error: 0, Pass: 37`）：`./hvigorw test --mode module -p module=core_navigation@default -p product=default --no-daemon`；命名规范/加路由四步骤/ArkUI Navigation 接入预留见 `core/navigation/README.md`；**新工程要点**：跨 har 模块判 Result 分支禁用 `instanceof Ok/Err`（类身份跨模块可能不一致，实测误判），用 `result.ok === false` 收窄或 `fold` |
| UI-003 UiState/Intent/Effect 基类约定 | 2026-09-09 ✅ | AI-Agent-M：`feature/_template` 注册为 har 模块（modules **仅追加** `feature_template`，包名 `@tgx/feature-template`，依赖 `@tgx/core-common`）；UiState/Intent/Effect 空接口标记 + `Reducer<S,I,E>` 契约（`(state, intent, env) -> {state, effects}`，env 注入 Clock/IdGenerator，reducer 纯函数可测）+ 计数器示例 feature（`copyWith` 不可变更新——ArkTS 不支持对象 spread、`kind` 字面量判别、幂等防重返回原引用、参数校验走 Effect）；纯单测 15 用例全 Success（每 intent 分支、effect 数量/类型/参数精确断言、输入不可变、chained runs 独立）：`./hvigorw test --mode module -p module=feature_template@default -p product=default --no-daemon`；`assembleHar` BUILD SUCCESSFUL；四步创建法/reducer 五条禁忌见 `feature/_template/README.md`；commit `a892ce2` |
| PLAT-004 网络状态生产 adapter | 2026-09-09 ✅ | AI-Agent-L：`platform/network` 注册为 har 模块（modules **仅追加** `platform_network`，包名 `@tgx/platform-network`，依赖 `@tgx/core-common` + `@tgx/platform-ports` file: 引用，oh_modules 符号链接同 ports）；ConnectivityAdapter = Kit-free 引擎（`ConnectivitySource` 注入面）+ ConnectivityKitSource（唯一 import `@ohos.net.connection`：`createNetConnection` 监听 netAvailable/netLost/netCapabilitiesChange，current 用 getDefaultNetSync+getNetCapabilitiesSync）；映射表 bearer→wifi/cellular/ethernet/other（多 bearer 优先级 ethernet>wifi>cellular>other）+ metered（networkCap 无 NET_CAPABILITY_NOT_METERED=11）+ SnapshotDeduper 连续同值去重；注册即派初始快照（经去重器防 flicker）、注销幂等（本 SDK NetConnection 无 off，unregister 移除全部监听→单订阅设计，active 闭包丢迟到事件）、注册失败 err(platform 2100002)；纯单测 18 用例全 Success（映射 7 + 去重 4 + 契约镜像 7，含注册失败透传）：`./hvigorw test --mode module -p module=platform_network@default -p product=default --no-daemon`；`assembleHar` BUILD SUCCESSFUL；ohosTest 设备骨架就位未上真机；权限 GET_NETWORK_INFO 已声明；验证矩阵/已知限制见 `platform/network/README.md` |
| CORE-002 TdGateway+RequestRegistry | 2026-09-09 ✅ | `core/td_gateway`（`@tgx/td-gateway`）：RequestRegistry（@extra.requestId 注入、Promise 恒回 Result 不 reject、超时 10s 可配、取消、迟到丢弃计数、7 项指标）+ OrderedEventRouter（clientId+sequence 单调校验、乱序上报不静默、重复幂等）；FakeBridge 单测 53/53；CI 全绿；commit `4f1194e` |
| CORE-005 授权状态机 reducer | 2026-09-09 ✅ | authReducer（event-driven，10 状态/12 事件/effect union）+ AuthorizationStateMachine 不可变包装 + failed/closed 终态守卫；98 用例全 Success（60 原有 + 38 新增）；CI 全绿；commit `9d5e7a1` |
| CORE-003 AccountScope/Registry | 2026-09-09 ✅ | `core/account`（`@tgx/core-account`）：生命周期纯 reducer（active/hibernating/closed 终态幂等）、每账号独占 TdGateway + ScopeIsolatingBridge 事件边界隔离、restoreAll 逐账号失败隔离、迟到事件守卫丢弃；AuthorizationState 占位待 CORE-005；60/60 用例；CI 全绿；commit `832f11f` |
| GEN-004 敏感字段元数据+脱敏 | 2026-09-09 ✅ | 生成器 `td_api_sensitive.py`（generate/verify 双模式，字节级可复现）：124 构造器/154 字段/44 类型级清单（redact 75/mask 79，三层首匹配规则表带决策注释）；产物 `td_api_generated/.../redaction/`（TdSensitiveFields 3861 行 + TdRedact）；`core/observability`（`@tgx/observability`）白名单 Logger + 双防线脱敏，43/43 用例（secret fixture 100% 拦截）；commit `4f1194e` |
| BRG-006 生产桥 adapter | 2026-09-09 ✅ | `platform/tdcore-bridge`（`@tgx/platform-tdcore-bridge`）：TdCoreBridge 实现 TdNativeBridgeLike（getVersion/execute/createClient/send/subscribeUpdates/unsubscribe/getMetrics，可注入 native module）；entry Bootstrap.ets 装配骨架（TdCoreBridge→AccountRegistry→scope，FakeAppFiles 占位，EntryAbility 未接）；11/11 用例；CI 全绿 |
| PLAT-002 Preferences/RDB adapter | 2026-09-09 ✅（设备项待验） | AI-Agent-K：`platform/storage` 注册为 har 模块（modules **仅追加** `platform_storage`，包名 `@tgx/platform-storage`，依赖 `@tgx/core-common` + `@tgx/platform-ports` file: 引用，oh_modules 符号链接同 ports）；**两个 PreferencesPort 生产 adapter**：`HarmonyPreferencesAdapter`（@ohos.data.preferences，open/openSync）+ `RdbPreferencesAdapter`（@ohos.data.relationalStore，open/幂等 close），共享纯 ArkTS `PreferenceStoreCore`（内存视图/同 key 合并/flush 后派发/clear 通配/失败挂起重试，语义对齐 PLAT-001 契约）；**schema+migration**：`tgx_meta(user_version)` + `tgx_kv(key,type_tag,value_text,value_real,value_integer)` 类型分列，线性版本链 `planMigrations`（up/down 双路径、缺 down 步骤拒绝回滚、版本跳跃遍历）+ `runMigrations`（每步完成先推版本标记→中断可断点续跑，Kit 层 beginTransaction/commit/rollBack 整体回滚）；fake 注入中断/升级/回滚单测 **47 用例全 Success**（`Tests run: 47, Failure: 0, Error: 0, Pass: 47`）：`./hvigorw test --mode module -p module=platform_storage@default -p product=default --no-daemon`；`assembleHar` BUILD SUCCESSFUL（Kit adapter 严格编译通过）；`src/ohosTest` 设备测试（真实落盘+重开读回/事件派发）就位**待真机**；**新工程要点**：ArkTS 收窄仅块内 `if (r.ok/r.err)` 有效（取反/early-return/else 分支均不收窄，用 getOrNull/getOrElse 或 fold 规避）；内联对象字面量类型被禁（用 interface union）；PLAT-001 contract 函数在 ports 的 src/test、跨模块相对 import 被编译器拒绝→全量 contract 复用待 test_support 包；验证矩阵/交接见 `platform/storage/README.md` |
| RECAPTCHA-001 reCAPTCHA verification flow | 2026-09-09 ✅ | subagent：`feature/auth` 模块内 9 文件修改 + 1 新建；`AuthEventParser` 新增 `parseRecaptchaUpdateFromWire`（解析 `updateApplicationRecaptchaVerificationRequired` wire JSON → `{verificationId, action, recaptchaKeyId}`，orthogonal 于 `AuthEvent` union 不影响 core/account 穷尽匹配）；`AuthStep` 加 `'waitRecaptcha'`；`AuthUiState` 加 `verificationId/recaptchaKeyId/recaptchaAction` 三字段（constructor/initial/copyWith 全更新）；`AuthIntent` 加 `OnRecaptchaRequired`+`SubmitRecaptchaToken`；`AuthEffect` 加 `SendVerificationToken`；`AuthReducer` 加 `onRecaptchaRequired`（step→waitRecaptcha, isSubmitting=false, 清错误）+ `submitRecaptchaToken`（isSubmitting=true, 产出 SendVerificationToken effect）；`AuthCoordinator.handleIncomingEvent` 在 `parseAuthEventFromWire` 前拦截 recaptcha update → dispatch OnRecaptchaRequired；`executeEffect` 加 `sendVerificationToken` case（Record<string,Object> 构参 → `setApplicationVerificationToken`）；`AuthRootPage` 加 `waitRecaptcha` 分支渲染 `RecaptchaPage`；新建 `RecaptchaPage.ets`（HarmonyOS `Web` 组件 + `registerJavaScriptProxy` JS bridge → `recaptchaBridge.onToken(token)` → 回调 `onToken` prop → dispatch `SubmitRecaptchaToken`）；`assembleHap` BUILD SUCCESSFUL |

已知工程要点（runbook 已记录）：hvigorw 为 shell/JS polyglot；离线构建依赖 `~/.hvigor/project_caches`；`DEVECO_SDK_HOME` 必须指向 `…/Contents/sdk`（wrapper 已内置）；签名/真机待用户提供。

已知工程要点（CORE-001 实测）：① 后续 har 模块照 `core/common/` 模板注册：`hvigorfile.ts` 用 `harTasks`；模块自己的 `build-profile.json5`（`{"apiType":"stageMode","buildOption":{}}`）；`src/main/module.json5` 的 `type` 必须是 `"har"`（写 `"shared"` 会被当 HSP 导致 `PackageSignHar` 缺失）；oh-package.json5 的 `main` 指向 `./src/main/ets/Index.ets`。② har 模块单测入口固定为 `src/test/List.test.ets`（hvigor 生成 harness 硬编码 import 它，由它汇总其他 `*.test.ets`）。③ 模块本地单测需在 `<module>/oh_modules/@ohos/hypium` 建符号链接到根 `oh_modules/.ohpm/@ohos+hypium@1.0.21/...`（gitignored；照抄 entry 的做法）。

## 阻塞 / 风险记录

| 日期 | 事项 | 状态 |
|---|---|---|
| 2026-09-08 | 用户输入项（api_id/api_hash、真机、AGC/Push 配置）未提供 —— 阻塞 Phase 1 真机项，不阻塞 Phase 0 工程脚手架 | ✅ 已解决：api_id/api_hash 已放入 gitignored `local.properties`（取自 Android 工程）；VYG-AL00 真机已连（API 24 / 6.1.0.135），DevEco 自动签名已接入 |
| 2026-09-08 | compatibleSdkVersion 26 与设备 API 24 不匹配 | ✅ 已修复为 `6.1.1(24)`（hvigor 映射表 6.1.1→24）；signed hap 已真机安装成功（bundle 校验通过），启动待解锁屏幕 |

| RECAPTCHA-002 Web reCAPTCHA baseUrl 修复 | 2026-09-10 ✅ | RecaptchaPage 恢复 Web 组件（loadData 带 baseUrl=https://web.telegram.org/ 解决 "Invalid domain for site key"）+ QR 码兜底按钮并存；AuthRootPage 传 recaptchaKeyId/onToken；waitRecaptcha 步骤忽略请求超时错误（verifier 持有原查询）；commit `830dc8c` |
| TDN-003 OHOS reCAPTCHA 拦截补丁 | 2026-09-10 ✅ | NetQueryDispatcher.cpp L112/L378 加 `|| defined(__OHOS__)` 启用 NetQueryVerifier（403 RECAPTCHA_CHECK 拦截 + verifier actor 创建）；patch 文件 `native/tdcore/patches/0002-ohos-recaptcha-verification.patch`；libtdjson.so 重编译完成（stripped 47.9MB） |

### 当前状态（2026-09-10）
- 手机已通过 QR 登录（AUTH-QR-001 by Codex），auth 全链路打通
- 会话列表已接入真实 TDLib 数据（CHATLIST-003）：登录/冷启动恢复后 Index.ets 渲染 `ChatListPage`，经 `ChatListCoordinator` ← `ChatListProjection`（ChatListMain）订阅 updateNewChat/updateChatPosition/updateChatLastMessage/updateChatReadInbox，`loadChats` 分页；下拉刷新走 RefreshChats
- 会话消息页已落地并真机验证通过（CHAT-001 + CHAT-002 基础）：点击会话行 → `onNavigateToChat` 回调 → Index.ets 创建 `ChatCoordinator`（`MessageProjection`：openChat + getChatHistory 分页 + 四类消息更新订阅）→ 渲染 `ChatPage` 文本气泡（右出左入、HH:mm、滚顶翻页、到底跟随新消息）；返回箭头销毁并切回列表
- **2026-09-10 修复聊天历史加载链**（commit `21c634b`）：真机发现所有会话只渲染 1 条消息。根因两条：① getChatHistory 初始请求 offset=-limit+1，from_message_id=0 时 TDLib 语义为"末条+之后 -offset-1 条更新的消息"，末条之后没有更新消息 → 只回 1 条（已改 offset=0）；② TDLib `get_dialog_history` 内存优先——内存里只有 last_message 时立即返回它并后台异步 preload 更旧历史，preload 无声完成（无 update 推送），客户端须再次请求才拿得到；配合修复：到顶判定改为连续 3 页无新增（容忍 preload 空窗），ChatCoordinator 在消息不足一屏（<20）时延迟 900ms 自动补拉。真机验证：EI CLUB 群连续补拉多页 20 条、单屏 11+ 气泡；be hu 私聊 5 条全量；消息真少的会话 3 次空跑后正确停止
- **E2E-001 G3 验收通过（2026-09-10，有保留）**：断网恢复（发消息 pending → 恢复网络自动重发成功）与杀进程重启（force-stop 冷启动直接回会话列表）真机实测通过；保留项见「已完成」表 E2E-001 行
- **下一步**：按计划 §9.6 进入 Phase 4/5 Epic 拆分——Epic 不得整体分配给单个 AI，先拆成 0.5–3 天工作包登记进「待认领」再逐包实施；可顺手的已知改进（非计划内、低优先）：senderName 接 user registry、日期分隔条、非文本消息占位标签实体渲染、翻页前插滚动跳动
