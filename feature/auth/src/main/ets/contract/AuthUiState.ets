/**
 * feature/auth — 登录界面可观察状态（AUTH-001）。
 *
 * 遵循计划 §5.11 / UI-003：所有字段只读，不可变更新经 copyWith() 派生。
 */

import { UiState } from '@tgx/feature-template';
import { AuthState } from '@tgx/core-account';
import { AuthStep } from './AuthStep';
import { DEFAULT_COUNTRY } from '../model/CountryCode';

export interface AuthUiStateOptions {
  readonly step?: AuthStep;
  readonly countryCode?: string;
  readonly countryName?: string;
  readonly rawPhone?: string;
  readonly formattedPhone?: string;
  readonly code?: string;
  readonly codeLength?: number;
  readonly resendTimeoutSeconds?: number;
  readonly canResendCode?: boolean;
  readonly password?: string;
  readonly passwordHint?: string;
  readonly isPasswordVisible?: boolean;
  readonly firstName?: string;
  readonly lastName?: string;
  readonly verificationId?: number;
  readonly recaptchaKeyId?: string;
  readonly recaptchaAction?: string;
  readonly isSubmitting?: boolean;
  readonly errorMessage?: string | null;
  readonly errorCode?: string | null;
  readonly rawAuthState?: AuthState | null;
}

export class AuthUiState implements UiState {
  readonly step: AuthStep;
  readonly countryCode: string;
  readonly countryName: string;
  readonly rawPhone: string;
  readonly formattedPhone: string;
  readonly code: string;
  readonly codeLength: number;
  readonly resendTimeoutSeconds: number;
  readonly canResendCode: boolean;
  readonly password: string;
  readonly passwordHint: string;
  readonly isPasswordVisible: boolean;
  readonly firstName: string;
  readonly lastName: string;
  readonly verificationId: number;
  readonly recaptchaKeyId: string;
  readonly recaptchaAction: string;
  readonly isSubmitting: boolean;
  readonly errorMessage: string | null;
  readonly errorCode: string | null;
  readonly rawAuthState: AuthState | null;

  constructor(
    step: AuthStep,
    countryCode: string,
    countryName: string,
    rawPhone: string,
    formattedPhone: string,
    code: string,
    codeLength: number,
    resendTimeoutSeconds: number,
    canResendCode: boolean,
    password: string,
    passwordHint: string,
    isPasswordVisible: boolean,
    firstName: string,
    lastName: string,
    verificationId: number,
    recaptchaKeyId: string,
    recaptchaAction: string,
    isSubmitting: boolean,
    errorMessage: string | null,
    errorCode: string | null,
    rawAuthState: AuthState | null
  ) {
    this.step = step;
    this.countryCode = countryCode;
    this.countryName = countryName;
    this.rawPhone = rawPhone;
    this.formattedPhone = formattedPhone;
    this.code = code;
    this.codeLength = codeLength;
    this.resendTimeoutSeconds = resendTimeoutSeconds;
    this.canResendCode = canResendCode;
    this.password = password;
    this.passwordHint = passwordHint;
    this.isPasswordVisible = isPasswordVisible;
    this.firstName = firstName;
    this.lastName = lastName;
    this.verificationId = verificationId;
    this.recaptchaKeyId = recaptchaKeyId;
    this.recaptchaAction = recaptchaAction;
    this.isSubmitting = isSubmitting;
    this.errorMessage = errorMessage;
    this.errorCode = errorCode;
    this.rawAuthState = rawAuthState;
  }

  static initial(): AuthUiState {
    return new AuthUiState(
      'waitPhone',
      DEFAULT_COUNTRY.dialCode,
      DEFAULT_COUNTRY.name,
      '',
      DEFAULT_COUNTRY.dialCode,
      '',
      5,
      60,
      false,
      '',
      '',
      false,
      '',
      '',
      0,
      '',
      '',
      false,
      null,
      null,
      null
    );
  }

  copyWith(options: AuthUiStateOptions): AuthUiState {
    return new AuthUiState(
      options.step !== undefined ? options.step : this.step,
      options.countryCode !== undefined ? options.countryCode : this.countryCode,
      options.countryName !== undefined ? options.countryName : this.countryName,
      options.rawPhone !== undefined ? options.rawPhone : this.rawPhone,
      options.formattedPhone !== undefined ? options.formattedPhone : this.formattedPhone,
      options.code !== undefined ? options.code : this.code,
      options.codeLength !== undefined ? options.codeLength : this.codeLength,
      options.resendTimeoutSeconds !== undefined ? options.resendTimeoutSeconds : this.resendTimeoutSeconds,
      options.canResendCode !== undefined ? options.canResendCode : this.canResendCode,
      options.password !== undefined ? options.password : this.password,
      options.passwordHint !== undefined ? options.passwordHint : this.passwordHint,
      options.isPasswordVisible !== undefined ? options.isPasswordVisible : this.isPasswordVisible,
      options.firstName !== undefined ? options.firstName : this.firstName,
      options.lastName !== undefined ? options.lastName : this.lastName,
      options.verificationId !== undefined ? options.verificationId : this.verificationId,
      options.recaptchaKeyId !== undefined ? options.recaptchaKeyId : this.recaptchaKeyId,
      options.recaptchaAction !== undefined ? options.recaptchaAction : this.recaptchaAction,
      options.isSubmitting !== undefined ? options.isSubmitting : this.isSubmitting,
      options.errorMessage !== undefined ? options.errorMessage : this.errorMessage,
      options.errorCode !== undefined ? options.errorCode : this.errorCode,
      options.rawAuthState !== undefined ? options.rawAuthState : this.rawAuthState
    );
  }
}
