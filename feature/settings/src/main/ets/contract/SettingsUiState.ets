/**
 * feature/settings — 设置页可观察状态（SET-101）。
 *
 * 遵循计划 §5.11 / UI-003：
 * - 纯 ArkTS 契约层；
 * - 所有字段只读，不可变状态经 copyWith 派生；
 * - 严禁匿名对象字面量传参，提供明确的 SettingsUiStateOptions 接口。
 */

import { UiState } from '@tgx/feature-template';
import { ThemePreference } from '@tgx/core-design-system';
import { LanguagePreference } from '@tgx/core-common';

export type SettingsThemeMode = ThemePreference;

export interface SettingsUiStateOptions {
  readonly userId?: number;
  readonly displayName?: string;
  readonly username?: string;
  readonly phoneNumber?: string;
  readonly avatarLocalPath?: string | null;
  readonly bio?: string;
  readonly notificationsEnabled?: boolean;
  readonly isUpdatingNotifications?: boolean;
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
}

export class SettingsUiState implements UiState {
  readonly userId: number;
  readonly displayName: string;
  readonly username: string;
  readonly phoneNumber: string;
  readonly avatarLocalPath: string | null;
  readonly bio: string;

  readonly notificationsEnabled: boolean;
  readonly isUpdatingNotifications: boolean;
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

  constructor(
    userId: number,
    displayName: string,
    username: string,
    phoneNumber: string,
    avatarLocalPath: string | null,
    bio: string,
    notificationsEnabled: boolean,
    isUpdatingNotifications: boolean,
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
    showAccountSwitcher: boolean = false
  ) {
    this.userId = userId;
    this.displayName = displayName;
    this.username = username;
    this.phoneNumber = phoneNumber;
    this.avatarLocalPath = avatarLocalPath;
    this.bio = bio;
    this.notificationsEnabled = notificationsEnabled;
    this.isUpdatingNotifications = isUpdatingNotifications;
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
  }

  static initial(
    themeMode: SettingsThemeMode = 'system',
    languagePreference: LanguagePreference = 'system',
    languageCode: string = 'en',
    currentAccountKey: string = '',
    availableAccounts: readonly string[] = []
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
      false
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
      options.isUpdatingNotifications !== undefined
        ? options.isUpdatingNotifications
        : this.isUpdatingNotifications,
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
      options.showAccountSwitcher !== undefined ? options.showAccountSwitcher : this.showAccountSwitcher
    );
  }
}
