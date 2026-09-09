# feature/auth（AUTH-001）

Telegram X HarmonyOS NEXT 授权登录切片（MVI 架构）：
手机号输入、验证码接收与输入（自动提交/倒计时/重发）、2FA 密码校验与新用户注册。

纯 ArkTS 状态管理与 MVI Reducer，视图层采用声明式 ArkUI 组件（Stage 模型 HAR 模块）。

## 模块信息

- 模块名称：`feature_auth`
- 包名：`@tgx/feature-auth`
- 依赖：
  - `@tgx/core-common`：`Result<T, E>`、`AppError`、`Clock`、`IdGenerator`
  - `@tgx/core-design-system`：设计令牌与主题
  - `@tgx/core-navigation`：路由契约
  - `@tgx/core-account`：`AccountScope`、`AuthState`、`authReducer`
  - `@tgx/feature-template`：`UiState`、`Intent`、`Effect`、`Reducer` 契约
  - `@tgx/td-gateway`：`TdWireObject`、`TdRoutedEvent`

## 架构与单向数据流

```text
ArkUI Page (PhonePage / CodePage / PasswordPage / RegistrationPage)
    │
    ▼ (Dispatch Intent)
AuthCoordinator
    │
    ├─► AuthReducer (Pure Reducer: State + Intent -> New State + Effects)
    │
    └─► AccountScope (core/account)
            │
            ├─► scope.request(...) (TDLib API: setAuthenticationPhoneNumber, etc.)
            │
            └─► scope.subscribeEvents(...)
                     │
                     ▼ (updateAuthorizationState)
                 core/account.authReducer
                     │
                     ▼
                 AuthorizationStateHolder.replace()
                     │
                     ▼ (OnAuthStateChanged)
                 AuthReducer -> UI 重渲染 / 步骤切换
```

## 核心接口与状态定义

1. **`AuthStep`**：
   `waitParams` | `waitDbKey` | `waitPhone` | `waitCode` | `wait2fa` | `waitRegistration` | `ready` | `loggingOut` | `closing` | `closed` | `failed`

2. **`AuthUiState`**：
   包含步骤、国家码、电话号码、验证码（长度与倒计时）、2FA 密码（提示与显隐）、新用户姓名、loading 提交态与错误信息。支持纯不可变更新 `copyWith()`。

3. **`AuthIntent`**：
   - 手机号：`SelectCountry`, `ChangePhoneInput`, `SubmitPhone`
   - 验证码：`ChangeCodeInput`, `SubmitCode`, `RequestResendCode`, `CountdownTick`
   - 2FA 密码：`ChangePasswordInput`, `TogglePasswordVisibility`, `SubmitPassword`
   - 注册：`ChangeFirstName`, `ChangeLastName`, `SubmitRegistration`
   - 状态协同：`OnAuthStateChanged`, `OnRequestError`, `ClearError`, `BackToPhone`

4. **`AuthEffect`**：
   - `SendPhoneNumber`, `CheckCode`, `ResendCode`, `CheckPassword`, `RegisterUser`
   - `NavigateToRoute('chat_list')`
   - `ShowToast`
   - `StartCountdown`, `StopCountdown`

5. **`AuthCoordinator`**：
   负责调度状态与监听底层 `AccountScope` 事件流。

## 测试验证

```bash
./hvigorw test --mode module -p module=feature_auth@default -p product=default --no-daemon
```
