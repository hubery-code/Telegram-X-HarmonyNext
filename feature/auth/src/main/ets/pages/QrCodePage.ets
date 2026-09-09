/** feature/auth — TDLib 原生二维码登录页（AUTH-QR-001）。 */

import { LightTheme } from '@tgx/core-design-system';

const T = LightTheme;

@Component
export struct QrCodePage {
  @Prop link: string = '';
  @Prop errorMessage: string | null = null;
  onRetry: () => void = () => {};

  build() {
    Column() {
      Text('Log in with QR code')
        .fontSize(T.typography.largeTitle.fontSize)
        .fontWeight(T.typography.largeTitle.fontWeight)
        .fontColor(T.colors.textPrimary)
        .textAlign(TextAlign.Center)
        .margin({ top: T.spacing.huge, bottom: T.spacing.sm })

      Text('Open Telegram on another device, then go to Settings > Devices > Link Desktop Device and scan this code.')
        .fontSize(T.typography.subheadline.fontSize)
        .fontColor(T.colors.textSecondary)
        .textAlign(TextAlign.Center)
        .margin({ left: T.spacing.xxl, right: T.spacing.xxl, bottom: T.spacing.xxl })

      if (this.link.length > 0) {
        Stack() {
          Rect()
            .width(272)
            .height(272)
            .fill(Color.White)
            .radius(T.radius.md)

          QRCode(this.link)
            .width(240)
            .height(240)
            .color(Color.Black)
            .backgroundColor(Color.White)
        }
        .width(272)
        .height(272)
      } else {
        Column() {
          if (this.errorMessage === null) {
            LoadingProgress()
              .width(48)
              .height(48)
              .color(T.colors.accent)
              .margin({ bottom: T.spacing.md })

            Text('Preparing a secure QR code...')
              .fontSize(T.typography.body.fontSize)
              .fontColor(T.colors.textSecondary)
          } else {
            Text(this.errorMessage)
              .fontSize(T.typography.body.fontSize)
              .fontColor(T.colors.destructive)
              .textAlign(TextAlign.Center)
              .margin({ left: T.spacing.md, right: T.spacing.md, bottom: T.spacing.md })

            Button('Try again')
              .fontColor(T.colors.textOnAccent)
              .backgroundColor(T.colors.accent)
              .onClick(() => {
                this.onRetry();
              })
          }
        }
        .width(272)
        .height(272)
        .justifyContent(FlexAlign.Center)
      }

      Text('The code refreshes automatically. Keep this screen open while scanning.')
        .fontSize(T.typography.footnote.fontSize)
        .fontColor(T.colors.textSecondary)
        .textAlign(TextAlign.Center)
        .margin({ top: T.spacing.xxl, left: T.spacing.xxl, right: T.spacing.xxl })

      Blank()
    }
    .width('100%')
    .height('100%')
    .alignItems(HorizontalAlign.Center)
    .backgroundColor(T.colors.background)
  }
}
