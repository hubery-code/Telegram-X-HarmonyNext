/**
 * feature/auth — AuthRootPage：授权流程根容器页（AUTH-001）。
 *
 * 依据 AuthUiState.step 分发子页面组件。
 * 全部色彩/字号/间距用 design_system token。
 */

import { LightTheme, Theme } from '@tgx/core-design-system';
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
  SubmitRecaptchaToken,
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


@Component
export struct AuthRootPage {
  /**
   * FEAT-UI-001 全局深色主题：entry 装配层把 ThemeManager 的当前主题写入
   * AppStorage('activeTheme')，本页以 @StorageProp 订阅。该值变化会触发本页
   * 重渲染。此前写死 `const T = LightTheme`，主题切换后引用不变，深色不生效。
   * 短名 T 直接落在装饰器成员上——ArkUI 的 build 转换不接管 struct 内自定义
   * getter，写成 getter 会在渲染闭包里取到 undefined 并抛 TypeError。
   */
  @StorageProp('activeTheme') T: Theme = LightTheme;
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
          recaptchaKeyId: this.uiState.recaptchaKeyId,
          isSubmitting: this.uiState.isSubmitting,
          onToken: (token: string) => {
            this.onDispatch(new SubmitRecaptchaToken(token));
          },
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
            .fontSize(this.T.typography.title.fontSize)
            .fontWeight(this.T.typography.largeTitle.fontWeight)
            .fontColor(this.T.colors.destructive)
            .margin({ top: 48, bottom: this.T.spacing.md })

          Text(this.uiState.errorMessage !== null ? this.uiState.errorMessage : 'An unexpected error occurred.')
            .fontSize(this.T.typography.footnote.fontSize)
            .fontColor(this.T.colors.textSecondary)
            .textAlign(TextAlign.Center)
            .margin({ bottom: this.T.spacing.xxl, left: this.T.spacing.xxl, right: this.T.spacing.xxl })

          Button('Try Again')
            .width('80%')
            .height(44)
            .backgroundColor(this.T.colors.accent)
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
            .color(this.T.colors.accent)
            .margin({ top: 120, bottom: this.T.spacing.lg })

          Text(this.uiState.step === 'ready' ? 'Signing in...' : 'Connecting...')
            .fontSize(this.T.typography.body.fontSize)
            .fontColor(this.T.colors.textSecondary)
        }
        .width('100%')
        .height('100%')
        .alignItems(HorizontalAlign.Center)
      }
    }
    .width('100%')
    .height('100%')
    .backgroundColor(this.T.colors.background)
  }
}
