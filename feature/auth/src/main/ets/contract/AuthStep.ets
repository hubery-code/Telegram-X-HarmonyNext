/**
 * feature/auth — 登录流程步骤（AUTH-001）。
 *
 * 与 core/account 的 AuthState.kind 保持语义映射，但服务于 UI 渲染分发。
 */

export type AuthStep =
  | 'waitParams'
  | 'waitDbKey'
  | 'waitPhone'
  | 'waitCode'
  | 'wait2fa'
  | 'waitRegistration'
  | 'waitRecaptcha'
  | 'waitQrCode'
  | 'ready'
  | 'loggingOut'
  | 'closing'
  | 'closed'
  | 'failed';
