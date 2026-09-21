/** feature/auth — TDLib 原生二维码登录页（AUTH-QR-001）。 */

import { LightTheme, Theme } from '@tgx/core-design-system';


@Component
export struct QrCodePage {
  /**
   * FEAT-UI-001 全局深色主题：entry 装配层把 ThemeManager 的当前主题写入
   * AppStorage('activeTheme')，本页以 @StorageProp 订阅。该值变化会触发本页
   * 重渲染。此前写死 `const T = LightTheme`，主题切换后引用不变，深色不生效。
   * 短名 T 直接落在装饰器成员上——ArkUI 的 build 转换不接管 struct 内自定义
   * getter，写成 getter 会在渲染闭包里取到 undefined 并抛 TypeError。
   */
  @StorageProp('activeTheme') T: Theme = LightTheme;
  @Prop link: string = '';
  @Prop errorMessage: string | null = null;
  onRetry: () => void = () => {};

  build() {
    Column() {
      Text('Log in with QR code')
        .fontSize(this.T.typography.largeTitle.fontSize)
        .fontWeight(this.T.typography.largeTitle.fontWeight)
        .fontColor(this.T.colors.textPrimary)
        .textAlign(TextAlign.Center)
        .margin({ top: this.T.spacing.huge, bottom: this.T.spacing.sm })

      Text('Open Telegram on another device, then go to Settings > Devices > Link Desktop Device and scan this code.')
        .fontSize(this.T.typography.subheadline.fontSize)
        .fontColor(this.T.colors.textSecondary)
        .textAlign(TextAlign.Center)
        .margin({ left: this.T.spacing.xxl, right: this.T.spacing.xxl, bottom: this.T.spacing.xxl })

      if (this.link.length > 0) {
        Stack() {
          Rect()
            .width(272)
            .height(272)
            .fill(Color.White)
            .radius(this.T.radius.md)

          QRCode(this.link)
            .width(240)
            .height(240)
            .color(Color.Black)
            .backgroundColor(Color.White)

          Image($r('app.media.ic_qrcode_scan'))
            .width(44)
            .height(44)
            .fillColor(this.T.colors.accent)
            .backgroundColor(Color.White)
            .borderRadius(this.T.radius.sm)
            .padding(4)
        }
        .width(272)
        .height(272)
      } else {
        Column() {
          if (this.errorMessage === null) {
            Image($r('app.media.ic_qrcode_scan'))
              .width(48)
              .height(48)
              .fillColor(this.T.colors.accent)
              .margin({ bottom: this.T.spacing.md })

            LoadingProgress()
              .width(36)
              .height(36)
              .color(this.T.colors.accent)
              .margin({ bottom: this.T.spacing.md })

            Text('Preparing a secure QR code...')
              .fontSize(this.T.typography.body.fontSize)
              .fontColor(this.T.colors.textSecondary)
          } else {
            Text(this.errorMessage)
              .fontSize(this.T.typography.body.fontSize)
              .fontColor(this.T.colors.destructive)
              .textAlign(TextAlign.Center)
              .margin({ left: this.T.spacing.md, right: this.T.spacing.md, bottom: this.T.spacing.md })

            Button('Try again')
              .fontColor(this.T.colors.textOnAccent)
              .backgroundColor(this.T.colors.accent)
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
        .fontSize(this.T.typography.footnote.fontSize)
        .fontColor(this.T.colors.textSecondary)
        .textAlign(TextAlign.Center)
        .margin({ top: this.T.spacing.xxl, left: this.T.spacing.xxl, right: this.T.spacing.xxl })

      Blank()
    }
    .width('100%')
    .height('100%')
    .alignItems(HorizontalAlign.Center)
    .backgroundColor(this.T.colors.background)
  }
}
