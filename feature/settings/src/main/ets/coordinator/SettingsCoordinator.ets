/**
 * feature/settings — 设置页协调器（SET-101）。
 *
 * 桥接 AccountScope / UserRegistry / TDLib Gateway：
 * - start() 时派发 LoadUserProfile；
 * - 处理 LogoutEffect：调用 scope.request('logOut') 并导航回登录或通知上层；
 * - 提供状态订阅 subscribe(listener: (state: SettingsUiState) => void): () => void;
 * - 统一异常捕获与 error message 处理。
 */

import { Logger } from '@tgx/observability';
import {
  AppError,
  AppErrors,
  Lang,
  LanguagePreference,
  ManualClock,
  Result,
  SequentialIdGenerator,
  SupportedLanguage,
  err,
  ok
} from '@tgx/core-common';
import { AccountScope } from '@tgx/core-account';
import {
  APP_LOCK_ERROR_STORE,
  APP_LOCK_ERROR_WRONG,
  APP_LOCK_NOTICE_REMOVED,
  APP_LOCK_NOTICE_SAVED,
  AUTO_LOCK_DEFAULT,
  appLockNoticeKeyForError,
  AutoDownloadPolicy,
  AutoLockChoice,
  AppLockStore,
  AutoDownloadPolicyStore,
  DataSaverSettings,
  DataSaverStore,
  DownloadLimitsByNetwork,
  DownloadLimitsStore,
  UserRegistry
} from '@tgx/core-domain';
import {
  GetMe,
  GetScopeNotificationSettings,
  GetStorageStatistics,
  GetUserFullInfo,
  LogOut,
  NotificationSettingsScopeChannelChats,
  NotificationSettingsScopeGroupChats,
  NotificationSettingsScopePrivateChats,
  OptimizeStorage,
  ScopeNotificationSettings,
  SetScopeNotificationSettings,
  StorageStatistics,
  TdJsonRaw,
  User,
  UserFullInfo,
  TdNotificationSettingsScope,
  decodeScopeNotificationSettings,
  decodeStorageStatistics,
  decodeUser,
  decodeUserFullInfo,
  encodeGetMe,
  encodeGetScopeNotificationSettings,
  encodeGetStorageStatistics,
  encodeGetUserFullInfo,
  encodeLogOut,
  encodeOptimizeStorage,
  encodeSetScopeNotificationSettings,
  GetActiveSessions,
  encodeGetActiveSessions,
  Sessions,
  decodeSessions,
  Session,
  TerminateSession,
  encodeTerminateSession,
  TerminateAllOtherSessions,
  encodeTerminateAllOtherSessions,
  GetUserPrivacySettingRules,
  encodeGetUserPrivacySettingRules,
  SetUserPrivacySettingRules,
  encodeSetUserPrivacySettingRules,
  UserPrivacySettingRules,
  TdUserPrivacySettingRule,
  decodeUserPrivacySettingRules,
  AddedProxies,
  AddedProxy,
  DisableProxy,
  EditProxy,
  EnableProxy,
  GetProxies,
  RemoveProxy,
  AddProxy,
  ProxyValue,
  PingProxy,
  Seconds,
  TdConnectionState,
  UpdateConnectionState,
  decodeAddedProxies,
  decodeSeconds,
  decodeUpdateConnectionState,
  encodeAddProxy,
  encodeDisableProxy,
  encodeEditProxy,
  encodeEnableProxy,
  encodeGetProxies,
  encodePingProxy,
  encodeRemoveProxy
} from '@tgx/core-td-api-generated';
import {
  TdPendingRequest,
  TdRoutedEvent,
  TdUpdateFilter,
  TdUpdateSubscription,
  TdWireObject
} from '@tgx/td-gateway';
import { ReducerEnv, ReducerResult } from '@tgx/feature-template';
import { SettingsUiState } from '../contract/SettingsUiState';
import { formatStorageLabel } from '../model/StorageSize';
import {
  NotificationScopeKey,
  areNotificationsEnabled,
  isNotificationScopeEnabled,
  withNotificationsEnabled
} from '../model/NotificationSettings';
import { ActiveSessionItem } from '../model/ActiveSessionItem';
import {
  choiceFromRules,
  PrivacyChoice,
  PrivacySettingItem,
  PrivacySettingKey,
  PRIVACY_SETTING_KEYS,
  privacySettingLabel,
  rulesForChoice,
  toUserPrivacySetting
} from '../model/PrivacySettings';
import {
  classifyProxyFailure,
  pingProxyRequestFromItem,
  PROXY_NONE_ID,
  PROXY_PING_FAILED,
  PROXY_PING_LOADING,
  PROXY_PING_TIMEOUT_KEY,
  PROXY_PING_TIMEOUT_MS,
  ProxyForm,
  ProxyItem,
  PROXY_NEW_ID,
  proxyConnectionStateOfType,
  proxyEnabledCount,
  proxyItemFromAdded,
  proxyPingMsOfSeconds,
  proxyPingOf,
  proxyTdlibCodeOf,
  proxyValueFromForm
} from '../model/ProxySettings';
import {
  ActiveSessionsLoaded,
  ActiveSessionsLoadFailed,
  CacheCleared,
  LoadActiveSessions,
  LoadNotificationSettings,
  LoadStorageStats,
  LoadUserProfile,
  NotificationScopeUpdated,
  NotificationScopeUpdateFailed,
  NotificationSettingsLoaded,
  NotificationSettingsUpdated,
  NotificationSettingsUpdateFailed,
  ProfileLoaded,
  PrivacySettingsLoaded,
  PrivacySettingUpdated,
  PrivacySettingUpdateFailed,
  SetAvailableAccounts,
  SetErrorMessage,
  SettingsIntent,
  StorageStatsLoaded,
  UserProfileData,
  ProxiesLoaded,
  ProxyPingUpdated,
  ProxyConnectionStateChanged,
  LoadAutoDownloadPolicy,
  AutoDownloadPolicyLoaded,
  DataSaverSettingsLoaded,
  DownloadLimitsLoaded,
  AutoLockChoiceRejected,
  TogglePasscodeVisible,
  PasscodeVisibleRejected,
  PasscodeMismatched,
  PasscodeOperationDone,
  PasscodeOperationFailed,
  PasscodeRejected,
  PasscodeStateLoaded,
  PasscodeVerified
} from '../contract/SettingsIntent';
import {
  ClearCacheEffect,
  LoadActiveSessionsEffect,
  LoadNotificationSettingsEffect,
  LoadProfileEffect,
  LoadStorageStatsEffect,
  LogoutEffect,
  NavigateToAuthEffect,
  RequestAddAccountEffect,
  SettingsEffect,
  SetNotificationScopeEnabledEffect,
  SetNotificationsEnabledEffect,
  ShowToastEffect,
  SwitchAccountEffect,
  TerminateAllOtherSessionsEffect,
  TerminateSessionEffect,
  LoadPrivacySettingsEffect,
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
  PersistDownloadLimitsEffect,
  ClearPasscodeDraftEffect,
  CommitPasscodeEffect,
  LoadPasscodeStateEffect,
  PersistAutoLockChoiceEffect,
  PersistPasscodeVisibleEffect,
  StorePasscodeDraftEffect,
  VerifyPasscodeEffect
} from '../contract/SettingsEffect';
import { settingsReducer } from '../reducer/SettingsReducer';
import { Theme, ThemeManager } from '@tgx/core-design-system';

const TAG: string = 'SettingsCoordinator';

/** 日志用的规则类型串：排查「写进去的和回读回来的不是一条」时唯一可辨识的信息。 */
function privacyRuleTypesForLog(rules: TdUserPrivacySettingRule[]): string {
  const types: string[] = [];
  for (let i = 0; i < rules.length; i++) {
    types.push(rules[i].type);
  }
  return types.join(',');
}

export type SettingsUiStateListener = (state: SettingsUiState) => void;

export class SettingsCoordinator {
  private readonly scope: AccountScope;
  private readonly userRegistry: UserRegistry;
  private readonly env: ReducerEnv;
  private readonly onNavigateToAuth: () => void;
  private readonly onSwitchAccount: (accountKey: string) => void;
  private readonly onRequestAddAccount: () => void;
  private readonly logger: Logger;
  private currentState: SettingsUiState;
  private readonly listeners: SettingsUiStateListener[] = [];
  private unsubscribeUser: (() => void) | null = null;
  private unsubscribeTheme: (() => void) | null = null;
  private unsubscribeLang: (() => void) | null = null;
  private subscribedUserId: number = 0;
  private notificationScopeSettings: ScopeNotificationSettings[] = [];
  /**
   * AUTODL-101：自动下载策略的落盘端口，由装配层（entry）注入。
   * 用 setter 而不是构造参数：构造已经有 9 个位置参数，再加一位会让每个调用点都跟着改，
   * 而这一位是可选能力（缺省时页面显示的就是默认策略，行为与 TGX 首装一致）。
   */
  private autoDownloadStore: AutoDownloadPolicyStore | null = null;
  /** APPLOCK-101：应用锁存储；由 entry 装配层注入，未注入时子页各行只读不回写。 */
  private appLockStore: AppLockStore | null = null;
  /**
   * 「输入两次」流程里第一次的草稿。
   * 刻意不进 `SettingsUiState`：状态每帧被复制、可能被日志与调试面板快照，密码这种
   * 短秘密值一旦进了状态就到处留副本。草稿只活在本 coordinator 实例的内存里，
   * 取消 / 关闭子页 / 写盘失败都会由 `clearPasscodeDraft` effect 抹掉。
   */
  private passcodeDraft: string | null = null;
  /**
   * AUTODL-102：省流量设置的落盘端口。同样是 setter 注入、同样可选 ——
   * 没注入时页面显默认档（只勾「漫游」），与 Android 首装一致。
   */
  private dataSaverStore: DataSaverStore | null = null;
  /**
   * AUTODL-103：按网络档的自动下载限制落盘端口。同样 setter 注入、同样可选 ——
   * 没注入时页面显 Android 默认（Wi-Fi 50MB / 移动 15MB / 漫游 5MB）。
   */
  private downloadLimitsStore: DownloadLimitsStore | null = null;
  /**
   * PROXY-102：探测轮次令牌。TDLib 不会取消已经发出去的 `pingProxy`，所以晚到的
   * 旧轮回包只能靠世代号丢 —— 不丢就会出现「代理已删除，那一行又亮起来」。
   */
  private pingGeneration: number = 0;
  /** PROXY-102：`updateConnectionState` 订阅；首次读代理列表时建立，destroy 时退订。 */
  private connectionSubscription: TdUpdateSubscription | null = null;
  private destroyed: boolean = false;

  /** 注入策略存储；必须在 start() 之前调用。 */
  setAutoDownloadStore(store: AutoDownloadPolicyStore | null): void {
    this.autoDownloadStore = store;
  }

  /**
   * APPLOCK-101：注入应用锁存储（entry 装配层调）。传 null 表示这台设备没接上安全存储，
   * 此时子页仍然可读档位，但任何 PIN 写回都会回 `passcodeOperationFailed` —— 不做静默降级，
   * 因为「界面说已开启、实际没有密码」是最坏的一种谎。
   */
  setAppLockStore(store: AppLockStore | null): void {
    this.appLockStore = store;
    this.passcodeDraft = null;
  }

  /** 注入省流量设置存储；必须在 start() 之前调用。 */
  setDataSaverStore(store: DataSaverStore | null): void {
    this.dataSaverStore = store;
  }

  /** 注入按网络档的限制存储；必须在 start() 之前调用。 */
  setDownloadLimitsStore(store: DownloadLimitsStore | null): void {
    this.downloadLimitsStore = store;
  }

  constructor(
    scope: AccountScope,
    userRegistry?: UserRegistry,
    env?: ReducerEnv,
    onNavigateToAuth?: () => void,
    logger?: Logger,
    onSwitchAccount?: (accountKey: string) => void,
    onRequestAddAccount?: () => void,
    currentAccountKey?: string,
    availableAccounts?: readonly string[]
  ) {
    this.scope = scope;
    this.userRegistry = userRegistry !== undefined ? userRegistry : new UserRegistry(scope);
    this.env = env !== undefined ? env : {
      clock: new ManualClock(1000, 500),
      ids: new SequentialIdGenerator('settings-')
    };
    this.onNavigateToAuth = onNavigateToAuth !== undefined ? onNavigateToAuth : (): void => {};
    this.onSwitchAccount = onSwitchAccount !== undefined ? onSwitchAccount : (_key: string): void => {};
    this.onRequestAddAccount = onRequestAddAccount !== undefined ? onRequestAddAccount : (): void => {};
    this.logger = logger !== undefined ? logger : new Logger();
    this.currentState = SettingsUiState.initial(
      'system',
      'system',
      'en',
      currentAccountKey !== undefined ? currentAccountKey : '',
      availableAccounts !== undefined ? availableAccounts : []
    );

    const currentThemePref = ThemeManager.getInstance().getPreference();
    if (this.currentState.themeMode !== currentThemePref) {
      this.currentState = this.currentState.copyWith({ themeMode: currentThemePref });
    }

    // FEAT-UI-002 / SET-105：与 ThemeManager 的字号对齐。
    // entry 启动时已把持久化字号灌进 ThemeManager，这里是设置页的首次同步。
    const currentFontSize: number = ThemeManager.getInstance().getChatFontSize();
    if (this.currentState.chatFontSize !== currentFontSize) {
      this.currentState = this.currentState.copyWith({ chatFontSize: currentFontSize });
    }

    const currentLangPref: LanguagePreference = Lang.getInstance().getPreference();
    const currentLangCode: string = Lang.getInstance().getLanguage();
    if (this.currentState.languagePreference !== currentLangPref || this.currentState.languageCode !== currentLangCode) {
      this.currentState = this.currentState.copyWith({
        languagePreference: currentLangPref,
        languageCode: currentLangCode
      });
    }

    const self: SettingsCoordinator = this;
    this.unsubscribeTheme = ThemeManager.getInstance().subscribe((_theme: Theme): void => {
      if (self.destroyed) {
        return;
      }
      const pref = ThemeManager.getInstance().getPreference();
      const fontSize: number = ThemeManager.getInstance().getChatFontSize();
      // 字号与主题共用这一条订阅：两者都会重建 Theme 对象，分开订阅会重复通知。
      if (self.currentState.themeMode !== pref || self.currentState.chatFontSize !== fontSize) {
        self.currentState = self.currentState.copyWith({
          themeMode: pref,
          chatFontSize: fontSize
        });
        for (let i = 0; i < self.listeners.length; i++) {
          self.listeners[i](self.currentState);
        }
      }
    });

    this.unsubscribeLang = Lang.getInstance().subscribe((lang: SupportedLanguage, pref: LanguagePreference): void => {
      if (self.destroyed) {
        return;
      }
      if (self.currentState.languagePreference !== pref || self.currentState.languageCode !== lang) {
        self.currentState = self.currentState.copyWith({
          languagePreference: pref,
          languageCode: lang
        });
        for (let i = 0; i < self.listeners.length; i++) {
          self.listeners[i](self.currentState);
        }
      }
    });
  }

  get state(): SettingsUiState {
    return this.currentState;
  }

  start(): void {
    this.dispatch(new LoadUserProfile());
    this.dispatch(new LoadNotificationSettings());
    // SET-104：进页即静默拉一次真实存储占用（此前 storageCacheSize 是硬编码占位）。
    this.dispatch(new LoadStorageStats());
    // AUTODL-101：策略行在「数据与存储」卡片里，进页就要有真实副标题。
    this.dispatch(new LoadAutoDownloadPolicy());
  }

  destroy(): void {
    this.destroyed = true;
    if (this.unsubscribeUser !== null) {
      this.unsubscribeUser();
      this.unsubscribeUser = null;
    }
    if (this.unsubscribeTheme !== null) {
      this.unsubscribeTheme();
      this.unsubscribeTheme = null;
    }
    if (this.unsubscribeLang !== null) {
      this.unsubscribeLang();
      this.unsubscribeLang = null;
    }
    if (this.connectionSubscription !== null) {
      this.connectionSubscription.unsubscribe();
      this.connectionSubscription = null;
    }
    this.listeners.length = 0;
  }

  subscribe(listener: SettingsUiStateListener): () => void {
    this.listeners.push(listener);
    listener(this.currentState);
    return (): void => {
      const idx: number = this.listeners.indexOf(listener);
      if (idx >= 0) {
        this.listeners.splice(idx, 1);
      }
    };
  }

  dispatch(intent: SettingsIntent): void {
    const result: ReducerResult<SettingsUiState, SettingsEffect> = settingsReducer(
      this.currentState,
      intent,
      this.env
    );

    const stateChanged: boolean = result.state !== this.currentState;
    this.currentState = result.state;

    if (stateChanged) {
      for (let i = 0; i < this.listeners.length; i++) {
        this.listeners[i](this.currentState);
      }
    }

    if (result.effects.length > 0) {
      for (let i = 0; i < result.effects.length; i++) {
        this.executeEffect(result.effects[i]);
      }
    }
  }

  private executeEffect(effect: SettingsEffect): void {
    switch (effect.kind) {
      case 'loadProfile':
        this.handleLoadProfile();
        break;

      case 'loadNotificationSettings':
        this.handleLoadNotificationSettings();
        break;

      case 'setNotificationsEnabled': {
        const notificationEffect: SetNotificationsEnabledEffect = effect as SetNotificationsEnabledEffect;
        this.handleSetNotificationsEnabled(notificationEffect.enabled);
        break;
      }

      case 'setNotificationScopeEnabled': {
        const scopeEffect: SetNotificationScopeEnabledEffect = effect as SetNotificationScopeEnabledEffect;
        this.handleSetNotificationScopeEnabled(scopeEffect.scope, scopeEffect.enabled);
        break;
      }

      case 'logout':
        this.handleLogout();
        break;

      case 'clearCache':
        this.handleClearCache();
        break;

      case 'loadStorageStats':
        this.handleLoadStorageStats();
        break;

      case 'navigateToAuth':
        this.logger.info(TAG, 'navigating_to_auth');
        this.onNavigateToAuth();
        break;

      case 'showToast': {
        const toastEffect: ShowToastEffect = effect as ShowToastEffect;
        this.logger.info(TAG, 'toast', toastEffect.message);
        break;
      }

      case 'switchAccount': {
        const switchEffect: SwitchAccountEffect = effect as SwitchAccountEffect;
        this.logger.info(TAG, 'switch_account', switchEffect.accountKey);
        this.onSwitchAccount(switchEffect.accountKey);
        break;
      }

      case 'requestAddAccount': {
        this.logger.info(TAG, 'request_add_account');
        this.onRequestAddAccount();
        break;
      }

      case 'loadActiveSessions':
        this.handleLoadActiveSessions();
        break;

      case 'terminateSession': {
        const termEffect: TerminateSessionEffect = effect as TerminateSessionEffect;
        this.handleTerminateSession(termEffect.sessionId);
        break;
      }

      case 'terminateAllOtherSessions':
        this.handleTerminateAllOtherSessions();
        break;

      case 'loadPrivacySettings':
        this.handleLoadPrivacySettings();
        break;

      case 'setPrivacySetting': {
        const privacyEffect: SetPrivacySettingEffect = effect as SetPrivacySettingEffect;
        this.handleSetPrivacySetting(privacyEffect.key, privacyEffect.choice);
        break;
      }

      case 'loadProxies':
        this.handleLoadProxies();
        break;

      case 'enableProxy': {
        const enableEffect: EnableProxyEffect = effect as EnableProxyEffect;
        this.handleEnableProxy(enableEffect.proxyId);
        break;
      }

      case 'disableProxy':
        this.handleDisableProxy();
        break;

      case 'saveProxy': {
        const saveEffect: SaveProxyEffect = effect as SaveProxyEffect;
        this.handleSaveProxy(saveEffect.form);
        break;
      }

      case 'removeProxy': {
        const removeEffect: RemoveProxyEffect = effect as RemoveProxyEffect;
        this.handleRemoveProxy(removeEffect.proxyId);
        break;
      }

      case 'pingProxies':
        this.handlePingProxies();
        break;

      case 'loadAutoDownloadPolicy':
        this.handleLoadAutoDownloadPolicy();
        break;

      case 'persistAutoDownloadPolicy': {
        const persistEffect: PersistAutoDownloadPolicyEffect = effect as PersistAutoDownloadPolicyEffect;
        this.handlePersistAutoDownloadPolicy(persistEffect.policy);
        break;
      }

      case 'loadDataSaverSettings':
        this.handleLoadDataSaverSettings();
        break;

      case 'persistDataSaverSettings': {
        const persistEffect: PersistDataSaverSettingsEffect = effect as PersistDataSaverSettingsEffect;
        this.handlePersistDataSaverSettings(persistEffect.settings);
        break;
      }

      case 'loadDownloadLimits':
        this.handleLoadDownloadLimits();
        break;

      case 'persistDownloadLimits': {
        const persistEffect: PersistDownloadLimitsEffect = effect as PersistDownloadLimitsEffect;
        this.handlePersistDownloadLimits(persistEffect.limits);
        break;
      }

      // ---- APPLOCK-101 应用锁 ----
      case 'loadPasscodeState':
        this.handleLoadPasscodeState();
        break;

      case 'storePasscodeDraft': {
        const draftEffect: StorePasscodeDraftEffect = effect as StorePasscodeDraftEffect;
        this.handleStorePasscodeDraft(draftEffect.pin);
        break;
      }

      case 'clearPasscodeDraft':
        this.handleClearPasscodeDraft();
        break;

      case 'commitPasscode': {
        const commitEffect: CommitPasscodeEffect = effect as CommitPasscodeEffect;
        this.handleCommitPasscode(commitEffect.pin);
        break;
      }

      case 'verifyPasscode': {
        const verifyEffect: VerifyPasscodeEffect = effect as VerifyPasscodeEffect;
        this.handleVerifyPasscode(verifyEffect.pin, verifyEffect.purpose);
        break;
      }

      case 'persistAutoLockChoice': {
        const choiceEffect: PersistAutoLockChoiceEffect = effect as PersistAutoLockChoiceEffect;
        this.handlePersistAutoLockChoice(choiceEffect.choice);
        break;
      }

      case 'persistPasscodeVisible': {
        const visibleEffect: PersistPasscodeVisibleEffect = effect as PersistPasscodeVisibleEffect;
        this.handlePersistPasscodeVisible(visibleEffect.visible);
        break;
      }

      default:
        break;
    }
  }

  setAccounts(accounts: readonly string[], currentAccountKey?: string): void {
    this.dispatch(new SetAvailableAccounts(accounts, currentAccountKey));
  }

  private handleLoadProfile(): void {
    const meReq: GetMe = new GetMe();
    const result: Result<TdPendingRequest, AppError> = this.scope.request(
      'getMe',
      encodeGetMe(meReq) as TdWireObject
    );

    if (result.ok) {
      const self: SettingsCoordinator = this;
      result.value.promise.then((res: Result<TdWireObject, AppError>): void => {
        if (res.ok) {
          const user: User | null = decodeUser(res.value as TdJsonRaw);
          if (user !== null) {
            self.userRegistry.putUser(user);
            self.fetchFullInfoAndDispatch(user);
          } else {
            self.dispatch(new SetErrorMessage('Failed to decode user profile'));
          }
        }
        if (res.err) {
          self.dispatch(new SetErrorMessage(res.error.message));
        }
      }).catch((e: Error): void => {
        self.dispatch(new SetErrorMessage(e.message));
      });
    }
    if (result.err) {
      this.dispatch(new SetErrorMessage(result.error.message));
    }
  }

  private fetchFullInfoAndDispatch(user: User): void {
    const fullReq: GetUserFullInfo = new GetUserFullInfo();
    fullReq.user_id = user.id;
    const result: Result<TdPendingRequest, AppError> = this.scope.request(
      'getUserFullInfo',
      encodeGetUserFullInfo(fullReq) as TdWireObject
    );

    if (result.ok) {
      const self: SettingsCoordinator = this;
      result.value.promise.then((res: Result<TdWireObject, AppError>): void => {
        let bio: string = '';
        if (res.ok) {
          const fullInfo: UserFullInfo | null = decodeUserFullInfo(res.value as TdJsonRaw);
          if (fullInfo !== null && fullInfo.bio !== null) {
            bio = fullInfo.bio.text;
          }
        }
        if (res.err) {
          this.logger.logError(TAG, res.error);
        }
        self.dispatchProfile(user, bio);
      }).catch((): void => {
        self.dispatchProfile(user, '');
      });
    }
    if (result.err) {
      this.dispatchProfile(user, '');
    }
  }

  private dispatchProfile(user: User, bio: string): void {
    const displayName: string = this.userRegistry.formatFullName(user);
    let username: string = '';
    if (user.usernames !== null) {
      if (user.usernames.active_usernames.length > 0) {
        username = user.usernames.active_usernames[0];
      } else if (user.usernames.editable_username.length > 0) {
        username = user.usernames.editable_username;
      }
    }
    let avatarPath: string | null = null;
    if (
      user.profile_photo !== null &&
      user.profile_photo.small !== null &&
      user.profile_photo.small.local !== null &&
      user.profile_photo.small.local.path.length > 0
    ) {
      avatarPath = user.profile_photo.small.local.path;
    }

    const profile: UserProfileData = {
      userId: user.id,
      displayName: displayName.length > 0 ? displayName : (username.length > 0 ? username : `User ${user.id}`),
      username: username,
      phoneNumber: user.phone_number,
      avatarLocalPath: avatarPath,
      bio: bio
    };

    this.dispatch(new ProfileLoaded(profile));
    this.subscribeUserUpdates(user.id);
  }

  private subscribeUserUpdates(userId: number): void {
    if (this.subscribedUserId === userId && this.unsubscribeUser !== null) {
      return;
    }
    if (this.unsubscribeUser !== null) {
      this.unsubscribeUser();
      this.unsubscribeUser = null;
    }
    this.subscribedUserId = userId;
    const self: SettingsCoordinator = this;
    const sub = this.userRegistry.subscribeUser(userId, (updatedUser: User): void => {
      if (!self.destroyed) {
        self.dispatchProfile(updatedUser, self.currentState.bio);
      }
    });
    this.unsubscribeUser = (): void => {
      sub.unsubscribe();
    };
  }

  private handleLogout(): void {
    const req: LogOut = new LogOut();
    const result: Result<TdPendingRequest, AppError> = this.scope.request(
      'logOut',
      encodeLogOut(req) as TdWireObject
    );

    if (result.ok) {
      const self: SettingsCoordinator = this;
      result.value.promise.then((res: Result<TdWireObject, AppError>): void => {
        if (res.ok) {
          self.executeEffect(new NavigateToAuthEffect());
        }
        if (res.err) {
          self.dispatch(new SetErrorMessage(res.error.message));
        }
      }).catch((e: Error): void => {
        self.dispatch(new SetErrorMessage(e.message));
      });
    }
    if (result.err) {
      this.dispatch(new SetErrorMessage(result.error.message));
    }
  }

  private notificationScopes(): TdNotificationSettingsScope[] {
    const scopes: TdNotificationSettingsScope[] = [];
    scopes.push(new NotificationSettingsScopePrivateChats());
    scopes.push(new NotificationSettingsScopeGroupChats());
    scopes.push(new NotificationSettingsScopeChannelChats());
    return scopes;
  }

  private async fetchNotificationSettings(
    scope: TdNotificationSettingsScope
  ): Promise<Result<ScopeNotificationSettings, AppError>> {
    const request: GetScopeNotificationSettings = new GetScopeNotificationSettings();
    request.scope = scope;
    const pendingResult: Result<TdPendingRequest, AppError> = this.scope.request(
      'getScopeNotificationSettings',
      encodeGetScopeNotificationSettings(request) as TdWireObject
    );
    if (pendingResult.ok) {
      const response: Result<TdWireObject, AppError> = await pendingResult.value.promise;
      if (response.ok) {
        const settings: ScopeNotificationSettings | null =
          decodeScopeNotificationSettings(response.value as TdJsonRaw);
        if (settings === null) {
          return err<ScopeNotificationSettings, AppError>(
            AppErrors.internal(
              'settings_notification_decode',
              'TDLib scope notification settings response could not be decoded'
            )
          );
        }
        return ok<ScopeNotificationSettings, AppError>(settings);
      }
      if (response.err) {
        return err<ScopeNotificationSettings, AppError>(response.error);
      }
      return err<ScopeNotificationSettings, AppError>(
        AppErrors.internal('settings_notification_response', 'TDLib returned no notification settings result')
      );
    }
    if (pendingResult.err) {
      return err<ScopeNotificationSettings, AppError>(pendingResult.error);
    }
    return err<ScopeNotificationSettings, AppError>(
      AppErrors.internal('settings_notification_request', 'TDLib notification settings request was not created')
    );
  }

  private async fetchAllNotificationSettings(): Promise<Result<ScopeNotificationSettings[], AppError>> {
    const scopes: TdNotificationSettingsScope[] = this.notificationScopes();
    const settings: ScopeNotificationSettings[] = [];
    for (let i = 0; i < scopes.length; i++) {
      const result: Result<ScopeNotificationSettings, AppError> =
        await this.fetchNotificationSettings(scopes[i]);
      if (result.ok) {
        settings.push(result.value);
      }
      if (result.err) {
        return err<ScopeNotificationSettings[], AppError>(result.error);
      }
    }
    return ok<ScopeNotificationSettings[], AppError>(settings);
  }

  private async writeNotificationSettings(
    scope: TdNotificationSettingsScope,
    settings: ScopeNotificationSettings
  ): Promise<Result<void, AppError>> {
    const request: SetScopeNotificationSettings = new SetScopeNotificationSettings();
    request.scope = scope;
    request.notification_settings = settings;
    const pendingResult: Result<TdPendingRequest, AppError> = this.scope.request(
      'setScopeNotificationSettings',
      encodeSetScopeNotificationSettings(request) as TdWireObject
    );
    if (pendingResult.ok) {
      const response: Result<TdWireObject, AppError> = await pendingResult.value.promise;
      if (response.ok) {
        return ok<void, AppError>(undefined);
      }
      if (response.err) {
        return err<void, AppError>(response.error);
      }
      return err<void, AppError>(
        AppErrors.internal('settings_notification_write_response', 'TDLib returned no notification write result')
      );
    }
    if (pendingResult.err) {
      return err<void, AppError>(pendingResult.error);
    }
    return err<void, AppError>(
      AppErrors.internal('settings_notification_write_request', 'TDLib notification write request was not created')
    );
  }

  private notificationErrorMessage(error: AppError, action: string): string {
    if (error.kind === 'tdlib' && error.code === 'too_many_requests') {
      return 'Too many requests. Please wait and try again.';
    }
    if (error.kind === 'network') {
      return `Unable to ${action} notification settings. Check your connection.`;
    }
    return `Unable to ${action} notification settings. Please try again.`;
  }

  private handleLoadNotificationSettings(): void {
    this.loadNotificationSettings();
  }

  private async loadNotificationSettings(): Promise<void> {
    try {
      const result: Result<ScopeNotificationSettings[], AppError> =
        await this.fetchAllNotificationSettings();
      if (this.destroyed) {
        return;
      }
      if (result.ok) {
        this.notificationScopeSettings = result.value;
        this.dispatch(new NotificationSettingsLoaded(
          areNotificationsEnabled(result.value),
          isNotificationScopeEnabled(result.value[0]),
          isNotificationScopeEnabled(result.value[1]),
          isNotificationScopeEnabled(result.value[2])
        ));
        return;
      }
      if (result.err) {
        this.logger.logError(TAG, result.error);
        this.dispatch(new NotificationSettingsUpdateFailed(
          this.notificationErrorMessage(result.error, 'load')
        ));
      }
    } catch (e) {
      if (this.destroyed) {
        return;
      }
      const cause: string = e instanceof Error ? e.name : 'non-error';
      const error: AppError = AppErrors.unknown(
        'settings-notification-load',
        'Unexpected notification settings load failure',
        cause
      );
      this.logger.logError(TAG, error);
      this.dispatch(new NotificationSettingsUpdateFailed(
        this.notificationErrorMessage(error, 'load')
      ));
    }
  }

  private handleSetNotificationsEnabled(enabled: boolean): void {
    this.setNotificationsEnabled(enabled);
  }

  private notificationScopeIndex(scope: NotificationScopeKey): number {
    if (scope === 'private') {
      return 0;
    }
    if (scope === 'group') {
      return 1;
    }
    return 2;
  }

  private handleSetNotificationScopeEnabled(scope: NotificationScopeKey, enabled: boolean): void {
    this.setNotificationScopeEnabled(scope, enabled);
  }

  private async setNotificationScopeEnabled(scope: NotificationScopeKey, enabled: boolean): Promise<void> {
    try {
      let currentSettings: ScopeNotificationSettings[] = this.notificationScopeSettings;
      if (currentSettings.length !== 3) {
        const loadResult: Result<ScopeNotificationSettings[], AppError> =
          await this.fetchAllNotificationSettings();
        if (loadResult.ok) {
          currentSettings = loadResult.value;
        }
        if (loadResult.err) {
          if (!this.destroyed) {
            this.logger.logError(TAG, loadResult.error);
            this.dispatch(new NotificationScopeUpdateFailed(
              scope,
              this.notificationErrorMessage(loadResult.error, 'update')
            ));
          }
          return;
        }
      }

      const index: number = this.notificationScopeIndex(scope);
      const next: ScopeNotificationSettings = withNotificationsEnabled(currentSettings[index], enabled);
      const writeResult: Result<void, AppError> =
        await this.writeNotificationSettings(this.notificationScopes()[index], next);
      if (writeResult.ok) {
        if (this.destroyed) {
          return;
        }
        const updatedSettings: ScopeNotificationSettings[] = [];
        for (let i = 0; i < currentSettings.length; i++) {
          updatedSettings.push(i === index ? next : currentSettings[i]);
        }
        this.notificationScopeSettings = updatedSettings;
        this.dispatch(new NotificationScopeUpdated(scope, enabled));
        return;
      }
      if (writeResult.err && !this.destroyed) {
        this.logger.logError(TAG, writeResult.error);
        this.dispatch(new NotificationScopeUpdateFailed(
          scope,
          this.notificationErrorMessage(writeResult.error, 'update')
        ));
      }
    } catch (e) {
      if (this.destroyed) {
        return;
      }
      const cause: string = e instanceof Error ? e.name : 'non-error';
      const error: AppError = AppErrors.unknown(
        'settings-notification-scope-update',
        'Unexpected notification scope update failure',
        cause
      );
      this.logger.logError(TAG, error);
      this.dispatch(new NotificationScopeUpdateFailed(
        scope,
        this.notificationErrorMessage(error, 'update')
      ));
    }
  }

  private async setNotificationsEnabled(enabled: boolean): Promise<void> {
    try {
      let currentSettings: ScopeNotificationSettings[] = this.notificationScopeSettings;
      if (currentSettings.length !== 3) {
        const loadResult: Result<ScopeNotificationSettings[], AppError> =
          await this.fetchAllNotificationSettings();
        if (loadResult.ok) {
          currentSettings = loadResult.value;
        }
        if (loadResult.err) {
          if (!this.destroyed) {
            this.logger.logError(TAG, loadResult.error);
            this.dispatch(new NotificationSettingsUpdateFailed(
              this.notificationErrorMessage(loadResult.error, 'update')
            ));
          }
          return;
        }
      }

      const scopes: TdNotificationSettingsScope[] = this.notificationScopes();
      const updatedSettings: ScopeNotificationSettings[] = [];
      for (let i = 0; i < scopes.length; i++) {
        const next: ScopeNotificationSettings = withNotificationsEnabled(currentSettings[i], enabled);
        const writeResult: Result<void, AppError> = await this.writeNotificationSettings(scopes[i], next);
        if (writeResult.err) {
          // Best-effort rollback keeps the three TDLib scopes from being left in a
          // mixed state when a later write fails after earlier scopes succeeded.
          for (let rollbackIndex = 0; rollbackIndex < updatedSettings.length; rollbackIndex++) {
            await this.writeNotificationSettings(scopes[rollbackIndex], currentSettings[rollbackIndex]);
          }
          if (!this.destroyed) {
            this.logger.logError(TAG, writeResult.error);
            this.dispatch(new NotificationSettingsUpdateFailed(
              this.notificationErrorMessage(writeResult.error, 'update')
            ));
            this.loadNotificationSettings();
          }
          return;
        }
        updatedSettings.push(next);
      }

      if (this.destroyed) {
        return;
      }
      this.notificationScopeSettings = updatedSettings;
      this.dispatch(new NotificationSettingsUpdated(enabled));
    } catch (e) {
      if (this.destroyed) {
        return;
      }
      const cause: string = e instanceof Error ? e.name : 'non-error';
      const error: AppError = AppErrors.unknown(
        'settings-notification-update',
        'Unexpected notification settings update failure',
        cause
      );
      this.logger.logError(TAG, error);
      this.dispatch(new NotificationSettingsUpdateFailed(
        this.notificationErrorMessage(error, 'update')
      ));
    }
  }

  /**
   * SET-104：拉取真实存储占用（getStorageStatistics）。
   * chat_limit=0 → 只算总量，不要按会话拆分的明细（设置页只需要总占用）；
   * 失败静默——设置页其它功能不受影响，保留上一次的显示值。
   */
  private handleLoadStorageStats(): void {
    const statsReq: GetStorageStatistics = new GetStorageStatistics();
    statsReq.chat_limit = 0;
    const result: Result<TdPendingRequest, AppError> = this.scope.request(
      'getStorageStatistics',
      encodeGetStorageStatistics(statsReq) as TdWireObject
    );

    if (result.ok) {
      const self: SettingsCoordinator = this;
      result.value.promise.then((res: Result<TdWireObject, AppError>): void => {
        if (self.destroyed) {
          return;
        }
        if (res.ok) {
          const stats: StorageStatistics | null = decodeStorageStatistics(res.value as TdJsonRaw);
          if (stats !== null) {
            self.dispatch(new StorageStatsLoaded(formatStorageLabel(stats.size, stats.count)));
          }
        }
        if (res.err) {
          this.logger.logError(TAG, res.error);
        }
      }).catch((): void => {
      });
    }
    if (result.err) {
      this.logger.logError(TAG, result.error);
    }
  }

  /**
   * SET-104：一键清理缓存（optimizeStorage）。
   *
   * size/ttl/count/immunity_delay 全传 0 = **删到剩 0 字节**（TDLib 里 -1 才是
   * "用默认上限"，0 是硬上限），file_types 留空即 TDLib 默认口径（缩略图/头像/
   * 贴纸/壁纸不删）。与 Android SettingsCacheController 的
   * `OptimizeStorage(0, 0, 0, 0, ...)` 完全一致。
   *
   * 清理后**用响应里返回的真实统计**刷新显示——响应就是清理后的整体
   * StorageStatistics（return_deleted_file_statistics=false），因此不必再发
   * 一次 getStorageStatistics；此前这里硬编码 '0 B' 是错的（数据库、语言包等
   * 非文件占用并不会被清掉，真实值通常不为 0）。
   */
  private handleClearCache(): void {
    const optReq: OptimizeStorage = new OptimizeStorage();
    optReq.size = 0;
    optReq.ttl = 0;
    optReq.count = 0;
    optReq.immunity_delay = 0;
    optReq.return_deleted_file_statistics = false;
    const result: Result<TdPendingRequest, AppError> = this.scope.request(
      'optimizeStorage',
      encodeOptimizeStorage(optReq) as TdWireObject
    );

    if (result.ok) {
      const self: SettingsCoordinator = this;
      result.value.promise.then((res: Result<TdWireObject, AppError>): void => {
        if (self.destroyed) {
          return;
        }
        if (res.ok) {
          const stats: StorageStatistics | null = decodeStorageStatistics(res.value as TdJsonRaw);
          const label: string = stats !== null
            ? formatStorageLabel(stats.size, stats.count)
            : '0 B';
          self.dispatch(new CacheCleared(label));
        }
        if (res.err) {
          self.dispatch(new SetErrorMessage(res.error.message));
        }
      }).catch((e: Error): void => {
        self.dispatch(new SetErrorMessage(e.message));
      });
    }
    if (result.err) {
      this.dispatch(new SetErrorMessage(result.error.message));
    }
  }

  /**
   * FEAT-P2-008：拉取活跃设备与登录会话列表（getActiveSessions）。
   */
  private handleLoadActiveSessions(): void {
    const req: GetActiveSessions = new GetActiveSessions();
    const result: Result<TdPendingRequest, AppError> = this.scope.request(
      'getActiveSessions',
      encodeGetActiveSessions(req) as TdWireObject
    );

    if (result.ok) {
      const self: SettingsCoordinator = this;
      result.value.promise.then((res: Result<TdWireObject, AppError>): void => {
        if (self.destroyed) {
          return;
        }
        if (res.ok) {
          const sessionsObj: Sessions | null = decodeSessions(res.value as TdJsonRaw);
          if (sessionsObj !== null && sessionsObj.sessions !== undefined) {
            const list: ActiveSessionItem[] = [];
            for (let i = 0; i < sessionsObj.sessions.length; i++) {
              const s: Session = sessionsObj.sessions[i];
              list.push({
                id: s.id,
                isCurrent: s.is_current,
                deviceModel: s.device_model,
                platform: s.platform,
                applicationName: s.application_name,
                applicationVersion: s.application_version,
                ipAddress: s.ip_address,
                location: s.location,
                lastActiveDate: s.last_active_date
              });
            }
            self.dispatch(new ActiveSessionsLoaded(list));
          } else {
            self.dispatch(new ActiveSessionsLoaded([]));
          }
        }
        if (res.err) {
          self.logger.logError(TAG, res.error);
          self.dispatch(new ActiveSessionsLoadFailed(res.error.message));
        }
      }).catch((e: Error): void => {
        self.dispatch(new ActiveSessionsLoadFailed(e.message));
      });
    }
    if (result.err) {
      this.logger.logError(TAG, result.error);
      this.dispatch(new ActiveSessionsLoadFailed(result.error.message));
    }
  }

  /**
   * FEAT-P2-008：终止指定设备会话（terminateSession）。
   */
  private handleTerminateSession(sessionId: string): void {
    const req: TerminateSession = new TerminateSession();
    req.session_id = sessionId;
    const result: Result<TdPendingRequest, AppError> = this.scope.request(
      'terminateSession',
      encodeTerminateSession(req) as TdWireObject
    );

    if (result.ok) {
      const self: SettingsCoordinator = this;
      result.value.promise.then((res: Result<TdWireObject, AppError>): void => {
        if (self.destroyed) {
          return;
        }
        if (res.ok) {
          self.dispatch(new LoadActiveSessions());
        }
        if (res.err) {
          self.logger.logError(TAG, res.error);
          self.dispatch(new SetErrorMessage(res.error.message));
        }
      }).catch((e: Error): void => {
        self.dispatch(new SetErrorMessage(e.message));
      });
    }
    if (result.err) {
      this.logger.logError(TAG, result.error);
      this.dispatch(new SetErrorMessage(result.error.message));
    }
  }

  /**
   * FEAT-P2-008：终止除当前设备外的所有会话（terminateAllOtherSessions）。
   */
  private handleTerminateAllOtherSessions(): void {
    const req: TerminateAllOtherSessions = new TerminateAllOtherSessions();
    const result: Result<TdPendingRequest, AppError> = this.scope.request(
      'terminateAllOtherSessions',
      encodeTerminateAllOtherSessions(req) as TdWireObject
    );

    if (result.ok) {
      const self: SettingsCoordinator = this;
      result.value.promise.then((res: Result<TdWireObject, AppError>): void => {
        if (self.destroyed) {
          return;
        }
        if (res.ok) {
          self.dispatch(new LoadActiveSessions());
        }
        if (res.err) {
          self.logger.logError(TAG, res.error);
          self.dispatch(new SetErrorMessage(res.error.message));
        }
      }).catch((e: Error): void => {
        self.dispatch(new SetErrorMessage(e.message));
      });
    }
    if (result.err) {
      this.logger.logError(TAG, result.error);
      this.dispatch(new SetErrorMessage(result.error.message));
    }
  }

  // ---- SELF-102 隐私和安全 ----

  /**
   * 读取 8 项隐私设置。
   * 串行而不是 Promise.all：TDLib 对同一连接的并发请求会回 too_many_requests，
   * 通知设置（SET-106）同口径处理，这里保持一致。
   * 单项失败不整屏报错，只把该项落成 unknown，其余 7 项照常显示。
   */
  private handleLoadPrivacySettings(): void {
    this.loadPrivacySettings();
  }

  private async loadPrivacySettings(): Promise<void> {
    try {
      const items: PrivacySettingItem[] = [];
      for (let i = 0; i < PRIVACY_SETTING_KEYS.length; i++) {
        const key: PrivacySettingKey = PRIVACY_SETTING_KEYS[i];
        const result: Result<PrivacyChoice, AppError> = await this.fetchPrivacyChoice(key);
        if (result.ok) {
          items.push(new PrivacySettingItem(key, result.value));
        }
        if (result.err) {
          this.logger.logError(TAG, result.error);
          items.push(new PrivacySettingItem(key, 'unknown'));
        }
      }
      if (this.destroyed) {
        return;
      }
      this.dispatch(new PrivacySettingsLoaded(items));
    } catch (e) {
      if (this.destroyed) {
        return;
      }
      const cause: string = e instanceof Error ? e.name : 'non-error';
      const error: AppError = AppErrors.unknown(
        'settings-privacy-load',
        'Unexpected privacy settings load failure',
        cause
      );
      this.logger.logError(TAG, error);
      this.dispatch(new PrivacySettingsLoaded([]));
      this.dispatch(new SetErrorMessage(this.privacyErrorMessage(error, 'load')));
    }
  }

  private handleSetPrivacySetting(key: PrivacySettingKey, choice: PrivacyChoice): void {
    this.setPrivacySetting(key, choice);
  }

  /**
   * 写回后回读该项，以服务端返回值驱动界面。
   * TDLib 会把规则原样存下来，但「写 A 读到 B」才是真问题（例如账号无 Premium
   * 时写 allowPremiumUsers 会被规范化），所以不能用请求值乐观更新。
   */
  private async setPrivacySetting(key: PrivacySettingKey, choice: PrivacyChoice): Promise<void> {
    try {
      const writeResult: Result<void, AppError> = await this.writePrivacyRules(key, choice);
      if (writeResult.err) {
        if (!this.destroyed) {
          this.logger.logError(TAG, writeResult.error);
          this.dispatch(new PrivacySettingUpdateFailed(
            key,
            this.privacyErrorMessage(writeResult.error, 'update')
          ));
        }
        return;
      }
      const readResult: Result<PrivacyChoice, AppError> = await this.fetchPrivacyChoice(key);
      if (this.destroyed) {
        return;
      }
      if (readResult.ok) {
        this.dispatch(new PrivacySettingUpdated(key, readResult.value));
        return;
      }
      if (readResult.err) {
        this.logger.logError(TAG, readResult.error);
        this.dispatch(new PrivacySettingUpdateFailed(
          key,
          this.privacyErrorMessage(readResult.error, 'update')
        ));
      }
    } catch (e) {
      if (this.destroyed) {
        return;
      }
      const cause: string = e instanceof Error ? e.name : 'non-error';
      const error: AppError = AppErrors.unknown(
        'settings-privacy-update',
        'Unexpected privacy setting update failure',
        cause
      );
      this.logger.logError(TAG, error);
      this.dispatch(new PrivacySettingUpdateFailed(key, this.privacyErrorMessage(error, 'update')));
    }
  }

  private async fetchPrivacyChoice(key: PrivacySettingKey): Promise<Result<PrivacyChoice, AppError>> {
    const request: GetUserPrivacySettingRules = new GetUserPrivacySettingRules();
    request.setting = toUserPrivacySetting(key);
    const pendingResult: Result<TdPendingRequest, AppError> = this.scope.request(
      'getUserPrivacySettingRules',
      encodeGetUserPrivacySettingRules(request) as TdWireObject
    );
    if (pendingResult.ok) {
      const response: Result<TdWireObject, AppError> = await pendingResult.value.promise;
      if (response.ok) {
        const rules: UserPrivacySettingRules | null =
          decodeUserPrivacySettingRules(response.value as TdJsonRaw);
        if (rules === null) {
          return err<PrivacyChoice, AppError>(
            AppErrors.internal(
              'settings_privacy_decode',
              `TDLib privacy rules for ${privacySettingLabel(key)} could not be decoded`
            )
          );
        }
        const choice: PrivacyChoice = choiceFromRules(rules.rules);
        this.logger.info(
          TAG,
          'privacy_rules_read',
          `${key} -> ${choice},rules=[${privacyRuleTypesForLog(rules.rules)}]`
        );
        return ok<PrivacyChoice, AppError>(choice);
      }
      if (response.err) {
        return err<PrivacyChoice, AppError>(response.error);
      }
      return err<PrivacyChoice, AppError>(
        AppErrors.internal('settings_privacy_response', 'TDLib returned no privacy rules result')
      );
    }
    if (pendingResult.err) {
      return err<PrivacyChoice, AppError>(pendingResult.error);
    }
    return err<PrivacyChoice, AppError>(
      AppErrors.internal('settings_privacy_request', 'TDLib privacy rules request was not created')
    );
  }

  private async writePrivacyRules(
    key: PrivacySettingKey,
    choice: PrivacyChoice
  ): Promise<Result<void, AppError>> {
    const rules: UserPrivacySettingRules = new UserPrivacySettingRules();
    rules.rules = rulesForChoice(choice);
    const request: SetUserPrivacySettingRules = new SetUserPrivacySettingRules();
    request.setting = toUserPrivacySetting(key);
    request.rules = rules;
    this.logger.info(
      TAG,
      'privacy_rules_write',
      `${key} <- ${choice},rules=[${privacyRuleTypesForLog(rules.rules)}]`
    );
    const pendingResult: Result<TdPendingRequest, AppError> = this.scope.request(
      'setUserPrivacySettingRules',
      encodeSetUserPrivacySettingRules(request) as TdWireObject
    );
    if (pendingResult.ok) {
      const response: Result<TdWireObject, AppError> = await pendingResult.value.promise;
      if (response.ok) {
        return ok<void, AppError>(undefined);
      }
      if (response.err) {
        return err<void, AppError>(response.error);
      }
      return err<void, AppError>(
        AppErrors.internal('settings_privacy_write_response', 'TDLib returned no privacy write result')
      );
    }
    if (pendingResult.err) {
      return err<void, AppError>(pendingResult.error);
    }
    return err<void, AppError>(
      AppErrors.internal('settings_privacy_write_request', 'TDLib privacy write request was not created')
    );
  }

  private privacyErrorMessage(error: AppError, action: string): string {
    if (error.kind === 'tdlib' && error.code === 'too_many_requests') {
      return 'Too many requests. Please wait and try again.';
    }
    if (error.kind === 'network') {
      return `Unable to ${action} privacy settings. Check your connection.`;
    }
    return `Unable to ${action} privacy settings. Please try again.`;
  }

  // ---- PROXY-101 网络代理 ----

  private handleLoadProxies(): void {
    this.loadProxies();
  }

  /**
   * 读列表。
   * 单条识别不出代理类型时丢掉那一行而不是整屏报错：TDLib 的 `proxyType` 是联合，
   * 版本差异只会让一条行变未知，其余行照常可用。
   */
  private async loadProxies(): Promise<void> {
    try {
      const result: Result<ProxyItem[], AppError> = await this.fetchProxyItems();
      if (this.destroyed) {
        return;
      }
      if (result.ok) {
        this.dispatch(new ProxiesLoaded(result.value));
        return;
      }
      if (result.err) {
        this.logger.logError(TAG, result.error);
        this.dispatch(new ProxiesLoaded([]));
        this.dispatch(new SetErrorMessage(this.proxyErrorMessage(result.error, 'load')));
      }
    } catch (e) {
      if (this.destroyed) {
        return;
      }
      const cause: string = e instanceof Error ? e.name : 'non-error';
      const error: AppError = AppErrors.unknown(
        'settings-proxy-load',
        'Unexpected proxy list load failure',
        cause
      );
      this.logger.logError(TAG, error);
      this.dispatch(new ProxiesLoaded([]));
      this.dispatch(new SetErrorMessage(this.proxyErrorMessage(error, 'load')));
    }
  }

  private handleEnableProxy(proxyId: number): void {
    const request: EnableProxy = new EnableProxy();
    request.proxy_id = proxyId;
    this.writeProxies('enableProxy', encodeEnableProxy(request) as TdWireObject, `id=${proxyId}`);
  }

  private handleDisableProxy(): void {
    const request: DisableProxy = new DisableProxy();
    this.writeProxies('disableProxy', encodeDisableProxy(request) as TdWireObject, 'none');
  }

  private handleRemoveProxy(proxyId: number): void {
    const request: RemoveProxy = new RemoveProxy();
    request.proxy_id = proxyId;
    this.writeProxies('removeProxy', encodeRemoveProxy(request) as TdWireObject, `id=${proxyId}`);
  }

  /**
   * 新增 / 编辑共用一条路径：表单里带 id 就是 editProxy，PROXY_NEW_ID 就是 addProxy。
   * `enable` 取表单的「立即启用」，所以「添加并启用」是一条 addProxy(enable=true)，
   * 不需要再补一发 enableProxy（TDLib 保证两者原子）。
   */
  private handleSaveProxy(form: ProxyForm): void {
    const proxy: ProxyValue = proxyValueFromForm(form);
    if (form.id === PROXY_NEW_ID) {
      const request: AddProxy = new AddProxy();
      request.proxy = proxy;
      request.enable = form.enable;
      request.comment = form.comment.trim();
      this.writeProxies(
        'addProxy',
        encodeAddProxy(request) as TdWireObject,
        `${proxy.server}:${proxy.port},enable=${request.enable}`
      );
      return;
    }
    const edit: EditProxy = new EditProxy();
    edit.proxy_id = form.id;
    edit.proxy = proxy;
    edit.enable = form.enable;
    edit.comment = form.comment.trim();
    this.writeProxies(
      'editProxy',
      encodeEditProxy(edit) as TdWireObject,
      `id=${edit.proxy_id},${proxy.server}:${proxy.port},enable=${edit.enable}`
    );
  }

  /** 一条写请求 + 回读列表：单选态只有 TDLib 知道真相，不做乐观更新。 */
  private async writeProxies(
    op: string,
    payload: TdWireObject,
    detail: string
  ): Promise<void> {
    this.logger.info(TAG, 'proxy_write', `${op} ${detail}`);
    try {
      const pendingResult: Result<TdPendingRequest, AppError> = this.scope.request(op, payload);
      if (pendingResult.err) {
        if (!this.destroyed) {
          this.logger.logError(TAG, pendingResult.error);
          this.dispatch(new SetErrorMessage(this.proxyErrorMessage(pendingResult.error, op)));
        }
        return;
      }
      if (!pendingResult.ok) {
        if (!this.destroyed) {
          this.dispatch(new SetErrorMessage(`Unable to ${op}. Please try again.`));
        }
        return;
      }
      const response: Result<TdWireObject, AppError> = await pendingResult.value.promise;
      if (response.err) {
        if (!this.destroyed) {
          this.logger.logError(TAG, response.error);
          this.dispatch(new SetErrorMessage(this.proxyErrorMessage(response.error, op)));
        }
        return;
      }
      if (this.destroyed) {
        return;
      }
      await this.loadProxies();
    } catch (e) {
      if (this.destroyed) {
        return;
      }
      const cause: string = e instanceof Error ? e.name : 'non-error';
      const error: AppError = AppErrors.unknown(
        'settings-proxy-write',
        `Unexpected ${op} failure`,
        cause
      );
      this.logger.logError(TAG, error);
      this.dispatch(new SetErrorMessage(this.proxyErrorMessage(error, op)));
    }
  }

  private async fetchProxyItems(): Promise<Result<ProxyItem[], AppError>> {
    const request: GetProxies = new GetProxies();
    const pendingResult: Result<TdPendingRequest, AppError> = this.scope.request(
      'getProxies',
      encodeGetProxies(request) as TdWireObject
    );
    if (pendingResult.ok) {
      const response: Result<TdWireObject, AppError> = await pendingResult.value.promise;
      if (response.ok) {
        const added: AddedProxies | null = decodeAddedProxies(response.value as TdJsonRaw);
        if (added === null) {
          return err<ProxyItem[], AppError>(
            AppErrors.internal('settings_proxy_decode', 'TDLib proxy list could not be decoded')
          );
        }
        const items: ProxyItem[] = [];
        let skipped: number = 0;
        for (let i = 0; i < added.proxies.length; i++) {
          const row: AddedProxy = added.proxies[i];
          const item: ProxyItem | null = proxyItemFromAdded(row);
          if (item === null) {
            skipped = skipped + 1;
            continue;
          }
          items.push(item);
        }
        this.logger.info(
          TAG,
          'proxy_list_read',
          `count=${items.length},skipped=${skipped},enabled=${proxyEnabledCount(items)}`
        );
        return ok<ProxyItem[], AppError>(items);
      }
      if (response.err) {
        return err<ProxyItem[], AppError>(response.error);
      }
      return err<ProxyItem[], AppError>(
        AppErrors.internal('settings_proxy_response', 'TDLib returned no proxy list result')
      );
    }
    if (pendingResult.err) {
      return err<ProxyItem[], AppError>(pendingResult.error);
    }
    return err<ProxyItem[], AppError>(
      AppErrors.internal('settings_proxy_request', 'TDLib proxy list request was not created')
    );
  }

  private proxyErrorMessage(error: AppError, action: string): string {
    if (error.kind === 'tdlib' && error.code === 'too_many_requests') {
      return 'Too many requests. Please wait and try again.';
    }
    if (error.kind === 'network') {
      return `Unable to ${action} proxy. Check your connection.`;
    }
    return `Unable to ${action} proxy. Please try again.`;
  }

  // ---- PROXY-102 连通性探测与连接态 ----

  /**
   * 一轮探测：列表里每行各发一次 `pingProxy`，外加「不使用代理」行的直连探测
   * （TDLib 语义：`proxy` 留空即绕开代理发）。各行并行，谁先回来谁先亮。
   */
  private handlePingProxies(): void {
    if (this.destroyed || !this.currentState.showProxyPage) {
      return;
    }
    this.subscribeConnectionState();
    this.pingGeneration = this.pingGeneration + 1;
    const generation: number = this.pingGeneration;
    const items: ProxyItem[] = this.currentState.proxyItems;
    this.pingProxyRow(generation, PROXY_NONE_ID, null);
    for (let i = 0; i < items.length; i++) {
      this.pingProxyRow(generation, items[i].id, items[i]);
    }
    this.logger.info(TAG, 'proxy_ping', `round=${generation},rows=${items.length + 1}`);
  }

  private async pingProxyRow(
    generation: number,
    proxyId: number,
    item: ProxyItem | null
  ): Promise<void> {
    const request: PingProxy = pingProxyRequestFromItem(item);
    this.dispatch(new ProxyPingUpdated(proxyId, PROXY_PING_LOADING));
    this.schedulePingTimeout(generation, proxyId);
    const startedAt: number = Date.now();
    const pendingResult: Result<TdPendingRequest, AppError> = this.scope.request(
      'pingProxy',
      encodePingProxy(request) as TdWireObject
    );
    if (pendingResult.err) {
      this.logger.logError(TAG, pendingResult.error);
      // 请求根本没发出去（本地失败），原因同样按分类给一句话。
      this.applyPing(generation, proxyId, PROXY_PING_FAILED, classifyProxyFailure(pendingResult.error, 0));
      return;
    }
    if (!pendingResult.ok) {
      this.applyPing(generation, proxyId, PROXY_PING_FAILED, 'Proxy error');
      return;
    }
    try {
      const response: Result<TdWireObject, AppError> = await pendingResult.value.promise;
      if (response.err) {
        // PROXY-103：TDLib 原文只进得了分类器、进不了屏幕与日志
        // （`AppError` 刻意把 message 留作诊断、原文放 cause，别的请求的原文里可能出现手机号），
        // 行上说的是本端分类出来的一句话，数字码只留给日志。
        const reason: string = classifyProxyFailure(response.error, Date.now() - startedAt);
        this.logger.info(
          TAG,
          'proxy_ping_error',
          `id=${proxyId},kind=${response.error.kind},reason=${reason},` +
            `code=${proxyTdlibCodeOf(response.error)},elapsed=${Date.now() - startedAt}`
        );
        this.applyPing(generation, proxyId, PROXY_PING_FAILED, reason);
        return;
      }
      if (!response.ok) {
        this.applyPing(generation, proxyId, PROXY_PING_FAILED, 'Proxy error');
        return;
      }
      const seconds: Seconds | null = decodeSeconds(response.value as TdJsonRaw);
      if (seconds === null) {
        this.applyPing(generation, proxyId, PROXY_PING_FAILED, 'Proxy error');
        return;
      }
      const pingMs: number = proxyPingMsOfSeconds(seconds.seconds);
      // 成功（含 0 秒当失败）都不该留着上一次的原因 —— 空串即擦除。
      this.applyPing(
        generation,
        proxyId,
        pingMs,
        pingMs === PROXY_PING_FAILED ? 'Proxy error' : ''
      );
    } catch (e) {
      this.applyPing(generation, proxyId, PROXY_PING_FAILED, 'Proxy error');
    }
  }

  /**
   * 本地超时兜底：TDLib 的 `pingProxy` 挂在一个不可达地址上可以几分钟不回包，
   * 而那一行会一直停在「Checking…」—— 用户读到的是「还在测」，真相是「没人在测」。
   *
   * 只对**还在途**的那一行说话：模拟器实测到 `127.0.0.1:989` 的拒连 7ms 就回来了，
   * 10s 后定时器照样到点，把已经落定的「Connection refused」盖成了「Connection timed out」。
   * 世代号挡不住这种覆盖（还是同一轮），所以必须按行的当前探测态判。
   */
  private schedulePingTimeout(generation: number, proxyId: number): void {
    const self: SettingsCoordinator = this;
    setTimeout((): void => {
      if (proxyPingOf(self.currentState.proxyPingMs, proxyId) !== PROXY_PING_LOADING) {
        return;
      }
      self.applyPing(generation, proxyId, PROXY_PING_FAILED, PROXY_PING_TIMEOUT_KEY);
    }, PROXY_PING_TIMEOUT_MS);
  }

  /** 回包只认当轮：旧轮晚到、页面已经关掉，都不该再改那一行说什么。 */
  private applyPing(generation: number, proxyId: number, pingMs: number, failureKey: string): void {
    if (this.destroyed || generation !== this.pingGeneration || !this.currentState.showProxyPage) {
      return;
    }
    this.dispatch(new ProxyPingUpdated(proxyId, pingMs, failureKey));
  }

  /**
   * 连接态走 gateway 的过滤订阅，而不是 `scope.subscribeEvents` —— 后者是单槽监听，
   * 装配层已经把它交给 auth 事件了。整个协调器只建一次，destroy 时退订。
   */
  private subscribeConnectionState(): void {
    if (this.connectionSubscription !== null) {
      return;
    }
    const filter: TdUpdateFilter = {
      clientId: this.scope.clientId,
      types: ['updateConnectionState']
    };
    const self: SettingsCoordinator = this;
    this.connectionSubscription = this.scope.gatewayInstance.subscribeUpdates(
      filter,
      (event: TdRoutedEvent): void => {
        self.handleConnectionStateEvent(event);
      }
    );
  }

  private handleConnectionStateEvent(event: TdRoutedEvent): void {
    if (this.destroyed) {
      return;
    }
    const update: UpdateConnectionState | null = decodeUpdateConnectionState(
      event.payload as TdJsonRaw
    );
    if (update === null) {
      return;
    }
    const state: TdConnectionState | null = update.state;
    const type: string = state === null ? '' : state.type;
    this.logger.info(TAG, 'proxy_connection', type);
    this.dispatch(new ProxyConnectionStateChanged(proxyConnectionStateOfType(type)));
  }

  // ---- AUTODL-101 自动媒体下载 ----

  /**
   * 读策略。端口没注入、盘上没值、值读坏了都回落默认策略 —— 与 TGX 首装一致，
   * 页面因此永远有得显。
   */
  private handleLoadAutoDownloadPolicy(): void {
    const store: AutoDownloadPolicyStore | null = this.autoDownloadStore;
    const loaded: AutoDownloadPolicy | null = store !== null ? store.load() : null;
    this.dispatch(new AutoDownloadPolicyLoaded(
      loaded !== null ? loaded : AutoDownloadPolicy.defaultPolicy()
    ));
  }

  /**
   * 写策略。勾选项是乐观更新进状态的，所以写失败必须把界面回滚成盘上真实的那一份：
   * 留着「看起来已开、其实没存」的开关，比报一次错更糟 —— 聊天页按盘上的策略下载。
   */
  private handlePersistAutoDownloadPolicy(policy: AutoDownloadPolicy): void {
    const store: AutoDownloadPolicyStore | null = this.autoDownloadStore;
    if (store === null) {
      return;
    }
    if (store.save(policy)) {
      return;
    }
    const restored: AutoDownloadPolicy | null = store.load();
    this.dispatch(new AutoDownloadPolicyLoaded(
      restored !== null ? restored : AutoDownloadPolicy.defaultPolicy()
    ));
    this.dispatch(new SetErrorMessage('Unable to save automatic download settings.'));
  }

  // ---- AUTODL-102 省流量（Data Saver）----

  /** 读省流量设置；端口没注入或盘上没值都回落 Android 的默认档（只勾「漫游」）。 */
  private handleLoadDataSaverSettings(): void {
    const store: DataSaverStore | null = this.dataSaverStore;
    const loaded: DataSaverSettings | null = store !== null ? store.load() : null;
    this.dispatch(new DataSaverSettingsLoaded(
      loaded !== null ? loaded : DataSaverSettings.defaultSettings()
    ));
  }

  /**
   * 写省流量设置。回滚逻辑与自动下载那一份同理：主开关看起来已开、盘上却没存住，
   * 用户会在蜂窝下被扣流量还毫不知情。
   */
  private handlePersistDataSaverSettings(settings: DataSaverSettings): void {
    const store: DataSaverStore | null = this.dataSaverStore;
    if (store === null) {
      return;
    }
    if (store.save(settings)) {
      return;
    }
    const restored: DataSaverSettings | null = store.load();
    this.dispatch(new DataSaverSettingsLoaded(
      restored !== null ? restored : DataSaverSettings.defaultSettings()
    ));
    this.dispatch(new SetErrorMessage('Unable to save data saver settings.'));
  }

  // ---- AUTODL-103 按网络类型的自动下载限制 ----

  /** 读限制；端口没注入或盘上没值都回落 Android 默认（Wi-Fi 50MB / 移动 15MB / 漫游 5MB）。 */
  private handleLoadDownloadLimits(): void {
    const store: DownloadLimitsStore | null = this.downloadLimitsStore;
    const loaded: DownloadLimitsByNetwork | null = store !== null ? store.load() : null;
    this.dispatch(new DownloadLimitsLoaded(
      loaded !== null ? loaded : DownloadLimitsByNetwork.defaultLimits()
    ));
  }

  /**
   * 写限制。回滚同理：副标题显着「超过 1 MB」、盘上还是 50MB，聊天页按盘上的值放行，
   * 用户会以为限制没生效而不是没存住。
   */
  private handlePersistDownloadLimits(limits: DownloadLimitsByNetwork): void {
    const store: DownloadLimitsStore | null = this.downloadLimitsStore;
    if (store === null) {
      return;
    }
    if (store.save(limits)) {
      return;
    }
    const restored: DownloadLimitsByNetwork | null = store.load();
    this.dispatch(new DownloadLimitsLoaded(
      restored !== null ? restored : DownloadLimitsByNetwork.defaultLimits()
    ));
    this.dispatch(new SetErrorMessage('Unable to save download limits.'));
  }

  // ---- APPLOCK-101 应用锁（Passcode）----

  /**
   * 读盘：本机是否已设 PIN + 自动锁定档位。
   * `refreshPasscodeSet()` 是唯一一次异步确认（安全存储查询），档位是同步读偏好缓存。
   * 读失败按「未设 PIN」回灌：锁本身没生效比多问一次密码更安全，且这条路径只有
   * 设备被恢复出厂/系统清理过才会走到。
   */
  private handleLoadPasscodeState(): void {
    const store: AppLockStore | null = this.appLockStore;
    if (store === null) {
      this.dispatch(new PasscodeStateLoaded(false, AUTO_LOCK_DEFAULT));
      return;
    }
    const self: SettingsCoordinator = this;
    store.refreshPasscodeSet().then((res: Result<boolean, AppError>): void => {
      let isSet: boolean = false;
      if (res.ok) {
        isSet = res.value;
      }
      self.dispatch(new PasscodeStateLoaded(isSet, store.autoLockChoice(), store.passcodeVisible()));
    });
  }

  private handleStorePasscodeDraft(pin: string): void {
    this.passcodeDraft = pin;
  }

  private handleClearPasscodeDraft(): void {
    this.passcodeDraft = null;
  }

  /**
   * 确认步提交：先与草稿比对，再落盘。
   * 比对放在 coordinator 而不是 reducer，正是因为要比的两个值里有一个是密码 ——
   * reducer 只能看见 state，而 state 里不许有它。
   */
  private handleCommitPasscode(pin: string): void {
    const store: AppLockStore | null = this.appLockStore;
    if (store === null) {
      this.dispatch(new PasscodeOperationFailed(APP_LOCK_ERROR_STORE));
      return;
    }
    const draft: string | null = this.passcodeDraft;
    this.passcodeDraft = null;
    if (draft === null || draft !== pin) {
      this.dispatch(new PasscodeMismatched());
      return;
    }
    const self: SettingsCoordinator = this;
    store.setPasscode(pin).then((res: Result<void, AppError>): void => {
      // ArkTS 不会在提前 return 后收窄 Result，成功/失败必须各写一个显式分支。
      if (res.ok) {
        self.dispatch(new PasscodeOperationDone(APP_LOCK_NOTICE_SAVED, store.isPasscodeSet()));
      }
      if (res.err) {
        self.logger.logError(TAG, res.error);
        self.dispatch(new PasscodeOperationFailed(appLockNoticeKeyForError(res.error)));
      }
    });
  }

  /**
   * 校验当前密码。`purpose` 决定验完的下一步：
   * - `disable` → 紧接着抹掉秘密值，两次派发（`passcodeVerified` 解在途、`passcodeOperationDone` 收尾）；
   * - `change` → 只推进到「输入新密码」，秘密值还没变，中途退出也不会把用户锁在外面。
   */
  private handleVerifyPasscode(pin: string, purpose: 'disable' | 'change'): void {
    const store: AppLockStore | null = this.appLockStore;
    if (store === null) {
      this.dispatch(new PasscodeOperationFailed(APP_LOCK_ERROR_STORE));
      return;
    }
    const self: SettingsCoordinator = this;
    store.verifyPasscode(pin).then((res: Result<boolean, AppError>): void => {
      if (res.err) {
        self.dispatch(new PasscodeOperationFailed(appLockNoticeKeyForError(res.error)));
        return;
      }
      if (res.ok) {
        self.handleVerifyOutcome(res.value, purpose, store);
      }
    });
  }

  /** 校验结论的下一步。抽成独立方法只为让上面那对 `res.err` / `res.ok` 分支保持显式。 */
  private handleVerifyOutcome(matched: boolean, purpose: 'disable' | 'change', store: AppLockStore): void {
    if (!matched) {
      this.dispatch(new PasscodeRejected(APP_LOCK_ERROR_WRONG));
      return;
    }
    if (purpose === 'change') {
      this.dispatch(new PasscodeVerified('change'));
      return;
    }
    this.dispatch(new PasscodeVerified('disable'));
    const self: SettingsCoordinator = this;
    store.removePasscode().then((removed: Result<void, AppError>): void => {
      if (removed.ok) {
        self.dispatch(new PasscodeOperationDone(APP_LOCK_NOTICE_REMOVED, store.isPasscodeSet()));
      }
      if (removed.err) {
        self.dispatch(new PasscodeOperationFailed(appLockNoticeKeyForError(removed.error)));
      }
    });
  }

  /**
   * 写档位。 reducer 已乐观改过界面值，这里失败就把它回灌成盘上真实的那一份 ——
   * 显示「1 分钟」而按「立即」锁定，用户是在被误导，不是在用设置。
   */
  private handlePersistAutoLockChoice(choice: AutoLockChoice): void {
    const store: AppLockStore | null = this.appLockStore;
    if (store === null) {
      return;
    }
    if (store.setAutoLockChoice(choice)) {
      return;
    }
    this.dispatch(new AutoLockChoiceRejected(store.autoLockChoice()));
  }

  /**
   * 写「显示输入的密码」偏好（APPLOCK-102）。与档位同一套乐观回灌：
   * 写盘失败就把开关倒回去，避免屏上说明文、实际按圆点存着走。
   */
  private handlePersistPasscodeVisible(visible: boolean): void {
    const store: AppLockStore | null = this.appLockStore;
    if (store === null) {
      return;
    }
    if (store.setPasscodeVisible(visible)) {
      return;
    }
    this.dispatch(new PasscodeVisibleRejected(store.passcodeVisible()));
  }
}