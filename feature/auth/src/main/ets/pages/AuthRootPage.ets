/**
 * feature/auth — AuthRootPage：授权流程根容器页（AUTH-001）。
 *
 * 依据 AuthUiState.step 分发子页面组件。
 * 全部色彩/字号/间距用 design_system token。
 */

import { LightTheme } from '@tgx/core-design-system';
import { AuthUiState } from '../contract/AuthUiState';
import {
  BackToPhone,
  ChangeCodeInput,
  ChangeFirstName,
  ChangeLastName,
  ChangePasswordInput,
  ChangePhoneInput,
  ClearError,
  RequestResendCode,
  SelectCountry,
  SubmitCode,
  SubmitPassword,
  SubmitPhone,
  SubmitRegistration,
  RequestQrCodeLogin,
  TogglePasswordVisibility
} from '../contract/AuthIntent';
import { CountryInfo } from '../model/CountryCode';
import { PhonePage } from './PhonePage';
import { CodePage } from './CodePage';
import { PasswordPage } from './PasswordPage';
import { RegistrationPage } from './RegistrationPage';
import { RecaptchaPage } from './RecaptchaPage';
import { QrCodePage } from './QrCodePage';

const T = LightTheme;

@Component
export struct AuthRootPage {
  @Prop uiState: AuthUiState = AuthUiState.initial();

  onDispatch: (intent: Object) => void = () => {};

  build() {
    Column() {
      if (this.uiState.step === 'waitPhone') {
        PhonePage({
          countryCode: this.uiState.countryCode,
          countryName: this.uiState.countryName,
          rawPhone: this.uiState.rawPhone,
          isSubmitting: this.uiState.isSubmitting,
          errorMessage: this.uiState.errorMessage,
          onCountrySelected: (info: CountryInfo) => {
            this.onDispatch(new SelectCountry(info.dialCode, info.name));
          },
          onPhoneChanged: (phone: string) => {
            this.onDispatch(new ChangePhoneInput(phone));
          },
          onSubmit: () => {
            this.onDispatch(new SubmitPhone());
          },
          onUseQrCode: () => {
            this.onDispatch(new RequestQrCodeLogin());
          }
        })
      } else if (this.uiState.step === 'waitCode') {
        CodePage({
          formattedPhone: this.uiState.formattedPhone,
          code: this.uiState.code,
          codeLength: this.uiState.codeLength,
          resendTimeoutSeconds: this.uiState.resendTimeoutSeconds,
          canResendCode: this.uiState.canResendCode,
          isSubmitting: this.uiState.isSubmitting,
          errorMessage: this.uiState.errorMessage,
          onCodeChanged: (code: string) => {
            this.onDispatch(new ChangeCodeInput(code));
          },
          onSubmit: () => {
            this.onDispatch(new SubmitCode());
          },
          onResend: () => {
            this.onDispatch(new RequestResendCode());
          },
          onBackToPhone: () => {
            this.onDispatch(new BackToPhone());
          }
        })
      } else if (this.uiState.step === 'wait2fa') {
        PasswordPage({
          password: this.uiState.password,
          passwordHint: this.uiState.passwordHint,
          isPasswordVisible: this.uiState.isPasswordVisible,
          isSubmitting: this.uiState.isSubmitting,
          errorMessage: this.uiState.errorMessage,
          onPasswordChanged: (pwd: string) => {
            this.onDispatch(new ChangePasswordInput(pwd));
          },
          onToggleVisibility: () => {
            this.onDispatch(new TogglePasswordVisibility());
          },
          onSubmit: () => {
            this.onDispatch(new SubmitPassword());
          },
          onBackToPhone: () => {
            this.onDispatch(new BackToPhone());
          }
        })
      } else if (this.uiState.step === 'waitRegistration') {
        RegistrationPage({
          firstName: this.uiState.firstName,
          lastName: this.uiState.lastName,
          isSubmitting: this.uiState.isSubmitting,
          errorMessage: this.uiState.errorMessage,
          onFirstNameChanged: (fn: string) => {
            this.onDispatch(new ChangeFirstName(fn));
          },
          onLastNameChanged: (ln: string) => {
            this.onDispatch(new ChangeLastName(ln));
          },
          onSubmit: () => {
            this.onDispatch(new SubmitRegistration());
          }
        })
      } else if (this.uiState.step === 'waitRecaptcha') {
        RecaptchaPage({
          isSubmitting: this.uiState.isSubmitting,
          onUseQrCode: () => {
            this.onDispatch(new RequestQrCodeLogin());
          },
          onBackToPhone: () => {
            this.onDispatch(new BackToPhone());
          }
        })
      } else if (this.uiState.step === 'waitQrCode') {
        QrCodePage({
          link: this.uiState.qrCodeLink,
          errorMessage: this.uiState.errorMessage,
          onRetry: () => {
            this.onDispatch(new RequestQrCodeLogin());
          }
        })
      } else if (this.uiState.step === 'failed') {
        Column() {
          Text('Authorization Failed')
            .fontSize(T.typography.title.fontSize)
            .fontWeight(T.typography.largeTitle.fontWeight)
            .fontColor(T.colors.destructive)
            .margin({ top: 48, bottom: T.spacing.md })

          Text(this.uiState.errorMessage !== null ? this.uiState.errorMessage : 'An unexpected error occurred.')
            .fontSize(T.typography.footnote.fontSize)
            .fontColor(T.colors.textSecondary)
            .textAlign(TextAlign.Center)
            .margin({ bottom: T.spacing.xxl, left: T.spacing.xxl, right: T.spacing.xxl })

          Button('Try Again')
            .width('80%')
            .height(44)
            .backgroundColor(T.colors.accent)
            .onClick(() => {
              this.onDispatch(new BackToPhone());
            })
        }
        .width('100%')
        .height('100%')
        .alignItems(HorizontalAlign.Center)
      } else {
        Column() {
          LoadingProgress()
            .width(48)
            .height(48)
            .color(T.colors.accent)
            .margin({ top: 120, bottom: T.spacing.lg })

          Text(this.uiState.step === 'ready' ? 'Signing in...' : 'Connecting...')
            .fontSize(T.typography.body.fontSize)
            .fontColor(T.colors.textSecondary)
        }
        .width('100%')
        .height('100%')
        .alignItems(HorizontalAlign.Center)
      }
    }
    .width('100%')
    .height('100%')
    .backgroundColor(T.colors.background)
  }
}
