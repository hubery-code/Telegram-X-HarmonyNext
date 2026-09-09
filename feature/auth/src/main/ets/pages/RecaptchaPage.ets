/**
 * TDLib 的 application reCAPTCHA 仅供受支持的官方移动端集成使用。
 * HarmonyOS NEXT 无法使用 Android package 绑定的 key，因此这里提供 TDLib
 * 原生二维码登录作为已有账号的安全兜底，不再尝试把移动端 key 塞进 WebView。
 */

import { LightTheme } from '@tgx/core-design-system';

const T = LightTheme;

@Component
export struct RecaptchaPage {
  @Prop isSubmitting: boolean = false;
  onUseQrCode: () => void = () => {};
  onBackToPhone: () => void = () => {};

  build() {
    Column() {
      Text('Verification unavailable')
        .fontSize(T.typography.largeTitle.fontSize)
        .fontWeight(T.typography.largeTitle.fontWeight)
        .fontColor(T.colors.textPrimary)
        .textAlign(TextAlign.Center)
        .margin({ top: T.spacing.huge, bottom: T.spacing.md })

      Text('This verification method is not supported on HarmonyOS NEXT. If you already use Telegram on another device, sign in securely with a QR code.')
        .fontSize(T.typography.subheadline.fontSize)
        .fontColor(T.colors.textSecondary)
        .textAlign(TextAlign.Center)
        .margin({ left: T.spacing.xxl, right: T.spacing.xxl })

      Blank()

      Button(this.isSubmitting ? 'Preparing QR code...' : 'Log in with QR code')
        .width('90%')
        .height(48)
        .backgroundColor(this.isSubmitting ? T.colors.disabled : T.colors.accent)
        .borderRadius(T.radius.full)
        .enabled(!this.isSubmitting)
        .onClick(() => {
          this.onUseQrCode();
        })

      Button('Use another phone number')
        .width('90%')
        .height(44)
        .fontColor(T.colors.accent)
        .backgroundColor(Color.Transparent)
        .margin({ top: T.spacing.sm, bottom: T.spacing.huge })
        .onClick(() => {
          this.onBackToPhone();
        })
    }
    .width('100%')
    .height('100%')
    .alignItems(HorizontalAlign.Center)
    .backgroundColor(T.colors.background)
  }
}
