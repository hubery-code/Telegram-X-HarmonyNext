# 行为样本：登录授权流程（手机号 → 验证码 → 2FA / 二维码）

> 截图/录屏：待真机采集。本文档基于 Android 参考实现代码分析（类路径与行号已核实），真机素材回填到本文件「证据」小节。
> 关联：计划 §3.1 P0「真机完成授权」、§3.2 P1「手机号/验证码/2FA/二维码授权状态机」；FEATURE_MATRIX `P0-FEAS-002`。

## 1. 场景总览

Telegram X 的登录是一条由 TDLib `AuthorizationState` 驱动的状态机，UI 层（`MainActivity` + 各 Controller）只负责把状态映射为页面，并发起对应 request。全部状态分支见 `MainActivity.java:356`（`processAuthorizationStateChange`）与 `MainActivity.java:562`（按状态生成 Controller 的 switch）。

状态机（TDLib 侧，按出现顺序）：

```
WaitTdlibParameters → WaitPhoneNumber → (WaitCode | WaitEmailAddress/WaitEmailCode)
  → WaitRegistration（可选）→ WaitPassword（可选，2FA）→ Ready
旁路：LoggingOut / Closing / Closed；WaitPremiumPurchase；WaitOtherDeviceConfirmation
```

## 2. 场景步骤序列

### 2.1 冷启动（未登录，单账号）

| # | 用户动作 | 系统事件 | UI 状态 |
|---|---|---|---|
| 1 | 启动 App | TDLib client 创建，发 `SetTdlibParameters`（数据库目录、api_id/api_hash 由 app 注入） | 首次安装且未尝试过时进 Intro 页；否则直接进手机号页（`MainActivity.java:630-642`，`initUnauthorizedController`：首次 `IntroController`，`IntroController.isIntroAttemptedButFailed()` 失败后直接 `PhoneController`） |
| 2 | （首次）滑动/跳过介绍 | — | Intro 页（`ui/IntroController.java`）滑出，`PhoneController` 入栈 |
| 3 | 选择国家码、输入手机号占位符 `+86 1xx-xxxx-xxxx`，勾选服务条款 | `SetAuthenticationPhoneNumber(phone, settings)`（`ui/PhoneController.java:1141`） | 手机号页：国家码选择器、条款勾选框、继续按钮；提交后按钮转 loading，输入锁定 |
| 4 | TDLib 接受手机号 | `AuthorizationStateWaitCode`（codeInfo 含验证码类型/长度/发送渠道） | `MainActivity.java:564-567` 生成 `PasswordController`（`MODE_CODE`）入栈：验证码输入框、倒计时、「重新发送」 |
| 5 | 输入验证码 | `CheckAuthenticationCode(code)`（`ui/PasswordController.java:1686`） | 输入足够位数自动提交；错误时输入框抖动/红框并显示错误文案，停留在原页 |
| 6 | 验证码过期重发 | `ResendAuthenticationCode(reason)`（`ui/PasswordController.java:1167`） | 倒计时归零后重发按钮可点；部分渠道需先确认手机号（`MODE_CODE_PHONE_CONFIRM`） |
| 7 | （若账号已设 2FA）进入密码页 | `AuthorizationStateWaitPassword`（含 passwordHint、recoveryPending） | `PasswordController`（`MODE_LOGIN`，`MainActivity.java:588-591`）：密码输入框、提示 hint、「忘记密码」入口 |
| 8 | 输入 2FA 密码 | `CheckAuthenticationPassword(password)`（`ui/PasswordController.java:1810`） | 提交后 loading；错误显示剩余重试次数，连续错误可被限流 |
| 9 | （若新注册）进入注册页 | `AuthorizationStateWaitRegistration`（termsOfService） | `EditNameController`（`MainActivity` 的状态 switch，`MainActivity.java:582-585`，`EditNameController.Mode.SIGNUP`）：名/姓两个输入框 |
| 10 | 提交姓名 | `RegisterUser(firstName, lastName)` | 提交后等待最终状态 |
| 11 | 授权完成 | `AuthorizationStateReady` | 授权页栈被 `ChatsController` 替换（`MainActivity.java:612` 分支 + `processAuthorizationStateChange` 的栈重建），进入会话列表 |

### 2.2 二维码登录（被扫码方为本机时）

| # | 用户动作 | 系统事件 | UI 状态 |
|---|---|---|---|
| 1 | 其他客户端扫码发起登录 | TDLib 进入 `AuthorizationStateWaitOtherDeviceConfirmation`（含二维码内容 `tg://login?token=…` 与有效期） | **TGX 不展示此状态**：`MainActivity.java:604-606` 注释 "Should never come to TGX"，仅作防御分支 |
| 2 | （本机作为扫码方）打开「已登录设备 → 链接桌面设备」扫描 QR | 解析出 `tg://login` 深链 → `TdlibUi.java:4145`（`InternalLinkTypeQrCodeAuthentication`）→ `Tdlib.confirmQrCodeAuthentication`（`telegram/Tdlib.java:5598`）发 `ConfirmQrCodeAuthentication(link)` | 扫码后确认弹窗，确认后对方设备完成登录；`ui/SettingsSessionsController.java:662-663` 是参考入口 |

### 2.3 多账号添加

| # | 用户动作 | 系统事件 | UI 状态 |
|---|---|---|---|
| 1 | 已登录态发起「添加账号」 | 新 `TdlibAccount` 创建（`telegram/TdlibManager.java` / `telegram/TdlibAccount.java`），走同一状态机 | `PhoneController` 以 `isAccountAdd()` 模式打开（`MainActivity.java:415-418`），标题与返回行为区分于首账号登录；登录成功后回账号切换视图 |

### 2.4 登出

| # | 用户动作 | 系统事件 | UI 状态 |
|---|---|---|---|
| 1 | 设置 → 登出 | `LogOut` → `AuthorizationStateLoggingOut` → `Closing` → `Closed` | 登出期间 UI 不做页面切换（`MainActivity.java:609-614` 为空分支），完成后 TDLib 实例销毁，回到手机号页 |

## 3. 关键 UI 状态汇总

- **手机号页**：国家码选择器（按地区过滤）、手机号格式化输入、条款勾选、模拟器检测警告弹窗（`ui/PhoneController.java:1330-1398`，`EmulatorWarningTitle`）。
- **验证码页**：验证码输入（按 codeInfo 长度自动提交）、发送渠道说明、倒计时重发、更换手机号入口（返回上一页）。
- **2FA 密码页**：hint 展示、忘记密码 → 恢复邮箱流程（`MODE_EMAIL_RECOVERY` / `MODE_LOGIN_EMAIL_RECOVERY`）、密码可见性切换。
- **错误处理**：所有 request 失败均回调 TDLib `Error`，UI 在原地显示错误文案（手机号格式错误、验证码错误、密码错误、频繁调用限流），不跳页。
- **状态恢复**：杀进程后重启，`Tdlib` 从持久化的 `AuthorizationState` 恢复，UI 按当前状态直接生成对应页面，不重复提交（`MainActivity.java:518` `onAuthorizationStateChanged` 对每个账号独立触发）。

## 4. Android 类（真实路径，相对 `org/thunderdog/challegram/`）

| 类 | 作用 |
|---|---|
| `MainActivity.java` | 授权状态机 → 页面路由（`processAuthorizationStateChange` :356、Controller 生成 switch :562、未授权栈初始化 :630） |
| `ui/IntroController.java` | 首次启动介绍页 |
| `ui/PhoneController.java` | 手机号输入页（`SetAuthenticationPhoneNumber` :1141、模拟器警告 :1330） |
| `ui/PasswordController.java` | 验证码页（`MODE_CODE`）与 2FA 密码页（`MODE_LOGIN`），模式常量 :84-98 |
| `ui/EditNameController.java` | 新用户注册姓名页 |
| `ui/SettingsSessionsController.java` | 扫码链接桌面设备入口（`confirmQrCodeAuthentication` :662） |
| `telegram/Tdlib.java` | TDLib client 封装；`confirmQrCodeAuthentication` :5598、授权状态分发 :10721-10734 |
| `telegram/TdlibManager.java` / `telegram/TdlibAccount.java` | 多账号生命周期与账号对象 |
| `telegram/AuthorizationListener.java` | 授权状态监听接口 |

## 5. TDLib 事件对照

| request | 触发的状态 / update |
|---|---|
| `SetTdlibParameters` | → `AuthorizationStateWaitPhoneNumber`（或 `Ready` 若已登录） |
| `SetAuthenticationPhoneNumber` | → `AuthorizationStateWaitCode` / `WaitEmailAddress` / `WaitPassword` |
| `CheckAuthenticationCode` / `CheckAuthenticationEmailCode` | → `WaitRegistration` / `WaitPassword` / `Ready`；失败返回 `Error` |
| `ResendAuthenticationCode` | 重新下发验证码，重置倒计时 |
| `CheckAuthenticationPassword` | → `Ready` |
| `RegisterUser` | → `Ready` |
| `ConfirmQrCodeAuthentication` | 扫码方确认对方设备登录，返回 `Session` |
| `LogOut` | → `LoggingOut` → `Closing` → `Closed` |
| `GetAuthorizationState` | 杀进程恢复时 UI 层查询当前状态 |

## 6. Harmony 侧验收观察点

1. 状态机驱动：页面切换必须由 `AuthorizationState` update 触发，用户提交后不允许本地猜跳页面（错误只能在原地展示）。
2. 验证码自动提交位数按 `codeInfo` 动态适配；倒计时归零前重发按钮禁用。
3. 2FA hint、忘记密码/恢复邮箱入口齐全；密码错误显示剩余次数。
4. 杀进程重启后停在授权流程的正确步骤，不丢失已输入进度之外的异常跳转。
5. 二维码：本机作为扫码方完成 `ConfirmQrCodeAuthentication` 全流程（计划 P1 范围按 §3.2）；`WaitOtherDeviceConfirmation` 仅实现防御性占位。
6. 多账号添加走与首账号相同的控制器，标题/返回行为可区分。
7. api_id/api_hash 仅在注入 TDLib 时使用，不出现在日志与 UI（见 SEC-001 秘密管理规则）。

## 7. 证据（待回填）

- [ ] 手机号页截图、验证码页截图、2FA 密码页截图（真机，脱敏）
- [ ] 错误态截图（错误验证码、限流提示）
- [ ] 登录成功 → 会话列表切换录屏
