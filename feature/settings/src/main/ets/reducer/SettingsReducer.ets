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
import { ThemeManager, clampChatFontSize } from '@tgx/core-design-system';
import { Lang, LanguagePreference } from '@tgx/core-common';
import { SettingsUiState, SettingsUiStateOptions } from '../contract/SettingsUiState';
import {
  APP_LOCK_NOTICE_INVALID,
  APP_LOCK_NOTICE_MISMATCH,
  AutoLockChoice,
  PasscodeFlowStage,
  nextAutoLockChoice,
  passcodeStepFor,
  PasscodeStepResult
} from '@tgx/core-domain';
import {
  OpenPasscodePage,
  ClosePasscodePage,
  LoadPasscodeState,
  PasscodeStateLoaded,
  TogglePasscodeRequested,
  ChangePasscodeRequested,
  CycleAutoLockChoice,
  CancelPasscodeFlow,
  PasscodeSubmitted,
  PasscodeVerified,
  PasscodeRejected,
  PasscodeMismatched,
  PasscodeOperationFailed,
  PasscodeOperationDone,
  AutoLockChoiceRejected,
  TogglePasscodeVisible,
  PasscodeVisibleRejected
} from '../contract/SettingsIntent';
import {
  ClearPasscodeDraftEffect,
  CommitPasscodeEffect,
  LoadPasscodeStateEffect,
  PersistAutoLockChoiceEffect,
  PersistPasscodeVisibleEffect,
  StorePasscodeDraftEffect,
  VerifyPasscodeEffect
} from '../contract/SettingsEffect';
import { parseSettingsSection } from '../model/SettingsSection';
import {
  CacheCleared,
  ChangeChatFontSize,
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
  ToggleNotificationScope,
  OpenDevicesPage,
  CloseDevicesPage,
  SectionFocused,
  LoadActiveSessions,
  ActiveSessionsLoaded,
  ActiveSessionsLoadFailed,
  TerminateSessionIntent,
  TerminateAllOtherSessionsIntent,
  OpenPrivacyPage,
  ClosePrivacyPage,
  LoadPrivacySettings,
  PrivacySettingsLoaded,
  OpenPrivacyKeyPage,
  ClosePrivacyKeyPage,
  PrivacyDetailLoaded,
  PrivacyDetailLoadFailed,
  SetPrivacyMode,
  TogglePrivacyPremium,
  TogglePrivacyHideReadTime,
  PrivacyReadDateLoaded,
  PrivacyReadDateRejected,
  OpenPrivacyPicker,
  ClosePrivacyPicker,
  TogglePrivacyPickerContact,
  TogglePrivacyPickerChat,
  ApplyPrivacyPicker,
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
  DataSaverSettingsLoaded,
  SetDataSaverFlag,
  DownloadLimitsLoaded,
  SetDownloadLimitSize,
  SetDownloadLimitExclusion
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
  SwitchAccountEffect,
  LoadActiveSessionsEffect,
  TerminateSessionEffect,
  TerminateAllOtherSessionsEffect,
  LoadPrivacySettingsEffect,
  LoadPrivacyDetailEffect,
  SetPrivacySettingEffect,
  SetReadDatePrivacyEffect,
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
} from '../contract/SettingsEffect';
import { TdUserPrivacySettingRule } from '@tgx/core-td-api-generated';
import { NotificationScopeKey } from '../model/NotificationSettings';
import {
  PrivacySettingItem,
  PrivacySettingKey,
  privacyNeedsPremiumRow,
  privacyPremiumForMode
} from '../model/PrivacySettings';
import {
  parsePrivacyRules,
  privacyRulesForMode,
  privacyRulesWithAllowExceptions,
  privacyRulesWithPremium,
  privacyRulesWithRestrictExceptions,
  PrivacyRulesView
} from '../model/PrivacyRules';
import {
  PrivacyDetailState,
  privacyChatsWithPicked,
  privacyContactsWithPicked
} from '../model/PrivacyDetail';
import {
  PROXY_NONE_ID,
  ProxyConnectionState,
  ProxyItem,
  proxyFormError,
  proxyPingsPrunedTo,
  proxyPingsWith,
  proxyFailuresPrunedTo,
  proxyFailuresWith
} from '../model/ProxySettings';
import {
  AutoDownloadFlags,
  AutoDownloadPolicy,
  DataSaverSettings,
  DownloadLimitsByNetwork,
  NetworkDownloadLimits
} from '@tgx/core-domain';

function notificationScopeEnabled(state: SettingsUiState, scope: NotificationScopeKey): boolean {
  if (scope === 'private') {
    return state.privateNotificationsEnabled;
  }
  if (scope === 'group') {
    return state.groupNotificationsEnabled;
  }
  return state.channelNotificationsEnabled;
}

/** 用回读到的规则列表刷新某一行的展示值（列表页文案的唯一来源）。 */
function privacyItemsWithUpdated(
  items: readonly PrivacySettingItem[],
  key: PrivacySettingKey,
  rules: TdUserPrivacySettingRule[]
): PrivacySettingItem[] {
  const next: PrivacySettingItem[] = [];
  const view: PrivacyRulesView = parsePrivacyRules(rules);
  for (let i = 0; i < items.length; i++) {
    next.push(items[i].key === key ? items[i].withView(view) : items[i]);
  }
  return next;
}

/**
 * 详情页的每一次本地编辑都走这里：换规则、不动 `savedRules`，`isDirty()` 因此成立。
 * 返回 null 表示当前没有打开任何一项（调用方据此忽略意图，不凭空造详情态）。
 */
function detailWithRules(
  state: SettingsUiState,
  rules: TdUserPrivacySettingRule[]
): SettingsUiState | null {
  const detail: PrivacyDetailState | null = state.privacyDetail;
  if (detail === null) {
    return null;
  }
  return state.copyWith({ privacyDetail: detail.copyWith({ rules: rules }) });
}

/**
 * 勾选集合的增删：已勾则去掉，未勾则追加到末尾。
 * 顺序有语义 —— 写回规则时按这个顺序进 `user_ids` / `chat_ids`，TDLib 保留顺序，
 * 所以后勾选的人排在名单后面（Android 的选择器同样是追加式）。
 */
function togglePickedId(picked: number[], id: number): number[] {
  const next: number[] = [];
  for (let i = 0; i < picked.length; i++) {
    if (picked[i] !== id) {
      next.push(picked[i]);
    }
  }
  if (picked.indexOf(id) < 0) {
    next.push(id);
  }
  return next;
}

/** 按 TDLib id 取代理行；列表里还没有该行时返回 null（调用方据此忽略点击）。 */
function proxyItemById(
  items: readonly ProxyItem[],
  proxyId: number
): ProxyItem | null {
  for (let i = 0; i < items.length; i++) {
    if (items[i].id === proxyId) {
      return items[i];
    }
  }
  return null;
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

    case 'changeChatFontSize': {
      const fontIntent: ChangeChatFontSize = intent as ChangeChatFontSize;
      // 先吸附到合法档位再比对——避免「滑块拖到 15.4」这类中间值被写进状态，
      // 档位表是唯一真相源（TGX 的 isGoodChatFontSize 是同一意图的严格版）。
      const applied: number = clampChatFontSize(fontIntent.chatFontSize);
      if (state.chatFontSize === applied) {
        return reduced(state);
      }

      // 1. 同步更新全局 ThemeManager（消息内容文字的字号来源）
      ThemeManager.getInstance().setChatFontSize(applied);

      // 2. 同步写入 AppStorage。这里**只做这一件事**：落盘由 entry 装配层完成
      //    （entry/Index.ets 的 @StorageProp + @Watch → store/SettingsStore.ets），
      //    业务层因此保持零 Kit 依赖。约定该键在 AppStorage 里存**字符串**，
      //    与 entry 启动时的回灌写法保持一致。
      try {
        AppStorage.setOrCreate<string>('chatFontSize', `${applied}`);
      } catch (_e) {
        // 无 AppStorage 运行环境（如纯逻辑单测）容错
      }

      const options: SettingsUiStateOptions = {
        chatFontSize: applied
      };
      const nextState: SettingsUiState = state.copyWith(options);
      const effects: readonly SettingsEffect[] = [
        new ShowToastEffect(`Chat text size set to ${applied}`)
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

    case 'openDevicesPage': {
      const options: SettingsUiStateOptions = {
        showDevicesPage: true,
        isLoadingSessions: true,
        errorMessage: null
      };
      return reduced(state.copyWith(options), [new LoadActiveSessionsEffect()]);
    }

    case 'closeDevicesPage': {
      const options: SettingsUiStateOptions = {
        showDevicesPage: false
      };
      return reduced(state.copyWith(options));
    }

    case 'sectionFocused': {
      const focus: SectionFocused = intent as SectionFocused;
      // 'devices' 的落点是既有的整屏活跃会话子页，不占分区渲染。
      if (focus.section === 'devices') {
        const options: SettingsUiStateOptions = {
          section: 'all',
          showDevicesPage: true,
          isLoadingSessions: true,
          errorMessage: null
        };
        return reduced(state.copyWith(options), [new LoadActiveSessionsEffect()]);
      }
      // 'privacy' 同理：SELF-101 的「隐私和安全」行落在整屏 PrivacySubPage。
      if (focus.section === 'privacy') {
        const options: SettingsUiStateOptions = {
          section: 'all',
          showPrivacyPage: true,
          privacyDetail: null,
          isLoadingPrivacy: true,
          errorMessage: null
        };
        return reduced(state.copyWith(options), [new LoadPrivacySettingsEffect()]);
      }
      const options: SettingsUiStateOptions = {
        section: parseSettingsSection(focus.section)
      };
      return reduced(state.copyWith(options));
    }

    case 'loadActiveSessions': {
      const options: SettingsUiStateOptions = {
        isLoadingSessions: true
      };
      return reduced(state.copyWith(options), [new LoadActiveSessionsEffect()]);
    }

    case 'activeSessionsLoaded': {
      const loadedIntent: ActiveSessionsLoaded = intent as ActiveSessionsLoaded;
      const options: SettingsUiStateOptions = {
        activeSessions: loadedIntent.sessions,
        isLoadingSessions: false
      };
      return reduced(state.copyWith(options));
    }

    case 'activeSessionsLoadFailed': {
      const failedIntent: ActiveSessionsLoadFailed = intent as ActiveSessionsLoadFailed;
      const options: SettingsUiStateOptions = {
        isLoadingSessions: false,
        errorMessage: failedIntent.errorMessage
      };
      return reduced(state.copyWith(options));
    }

    case 'terminateSession': {
      const termIntent: TerminateSessionIntent = intent as TerminateSessionIntent;
      return reduced(state, [new TerminateSessionEffect(termIntent.sessionId)]);
    }

    case 'terminateAllOtherSessions': {
      return reduced(state, [new TerminateAllOtherSessionsEffect()]);
    }

    // ---- SELF-102 隐私和安全 ----

    case 'openPrivacyPage': {
      const options: SettingsUiStateOptions = {
        showPrivacyPage: true,
        isLoadingPrivacy: true,
        errorMessage: null
      };
      return reduced(state.copyWith(options), [new LoadPrivacySettingsEffect()]);
    }

    case 'closePrivacyPage': {
      if (!state.showPrivacyPage) {
        return reduced(state);
      }
      // 离列表页时把详情页状态一起丢掉：未提交的编辑不该在下次进入时复活。
      const options: SettingsUiStateOptions = {
        showPrivacyPage: false,
        privacyDetail: null
      };
      return reduced(state.copyWith(options));
    }

    case 'loadPrivacySettings': {
      const options: SettingsUiStateOptions = {
        isLoadingPrivacy: true
      };
      return reduced(state.copyWith(options), [new LoadPrivacySettingsEffect()]);
    }

    case 'privacySettingsLoaded': {
      const loadedIntent: PrivacySettingsLoaded = intent as PrivacySettingsLoaded;
      const options: SettingsUiStateOptions = {
        privacyItems: loadedIntent.items,
        isLoadingPrivacy: false,
        updatingPrivacyKey: null
      };
      return reduced(state.copyWith(options));
    }

    case 'openPrivacyKeyPage': {
      const openIntent: OpenPrivacyKeyPage = intent as OpenPrivacyKeyPage;
      const options: SettingsUiStateOptions = {
        privacyDetail: PrivacyDetailState.forLoading(openIntent.key),
        errorMessage: null
      };
      return reduced(state.copyWith(options), [new LoadPrivacyDetailEffect(openIntent.key)]);
    }

    /**
     * 离开详情页 = 唯一一次写回（Android `onBlur → saveChanges()`）：
     * 没有改动就不发请求（`nothingChanged()`），有改动才带上本地规则列表去写。
     * 详情态立即清空 —— 写回失败的报错由列表页横幅承担，用户在那一行看到服务端真值。
     */
    case 'closePrivacyKeyPage': {
      const detail: PrivacyDetailState | null = state.privacyDetail;
      if (detail === null) {
        return reduced(state);
      }
      if (state.updatingPrivacyKey !== null || !detail.isDirty()) {
        return reduced(state.copyWith({ privacyDetail: null }));
      }
      return reduced(
        state.copyWith({ privacyDetail: null, updatingPrivacyKey: detail.key }),
        [new SetPrivacySettingEffect(detail.key, detail.rules)]
      );
    }

    case 'privacyDetailLoaded': {
      const loaded: PrivacyDetailLoaded = intent as PrivacyDetailLoaded;
      const detail: PrivacyDetailState | null = state.privacyDetail;
      // 只接受当前打开的项的回包：详情页可能已经被关掉或切走，晚到的回包不能把它复活。
      if (detail === null || detail.key !== loaded.key) {
        return reduced(state);
      }
      return reduced(state.copyWith({
        privacyDetail: PrivacyDetailState.forLoaded(
          loaded.key, loaded.rules, loaded.contacts, loaded.chats, loaded.showReadDate
        )
      }));
    }

    case 'privacyDetailLoadFailed': {
      const failed: PrivacyDetailLoadFailed = intent as PrivacyDetailLoadFailed;
      const detail: PrivacyDetailState | null = state.privacyDetail;
      if (detail === null || detail.key !== failed.key) {
        return reduced(state);
      }
      return reduced(state.copyWith({
        privacyDetail: detail.copyWith({ loading: false, errorMessage: failed.errorMessage })
      }));
    }

    case 'setPrivacyMode': {
      const modeIntent: SetPrivacyMode = intent as SetPrivacyMode;
      const detail: PrivacyDetailState | null = state.privacyDetail;
      if (detail === null) {
        return reduced(state);
      }
      // Premium 不是本端可自选的档位：Android 在改档那一次就把 `plusPremium` 算成
      // 「这一项是 invites 且新档位是 contacts」，其它项改档等于顺手把已有的 premium 规则摘掉。
      const next: TdUserPrivacySettingRule[] = privacyRulesForMode(
        detail.rules,
        modeIntent.mode,
        privacyPremiumForMode(detail.key, modeIntent.mode)
      );
      const reducedState: SettingsUiState | null = detailWithRules(state, next);
      return reducedState === null ? reduced(state) : reduced(reducedState);
    }

    /**
     * PRIVACY-103：Premium 放行只属于「群组与频道邀请」这一项，且改的是**这一条规则本身**
     * （`privacyRulesWithPremium`）—— 不动档位、不动例外名单。
     * 「所有人」档下这行根本不出现（Android `needExtraToggle`），所以那一档的点击直接忽略，
     * 而不是悄悄写进一条界面上看不见、也撤回不了的规则。
     */
    case 'togglePrivacyPremium': {
      const detail: PrivacyDetailState | null = state.privacyDetail;
      if (detail === null || !privacyNeedsPremiumRow(detail.key)) {
        return reduced(state);
      }
      const view: PrivacyRulesView = parsePrivacyRules(detail.rules);
      if (view.mode === 'everybody') {
        return reduced(state);
      }
      const next: TdUserPrivacySettingRule[] =
        privacyRulesWithPremium(detail.rules, !view.plusPremium);
      const reducedState: SettingsUiState | null = detailWithRules(state, next);
      return reducedState === null ? reduced(state) : reduced(reducedState);
    }

    /**
     * 「隐藏已读时间」（PRIVACY-103）。两点与上面的规则编辑相反：
     * 1. 它不在隐私规则列表里，是 TDLib 的另一个设置，所以**当场就写**，不等离开页面；
     * 2. 界面上的开关是「隐藏」，TDLib 的字段是 `show_read_date`，**方向相反**
     *    （Android `readDatePrivacySetting.showReadDate = !adapter.toggleView(v)`）。
     * `showReadDate === null` 是「还没读到」，此时这一行不可点（Android 把该 cell 置灰）。
     */
    case 'togglePrivacyHideReadTime': {
      const detail: PrivacyDetailState | null = state.privacyDetail;
      if (detail === null || detail.showReadDate === null) {
        return reduced(state);
      }
      const showReadDate: boolean = !detail.showReadDate;
      return reduced(
        state.copyWith({ privacyDetail: detail.copyWith({ showReadDate: showReadDate }) }),
        [new SetReadDatePrivacyEffect(showReadDate)]
      );
    }

    case 'privacyReadDateLoaded': {
      const loadedDate: PrivacyReadDateLoaded = intent as PrivacyReadDateLoaded;
      const detail: PrivacyDetailState | null = state.privacyDetail;
      if (detail === null) {
        return reduced(state);
      }
      return reduced(state.copyWith({
        privacyDetail: detail.copyWith({ showReadDate: loadedDate.showReadDate })
      }));
    }

    /** 写失败且读不回真值时退到上一个已知值；`null` 表示退回「没读到」= 该行重新不可点。 */
    case 'privacyReadDateRejected': {
      const rejected: PrivacyReadDateRejected = intent as PrivacyReadDateRejected;
      const detail: PrivacyDetailState | null = state.privacyDetail;
      if (detail === null) {
        return reduced(state);
      }
      return reduced(state.copyWith({
        privacyDetail: detail.copyWith({ showReadDate: rejected.showReadDate })
      }));
    }

    case 'openPrivacyPicker': {
      const pickerIntent: OpenPrivacyPicker = intent as OpenPrivacyPicker;
      const detail: PrivacyDetailState | null = state.privacyDetail;
      if (detail === null) {
        return reduced(state);
      }
      const view: PrivacyRulesView = parsePrivacyRules(detail.rules);
      // 人和会话各自一份勾选集合：两名单在规则里是两条独立规则，勾选不能互相覆盖。
      const currentUsers: number[] =
        pickerIntent.target === 'always' ? view.plusUserIds : view.minusUserIds;
      const currentChats: number[] =
        pickerIntent.target === 'always' ? view.plusChatIds : view.minusChatIds;
      return reduced(state.copyWith({
        privacyDetail: detail.copyWith({
          pickerTarget: pickerIntent.target,
          pickedUserIds: currentUsers.slice(),
          pickedChatIds: currentChats.slice(),
          contacts: privacyContactsWithPicked(detail.contacts, currentUsers),
          chats: privacyChatsWithPicked(detail.chats, currentChats)
        })
      }));
    }

    case 'closePrivacyPicker': {
      const detail: PrivacyDetailState | null = state.privacyDetail;
      if (detail === null || detail.pickerTarget === null) {
        return reduced(state);
      }
      return reduced(state.copyWith({
        privacyDetail: detail.copyWith({
          pickerTarget: null,
          pickedUserIds: [],
          pickedChatIds: [],
          contacts: privacyContactsWithPicked(detail.contacts, []),
          chats: privacyChatsWithPicked(detail.chats, [])
        })
      }));
    }

    case 'togglePrivacyPickerContact': {
      const toggleIntent: TogglePrivacyPickerContact = intent as TogglePrivacyPickerContact;
      const detail: PrivacyDetailState | null = state.privacyDetail;
      if (detail === null || detail.pickerTarget === null) {
        return reduced(state);
      }
      const next: number[] =
        togglePickedId(detail.pickedUserIds, toggleIntent.userId);
      return reduced(state.copyWith({
        privacyDetail: detail.copyWith({
          pickedUserIds: next,
          contacts: privacyContactsWithPicked(detail.contacts, next)
        })
      }));
    }

    /** PRIVACY-102：会话分区与联系人分区同一条勾选语义，只是 id 是 chatId。 */
    case 'togglePrivacyPickerChat': {
      const toggleIntent: TogglePrivacyPickerChat = intent as TogglePrivacyPickerChat;
      const detail: PrivacyDetailState | null = state.privacyDetail;
      if (detail === null || detail.pickerTarget === null) {
        return reduced(state);
      }
      const next: number[] = togglePickedId(detail.pickedChatIds, toggleIntent.chatId);
      return reduced(state.copyWith({
        privacyDetail: detail.copyWith({
          pickedChatIds: next,
          chats: privacyChatsWithPicked(detail.chats, next)
        })
      }));
    }

    /**
     * 提交勾选 = 全量替换该侧名单（Android `allowExceptions` / `disallowExceptions`）：
     * 新名单插到列表最前，另一侧里的同名 id 被摘掉 —— 同一个人/同一个群不能既总是允许又从不允许。
     */
    case 'applyPrivacyPicker': {
      const detail: PrivacyDetailState | null = state.privacyDetail;
      if (detail === null || detail.pickerTarget === null) {
        return reduced(state);
      }
      const nextRules: TdUserPrivacySettingRule[] = detail.pickerTarget === 'always'
        ? privacyRulesWithAllowExceptions(
          detail.rules, detail.pickedUserIds, detail.pickedChatIds
        )
        : privacyRulesWithRestrictExceptions(
          detail.rules, detail.pickedUserIds, detail.pickedChatIds
        );
      return reduced(state.copyWith({
        privacyDetail: detail.copyWith({
          rules: nextRules,
          pickerTarget: null,
          pickedUserIds: [],
          pickedChatIds: [],
          contacts: privacyContactsWithPicked(detail.contacts, []),
          chats: privacyChatsWithPicked(detail.chats, [])
        })
      }));
    }

    case 'privacyRulesSaved': {
      const savedIntent: PrivacyRulesSaved = intent as PrivacyRulesSaved;
      const options: SettingsUiStateOptions = {
        privacyItems: privacyItemsWithUpdated(
          state.privacyItems,
          savedIntent.key,
          savedIntent.rules
        ),
        updatingPrivacyKey: null,
        errorMessage: null
      };
      return reduced(state.copyWith(options));
    }

    case 'privacyRulesSaveFailed': {
      const failedIntent: PrivacyRulesSaveFailed = intent as PrivacyRulesSaveFailed;
      const options: SettingsUiStateOptions = {
        updatingPrivacyKey: null,
        errorMessage: failedIntent.errorMessage
      };
      return reduced(state.copyWith(options));
    }

    // ---- PROXY-101 网络代理 ----

    case 'openProxyPage': {
      const options: SettingsUiStateOptions = {
        showProxyPage: true,
        isLoadingProxies: true,
        errorMessage: null
      };
      return reduced(state.copyWith(options), [new LoadProxiesEffect()]);
    }

    case 'closeProxyPage': {
      if (!state.showProxyPage) {
        return reduced(state);
      }
      // 探测结果是这一页的临时观察，不是账号状态：离页清空，回来时重新测。
      const cleared: Map<number, number> = new Map();
      const clearedFailures: Map<number, string> = new Map();
      const options: SettingsUiStateOptions = {
        showProxyPage: false,
        proxyPingMs: cleared,
        proxyPingFailure: clearedFailures,
        proxyConnection: 'unknown'
      };
      return reduced(state.copyWith(options));
    }

    case 'loadProxies': {
      const options: SettingsUiStateOptions = {
        isLoadingProxies: true
      };
      return reduced(state.copyWith(options), [new LoadProxiesEffect()]);
    }

    case 'proxiesLoaded': {
      const loadedIntent: ProxiesLoaded = intent as ProxiesLoaded;
      const options: SettingsUiStateOptions = {
        proxyItems: loadedIntent.items,
        isLoadingProxies: false,
        updatingProxyId: null,
        // 重建行的同时留住还活着的探测结果：删掉的行不留残值，在途的行不被抹掉。
        // 两张侧表用同一个口径剪枝，否则失败原因会留在一个已经不存在的行上。
        proxyPingMs: proxyPingsPrunedTo(state.proxyPingMs, loadedIntent.items),
        proxyPingFailure: proxyFailuresPrunedTo(state.proxyPingFailure, loadedIntent.items)
      };
      // 每次读到列表都把每一行（含「不使用代理」）探一遍 —— 可用性是测出来的，不是猜的。
      return reduced(state.copyWith(options), [new PingProxiesEffect()]);
    }

    case 'selectProxy': {
      const selectIntent: SelectProxy = intent as SelectProxy;
      if (state.updatingProxyId !== null) {
        return reduced(state);
      }
      // 「不使用代理」这一行没有对应的 TDLib 对象，只能走 disableProxy。
      if (selectIntent.proxyId === PROXY_NONE_ID) {
        const options: SettingsUiStateOptions = {
          updatingProxyId: PROXY_NONE_ID
        };
        return reduced(state.copyWith(options), [new DisableProxyEffect()]);
      }
      const item: ProxyItem | null = proxyItemById(state.proxyItems, selectIntent.proxyId);
      // 列表还没读到该行时忽略点击，而不是凭 id 猜一个启用态出去。
      if (item === null) {
        return reduced(state);
      }
      // TDLib 只允许一个代理生效；点已选中的那行是空操作，不该再发请求。
      if (item.isEnabled) {
        return reduced(state);
      }
      const options: SettingsUiStateOptions = {
        updatingProxyId: selectIntent.proxyId
      };
      return reduced(state.copyWith(options), [new EnableProxyEffect(selectIntent.proxyId)]);
    }

    case 'saveProxy': {
      const saveIntent: SaveProxy = intent as SaveProxy;
      if (state.updatingProxyId !== null) {
        return reduced(state);
      }
      // 页面已经把「完成」置灰，这里再挡一道：表单不能凭空绕过校验写出去。
      const errorKey: string = proxyFormError(saveIntent.form);
      if (errorKey.length > 0) {
        const options: SettingsUiStateOptions = {
          errorMessage: errorKey
        };
        return reduced(state.copyWith(options));
      }
      const options: SettingsUiStateOptions = {
        updatingProxyId: saveIntent.form.id,
        errorMessage: null
      };
      return reduced(state.copyWith(options), [new SaveProxyEffect(saveIntent.form)]);
    }

    case 'removeProxyRequested': {
      const removeIntent: RemoveProxyRequested = intent as RemoveProxyRequested;
      if (state.updatingProxyId !== null) {
        return reduced(state);
      }
      if (proxyItemById(state.proxyItems, removeIntent.proxyId) === null) {
        return reduced(state);
      }
      const options: SettingsUiStateOptions = {
        updatingProxyId: removeIntent.proxyId
      };
      return reduced(state.copyWith(options), [new RemoveProxyEffect(removeIntent.proxyId)]);
    }

    // ---- PROXY-102 连通性探测与连接态 ----

    case 'proxyPingUpdated': {
      const pingIntent: ProxyPingUpdated = intent as ProxyPingUpdated;
      // 行已经不在了（被删了或列表重建过）就别再写：晚到的回包不该复活一个探测值。
      if (pingIntent.proxyId !== PROXY_NONE_ID &&
        proxyItemById(state.proxyItems, pingIntent.proxyId) === null) {
        return reduced(state);
      }
      const options: SettingsUiStateOptions = {
        proxyPingMs: proxyPingsWith(state.proxyPingMs, pingIntent.proxyId, pingIntent.pingMs),
        // 两张表同一个口径写：成功探测要把上一次的失败原因擦掉，否则「Error」的句子还在、
        // 延迟也跟着显示，读起来的是一句自相矛盾的话。
        proxyPingFailure: proxyFailuresWith(state.proxyPingFailure, pingIntent.proxyId, pingIntent.failureKey)
      };
      return reduced(state.copyWith(options));
    }

    case 'proxyConnectionStateChanged': {
      const connectionIntent: ProxyConnectionStateChanged = intent as ProxyConnectionStateChanged;
      const previous: ProxyConnectionState = state.proxyConnection;
      if (previous === connectionIntent.connection) {
        return reduced(state);
      }
      const options: SettingsUiStateOptions = {
        proxyConnection: connectionIntent.connection
      };
      // 只在真的「断了又通」时重测：断网期间那批探测值是按旧网络出来的。
      // 首帧 unknown → ready 不重测，否则每次进页都要多发一轮。
      const recovered: boolean = connectionIntent.connection === 'ready' &&
        previous !== 'unknown' && state.showProxyPage;
      if (recovered) {
        return reduced(state.copyWith(options), [new PingProxiesEffect()]);
      }
      return reduced(state.copyWith(options));
    }

    // ---- AUTODL-101 自动媒体下载 ----

    case 'openAutoDownloadPage': {
      const options: SettingsUiStateOptions = {
        showAutoDownloadPage: true,
        errorMessage: null
      };
      // 每次进子页都重读一遍：策略是本机偏好，别处（聊天页）不会改，
      // 但进程重启后首次进来必须拿到盘上的值，而不是 initial() 的 null。
      return reduced(state.copyWith(options), [new LoadAutoDownloadPolicyEffect()]);
    }

    case 'closeAutoDownloadPage': {
      if (!state.showAutoDownloadPage) {
        return reduced(state);
      }
      const options: SettingsUiStateOptions = {
        showAutoDownloadPage: false
      };
      return reduced(state.copyWith(options));
    }

    case 'loadAutoDownloadPolicy': {
      return reduced(state, [new LoadAutoDownloadPolicyEffect()]);
    }

    case 'autoDownloadPolicyLoaded': {
      const loadedIntent: AutoDownloadPolicyLoaded = intent as AutoDownloadPolicyLoaded;
      const options: SettingsUiStateOptions = {
        autoDownloadPolicy: loadedIntent.policy,
        errorMessage: null
      };
      return reduced(state.copyWith(options));
    }

    case 'setAutoDownloadKind': {
      const setIntent: SetAutoDownloadKind = intent as SetAutoDownloadKind;
      const policy: AutoDownloadPolicy | null = state.autoDownloadPolicy;
      // 还没读到盘上的策略就忽略勾选：此时写回等于用猜出来的默认覆盖用户偏好。
      if (policy === null) {
        return reduced(state);
      }
      const flags: AutoDownloadFlags = policy.flagsOf(setIntent.scope);
      if (flags.of(setIntent.mediaKind) === setIntent.enabled) {
        // Toggle 的 onChange 在挂载时会回调一次初值，同值不算变更、不该落盘。
        return reduced(state);
      }
      const next: AutoDownloadPolicy = policy.withFlags(
        setIntent.scope,
        flags.with(setIntent.mediaKind, setIntent.enabled)
      );
      const options: SettingsUiStateOptions = {
        autoDownloadPolicy: next,
        errorMessage: null
      };
      return reduced(state.copyWith(options), [new PersistAutoDownloadPolicyEffect(next)]);
    }

    // ---- AUTODL-102 省流量（Data Saver）----
    // 与自动下载同一子页、同一套「读盘 → 勾选即写回 → 以存储返回值回灌」的流程，
    // 但走另一个偏好键：Android 就是把 settings_datasaver 与 settings_autodownload 分开存。

    case 'loadDataSaverSettings': {
      return reduced(state, [new LoadDataSaverSettingsEffect()]);
    }

    case 'dataSaverSettingsLoaded': {
      const loadedIntent: DataSaverSettingsLoaded = intent as DataSaverSettingsLoaded;
      const options: SettingsUiStateOptions = {
        dataSaverSettings: loadedIntent.settings,
        errorMessage: null
      };
      return reduced(state.copyWith(options));
    }

    case 'setDataSaverFlag': {
      const flagIntent: SetDataSaverFlag = intent as SetDataSaverFlag;
      const settings: DataSaverSettings | null = state.dataSaverSettings;
      // 同 setAutoDownloadKind：没读到盘就不写，否则会用猜出来的默认覆盖用户偏好。
      if (settings === null) {
        return reduced(state);
      }
      if (settings.ofFlag(flagIntent.flag) === flagIntent.enabled) {
        // Toggle 挂载时会回调一次初值，同值不算变更、不该落盘。
        return reduced(state);
      }
      const next: DataSaverSettings = settings.withFlag(flagIntent.flag, flagIntent.enabled);
      const options: SettingsUiStateOptions = {
        dataSaverSettings: next,
        errorMessage: null
      };
      return reduced(state.copyWith(options), [new PersistDataSaverSettingsEffect(next)]);
    }

    // ---- AUTODL-103 按网络类型的自动下载限制 ----
    // 第三份独立设置（Android 的 settings_limit_wifi|mobile|roaming）：同一子页、
    // 同一套「读盘 → 改即写回 → 以存储返回值回灌」，但每档网络各自一格，
    // 一次写回整份三档六格，避免只写半套留下互相矛盾的限制。

    case 'loadDownloadLimits': {
      return reduced(state, [new LoadDownloadLimitsEffect()]);
    }

    case 'downloadLimitsLoaded': {
      const loadedIntent: DownloadLimitsLoaded = intent as DownloadLimitsLoaded;
      const options: SettingsUiStateOptions = {
        downloadLimits: loadedIntent.limits,
        errorMessage: null
      };
      return reduced(state.copyWith(options));
    }

    case 'setDownloadLimitSize': {
      const sizeIntent: SetDownloadLimitSize = intent as SetDownloadLimitSize;
      const limits: DownloadLimitsByNetwork | null = state.downloadLimits;
      // 同 setAutoDownloadKind：没读到盘就不写，否则会用猜出来的默认覆盖用户偏好。
      if (limits === null) {
        return reduced(state);
      }
      const current: NetworkDownloadLimits = limits.of(sizeIntent.network);
      if (current.sizeCode === sizeIntent.sizeCode) {
        // 单选列表重选当前档不算变更、不该落盘。
        return reduced(state);
      }
      const next: DownloadLimitsByNetwork = limits.withNetwork(
        sizeIntent.network,
        current.withSizeCode(sizeIntent.sizeCode)
      );
      const options: SettingsUiStateOptions = {
        downloadLimits: next,
        errorMessage: null
      };
      return reduced(state.copyWith(options), [new PersistDownloadLimitsEffect(next)]);
    }

    case 'setDownloadLimitExclusion': {
      const excludeIntent: SetDownloadLimitExclusion = intent as SetDownloadLimitExclusion;
      const limits: DownloadLimitsByNetwork | null = state.downloadLimits;
      if (limits === null) {
        return reduced(state);
      }
      const current: NetworkDownloadLimits = limits.of(excludeIntent.network);
      if (current.isExcluded(excludeIntent.mediaKind) === excludeIntent.excluded) {
        // Toggle 挂载时会回调一次初值，同值不算变更、不该落盘。
        return reduced(state);
      }
      const next: DownloadLimitsByNetwork = limits.withNetwork(
        excludeIntent.network,
        current.withExcluded(excludeIntent.mediaKind, excludeIntent.excluded)
      );
      const options: SettingsUiStateOptions = {
        downloadLimits: next,
        errorMessage: null
      };
      return reduced(state.copyWith(options), [new PersistDownloadLimitsEffect(next)]);
    }


    // ---- APPLOCK-101 应用锁（Passcode）----
    // 判据全在 core/domain 的 `passcodeStepFor`：键盘在设置页和锁屏遮罩是两套界面，
    // 「什么时候算一次提交、提交完该进哪一步」必须只有一个答案。

    case 'openPasscodePage': {
      const options: SettingsUiStateOptions = {
        showPasscodePage: true,
        passcodeFlow: 'idle',
        passcodeNotice: null,
        errorMessage: null
      };
      // 每次进来重读盘：PIN 与档位是本机状态，别的入口（锁屏遮罩）会改它。
      return reduced(state.copyWith(options), [new LoadPasscodeStateEffect()]);
    }

    case 'closePasscodePage': {
      if (!state.showPasscodePage) {
        return reduced(state);
      }
      const options: SettingsUiStateOptions = {
        showPasscodePage: false,
        passcodeFlow: 'idle',
        isUpdatingPasscode: false,
        passcodeNotice: null
      };
      return reduced(state.copyWith(options), [new ClearPasscodeDraftEffect()]);
    }

    case 'loadPasscodeState': {
      return reduced(state, [new LoadPasscodeStateEffect()]);
    }

    case 'passcodeStateLoaded': {
      const loaded: PasscodeStateLoaded = intent as PasscodeStateLoaded;
      const options: SettingsUiStateOptions = {
        passcodeIsSet: loaded.isSet,
        autoLockChoice: loaded.autoLock,
        passcodeVisible: loaded.visible,
        isUpdatingPasscode: false
      };
      return reduced(state.copyWith(options));
    }

    case 'togglePasscodeRequested': {
      // 在途时重复点行不放行：两次写同一个秘密值没有意义，且第二次的结论会盖掉第一次的提示。
      if (state.isUpdatingPasscode || state.passcodeFlow !== 'idle') {
        return reduced(state);
      }
      const options: SettingsUiStateOptions = {
        passcodeFlow: state.passcodeIsSet ? 'verify-disable' : 'enter',
        passcodeNotice: null
      };
      return reduced(state.copyWith(options));
    }

    case 'changePasscodeRequested': {
      if (state.isUpdatingPasscode || state.passcodeFlow !== 'idle' || !state.passcodeIsSet) {
        return reduced(state);
      }
      const options: SettingsUiStateOptions = {
        passcodeFlow: 'verify-change',
        passcodeNotice: null
      };
      return reduced(state.copyWith(options));
    }

    case 'cycleAutoLockChoice': {
      const next: AutoLockChoice = nextAutoLockChoice(state.autoLockChoice);
      const options: SettingsUiStateOptions = {
        autoLockChoice: next
      };
      // 乐观改档：写盘失败时 coordinator 回灌 `autoLockChoiceRejected`。
      return reduced(state.copyWith(options), [new PersistAutoLockChoiceEffect(next)]);
    }

    case 'autoLockChoiceRejected': {
      const rejected: AutoLockChoiceRejected = intent as AutoLockChoiceRejected;
      const options: SettingsUiStateOptions = {
        autoLockChoice: rejected.previous,
        errorMessage: 'Failed to save the setting.'
      };
      return reduced(state.copyWith(options));
    }

    case 'togglePasscodeVisible': {
      const next: boolean = !state.passcodeVisible;
      const options: SettingsUiStateOptions = {
        passcodeVisible: next
      };
      // 乐观翻转，写盘失败由 coordinator 回灌 `passcodeVisibleRejected`。
      return reduced(state.copyWith(options), [new PersistPasscodeVisibleEffect(next)]);
    }

    case 'passcodeVisibleRejected': {
      const rejected: PasscodeVisibleRejected = intent as PasscodeVisibleRejected;
      const options: SettingsUiStateOptions = {
        passcodeVisible: rejected.previous,
        errorMessage: 'Failed to save the setting.'
      };
      return reduced(state.copyWith(options));
    }

    case 'cancelPasscodeFlow': {
      if (state.passcodeFlow === 'idle') {
        return reduced(state);
      }
      const options: SettingsUiStateOptions = {
        passcodeFlow: 'idle',
        isUpdatingPasscode: false,
        passcodeNotice: null
      };
      return reduced(state.copyWith(options), [new ClearPasscodeDraftEffect()]);
    }

    case 'passcodeSubmitted': {
      const submitted: PasscodeSubmitted = intent as PasscodeSubmitted;
      const step: PasscodeStepResult = passcodeStepFor(state.passcodeFlow, submitted.pin);
      if (step.action === 'ignore') {
        return reduced(state);
      }
      if (step.action === 'invalid') {
        const options: SettingsUiStateOptions = {
          passcodeNotice: APP_LOCK_NOTICE_INVALID
        };
        return reduced(state.copyWith(options));
      }
      if (step.action === 'draft') {
        const flowOptions: SettingsUiStateOptions = {
          passcodeFlow: 'confirm',
          passcodeNotice: null
        };
        return reduced(state.copyWith(flowOptions), [new StorePasscodeDraftEffect(submitted.pin)]);
      }
      if (step.action === 'commit') {
        const busyOptions: SettingsUiStateOptions = {
          isUpdatingPasscode: true,
          passcodeNotice: null
        };
        return reduced(state.copyWith(busyOptions), [new CommitPasscodeEffect(submitted.pin)]);
      }
      const purpose: 'disable' | 'change' = state.passcodeFlow === 'verify-change' ? 'change' : 'disable';
      const verifyOptions: SettingsUiStateOptions = {
        isUpdatingPasscode: true,
        passcodeNotice: null
      };
      return reduced(state.copyWith(verifyOptions), [new VerifyPasscodeEffect(submitted.pin, purpose)]);
    }

    case 'passcodeVerified': {
      const verified: PasscodeVerified = intent as PasscodeVerified;
      if (verified.purpose === 'change') {
        // 旧密码验过 → 直接进「输入新密码」；草稿清掉，新密码要从头输两遍。
        const options: SettingsUiStateOptions = {
          passcodeFlow: 'enter',
          isUpdatingPasscode: false,
          passcodeNotice: null
        };
        return reduced(state.copyWith(options), [new ClearPasscodeDraftEffect()]);
      }
      // 'disable'：coordinator 紧接着抹掉秘密值，成功回 `passcodeOperationDone`。
      const options: SettingsUiStateOptions = {
        isUpdatingPasscode: false
      };
      return reduced(state.copyWith(options));
    }

    case 'passcodeRejected': {
      const rejected: PasscodeRejected = intent as PasscodeRejected;
      const options: SettingsUiStateOptions = {
        isUpdatingPasscode: false,
        passcodeNotice: rejected.noticeKey
      };
      // 阶段不动：密码错了留在原地重输，锁屏那边同一条规则。
      return reduced(state.copyWith(options));
    }

    case 'passcodeMismatched': {
      const options: SettingsUiStateOptions = {
        passcodeFlow: 'enter',
        isUpdatingPasscode: false,
        passcodeNotice: APP_LOCK_NOTICE_MISMATCH
      };
      return reduced(state.copyWith(options), [new ClearPasscodeDraftEffect()]);
    }

    case 'passcodeOperationFailed': {
      const failed: PasscodeOperationFailed = intent as PasscodeOperationFailed;
      const options: SettingsUiStateOptions = {
        passcodeFlow: 'idle',
        isUpdatingPasscode: false,
        passcodeNotice: failed.noticeKey
      };
      return reduced(state.copyWith(options), [new ClearPasscodeDraftEffect()]);
    }

    case 'passcodeOperationDone': {
      const done: PasscodeOperationDone = intent as PasscodeOperationDone;
      const options: SettingsUiStateOptions = {
        passcodeFlow: 'idle',
        isUpdatingPasscode: false,
        passcodeIsSet: done.isSet,
        passcodeNotice: done.noticeKey
      };
      return reduced(state.copyWith(options), [new ClearPasscodeDraftEffect()]);
    }

    default:
      return reduced(state);
  }
};
