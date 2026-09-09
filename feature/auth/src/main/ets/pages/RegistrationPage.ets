/**
 * feature/auth — RegistrationPage：新用户注册页（AUTH-001）。
 *
 * 名/姓输入 + 注册按钮。
 * 全部色彩/字号/间距用 design_system token。
 */

import { LightTheme } from '@tgx/core-design-system';

const T = LightTheme;

@Component
export struct RegistrationPage {
  @Prop firstName: string = '';
  @Prop lastName: string = '';
  @Prop isSubmitting: boolean = false;
  @Prop errorMessage: string | null = null;

  onFirstNameChanged: (fn: string) => void = () => {};
  onLastNameChanged: (ln: string) => void = () => {};
  onSubmit: () => void = () => {};

  build() {
    Column() {
      Text('Your Name')
        .fontSize(T.typography.largeTitle.fontSize)
        .fontWeight(T.typography.largeTitle.fontWeight)
        .fontColor(T.colors.textPrimary)
        .margin({ top: T.spacing.huge, bottom: T.spacing.sm })

      Text('Enter your name to complete registration.')
        .fontSize(T.typography.subheadline.fontSize)
        .fontColor(T.colors.textSecondary)
        .textAlign(TextAlign.Center)
        .margin({ bottom: T.spacing.xxl, left: T.spacing.lg, right: T.spacing.lg })

      TextInput({
        text: this.firstName,
        placeholder: 'First name (required)'
      })
        .fontSize(T.typography.body.fontSize)
        .width('90%')
        .height(48)
        .backgroundColor(T.colors.surfaceVariant)
        .border({
          width: 1,
          color: this.errorMessage !== null ? T.colors.destructive : T.colors.border,
          radius: T.radius.md
        })
        .margin({ bottom: T.spacing.md })
        .onChange((val: string) => {
          this.onFirstNameChanged(val);
        })

      TextInput({
        text: this.lastName,
        placeholder: 'Last name (optional)'
      })
        .fontSize(T.typography.body.fontSize)
        .width('90%')
        .height(48)
        .backgroundColor(T.colors.surfaceVariant)
        .border({
          width: 1,
          color: T.colors.border,
          radius: T.radius.md
        })
        .onChange((val: string) => {
          this.onLastNameChanged(val);
        })

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
          Text(this.isSubmitting ? 'Registering...' : 'Complete')
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
