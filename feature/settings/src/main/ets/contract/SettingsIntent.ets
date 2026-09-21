/**
 * feature/settings — 设置页用户意图与系统事件（SET-101）。
 *
 * 遵循计划 §5.11 / UI-003：
 * - 每个变体带 `kind` 判别字面量属性，由 reducer 做穷尽收窄；
 * - 纯 ArkTS 契约层。
 */

import { Intent } from '@tgx/feature-template';
import { LanguagePreference } from '@tgx/core-common';
import { SettingsThemeMode } from './SettingsUiState';
import { NotificationScopeKey } from '../model/NotificationSettings';
import { ActiveSessionItem } from '../model/ActiveSessionItem';

export interface UserProfileData {
  readonly userId: number;
  readonly displayName: string;
  readonly username: string;
  readonly phoneNumber: string;
  readonly avatarLocalPath: string | null;
  readonly bio: string;
}

export class LoadUserProfile implements Intent {
  readonly kind: 'loadUserProfile' = 'loadUserProfile';
}

export class ToggleNotifications implements Intent {
  readonly kind: 'toggleNotifications' = 'toggleNotifications';
}

export class ToggleNotificationScope implements Intent {
  readonly kind: 'toggleNotificationScope' = 'toggleNotificationScope';
  readonly scope: NotificationScopeKey;

  constructor(scope: NotificationScopeKey) {
    this.scope = scope;
  }
}

export class LoadNotificationSettings implements Intent {
  readonly kind: 'loadNotificationSettings' = 'loadNotificationSettings';
}

export class NotificationSettingsLoaded implements Intent {
  readonly kind: 'notificationSettingsLoaded' = 'notificationSettingsLoaded';
  readonly enabled: boolean;
  readonly privateEnabled: boolean;
  readonly groupEnabled: boolean;
  readonly channelEnabled: boolean;

  constructor(enabled: boolean, privateEnabled: boolean, groupEnabled: boolean, channelEnabled: boolean) {
    this.enabled = enabled;
    this.privateEnabled = privateEnabled;
    this.groupEnabled = groupEnabled;
    this.channelEnabled = channelEnabled;
  }
}

export class NotificationSettingsUpdated implements Intent {
  readonly kind: 'notificationSettingsUpdated' = 'notificationSettingsUpdated';
  readonly enabled: boolean;

  constructor(enabled: boolean) {
    this.enabled = enabled;
  }
}

export class NotificationSettingsUpdateFailed implements Intent {
  readonly kind: 'notificationSettingsUpdateFailed' = 'notificationSettingsUpdateFailed';
  readonly errorMessage: string;

  constructor(errorMessage: string) {
    this.errorMessage = errorMessage;
  }
}

export class NotificationScopeUpdated implements Intent {
  readonly kind: 'notificationScopeUpdated' = 'notificationScopeUpdated';
  readonly scope: NotificationScopeKey;
  readonly enabled: boolean;

  constructor(scope: NotificationScopeKey, enabled: boolean) {
    this.scope = scope;
    this.enabled = enabled;
  }
}

export class NotificationScopeUpdateFailed implements Intent {
  readonly kind: 'notificationScopeUpdateFailed' = 'notificationScopeUpdateFailed';
  readonly scope: NotificationScopeKey;
  readonly errorMessage: string;

  constructor(scope: NotificationScopeKey, errorMessage: string) {
    this.scope = scope;
    this.errorMessage = errorMessage;
  }
}

export class ChangeThemeMode implements Intent {
  readonly kind: 'changeThemeMode' = 'changeThemeMode';
  readonly themeMode: SettingsThemeMode;

  constructor(themeMode: SettingsThemeMode) {
    this.themeMode = themeMode;
  }
}

/**
 * FEAT-UI-002 / SET-105：调整聊天消息字号。
 * 单位 sp，传入值会被吸附到最近合法档位（见 `@tgx/core-design-system` 的
 * `clampChatFontSize`），因此调用方可以直接传滑块/档位按钮的原始值。
 */
export class ChangeChatFontSize implements Intent {
  readonly kind: 'changeChatFontSize' = 'changeChatFontSize';
  readonly chatFontSize: number;

  constructor(chatFontSize: number) {
    this.chatFontSize = chatFontSize;
  }
}

export class ChangeLanguage implements Intent {
  readonly kind: 'changeLanguage' = 'changeLanguage';
  readonly languagePreference: LanguagePreference;

  constructor(languagePreference: LanguagePreference) {
    this.languagePreference = languagePreference;
  }
}

export class SetLanguage implements Intent {
  readonly kind: 'setLanguage' = 'setLanguage';
  readonly languagePreference: LanguagePreference;

  constructor(languagePreference: LanguagePreference) {
    this.languagePreference = languagePreference;
  }
}

export class RequestLogout implements Intent {
  readonly kind: 'requestLogout' = 'requestLogout';
}

export class CancelLogout implements Intent {
  readonly kind: 'cancelLogout' = 'cancelLogout';
}

export class ConfirmLogout implements Intent {
  readonly kind: 'confirmLogout' = 'confirmLogout';
}

export class ClearCacheRequested implements Intent {
  readonly kind: 'clearCacheRequested' = 'clearCacheRequested';
}

/**
 * SET-104：进入设置页时请求拉取存储占用（reducer 出 loadStorageStats effect）。
 */
export class LoadStorageStats implements Intent {
  readonly kind: 'loadStorageStats' = 'loadStorageStats';
}

/**
 * SET-104：存储占用拉取/清理后的结果回灌。
 * label 由 coordinator 用 `formatStorageLabel` 预先格式化好——与既有
 * CacheCleared 携带已格式化字符串的约定保持一致，reducer 保持纯搬运。
 */
export class StorageStatsLoaded implements Intent {
  readonly kind: 'storageStatsLoaded' = 'storageStatsLoaded';
  readonly label: string;

  constructor(label: string) {
    this.label = label;
  }
}

export class CacheCleared implements Intent {
  readonly kind: 'cacheCleared' = 'cacheCleared';
  readonly newCacheSize: string;

  constructor(newCacheSize: string = '0 B') {
    this.newCacheSize = newCacheSize;
  }
}

export class ProfileLoaded implements Intent {
  readonly kind: 'profileLoaded' = 'profileLoaded';
  readonly profile: UserProfileData;

  constructor(profile: UserProfileData) {
    this.profile = profile;
  }
}

export class SetErrorMessage implements Intent {
  readonly kind: 'setErrorMessage' = 'setErrorMessage';
  readonly errorMessage: string | null;

  constructor(errorMessage: string | null) {
    this.errorMessage = errorMessage;
  }
}

export class SwitchAccount implements Intent {
  readonly kind: 'switchAccount' = 'switchAccount';
  readonly accountKey: string;

  constructor(accountKey: string) {
    this.accountKey = accountKey;
  }
}

export class RequestAddAccount implements Intent {
  readonly kind: 'requestAddAccount' = 'requestAddAccount';
}

export class OpenAccountSwitcher implements Intent {
  readonly kind: 'openAccountSwitcher' = 'openAccountSwitcher';
}

export class CloseAccountSwitcher implements Intent {
  readonly kind: 'closeAccountSwitcher' = 'closeAccountSwitcher';
}

export class SetAvailableAccounts implements Intent {
  readonly kind: 'setAvailableAccounts' = 'setAvailableAccounts';
  readonly accounts: readonly string[];
  readonly currentAccountKey?: string;

  constructor(accounts: readonly string[], currentAccountKey?: string) {
    this.accounts = accounts;
    this.currentAccountKey = currentAccountKey;
  }
}

/** FEAT-P2-008：打开活跃设备页面。 */
export class OpenDevicesPage implements Intent {
  readonly kind: 'openDevicesPage' = 'openDevicesPage';
}

/** FEAT-P2-008：关闭活跃设备页面。 */
export class CloseDevicesPage implements Intent {
  readonly kind: 'closeDevicesPage' = 'closeDevicesPage';
}

/** FEAT-P2-008：拉取活跃设备/会话列表。 */
export class LoadActiveSessions implements Intent {
  readonly kind: 'loadActiveSessions' = 'loadActiveSessions';
}

/** FEAT-P2-008：活跃设备/会话列表加载完成。 */
export class ActiveSessionsLoaded implements Intent {
  readonly kind: 'activeSessionsLoaded' = 'activeSessionsLoaded';
  readonly sessions: readonly ActiveSessionItem[];

  constructor(sessions: readonly ActiveSessionItem[]) {
    this.sessions = sessions;
  }
}

/** FEAT-P2-008：活跃设备/会话列表加载失败。 */
export class ActiveSessionsLoadFailed implements Intent {
  readonly kind: 'activeSessionsLoadFailed' = 'activeSessionsLoadFailed';
  readonly errorMessage: string;

  constructor(errorMessage: string) {
    this.errorMessage = errorMessage;
  }
}

/** FEAT-P2-008：终止指定设备会话。 */
export class TerminateSessionIntent implements Intent {
  readonly kind: 'terminateSession' = 'terminateSession';
  readonly sessionId: string;

  constructor(sessionId: string) {
    this.sessionId = sessionId;
  }
}

/** FEAT-P2-008：终止除当前设备外的所有会话。 */
export class TerminateAllOtherSessionsIntent implements Intent {
  readonly kind: 'terminateAllOtherSessions' = 'terminateAllOtherSessions';
}

export type SettingsIntent =
  | LoadUserProfile
  | ToggleNotifications
  | ToggleNotificationScope
  | LoadNotificationSettings
  | NotificationSettingsLoaded
  | NotificationSettingsUpdated
  | NotificationSettingsUpdateFailed
  | NotificationScopeUpdated
  | NotificationScopeUpdateFailed
  | ChangeThemeMode
  | ChangeChatFontSize
  | ChangeLanguage
  | SetLanguage
  | RequestLogout
  | CancelLogout
  | ConfirmLogout
  | ClearCacheRequested
  | LoadStorageStats
  | StorageStatsLoaded
  | CacheCleared
  | ProfileLoaded
  | SetErrorMessage
  | SwitchAccount
  | RequestAddAccount
  | OpenAccountSwitcher
  | CloseAccountSwitcher
  | SetAvailableAccounts
  | OpenDevicesPage
  | CloseDevicesPage
  | LoadActiveSessions
  | ActiveSessionsLoaded
  | ActiveSessionsLoadFailed
  | TerminateSessionIntent
  | TerminateAllOtherSessionsIntent;
