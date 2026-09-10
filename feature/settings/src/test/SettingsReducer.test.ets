import { describe, it, expect } from '@ohos/hypium';
import { ManualClock, SequentialIdGenerator } from '@tgx/core-common';
import { ReducerEnv } from '@tgx/feature-template';
import { SettingsUiState, SettingsUiStateOptions } from '../main/ets/contract/SettingsUiState';
import {
  CacheCleared,
  CancelLogout,
  ChangeThemeMode,
  ClearCacheRequested,
  ConfirmLogout,
  LoadUserProfile,
  ProfileLoaded,
  RequestLogout,
  SetErrorMessage,
  ToggleNotifications,
  UserProfileData
} from '../main/ets/contract/SettingsIntent';
import {
  ClearCacheEffect,
  LoadProfileEffect,
  LogoutEffect,
  ShowToastEffect
} from '../main/ets/contract/SettingsEffect';
import { settingsReducer } from '../main/ets/reducer/SettingsReducer';

function makeEnv(nowMillis: number = 1000, monotonicMillis: number = 500): ReducerEnv {
  const env: ReducerEnv = {
    clock: new ManualClock(nowMillis, monotonicMillis),
    ids: new SequentialIdGenerator('settings-test-')
  };
  return env;
}

export default function settingsReducerTest(): void {
  describe('SettingsReducerTest', () => {
    it('initialState_hasExpectedDefaults', 0, () => {
      const state = SettingsUiState.initial();
      expect(state.userId).assertEqual(0);
      expect(state.displayName).assertEqual('');
      expect(state.username).assertEqual('');
      expect(state.phoneNumber).assertEqual('');
      expect(state.avatarLocalPath).assertNull();
      expect(state.bio).assertEqual('');
      expect(state.notificationsEnabled).assertTrue();
      expect(state.storageCacheSize).assertEqual('0 B');
      expect(state.themeMode).assertEqual('system');
      expect(state.appVersion).assertEqual('1.0.0');
      expect(state.isLoading).assertFalse();
      expect(state.isLoggingOut).assertFalse();
      expect(state.errorMessage).assertNull();
      expect(state.showLogoutConfirm).assertFalse();
    });

    it('loadUserProfile_notLoading_setsLoadingAndEmitsEffect', 0, () => {
      const state = SettingsUiState.initial();
      const result = settingsReducer(state, new LoadUserProfile(), makeEnv());

      expect(result.state.isLoading).assertTrue();
      expect(result.state.errorMessage).assertNull();
      expect(result.effects.length).assertEqual(1);
      expect(result.effects[0].kind).assertEqual('loadProfile');
    });

    it('loadUserProfile_alreadyLoading_isIdempotent', 0, () => {
      const options: SettingsUiStateOptions = { isLoading: true };
      const state = SettingsUiState.initial().copyWith(options);
      const result = settingsReducer(state, new LoadUserProfile(), makeEnv());

      expect(result.state === state).assertTrue();
      expect(result.effects.length).assertEqual(0);
    });

    it('profileLoaded_updatesFieldsAndResetsLoading', 0, () => {
      const options: SettingsUiStateOptions = { isLoading: true, errorMessage: 'Old error' };
      const state = SettingsUiState.initial().copyWith(options);

      const profile: UserProfileData = {
        userId: 12345,
        displayName: 'Alice Cooper',
        username: 'alice',
        phoneNumber: '+1234567890',
        avatarLocalPath: '/data/storage/avatar.jpg',
        bio: 'Hello world'
      };

      const result = settingsReducer(state, new ProfileLoaded(profile), makeEnv());

      expect(result.state.userId).assertEqual(12345);
      expect(result.state.displayName).assertEqual('Alice Cooper');
      expect(result.state.username).assertEqual('alice');
      expect(result.state.phoneNumber).assertEqual('+1234567890');
      expect(result.state.avatarLocalPath).assertEqual('/data/storage/avatar.jpg');
      expect(result.state.bio).assertEqual('Hello world');
      expect(result.state.isLoading).assertFalse();
      expect(result.state.errorMessage).assertNull();
      expect(result.effects.length).assertEqual(0);
    });

    it('toggleNotifications_togglesValueAndEmitsToast', 0, () => {
      const state = SettingsUiState.initial();
      expect(state.notificationsEnabled).assertTrue();

      const r1 = settingsReducer(state, new ToggleNotifications(), makeEnv());
      expect(r1.state.notificationsEnabled).assertFalse();
      expect(r1.effects.length).assertEqual(1);
      expect(r1.effects[0].kind).assertEqual('showToast');
      expect((r1.effects[0] as ShowToastEffect).message).assertEqual('Notifications disabled');

      const r2 = settingsReducer(r1.state, new ToggleNotifications(), makeEnv());
      expect(r2.state.notificationsEnabled).assertTrue();
      expect(r2.effects.length).assertEqual(1);
      expect((r2.effects[0] as ShowToastEffect).message).assertEqual('Notifications enabled');
    });

    it('changeThemeMode_updatesThemeAndEmitsToast', 0, () => {
      const state = SettingsUiState.initial();
      const result = settingsReducer(state, new ChangeThemeMode('dark'), makeEnv());

      expect(result.state.themeMode).assertEqual('dark');
      expect(result.effects.length).assertEqual(1);
      expect(result.effects[0].kind).assertEqual('showToast');
      expect((result.effects[0] as ShowToastEffect).message).assertEqual('Theme mode set to dark');
    });

    it('changeThemeMode_sameMode_isNoOp', 0, () => {
      const options: SettingsUiStateOptions = { themeMode: 'dark' };
      const state = SettingsUiState.initial().copyWith(options);
      const result = settingsReducer(state, new ChangeThemeMode('dark'), makeEnv());

      expect(result.state === state).assertTrue();
      expect(result.effects.length).assertEqual(0);
    });

    it('requestLogout_showsConfirm', 0, () => {
      const state = SettingsUiState.initial();
      const result = settingsReducer(state, new RequestLogout(), makeEnv());

      expect(result.state.showLogoutConfirm).assertTrue();
      expect(result.effects.length).assertEqual(0);
    });

    it('requestLogout_alreadyShowing_isNoOp', 0, () => {
      const options: SettingsUiStateOptions = { showLogoutConfirm: true };
      const state = SettingsUiState.initial().copyWith(options);
      const result = settingsReducer(state, new RequestLogout(), makeEnv());

      expect(result.state === state).assertTrue();
      expect(result.effects.length).assertEqual(0);
    });

    it('cancelLogout_hidesConfirm', 0, () => {
      const options: SettingsUiStateOptions = { showLogoutConfirm: true };
      const state = SettingsUiState.initial().copyWith(options);
      const result = settingsReducer(state, new CancelLogout(), makeEnv());

      expect(result.state.showLogoutConfirm).assertFalse();
      expect(result.effects.length).assertEqual(0);
    });

    it('cancelLogout_notShowing_isNoOp', 0, () => {
      const state = SettingsUiState.initial();
      const result = settingsReducer(state, new CancelLogout(), makeEnv());

      expect(result.state === state).assertTrue();
      expect(result.effects.length).assertEqual(0);
    });

    it('confirmLogout_setsLoggingOutAndEmitsEffect', 0, () => {
      const options: SettingsUiStateOptions = { showLogoutConfirm: true };
      const state = SettingsUiState.initial().copyWith(options);
      const result = settingsReducer(state, new ConfirmLogout(), makeEnv());

      expect(result.state.isLoggingOut).assertTrue();
      expect(result.state.showLogoutConfirm).assertFalse();
      expect(result.effects.length).assertEqual(1);
      expect(result.effects[0].kind).assertEqual('logout');
    });

    it('confirmLogout_alreadyLoggingOut_isNoOp', 0, () => {
      const options: SettingsUiStateOptions = { isLoggingOut: true };
      const state = SettingsUiState.initial().copyWith(options);
      const result = settingsReducer(state, new ConfirmLogout(), makeEnv());

      expect(result.state === state).assertTrue();
      expect(result.effects.length).assertEqual(0);
    });

    it('clearCacheRequested_emitsClearCacheEffect', 0, () => {
      const state = SettingsUiState.initial();
      const result = settingsReducer(state, new ClearCacheRequested(), makeEnv());

      expect(result.state === state).assertTrue();
      expect(result.effects.length).assertEqual(1);
      expect(result.effects[0].kind).assertEqual('clearCache');
    });

    it('cacheCleared_updatesSizeAndShowsToast', 0, () => {
      const options: SettingsUiStateOptions = { storageCacheSize: '150 MB' };
      const state = SettingsUiState.initial().copyWith(options);
      const result = settingsReducer(state, new CacheCleared('0 B'), makeEnv());

      expect(result.state.storageCacheSize).assertEqual('0 B');
      expect(result.effects.length).assertEqual(1);
      expect(result.effects[0].kind).assertEqual('showToast');
    });

    it('setErrorMessage_updatesErrorAndResetsLoading', 0, () => {
      const options: SettingsUiStateOptions = { isLoading: true, isLoggingOut: true };
      const state = SettingsUiState.initial().copyWith(options);
      const result = settingsReducer(state, new SetErrorMessage('Connection timed out'), makeEnv());

      expect(result.state.isLoading).assertFalse();
      expect(result.state.isLoggingOut).assertFalse();
      expect(result.state.errorMessage).assertEqual('Connection timed out');
      expect(result.effects.length).assertEqual(0);
    });

    it('reducer_doesNotMutateInputState', 0, () => {
      const state = SettingsUiState.initial();
      const userIdBefore = state.userId;
      const notificationsBefore = state.notificationsEnabled;
      const themeBefore = state.themeMode;

      settingsReducer(state, new ToggleNotifications(), makeEnv());
      settingsReducer(state, new ChangeThemeMode('dark'), makeEnv());
      settingsReducer(state, new RequestLogout(), makeEnv());

      expect(state.userId).assertEqual(userIdBefore);
      expect(state.notificationsEnabled).assertEqual(notificationsBefore);
      expect(state.themeMode).assertEqual(themeBefore);
    });

    it('reducer_isPure_sameInputsProduceIdenticalOutputs', 0, () => {
      const state = SettingsUiState.initial();
      const intent = new ToggleNotifications();
      const r1 = settingsReducer(state, intent, makeEnv(100, 200));
      const r2 = settingsReducer(state, intent, makeEnv(100, 200));

      expect(r1.state.notificationsEnabled).assertEqual(r2.state.notificationsEnabled);
      expect(r1.effects.length).assertEqual(r2.effects.length);
      expect((r1.effects[0] as ShowToastEffect).message).assertEqual((r2.effects[0] as ShowToastEffect).message);
    });
  });
}
