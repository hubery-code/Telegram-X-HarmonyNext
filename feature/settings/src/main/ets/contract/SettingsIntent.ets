/**
 * feature/settings — 设置页用户意图与系统事件（SET-101）。
 *
 * 遵循计划 §5.11 / UI-003：
 * - 每个变体带 `kind` 判别字面量属性，由 reducer 做穷尽收窄；
 * - 纯 ArkTS 契约层。
 */

import { Intent } from '@tgx/feature-template';
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

export class ChangeThemeMode implements Intent {
  readonly kind: 'changeThemeMode' = 'changeThemeMode';
  readonly themeMode: SettingsThemeMode;

  constructor(themeMode: SettingsThemeMode) {
    this.themeMode = themeMode;
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

export type SettingsIntent =
  | LoadUserProfile
  | ToggleNotifications
  | ChangeThemeMode
  | RequestLogout
  | CancelLogout
  | ConfirmLogout
  | ClearCacheRequested
  | CacheCleared
  | ProfileLoaded
  | SetErrorMessage;
