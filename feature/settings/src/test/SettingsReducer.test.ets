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
  NotificationScopeUpdated,
  NotificationScopeUpdateFailed,
  NotificationSettingsLoaded,
  NotificationSettingsUpdated,
  NotificationSettingsUpdateFailed,
  OpenAccountSwitcher,
  OpenDevicesPage,
  CloseDevicesPage,
  LoadActiveSessions,
  ActiveSessionsLoaded,
  ActiveSessionsLoadFailed,
  TerminateSessionIntent,
  TerminateAllOtherSessionsIntent,
  ProfileLoaded,
  RequestAddAccount,
  SectionFocused,
  RequestLogout,
  SetAvailableAccounts,
  SetErrorMessage,
  SetLanguage,
  StorageStatsLoaded,
  SwitchAccount,
  ToggleNotificationScope,
  ToggleNotifications,
  OpenPrivacyPage,
  ClosePrivacyPage,
  LoadPrivacySettings,
  PrivacySettingsLoaded,
  TogglePrivacySetting,
  PrivacySettingUpdated,
  PrivacySettingUpdateFailed,
  OpenProxyPage,
  CloseProxyPage,
  LoadProxies,
  ProxiesLoaded,
  SelectProxy,
  SaveProxy,
  RemoveProxyRequested,
  OpenAutoDownloadPage,
  CloseAutoDownloadPage,
  LoadAutoDownloadPolicy,
  AutoDownloadPolicyLoaded,
  SetAutoDownloadKind,
  LoadDataSaverSettings,
  DataSaverSettingsLoaded,
  SetDataSaverFlag,
  LoadDownloadLimits,
  DownloadLimitsLoaded,
  SetDownloadLimitSize,
  SetDownloadLimitExclusion,
  UserProfileData
} from '../main/ets/contract/SettingsIntent';
import {
  ClearCacheEffect,
  LoadActiveSessionsEffect,
  LoadNotificationSettingsEffect,
  LoadProfileEffect,
  LoadStorageStatsEffect,
  LogoutEffect,
  RequestAddAccountEffect,
  SetNotificationScopeEnabledEffect,
  SetNotificationsEnabledEffect,
  ShowToastEffect,
  SwitchAccountEffect,
  TerminateAllOtherSessionsEffect,
  TerminateSessionEffect,
  SetPrivacySettingEffect,
  LoadProxiesEffect,
  EnableProxyEffect,
  DisableProxyEffect,
  SaveProxyEffect,
  RemoveProxyEffect,
  LoadAutoDownloadPolicyEffect,
  PersistAutoDownloadPolicyEffect,
  LoadDataSaverSettingsEffect,
  PersistDataSaverSettingsEffect,
  LoadDownloadLimitsEffect,
  PersistDownloadLimitsEffect
} from '../main/ets/contract/SettingsEffect';
import {
  AutoDownloadFlags,
  AutoDownloadPolicy,
  DATA_SAVER_FLAG_ENABLED,
  DATA_SAVER_FLAG_WHEN_MOBILE,
  DATA_SAVER_FLAG_WHEN_ROAMING,
  DataSaverSettings,
  DOWNLOAD_LIMIT_1MB,
  DOWNLOAD_LIMIT_50MB,
  DOWNLOAD_LIMIT_NONE,
  DownloadLimitsByNetwork,
  NetworkDownloadLimits
} from '@tgx/core-domain';
import { ActiveSessionItem } from '../main/ets/model/ActiveSessionItem';
import { PrivacySettingItem } from '../main/ets/model/PrivacySettings';
import {
  PROXY_NONE_ID,
  PROXY_NEW_ID,
  ProxyForm,
  ProxyItem,
  ProxyKind
} from '../main/ets/model/ProxySettings';
import { settingsReducer } from '../main/ets/reducer/SettingsReducer';

function makeEnv(nowMillis: number = 1000, monotonicMillis: number = 500): ReducerEnv {
  const env: ReducerEnv = {
    clock: new ManualClock(nowMillis, monotonicMillis),
    ids: new SequentialIdGenerator('settings-test-')
  };
  return env;
}

/** SELF-102：已加载到隐私行、且首屏加载结束的起始态。 */
function privacyState(items: PrivacySettingItem[]): SettingsUiState {
  return SettingsUiState.initial().copyWith({
    privacyItems: items,
    isLoadingPrivacy: false
  });
}

/** PROXY-101：已读到代理列表、首屏加载结束的起始态。 */
function proxyState(items: ProxyItem[]): SettingsUiState {
  return SettingsUiState.initial().copyWith({
    proxyItems: items,
    showProxyPage: true,
    isLoadingProxies: false
  });
}

function proxyRow(
  id: number,
  kind: ProxyKind,
  server: string,
  port: number,
  isEnabled: boolean
): ProxyItem {
  return new ProxyItem(id, kind, server, port, '', '', '', false, '', isEnabled);
}

function proxyFormItem(id: number, server: string, port: string, kind: ProxyKind): ProxyForm {
  return new ProxyForm(id, kind, server, port, '', '', '', false, '', true);
}

/** AUTODL-101：已经读到盘上策略、子页已打开的起始态。 */
function autoDownloadState(policy: AutoDownloadPolicy | null): SettingsUiState {
  return SettingsUiState.initial().copyWith({
    showAutoDownloadPage: true,
    autoDownloadPolicy: policy
  });
}

/** AUTODL-102：已经读到盘上省流量设置的起始态（与策略同页，页已打开）。 */
function dataSaverState(settings: DataSaverSettings | null): SettingsUiState {
  return SettingsUiState.initial().copyWith({
    showAutoDownloadPage: true,
    dataSaverSettings: settings
  });
}

/** AUTODL-103：已经读到盘上按网络档限制的起始态（同一张子页）。 */
function downloadLimitsState(limits: DownloadLimitsByNetwork | null): SettingsUiState {
  return SettingsUiState.initial().copyWith({
    showAutoDownloadPage: true,
    downloadLimits: limits
  });
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
      expect(state.privateNotificationsEnabled).assertTrue();
      expect(state.groupNotificationsEnabled).assertTrue();
      expect(state.channelNotificationsEnabled).assertTrue();
      expect(state.isUpdatingNotifications).assertTrue();
      expect(state.updatingNotificationScope).assertNull();
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
      const result = settingsReducer(
        state,
        new NotificationSettingsLoaded(false, true, false, true),
        makeEnv()
      );

      expect(result.state.notificationsEnabled).assertFalse();
      expect(result.state.privateNotificationsEnabled).assertTrue();
      expect(result.state.groupNotificationsEnabled).assertFalse();
      expect(result.state.channelNotificationsEnabled).assertTrue();
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
      expect(result.state.privateNotificationsEnabled).assertFalse();
      expect(result.state.groupNotificationsEnabled).assertFalse();
      expect(result.state.channelNotificationsEnabled).assertFalse();
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

    it('toggleNotificationScope_waitsForTdlibAndTargetsOneScope', 0, () => {
      const state = SettingsUiState.initial().copyWith({ isUpdatingNotifications: false });
      const result = settingsReducer(state, new ToggleNotificationScope('group'), makeEnv());

      expect(result.state.groupNotificationsEnabled).assertTrue();
      expect(result.state.updatingNotificationScope).assertEqual('group');
      expect(result.effects.length).assertEqual(1);
      const effect: SetNotificationScopeEnabledEffect =
        result.effects[0] as SetNotificationScopeEnabledEffect;
      expect(effect.kind).assertEqual('setNotificationScopeEnabled');
      expect(effect.scope).assertEqual('group');
      expect(effect.enabled).assertFalse();
    });

    it('notificationScopeUpdated_updatesAggregateState', 0, () => {
      const state = SettingsUiState.initial().copyWith({
        isUpdatingNotifications: false,
        updatingNotificationScope: 'private'
      });
      const result = settingsReducer(state, new NotificationScopeUpdated('private', false), makeEnv());

      expect(result.state.privateNotificationsEnabled).assertFalse();
      expect(result.state.groupNotificationsEnabled).assertTrue();
      expect(result.state.channelNotificationsEnabled).assertTrue();
      expect(result.state.notificationsEnabled).assertFalse();
      expect(result.state.updatingNotificationScope).assertNull();
      expect(result.effects.length).assertEqual(0);
    });

    it('notificationScopeUpdateFailed_preservesScopeAndUnlocksControls', 0, () => {
      const state = SettingsUiState.initial().copyWith({
        isUpdatingNotifications: false,
        updatingNotificationScope: 'channel'
      });
      const result = settingsReducer(
        state,
        new NotificationScopeUpdateFailed('channel', 'Unable to update notification settings.'),
        makeEnv()
      );

      expect(result.state.channelNotificationsEnabled).assertTrue();
      expect(result.state.updatingNotificationScope).assertNull();
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

    it('openDevicesPage_opensSubPage_startsLoading_andEmitsEffect', 0, () => {
      const state = SettingsUiState.initial();
      const result = settingsReducer(state, new OpenDevicesPage(), makeEnv());

      expect(result.state.showDevicesPage).assertTrue();
      expect(result.state.isLoadingSessions).assertTrue();
      expect(result.state.errorMessage).assertNull();
      expect(result.effects.length).assertEqual(1);
      expect(result.effects[0].kind).assertEqual('loadActiveSessions');
    });

    it('closeDevicesPage_resetsShowDevicesPageFlag', 0, () => {
      const state = SettingsUiState.initial().copyWith({ showDevicesPage: true });
      const result = settingsReducer(state, new CloseDevicesPage(), makeEnv());

      expect(result.state.showDevicesPage).assertFalse();
      expect(result.effects.length).assertEqual(0);
    });

    it('loadActiveSessions_setsLoadingFlag_andEmitsEffect', 0, () => {
      const state = SettingsUiState.initial();
      const result = settingsReducer(state, new LoadActiveSessions(), makeEnv());

      expect(result.state.isLoadingSessions).assertTrue();
      expect(result.effects.length).assertEqual(1);
      expect(result.effects[0].kind).assertEqual('loadActiveSessions');
    });

    it('activeSessionsLoaded_populatesSessions_andClearsLoading', 0, () => {
      const state = SettingsUiState.initial().copyWith({ isLoadingSessions: true });
      const mockSessions: ActiveSessionItem[] = [
        {
          id: 's1',
          isCurrent: true,
          deviceModel: 'HUAWEI Mate 60 Pro',
          platform: 'HarmonyOS NEXT',
          applicationName: 'Telegram X',
          applicationVersion: '0.26.8',
          ipAddress: '10.0.0.1',
          location: 'Shenzhen, China',
          lastActiveDate: 1726500000
        },
        {
          id: 's2',
          isCurrent: false,
          deviceModel: 'MacBook Pro',
          platform: 'macOS',
          applicationName: 'Telegram Desktop',
          applicationVersion: '4.14.0',
          ipAddress: '10.0.0.2',
          location: 'Shenzhen, China',
          lastActiveDate: 1726490000
        }
      ];
      const result = settingsReducer(state, new ActiveSessionsLoaded(mockSessions), makeEnv());

      expect(result.state.isLoadingSessions).assertFalse();
      expect(result.state.activeSessions.length).assertEqual(2);
      expect(result.state.activeSessions[0].id).assertEqual('s1');
      expect(result.state.activeSessions[0].isCurrent).assertTrue();
      expect(result.state.activeSessions[1].id).assertEqual('s2');
      expect(result.state.activeSessions[1].isCurrent).assertFalse();
      expect(result.effects.length).assertEqual(0);
    });

    it('activeSessionsLoadFailed_clearsLoading_andSetsErrorMessage', 0, () => {
      const state = SettingsUiState.initial().copyWith({ isLoadingSessions: true });
      const result = settingsReducer(state, new ActiveSessionsLoadFailed('Network timeout'), makeEnv());

      expect(result.state.isLoadingSessions).assertFalse();
      expect(result.state.errorMessage).assertEqual('Network timeout');
      expect(result.effects.length).assertEqual(0);
    });

    it('terminateSession_emitsTerminateSessionEffectWithId', 0, () => {
      const state = SettingsUiState.initial();
      const result = settingsReducer(state, new TerminateSessionIntent('session_12345'), makeEnv());

      expect(result.state === state).assertTrue();
      expect(result.effects.length).assertEqual(1);
      expect(result.effects[0].kind).assertEqual('terminateSession');
      expect((result.effects[0] as TerminateSessionEffect).sessionId).assertEqual('session_12345');
    });

    it('terminateAllOtherSessions_emitsTerminateAllOtherSessionsEffect', 0, () => {
      const state = SettingsUiState.initial();
      const result = settingsReducer(state, new TerminateAllOtherSessionsIntent(), makeEnv());

      expect(result.state === state).assertTrue();
      expect(result.effects.length).assertEqual(1);
      expect(result.effects[0].kind).assertEqual('terminateAllOtherSessions');
    });

    it('sectionFocused_notificationsSwitchesSectionWithoutEffects', 0, () => {
      const state = SettingsUiState.initial();
      expect(state.section).assertEqual('all');

      const result = settingsReducer(state, new SectionFocused('notifications'), makeEnv());
      expect(result.state.section).assertEqual('notifications');
      expect(result.effects.length).assertEqual(0);
    });

    it('sectionFocused_dataAndStorageSwitchesSection', 0, () => {
      const state = SettingsUiState.initial();
      const result = settingsReducer(state, new SectionFocused('data_and_storage'), makeEnv());
      expect(result.state.section).assertEqual('data_and_storage');
      expect(result.state.showDevicesPage).assertFalse();
    });

    it('sectionFocused_devicesOpensActiveSessionsSubPage', 0, () => {
      const state = SettingsUiState.initial();
      const result = settingsReducer(state, new SectionFocused('devices'), makeEnv());

      // 设备行的落点是既有的整屏活跃会话子页：分区保持 'all'，并触发会话拉取。
      expect(result.state.section).assertEqual('all');
      expect(result.state.showDevicesPage).assertTrue();
      expect(result.state.isLoadingSessions).assertTrue();
      expect(result.effects.length).assertEqual(1);
      expect(result.effects[0].kind).assertEqual('loadActiveSessions');
    });

    it('sectionFocused_unknownSectionFallsBackToFullPage', 0, () => {
      const state = SettingsUiState.initial().copyWith({ section: 'notifications' });
      const result = settingsReducer(state, new SectionFocused('privacy_and_security_x'), makeEnv());
      expect(result.state.section).assertEqual('all');
      expect(result.state.showPrivacyPage).assertFalse();
    });

    it('copyWith_keepsSectionWhenUnspecified', 0, () => {
      const state = SettingsUiState.initial().copyWith({ section: 'data_and_storage' });
      const next = state.copyWith({ displayName: 'hubery' });
      expect(next.section).assertEqual('data_and_storage');
      expect(next.displayName).assertEqual('hubery');
    });

    // ---- SELF-102 隐私和安全 ----

    it('openPrivacyPage_opensSubPage_startsLoading_andEmitsEffect', 0, () => {
      const result = settingsReducer(SettingsUiState.initial(), new OpenPrivacyPage(), makeEnv());

      expect(result.state.showPrivacyPage).assertTrue();
      expect(result.state.isLoadingPrivacy).assertTrue();
      expect(result.effects.length).assertEqual(1);
      expect(result.effects[0].kind).assertEqual('loadPrivacySettings');
    });

    it('closePrivacyPage_onlyTogglesFlag', 0, () => {
      const state = privacyState([]).copyWith({ showPrivacyPage: true });
      const result = settingsReducer(state, new ClosePrivacyPage(), makeEnv());

      expect(result.state.showPrivacyPage).assertFalse();
      // 关闭子页不得把已读到的档位清空：回到设置页时卡片副标题还要用。
      expect(result.state.privacyItems.length).assertEqual(0);
      expect(result.effects.length).assertEqual(0);
    });

    it('closePrivacyPage_whenAlreadyClosed_isIdentity', 0, () => {
      const state = privacyState([]);
      const result = settingsReducer(state, new ClosePrivacyPage(), makeEnv());
      expect(result.state === state).assertTrue();
    });

    it('loadPrivacySettings_setsLoadingFlag_andEmitsEffect', 0, () => {
      const result = settingsReducer(privacyState([]), new LoadPrivacySettings(), makeEnv());

      expect(result.state.isLoadingPrivacy).assertTrue();
      expect(result.effects.length).assertEqual(1);
      expect(result.effects[0].kind).assertEqual('loadPrivacySettings');
    });

    it('privacySettingsLoaded_populatesItems_andClearsLoading', 0, () => {
      const items: PrivacySettingItem[] = [
        new PrivacySettingItem('show_last_seen', 'contacts'),
        new PrivacySettingItem('allow_calls', 'everybody')
      ];
      const state = SettingsUiState.initial().copyWith({ isLoadingPrivacy: true });
      const result = settingsReducer(state, new PrivacySettingsLoaded(items), makeEnv());

      expect(result.state.privacyItems.length).assertEqual(2);
      expect(result.state.privacyItems[0].choice).assertEqual('contacts');
      expect(result.state.privacyItems[1].choice).assertEqual('everybody');
      expect(result.state.isLoadingPrivacy).assertFalse();
    });

    it('togglePrivacySetting_writesNextChoice_andMarksRowBusy', 0, () => {
      const state = privacyState([new PrivacySettingItem('show_last_seen', 'everybody')]);
      const result = settingsReducer(state, new TogglePrivacySetting('show_last_seen'), makeEnv());

      expect(result.state.updatingPrivacyKey).assertEqual('show_last_seen');
      expect(result.effects.length).assertEqual(1);
      const effect = result.effects[0] as SetPrivacySettingEffect;
      expect(effect.kind).assertEqual('setPrivacySetting');
      expect(effect.key).assertEqual('show_last_seen');
      expect(effect.choice).assertEqual('contacts');
      // 写回成功前不改显示档位：界面必须反映服务端值而不是猜的值。
      expect(result.state.privacyItems[0].choice).assertEqual('everybody');
    });

    it('togglePrivacySetting_ignoresWhileAnotherRowIsUpdating', 0, () => {
      const state = privacyState([
        new PrivacySettingItem('show_last_seen', 'everybody'),
        new PrivacySettingItem('allow_calls', 'contacts')
      ]).copyWith({ updatingPrivacyKey: 'show_last_seen' });
      const result = settingsReducer(state, new TogglePrivacySetting('allow_calls'), makeEnv());

      expect(result.state === state).assertTrue();
      expect(result.effects.length).assertEqual(0);
    });

    it('togglePrivacySetting_ignoresUnknownRowKey', 0, () => {
      // 该项还没读到（首屏加载中）：点了不能凭默认值写服务端。
      const state = privacyState([new PrivacySettingItem('show_bio', 'nobody')]);
      const result = settingsReducer(state, new TogglePrivacySetting('allow_calls'), makeEnv());

      expect(result.state === state).assertTrue();
      expect(result.effects.length).assertEqual(0);
    });

    it('togglePrivacySetting_fromCustom_resetsToContacts', 0, () => {
      const state = privacyState([new PrivacySettingItem('show_phone_number', 'custom')]);
      const result = settingsReducer(state, new TogglePrivacySetting('show_phone_number'), makeEnv());

      const effect = result.effects[0] as SetPrivacySettingEffect;
      expect(effect.choice).assertEqual('contacts');
    });

    it('privacySettingUpdated_replacesSingleRowAndKeepsOthers', 0, () => {
      const state = privacyState([
        new PrivacySettingItem('show_last_seen', 'everybody'),
        new PrivacySettingItem('allow_calls', 'nobody')
      ]).copyWith({ updatingPrivacyKey: 'show_last_seen' });
      const result = settingsReducer(
        state,
        new PrivacySettingUpdated('show_last_seen', 'nobody'),
        makeEnv()
      );

      expect(result.state.privacyItems[0].choice).assertEqual('nobody');
      expect(result.state.privacyItems[1].choice).assertEqual('nobody');
      expect(result.state.updatingPrivacyKey === null).assertTrue();
      expect(result.state.errorMessage === null).assertTrue();
    });

    it('privacySettingUpdateFailed_keepsShownChoice_andReportsError', 0, () => {
      const state = privacyState([new PrivacySettingItem('show_last_seen', 'everybody')])
        .copyWith({ updatingPrivacyKey: 'show_last_seen' });
      const result = settingsReducer(
        state,
        new PrivacySettingUpdateFailed('show_last_seen', 'Unable to update privacy settings.'),
        makeEnv()
      );

      expect(result.state.privacyItems[0].choice).assertEqual('everybody');
      expect(result.state.updatingPrivacyKey === null).assertTrue();
      expect(result.state.errorMessage).assertEqual('Unable to update privacy settings.');
    });

    it('sectionFocused_privacyOpensPrivacySubPage', 0, () => {
      const result = settingsReducer(SettingsUiState.initial(), new SectionFocused('privacy'), makeEnv());

      // SELF-101 的「隐私和安全」行落在整屏子页，和 devices 同构。
      expect(result.state.section).assertEqual('all');
      expect(result.state.showPrivacyPage).assertTrue();
      expect(result.state.isLoadingPrivacy).assertTrue();
      expect(result.effects.length).assertEqual(1);
      expect(result.effects[0].kind).assertEqual('loadPrivacySettings');
    });

    it('copyWith_keepsPrivacyFieldsWhenUnspecified', 0, () => {
      const state = privacyState([new PrivacySettingItem('show_bio', 'nobody')])
        .copyWith({ showPrivacyPage: true, updatingPrivacyKey: 'show_bio' });
      const next = state.copyWith({ displayName: 'hubery' });

      expect(next.privacyItems.length).assertEqual(1);
      expect(next.showPrivacyPage).assertTrue();
      expect(next.updatingPrivacyKey).assertEqual('show_bio');
      expect(next.isLoadingPrivacy).assertFalse();
    });

    // ---- PROXY-101 网络代理 ----

    it('initialState_hasProxyDefaults', 0, () => {
      const state = SettingsUiState.initial();
      expect(state.showProxyPage).assertFalse();
      expect(state.proxyItems.length).assertEqual(0);
      expect(state.isLoadingProxies).assertFalse();
      expect(state.updatingProxyId === null).assertTrue();
    });

    it('openProxyPage_opensSubPage_startsLoading_andEmitsEffect', 0, () => {
      const result = settingsReducer(SettingsUiState.initial(), new OpenProxyPage(), makeEnv());

      expect(result.state.showProxyPage).assertTrue();
      expect(result.state.isLoadingProxies).assertTrue();
      expect(result.state.errorMessage).assertNull();
      expect(result.effects.length).assertEqual(1);
      expect(result.effects[0].kind).assertEqual('loadProxies');
    });

    it('closeProxyPage_keepsLoadedItems', 0, () => {
      const state = proxyState([proxyRow(3, 'socks5', 'a.com', 1080, true)]);
      const result = settingsReducer(state, new CloseProxyPage(), makeEnv());

      expect(result.state.showProxyPage).assertFalse();
      // 设置主页「代理」行副标题要靠这份缓存，关闭子页不能清空。
      expect(result.state.proxyItems.length).assertEqual(1);
      expect(result.effects.length).assertEqual(0);
    });

    it('closeProxyPage_whenAlreadyClosed_isNoop', 0, () => {
      const state = SettingsUiState.initial();
      const result = settingsReducer(state, new CloseProxyPage(), makeEnv());

      expect(result.state === state).assertTrue();
      expect(result.effects.length).assertEqual(0);
    });

    it('loadProxies_setsLoadingAndEmitsEffect', 0, () => {
      const state = proxyState([]);
      const result = settingsReducer(state, new LoadProxies(), makeEnv());

      expect(result.state.isLoadingProxies).assertTrue();
      expect(result.effects.length).assertEqual(1);
      const effect = result.effects[0] as LoadProxiesEffect;
      expect(effect.kind).assertEqual('loadProxies');
    });

    it('proxiesLoaded_replacesItemsAndClearsBusy', 0, () => {
      const state = proxyState([proxyRow(1, 'socks5', 'old.com', 1, false)])
        .copyWith({ isLoadingProxies: true, updatingProxyId: 1 });
      const items: ProxyItem[] = [
        proxyRow(7, 'mtproto', 'new.com', 443, true),
        proxyRow(8, 'http', 'b.com', 8080, false)
      ];
      const result = settingsReducer(state, new ProxiesLoaded(items), makeEnv());

      expect(result.state.proxyItems.length).assertEqual(2);
      expect(result.state.proxyItems[0].id).assertEqual(7);
      expect(result.state.isLoadingProxies).assertFalse();
      expect(result.state.updatingProxyId === null).assertTrue();
      expect(result.effects.length).assertEqual(0);
    });

    it('selectProxy_unenabledRow_enablesAndMarksBusy', 0, () => {
      const state = proxyState([
        proxyRow(7, 'socks5', 'a.com', 1080, true),
        proxyRow(8, 'socks5', 'b.com', 1080, false)
      ]);
      const result = settingsReducer(state, new SelectProxy(8), makeEnv());

      expect(result.state.updatingProxyId).assertEqual(8);
      expect(result.effects.length).assertEqual(1);
      const effect = result.effects[0] as EnableProxyEffect;
      expect(effect.kind).assertEqual('enableProxy');
      expect(effect.proxyId).assertEqual(8);
      // 单选态由写回后的回读校正，不在这里乐观改行。
      expect(result.state.proxyItems[0].isEnabled).assertTrue();
      expect(result.state.proxyItems[1].isEnabled).assertFalse();
    });

    it('selectProxy_noneRow_disables', 0, () => {
      const state = proxyState([proxyRow(7, 'socks5', 'a.com', 1080, true)]);
      const result = settingsReducer(state, new SelectProxy(PROXY_NONE_ID), makeEnv());

      expect(result.state.updatingProxyId).assertEqual(PROXY_NONE_ID);
      expect(result.effects.length).assertEqual(1);
      expect((result.effects[0] as DisableProxyEffect).kind).assertEqual('disableProxy');
    });

    it('selectProxy_alreadyEnabledOrUnknown_isNoop', 0, () => {
      const state = proxyState([proxyRow(7, 'socks5', 'a.com', 1080, true)]);
      const same = settingsReducer(state, new SelectProxy(7), makeEnv());
      expect(same.state === state).assertTrue();
      expect(same.effects.length).assertEqual(0);

      const missing = settingsReducer(state, new SelectProxy(99), makeEnv());
      expect(missing.state === state).assertTrue();
      expect(missing.effects.length).assertEqual(0);
    });

    it('selectProxy_whileBusy_isNoop', 0, () => {
      const state = proxyState([proxyRow(8, 'socks5', 'b.com', 1080, false)])
        .copyWith({ updatingProxyId: 8 });
      const result = settingsReducer(state, new SelectProxy(8), makeEnv());

      expect(result.state === state).assertTrue();
      expect(result.effects.length).assertEqual(0);
    });

    it('saveProxy_valid_newForm_emitsSaveWithNewId', 0, () => {
      const state = proxyState([]);
      const form: ProxyForm = proxyFormItem(PROXY_NEW_ID, 'proxy.example.com', '1080', 'socks5');
      const result = settingsReducer(state, new SaveProxy(form), makeEnv());

      expect(result.state.updatingProxyId).assertEqual(PROXY_NEW_ID);
      expect(result.state.errorMessage).assertNull();
      expect(result.effects.length).assertEqual(1);
      const effect = result.effects[0] as SaveProxyEffect;
      expect(effect.kind).assertEqual('saveProxy');
      expect(effect.form.id).assertEqual(PROXY_NEW_ID);
      expect(effect.form.server).assertEqual('proxy.example.com');
    });

    it('saveProxy_invalidForm_reportsErrorWithoutEffect', 0, () => {
      const state = proxyState([]);
      const result = settingsReducer(state, new SaveProxy(proxyFormItem(PROXY_NEW_ID, '', '0', 'socks5')), makeEnv());

      // 校验失败只出错误文案，绝不把半截表单写给 TDLib。
      expect(result.effects.length).assertEqual(0);
      expect(result.state.updatingProxyId === null).assertTrue();
      expect(result.state.errorMessage).assertEqual('Server address required');
    });

    it('saveProxy_invalidMtprotoSecret_reportsSecretError', 0, () => {
      const state = proxyState([]);
      const form: ProxyForm = new ProxyForm(
        PROXY_NEW_ID, 'mtproto', 'a.com', '443', '', '', 'zzzz', false, '', true
      );
      const result = settingsReducer(state, new SaveProxy(form), makeEnv());

      expect(result.effects.length).assertEqual(0);
      expect(result.state.errorMessage).assertEqual('Secret must be hexadecimal');
    });

    it('saveProxy_editForm_carriesRowId', 0, () => {
      const state = proxyState([proxyRow(7, 'socks5', 'a.com', 1080, false)]);
      const result = settingsReducer(state, new SaveProxy(proxyFormItem(7, 'a.com', '1080', 'socks5')), makeEnv());

      expect(result.state.updatingProxyId).assertEqual(7);
      expect((result.effects[0] as SaveProxyEffect).form.id).assertEqual(7);
    });

    it('removeProxyRequested_existingRow_emitsRemove', 0, () => {
      const state = proxyState([proxyRow(7, 'socks5', 'a.com', 1080, false)]);
      const result = settingsReducer(state, new RemoveProxyRequested(7), makeEnv());

      expect(result.state.updatingProxyId).assertEqual(7);
      expect(result.effects.length).assertEqual(1);
      expect((result.effects[0] as RemoveProxyEffect).proxyId).assertEqual(7);
    });

    it('removeProxyRequested_missingRowOrBusy_isNoop', 0, () => {
      const state = proxyState([proxyRow(7, 'socks5', 'a.com', 1080, false)]);
      const missing = settingsReducer(state, new RemoveProxyRequested(21), makeEnv());
      expect(missing.state === state).assertTrue();
      expect(missing.effects.length).assertEqual(0);

      const busy = state.copyWith({ updatingProxyId: 7 });
      const busyResult = settingsReducer(busy, new RemoveProxyRequested(7), makeEnv());
      expect(busyResult.state === busy).assertTrue();
      expect(busyResult.effects.length).assertEqual(0);
    });

    it('copyWith_keepsProxyFieldsWhenUnspecified', 0, () => {
      const state = proxyState([proxyRow(7, 'socks5', 'a.com', 1080, true)])
        .copyWith({ updatingProxyId: 7, isLoadingProxies: true });
      const next = state.copyWith({ displayName: 'hubery' });

      expect(next.proxyItems.length).assertEqual(1);
      expect(next.showProxyPage).assertTrue();
      expect(next.updatingProxyId).assertEqual(7);
      expect(next.isLoadingProxies).assertTrue();
    });

    // ---- AUTODL-101 自动媒体下载 ----

    it('initialState_hasAutoDownloadDefaults', 0, () => {
      const state = SettingsUiState.initial();
      expect(state.showAutoDownloadPage).assertFalse();
      // null 表示「还没读到盘上的策略」，与「读到但全关」是两回事
      expect(state.autoDownloadPolicy === null).assertTrue();
    });

    it('openAutoDownloadPage_opensSubPage_andRequestsLoad', 0, () => {
      const result = settingsReducer(SettingsUiState.initial(), new OpenAutoDownloadPage(), makeEnv());

      expect(result.state.showAutoDownloadPage).assertTrue();
      expect(result.state.errorMessage).assertNull();
      expect(result.effects.length).assertEqual(1);
      expect((result.effects[0] as LoadAutoDownloadPolicyEffect).kind).assertEqual('loadAutoDownloadPolicy');
    });

    it('closeAutoDownloadPage_keepsLoadedPolicy', 0, () => {
      const state = autoDownloadState(AutoDownloadPolicy.defaultPolicy());
      const result = settingsReducer(state, new CloseAutoDownloadPage(), makeEnv());

      expect(result.state.showAutoDownloadPage).assertFalse();
      // 设置主页的「自动媒体下载」行要靠这份缓存出副标题，关闭子页不能清空。
      expect(result.state.autoDownloadPolicy !== null).assertTrue();
      expect(result.effects.length).assertEqual(0);
    });

    it('closeAutoDownloadPage_whenAlreadyClosed_isNoop', 0, () => {
      const state = SettingsUiState.initial();
      const result = settingsReducer(state, new CloseAutoDownloadPage(), makeEnv());
      expect(result.state === state).assertTrue();
      expect(result.effects.length).assertEqual(0);
    });

    it('loadAutoDownloadPolicy_emitsEffectWithoutTouchingState', 0, () => {
      const state = autoDownloadState(null);
      const result = settingsReducer(state, new LoadAutoDownloadPolicy(), makeEnv());

      expect(result.state === state).assertTrue();
      expect(result.effects.length).assertEqual(1);
      expect(result.effects[0].kind).assertEqual('loadAutoDownloadPolicy');
    });

    it('autoDownloadPolicyLoaded_storesPolicyAndClearsError', 0, () => {
      const state = SettingsUiState.initial().copyWith({ errorMessage: 'boom' });
      const policy: AutoDownloadPolicy = AutoDownloadPolicy.defaultPolicy();
      const result = settingsReducer(state, new AutoDownloadPolicyLoaded(policy), makeEnv());

      expect(result.state.autoDownloadPolicy === policy).assertTrue();
      expect(result.state.errorMessage).assertNull();
      expect(result.effects.length).assertEqual(0);
    });

    it('setAutoDownloadKind_withoutLoadedPolicy_isNoop', 0, () => {
      const state = autoDownloadState(null);
      const result = settingsReducer(state, new SetAutoDownloadKind('private', 'video', true), makeEnv());

      // 没读盘就写回等于拿猜出来的默认覆盖用户偏好，必须整个忽略。
      expect(result.state === state).assertTrue();
      expect(result.effects.length).assertEqual(0);
    });

    it('setAutoDownloadKind_sameValue_isNoop', 0, () => {
      // Toggle 挂载时会回调一次初值；同值不该落盘。
      const policy: AutoDownloadPolicy = AutoDownloadPolicy.defaultPolicy();
      const state = autoDownloadState(policy);
      const result = settingsReducer(state, new SetAutoDownloadKind('private', 'photo', true), makeEnv());

      expect(result.state === state).assertTrue();
      expect(result.effects.length).assertEqual(0);
    });

    it('setAutoDownloadKind_updatesOnlyTargetScopeAndPersists', 0, () => {
      const policy: AutoDownloadPolicy = AutoDownloadPolicy.defaultPolicy();
      const state = autoDownloadState(policy);
      const result = settingsReducer(state, new SetAutoDownloadKind('group', 'video', true), makeEnv());

      expect(result.effects.length).assertEqual(1);
      const effect: PersistAutoDownloadPolicyEffect = result.effects[0] as PersistAutoDownloadPolicyEffect;
      expect(effect.kind).assertEqual('persistAutoDownloadPolicy');
      const persisted: AutoDownloadPolicy = effect.policy;
      expect(persisted.groupFlags.video).assertTrue();
      // 其余分区不能被子页的单项勾选带跑
      expect(persisted.privateFlags.equals(policy.privateFlags)).assertTrue();
      expect(persisted.channelFlags.equals(policy.channelFlags)).assertTrue();
      // 原策略也不该被就地改动（reducer 必须是纯函数）
      expect(state.autoDownloadPolicy !== null && state.autoDownloadPolicy.groupFlags.video).assertFalse();
      expect(result.state.autoDownloadPolicy !== null
        && result.state.autoDownloadPolicy.groupFlags.toMask()).assertEqual(persisted.groupFlags.toMask());
    });

    it('setAutoDownloadKind_turningOffDefaultKind_persistsMask', 0, () => {
      const policy: AutoDownloadPolicy = AutoDownloadPolicy.defaultPolicy();
      const state = autoDownloadState(policy);
      const result = settingsReducer(state, new SetAutoDownloadKind('channel', 'photo', false), makeEnv());

      const persisted: AutoDownloadPolicy = (result.effects[0] as PersistAutoDownloadPolicyEffect).policy;
      const expected: number = AutoDownloadFlags.defaultFlags().with('photo', false).toMask();
      expect(persisted.channelFlags.toMask()).assertEqual(expected);
      expect(persisted.privateFlags.toMask()).assertEqual(AutoDownloadFlags.defaultFlags().toMask());
    });

    it('copyWith_keepsAutoDownloadFieldsWhenUnspecified', 0, () => {
      const state = autoDownloadState(AutoDownloadPolicy.defaultPolicy());
      const next = state.copyWith({ displayName: 'hubery' });

      expect(next.showAutoDownloadPage).assertTrue();
      expect(next.autoDownloadPolicy !== null).assertTrue();
    });

    // ---- AUTODL-102 省流量（Data Saver）----

    it('initialState_hasNoDataSaverSettingsLoaded', 0, () => {
      // null = 「还没读盘」，页面据此显 Loading，而不是显一份猜出来的默认。
      expect(SettingsUiState.initial().dataSaverSettings === null).assertTrue();
    });

    it('loadDataSaverSettings_emitsEffectWithoutTouchingState', 0, () => {
      const state = dataSaverState(null);
      const result = settingsReducer(state, new LoadDataSaverSettings(), makeEnv());

      expect(result.state === state).assertTrue();
      expect(result.effects.length).assertEqual(1);
      expect((result.effects[0] as LoadDataSaverSettingsEffect).kind).assertEqual('loadDataSaverSettings');
    });

    it('dataSaverSettingsLoaded_storesSettingsAndClearsError', 0, () => {
      const state = SettingsUiState.initial().copyWith({ errorMessage: 'boom' });
      const settings: DataSaverSettings = DataSaverSettings.defaultSettings();
      const result = settingsReducer(state, new DataSaverSettingsLoaded(settings), makeEnv());

      expect(result.state.dataSaverSettings === settings).assertTrue();
      expect(result.state.errorMessage).assertNull();
      expect(result.effects.length).assertEqual(0);
    });

    it('setDataSaverFlag_withoutLoadedSettings_isNoop', 0, () => {
      const state = dataSaverState(null);
      const result = settingsReducer(state, new SetDataSaverFlag(DATA_SAVER_FLAG_ENABLED, true), makeEnv());

      // 没读盘就写回 = 用默认档覆盖用户盘上的偏好，必须整个忽略。
      expect(result.state === state).assertTrue();
      expect(result.effects.length).assertEqual(0);
    });

    it('setDataSaverFlag_sameValue_isNoop', 0, () => {
      // Toggle 挂载时会回调一次初值（Android 默认勾着「漫游」），同值不该落盘。
      const state = dataSaverState(DataSaverSettings.defaultSettings());
      const result = settingsReducer(state,
        new SetDataSaverFlag(DATA_SAVER_FLAG_WHEN_ROAMING, true), makeEnv());

      expect(result.state === state).assertTrue();
      expect(result.effects.length).assertEqual(0);
    });

    it('setDataSaverFlag_togglesOnlyThatBitAndPersists', 0, () => {
      const source: DataSaverSettings = DataSaverSettings.defaultSettings();
      const state = dataSaverState(source);
      const result = settingsReducer(state,
        new SetDataSaverFlag(DATA_SAVER_FLAG_WHEN_MOBILE, true), makeEnv());

      expect(result.effects.length).assertEqual(1);
      const effect: PersistDataSaverSettingsEffect = result.effects[0] as PersistDataSaverSettingsEffect;
      expect(effect.kind).assertEqual('persistDataSaverSettings');
      expect(effect.settings.toMask())
        .assertEqual(DATA_SAVER_FLAG_WHEN_MOBILE | DATA_SAVER_FLAG_WHEN_ROAMING);
      // 主开关不能被「多勾一档」带跑。
      expect(effect.settings.enabled).assertFalse();
      // reducer 是纯函数：入参那份设置不得被就地改动。
      expect(source.toMask()).assertEqual(DATA_SAVER_FLAG_WHEN_ROAMING);
      expect(state.dataSaverSettings !== null && state.dataSaverSettings.whenMobile).assertFalse();
      expect(result.state.dataSaverSettings !== null
        && result.state.dataSaverSettings.toMask()).assertEqual(effect.settings.toMask());
    });

    it('setDataSaverFlag_turningOnMaster_savesMaskOne', 0, () => {
      const state = dataSaverState(DataSaverSettings.defaultSettings());
      const result = settingsReducer(state,
        new SetDataSaverFlag(DATA_SAVER_FLAG_ENABLED, true), makeEnv());

      const persisted: DataSaverSettings = (result.effects[0] as PersistDataSaverSettingsEffect).settings;
      expect(persisted.toMask()).assertEqual(DATA_SAVER_FLAG_ENABLED | DATA_SAVER_FLAG_WHEN_ROAMING);
    });

    it('dataSaverAndAutoDownload_doNotClobberEachOther', 0, () => {
      // 同页两套设置各自 copyWith 一位，另一套必须原样留着 ——
      // 省流量卡在最上面，用户勾完主开关不该把下面的分区策略清成「未读盘」。
      const state = SettingsUiState.initial().copyWith({
        showAutoDownloadPage: true,
        autoDownloadPolicy: AutoDownloadPolicy.defaultPolicy(),
        dataSaverSettings: DataSaverSettings.defaultSettings()
      });
      const afterSaver = settingsReducer(state,
        new SetDataSaverFlag(DATA_SAVER_FLAG_ENABLED, true), makeEnv()).state;
      expect(afterSaver.autoDownloadPolicy !== null).assertTrue();
      expect(afterSaver.autoDownloadPolicy === state.autoDownloadPolicy).assertTrue();

      const afterKind = settingsReducer(afterSaver,
        new SetAutoDownloadKind('private', 'video', true), makeEnv()).state;
      expect(afterKind.dataSaverSettings !== null).assertTrue();
      expect(afterKind.dataSaverSettings !== null
        && afterKind.dataSaverSettings.enabled).assertTrue();
    });

    it('closeAutoDownloadPage_keepsLoadedDataSaverSettings', 0, () => {
      const state = dataSaverState(DataSaverSettings.defaultSettings());
      const result = settingsReducer(state, new CloseAutoDownloadPage(), makeEnv());

      expect(result.state.showAutoDownloadPage).assertFalse();
      expect(result.state.dataSaverSettings !== null).assertTrue();
    });

    // ---- AUTODL-103 按网络类型的自动下载限制 ----

    it('initialState_hasNoDownloadLimitsLoaded', 0, () => {
      expect(SettingsUiState.initial().downloadLimits === null).assertTrue();
    });

    it('loadDownloadLimits_emitsEffectWithoutTouchingState', 0, () => {
      const state = downloadLimitsState(null);
      const result = settingsReducer(state, new LoadDownloadLimits(), makeEnv());

      expect(result.effects.length).assertEqual(1);
      expect((result.effects[0] as LoadDownloadLimitsEffect).kind).assertEqual('loadDownloadLimits');
      expect(result.state.downloadLimits === null).assertTrue();
    });

    it('downloadLimitsLoaded_storesLimitsAndClearsError', 0, () => {
      const state = downloadLimitsState(null).copyWith({ errorMessage: 'boom' });
      const limits: DownloadLimitsByNetwork = DownloadLimitsByNetwork.defaultLimits();
      const result = settingsReducer(state, new DownloadLimitsLoaded(limits), makeEnv());

      expect(result.state.downloadLimits === limits).assertTrue();
      expect(result.state.errorMessage === null).assertTrue();
    });

    it('setDownloadLimitSize_withoutLoadedLimits_isNoop', 0, () => {
      // 没读到盘就不写：否则会用猜出来的默认覆盖用户偏好（聊天页按盘上的限制下载）
      const state = downloadLimitsState(null);
      const result = settingsReducer(state, new SetDownloadLimitSize('wifi', DOWNLOAD_LIMIT_1MB), makeEnv());

      expect(result.effects.length).assertEqual(0);
      expect(result.state.downloadLimits === null).assertTrue();
    });

    it('setDownloadLimitSize_sameValue_isNoop', 0, () => {
      const state = downloadLimitsState(DownloadLimitsByNetwork.defaultLimits());
      const result = settingsReducer(state, new SetDownloadLimitSize('wifi', DOWNLOAD_LIMIT_50MB), makeEnv());

      expect(result.effects.length).assertEqual(0);
      expect(result.state.downloadLimits === state.downloadLimits).assertTrue();
    });

    it('setDownloadLimitSize_writesOnlyThatBucket', 0, () => {
      const source: DownloadLimitsByNetwork = DownloadLimitsByNetwork.defaultLimits();
      const state = downloadLimitsState(source);
      const result = settingsReducer(state, new SetDownloadLimitSize('wifi', DOWNLOAD_LIMIT_1MB), makeEnv());

      expect(result.effects.length).assertEqual(1);
      const effect: PersistDownloadLimitsEffect = result.effects[0] as PersistDownloadLimitsEffect;
      expect(effect.kind).assertEqual('persistDownloadLimits');
      expect(effect.limits.wifi.sizeCode).assertEqual(DOWNLOAD_LIMIT_1MB);
      expect(effect.limits.mobile.sizeCode).assertEqual(source.mobile.sizeCode);
      expect(effect.limits.roaming.sizeCode).assertEqual(source.roaming.sizeCode);
      // reducer 必须是纯函数：盘上那份没被就地改掉
      expect(source.wifi.sizeCode).assertEqual(DOWNLOAD_LIMIT_50MB);
      expect(result.state.downloadLimits !== null
        && result.state.downloadLimits.wifi.sizeCode).assertEqual(DOWNLOAD_LIMIT_1MB);
    });

    it('setDownloadLimitSize_onUnknownNetworkWritesThroughMobileBucket', 0, () => {
      // 设置页只会显式写三档，但 of() 把未知网络读成移动档 —— 写侧必须同规则，
      // 否则会出现「读的是移动、写不进移动」的错位。
      const state = downloadLimitsState(DownloadLimitsByNetwork.defaultLimits());
      const result = settingsReducer(state, new SetDownloadLimitSize('other', DOWNLOAD_LIMIT_1MB), makeEnv());

      const written: DownloadLimitsByNetwork = (result.effects[0] as PersistDownloadLimitsEffect).limits;
      expect(written.mobile.sizeCode).assertEqual(DOWNLOAD_LIMIT_1MB);
    });

    it('setDownloadLimitExclusion_togglesOnlyThatKind', 0, () => {
      const source: DownloadLimitsByNetwork = DownloadLimitsByNetwork.defaultLimits();
      const state = downloadLimitsState(source);
      const result = settingsReducer(state,
        new SetDownloadLimitExclusion('mobile', 'photo', true), makeEnv());

      const effect: PersistDownloadLimitsEffect = result.effects[0] as PersistDownloadLimitsEffect;
      expect(effect.limits.mobile.isExcluded('photo')).assertTrue();
      expect(effect.limits.mobile.isExcluded('video')).assertFalse();
      expect(effect.limits.wifi.excludedFlags.toMask()).assertEqual(0);
      // 尺寸档不该被类型勾选带跑
      expect(effect.limits.mobile.sizeCode).assertEqual(source.mobile.sizeCode);
    });

    it('setDownloadLimitExclusion_sameValue_isNoop', 0, () => {
      // Toggle 挂载时会回调一次初值，同值不该落盘
      const loaded: DownloadLimitsByNetwork = DownloadLimitsByNetwork.defaultLimits()
        .withNetwork('roaming', new NetworkDownloadLimits(DOWNLOAD_LIMIT_NONE)
          .withExcluded('gif', true));
      const state = downloadLimitsState(loaded);
      const result = settingsReducer(state,
        new SetDownloadLimitExclusion('roaming', 'gif', true), makeEnv());

      expect(result.effects.length).assertEqual(0);
      expect(result.state.downloadLimits === loaded).assertTrue();
    });

    it('downloadLimitsAndDataSaver_doNotClobberEachOther', 0, () => {
      // 同页三套设置各自写一位，另两套必须原样留着
      const state = SettingsUiState.initial().copyWith({
        showAutoDownloadPage: true,
        autoDownloadPolicy: AutoDownloadPolicy.defaultPolicy(),
        dataSaverSettings: DataSaverSettings.defaultSettings(),
        downloadLimits: DownloadLimitsByNetwork.defaultLimits()
      });
      const afterLimits = settingsReducer(state,
        new SetDownloadLimitSize('wifi', DOWNLOAD_LIMIT_1MB), makeEnv()).state;
      expect(afterLimits.dataSaverSettings === state.dataSaverSettings).assertTrue();
      expect(afterLimits.autoDownloadPolicy === state.autoDownloadPolicy).assertTrue();

      const afterSaver = settingsReducer(afterLimits,
        new SetDataSaverFlag(DATA_SAVER_FLAG_ENABLED, true), makeEnv()).state;
      expect(afterSaver.downloadLimits !== null
        && afterSaver.downloadLimits.wifi.sizeCode).assertEqual(DOWNLOAD_LIMIT_1MB);
      expect(afterSaver.autoDownloadPolicy === state.autoDownloadPolicy).assertTrue();
    });

    it('closeAutoDownloadPage_keepsLoadedDownloadLimits', 0, () => {
      const state = downloadLimitsState(DownloadLimitsByNetwork.defaultLimits());
      const result = settingsReducer(state, new CloseAutoDownloadPage(), makeEnv());

      expect(result.state.showAutoDownloadPage).assertFalse();
      expect(result.state.downloadLimits !== null).assertTrue();
    });
  });
}
