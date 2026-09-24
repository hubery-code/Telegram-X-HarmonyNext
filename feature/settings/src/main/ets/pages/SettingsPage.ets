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

import {
  DarkTheme,
  LightTheme,
  Theme,
  ThemeManager,
  CHAT_FONT_SIZE_STEPS,
  chatFontSizeAt,
  chatFontSizeIndex,
  chatTextSizeOf
} from '@tgx/core-design-system';
import { Lang, LanguagePreference, SupportedLanguage } from '@tgx/core-common';
import { SettingsThemeMode, SettingsUiState } from '../contract/SettingsUiState';
import {
  CancelLogout,
  ChangeChatFontSize,
  ChangeLanguage,
  ChangeThemeMode,
  ClearCacheRequested,
  CloseAccountSwitcher,
  CloseDevicesPage,
  ConfirmLogout,
  OpenAccountSwitcher,
  OpenDevicesPage,
  RequestAddAccount,
  RequestLogout,
  SetErrorMessage,
  SettingsIntent,
  SwitchAccount,
  ToggleNotificationScope,
  ToggleNotifications,
  ClosePrivacyPage,
  OpenPrivacyPage,
  CloseProxyPage,
  LoadProxies,
  OpenProxyPage
} from '../contract/SettingsIntent';
import { NotificationScopeKey } from '../model/NotificationSettings';
import {
  PrivacyChoice,
  PrivacySettingItem,
  PrivacySettingKey,
  privacyChoiceLabel
} from '../model/PrivacySettings';
import { proxyRowSummary } from '../model/ProxySettings';
import { SettingsCardKey, sectionShowsCard, settingsSectionTitleKey } from '../model/SettingsSection';
import { DevicesSubPage } from './DevicesSubPage';
import { PrivacySubPage } from './PrivacySubPage';
import { ProxySubPage } from './ProxySubPage';

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
    // 「代理」行的副标题要能区分「没配代理」和「配了但停用」，所以进页面就读一次列表；
    // 不进 reducer 初始状态是因为只有这一行用它，别让通知/存储分区也背上一个请求。
    this.onDispatch(new LoadProxies());
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

  /** SELF-101：分区直达时只渲染该分区的卡片块（'all' 即全量）。 */
  private showsCard(card: SettingsCardKey): boolean {
    return sectionShowsCard(this.uiState.section, card);
  }

  /** 分区页的标题已经是分区名，不再重复渲染分区小标题。 */
  private showsSectionTitle(): boolean {
    return this.uiState.section === 'all';
  }

  private getAccountsList(): string[] {
    const list: string[] = [];
    for (let i = 0; i < this.uiState.availableAccounts.length; i++) {
      list.push(this.uiState.availableAccounts[i]);
    }
    return list;
  }

  /** SELF-102：卡片副标题预览「最后上线时间」当前档位（未加载时为 unknown）。 */
  private privacyChoiceOf(key: PrivacySettingKey): PrivacyChoice {
    const items: readonly PrivacySettingItem[] = this.uiState.privacyItems;
    for (let i = 0; i < items.length; i++) {
      if (items[i].key === key) {
        return items[i].choice;
      }
    }
    return 'unknown';
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

            if (this.showsCard('profile')) {
              this.ProfileCardView()
            }

            if (this.showsCard('notifications')) {
              if (this.showsSectionTitle()) {
                this.SectionTitle(this.t('NOTIFICATIONS'))
              }
              this.NotificationsCardView()
            }

            if (this.showsCard('devices')) {
              if (this.showsSectionTitle()) {
                this.SectionTitle(this.t('DEVICES'))
              }
              this.DevicesCardView()
            }

            if (this.showsCard('privacy')) {
              if (this.showsSectionTitle()) {
                this.SectionTitle(this.t('PRIVACY'))
              }
              this.PrivacyCardView()
            }

            if (this.showsCard('storage') || this.showsCard('proxy')) {
              if (this.showsSectionTitle()) {
                this.SectionTitle(this.t('DATA AND STORAGE'))
              }
              if (this.showsCard('storage')) {
                this.StorageCardView()
              }
              if (this.showsCard('proxy')) {
                Column() {
                  this.ProxyCardView()
                }
                .margin({ top: this.getTheme().spacing.md })
              }
            }

            if (this.showsCard('appearance')) {
              this.SectionTitle(this.t('APPEARANCE'))
              this.ThemeCardView()
              this.ChatFontSizeCardView()
            }

            if (this.showsCard('language')) {
              this.SectionTitle(this.t('LANGUAGE'))
              this.LanguageCardView()
            }

            if (this.showsCard('about')) {
              this.SectionTitle(this.t('ABOUT'))
              this.AboutCardView()
            }

            if (this.showsCard('logout')) {
              this.LogoutSectionView()
            }
          }
          .width('100%')
          .padding({
            left: this.getTheme().spacing.screenInset,
            right: this.getTheme().spacing.screenInset,
            bottom: this.getTheme().spacing.xxl
          })
        }
        .layoutWeight(1)
        .align(Alignment.TopStart)
        .scrollBar(BarState.Off)
      }
      .width('100%')
      .height('100%')
      .backgroundColor(this.getTheme().colors.background)

      if (this.uiState.showAccountSwitcher) {
        this.AccountSwitcherDialog()
      }

      if (this.uiState.showLogoutConfirm) {
        this.LogoutConfirmDialog()
      }

      if (this.uiState.showDevicesPage) {
        DevicesSubPage({
          uiState: this.uiState,
          onDispatch: this.onDispatch,
          onBack: (): void => {
            this.onDispatch(new CloseDevicesPage());
          }
        })
      }

      if (this.uiState.showPrivacyPage) {
        PrivacySubPage({
          uiState: this.uiState,
          onDispatch: this.onDispatch,
          onBack: (): void => {
            this.onDispatch(new ClosePrivacyPage());
          }
        })
      }

      if (this.uiState.showProxyPage) {
        ProxySubPage({
          uiState: this.uiState,
          onDispatch: this.onDispatch,
          onBack: (): void => {
            this.onDispatch(new CloseProxyPage());
          }
        })
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
      Image($r('app.media.ic_back'))
        .width(24)
        .height(24)
        .fillColor(this.getTheme().colors.accent)
        .margin({ right: this.getTheme().spacing.md })
        .onClick((): void => {
          this.onBack();
        })

      Text(this.t(settingsSectionTitleKey(this.uiState.section)))
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
        Row() {
          Text(this.uiState.displayName.length > 0 ? this.uiState.displayName : this.t('Telegram User'))
            .fontSize(this.getTheme().typography.headline.fontSize)
            .fontWeight(this.getTheme().typography.headline.fontWeight)
            .fontColor(this.getTheme().colors.textPrimary)
            .maxLines(1)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
            .layoutWeight(1)

          if (this.uiState.currentAccountKey.length > 0) {
            Text(this.uiState.currentAccountKey)
              .fontSize(this.getTheme().typography.caption.fontSize)
              .fontColor(this.getTheme().colors.accent)
              .backgroundColor(this.getTheme().colors.surfaceVariant)
              .padding({
                left: this.getTheme().spacing.xs,
                right: this.getTheme().spacing.xs,
                top: this.getTheme().spacing.hairline,
                bottom: this.getTheme().spacing.hairline
              })
              .borderRadius(this.getTheme().radius.sm)
              .margin({ left: this.getTheme().spacing.xs })
          }
        }
        .width('100%')
        .alignItems(VerticalAlign.Center)

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

      // Account switch indicator
      Row() {
        Image($r('app.media.ic_chevron_down'))
          .width(18)
          .height(18)
          .fillColor(this.getTheme().colors.textSecondary)
          .margin({ left: this.getTheme().spacing.sm })
      }
      .alignItems(VerticalAlign.Center)
    }
    .width('100%')
    .padding(this.getTheme().spacing.md)
    .backgroundColor(this.getTheme().colors.surface)
    .borderRadius(this.getTheme().radius.lg)
    .margin({ bottom: this.getTheme().spacing.md })
    .onClick((): void => {
      this.onDispatch(new OpenAccountSwitcher());
    })
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
    Column() {
      Row() {
        Image($r('app.media.ic_notifications'))
          .width(22)
          .height(22)
          .fillColor(this.getTheme().colors.accent)
          .margin({ right: this.getTheme().spacing.sm })

        Text(this.t('All Notifications'))
          .fontSize(this.getTheme().typography.body.fontSize)
          .fontWeight(this.getTheme().typography.headline.fontWeight)
          .fontColor(this.getTheme().colors.textPrimary)
          .layoutWeight(1)

        Toggle({ type: ToggleType.Switch, isOn: this.uiState.notificationsEnabled })
          .enabled(!this.uiState.isUpdatingNotifications && this.uiState.updatingNotificationScope === null)
          .onChange((isOn: boolean): void => {
            if (isOn !== this.uiState.notificationsEnabled) {
              this.onDispatch(new ToggleNotifications());
            }
          })
      }
      .width('100%')
      .alignItems(VerticalAlign.Center)

      Divider()
        .color(this.getTheme().colors.divider)
        .margin({ top: this.getTheme().spacing.sm, bottom: this.getTheme().spacing.xs })

      this.NotificationScopeRow('Private Chats', 'private')
      this.NotificationScopeRow('Group Chats', 'group')
      this.NotificationScopeRow('Channels', 'channel')
    }
    .width('100%')
    .padding(this.getTheme().spacing.md)
    .backgroundColor(this.getTheme().colors.surface)
    .borderRadius(this.getTheme().radius.md)
  }

  /**
   * 分区开关是否开启。
   * 必须在 builder 内部读 this.uiState：@Builder 的按值入参不参与状态观察，
   * 开关点完后行内文案与 Toggle 不会重渲染（SET-106 首版即因此显示恒为关闭）。
   */
  private scopeNotificationsEnabled(scope: NotificationScopeKey): boolean {
    if (scope === 'private') {
      return this.uiState.privateNotificationsEnabled;
    }
    if (scope === 'group') {
      return this.uiState.groupNotificationsEnabled;
    }
    return this.uiState.channelNotificationsEnabled;
  }

  @Builder
  NotificationScopeRow(labelKey: string, scope: NotificationScopeKey) {
    Row() {
      Text(this.t(labelKey))
        .fontSize(this.getTheme().typography.subheadline.fontSize)
        .fontColor(this.getTheme().colors.textPrimary)
        .layoutWeight(1)

      Toggle({ type: ToggleType.Switch, isOn: this.scopeNotificationsEnabled(scope) })
        .enabled(!this.uiState.isUpdatingNotifications && this.uiState.updatingNotificationScope === null)
        .onChange((isOn: boolean): void => {
          if (isOn !== this.scopeNotificationsEnabled(scope)) {
            this.onDispatch(new ToggleNotificationScope(scope));
          }
        })
    }
    .width('100%')
    .height(40)
    .alignItems(VerticalAlign.Center)
  }

  @Builder
  DevicesCardView() {
    Row() {
      Image($r('app.media.ic_devices'))
        .width(22)
        .height(22)
        .fillColor(this.getTheme().colors.accent)
        .margin({ right: this.getTheme().spacing.sm })

      Column() {
        Text(this.t('Devices'))
          .fontSize(this.getTheme().typography.body.fontSize)
          .fontColor(this.getTheme().colors.textPrimary)

        Text(this.uiState.activeSessions.length > 0
          ? `${this.uiState.activeSessions.length} active sessions`
          : this.t('Active Sessions'))
          .fontSize(this.getTheme().typography.footnote.fontSize)
          .fontColor(this.getTheme().colors.textSecondary)
          .margin({ top: this.getTheme().spacing.xs })
      }
      .alignItems(HorizontalAlign.Start)
      .layoutWeight(1)

      Image($r('app.media.ic_chevron_right'))
        .width(18)
        .height(18)
        .fillColor(this.getTheme().colors.textSecondary)
    }
    .width('100%')
    .padding(this.getTheme().spacing.md)
    .backgroundColor(this.getTheme().colors.surface)
    .borderRadius(this.getTheme().radius.md)
    .onClick((): void => {
      this.onDispatch(new OpenDevicesPage());
    })
  }

  @Builder
  PrivacyCardView() {
    Row() {
      Image($r('app.media.ic_lock'))
        .width(22)
        .height(22)
        .fillColor(this.getTheme().colors.accent)
        .margin({ right: this.getTheme().spacing.sm })

      Column() {
        Text(this.t('Privacy & Security'))
          .fontSize(this.getTheme().typography.body.fontSize)
          .fontColor(this.getTheme().colors.textPrimary)

        Text(this.uiState.privacyItems.length > 0
          ? `${this.t('Last Seen')}: ${this.t(privacyChoiceLabel(this.privacyChoiceOf('show_last_seen')))}`
          : this.t('Tap a row to change who can see it.'))
          .fontSize(this.getTheme().typography.footnote.fontSize)
          .fontColor(this.getTheme().colors.textSecondary)
          .margin({ top: this.getTheme().spacing.xs })
      }
      .alignItems(HorizontalAlign.Start)
      .layoutWeight(1)

      Image($r('app.media.ic_chevron_right'))
        .width(18)
        .height(18)
        .fillColor(this.getTheme().colors.textSecondary)
    }
    .width('100%')
    .padding(this.getTheme().spacing.md)
    .backgroundColor(this.getTheme().colors.surface)
    .borderRadius(this.getTheme().radius.md)
    .onClick((): void => {
      this.onDispatch(new OpenPrivacyPage());
    })
  }

  /** PROXY-101：TGX 的「代理」行落在数据与存储分区，副标题即当前启用态。 */
  @Builder
  ProxyCardView() {
    Row() {
      Image($r('app.media.ic_link'))
        .width(22)
        .height(22)
        .fillColor(this.getTheme().colors.accent)
        .margin({ right: this.getTheme().spacing.sm })

      Column() {
        Text(this.t('Proxies'))
          .fontSize(this.getTheme().typography.body.fontSize)
          .fontColor(this.getTheme().colors.textPrimary)

        // 读回来之前不说「点按设置」：那一刻「没配代理」和「还没查到」是两回事。
        Text(this.uiState.isLoadingProxies && this.uiState.proxyItems.length === 0
          ? this.t('Loading...')
          : this.t(proxyRowSummary(this.uiState.proxyItems)))
          .fontSize(this.getTheme().typography.footnote.fontSize)
          .fontColor(this.getTheme().colors.textSecondary)
          .margin({ top: this.getTheme().spacing.xs })
      }
      .alignItems(HorizontalAlign.Start)
      .layoutWeight(1)

      Image($r('app.media.ic_chevron_right'))
        .width(18)
        .height(18)
        .fillColor(this.getTheme().colors.textSecondary)
    }
    .width('100%')
    .padding(this.getTheme().spacing.md)
    .backgroundColor(this.getTheme().colors.surface)
    .borderRadius(this.getTheme().radius.md)
    .onClick((): void => {
      this.onDispatch(new OpenProxyPage());
    })
  }

  @Builder
  StorageCardView() {
    Row() {
      Image($r('app.media.ic_storage'))
        .width(22)
        .height(22)
        .fillColor(this.getTheme().colors.accent)
        .margin({ right: this.getTheme().spacing.sm })

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
        Image($r('app.media.ic_palette'))
          .width(22)
          .height(22)
          .fillColor(this.getTheme().colors.accent)
          .margin({ right: this.getTheme().spacing.sm })

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

  /** FEAT-UI-002 / SET-105：当前字号档位下标（滑块 0..N-1）。 */
  private chatFontStepIndex(): number {
    return chatFontSizeIndex(this.uiState.chatFontSize);
  }

  /** 当前档位对应的字号（sp），用于卡片右上角读数。 */
  private chatFontStepValue(): number {
    return chatFontSizeAt(this.chatFontStepIndex());
  }

  /**
   * FEAT-UI-002 / SET-105：聊天字号卡片。
   *
   * 档位与 TGX `Settings.CHAT_FONT_SIZES` 逐值对齐（12–26，默认 15）。滑块用
   * **档位下标**驱动而非字号本身——档位是非等距的（…14,15,16,18,20…），下标
   * 才是线性量。下方预览行复用消息区的 `chatTextSizeOf`，与聊天页所见一致。
   */
  @Builder
  ChatFontSizeCardView() {
    Column() {
      Row() {
        Image($r('app.media.ic_text_size'))
          .width(22)
          .height(22)
          .fillColor(this.getTheme().colors.accent)
          .margin({ right: this.getTheme().spacing.sm })

        Text(this.t('Chat Text Size'))
          .fontSize(this.getTheme().typography.body.fontSize)
          .fontWeight(this.getTheme().typography.headline.fontWeight)
          .fontColor(this.getTheme().colors.textPrimary)
          .layoutWeight(1)

        Text(`${this.chatFontStepValue()}`)
          .fontSize(this.getTheme().typography.footnote.fontSize)
          .fontColor(this.getTheme().colors.textSecondary)
      }
      .width('100%')
      .alignItems(VerticalAlign.Center)

      Row() {
        Text('A')
          .fontSize(this.getTheme().typography.caption.fontSize)
          .fontColor(this.getTheme().colors.textSecondary)
          .margin({ right: this.getTheme().spacing.xs })

        Slider({
          value: this.chatFontStepIndex(),
          min: 0,
          max: CHAT_FONT_SIZE_STEPS.length - 1,
          step: 1,
          style: SliderStyle.OutSet
        })
          .layoutWeight(1)
          .selectedColor(this.getTheme().colors.accent)
          .trackColor(this.getTheme().colors.surfaceVariant)
          .onChange((value: number, mode: SliderChangeMode): void => {
            // reducer 对「同一档位」幂等，拖动过程中每帧派发是安全的。
            this.onDispatch(new ChangeChatFontSize(chatFontSizeAt(Math.round(value))));
          })

        Text('A')
          .fontSize(this.getTheme().typography.headline.fontSize)
          .fontColor(this.getTheme().colors.textSecondary)
          .margin({ left: this.getTheme().spacing.xs })
      }
      .width('100%')
      .alignItems(VerticalAlign.Center)
      .margin({ top: this.getTheme().spacing.xs })

      Column() {
        Text(this.t('This is how your messages will look.'))
          .fontSize(chatTextSizeOf(
            this.getTheme().typography.body.fontSize,
            this.uiState.chatFontSize
          ))
          .fontColor(this.getTheme().colors.chatText)
          .lineHeight(chatTextSizeOf(
            this.getTheme().typography.body.fontSize,
            this.uiState.chatFontSize
          ) * 1.35)
      }
      .width('100%')
      .alignItems(HorizontalAlign.Start)
      .padding(this.getTheme().spacing.sm)
      .backgroundColor(this.getTheme().colors.surfaceVariant)
      .borderRadius(this.getTheme().radius.md)
      .margin({ top: this.getTheme().spacing.sm })
    }
    .width('100%')
    .padding(this.getTheme().spacing.md)
    .backgroundColor(this.getTheme().colors.surface)
    .borderRadius(this.getTheme().radius.md)
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
        Image($r('app.media.ic_language'))
          .width(22)
          .height(22)
          .fillColor(this.getTheme().colors.accent)
          .margin({ right: this.getTheme().spacing.sm })

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
      Image($r('app.media.ic_help_outline'))
        .width(22)
        .height(22)
        .fillColor(this.getTheme().colors.accent)
        .margin({ right: this.getTheme().spacing.sm })

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
    Button() {
      Row() {
        Image($r('app.media.ic_logout'))
          .width(20)
          .height(20)
          .fillColor(this.getTheme().colors.destructive)
          .margin({ right: this.getTheme().spacing.xs })

        Text(this.t('Log Out'))
          .fontSize(this.getTheme().typography.headline.fontSize)
          .fontWeight(this.getTheme().typography.headline.fontWeight)
          .fontColor(this.getTheme().colors.destructive)
      }
      .justifyContent(FlexAlign.Center)
      .alignItems(VerticalAlign.Center)
    }
    .width('100%')
    .height(48)
    .margin({ top: this.getTheme().spacing.xl })
    .backgroundColor(this.getTheme().colors.surface)
    .borderRadius(this.getTheme().radius.md)
    .onClick((): void => {
      this.onDispatch(new RequestLogout());
    })
  }

  @Builder
  AccountSwitcherDialog() {
    Stack({ alignContent: Alignment.Center }) {
      Column()
        .width('100%')
        .height('100%')
        .backgroundColor(this.getTheme().colors.scrim)
        .onClick((): void => {
          this.onDispatch(new CloseAccountSwitcher());
        })

      Column() {
        Row() {
          Text(this.t('Switch Account'))
            .fontSize(this.getTheme().typography.title.fontSize)
            .fontWeight(this.getTheme().typography.title.fontWeight)
            .fontColor(this.getTheme().colors.textPrimary)
            .layoutWeight(1)

          Button(this.t('Close'))
            .fontSize(this.getTheme().typography.subheadline.fontSize)
            .fontColor(this.getTheme().colors.textSecondary)
            .backgroundColor(this.getTheme().colors.surface)
            .height(32)
            .onClick((): void => {
              this.onDispatch(new CloseAccountSwitcher());
            })
        }
        .width('100%')
        .alignItems(VerticalAlign.Center)
        .margin({ bottom: this.getTheme().spacing.md })

        List() {
          ForEach(this.getAccountsList(), (accountKey: string) => {
            ListItem() {
              Row() {
                Text(accountKey.length > 0 ? accountKey.charAt(0).toUpperCase() : 'A')
                  .width(36)
                  .height(36)
                  .borderRadius(this.getTheme().radius.full)
                  .backgroundColor(accountKey === this.uiState.currentAccountKey ? this.getTheme().colors.accent : this.getTheme().colors.surfaceVariant)
                  .fontColor(accountKey === this.uiState.currentAccountKey ? this.getTheme().colors.textOnAccent : this.getTheme().colors.textPrimary)
                  .fontSize(this.getTheme().typography.headline.fontSize)
                  .fontWeight(this.getTheme().typography.headline.fontWeight)
                  .textAlign(TextAlign.Center)
                  .margin({ right: this.getTheme().spacing.sm })

                Column() {
                  Text(accountKey)
                    .fontSize(this.getTheme().typography.body.fontSize)
                    .fontWeight(accountKey === this.uiState.currentAccountKey ? this.getTheme().typography.headline.fontWeight : this.getTheme().typography.body.fontWeight)
                    .fontColor(this.getTheme().colors.textPrimary)

                  if (accountKey === this.uiState.currentAccountKey) {
                    Text(this.t('Active'))
                      .fontSize(this.getTheme().typography.caption.fontSize)
                      .fontColor(this.getTheme().colors.accent)
                  }
                }
                .layoutWeight(1)
                .alignItems(HorizontalAlign.Start)

                if (accountKey === this.uiState.currentAccountKey) {
                  Image($r('app.media.ic_check_single'))
                    .width(20)
                    .height(20)
                    .fillColor(this.getTheme().colors.accent)
                }
              }
              .width('100%')
              .padding({
                top: this.getTheme().spacing.sm,
                bottom: this.getTheme().spacing.sm,
                left: this.getTheme().spacing.sm,
                right: this.getTheme().spacing.sm
              })
              .backgroundColor(accountKey === this.uiState.currentAccountKey ? this.getTheme().colors.surfaceVariant : this.getTheme().colors.surface)
              .borderRadius(this.getTheme().radius.md)
              .onClick((): void => {
                if (accountKey !== this.uiState.currentAccountKey) {
                  this.onDispatch(new SwitchAccount(accountKey));
                } else {
                  this.onDispatch(new CloseAccountSwitcher());
                }
              })
            }
            .margin({ bottom: this.getTheme().spacing.xs })
          })
        }
        .width('100%')
        .constraintSize({ maxHeight: 240 })

        Button() {
          Row() {
            Image($r('app.media.ic_add'))
              .width(18)
              .height(18)
              .fillColor(this.getTheme().colors.accent)
              .margin({ right: this.getTheme().spacing.xs })

            Text(this.t('Add Account'))
              .fontSize(this.getTheme().typography.headline.fontSize)
              .fontWeight(this.getTheme().typography.headline.fontWeight)
              .fontColor(this.getTheme().colors.accent)
          }
          .justifyContent(FlexAlign.Center)
          .alignItems(VerticalAlign.Center)
        }
        .width('100%')
        .height(44)
        .margin({ top: this.getTheme().spacing.md })
        .backgroundColor(this.getTheme().colors.surfaceVariant)
        .borderRadius(this.getTheme().radius.md)
        .onClick((): void => {
          this.onDispatch(new RequestAddAccount());
        })
      }
      .width('88%')
      .padding(this.getTheme().spacing.lg)
      .backgroundColor(this.getTheme().colors.surface)
      .borderRadius(this.getTheme().radius.lg)
    }
    .width('100%')
    .height('100%')
  }

  @Builder
  LogoutConfirmDialog() {
    Stack({ alignContent: Alignment.Center }) {
      Column()
        .width('100%')
        .height('100%')
        .backgroundColor(this.getTheme().colors.scrim)
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
