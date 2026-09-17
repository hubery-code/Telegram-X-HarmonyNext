/**
 * feature/auth — PhonePage：手机号输入页（AUTH-001）。
 *
 * 国家码选择 + 手机号输入 + 条款占位 + 继续按钮。
 * 全部色彩/字号/间距用 design_system token，不硬编码。
 */

import { LightTheme } from '@tgx/core-design-system';
import { CountryInfo, DEFAULT_COUNTRY, SUPPORTED_COUNTRIES } from '../model/CountryCode';

const T = LightTheme;

@Component
export struct PhonePage {
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
        .fontSize(T.typography.largeTitle.fontSize)
        .fontWeight(T.typography.largeTitle.fontWeight)
        .fontColor(T.colors.textPrimary)
        .margin({ top: T.spacing.huge, bottom: T.spacing.sm })

      Text('Please confirm your country code and enter your phone number.')
        .fontSize(T.typography.subheadline.fontSize)
        .fontColor(T.colors.textSecondary)
        .textAlign(TextAlign.Center)
        .margin({ bottom: T.spacing.xxl, left: T.spacing.lg, right: T.spacing.lg })

      Row() {
        Text(this.countryName)
          .fontSize(T.typography.headline.fontSize)
          .fontColor(T.colors.textPrimary)
          .layoutWeight(1)

        Text(this.countryCode)
          .fontSize(T.typography.headline.fontSize)
          .fontColor(T.colors.accent)
          .fontWeight(T.typography.headline.fontWeight)

        Image($r('app.media.ic_chevron_down'))
          .width(20)
          .height(20)
          .fillColor(T.colors.textSecondary)
          .margin({ left: T.spacing.xs })
      }
      .width('90%')
      .padding({ left: T.spacing.lg, right: T.spacing.lg, top: T.spacing.md, bottom: T.spacing.md })
      .backgroundColor(T.colors.backgroundSecondary)
      .borderRadius(T.radius.md)
      .onClick(() => {
        this.showCountryPicker = !this.showCountryPicker;
      })

      if (this.showCountryPicker) {
        List() {
          ForEach(SUPPORTED_COUNTRIES, (item: CountryInfo) => {
            ListItem() {
              Row() {
                Text(item.name)
                  .fontSize(T.typography.subheadline.fontSize)
                  .fontColor(T.colors.textPrimary)
                  .layoutWeight(1)
                Text(item.dialCode)
                  .fontSize(T.typography.subheadline.fontSize)
                  .fontColor(T.colors.textSecondary)
              }
              .width('100%')
              .padding({ top: T.spacing.sm + T.spacing.xs, bottom: T.spacing.sm + T.spacing.xs, left: T.spacing.lg, right: T.spacing.lg })
              .onClick(() => {
                this.onCountrySelected(item);
                this.showCountryPicker = false;
              })
            }
          })
        }
        .width('90%')
        .height(180)
        .backgroundColor(T.colors.surface)
        .border({ width: 1, color: T.colors.divider, radius: T.radius.md })
        .margin({ top: T.spacing.xs })
      }

      Row() {
        Text(this.countryCode)
          .fontSize(T.typography.body.fontSize)
          .fontWeight(T.typography.headline.fontWeight)
          .fontColor(T.colors.textPrimary)
          .margin({ right: T.spacing.sm })

        TextInput({ text: this.rawPhone, placeholder: 'Phone number' })
          .type(InputType.PhoneNumber)
          .fontSize(T.typography.body.fontSize)
          .layoutWeight(1)
          .backgroundColor(Color.Transparent)
          .onChange((value: string) => {
            this.onPhoneChanged(value);
          })
      }
      .width('90%')
      .padding({ left: T.spacing.lg, right: T.spacing.lg, top: T.spacing.sm + T.spacing.xs, bottom: T.spacing.sm + T.spacing.xs })
      .margin({ top: T.spacing.lg })
      .backgroundColor(T.colors.surfaceVariant)
      .border({
        width: 1,
        color: this.errorMessage !== null ? T.colors.destructive : T.colors.border,
        radius: T.radius.md
      })

      if (this.errorMessage !== null) {
        Text(this.errorMessage)
          .fontSize(T.typography.footnote.fontSize)
          .fontColor(T.colors.destructive)
          .margin({ top: T.spacing.sm, left: T.spacing.xxl, right: T.spacing.xxl })
          .textAlign(TextAlign.Start)
      }

      Blank()

      Button('Log in with QR code')
        .width('90%')
        .height(44)
        .fontColor(T.colors.accent)
        .backgroundColor(Color.Transparent)
        .enabled(!this.isSubmitting)
        .margin({ bottom: T.spacing.sm })
        .onClick(() => {
          this.onUseQrCode();
        })

      Button() {
        Row() {
          if (this.isSubmitting) {
            LoadingProgress()
              .width(20)
              .height(20)
              .color(T.colors.textOnAccent)
              .margin({ right: T.spacing.sm })
          }
          Text(this.isSubmitting ? 'Connecting...' : 'Continue')
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
