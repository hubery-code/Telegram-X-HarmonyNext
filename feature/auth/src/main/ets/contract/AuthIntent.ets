/**
 * feature/auth — 登录意图（AUTH-001）。
 *
 * 包含用户操作与系统事件。每个类带字面量 kind 判别属性，供 reducer 穷尽收窄。
 */

import { Intent } from '@tgx/feature-template';
import { AuthState } from '@tgx/core-account';
import { AppError } from '@tgx/core-common';

export class SelectCountry implements Intent {
  readonly kind: 'selectCountry' = 'selectCountry';
  readonly countryCode: string;
  readonly countryName: string;

  constructor(countryCode: string, countryName: string) {
    this.countryCode = countryCode;
    this.countryName = countryName;
  }
}

export class ChangePhoneInput implements Intent {
  readonly kind: 'changePhoneInput' = 'changePhoneInput';
  readonly phone: string;

  constructor(phone: string) {
    this.phone = phone;
  }
}

export class SubmitPhone implements Intent {
  readonly kind: 'submitPhone' = 'submitPhone';
}

export class ChangeCodeInput implements Intent {
  readonly kind: 'changeCodeInput' = 'changeCodeInput';
  readonly code: string;

  constructor(code: string) {
    this.code = code;
  }
}

export class SubmitCode implements Intent {
  readonly kind: 'submitCode' = 'submitCode';
}

export class RequestResendCode implements Intent {
  readonly kind: 'requestResendCode' = 'requestResendCode';
}

export class ChangePasswordInput implements Intent {
  readonly kind: 'changePasswordInput' = 'changePasswordInput';
  readonly password: string;

  constructor(password: string) {
    this.password = password;
  }
}

export class TogglePasswordVisibility implements Intent {
  readonly kind: 'togglePasswordVisibility' = 'togglePasswordVisibility';
}

export class SubmitPassword implements Intent {
  readonly kind: 'submitPassword' = 'submitPassword';
}

export class ChangeFirstName implements Intent {
  readonly kind: 'changeFirstName' = 'changeFirstName';
  readonly firstName: string;

  constructor(firstName: string) {
    this.firstName = firstName;
  }
}

export class ChangeLastName implements Intent {
  readonly kind: 'changeLastName' = 'changeLastName';
  readonly lastName: string;

  constructor(lastName: string) {
    this.lastName = lastName;
  }
}

export class SubmitRegistration implements Intent {
  readonly kind: 'submitRegistration' = 'submitRegistration';
}

export class OnAuthStateChanged implements Intent {
  readonly kind: 'onAuthStateChanged' = 'onAuthStateChanged';
  readonly authState: AuthState;

  constructor(authState: AuthState) {
    this.authState = authState;
  }
}

export class OnRequestError implements Intent {
  readonly kind: 'onRequestError' = 'onRequestError';
  readonly error: AppError;

  constructor(error: AppError) {
    this.error = error;
  }
}

export class CountdownTick implements Intent {
  readonly kind: 'countdownTick' = 'countdownTick';
}

export class ClearError implements Intent {
  readonly kind: 'clearError' = 'clearError';
}

export class BackToPhone implements Intent {
  readonly kind: 'backToPhone' = 'backToPhone';
}

export class OnRecaptchaRequired implements Intent {
  readonly kind: 'onRecaptchaRequired' = 'onRecaptchaRequired';
  readonly verificationId: number;
  readonly action: string;
  readonly recaptchaKeyId: string;

  constructor(verificationId: number, action: string, recaptchaKeyId: string) {
    this.verificationId = verificationId;
    this.action = action;
    this.recaptchaKeyId = recaptchaKeyId;
  }
}

export class SubmitRecaptchaToken implements Intent {
  readonly kind: 'submitRecaptchaToken' = 'submitRecaptchaToken';
  readonly token: string;

  constructor(token: string) {
    this.token = token;
  }
}

export class RequestQrCodeLogin implements Intent {
  readonly kind: 'requestQrCodeLogin' = 'requestQrCodeLogin';
}

export class OnQrCodeLinkReceived implements Intent {
  readonly kind: 'onQrCodeLinkReceived' = 'onQrCodeLinkReceived';
  readonly link: string;

  constructor(link: string) {
    this.link = link;
  }
}

export type AuthIntent =
  | SelectCountry
  | ChangePhoneInput
  | SubmitPhone
  | ChangeCodeInput
  | SubmitCode
  | RequestResendCode
  | ChangePasswordInput
  | TogglePasswordVisibility
  | SubmitPassword
  | ChangeFirstName
  | ChangeLastName
  | SubmitRegistration
  | OnAuthStateChanged
  | OnRequestError
  | CountdownTick
  | ClearError
  | BackToPhone
  | OnRecaptchaRequired
  | SubmitRecaptchaToken
  | RequestQrCodeLogin
  | OnQrCodeLinkReceived;
