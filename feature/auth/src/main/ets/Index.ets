/**
 * feature/auth — 导出入口（AUTH-001）。
 */

export {
  CountryInfo,
  DEFAULT_COUNTRY,
  SUPPORTED_COUNTRIES,
  findCountryByDialCode,
  findCountryByIso,
  formatFullPhoneNumber
} from './model/CountryCode';

export { AuthStep } from './contract/AuthStep';
export { AuthUiStateOptions, AuthUiState } from './contract/AuthUiState';

export {
  SelectCountry,
  ChangePhoneInput,
  SubmitPhone,
  ChangeCodeInput,
  SubmitCode,
  RequestResendCode,
  ChangePasswordInput,
  TogglePasswordVisibility,
  SubmitPassword,
  ChangeFirstName,
  ChangeLastName,
  SubmitRegistration,
  OnAuthStateChanged,
  OnRequestError,
  CountdownTick,
  ClearError,
  BackToPhone,
  OnRecaptchaRequired,
  SubmitRecaptchaToken,
  RequestQrCodeLogin,
  OnQrCodeLinkReceived,
  AuthIntent
} from './contract/AuthIntent';

export {
  SendPhoneNumber,
  CheckCode,
  ResendCode,
  CheckPassword,
  RegisterUser,
  NavigateToRoute,
  ShowToast,
  StartCountdown,
  StopCountdown,
  SendVerificationToken,
  RequestQrCodeAuthentication,
  AuthEffect
} from './contract/AuthEffect';

export { authReducer } from './reducer/AuthReducer';

export {
  RecaptchaUpdateInfo,
  parseAuthEventFromWire,
  parseRecaptchaUpdateFromWire,
  parseQrCodeLinkFromWire
} from './coordinator/AuthEventParser';
export {
  AuthAccountScopeLike,
  AuthSubscriptionLike,
  AuthUiStateListener,
  AuthCoordinatorDeps,
  AuthCoordinator,
  TdlibParametersConfig
} from './coordinator/AuthCoordinator';

export { PhonePage } from './pages/PhonePage';
export { CodePage } from './pages/CodePage';
export { PasswordPage } from './pages/PasswordPage';
export { RegistrationPage } from './pages/RegistrationPage';
export { RecaptchaPage } from './pages/RecaptchaPage';
export { QrCodePage } from './pages/QrCodePage';
export { AuthRootPage } from './pages/AuthRootPage';
