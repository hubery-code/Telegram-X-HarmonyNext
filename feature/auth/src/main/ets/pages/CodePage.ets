/**
 * feature/auth — CodePage：验证码输入页（AUTH-001）。
 *
 * 验证码输入（codeLength 格子占位）、倒计时、重发按钮。
 * 全部色彩/字号/间距用 design_system token。
 */

import { LightTheme } from '@tgx/core-design-system';

const T = LightTheme;

@Component
export struct CodePage {
  @Prop formattedPhone: string = '';
  @Prop code: string = '';
  @Prop codeLength: number = 5;
  @Prop resendTimeoutSeconds: number = 60;
  @Prop canResendCode: boolean = false;
  @Prop isSubmitting: boolean = false;
  @Prop errorMessage: string | null = null;

  onCodeChanged: (code: string) => void = () => {};
  onSubmit: () => void = () => {};
  onResend: () => void = () => {};
  onBackToPhone: () => void = () => {};

  private formatCountdown(seconds: number): string {
    const mins: number = Math.floor(seconds / 60);
    const secs: number = seconds % 60;
    const secStr: string = secs < 10 ? `0${secs}` : `${secs}`;
    return `${mins}:${secStr}`;
  }

  build() {
    Column() {
      Text('Enter Code')
        .fontSize(T.typography.largeTitle.fontSize)
        .fontWeight(T.typography.largeTitle.fontWeight)
        .fontColor(T.colors.textPrimary)
        .margin({ top: T.spacing.huge, bottom: T.spacing.sm })

      Text(`We sent an SMS with the code to ${this.formattedPhone}`)
        .fontSize(T.typography.subheadline.fontSize)
        .fontColor(T.colors.textSecondary)
        .textAlign(TextAlign.Center)
        .margin({ bottom: T.spacing.sm, left: T.spacing.lg, right: T.spacing.lg })

      Text('Wrong number?')
        .fontSize(T.typography.subheadline.fontSize)
        .fontColor(T.colors.accent)
        .fontWeight(T.typography.headline.fontWeight)
        .margin({ bottom: T.spacing.xxl })
        .onClick(() => {
          this.onBackToPhone();
        })

      TextInput({
        text: this.code,
        placeholder: `Enter ${this.codeLength}-digit code`
      })
        .type(InputType.Number)
        .maxLength(this.codeLength)
        .fontSize(T.typography.largeTitle.fontSize)
        .fontWeight(T.typography.largeTitle.fontWeight)
        .textAlign(TextAlign.Center)
        .width('70%')
        .height(52)
        .backgroundColor(T.colors.surfaceVariant)
        .border({
          width: 1,
          color: this.errorMessage !== null ? T.colors.destructive : T.colors.border,
          radius: T.radius.md
        })
        .onChange((val: string) => {
          this.onCodeChanged(val);
        })

      if (this.errorMessage !== null) {
        Text(this.errorMessage)
          .fontSize(T.typography.footnote.fontSize)
          .fontColor(T.colors.destructive)
          .margin({ top: T.spacing.sm, left: T.spacing.xxl, right: T.spacing.xxl })
          .textAlign(TextAlign.Center)
      }

      if (this.canResendCode) {
        Text('Resend code')
          .fontSize(T.typography.subheadline.fontSize)
          .fontColor(T.colors.accent)
          .fontWeight(T.typography.headline.fontWeight)
          .margin({ top: T.spacing.xxl })
          .onClick(() => {
            this.onResend();
          })
      } else {
        Text(`Resend code in ${this.formatCountdown(this.resendTimeoutSeconds)}`)
          .fontSize(T.typography.subheadline.fontSize)
          .fontColor(T.colors.textTertiary)
          .margin({ top: T.spacing.xxl })
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
          Text(this.isSubmitting ? 'Verifying...' : 'Submit')
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
