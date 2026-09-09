/**
 * feature/auth — PasswordPage：2FA 密码输入页（AUTH-001）。
 *
 * 密码输入 + hint 显示 + 显隐切换 + 恢复邮箱入口占位。
 * 全部色彩/字号/间距用 design_system token。
 */

import { LightTheme } from '@tgx/core-design-system';

const T = LightTheme;

@Component
export struct PasswordPage {
  @Prop password: string = '';
  @Prop passwordHint: string = '';
  @Prop isPasswordVisible: boolean = false;
  @Prop isSubmitting: boolean = false;
  @Prop errorMessage: string | null = null;

  onPasswordChanged: (pwd: string) => void = () => {};
  onToggleVisibility: () => void = () => {};
  onSubmit: () => void = () => {};
  onBackToPhone: () => void = () => {};

  build() {
    Column() {
      Text('Two-Step Verification')
        .fontSize(T.typography.largeTitle.fontSize)
        .fontWeight(T.typography.largeTitle.fontWeight)
        .fontColor(T.colors.textPrimary)
        .margin({ top: T.spacing.huge, bottom: T.spacing.sm })

      Text('Your account is protected with an additional password.')
        .fontSize(T.typography.subheadline.fontSize)
        .fontColor(T.colors.textSecondary)
        .textAlign(TextAlign.Center)
        .margin({ bottom: T.spacing.xxl, left: T.spacing.lg, right: T.spacing.lg })

      Row() {
        TextInput({
          text: this.password,
          placeholder: 'Enter your password'
        })
          .type(this.isPasswordVisible ? InputType.Normal : InputType.Password)
          .fontSize(T.typography.body.fontSize)
          .layoutWeight(1)
          .backgroundColor(Color.Transparent)
          .onChange((val: string) => {
            this.onPasswordChanged(val);
          })

        Text(this.isPasswordVisible ? 'Hide' : 'Show')
          .fontSize(T.typography.subheadline.fontSize)
          .fontColor(T.colors.accent)
          .fontWeight(T.typography.headline.fontWeight)
          .margin({ left: T.spacing.sm })
          .onClick(() => {
            this.onToggleVisibility();
          })
      }
      .width('90%')
      .padding({ left: T.spacing.lg, right: T.spacing.lg, top: T.spacing.sm + T.spacing.xs, bottom: T.spacing.sm + T.spacing.xs })
      .backgroundColor(T.colors.surfaceVariant)
      .border({
        width: 1,
        color: this.errorMessage !== null ? T.colors.destructive : T.colors.border,
        radius: T.radius.md
      })

      if (this.passwordHint.length > 0) {
        Text(`Hint: ${this.passwordHint}`)
          .fontSize(T.typography.footnote.fontSize)
          .fontColor(T.colors.textSecondary)
          .margin({ top: T.spacing.sm, left: T.spacing.xxl, right: T.spacing.xxl })
          .alignSelf(ItemAlign.Start)
      }

      if (this.errorMessage !== null) {
        Text(this.errorMessage)
          .fontSize(T.typography.footnote.fontSize)
          .fontColor(T.colors.destructive)
          .margin({ top: T.spacing.sm, left: T.spacing.xxl, right: T.spacing.xxl })
          .alignSelf(ItemAlign.Start)
      }

      Blank()

      Button() {
        Row() {
          if (this.isSubmitting) {
            LoadingProgress()
              .width(20)
              .height(20)
              .color(T.colors.textOnAccent)
              .margin({ right: T.spacing.sm })
          }
          Text(this.isSubmitting ? 'Verifying...' : 'Continue')
            .fontSize(T.typography.callout.fontSize)
            .fontWeight(T.typography.largeTitle.fontWeight)
            .fontColor(T.colors.textOnAccent)
        }
      }
      .width('90%')
      .height(48)
      .backgroundColor(this.isSubmitting ? T.colors.disabled : T.colors.accent)
      .borderRadius(T.radius.full)
      .enabled(!this.isSubmitting)
      .margin({ bottom: T.spacing.huge })
      .onClick(() => {
        this.onSubmit();
      })
    }
    .width('100%')
    .height('100%')
    .backgroundColor(T.colors.background)
  }
}
