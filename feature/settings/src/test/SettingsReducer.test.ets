import { describe, it, expect } from '@ohos/hypium';
import { ThemeManager, LightTheme, DarkTheme } from '@tgx/core-design-system';
import { Lang, ManualClock, SequentialIdGenerator } from '@tgx/core-common';
import { ReducerEnv } from '@tgx/feature-template';
import { SettingsUiState, SettingsUiStateOptions } from '../main/ets/contract/SettingsUiState';
import {
  CacheCleared,
  CancelLogout,
  ChangeLanguage,
  ChangeThemeMode,
  ClearCacheRequested,
  CloseAccountSwitcher,
  ConfirmLogout,
  LoadNotificationSettings,
  LoadStorageStats,
  LoadUserProfile,
  NotificationSettingsLoaded,
  NotificationSettingsUpdated,
  NotificationSettingsUpdateFailed,
  OpenAccountSwitcher,
  ProfileLoaded,
  RequestAddAccount,
  RequestLogout,
  SetAvailableAccounts,
  SetErrorMessage,
  SetLanguage,
  StorageStatsLoaded,
  SwitchAccount,
  ToggleNotifications,
  UserProfileData
} from '../main/ets/contract/SettingsIntent';
import {
  ClearCacheEffect,
  LoadNotificationSettingsEffect,
  LoadProfileEffect,
  LoadStorageStatsEffect,
  LogoutEffect,
  RequestAddAccountEffect,
  SetNotificationsEnabledEffect,
  ShowToastEffect,
  SwitchAccountEffect
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
      expect(state.isUpdatingNotifications).assertTrue();
      expect(state.storageCacheSize).assertEqual('0 B');
      expect(state.themeMode).assertEqual('system');
      expect(state.appVersion).assertEqual('1.0.0');
      expect(state.isLoading).assertFalse();
      expect(state.isLoggingOut).assertFalse();
      expect(state.errorMessage).assertNull();
      expect(state.showLogoutConfirm).assertFalse();
      expect(state.availableAccounts.length).assertEqual(0);
      expect(state.currentAccountKey).assertEqual('');
      expect(state.showAccountSwitcher).assertFalse();
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

    it('loadNotificationSettings_emitsLoadEffect', 0, () => {
      const state = SettingsUiState.initial();
      const result = settingsReducer(state, new LoadNotificationSettings(), makeEnv());

      expect(result.state === state).assertTrue();
      expect(result.effects.length).assertEqual(1);
      expect((result.effects[0] as LoadNotificationSettingsEffect).kind)
        .assertEqual('loadNotificationSettings');
    });

    it('toggleNotifications_waitsForTdlibBeforeChangingValue', 0, () => {
      const state = SettingsUiState.initial().copyWith({ isUpdatingNotifications: false });
      expect(state.notificationsEnabled).assertTrue();

      const result = settingsReducer(state, new ToggleNotifications(), makeEnv());
      expect(result.state.notificationsEnabled).assertTrue();
      expect(result.state.isUpdatingNotifications).assertTrue();
      expect(result.effects.length).assertEqual(1);
      const effect: SetNotificationsEnabledEffect = result.effects[0] as SetNotificationsEnabledEffect;
      expect(effect.kind).assertEqual('setNotificationsEnabled');
      expect(effect.enabled).assertFalse();
    });

    it('toggleNotifications_whileUpdating_isIdempotent', 0, () => {
      const state = SettingsUiState.initial();
      const result = settingsReducer(state, new ToggleNotifications(), makeEnv());

      expect(result.state === state).assertTrue();
      expect(result.effects.length).assertEqual(0);
    });

    it('notificationSettingsLoaded_reflectsAllScopeState', 0, () => {
      const state = SettingsUiState.initial();
      const result = settingsReducer(state, new NotificationSettingsLoaded(false), makeEnv());

      expect(result.state.notificationsEnabled).assertFalse();
      expect(result.state.isUpdatingNotifications).assertFalse();
      expect(result.effects.length).assertEqual(0);
    });

    it('notificationSettingsUpdated_commitsValueAndEmitsToast', 0, () => {
      const state = SettingsUiState.initial().copyWith({
        notificationsEnabled: true,
        isUpdatingNotifications: true
      });
      const result = settingsReducer(state, new NotificationSettingsUpdated(false), makeEnv());

      expect(result.state.notificationsEnabled).assertFalse();
      expect(result.state.isUpdatingNotifications).assertFalse();
      expect(result.effects.length).assertEqual(1);
      expect((result.effects[0] as ShowToastEffect).message).assertEqual('Notifications disabled');
    });

    it('notificationSettingsUpdateFailed_keepsValueAndUnlocksToggle', 0, () => {
      const state = SettingsUiState.initial().copyWith({ isUpdatingNotifications: true });
      const result = settingsReducer(
        state,
        new NotificationSettingsUpdateFailed('Unable to update notification settings.'),
        makeEnv()
      );

      expect(result.state.notificationsEnabled).assertTrue();
      expect(result.state.isUpdatingNotifications).assertFalse();
      expect(result.state.errorMessage).assertEqual('Unable to update notification settings.');
      expect(result.effects.length).assertEqual(0);
    });

    it('changeThemeMode_updatesThemeAndEmitsToast', 0, () => {
      ThemeManager.getInstance().reset();
      const state = SettingsUiState.initial();
      const result = settingsReducer(state, new ChangeThemeMode('dark'), makeEnv());

      expect(result.state.themeMode).assertEqual('dark');
      expect(result.effects.length).assertEqual(1);
      expect(result.effects[0].kind).assertEqual('showToast');
      expect((result.effects[0] as ShowToastEffect).message).assertEqual('Theme mode set to dark');
      expect(ThemeManager.getInstance().getPreference()).assertEqual('dark');
      expect(ThemeManager.getInstance().getEffectiveTheme()).assertEqual(DarkTheme);
    });

    it('changeThemeMode_toLight_syncsThemeManagerAndEmitsToast', 0, () => {
      ThemeManager.getInstance().reset();
      const state = SettingsUiState.initial().copyWith({ themeMode: 'dark' });
      ThemeManager.getInstance().setPreference('dark');

      const result = settingsReducer(state, new ChangeThemeMode('light'), makeEnv());

      expect(result.state.themeMode).assertEqual('light');
      expect(ThemeManager.getInstance().getPreference()).assertEqual('light');
      expect(ThemeManager.getInstance().getEffectiveTheme()).assertEqual(LightTheme);
      expect((result.effects[0] as ShowToastEffect).message).assertEqual('Theme mode set to light');
    });

    it('changeThemeMode_toSystem_syncsThemeManagerAndEmitsToast', 0, () => {
      ThemeManager.getInstance().reset();
      const state = SettingsUiState.initial().copyWith({ themeMode: 'light' });
      ThemeManager.getInstance().setPreference('light');

      const result = settingsReducer(state, new ChangeThemeMode('system'), makeEnv());

      expect(result.state.themeMode).assertEqual('system');
      expect(ThemeManager.getInstance().getPreference()).assertEqual('system');
      expect((result.effects[0] as ShowToastEffect).message).assertEqual('Theme mode set to system');
    });

    it('changeThemeMode_sameMode_isNoOp', 0, () => {
      ThemeManager.getInstance().reset();
      const options: SettingsUiStateOptions = { themeMode: 'dark' };
      const state = SettingsUiState.initial().copyWith(options);
      const result = settingsReducer(state, new ChangeThemeMode('dark'), makeEnv());

      expect(result.state === state).assertTrue();
      expect(result.effects.length).assertEqual(0);
    });

    it('initialState_respectsExplicitThemeMode', 0, () => {
      const state = SettingsUiState.initial('dark');
      expect(state.themeMode).assertEqual('dark');
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
      const state = SettingsUiState.initial().copyWith({ isUpdatingNotifications: false });
      const intent = new ToggleNotifications();
      const r1 = settingsReducer(state, intent, makeEnv(100, 200));
      const r2 = settingsReducer(state, intent, makeEnv(100, 200));

      expect(r1.state.notificationsEnabled).assertEqual(r2.state.notificationsEnabled);
      expect(r1.effects.length).assertEqual(r2.effects.length);
      expect(r1.effects[0].kind).assertEqual(r2.effects[0].kind);
      expect((r1.effects[0] as SetNotificationsEnabledEffect).enabled)
        .assertEqual((r2.effects[0] as SetNotificationsEnabledEffect).enabled);
    });

    // ---- SET-104 存储占用 ----

    it('loadStorageStats_emitsEffectWithoutTouchingState', 0, () => {
      // 静默刷新：只出 effect，不动 UI 状态（不置 isLoading，避免打断其它区块）
      const state = SettingsUiState.initial();
      const result = settingsReducer(state, new LoadStorageStats(), makeEnv());

      expect(result.state === state).assertTrue();
      expect(result.effects.length).assertEqual(1);
      expect(result.effects[0].kind).assertEqual('loadStorageStats');
    });

    it('storageStatsLoaded_writesFormattedLabel', 0, () => {
      const state = SettingsUiState.initial();
      const result = settingsReducer(
        state,
        new StorageStatsLoaded('12.3 MB · 45 files'),
        makeEnv()
      );

      expect(result.state.storageCacheSize).assertEqual('12.3 MB · 45 files');
      expect(result.effects.length).assertEqual(0);
    });

    it('storageStatsLoaded_replacesStalePlaceholder', 0, () => {
      // 初始硬编码占位 '0 B' 必须被真实值覆盖
      const state = SettingsUiState.initial();
      expect(state.storageCacheSize).assertEqual('0 B');

      const result = settingsReducer(state, new StorageStatsLoaded('1.5 KB · 2 files'), makeEnv());
      expect(result.state.storageCacheSize).assertEqual('1.5 KB · 2 files');
    });

    it('cacheCleared_usesReturnedStatisticsNotHardcodedZero', 0, () => {
      // 清理后显示的是 TDLib 返回的真实剩余占用（数据库/语言包不会被清掉，
      // 真实值通常非 0）——不再是此前硬编码的 '0 B'
      const state = SettingsUiState.initial().copyWith({ storageCacheSize: '500.0 MB · 900 files' });
      const result = settingsReducer(state, new CacheCleared('48.2 MB · 120 files'), makeEnv());

      expect(result.state.storageCacheSize).assertEqual('48.2 MB · 120 files');
      expect(result.effects.length).assertEqual(1);
      expect((result.effects[0] as ShowToastEffect).message).assertEqual('Cache cleared');
    });

    it('clearCacheRequested_stillEmitsClearEffect', 0, () => {
      const state = SettingsUiState.initial();
      const result = settingsReducer(state, new ClearCacheRequested(), makeEnv());

      expect(result.effects.length).assertEqual(1);
      expect(result.effects[0].kind).assertEqual('clearCache');
    });

    // ---- ACC-101 多账号支持 ----

    it('openAccountSwitcher_setsShowAccountSwitcherTrue', 0, () => {
      const state = SettingsUiState.initial();
      expect(state.showAccountSwitcher).assertFalse();

      const result = settingsReducer(state, new OpenAccountSwitcher(), makeEnv());
      expect(result.state.showAccountSwitcher).assertTrue();
      expect(result.effects.length).assertEqual(0);
    });

    it('openAccountSwitcher_alreadyShowing_isNoOp', 0, () => {
      const state = SettingsUiState.initial().copyWith({ showAccountSwitcher: true });
      const result = settingsReducer(state, new OpenAccountSwitcher(), makeEnv());

      expect(result.state === state).assertTrue();
      expect(result.effects.length).assertEqual(0);
    });

    it('closeAccountSwitcher_setsShowAccountSwitcherFalse', 0, () => {
      const state = SettingsUiState.initial().copyWith({ showAccountSwitcher: true });
      const result = settingsReducer(state, new CloseAccountSwitcher(), makeEnv());

      expect(result.state.showAccountSwitcher).assertFalse();
      expect(result.effects.length).assertEqual(0);
    });

    it('closeAccountSwitcher_notShowing_isNoOp', 0, () => {
      const state = SettingsUiState.initial();
      const result = settingsReducer(state, new CloseAccountSwitcher(), makeEnv());

      expect(result.state === state).assertTrue();
      expect(result.effects.length).assertEqual(0);
    });

    it('switchAccount_updatesCurrentAccountKey_closesSwitcher_andEmitsEffect', 0, () => {
      const state = SettingsUiState.initial('system', 'system', 'en', 'default', ['default', 'account_2'])
        .copyWith({ showAccountSwitcher: true });

      const result = settingsReducer(state, new SwitchAccount('account_2'), makeEnv());

      expect(result.state.currentAccountKey).assertEqual('account_2');
      expect(result.state.showAccountSwitcher).assertFalse();
      expect(result.effects.length).assertEqual(1);
      expect(result.effects[0].kind).assertEqual('switchAccount');
      expect((result.effects[0] as SwitchAccountEffect).accountKey).assertEqual('account_2');
    });

    it('requestAddAccount_closesSwitcher_andEmitsEffect', 0, () => {
      const state = SettingsUiState.initial().copyWith({ showAccountSwitcher: true });
      const result = settingsReducer(state, new RequestAddAccount(), makeEnv());

      expect(result.state.showAccountSwitcher).assertFalse();
      expect(result.effects.length).assertEqual(1);
      expect(result.effects[0].kind).assertEqual('requestAddAccount');
    });

    it('setAvailableAccounts_updatesAccountsAndCurrentKey', 0, () => {
      const state = SettingsUiState.initial();
      const accounts: string[] = ['acc_1', 'acc_2', 'acc_3'];
      const result = settingsReducer(state, new SetAvailableAccounts(accounts, 'acc_2'), makeEnv());

      expect(result.state.availableAccounts.length).assertEqual(3);
      expect(result.state.availableAccounts[0]).assertEqual('acc_1');
      expect(result.state.availableAccounts[1]).assertEqual('acc_2');
      expect(result.state.availableAccounts[2]).assertEqual('acc_3');
      expect(result.state.currentAccountKey).assertEqual('acc_2');
      expect(result.effects.length).assertEqual(0);
    });

    it('setAvailableAccounts_preservesCurrentKeyWhenOmitted', 0, () => {
      const state = SettingsUiState.initial('system', 'system', 'en', 'primary_acc');
      const accounts: string[] = ['primary_acc', 'second_acc'];
      const result = settingsReducer(state, new SetAvailableAccounts(accounts), makeEnv());

      expect(result.state.availableAccounts.length).assertEqual(2);
      expect(result.state.currentAccountKey).assertEqual('primary_acc');
    });
  });
}
