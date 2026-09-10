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
import { SettingsUiState, SettingsUiStateOptions } from '../contract/SettingsUiState';
import {
  CacheCleared,
  ChangeThemeMode,
  ProfileLoaded,
  SetErrorMessage,
  SettingsIntent
} from '../contract/SettingsIntent';
import {
  ClearCacheEffect,
  LoadProfileEffect,
  LogoutEffect,
  SettingsEffect,
  ShowToastEffect
} from '../contract/SettingsEffect';

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
      const nextEnabled: boolean = !state.notificationsEnabled;
      const options: SettingsUiStateOptions = {
        notificationsEnabled: nextEnabled
      };
      const nextState: SettingsUiState = state.copyWith(options);
      const message: string = nextEnabled ? 'Notifications enabled' : 'Notifications disabled';
      const effects: readonly SettingsEffect[] = [new ShowToastEffect(message)];
      return reduced(nextState, effects);
    }

    case 'changeThemeMode': {
      const themeIntent: ChangeThemeMode = intent as ChangeThemeMode;
      if (state.themeMode === themeIntent.themeMode) {
        return reduced(state);
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

    default:
      return reduced(state);
  }
};
