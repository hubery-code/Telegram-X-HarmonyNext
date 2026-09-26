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
  OpenPrivacyKeyPage,
  ClosePrivacyKeyPage,
  SetPrivacyMode,
  TogglePrivacyPremium,
  OpenPrivacyPicker,
  ClosePrivacyPicker,
  TogglePrivacyPickerContact,
  ApplyPrivacyPicker,
  PrivacyDetailLoaded,
  PrivacyDetailLoadFailed,
  PrivacyRulesSaved,
  PrivacyRulesSaveFailed,
  OpenProxyPage,
  CloseProxyPage,
  LoadProxies,
  ProxiesLoaded,
  SelectProxy,
  SaveProxy,
  RemoveProxyRequested,
  ProxyPingUpdated,
  ProxyConnectionStateChanged,
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
  PingProxiesEffect,
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
import { PrivacySettingItem, PrivacySettingKey, privacyRowLabel } from '../main/ets/model/PrivacySettings';
import { parsePrivacyRules } from '../main/ets/model/PrivacyRules';
import { PrivacyDetailState, PrivacyContactRow } from '../main/ets/model/PrivacyDetail';
import {
  TdUserPrivacySettingRule,
  UserPrivacySettingRuleAllowAll,
  UserPrivacySettingRuleAllowContacts,
  UserPrivacySettingRuleAllowPremiumUsers,
  UserPrivacySettingRuleAllowUsers,
  UserPrivacySettingRuleRestrictAll,
  UserPrivacySettingRuleRestrictUsers
} from '@tgx/core-td-api-generated';
import {
  PROXY_NONE_ID,
  PROXY_NEW_ID,
  PROXY_PING_FAILED,
  PROXY_PING_LOADING,
  PROXY_PING_UNSET,
  ProxyForm,
  ProxyItem,
  ProxyKind,
  proxyFailureOf,
  proxyPingOf
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

/**
 * PRIVACY-101：隐私测试的小工具。
 * 规则列表直接用 TDLib 生成类构造，断言时压成 `a>b>c` 的类型串 —— 例外名单的
 * 语义全在「顺序 + 类型」上，比逐条 cast 好读得多。
 */
function everybodyRules(): TdUserPrivacySettingRule[] {
  return [new UserPrivacySettingRuleAllowAll()];
}

function contactsRules(): TdUserPrivacySettingRule[] {
  return [new UserPrivacySettingRuleAllowContacts(), new UserPrivacySettingRuleRestrictAll()];
}

function nobodyRules(): TdUserPrivacySettingRule[] {
  // 设备实测：TDLib 对「没有人能看到」读回的就是空列表。
  return [];
}

function allowUsersRule(userIds: number[]): TdUserPrivacySettingRule {
  const rule: UserPrivacySettingRuleAllowUsers = new UserPrivacySettingRuleAllowUsers();
  rule.user_ids = userIds;
  return rule;
}

function restrictUsersRule(userIds: number[]): TdUserPrivacySettingRule {
  const rule: UserPrivacySettingRuleRestrictUsers = new UserPrivacySettingRuleRestrictUsers();
  rule.user_ids = userIds;
  return rule;
}

function privacyItem(key: PrivacySettingKey, rules: TdUserPrivacySettingRule[]): PrivacySettingItem {
  return new PrivacySettingItem(key, parsePrivacyRules(rules));
}

function contacts(): PrivacyContactRow[] {
  return [new PrivacyContactRow(1001, 'Alice', false), new PrivacyContactRow(2002, 'Bob', false)];
}

/** 已读完、可直接编辑的详情态（`savedRules` 即服务端快照）。 */
function loadedDetail(
  key: PrivacySettingKey,
  rules: TdUserPrivacySettingRule[],
  rows: PrivacyContactRow[]
): PrivacyDetailState {
  return PrivacyDetailState.forLoaded(key, rules, rows);
}

function stateWithDetail(detail: PrivacyDetailState): SettingsUiState {
  return privacyState([privacyItem(detail.key, detail.savedRules)]).copyWith({
    showPrivacyPage: true,
    privacyDetail: detail
  });
}

/** 详情页当前的规则列表；没有打开详情时回空列表（调用方据此断言「什么都没发生」）。 */
function rulesOf(state: SettingsUiState): TdUserPrivacySettingRule[] {
  const detail: PrivacyDetailState | null = state.privacyDetail;
  return detail === null ? [] : detail.rules;
}

function typesOf(rules: TdUserPrivacySettingRule[]): string {
  const out: string[] = [];
  for (let i = 0; i < rules.length; i++) {
    out.push(rules[i].type);
  }
  return out.join('>');
}

function idsOf(rule: TdUserPrivacySettingRule): number[] {
  if (rule.type === 'userPrivacySettingRuleAllowUsers') {
    return (rule as UserPrivacySettingRuleAllowUsers).user_ids;
  }
  if (rule.type === 'userPrivacySettingRuleRestrictUsers') {
    return (rule as UserPrivacySettingRuleRestrictUsers).user_ids;
  }
  return [];
}

function selectedIdsOf(rows: PrivacyContactRow[]): number[] {
  const out: number[] = [];
  for (let i = 0; i < rows.length; i++) {
    if (rows[i].selected) {
      out.push(rows[i].userId);
    }
  }
  return out;
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

/** PROXY-102：探测表的测试构造器，`[[proxyId, pingMs], ...]`。 */
function pingTable(entries: number[][]): Map<number, number> {
  const table: Map<number, number> = new Map();
  for (let i = 0; i < entries.length; i++) {
    table.set(entries[i][0], entries[i][1]);
  }
  return table;
}

/** PROXY-103：失败原因表的构造入参（`[proxyId 的十进制串, langKey]`）。 */
function failureTable(entries: string[][]): Map<number, string> {
  const table: Map<number, string> = new Map();
  for (let i = 0; i < entries.length; i++) {
    table.set(Number(entries[i][0]), entries[i][1]);
  }
  return table;
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

    it('closePrivacyPage_clearsFlagAndUncommittedDetail', 0, () => {
      const state = stateWithDetail(loadedDetail('show_bio', everybodyRules(), contacts())).copyWith({
        showPrivacyPage: true
      });
      const result = settingsReducer(state, new ClosePrivacyPage(), makeEnv());

      expect(result.state.showPrivacyPage).assertFalse();
      // 未提交的编辑不带回列表页，但已读到的行视图要留着（卡片副标题还在用）。
      expect(result.state.privacyDetail === null).assertTrue();
      expect(result.state.privacyItems.length).assertEqual(1);
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
        privacyItem('show_last_seen', contactsRules()),
        privacyItem('allow_calls', everybodyRules())
      ];
      const state = SettingsUiState.initial().copyWith({ isLoadingPrivacy: true });
      const result = settingsReducer(state, new PrivacySettingsLoaded(items), makeEnv());

      expect(result.state.privacyItems.length).assertEqual(2);
      expect(privacyRowLabel(result.state.privacyItems[0])).assertEqual('My Contacts');
      expect(privacyRowLabel(result.state.privacyItems[1])).assertEqual('Everybody');
      expect(result.state.isLoadingPrivacy).assertFalse();
    });

    // ---- PRIVACY-101 详情页：开合与写回时机 ----

    it('openPrivacyKeyPage_opensDetailLoading_andEmitsDetailEffect', 0, () => {
      const state = privacyState([privacyItem('show_bio', everybodyRules())]);
      const result = settingsReducer(state, new OpenPrivacyKeyPage('show_bio'), makeEnv());

      const detail: PrivacyDetailState | null = result.state.privacyDetail;
      expect(detail !== null).assertTrue();
      if (detail !== null) {
        expect(detail.key).assertEqual('show_bio');
        expect(detail.loading).assertTrue();
        expect(detail.rules.length).assertEqual(0);
      }
      expect(result.effects.length).assertEqual(1);
      expect(result.effects[0].kind).assertEqual('loadPrivacyDetail');
    });

    it('privacyDetailLoaded_fillsRulesAndContacts_andClearsLoading', 0, () => {
      const state = stateWithDetail(PrivacyDetailState.forLoading('show_bio'));
      const loaded: PrivacyDetailLoaded = new PrivacyDetailLoaded(
        'show_bio',
        contactsRules(),
        contacts()
      );
      const result = settingsReducer(state, loaded, makeEnv());

      const detail: PrivacyDetailState | null = result.state.privacyDetail;
      expect(detail !== null).assertTrue();
      if (detail !== null) {
        expect(detail.loading).assertFalse();
        expect(detail.rules.length).assertEqual(2);
        // 服务端快照 == 本地列表：刚读到的项不该被当成「有未保存的改动」。
        expect(detail.isDirty()).assertFalse();
      }
    });

    it('privacyDetailLoaded_ignoresRepliesForAnotherKey', 0, () => {
      const state = stateWithDetail(loadedDetail('show_bio', everybodyRules(), contacts()));
      const late: PrivacyDetailLoaded = new PrivacyDetailLoaded('show_phone_number', [], []);
      const result = settingsReducer(state, late, makeEnv());

      expect(result.state === state).assertTrue();
    });

    it('privacyDetailLoadFailed_keepsDetailOpenWithErrorMessage', 0, () => {
      const state = stateWithDetail(PrivacyDetailState.forLoading('show_bio'));
      const failed: PrivacyDetailLoadFailed =
        new PrivacyDetailLoadFailed('show_bio', 'Unable to load privacy settings.');
      const result = settingsReducer(state, failed, makeEnv());

      const detail: PrivacyDetailState | null = result.state.privacyDetail;
      expect(detail !== null).assertTrue();
      if (detail !== null) {
        expect(detail.loading).assertFalse();
        expect(detail.errorMessage).assertEqual('Unable to load privacy settings.');
      }
    });

    it('closePrivacyKeyPage_withoutEdits_writesNothing', 0, () => {
      const state = stateWithDetail(loadedDetail('show_bio', contactsRules(), contacts()));
      const result = settingsReducer(state, new ClosePrivacyKeyPage(), makeEnv());

      expect(result.state.privacyDetail === null).assertTrue();
      expect(result.effects.length).assertEqual(0);
      expect(result.state.updatingPrivacyKey === null).assertTrue();
    });

    it('closePrivacyKeyPage_withEdits_writesLocalRulesOnce', 0, () => {
      const state = stateWithDetail(loadedDetail('show_bio', contactsRules(), contacts())
        .copyWith({ rules: everybodyRules() }));
      const result = settingsReducer(state, new ClosePrivacyKeyPage(), makeEnv());

      expect(result.state.privacyDetail === null).assertTrue();
      expect(result.state.updatingPrivacyKey).assertEqual('show_bio');
      expect(result.effects.length).assertEqual(1);
      const effect: SetPrivacySettingEffect = result.effects[0] as SetPrivacySettingEffect;
      expect(effect.kind).assertEqual('setPrivacySetting');
      expect(effect.key).assertEqual('show_bio');
      // 写回的是本地编辑后的整条列表（含例外名单），不是重新拼出来的单条规则。
      expect(typesOf(effect.rules)).assertEqual('userPrivacySettingRuleAllowAll');
    });

    it('closePrivacyKeyPage_whileAnotherWriteIsPending_skipsWrite', 0, () => {
      const state = stateWithDetail(loadedDetail('show_bio', contactsRules(), contacts())
        .copyWith({ rules: everybodyRules() }))
        .copyWith({ updatingPrivacyKey: 'allow_calls' });
      const result = settingsReducer(state, new ClosePrivacyKeyPage(), makeEnv());

      expect(result.state.privacyDetail === null).assertTrue();
      expect(result.effects.length).assertEqual(0);
    });

    // ---- PRIVACY-101 详情页：主档位与 Premium ----

    it('setPrivacyMode_rewritesGeneralRules_andKeepsExceptions', 0, () => {
      const rules: TdUserPrivacySettingRule[] =
        [restrictUsersRule([2002]), new UserPrivacySettingRuleAllowContacts(), new UserPrivacySettingRuleRestrictAll()];
      const state = stateWithDetail(loadedDetail('show_bio', rules, contacts()));
      const result = settingsReducer(state, new SetPrivacyMode('everybody'), makeEnv());

      const detail: PrivacyDetailState | null = result.state.privacyDetail;
      expect(detail !== null).assertTrue();
      if (detail !== null) {
        expect(typesOf(detail.rules))
          .assertEqual('userPrivacySettingRuleRestrictUsers>userPrivacySettingRuleAllowAll');
        // 改档只动本地：没离开页面前不发 setUserPrivacySettingRules。
        expect(detail.savedRules.length).assertEqual(3);
        expect(detail.isDirty()).assertTrue();
      }
      expect(result.effects.length).assertEqual(0);
    });

    it('setPrivacyMode_whenDetailClosed_isIdentity', 0, () => {
      const state = privacyState([privacyItem('show_bio', everybodyRules())]);
      const result = settingsReducer(state, new SetPrivacyMode('nobody'), makeEnv());

      expect(result.state === state).assertTrue();
      expect(result.effects.length).assertEqual(0);
    });

    it('togglePrivacyPremium_inContactsMode_addsThenRemovesPremiumRule', 0, () => {
      const state = stateWithDetail(loadedDetail('show_bio', contactsRules(), contacts()));
      const on: SettingsUiState = settingsReducer(state, new TogglePrivacyPremium(), makeEnv()).state;
      expect(typesOf(rulesOf(on))).assertEqual(
        'userPrivacySettingRuleAllowPremiumUsers>userPrivacySettingRuleAllowContacts>userPrivacySettingRuleRestrictAll'
      );

      const off: SettingsUiState = settingsReducer(on, new TogglePrivacyPremium(), makeEnv()).state;
      expect(typesOf(rulesOf(off))).assertEqual(
        'userPrivacySettingRuleAllowContacts>userPrivacySettingRuleRestrictAll'
      );
      // 两次点完回到原样：不该留下「未保存的改动」。
      const offDetail: PrivacyDetailState | null = off.privacyDetail;
      expect(offDetail !== null).assertTrue();
      if (offDetail !== null) {
        expect(offDetail.isDirty()).assertFalse();
      }
    });

    it('togglePrivacyPremium_outsideContactsMode_isIgnored', 0, () => {
      const state = stateWithDetail(loadedDetail('show_bio', everybodyRules(), contacts()));
      const result = settingsReducer(state, new TogglePrivacyPremium(), makeEnv());

      // 「所有人」档下点 Premium 不该顺手把可见面缩到联系人。
      expect(result.state === state).assertTrue();
    });

    // ---- PRIVACY-101 详情页：例外名单选择器 ----

    it('openPrivacyPicker_seedsPickedIdsFromTheEditedSide', 0, () => {
      const rules: TdUserPrivacySettingRule[] = [
        allowUsersRule([1001]),
        new UserPrivacySettingRuleAllowContacts(),
        new UserPrivacySettingRuleRestrictAll()
      ];
      const state = stateWithDetail(loadedDetail('show_bio', rules, contacts()));
      const result = settingsReducer(state, new OpenPrivacyPicker('always'), makeEnv());

      const detail: PrivacyDetailState | null = result.state.privacyDetail;
      expect(detail !== null).assertTrue();
      if (detail !== null) {
        expect(detail.pickedUserIds.join(',')).assertEqual('1001');
        expect(selectedIdsOf(detail.contacts).join(',')).assertEqual('1001');
      }

      const never: SettingsUiState =
        settingsReducer(result.state, new OpenPrivacyPicker('never'), makeEnv()).state;
      const neverDetail: PrivacyDetailState | null = never.privacyDetail;
      expect(neverDetail !== null).assertTrue();
      if (neverDetail !== null) {
        expect(neverDetail.pickedUserIds.length).assertEqual(0);
        expect(selectedIdsOf(neverDetail.contacts).length).assertEqual(0);
      }
    });

    it('togglePrivacyPickerContact_addsThenRemoves_andLeavesRulesAlone', 0, () => {
      const state = stateWithDetail(loadedDetail('show_bio', contactsRules(), contacts())
        .copyWith({ pickerTarget: 'always', pickedUserIds: [] }));
      const added: SettingsUiState =
        settingsReducer(state, new TogglePrivacyPickerContact(2002), makeEnv()).state;
      const addedDetail: PrivacyDetailState | null = added.privacyDetail;
      expect(addedDetail !== null).assertTrue();
      if (addedDetail !== null) {
        expect(addedDetail.pickedUserIds.join(',')).assertEqual('2002');
        expect(selectedIdsOf(addedDetail.contacts).join(',')).assertEqual('2002');
        expect(typesOf(addedDetail.rules)).assertEqual(typesOf(rulesOf(state)));
      }

      const removed: SettingsUiState =
        settingsReducer(added, new TogglePrivacyPickerContact(2002), makeEnv()).state;
      const removedDetail: PrivacyDetailState | null = removed.privacyDetail;
      expect(removedDetail !== null).assertTrue();
      if (removedDetail !== null) {
        expect(removedDetail.pickedUserIds.length).assertEqual(0);
      }
    });

    it('togglePrivacyPickerContact_whenPickerClosed_isIdentity', 0, () => {
      const state = stateWithDetail(loadedDetail('show_bio', contactsRules(), contacts()));
      const result = settingsReducer(state, new TogglePrivacyPickerContact(2002), makeEnv());

      expect(result.state === state).assertTrue();
    });

    it('closePrivacyPicker_dropsPicksWithoutTouchingRules', 0, () => {
      const state = stateWithDetail(loadedDetail('show_bio', contactsRules(), contacts())
        .copyWith({ pickerTarget: 'always', pickedUserIds: [2002] }));
      const result = settingsReducer(state, new ClosePrivacyPicker(), makeEnv());

      const detail: PrivacyDetailState | null = result.state.privacyDetail;
      expect(detail !== null).assertTrue();
      if (detail !== null) {
        expect(detail.pickerTarget === null).assertTrue();
        expect(detail.pickedUserIds.length).assertEqual(0);
        expect(detail.isDirty()).assertFalse();
        expect(selectedIdsOf(detail.contacts).length).assertEqual(0);
      }
    });

    it('applyPrivacyPicker_replacesAlwaysListAndStripsTheSamePersonFromNever', 0, () => {
      // 1001、2002 原本都在「从不允许」里，这次只把 1001 勾进「总是允许」：
      // 同一个人不能两侧都留，但没被勾选的 2002 必须原地不动。
      const rules: TdUserPrivacySettingRule[] = [
        restrictUsersRule([1001, 2002]),
        new UserPrivacySettingRuleAllowContacts(),
        new UserPrivacySettingRuleRestrictAll()
      ];
      const state = stateWithDetail(loadedDetail('show_bio', rules, contacts())
        .copyWith({ pickerTarget: 'always', pickedUserIds: [1001] }));
      const result = settingsReducer(state, new ApplyPrivacyPicker(), makeEnv());

      const detail: PrivacyDetailState | null = result.state.privacyDetail;
      expect(detail !== null).assertTrue();
      if (detail !== null) {
        expect(typesOf(detail.rules)).assertEqual(
          'userPrivacySettingRuleAllowUsers>userPrivacySettingRuleRestrictUsers>userPrivacySettingRuleAllowContacts>userPrivacySettingRuleRestrictAll'
        );
        // 新名单插到最前，例外必须先于主档位规则才可能先命中。
        expect(idsOf(detail.rules[0]).join(',')).assertEqual('1001');
        expect(idsOf(detail.rules[1]).join(',')).assertEqual('2002');
        expect(detail.pickerTarget === null).assertTrue();
        expect(detail.pickedUserIds.length).assertEqual(0);
        expect(detail.isDirty()).assertTrue();
      }
      expect(result.effects.length).assertEqual(0);
    });

    it('applyPrivacyPicker_withEmptyPicks_clearsThatSide', 0, () => {
      const rules: TdUserPrivacySettingRule[] = [
        allowUsersRule([1001]),
        new UserPrivacySettingRuleAllowContacts(),
        new UserPrivacySettingRuleRestrictAll()
      ];
      const state = stateWithDetail(loadedDetail('show_bio', rules, contacts())
        .copyWith({ pickerTarget: 'always', pickedUserIds: [] }));
      const result = settingsReducer(state, new ApplyPrivacyPicker(), makeEnv());

      const detail: PrivacyDetailState | null = result.state.privacyDetail;
      expect(detail !== null).assertTrue();
      if (detail !== null) {
        expect(typesOf(detail.rules)).assertEqual(
          'userPrivacySettingRuleAllowContacts>userPrivacySettingRuleRestrictAll'
        );
      }
    });

    // ---- PRIVACY-101 详情页：写回结果 ----

    it('privacyRulesSaved_updatesThatRowFromServerTruth', 0, () => {
      const state = privacyState([
        privacyItem('show_bio', everybodyRules()),
        privacyItem('allow_calls', contactsRules())
      ]).copyWith({ updatingPrivacyKey: 'show_bio' });
      const saved: PrivacyRulesSaved = new PrivacyRulesSaved('show_bio', nobodyRules());
      const result = settingsReducer(state, saved, makeEnv());

      expect(privacyRowLabel(result.state.privacyItems[0])).assertEqual('Nobody');
      expect(privacyRowLabel(result.state.privacyItems[1])).assertEqual('My Contacts');
      expect(result.state.updatingPrivacyKey === null).assertTrue();
      expect(result.state.errorMessage === null).assertTrue();
    });

    it('privacyRulesSaveFailed_keepsShownRow_andReportsError', 0, () => {
      const state = privacyState([privacyItem('show_bio', everybodyRules())])
        .copyWith({ updatingPrivacyKey: 'show_bio' });
      const failed: PrivacyRulesSaveFailed =
        new PrivacyRulesSaveFailed('show_bio', 'Unable to update privacy settings.');
      const result = settingsReducer(state, failed, makeEnv());

      // 失败时行上显示的仍是服务端真值，靠横幅说明这次没写进去。
      expect(privacyRowLabel(result.state.privacyItems[0])).assertEqual('Everybody');
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
      const state = privacyState([privacyItem('show_bio', nobodyRules())])
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

    it('closeProxyPage_clearsProbeTableButKeepsRows', 0, () => {
      const state = proxyState([proxyRow(7, 'socks5', 'a.com', 1080, true)])
        .copyWith({ proxyPingMs: pingTable([[7, 42]]), proxyConnection: 'ready' });
      const result = settingsReducer(state, new CloseProxyPage(), makeEnv());

      expect(result.state.showProxyPage).assertFalse();
      expect(result.state.proxyPingMs.size).assertEqual(0);
      expect(result.state.proxyConnection).assertEqual('unknown');
    });

    it('loadProxies_setsLoadingAndEmitsEffect', 0, () => {
      const state = proxyState([]);
      const result = settingsReducer(state, new LoadProxies(), makeEnv());

      expect(result.state.isLoadingProxies).assertTrue();
      expect(result.effects.length).assertEqual(1);
      const effect = result.effects[0] as LoadProxiesEffect;
      expect(effect.kind).assertEqual('loadProxies');
    });

    it('proxiesLoaded_replacesItemsAndRequestsProbe', 0, () => {
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
      // 读到列表就轮到探测：可用性是测出来的，不靠上一轮的残值。
      expect(result.effects.length).assertEqual(1);
      expect((result.effects[0] as PingProxiesEffect).kind).assertEqual('pingProxies');
    });

    it('proxiesLoaded_prunesDeadRowsAndKeepsLiveProbeResults', 0, () => {
      const state = proxyState([proxyRow(1, 'socks5', 'a.com', 1080, false)])
        .copyWith({ proxyPingMs: pingTable([[PROXY_NONE_ID, 33], [1, 77], [2, 88]]) });
      const items: ProxyItem[] = [
        proxyRow(1, 'socks5', 'a.com', 1080, false),
        proxyRow(3, 'socks5', 'c.com', 1080, false)
      ];
      const result = settingsReducer(state, new ProxiesLoaded(items), makeEnv());

      // 1 号行还在（在途的回包别被抹掉），0 是「不使用代理」，2 已经删了才该消失。
      expect(proxyPingOf(result.state.proxyPingMs, PROXY_NONE_ID)).assertEqual(33);
      expect(proxyPingOf(result.state.proxyPingMs, 1)).assertEqual(77);
      expect(result.state.proxyPingMs.has(2)).assertFalse();
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

    // ---- PROXY-102 连通性探测与连接态 ----

    it('proxyPingUpdated_writesTableAndKeepsOldOne', 0, () => {
      const state = proxyState([proxyRow(7, 'socks5', 'a.com', 1080, false)])
        .copyWith({ proxyPingMs: pingTable([[7, 11]]) });
      const result = settingsReducer(state, new ProxyPingUpdated(7, 222), makeEnv());

      expect(proxyPingOf(result.state.proxyPingMs, 7)).assertEqual(222);
      // 覆盖式写入，不是累加；旧实例也不能被就地改掉。
      expect(proxyPingOf(state.proxyPingMs, 7)).assertEqual(11);
      expect(result.effects.length).assertEqual(0);
    });

    it('proxyPingUpdated_noneRowIsAlwaysWritable', 0, () => {
      const state = proxyState([]);
      const loading = settingsReducer(state, new ProxyPingUpdated(PROXY_NONE_ID, PROXY_PING_LOADING), makeEnv());
      expect(proxyPingOf(loading.state.proxyPingMs, PROXY_NONE_ID)).assertEqual(PROXY_PING_LOADING);

      const result = settingsReducer(loading.state, new ProxyPingUpdated(PROXY_NONE_ID, 38), makeEnv());
      expect(proxyPingOf(result.state.proxyPingMs, PROXY_NONE_ID)).assertEqual(38);
    });

    it('proxyPingUpdated_dropsRepliesForDeadRows', 0, () => {
      const state = proxyState([proxyRow(7, 'socks5', 'a.com', 1080, false)]);
      const result = settingsReducer(state, new ProxyPingUpdated(21, PROXY_PING_FAILED), makeEnv());

      // 晚到的回包不能复活一个已经不存在的行。
      expect(result.state === state).assertTrue();
      expect(result.effects.length).assertEqual(0);
    });

    // ---- PROXY-103 失败原因与两张表的一致性 ----

    it('proxyPingUpdated_writesFailureAlongsideResult', 0, () => {
      const state = proxyState([proxyRow(7, 'socks5', 'a.com', 1080, false)]);
      const failed = settingsReducer(
        state,
        new ProxyPingUpdated(7, PROXY_PING_FAILED, 'Connection refused'),
        makeEnv()
      );
      expect(proxyPingOf(failed.state.proxyPingMs, 7)).assertEqual(PROXY_PING_FAILED);
      expect(proxyFailureOf(failed.state.proxyPingFailure, 7)).assertEqual('Connection refused');

      // 重试成功：延迟回来了，原因必须一起擦掉 —— 否则那句「出错」会跟在新延迟后面。
      const ok = settingsReducer(failed.state, new ProxyPingUpdated(7, 45), makeEnv());
      expect(proxyPingOf(ok.state.proxyPingMs, 7)).assertEqual(45);
      expect(proxyFailureOf(ok.state.proxyPingFailure, 7)).assertEqual('');
      expect(ok.state.proxyPingFailure.has(7)).assertFalse();
    });

    it('closeProxyPage_clearsBothProbeTables', 0, () => {
      const state = proxyState([proxyRow(7, 'socks5', 'a.com', 1080, true)])
        .copyWith({
          proxyPingMs: pingTable([[7, PROXY_PING_FAILED]]),
          proxyPingFailure: failureTable([['7', 'Address not found']]),
          proxyConnection: 'ready'
        });
      const result = settingsReducer(state, new CloseProxyPage(), makeEnv());

      expect(result.state.proxyPingMs.size).assertEqual(0);
      expect(result.state.proxyPingFailure.size).assertEqual(0);
    });

    it('proxiesLoaded_prunesFailureTableWithTheSameRule', 0, () => {
      const state = proxyState([proxyRow(1, 'socks5', 'a.com', 1080, false)])
        .copyWith({
          proxyPingFailure: failureTable([['0', 'Network unavailable'], ['1', 'Proxy error'], ['2', 'Proxy error']])
        });
      const items: ProxyItem[] = [proxyRow(1, 'socks5', 'a.com', 1080, false)];
      const result = settingsReducer(state, new ProxiesLoaded(items), makeEnv());

      expect(proxyFailureOf(result.state.proxyPingFailure, PROXY_NONE_ID)).assertEqual('Network unavailable');
      expect(proxyFailureOf(result.state.proxyPingFailure, 1)).assertEqual('Proxy error');
      expect(result.state.proxyPingFailure.has(2)).assertFalse();
    });

    it('proxyConnectionStateChanged_deduplicatesIdenticalState', 0, () => {
      const state = proxyState([proxyRow(7, 'socks5', 'a.com', 1080, true)])
        .copyWith({ proxyConnection: 'ready' });
      const result = settingsReducer(state, new ProxyConnectionStateChanged('ready'), makeEnv());

      expect(result.state === state).assertTrue();
      expect(result.effects.length).assertEqual(0);
    });

    it('proxyConnectionStateChanged_firstFrameDoesNotReprobe', 0, () => {
      const state = proxyState([proxyRow(7, 'socks5', 'a.com', 1080, true)]);
      const result = settingsReducer(state, new ProxyConnectionStateChanged('ready'), makeEnv());

      // unknown → ready 只是订阅后的首帧，不是「断了又通」，否则每次进页都多一轮探测。
      expect(result.state.proxyConnection).assertEqual('ready');
      expect(result.effects.length).assertEqual(0);
    });

    it('proxyConnectionStateChanged_recoveryReprobesWhilePageIsOpen', 0, () => {
      const state = proxyState([proxyRow(7, 'socks5', 'a.com', 1080, true)])
        .copyWith({ proxyConnection: 'waiting_for_network' });
      const result = settingsReducer(state, new ProxyConnectionStateChanged('ready'), makeEnv());

      expect(result.state.proxyConnection).assertEqual('ready');
      expect(result.effects.length).assertEqual(1);
      expect((result.effects[0] as PingProxiesEffect).kind).assertEqual('pingProxies');
    });

    it('proxyConnectionStateChanged_afterCloseDoesNotReprobe', 0, () => {
      const state = proxyState([proxyRow(7, 'socks5', 'a.com', 1080, true)])
        .copyWith({ proxyConnection: 'connecting' });
      const closed = state.copyWith({ showProxyPage: false });
      const result = settingsReducer(closed, new ProxyConnectionStateChanged('ready'), makeEnv());

      expect(result.state.proxyConnection).assertEqual('ready');
      expect(result.effects.length).assertEqual(0);
    });

    it('copyWith_keepsProbeFieldsWhenUnspecified', 0, () => {
      const state = proxyState([proxyRow(7, 'socks5', 'a.com', 1080, true)])
        .copyWith({ proxyPingMs: pingTable([[7, 55]]), proxyConnection: 'ready' });
      const next = state.copyWith({ displayName: 'hubery' });

      expect(proxyPingOf(next.proxyPingMs, 7)).assertEqual(55);
      expect(next.proxyConnection).assertEqual('ready');
      expect(proxyPingOf(SettingsUiState.initial().proxyPingMs, PROXY_NONE_ID)).assertEqual(PROXY_PING_UNSET);
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
