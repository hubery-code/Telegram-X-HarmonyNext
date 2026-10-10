/**
 * feature/auth — PasswordPage：2FA 密码输入页（AUTH-001）。
 *
 * 密码输入 + hint 显示 + 显隐切换 + 恢复邮箱入口占位。
 * 全部色彩/字号/间距用 design_system token。
 */

import { LightTheme, Theme } from '@tgx/core-design-system';
import { A11y, a11y, Lang, SupportedLanguage } from '@tgx/core-common';


@Component
export struct PasswordPage {
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
  @Prop password: string = '';
  @Prop passwordHint: string = '';
  @Prop isPasswordVisible: boolean = false;
  @Prop isSubmitting: boolean = false;
  @Prop errorMessage: string | null = null;

  onPasswordChanged: (pwd: string) => void = () => {};
  onToggleVisibility: () => void = () => {};
  onSubmit: () => void = () => {};
  onBackToPhone: () => void = () => {};

  private t(key: string, ...args: (string | number)[]): string {
    const langCode: SupportedLanguage = this.effectiveLanguage === 'zh' ? 'zh' : 'en';
    return Lang.getInstance().formatByKey(key, langCode, args);
  }

  build() {
    Column() {
      Text(this.t('Two-Step Verification'))
        .fontSize(this.T.typography.largeTitle.fontSize)
        .fontWeight(this.T.typography.largeTitle.fontWeight)
        .fontColor(this.T.colors.textPrimary)
        .margin({ top: this.T.spacing.huge, bottom: this.T.spacing.sm })

      Text(this.t('Your account is protected with an additional password.'))
        .fontSize(this.T.typography.subheadline.fontSize)
        .fontColor(this.T.colors.textSecondary)
        .textAlign(TextAlign.Center)
        .margin({ bottom: this.T.spacing.xxl, left: this.T.spacing.lg, right: this.T.spacing.lg })

      Row() {
        TextInput({
          text: this.password,
          placeholder: this.t('Enter your password')
        })
          .type(this.isPasswordVisible ? InputType.Normal : InputType.Password)
          .fontSize(this.T.typography.body.fontSize)
          .layoutWeight(1)
          .backgroundColor(Color.Transparent)
          .onChange((val: string) => {
            this.onPasswordChanged(val);
          })

        Image($r(this.isPasswordVisible ? 'app.media.ic_visibility' : 'app.media.ic_visibility_off'))
          .width(24)
          .height(24)
          .fillColor(this.T.colors.icon)
          .margin({ left: this.T.spacing.sm })
        .accessibilityText(a11y(this.isPasswordVisible ? A11y.HIDE_PASSWORD : A11y.SHOW_PASSWORD))
          .onClick(() => {
            this.onToggleVisibility();
          })
      }
      .width('90%')
      .padding({ left: this.T.spacing.lg, right: this.T.spacing.lg, top: this.T.spacing.sm + this.T.spacing.xs, bottom: this.T.spacing.sm + this.T.spacing.xs })
      .backgroundColor(this.T.colors.surfaceVariant)
      .border({
        width: 1,
        color: this.errorMessage !== null ? this.T.colors.destructive : this.T.colors.border,
        radius: this.T.radius.md
      })

      if (this.passwordHint.length > 0) {
        Text(this.t('Hint: {0}', this.passwordHint))
          .fontSize(this.T.typography.footnote.fontSize)
          .fontColor(this.T.colors.textSecondary)
          .margin({ top: this.T.spacing.sm, left: this.T.spacing.xxl, right: this.T.spacing.xxl })
          .alignSelf(ItemAlign.Start)
      }

      if (this.errorMessage !== null) {
        Text(this.errorMessage)
          .fontSize(this.T.typography.footnote.fontSize)
          .fontColor(this.T.colors.destructive)
          .margin({ top: this.T.spacing.sm, left: this.T.spacing.xxl, right: this.T.spacing.xxl })
          .alignSelf(ItemAlign.Start)
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
          Text(this.t(this.isSubmitting ? 'Verifying...' : 'Continue'))
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
