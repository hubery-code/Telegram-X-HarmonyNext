/**
 * feature/settings — 设置主页与账号中心组件（SET-101）。
 *
 * 遵循计划 §5.11 / UI-003：
 * - ArkUI 组件；
 * - 展示个人头像（无图展示首字母占位色块）、用户名、手机号；
 * - 各项设置条目（通知开关、缓存清理、主题模式切换）；
 * - 退出登录按钮及确认对话框；
 * - 加载中与错误状态提示；
 * - 色彩/字号/间距全部使用 design_system token。
 */

import { DarkTheme, LightTheme, Theme, ThemeManager } from '@tgx/core-design-system';
import { Lang, LanguagePreference, SupportedLanguage } from '@tgx/core-common';
import { SettingsThemeMode, SettingsUiState } from '../contract/SettingsUiState';
import {
  CancelLogout,
  ChangeLanguage,
  ChangeThemeMode,
  ClearCacheRequested,
  ConfirmLogout,
  RequestLogout,
  SetErrorMessage,
  SettingsIntent,
  ToggleNotifications
} from '../contract/SettingsIntent';

const AVATAR_SIZE: number = 64;
const BACK_ARROW_SIZE: number = 44;

export const AVATAR_PALETTE: string[] = [
  '#FFCC5049', // red
  '#FFD67722', // orange
  '#FF955CDB', // violet
  '#FF40A920', // green
  '#FF309EBA', // cyan
  '#FF368AD1', // blue
  '#FFC7508B'  // pink
];

@Component
export struct SettingsPage {
  @Prop @Watch('onUiStateChanged') uiState: SettingsUiState = SettingsUiState.initial();
  onDispatch: (intent: SettingsIntent) => void = (): void => {};

  /** 返回上一页（纯导航回调，由装配层接线，INTEG-001）。 */
  onBack: () => void = (): void => {};

  @State private effectiveTheme: Theme = LightTheme;
  @State private effectiveLang: SupportedLanguage = 'en';
  private unsubscribeTheme: (() => void) | null = null;
  private unsubscribeLang: (() => void) | null = null;

  aboutToAppear(): void {
    this.updateEffectiveTheme();
    this.effectiveLang = Lang.getInstance().getLanguage();
    const self: SettingsPage = this;
    this.unsubscribeTheme = ThemeManager.getInstance().subscribe((_theme: Theme): void => {
      self.updateEffectiveTheme();
    });
    this.unsubscribeLang = Lang.getInstance().subscribe((lang: SupportedLanguage): void => {
      self.effectiveLang = lang;
    });
  }

  aboutToDisappear(): void {
    if (this.unsubscribeTheme !== null) {
      this.unsubscribeTheme();
      this.unsubscribeTheme = null;
    }
    if (this.unsubscribeLang !== null) {
      this.unsubscribeLang();
      this.unsubscribeLang = null;
    }
  }

  onUiStateChanged(): void {
    this.updateEffectiveTheme();
    this.effectiveLang = Lang.getInstance().getLanguage();
  }

  private updateEffectiveTheme(): void {
    this.effectiveTheme = ThemeManager.getInstance().resolveTheme(this.uiState.themeMode);
  }

  private getTheme(): Theme {
    return this.effectiveTheme;
  }

  private t(key: string, ...args: (string | number)[]): string {
    const langCode: SupportedLanguage = this.uiState.languageCode === 'zh' || this.effectiveLang === 'zh' ? 'zh' : 'en';
    return Lang.getInstance().formatByKey(key, langCode, args);
  }

  private getAvatarLetter(): string {
    const name: string = this.uiState.displayName.trim();
    if (name.length > 0) {
      return name.charAt(0).toUpperCase();
    }
    const username: string = this.uiState.username.trim();
    if (username.length > 0) {
      return username.charAt(0).toUpperCase();
    }
    return 'U';
  }

  private getAvatarColor(): string {
    const idx: number = Math.abs(this.uiState.userId) % AVATAR_PALETTE.length;
    return AVATAR_PALETTE[idx];
  }

  build() {
    Stack() {
      Column() {
        this.HeaderView()

        Scroll() {
          Column() {
            if (this.uiState.errorMessage !== null) {
              this.ErrorBannerView()
            }

            this.ProfileCardView()

            this.SectionTitle(this.t('NOTIFICATIONS'))
            this.NotificationsCardView()

            this.SectionTitle(this.t('DATA AND STORAGE'))
            this.StorageCardView()

            this.SectionTitle(this.t('APPEARANCE'))
            this.ThemeCardView()

            this.SectionTitle(this.t('LANGUAGE'))
            this.LanguageCardView()

            this.SectionTitle(this.t('ABOUT'))
            this.AboutCardView()

            this.LogoutSectionView()
          }
          .width('100%')
          .padding({
            left: this.getTheme().spacing.screenInset,
            right: this.getTheme().spacing.screenInset,
            bottom: this.getTheme().spacing.xxl
          })
        }
        .layoutWeight(1)
        .scrollBar(BarState.Off)
      }
      .width('100%')
      .height('100%')
      .backgroundColor(this.getTheme().colors.background)

      if (this.uiState.showLogoutConfirm) {
        this.LogoutConfirmDialog()
      }

      if (this.uiState.isLoading || this.uiState.isLoggingOut) {
        this.LoadingOverlayView()
      }
    }
    .width('100%')
    .height('100%')
  }

  @Builder
  HeaderView() {
    Row() {
      Text('‹')
        .fontSize(this.getTheme().typography.largeTitle.fontSize)
        .fontWeight(this.getTheme().typography.title.fontWeight)
        .fontColor(this.getTheme().colors.accent)
        .width(BACK_ARROW_SIZE)
        .height(BACK_ARROW_SIZE)
        .textAlign(TextAlign.Center)
        .onClick((): void => {
          this.onBack();
        })

      Text(this.t('Settings'))
        .fontSize(this.getTheme().typography.largeTitle.fontSize)
        .fontWeight(this.getTheme().typography.largeTitle.fontWeight)
        .fontColor(this.getTheme().colors.textPrimary)
    }
    .width('100%')
    .alignItems(VerticalAlign.Center)
    .padding({
      left: this.getTheme().spacing.screenInset,
      right: this.getTheme().spacing.screenInset,
      top: this.getTheme().spacing.lg,
      bottom: this.getTheme().spacing.md
    })
  }

  @Builder
  ErrorBannerView() {
    Row() {
      Text(this.uiState.errorMessage !== null ? this.uiState.errorMessage : '')
        .fontSize(this.getTheme().typography.footnote.fontSize)
        .fontColor(this.getTheme().colors.destructive)
        .layoutWeight(1)

      Button(this.t('Dismiss'))
        .fontSize(this.getTheme().typography.caption.fontSize)
        .fontColor(this.getTheme().colors.textPrimary)
        .backgroundColor(this.getTheme().colors.surface)
        .height(28)
        .onClick((): void => {
          this.onDispatch(new SetErrorMessage(null));
        })
    }
    .width('100%')
    .padding(this.getTheme().spacing.md)
    .margin({ bottom: this.getTheme().spacing.md })
    .backgroundColor(this.getTheme().colors.surface)
    .borderRadius(this.getTheme().radius.md)
  }

  @Builder
  ProfileCardView() {
    Row() {
      if (this.uiState.avatarLocalPath !== null && this.uiState.avatarLocalPath.length > 0) {
        Image(this.uiState.avatarLocalPath)
          .width(AVATAR_SIZE)
          .height(AVATAR_SIZE)
          .borderRadius(this.getTheme().radius.full)
          .margin({ right: this.getTheme().spacing.md })
      } else {
        Text(this.getAvatarLetter())
          .width(AVATAR_SIZE)
          .height(AVATAR_SIZE)
          .borderRadius(this.getTheme().radius.full)
          .backgroundColor(this.getAvatarColor())
          .fontColor(this.getTheme().colors.textOnAccent)
          .fontSize(this.getTheme().typography.title.fontSize)
          .fontWeight(this.getTheme().typography.title.fontWeight)
          .textAlign(TextAlign.Center)
          .margin({ right: this.getTheme().spacing.md })
      }

      Column() {
        Text(this.uiState.displayName.length > 0 ? this.uiState.displayName : this.t('Telegram User'))
          .fontSize(this.getTheme().typography.headline.fontSize)
          .fontWeight(this.getTheme().typography.headline.fontWeight)
          .fontColor(this.getTheme().colors.textPrimary)
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })

        if (this.uiState.username.length > 0) {
          Text(`@${this.uiState.username}`)
            .fontSize(this.getTheme().typography.subheadline.fontSize)
            .fontColor(this.getTheme().colors.textSecondary)
            .margin({ top: this.getTheme().spacing.xs })
        }

        if (this.uiState.phoneNumber.length > 0) {
          Text(this.uiState.phoneNumber)
            .fontSize(this.getTheme().typography.footnote.fontSize)
            .fontColor(this.getTheme().colors.textSecondary)
            .margin({ top: this.getTheme().spacing.xs })
        }

        if (this.uiState.bio.length > 0) {
          Text(this.uiState.bio)
            .fontSize(this.getTheme().typography.footnote.fontSize)
            .fontColor(this.getTheme().colors.textSecondary)
            .margin({ top: this.getTheme().spacing.xs })
            .maxLines(2)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
        }
      }
      .layoutWeight(1)
      .alignItems(HorizontalAlign.Start)
    }
    .width('100%')
    .padding(this.getTheme().spacing.md)
    .backgroundColor(this.getTheme().colors.surface)
    .borderRadius(this.getTheme().radius.lg)
    .margin({ bottom: this.getTheme().spacing.md })
  }

  @Builder
  SectionTitle(title: string) {
    Text(title)
      .fontSize(this.getTheme().typography.caption.fontSize)
      .fontWeight(this.getTheme().typography.caption.fontWeight)
      .fontColor(this.getTheme().colors.textSecondary)
      .margin({
        top: this.getTheme().spacing.md,
        bottom: this.getTheme().spacing.xs,
        left: this.getTheme().spacing.xs
      })
      .width('100%')
  }

  @Builder
  NotificationsCardView() {
    Row() {
      Text(this.t('Notifications'))
        .fontSize(this.getTheme().typography.body.fontSize)
        .fontColor(this.getTheme().colors.textPrimary)
        .layoutWeight(1)

      Toggle({ type: ToggleType.Switch, isOn: this.uiState.notificationsEnabled })
        .onChange((isOn: boolean): void => {
          if (isOn !== this.uiState.notificationsEnabled) {
            this.onDispatch(new ToggleNotifications());
          }
        })
    }
    .width('100%')
    .padding(this.getTheme().spacing.md)
    .backgroundColor(this.getTheme().colors.surface)
    .borderRadius(this.getTheme().radius.md)
  }

  @Builder
  StorageCardView() {
    Row() {
      Column() {
        Text(this.t('Storage & Cache'))
          .fontSize(this.getTheme().typography.body.fontSize)
          .fontColor(this.getTheme().colors.textPrimary)

        Text(this.t('Cache size: {0}', this.uiState.storageCacheSize))
          .fontSize(this.getTheme().typography.footnote.fontSize)
          .fontColor(this.getTheme().colors.textSecondary)
          .margin({ top: this.getTheme().spacing.xs })
      }
      .alignItems(HorizontalAlign.Start)
      .layoutWeight(1)

      Button(this.t('Clear'))
        .fontSize(this.getTheme().typography.subheadline.fontSize)
        .fontColor(this.getTheme().colors.accent)
        .backgroundColor(this.getTheme().colors.surfaceVariant)
        .height(32)
        .onClick((): void => {
          this.onDispatch(new ClearCacheRequested());
        })
    }
    .width('100%')
    .padding(this.getTheme().spacing.md)
    .backgroundColor(this.getTheme().colors.surface)
    .borderRadius(this.getTheme().radius.md)
  }

  private getThemeModeSummary(): string {
    if (this.uiState.themeMode === 'system') {
      const activeMode: string = this.getTheme().mode === 'dark' ? this.t('Dark') : this.t('Light');
      return `${this.t('System')} (${activeMode})`;
    }
    if (this.uiState.themeMode === 'dark') {
      return this.t('Dark');
    }
    return this.t('Light');
  }

  @Builder
  ThemeCardView() {
    Column() {
      Row() {
        Text(this.t('Theme Mode'))
          .fontSize(this.getTheme().typography.body.fontSize)
          .fontWeight(this.getTheme().typography.headline.fontWeight)
          .fontColor(this.getTheme().colors.textPrimary)
          .layoutWeight(1)

        Text(this.getThemeModeSummary())
          .fontSize(this.getTheme().typography.footnote.fontSize)
          .fontColor(this.getTheme().colors.textSecondary)
      }
      .width('100%')
      .alignItems(VerticalAlign.Center)
      .margin({ bottom: this.getTheme().spacing.sm })

      Row() {
        this.ThemeOption('system', this.t('System'))
        this.ThemeOption('light', this.t('Light'))
        this.ThemeOption('dark', this.t('Dark'))
      }
      .width('100%')
      .justifyContent(FlexAlign.SpaceBetween)
    }
    .width('100%')
    .padding(this.getTheme().spacing.md)
    .backgroundColor(this.getTheme().colors.surface)
    .borderRadius(this.getTheme().radius.md)
  }

  @Builder
  ThemeOption(mode: SettingsThemeMode, label: string) {
    Button(label)
      .layoutWeight(1)
      .height(36)
      .margin({
        left: mode === 'system' ? 0 : this.getTheme().spacing.xs,
        right: mode === 'dark' ? 0 : this.getTheme().spacing.xs
      })
      .fontSize(this.getTheme().typography.subheadline.fontSize)
      .fontWeight(
        this.uiState.themeMode === mode
          ? this.getTheme().typography.headline.fontWeight
          : this.getTheme().typography.subheadline.fontWeight
      )
      .fontColor(
        this.uiState.themeMode === mode
          ? this.getTheme().colors.textOnAccent
          : this.getTheme().colors.textPrimary
      )
      .backgroundColor(
        this.uiState.themeMode === mode
          ? this.getTheme().colors.accent
          : this.getTheme().colors.surfaceVariant
      )
      .borderRadius(this.getTheme().radius.md)
      .onClick((): void => {
        this.onDispatch(new ChangeThemeMode(mode));
      })
  }

  private getLanguageSummary(): string {
    if (this.uiState.languagePreference === 'system') {
      const activeLang: string = this.uiState.languageCode === 'zh' || this.effectiveLang === 'zh' ? '简体中文' : 'English';
      return `${this.t('Follow System')} (${activeLang})`;
    }
    if (this.uiState.languagePreference === 'zh') {
      return '简体中文';
    }
    return 'English';
  }

  @Builder
  LanguageCardView() {
    Column() {
      Row() {
        Text(this.t('Language'))
          .fontSize(this.getTheme().typography.body.fontSize)
          .fontWeight(this.getTheme().typography.headline.fontWeight)
          .fontColor(this.getTheme().colors.textPrimary)
          .layoutWeight(1)

        Text(this.getLanguageSummary())
          .fontSize(this.getTheme().typography.footnote.fontSize)
          .fontColor(this.getTheme().colors.textSecondary)
      }
      .width('100%')
      .alignItems(VerticalAlign.Center)
      .margin({ bottom: this.getTheme().spacing.sm })

      Row() {
        this.LanguageOption('system', this.t('System'))
        this.LanguageOption('en', 'English')
        this.LanguageOption('zh', '简体中文')
      }
      .width('100%')
      .justifyContent(FlexAlign.SpaceBetween)
    }
    .width('100%')
    .padding(this.getTheme().spacing.md)
    .backgroundColor(this.getTheme().colors.surface)
    .borderRadius(this.getTheme().radius.md)
  }

  @Builder
  LanguageOption(mode: LanguagePreference, label: string) {
    Button(label)
      .layoutWeight(1)
      .height(36)
      .margin({
        left: mode === 'system' ? 0 : this.getTheme().spacing.xs,
        right: mode === 'zh' ? 0 : this.getTheme().spacing.xs
      })
      .fontSize(this.getTheme().typography.subheadline.fontSize)
      .fontWeight(
        this.uiState.languagePreference === mode
          ? this.getTheme().typography.headline.fontWeight
          : this.getTheme().typography.subheadline.fontWeight
      )
      .fontColor(
        this.uiState.languagePreference === mode
          ? this.getTheme().colors.textOnAccent
          : this.getTheme().colors.textPrimary
      )
      .backgroundColor(
        this.uiState.languagePreference === mode
          ? this.getTheme().colors.accent
          : this.getTheme().colors.surfaceVariant
      )
      .borderRadius(this.getTheme().radius.md)
      .onClick((): void => {
        this.onDispatch(new ChangeLanguage(mode));
      })
  }

  @Builder
  AboutCardView() {
    Row() {
      Text(this.t('App Version'))
        .fontSize(this.getTheme().typography.body.fontSize)
        .fontColor(this.getTheme().colors.textPrimary)
        .layoutWeight(1)

      Text(`v${this.uiState.appVersion}`)
        .fontSize(this.getTheme().typography.footnote.fontSize)
        .fontColor(this.getTheme().colors.textSecondary)
    }
    .width('100%')
    .padding(this.getTheme().spacing.md)
    .backgroundColor(this.getTheme().colors.surface)
    .borderRadius(this.getTheme().radius.md)
  }

  @Builder
  LogoutSectionView() {
    Button(this.t('Log Out'))
      .width('100%')
      .height(48)
      .margin({ top: this.getTheme().spacing.xl })
      .fontSize(this.getTheme().typography.headline.fontSize)
      .fontWeight(this.getTheme().typography.headline.fontWeight)
      .fontColor(this.getTheme().colors.destructive)
      .backgroundColor(this.getTheme().colors.surface)
      .borderRadius(this.getTheme().radius.md)
      .onClick((): void => {
        this.onDispatch(new RequestLogout());
      })
  }

  @Builder
  LogoutConfirmDialog() {
    Stack({ alignContent: Alignment.Center }) {
      Column()
        .width('100%')
        .height('100%')
        .backgroundColor('#66000000')
        .onClick((): void => {
          this.onDispatch(new CancelLogout());
        })

      Column() {
        Text(this.t('Log Out'))
          .fontSize(this.getTheme().typography.title.fontSize)
          .fontWeight(this.getTheme().typography.title.fontWeight)
          .fontColor(this.getTheme().colors.textPrimary)
          .margin({ bottom: this.getTheme().spacing.sm })

        Text(this.t('Are you sure you want to log out from this account?'))
          .fontSize(this.getTheme().typography.body.fontSize)
          .fontColor(this.getTheme().colors.textSecondary)
          .textAlign(TextAlign.Center)
          .margin({ bottom: this.getTheme().spacing.lg })

        Row() {
          Button(this.t('Cancel'))
            .layoutWeight(1)
            .height(40)
            .margin({ right: this.getTheme().spacing.sm })
            .fontSize(this.getTheme().typography.body.fontSize)
            .fontColor(this.getTheme().colors.textPrimary)
            .backgroundColor(this.getTheme().colors.surfaceVariant)
            .borderRadius(this.getTheme().radius.md)
            .onClick((): void => {
              this.onDispatch(new CancelLogout());
            })

          Button(this.t('Log Out'))
            .layoutWeight(1)
            .height(40)
            .margin({ left: this.getTheme().spacing.sm })
            .fontSize(this.getTheme().typography.body.fontSize)
            .fontColor(this.getTheme().colors.textOnAccent)
            .backgroundColor(this.getTheme().colors.destructive)
            .borderRadius(this.getTheme().radius.md)
            .onClick((): void => {
              this.onDispatch(new ConfirmLogout());
            })
        }
        .width('100%')
      }
      .width('82%')
      .padding(this.getTheme().spacing.lg)
      .backgroundColor(this.getTheme().colors.surface)
      .borderRadius(this.getTheme().radius.lg)
    }
    .width('100%')
    .height('100%')
  }

  @Builder
  LoadingOverlayView() {
    Stack({ alignContent: Alignment.Center }) {
      Column()
        .width('100%')
        .height('100%')
        .backgroundColor('#44000000')

      Column() {
        LoadingProgress()
          .width(44)
          .height(44)
          .color(this.getTheme().colors.accent)
          .margin({ bottom: this.getTheme().spacing.sm })

        Text(this.uiState.isLoggingOut ? this.t('Logging out...') : this.t('Loading...'))
          .fontSize(this.getTheme().typography.subheadline.fontSize)
          .fontColor(this.getTheme().colors.textPrimary)
      }
      .padding(this.getTheme().spacing.lg)
      .backgroundColor(this.getTheme().colors.surface)
      .borderRadius(this.getTheme().radius.md)
    }
    .width('100%')
    .height('100%')
  }
}
