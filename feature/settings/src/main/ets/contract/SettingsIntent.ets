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

export class LoadNotificationSettings implements Intent {
  readonly kind: 'loadNotificationSettings' = 'loadNotificationSettings';
}

export class NotificationSettingsLoaded implements Intent {
  readonly kind: 'notificationSettingsLoaded' = 'notificationSettingsLoaded';
  readonly enabled: boolean;

  constructor(enabled: boolean) {
    this.enabled = enabled;
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

export class ChangeThemeMode implements Intent {
  readonly kind: 'changeThemeMode' = 'changeThemeMode';
  readonly themeMode: SettingsThemeMode;

  constructor(themeMode: SettingsThemeMode) {
    this.themeMode = themeMode;
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

export type SettingsIntent =
  | LoadUserProfile
  | ToggleNotifications
  | LoadNotificationSettings
  | NotificationSettingsLoaded
  | NotificationSettingsUpdated
  | NotificationSettingsUpdateFailed
  | ChangeThemeMode
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
  | SetAvailableAccounts;
