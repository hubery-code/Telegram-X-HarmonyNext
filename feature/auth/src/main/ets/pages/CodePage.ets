/**
 * feature/auth — CodePage：验证码输入页（AUTH-001）。
 *
 * 验证码输入（codeLength 格子占位）、倒计时、重发按钮。
 * 全部色彩/字号/间距用 design_system token。
 */

import { LightTheme, Theme } from '@tgx/core-design-system';
import { Lang, SupportedLanguage } from '@tgx/core-common';


@Component
export struct CodePage {
  /**
   * FEAT-UI-001 全局深色主题：entry 装配层把 ThemeManager 的当前主题写入
   * AppStorage('activeTheme')，本页以 @StorageProp 订阅。该值变化会触发本页
   * 重渲染。此前写死 `const T = LightTheme`，主题切换后引用不变，深色不生效。
   * 短名 T 直接落在装饰器成员上——ArkUI 的 build 转换不接管 struct 内自定义
   * getter，写成 getter 会在渲染闭包里取到 undefined 并抛 TypeError。
   */
  @StorageProp('activeTheme') T: Theme = LightTheme;

  /**
   * I18N-HOTSWITCH-101：语言 tick。
   *
   * 装配层（entry/Index）订阅 Lang，把**有效语言**（'en' | 'zh'，不是偏好 'system'）镜像进
   * AppStorage('activeLanguage')；本页把它接成自己的可观察属性，于是 t() 读到的永远是
   * 当前语言，而**换语言会重渲染本页**——不再是「等下一次取数才有新字」（103/104 设备记录的头号
   * 盲区）。键缺席时 @StorageProp 用本行默认值自举，且挂载时自动取 AppStorage 现值，所以首帧
   * 就是对的，不需要再写一次手工同步。类型收在 string 而不是 SupportedLanguage：装饰器成员
   * 的字面量联合类型没有保证，而 t() 里反正要过一次收敛。
   */
  @StorageProp('activeLanguage') effectiveLanguage: string = 'en';
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

  private t(key: string, ...args: (string | number)[]): string {
    const langCode: SupportedLanguage = this.effectiveLanguage === 'zh' ? 'zh' : 'en';
    return Lang.getInstance().formatByKey(key, langCode, args);
  }

  build() {
    Column() {
      Text(this.t('Enter Code'))
        .fontSize(this.T.typography.largeTitle.fontSize)
        .fontWeight(this.T.typography.largeTitle.fontWeight)
        .fontColor(this.T.colors.textPrimary)
        .margin({ top: this.T.spacing.huge, bottom: this.T.spacing.sm })

      Text(this.t('We sent an SMS with the code to {0}', this.formattedPhone))
        .fontSize(this.T.typography.subheadline.fontSize)
        .fontColor(this.T.colors.textSecondary)
        .textAlign(TextAlign.Center)
        .margin({ bottom: this.T.spacing.sm, left: this.T.spacing.lg, right: this.T.spacing.lg })

      Text(this.t('Wrong number?'))
        .fontSize(this.T.typography.subheadline.fontSize)
        .fontColor(this.T.colors.accent)
        .fontWeight(this.T.typography.headline.fontWeight)
        .margin({ bottom: this.T.spacing.xxl })
        .onClick(() => {
          this.onBackToPhone();
        })

      TextInput({
        text: this.code,
        placeholder: this.t('Enter {0}-digit code', this.codeLength)
      })
        .type(InputType.Number)
        .maxLength(this.codeLength)
        .fontSize(this.T.typography.largeTitle.fontSize)
        .fontWeight(this.T.typography.largeTitle.fontWeight)
        .textAlign(TextAlign.Center)
        .width('70%')
        .height(52)
        .backgroundColor(this.T.colors.surfaceVariant)
        .border({
          width: 1,
          color: this.errorMessage !== null ? this.T.colors.destructive : this.T.colors.border,
          radius: this.T.radius.md
        })
        .onChange((val: string) => {
          this.onCodeChanged(val);
        })

      if (this.errorMessage !== null) {
        Text(this.errorMessage)
          .fontSize(this.T.typography.footnote.fontSize)
          .fontColor(this.T.colors.destructive)
          .margin({ top: this.T.spacing.sm, left: this.T.spacing.xxl, right: this.T.spacing.xxl })
          .textAlign(TextAlign.Center)
      }

      if (this.canResendCode) {
        Text(this.t('Resend code'))
          .fontSize(this.T.typography.subheadline.fontSize)
          .fontColor(this.T.colors.accent)
          .fontWeight(this.T.typography.headline.fontWeight)
          .margin({ top: this.T.spacing.xxl })
          .onClick(() => {
            this.onResend();
          })
      } else {
        Text(this.t('Resend code in {0}', this.formatCountdown(this.resendTimeoutSeconds)))
          .fontSize(this.T.typography.subheadline.fontSize)
          .fontColor(this.T.colors.textTertiary)
          .margin({ top: this.T.spacing.xxl })
      }

      Blank()

      Button() {
        Row() {
          if (this.isSubmitting) {
            LoadingProgress()
              .width(20)
              .height(20)
              .color(this.T.colors.textOnAccent)
              .margin({ right: this.T.spacing.sm })
          }
          Text(this.t(this.isSubmitting ? 'Verifying...' : 'Submit'))
            .fontSize(this.T.typography.callout.fontSize)
            .fontWeight(this.T.typography.largeTitle.fontWeight)
            .fontColor(this.T.colors.textOnAccent)
        }
      }
      .width('90%')
      .height(48)
      .backgroundColor(this.isSubmitting ? this.T.colors.disabled : this.T.colors.accent)
      .borderRadius(this.T.radius.full)
      .enabled(!this.isSubmitting)
      .margin({ bottom: this.T.spacing.huge })
      .onClick(() => {
        this.onSubmit();
      })
    }
    .width('100%')
    .height('100%')
    .backgroundColor(this.T.colors.background)
  }
}
