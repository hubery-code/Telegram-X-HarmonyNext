/**
 * feature/settings — 设置页可观察状态（SET-101）。
 *
 * 遵循计划 §5.11 / UI-003：
 * - 纯 ArkTS 契约层；
 * - 所有字段只读，不可变状态经 copyWith 派生；
 * - 严禁匿名对象字面量传参，提供明确的 SettingsUiStateOptions 接口。
 */

import { UiState } from '@tgx/feature-template';
import { ThemePreference, CHAT_FONT_SIZE_DEFAULT } from '@tgx/core-design-system';
import { LanguagePreference } from '@tgx/core-common';
import { NotificationScopeKey } from '../model/NotificationSettings';
import { ActiveSessionItem } from '../model/ActiveSessionItem';
import { SettingsSectionKey } from '../model/SettingsSection';
import { PrivacySettingItem, PrivacySettingKey } from '../model/PrivacySettings';
import { ProxyItem, ProxyConnectionState } from '../model/ProxySettings';
import { AutoDownloadPolicy, DataSaverSettings, DownloadLimitsByNetwork } from '@tgx/core-domain';

export type SettingsThemeMode = ThemePreference;

export interface SettingsUiStateOptions {
  readonly userId?: number;
  readonly displayName?: string;
  readonly username?: string;
  readonly phoneNumber?: string;
  readonly avatarLocalPath?: string | null;
  readonly bio?: string;
  readonly notificationsEnabled?: boolean;
  readonly privateNotificationsEnabled?: boolean;
  readonly groupNotificationsEnabled?: boolean;
  readonly channelNotificationsEnabled?: boolean;
  readonly isUpdatingNotifications?: boolean;
  readonly updatingNotificationScope?: NotificationScopeKey | null;
  readonly storageCacheSize?: string;
  readonly languageCode?: string;
  readonly languagePreference?: LanguagePreference;
  readonly themeMode?: SettingsThemeMode;
  readonly appVersion?: string;
  readonly isLoading?: boolean;
  readonly isLoggingOut?: boolean;
  readonly errorMessage?: string | null;
  readonly showLogoutConfirm?: boolean;
  readonly availableAccounts?: readonly string[];
  readonly currentAccountKey?: string;
  readonly showAccountSwitcher?: boolean;
  /** FEAT-P2-008：是否展示活跃设备页面。 */
  readonly showDevicesPage?: boolean;
  /** FEAT-P2-008：活跃设备/会话列表。 */
  readonly activeSessions?: readonly ActiveSessionItem[];
  /** FEAT-P2-008：是否正在加载会话列表。 */
  readonly isLoadingSessions?: boolean;
  /** FEAT-UI-002 / SET-105：聊天消息字号（sp，合法档位）。 */
  readonly chatFontSize?: number;
  /** SELF-101：分区直达时的可见分区；缺省 'all' 即完整设置页。 */
  readonly section?: SettingsSectionKey;
  /** SELF-102：是否展示「隐私和安全」子页。 */
  readonly showPrivacyPage?: boolean;
  /** SELF-102：隐私规则列表（TDLib userPrivacySettingRules 的页面投影）。 */
  readonly privacyItems?: readonly PrivacySettingItem[];
  /** SELF-102：是否正在读取隐私规则。 */
  readonly isLoadingPrivacy?: boolean;
  /** SELF-102：正在写回的隐私项；null 表示空闲。 */
  readonly updatingPrivacyKey?: PrivacySettingKey | null;
  /** PROXY-101：是否展示「代理」子页。 */
  readonly showProxyPage?: boolean;
  /** PROXY-101：已添加的代理列表（TDLib addedProxies 的页面投影）。 */
  readonly proxyItems?: ProxyItem[];
  /** PROXY-101：是否正在读取代理列表。 */
  readonly isLoadingProxies?: boolean;
  /** PROXY-101：正在写回的代理 id；null 表示空闲，0 是「不使用代理」行。 */
  readonly updatingProxyId?: number | null;
  /** AUTODL-101：是否展示「自动媒体下载」子页。 */
  readonly showAutoDownloadPage?: boolean;
  /** AUTODL-101：已读到的自动下载策略；null 表示还没读盘（行副标题显 Loading）。 */
  readonly autoDownloadPolicy?: AutoDownloadPolicy | null;
  /** AUTODL-102：省流量设置；null 表示还没读盘（此时行上按默认档显示）。 */
  readonly dataSaverSettings?: DataSaverSettings | null;
  /** AUTODL-103：按网络档的自动下载限制；null 表示还没读盘（三行副标题显 Loading）。 */
  readonly downloadLimits?: DownloadLimitsByNetwork | null;
  /**
   * PROXY-102：各行连通性探测结果（毫秒或模型层哨兵）。
   * key 是 TDLib 代理 id，`PROXY_NONE_ID`（0）是「不使用代理」行的直连探测。
   * 刻意不放进 `ProxyItem`：列表每次写回都要重读 `getProxies` 并整批重建行，
   * 挂在行上的在途探测会被那次重建抹掉。
   */
  readonly proxyPingMs?: Map<number, number>;
  /** PROXY-102：TDLib 连接态；'unknown' 表示还没收到 `updateConnectionState`。 */
  readonly proxyConnection?: ProxyConnectionState;
}

export class SettingsUiState implements UiState {
  readonly userId: number;
  readonly displayName: string;
  readonly username: string;
  readonly phoneNumber: string;
  readonly avatarLocalPath: string | null;
  readonly bio: string;

  readonly notificationsEnabled: boolean;
  readonly privateNotificationsEnabled: boolean;
  readonly groupNotificationsEnabled: boolean;
  readonly channelNotificationsEnabled: boolean;
  readonly isUpdatingNotifications: boolean;
  readonly updatingNotificationScope: NotificationScopeKey | null;
  readonly storageCacheSize: string;
  readonly languageCode: string;
  readonly languagePreference: LanguagePreference;
  readonly themeMode: SettingsThemeMode;
  readonly appVersion: string;

  readonly isLoading: boolean;
  readonly isLoggingOut: boolean;
  readonly errorMessage: string | null;
  readonly showLogoutConfirm: boolean;

  readonly availableAccounts: readonly string[];
  readonly currentAccountKey: string;
  readonly showAccountSwitcher: boolean;
  /** FEAT-P2-008：是否展示活跃设备页面。 */
  readonly showDevicesPage: boolean;
  /** FEAT-P2-008：活跃设备/会话列表。 */
  readonly activeSessions: readonly ActiveSessionItem[];
  /** FEAT-P2-008：是否正在加载会话列表。 */
  readonly isLoadingSessions: boolean;
  /** FEAT-UI-002 / SET-105：聊天消息字号（sp，恒为合法档位）。 */
  readonly chatFontSize: number;
  /** SELF-101：分区直达时的可见分区；'all' 为完整设置页。 */
  readonly section: SettingsSectionKey;
  /** SELF-102：是否展示「隐私和安全」子页。 */
  readonly showPrivacyPage: boolean;
  /** SELF-102：隐私规则列表。 */
  readonly privacyItems: readonly PrivacySettingItem[];
  /** SELF-102：是否正在读取隐私规则。 */
  readonly isLoadingPrivacy: boolean;
  /** SELF-102：正在写回的隐私项。 */
  readonly updatingPrivacyKey: PrivacySettingKey | null;
  /** PROXY-101：是否展示「代理」子页。 */
  readonly showProxyPage: boolean;
  /** PROXY-101：代理列表（TDLib addedProxies 的页面投影）。 */
  readonly proxyItems: ProxyItem[];
  /** PROXY-101：是否正在读取代理列表。 */
  readonly isLoadingProxies: boolean;
  /** PROXY-101：正在写回的代理 id；null 表示空闲，0 是「不使用代理」行。 */
  readonly updatingProxyId: number | null;
  /** AUTODL-101：是否展示「自动媒体下载」子页。 */
  readonly showAutoDownloadPage: boolean;
  /** AUTODL-101：自动下载策略；null 表示尚未读盘。 */
  readonly autoDownloadPolicy: AutoDownloadPolicy | null;
  /** AUTODL-102：省流量设置；null 表示尚未读盘。 */
  readonly dataSaverSettings: DataSaverSettings | null;
  /** AUTODL-103：按网络档的自动下载限制；null 表示尚未读盘。 */
  readonly downloadLimits: DownloadLimitsByNetwork | null;
  /** PROXY-102：各行连通性探测结果；空 Map 表示一行都没测过。 */
  readonly proxyPingMs: Map<number, number>;
  /** PROXY-102：TDLib 连接态。 */
  readonly proxyConnection: ProxyConnectionState;

  constructor(
    userId: number,
    displayName: string,
    username: string,
    phoneNumber: string,
    avatarLocalPath: string | null,
    bio: string,
    notificationsEnabled: boolean,
    privateNotificationsEnabled: boolean,
    groupNotificationsEnabled: boolean,
    channelNotificationsEnabled: boolean,
    isUpdatingNotifications: boolean,
    updatingNotificationScope: NotificationScopeKey | null,
    storageCacheSize: string,
    languageCode: string,
    languagePreference: LanguagePreference,
    themeMode: SettingsThemeMode,
    appVersion: string,
    isLoading: boolean,
    isLoggingOut: boolean,
    errorMessage: string | null,
    showLogoutConfirm: boolean,
    availableAccounts: readonly string[] = [],
    currentAccountKey: string = '',
    showAccountSwitcher: boolean = false,
    showDevicesPage: boolean = false,
    activeSessions: readonly ActiveSessionItem[] = [],
    isLoadingSessions: boolean = false,
    chatFontSize: number = CHAT_FONT_SIZE_DEFAULT,
    section: SettingsSectionKey = 'all',
    showPrivacyPage: boolean = false,
    privacyItems: readonly PrivacySettingItem[] = [],
    isLoadingPrivacy: boolean = false,
    updatingPrivacyKey: PrivacySettingKey | null = null,
    showProxyPage: boolean = false,
    proxyItems: ProxyItem[] = [],
    isLoadingProxies: boolean = false,
    updatingProxyId: number | null = null,
    showAutoDownloadPage: boolean = false,
    autoDownloadPolicy: AutoDownloadPolicy | null = null,
    dataSaverSettings: DataSaverSettings | null = null,
    downloadLimits: DownloadLimitsByNetwork | null = null,
    proxyPingMs: Map<number, number> = new Map(),
    proxyConnection: ProxyConnectionState = 'unknown'
  ) {
    this.userId = userId;
    this.displayName = displayName;
    this.username = username;
    this.phoneNumber = phoneNumber;
    this.avatarLocalPath = avatarLocalPath;
    this.bio = bio;
    this.notificationsEnabled = notificationsEnabled;
    this.privateNotificationsEnabled = privateNotificationsEnabled;
    this.groupNotificationsEnabled = groupNotificationsEnabled;
    this.channelNotificationsEnabled = channelNotificationsEnabled;
    this.isUpdatingNotifications = isUpdatingNotifications;
    this.updatingNotificationScope = updatingNotificationScope;
    this.storageCacheSize = storageCacheSize;
    this.languageCode = languageCode;
    this.languagePreference = languagePreference;
    this.themeMode = themeMode;
    this.appVersion = appVersion;
    this.isLoading = isLoading;
    this.isLoggingOut = isLoggingOut;
    this.errorMessage = errorMessage;
    this.showLogoutConfirm = showLogoutConfirm;
    this.availableAccounts = availableAccounts;
    this.currentAccountKey = currentAccountKey;
    this.showAccountSwitcher = showAccountSwitcher;
    this.showDevicesPage = showDevicesPage;
    this.activeSessions = activeSessions;
    this.isLoadingSessions = isLoadingSessions;
    this.chatFontSize = chatFontSize;
    this.section = section;
    this.showPrivacyPage = showPrivacyPage;
    this.privacyItems = privacyItems;
    this.isLoadingPrivacy = isLoadingPrivacy;
    this.updatingPrivacyKey = updatingPrivacyKey;
    this.showProxyPage = showProxyPage;
    this.proxyItems = proxyItems;
    this.isLoadingProxies = isLoadingProxies;
    this.updatingProxyId = updatingProxyId;
    this.showAutoDownloadPage = showAutoDownloadPage;
    this.autoDownloadPolicy = autoDownloadPolicy;
    this.dataSaverSettings = dataSaverSettings;
    this.downloadLimits = downloadLimits;
    this.proxyPingMs = proxyPingMs;
    this.proxyConnection = proxyConnection;
  }

  static initial(
    themeMode: SettingsThemeMode = 'system',
    languagePreference: LanguagePreference = 'system',
    languageCode: string = 'en',
    currentAccountKey: string = '',
    availableAccounts: readonly string[] = [],
    chatFontSize: number = CHAT_FONT_SIZE_DEFAULT
  ): SettingsUiState {
    return new SettingsUiState(
      0,
      '',
      '',
      '',
      null,
      '',
      true,
      true,
      true,
      true,
      true,
      null,
      '0 B',
      languageCode,
      languagePreference,
      themeMode,
      '1.0.0',
      false,
      false,
      null,
      false,
      availableAccounts,
      currentAccountKey,
      false,
      false,
      [],
      false,
      chatFontSize
    );
  }

  copyWith(options: SettingsUiStateOptions): SettingsUiState {
    return new SettingsUiState(
      options.userId !== undefined ? options.userId : this.userId,
      options.displayName !== undefined ? options.displayName : this.displayName,
      options.username !== undefined ? options.username : this.username,
      options.phoneNumber !== undefined ? options.phoneNumber : this.phoneNumber,
      options.avatarLocalPath !== undefined ? options.avatarLocalPath : this.avatarLocalPath,
      options.bio !== undefined ? options.bio : this.bio,
      options.notificationsEnabled !== undefined ? options.notificationsEnabled : this.notificationsEnabled,
      options.privateNotificationsEnabled !== undefined
        ? options.privateNotificationsEnabled
        : this.privateNotificationsEnabled,
      options.groupNotificationsEnabled !== undefined
        ? options.groupNotificationsEnabled
        : this.groupNotificationsEnabled,
      options.channelNotificationsEnabled !== undefined
        ? options.channelNotificationsEnabled
        : this.channelNotificationsEnabled,
      options.isUpdatingNotifications !== undefined
        ? options.isUpdatingNotifications
        : this.isUpdatingNotifications,
      options.updatingNotificationScope !== undefined
        ? options.updatingNotificationScope
        : this.updatingNotificationScope,
      options.storageCacheSize !== undefined ? options.storageCacheSize : this.storageCacheSize,
      options.languageCode !== undefined ? options.languageCode : this.languageCode,
      options.languagePreference !== undefined ? options.languagePreference : this.languagePreference,
      options.themeMode !== undefined ? options.themeMode : this.themeMode,
      options.appVersion !== undefined ? options.appVersion : this.appVersion,
      options.isLoading !== undefined ? options.isLoading : this.isLoading,
      options.isLoggingOut !== undefined ? options.isLoggingOut : this.isLoggingOut,
      options.errorMessage !== undefined ? options.errorMessage : this.errorMessage,
      options.showLogoutConfirm !== undefined ? options.showLogoutConfirm : this.showLogoutConfirm,
      options.availableAccounts !== undefined ? options.availableAccounts : this.availableAccounts,
      options.currentAccountKey !== undefined ? options.currentAccountKey : this.currentAccountKey,
      options.showAccountSwitcher !== undefined ? options.showAccountSwitcher : this.showAccountSwitcher,
      options.showDevicesPage !== undefined ? options.showDevicesPage : this.showDevicesPage,
      options.activeSessions !== undefined ? options.activeSessions : this.activeSessions,
      options.isLoadingSessions !== undefined ? options.isLoadingSessions : this.isLoadingSessions,
      options.chatFontSize !== undefined ? options.chatFontSize : this.chatFontSize,
      options.section !== undefined ? options.section : this.section,
      options.showPrivacyPage !== undefined ? options.showPrivacyPage : this.showPrivacyPage,
      options.privacyItems !== undefined ? options.privacyItems : this.privacyItems,
      options.isLoadingPrivacy !== undefined ? options.isLoadingPrivacy : this.isLoadingPrivacy,
      options.updatingPrivacyKey !== undefined ? options.updatingPrivacyKey : this.updatingPrivacyKey,
      options.showProxyPage !== undefined ? options.showProxyPage : this.showProxyPage,
      options.proxyItems !== undefined ? options.proxyItems : this.proxyItems,
      options.isLoadingProxies !== undefined ? options.isLoadingProxies : this.isLoadingProxies,
      options.updatingProxyId !== undefined ? options.updatingProxyId : this.updatingProxyId,
      options.showAutoDownloadPage !== undefined ? options.showAutoDownloadPage : this.showAutoDownloadPage,
      options.autoDownloadPolicy !== undefined ? options.autoDownloadPolicy : this.autoDownloadPolicy,
      // 显式传 null 表示「清空为未读盘」，与 undefined（不改动）区分开。
      options.dataSaverSettings !== undefined ? options.dataSaverSettings : this.dataSaverSettings,
      options.downloadLimits !== undefined ? options.downloadLimits : this.downloadLimits,
      options.proxyPingMs !== undefined ? options.proxyPingMs : this.proxyPingMs,
      options.proxyConnection !== undefined ? options.proxyConnection : this.proxyConnection
    );
  }
}
