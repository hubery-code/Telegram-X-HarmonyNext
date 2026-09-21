/**
 * feature/auth — PhonePage：手机号输入页（AUTH-001）。
 *
 * 国家码选择 + 手机号输入 + 条款占位 + 继续按钮。
 * 全部色彩/字号/间距用 design_system token，不硬编码。
 */

import { LightTheme, Theme } from '@tgx/core-design-system';
import { CountryInfo, DEFAULT_COUNTRY, SUPPORTED_COUNTRIES } from '../model/CountryCode';


@Component
export struct PhonePage {
  /**
   * FEAT-UI-001 全局深色主题：entry 装配层把 ThemeManager 的当前主题写入
   * AppStorage('activeTheme')，本页以 @StorageProp 订阅。该值变化会触发本页
   * 重渲染。此前写死 `const T = LightTheme`，主题切换后引用不变，深色不生效。
   * 短名 T 直接落在装饰器成员上——ArkUI 的 build 转换不接管 struct 内自定义
   * getter，写成 getter 会在渲染闭包里取到 undefined 并抛 TypeError。
   */
  @StorageProp('activeTheme') T: Theme = LightTheme;
  @Prop countryCode: string = DEFAULT_COUNTRY.dialCode;
  @Prop countryName: string = DEFAULT_COUNTRY.name;
  @Prop rawPhone: string = '';
  @Prop isSubmitting: boolean = false;
  @Prop errorMessage: string | null = null;

  onCountrySelected: (info: CountryInfo) => void = () => {};
  onPhoneChanged: (phone: string) => void = () => {};
  onSubmit: () => void = () => {};
  onUseQrCode: () => void = () => {};

  @State showCountryPicker: boolean = false;

  build() {
    Column() {
      Text('Your Phone')
        .fontSize(this.T.typography.largeTitle.fontSize)
        .fontWeight(this.T.typography.largeTitle.fontWeight)
        .fontColor(this.T.colors.textPrimary)
        .margin({ top: this.T.spacing.huge, bottom: this.T.spacing.sm })

      Text('Please confirm your country code and enter your phone number.')
        .fontSize(this.T.typography.subheadline.fontSize)
        .fontColor(this.T.colors.textSecondary)
        .textAlign(TextAlign.Center)
        .margin({ bottom: this.T.spacing.xxl, left: this.T.spacing.lg, right: this.T.spacing.lg })

      Row() {
        Text(this.countryName)
          .fontSize(this.T.typography.headline.fontSize)
          .fontColor(this.T.colors.textPrimary)
          .layoutWeight(1)

        Text(this.countryCode)
          .fontSize(this.T.typography.headline.fontSize)
          .fontColor(this.T.colors.accent)
          .fontWeight(this.T.typography.headline.fontWeight)

        Image($r('app.media.ic_chevron_down'))
          .width(20)
          .height(20)
          .fillColor(this.T.colors.textSecondary)
          .margin({ left: this.T.spacing.xs })
      }
      .width('90%')
      .padding({ left: this.T.spacing.lg, right: this.T.spacing.lg, top: this.T.spacing.md, bottom: this.T.spacing.md })
      .backgroundColor(this.T.colors.backgroundSecondary)
      .borderRadius(this.T.radius.md)
      .onClick(() => {
        this.showCountryPicker = !this.showCountryPicker;
      })

      if (this.showCountryPicker) {
        List() {
          ForEach(SUPPORTED_COUNTRIES, (item: CountryInfo) => {
            ListItem() {
              Row() {
                Text(item.name)
                  .fontSize(this.T.typography.subheadline.fontSize)
                  .fontColor(this.T.colors.textPrimary)
                  .layoutWeight(1)
                Text(item.dialCode)
                  .fontSize(this.T.typography.subheadline.fontSize)
                  .fontColor(this.T.colors.textSecondary)
              }
              .width('100%')
              .padding({ top: this.T.spacing.sm + this.T.spacing.xs, bottom: this.T.spacing.sm + this.T.spacing.xs, left: this.T.spacing.lg, right: this.T.spacing.lg })
              .onClick(() => {
                this.onCountrySelected(item);
                this.showCountryPicker = false;
              })
            }
          })
        }
        .width('90%')
        .height(180)
        .backgroundColor(this.T.colors.surface)
        .border({ width: 1, color: this.T.colors.divider, radius: this.T.radius.md })
        .margin({ top: this.T.spacing.xs })
      }

      Row() {
        Text(this.countryCode)
          .fontSize(this.T.typography.body.fontSize)
          .fontWeight(this.T.typography.headline.fontWeight)
          .fontColor(this.T.colors.textPrimary)
          .margin({ right: this.T.spacing.sm })

        TextInput({ text: this.rawPhone, placeholder: 'Phone number' })
          .type(InputType.PhoneNumber)
          .fontSize(this.T.typography.body.fontSize)
          .layoutWeight(1)
          .backgroundColor(Color.Transparent)
          .onChange((value: string) => {
            this.onPhoneChanged(value);
          })
      }
      .width('90%')
      .padding({ left: this.T.spacing.lg, right: this.T.spacing.lg, top: this.T.spacing.sm + this.T.spacing.xs, bottom: this.T.spacing.sm + this.T.spacing.xs })
      .margin({ top: this.T.spacing.lg })
      .backgroundColor(this.T.colors.surfaceVariant)
      .border({
        width: 1,
        color: this.errorMessage !== null ? this.T.colors.destructive : this.T.colors.border,
        radius: this.T.radius.md
      })

      if (this.errorMessage !== null) {
        Text(this.errorMessage)
          .fontSize(this.T.typography.footnote.fontSize)
          .fontColor(this.T.colors.destructive)
          .margin({ top: this.T.spacing.sm, left: this.T.spacing.xxl, right: this.T.spacing.xxl })
          .textAlign(TextAlign.Start)
      }

      Blank()

      Button('Log in with QR code')
        .width('90%')
        .height(44)
        .fontColor(this.T.colors.accent)
        .backgroundColor(Color.Transparent)
        .enabled(!this.isSubmitting)
        .margin({ bottom: this.T.spacing.sm })
        .onClick(() => {
          this.onUseQrCode();
        })

      Button() {
        Row() {
          if (this.isSubmitting) {
            LoadingProgress()
              .width(20)
              .height(20)
              .color(this.T.colors.textOnAccent)
              .margin({ right: this.T.spacing.sm })
          }
          Text(this.isSubmitting ? 'Connecting...' : 'Continue')
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
