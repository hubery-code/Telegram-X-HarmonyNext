/**
 * feature/settings — 设置页纯 Reducer（SET-101）。
 *
 * 遵循计划 §5.11 / UI-003：
 * - 纯函数：(state, intent, env) -> ReducerResult<SettingsUiState, SettingsEffect>
 * - 禁止修改入参 state；无变化时原样返回同一引用 reduced(state)；
 * - 副作用只以 Effect 描述形式返回，严禁在 reducer 内部执行；
 * - 严禁匿名对象字面量传参，统一使用 SettingsUiStateOptions。
 */

import { Reducer, ReducerEnv, ReducerResult, reduced } from '@tgx/feature-template';
import { ThemeManager } from '@tgx/core-design-system';
import { Lang, LanguagePreference } from '@tgx/core-common';
import { SettingsUiState, SettingsUiStateOptions } from '../contract/SettingsUiState';
import {
  CacheCleared,
  ChangeLanguage,
  ChangeThemeMode,
  CloseAccountSwitcher,
  LoadNotificationSettings,
  NotificationScopeUpdated,
  NotificationScopeUpdateFailed,
  NotificationSettingsLoaded,
  NotificationSettingsUpdated,
  NotificationSettingsUpdateFailed,
  OpenAccountSwitcher,
  ProfileLoaded,
  RequestAddAccount,
  SetAvailableAccounts,
  SetErrorMessage,
  SetLanguage,
  SettingsIntent,
  StorageStatsLoaded,
  SwitchAccount,
  ToggleNotificationScope
} from '../contract/SettingsIntent';
import {
  ClearCacheEffect,
  LoadNotificationSettingsEffect,
  LoadProfileEffect,
  LoadStorageStatsEffect,
  LogoutEffect,
  RequestAddAccountEffect,
  SettingsEffect,
  ShowToastEffect,
  SetNotificationScopeEnabledEffect,
  SetNotificationsEnabledEffect,
  SwitchAccountEffect
} from '../contract/SettingsEffect';
import { NotificationScopeKey } from '../model/NotificationSettings';

function notificationScopeEnabled(state: SettingsUiState, scope: NotificationScopeKey): boolean {
  if (scope === 'private') {
    return state.privateNotificationsEnabled;
  }
  if (scope === 'group') {
    return state.groupNotificationsEnabled;
  }
  return state.channelNotificationsEnabled;
}

export const settingsReducer: Reducer<SettingsUiState, SettingsIntent, SettingsEffect> = (
  state: SettingsUiState,
  intent: SettingsIntent,
  env: ReducerEnv
): ReducerResult<SettingsUiState, SettingsEffect> => {
  switch (intent.kind) {
    case 'loadUserProfile': {
      if (state.isLoading) {
        return reduced(state);
      }
      const options: SettingsUiStateOptions = {
        isLoading: true,
        errorMessage: null
      };
      const nextState: SettingsUiState = state.copyWith(options);
      const effects: readonly SettingsEffect[] = [new LoadProfileEffect()];
      return reduced(nextState, effects);
    }

    case 'profileLoaded': {
      const loadedIntent: ProfileLoaded = intent as ProfileLoaded;
      const options: SettingsUiStateOptions = {
        userId: loadedIntent.profile.userId,
        displayName: loadedIntent.profile.displayName,
        username: loadedIntent.profile.username,
        phoneNumber: loadedIntent.profile.phoneNumber,
        avatarLocalPath: loadedIntent.profile.avatarLocalPath,
        bio: loadedIntent.profile.bio,
        isLoading: false,
        errorMessage: null
      };
      const nextState: SettingsUiState = state.copyWith(options);
      return reduced(nextState);
    }

    case 'toggleNotifications': {
      if (state.isUpdatingNotifications || state.updatingNotificationScope !== null) {
        return reduced(state);
      }
      const nextEnabled: boolean = !state.notificationsEnabled;
      const options: SettingsUiStateOptions = {
        isUpdatingNotifications: true,
        errorMessage: null
      };
      const nextState: SettingsUiState = state.copyWith(options);
      const effects: readonly SettingsEffect[] = [new SetNotificationsEnabledEffect(nextEnabled)];
      return reduced(nextState, effects);
    }

    case 'toggleNotificationScope': {
      if (state.isUpdatingNotifications || state.updatingNotificationScope !== null) {
        return reduced(state);
      }
      const scopeIntent: ToggleNotificationScope = intent as ToggleNotificationScope;
      const nextEnabled: boolean = !notificationScopeEnabled(state, scopeIntent.scope);
      const options: SettingsUiStateOptions = {
        updatingNotificationScope: scopeIntent.scope,
        errorMessage: null
      };
      const effects: readonly SettingsEffect[] = [
        new SetNotificationScopeEnabledEffect(scopeIntent.scope, nextEnabled)
      ];
      return reduced(state.copyWith(options), effects);
    }

    case 'loadNotificationSettings': {
      const effects: readonly SettingsEffect[] = [new LoadNotificationSettingsEffect()];
      return reduced(state, effects);
    }

    case 'notificationSettingsLoaded': {
      const loadedIntent: NotificationSettingsLoaded = intent as NotificationSettingsLoaded;
      const options: SettingsUiStateOptions = {
        notificationsEnabled: loadedIntent.enabled,
        privateNotificationsEnabled: loadedIntent.privateEnabled,
        groupNotificationsEnabled: loadedIntent.groupEnabled,
        channelNotificationsEnabled: loadedIntent.channelEnabled,
        isUpdatingNotifications: false,
        updatingNotificationScope: null
      };
      return reduced(state.copyWith(options));
    }

    case 'notificationSettingsUpdated': {
      const updatedIntent: NotificationSettingsUpdated = intent as NotificationSettingsUpdated;
      const options: SettingsUiStateOptions = {
        notificationsEnabled: updatedIntent.enabled,
        privateNotificationsEnabled: updatedIntent.enabled,
        groupNotificationsEnabled: updatedIntent.enabled,
        channelNotificationsEnabled: updatedIntent.enabled,
        isUpdatingNotifications: false,
        updatingNotificationScope: null,
        errorMessage: null
      };
      const message: string = updatedIntent.enabled ? 'Notifications enabled' : 'Notifications disabled';
      const effects: readonly SettingsEffect[] = [new ShowToastEffect(message)];
      return reduced(state.copyWith(options), effects);
    }

    case 'notificationScopeUpdated': {
      const updatedIntent: NotificationScopeUpdated = intent as NotificationScopeUpdated;
      let privateEnabled: boolean = state.privateNotificationsEnabled;
      let groupEnabled: boolean = state.groupNotificationsEnabled;
      let channelEnabled: boolean = state.channelNotificationsEnabled;
      if (updatedIntent.scope === 'private') {
        privateEnabled = updatedIntent.enabled;
      } else if (updatedIntent.scope === 'group') {
        groupEnabled = updatedIntent.enabled;
      } else {
        channelEnabled = updatedIntent.enabled;
      }
      const options: SettingsUiStateOptions = {
        notificationsEnabled: privateEnabled && groupEnabled && channelEnabled,
        privateNotificationsEnabled: privateEnabled,
        groupNotificationsEnabled: groupEnabled,
        channelNotificationsEnabled: channelEnabled,
        updatingNotificationScope: null,
        errorMessage: null
      };
      return reduced(state.copyWith(options));
    }

    case 'notificationSettingsUpdateFailed': {
      const failedIntent: NotificationSettingsUpdateFailed = intent as NotificationSettingsUpdateFailed;
      const options: SettingsUiStateOptions = {
        isUpdatingNotifications: false,
        updatingNotificationScope: null,
        errorMessage: failedIntent.errorMessage
      };
      return reduced(state.copyWith(options));
    }

    case 'notificationScopeUpdateFailed': {
      const failedIntent: NotificationScopeUpdateFailed = intent as NotificationScopeUpdateFailed;
      const options: SettingsUiStateOptions = {
        updatingNotificationScope: null,
        errorMessage: failedIntent.errorMessage
      };
      return reduced(state.copyWith(options));
    }

    case 'changeThemeMode': {
      const themeIntent: ChangeThemeMode = intent as ChangeThemeMode;
      if (state.themeMode === themeIntent.themeMode) {
        return reduced(state);
      }
      // 1. 同步更新全局 ThemeManager
      ThemeManager.getInstance().setPreference(themeIntent.themeMode);

      // 2. 同步持久化到 AppStorage（若在 UI 运行环境中）
      try {
        AppStorage.setOrCreate<string>('themeMode', themeIntent.themeMode);
        AppStorage.setOrCreate<string>('themePreference', themeIntent.themeMode);
      } catch (_e) {
        // 无 AppStorage 运行环境（如纯逻辑单测）容错
      }

      const options: SettingsUiStateOptions = {
        themeMode: themeIntent.themeMode
      };
      const nextState: SettingsUiState = state.copyWith(options);
      const effects: readonly SettingsEffect[] = [
        new ShowToastEffect(`Theme mode set to ${themeIntent.themeMode}`)
      ];
      return reduced(nextState, effects);
    }

    case 'changeLanguage':
    case 'setLanguage': {
      const langIntent: ChangeLanguage = intent as ChangeLanguage;
      const pref: LanguagePreference = langIntent.languagePreference;
      if (state.languagePreference === pref) {
        return reduced(state);
      }
      // 1. 同步更新全局 Lang
      Lang.getInstance().setLanguage(pref);
      const effectiveLang: string = Lang.getInstance().getLanguage();

      // 2. 同步持久化到 AppStorage（若在 UI 运行环境中）
      try {
        AppStorage.setOrCreate<string>('appLanguage', pref);
        AppStorage.setOrCreate<string>('languagePreference', pref);
      } catch (_e) {
        // 无 AppStorage 运行环境（如纯逻辑单测）容错
      }

      const options: SettingsUiStateOptions = {
        languagePreference: pref,
        languageCode: effectiveLang
      };
      const nextState: SettingsUiState = state.copyWith(options);
      const effects: readonly SettingsEffect[] = [
        new ShowToastEffect(`Language set to ${pref}`)
      ];
      return reduced(nextState, effects);
    }

    case 'requestLogout': {
      if (state.showLogoutConfirm) {
        return reduced(state);
      }
      const options: SettingsUiStateOptions = {
        showLogoutConfirm: true
      };
      return reduced(state.copyWith(options));
    }

    case 'cancelLogout': {
      if (!state.showLogoutConfirm) {
        return reduced(state);
      }
      const options: SettingsUiStateOptions = {
        showLogoutConfirm: false
      };
      return reduced(state.copyWith(options));
    }

    case 'confirmLogout': {
      if (state.isLoggingOut) {
        return reduced(state);
      }
      const options: SettingsUiStateOptions = {
        isLoggingOut: true,
        showLogoutConfirm: false
      };
      const nextState: SettingsUiState = state.copyWith(options);
      const effects: readonly SettingsEffect[] = [new LogoutEffect()];
      return reduced(nextState, effects);
    }

    case 'clearCacheRequested': {
      const effects: readonly SettingsEffect[] = [new ClearCacheEffect()];
      return reduced(state, effects);
    }

    // ---- SET-104 存储占用 ----

    case 'loadStorageStats': {
      // 拉取存储占用：不改 UI 状态（静默刷新），只出 effect；
      // 结果经 storageStatsLoaded 回灌。重复进入设置页可反复触发，无副作用。
      const effects: readonly SettingsEffect[] = [new LoadStorageStatsEffect()];
      return reduced(state, effects);
    }

    case 'storageStatsLoaded': {
      const statsIntent: StorageStatsLoaded = intent as StorageStatsLoaded;
      const options: SettingsUiStateOptions = {
        storageCacheSize: statsIntent.label
      };
      return reduced(state.copyWith(options));
    }

    case 'cacheCleared': {
      const clearedIntent: CacheCleared = intent as CacheCleared;
      const options: SettingsUiStateOptions = {
        storageCacheSize: clearedIntent.newCacheSize
      };
      const nextState: SettingsUiState = state.copyWith(options);
      const effects: readonly SettingsEffect[] = [
        new ShowToastEffect('Cache cleared')
      ];
      return reduced(nextState, effects);
    }

    case 'setErrorMessage': {
      const errorIntent: SetErrorMessage = intent as SetErrorMessage;
      const options: SettingsUiStateOptions = {
        isLoading: false,
        isLoggingOut: false,
        errorMessage: errorIntent.errorMessage
      };
      return reduced(state.copyWith(options));
    }

    case 'openAccountSwitcher': {
      if (state.showAccountSwitcher) {
        return reduced(state);
      }
      return reduced(state.copyWith({ showAccountSwitcher: true }));
    }

    case 'closeAccountSwitcher': {
      if (!state.showAccountSwitcher) {
        return reduced(state);
      }
      return reduced(state.copyWith({ showAccountSwitcher: false }));
    }

    case 'switchAccount': {
      const switchIntent: SwitchAccount = intent as SwitchAccount;
      const targetKey: string = switchIntent.accountKey;
      const options: SettingsUiStateOptions = {
        currentAccountKey: targetKey,
        showAccountSwitcher: false
      };
      const nextState: SettingsUiState = state.copyWith(options);
      const effects: readonly SettingsEffect[] = [new SwitchAccountEffect(targetKey)];
      return reduced(nextState, effects);
    }

    case 'requestAddAccount': {
      const options: SettingsUiStateOptions = {
        showAccountSwitcher: false
      };
      const nextState: SettingsUiState = state.copyWith(options);
      const effects: readonly SettingsEffect[] = [new RequestAddAccountEffect()];
      return reduced(nextState, effects);
    }

    case 'setAvailableAccounts': {
      const setAccountsIntent: SetAvailableAccounts = intent as SetAvailableAccounts;
      const options: SettingsUiStateOptions = {
        availableAccounts: setAccountsIntent.accounts,
        currentAccountKey: setAccountsIntent.currentAccountKey !== undefined
          ? setAccountsIntent.currentAccountKey
          : state.currentAccountKey
      };
      return reduced(state.copyWith(options));
    }

    default:
      return reduced(state);
  }
};
