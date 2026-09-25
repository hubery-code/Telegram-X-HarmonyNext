/**
 * feature/settings — 设置页用户意图与系统事件（SET-101）。
 *
 * 遵循计划 §5.11 / UI-003：
 * - 每个变体带 `kind` 判别字面量属性，由 reducer 做穷尽收窄；
 * - 纯 ArkTS 契约层。
 */

import { Intent } from '@tgx/feature-template';
import { LanguagePreference } from '@tgx/core-common';
import { SettingsThemeMode } from './SettingsUiState';
import { NotificationScopeKey } from '../model/NotificationSettings';
import { ActiveSessionItem } from '../model/ActiveSessionItem';
import { PrivacyChoice, PrivacySettingItem, PrivacySettingKey } from '../model/PrivacySettings';
import { ProxyForm, ProxyItem, ProxyConnectionState } from '../model/ProxySettings';
import {
  AutoDownloadChatScope,
  AutoDownloadMediaKind,
  AutoDownloadPolicy,
  DataSaverNetworkType,
  DataSaverSettings,
  DownloadLimitsByNetwork
} from '@tgx/core-domain';

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

export class ToggleNotificationScope implements Intent {
  readonly kind: 'toggleNotificationScope' = 'toggleNotificationScope';
  readonly scope: NotificationScopeKey;

  constructor(scope: NotificationScopeKey) {
    this.scope = scope;
  }
}

export class LoadNotificationSettings implements Intent {
  readonly kind: 'loadNotificationSettings' = 'loadNotificationSettings';
}

export class NotificationSettingsLoaded implements Intent {
  readonly kind: 'notificationSettingsLoaded' = 'notificationSettingsLoaded';
  readonly enabled: boolean;
  readonly privateEnabled: boolean;
  readonly groupEnabled: boolean;
  readonly channelEnabled: boolean;

  constructor(enabled: boolean, privateEnabled: boolean, groupEnabled: boolean, channelEnabled: boolean) {
    this.enabled = enabled;
    this.privateEnabled = privateEnabled;
    this.groupEnabled = groupEnabled;
    this.channelEnabled = channelEnabled;
  }
}

export class NotificationSettingsUpdated implements Intent {
  readonly kind: 'notificationSettingsUpdated' = 'notificationSettingsUpdated';
  readonly enabled: boolean;

  constructor(enabled: boolean) {
    this.enabled = enabled;
  }
}

export class NotificationSettingsUpdateFailed implements Intent {
  readonly kind: 'notificationSettingsUpdateFailed' = 'notificationSettingsUpdateFailed';
  readonly errorMessage: string;

  constructor(errorMessage: string) {
    this.errorMessage = errorMessage;
  }
}

export class NotificationScopeUpdated implements Intent {
  readonly kind: 'notificationScopeUpdated' = 'notificationScopeUpdated';
  readonly scope: NotificationScopeKey;
  readonly enabled: boolean;

  constructor(scope: NotificationScopeKey, enabled: boolean) {
    this.scope = scope;
    this.enabled = enabled;
  }
}

export class NotificationScopeUpdateFailed implements Intent {
  readonly kind: 'notificationScopeUpdateFailed' = 'notificationScopeUpdateFailed';
  readonly scope: NotificationScopeKey;
  readonly errorMessage: string;

  constructor(scope: NotificationScopeKey, errorMessage: string) {
    this.scope = scope;
    this.errorMessage = errorMessage;
  }
}

export class ChangeThemeMode implements Intent {
  readonly kind: 'changeThemeMode' = 'changeThemeMode';
  readonly themeMode: SettingsThemeMode;

  constructor(themeMode: SettingsThemeMode) {
    this.themeMode = themeMode;
  }
}

/**
 * FEAT-UI-002 / SET-105：调整聊天消息字号。
 * 单位 sp，传入值会被吸附到最近合法档位（见 `@tgx/core-design-system` 的
 * `clampChatFontSize`），因此调用方可以直接传滑块/档位按钮的原始值。
 */
export class ChangeChatFontSize implements Intent {
  readonly kind: 'changeChatFontSize' = 'changeChatFontSize';
  readonly chatFontSize: number;

  constructor(chatFontSize: number) {
    this.chatFontSize = chatFontSize;
  }
}

export class ChangeLanguage implements Intent {
  readonly kind: 'changeLanguage' = 'changeLanguage';
  readonly languagePreference: LanguagePreference;

  constructor(languagePreference: LanguagePreference) {
    this.languagePreference = languagePreference;
  }
}

export class SetLanguage implements Intent {
  readonly kind: 'setLanguage' = 'setLanguage';
  readonly languagePreference: LanguagePreference;

  constructor(languagePreference: LanguagePreference) {
    this.languagePreference = languagePreference;
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

/**
 * SET-104：进入设置页时请求拉取存储占用（reducer 出 loadStorageStats effect）。
 */
export class LoadStorageStats implements Intent {
  readonly kind: 'loadStorageStats' = 'loadStorageStats';
}

/**
 * SET-104：存储占用拉取/清理后的结果回灌。
 * label 由 coordinator 用 `formatStorageLabel` 预先格式化好——与既有
 * CacheCleared 携带已格式化字符串的约定保持一致，reducer 保持纯搬运。
 */
export class StorageStatsLoaded implements Intent {
  readonly kind: 'storageStatsLoaded' = 'storageStatsLoaded';
  readonly label: string;

  constructor(label: string) {
    this.label = label;
  }
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

export class SwitchAccount implements Intent {
  readonly kind: 'switchAccount' = 'switchAccount';
  readonly accountKey: string;

  constructor(accountKey: string) {
    this.accountKey = accountKey;
  }
}

export class RequestAddAccount implements Intent {
  readonly kind: 'requestAddAccount' = 'requestAddAccount';
}

export class OpenAccountSwitcher implements Intent {
  readonly kind: 'openAccountSwitcher' = 'openAccountSwitcher';
}

export class CloseAccountSwitcher implements Intent {
  readonly kind: 'closeAccountSwitcher' = 'closeAccountSwitcher';
}

export class SetAvailableAccounts implements Intent {
  readonly kind: 'setAvailableAccounts' = 'setAvailableAccounts';
  readonly accounts: readonly string[];
  readonly currentAccountKey?: string;

  constructor(accounts: readonly string[], currentAccountKey?: string) {
    this.accounts = accounts;
    this.currentAccountKey = currentAccountKey;
  }
}

/** FEAT-P2-008：打开活跃设备页面。 */
export class OpenDevicesPage implements Intent {
  readonly kind: 'openDevicesPage' = 'openDevicesPage';
}

/** FEAT-P2-008：关闭活跃设备页面。 */
export class CloseDevicesPage implements Intent {
  readonly kind: 'closeDevicesPage' = 'closeDevicesPage';
}

/**
 * SELF-101：分区直达。`section` 是路由带来的外部字符串（`settingsSection/{section}`），
 * 由 reducer 经 `parseSettingsSection` 收敛后才写入状态；'devices' 转成打开活跃会话子页。
 */
export class SectionFocused implements Intent {
  readonly kind: 'sectionFocused' = 'sectionFocused';
  readonly section: string;

  constructor(section: string) {
    this.section = section;
  }
}

/** FEAT-P2-008：拉取活跃设备/会话列表。 */
export class LoadActiveSessions implements Intent {
  readonly kind: 'loadActiveSessions' = 'loadActiveSessions';
}

/** FEAT-P2-008：活跃设备/会话列表加载完成。 */
export class ActiveSessionsLoaded implements Intent {
  readonly kind: 'activeSessionsLoaded' = 'activeSessionsLoaded';
  readonly sessions: readonly ActiveSessionItem[];

  constructor(sessions: readonly ActiveSessionItem[]) {
    this.sessions = sessions;
  }
}

/** FEAT-P2-008：活跃设备/会话列表加载失败。 */
export class ActiveSessionsLoadFailed implements Intent {
  readonly kind: 'activeSessionsLoadFailed' = 'activeSessionsLoadFailed';
  readonly errorMessage: string;

  constructor(errorMessage: string) {
    this.errorMessage = errorMessage;
  }
}

/** FEAT-P2-008：终止指定设备会话。 */
export class TerminateSessionIntent implements Intent {
  readonly kind: 'terminateSession' = 'terminateSession';
  readonly sessionId: string;

  constructor(sessionId: string) {
    this.sessionId = sessionId;
  }
}

/** FEAT-P2-008：终止除当前设备外的所有会话。 */
export class TerminateAllOtherSessionsIntent implements Intent {
  readonly kind: 'terminateAllOtherSessions' = 'terminateAllOtherSessions';
}

/** SELF-102：打开「隐私和安全」子页（同时触发规则读取）。 */
export class OpenPrivacyPage implements Intent {
  readonly kind: 'openPrivacyPage' = 'openPrivacyPage';
}

/** SELF-102：关闭「隐私和安全」子页。 */
export class ClosePrivacyPage implements Intent {
  readonly kind: 'closePrivacyPage' = 'closePrivacyPage';
}

/** SELF-102：读取全部隐私设置规则。 */
export class LoadPrivacySettings implements Intent {
  readonly kind: 'loadPrivacySettings' = 'loadPrivacySettings';
}

/** SELF-102：规则读取完成（未取到的项以 unknown 呈现，不冒充默认值）。 */
export class PrivacySettingsLoaded implements Intent {
  readonly kind: 'privacySettingsLoaded' = 'privacySettingsLoaded';
  readonly items: readonly PrivacySettingItem[];

  constructor(items: readonly PrivacySettingItem[]) {
    this.items = items;
  }
}

/** SELF-102：点某一行，循环到下一个可见范围并写回。 */
export class TogglePrivacySetting implements Intent {
  readonly kind: 'togglePrivacySetting' = 'togglePrivacySetting';
  readonly key: PrivacySettingKey;

  constructor(key: PrivacySettingKey) {
    this.key = key;
  }
}

/** SELF-102：写回成功（以 TDLib 回读值为准）。 */
export class PrivacySettingUpdated implements Intent {
  readonly kind: 'privacySettingUpdated' = 'privacySettingUpdated';
  readonly key: PrivacySettingKey;
  readonly choice: PrivacyChoice;

  constructor(key: PrivacySettingKey, choice: PrivacyChoice) {
    this.key = key;
    this.choice = choice;
  }
}

/** SELF-102：写回失败，行内值退回读到的状态。 */
export class PrivacySettingUpdateFailed implements Intent {
  readonly kind: 'privacySettingUpdateFailed' = 'privacySettingUpdateFailed';
  readonly key: PrivacySettingKey;
  readonly errorMessage: string;

  constructor(key: PrivacySettingKey, errorMessage: string) {
    this.key = key;
    this.errorMessage = errorMessage;
  }
}

/** PROXY-101：打开「代理」子页（同时触发列表读取）。 */
export class OpenProxyPage implements Intent {
  readonly kind: 'openProxyPage' = 'openProxyPage';
}

/** PROXY-101：关闭「代理」子页。 */
export class CloseProxyPage implements Intent {
  readonly kind: 'closeProxyPage' = 'closeProxyPage';
}

/** PROXY-101：读取已添加的代理列表（getProxies）。 */
export class LoadProxies implements Intent {
  readonly kind: 'loadProxies' = 'loadProxies';
}

/** PROXY-101：列表读取完成；写回后也以该意图回灌，界面恒以 TDLib 返回值为准。 */
export class ProxiesLoaded implements Intent {
  readonly kind: 'proxiesLoaded' = 'proxiesLoaded';
  readonly items: ProxyItem[];

  constructor(items: ProxyItem[]) {
    this.items = items;
  }
}

/** PROXY-101：单选启用某个代理；`proxyId` 为 `PROXY_NONE_ID` 表示「不使用代理」。 */
export class SelectProxy implements Intent {
  readonly kind: 'selectProxy' = 'selectProxy';
  readonly proxyId: number;

  constructor(proxyId: number) {
    this.proxyId = proxyId;
  }
}

/** PROXY-101：保存代理；`form.id === PROXY_NEW_ID` 为新增，否则为编辑该行。 */
export class SaveProxy implements Intent {
  readonly kind: 'saveProxy' = 'saveProxy';
  readonly form: ProxyForm;

  constructor(form: ProxyForm) {
    this.form = form;
  }
}

/** PROXY-101：删除代理（页面已二次确认）。 */
export class RemoveProxyRequested implements Intent {
  readonly kind: 'removeProxyRequested' = 'removeProxyRequested';
  readonly proxyId: number;

  constructor(proxyId: number) {
    this.proxyId = proxyId;
  }
}

/**
 * PROXY-102：某一行 `pingProxy` 的回结果。
 * `proxyId` 用 `PROXY_NONE_ID`（0）表示「不使用代理」那一行的直连探测；
 * `pingMs` 取模型层的哨兵（LOADING / FAILED）或正数毫秒。
 *
 * PROXY-103 加 `failureKey`：失败那一行要说的「为什么」，同样是 Lang key，
 * 成功/在途传空串（空串即擦除这一行的旧原因）。为什么不编进 `pingMs`：
 * `PROXY_PING_FAILED` 只有一个值，说不出是拒连、查不到地址还是本地超时。
 */
export class ProxyPingUpdated implements Intent {
  readonly kind: 'proxyPingUpdated' = 'proxyPingUpdated';
  readonly proxyId: number;
  readonly pingMs: number;
  readonly failureKey: string;

  constructor(proxyId: number, pingMs: number, failureKey: string = '') {
    this.proxyId = proxyId;
    this.pingMs = pingMs;
    this.failureKey = failureKey;
  }
}

/** PROXY-102：TDLib `updateConnectionState` 进状态；连接文案只属于当前生效的那条路。 */
export class ProxyConnectionStateChanged implements Intent {
  readonly kind: 'proxyConnectionStateChanged' = 'proxyConnectionStateChanged';
  readonly connection: ProxyConnectionState;

  constructor(connection: ProxyConnectionState) {
    this.connection = connection;
  }
}

/** AUTODL-101：打开「自动媒体下载」子页（同时读取本地策略）。 */
export class OpenAutoDownloadPage implements Intent {
  readonly kind: 'openAutoDownloadPage' = 'openAutoDownloadPage';
}

/** AUTODL-101：关闭「自动媒体下载」子页。 */
export class CloseAutoDownloadPage implements Intent {
  readonly kind: 'closeAutoDownloadPage' = 'closeAutoDownloadPage';
}

/** AUTODL-101：读取自动下载策略（设置页首帧也要读，行副标题依赖它）。 */
export class LoadAutoDownloadPolicy implements Intent {
  readonly kind: 'loadAutoDownloadPolicy' = 'loadAutoDownloadPolicy';
}

/** AUTODL-101：策略读取完成；写回后同样以该意图回灌，界面恒以存储返回值为准。 */
export class AutoDownloadPolicyLoaded implements Intent {
  readonly kind: 'autoDownloadPolicyLoaded' = 'autoDownloadPolicyLoaded';
  readonly policy: AutoDownloadPolicy;

  constructor(policy: AutoDownloadPolicy) {
    this.policy = policy;
  }
}

/** AUTODL-101：勾选某一分区内的一类媒体。 */
export class SetAutoDownloadKind implements Intent {
  readonly kind: 'setAutoDownloadKind' = 'setAutoDownloadKind';
  readonly scope: AutoDownloadChatScope;
  readonly mediaKind: AutoDownloadMediaKind;
  readonly enabled: boolean;

  constructor(scope: AutoDownloadChatScope, mediaKind: AutoDownloadMediaKind, enabled: boolean) {
    this.scope = scope;
    this.mediaKind = mediaKind;
    this.enabled = enabled;
  }
}

/**
 * AUTODL-102：读取省流量设置。子页首帧也要读 —— 「自动开启」那行的副标题
 * 直接是 Mobile / Roaming / both / None 摘要，跟自动下载行的副标题同一套道理。
 */
export class LoadDataSaverSettings implements Intent {
  readonly kind: 'loadDataSaverSettings' = 'loadDataSaverSettings';
}

/** AUTODL-102：省流量设置读取完成；写回后同样以该意图回灌，界面恒以存储返回值为准。 */
export class DataSaverSettingsLoaded implements Intent {
  readonly kind: 'dataSaverSettingsLoaded' = 'dataSaverSettingsLoaded';
  readonly settings: DataSaverSettings;

  constructor(settings: DataSaverSettings) {
    this.settings = settings;
  }
}

/**
 * AUTODL-102：改省流量的某一位（`DATA_SAVER_FLAG_ENABLED` / `WHEN_MOBILE` / `WHEN_ROAMING`）。
 * 带位而不是带整份设置：一行一个开关，勾哪个改哪个；reducer 负责不可变替换。
 */
export class SetDataSaverFlag implements Intent {
  readonly kind: 'setDataSaverFlag' = 'setDataSaverFlag';
  readonly flag: number;
  readonly enabled: boolean;

  constructor(flag: number, enabled: boolean) {
    this.flag = flag;
    this.enabled = enabled;
  }
}

/**
 * AUTODL-103：读取按网络档的自动下载限制。
 * 子页首帧也要读 —— 三行「按网络类型限制」的副标题就是这份设置的摘要，
 * 与省流量、自动下载策略各读各的盘（三者存在三个不同的偏好键族里）。
 */
export class LoadDownloadLimits implements Intent {
  readonly kind: 'loadDownloadLimits' = 'loadDownloadLimits';
}

/** AUTODL-103：限制读取完成；写回后同样以该意图回灌，界面恒以存储返回值为准。 */
export class DownloadLimitsLoaded implements Intent {
  readonly kind: 'downloadLimitsLoaded' = 'downloadLimitsLoaded';
  readonly limits: DownloadLimitsByNetwork;

  constructor(limits: DownloadLimitsByNetwork) {
    this.limits = limits;
  }
}

/**
 * AUTODL-103：改某一档的尺寸上限。
 * 带的是档位码（`DOWNLOAD_LIMIT_*`）而不是字节数 —— 档位才是设置的本体，
 * 「无上限」没有对应的字节值，用码才不会把「无限」写成「0 字节全拦」。
 */
export class SetDownloadLimitSize implements Intent {
  readonly kind: 'setDownloadLimitSize' = 'setDownloadLimitSize';
  readonly network: DataSaverNetworkType;
  readonly sizeCode: number;

  constructor(network: DataSaverNetworkType, sizeCode: number) {
    this.network = network;
    this.sizeCode = sizeCode;
  }
}

/**
 * AUTODL-103：改某一档额外排除的媒体类型。
 * 勾选语义与分区面板**相反** —— 这里勾上表示「这一类不自动下」
 * （Android 的限制面板里那七行是 `No Photos / No Videos / …`）。
 */
export class SetDownloadLimitExclusion implements Intent {
  readonly kind: 'setDownloadLimitExclusion' = 'setDownloadLimitExclusion';
  readonly network: DataSaverNetworkType;
  readonly mediaKind: AutoDownloadMediaKind;
  readonly excluded: boolean;

  constructor(network: DataSaverNetworkType, mediaKind: AutoDownloadMediaKind, excluded: boolean) {
    this.network = network;
    this.mediaKind = mediaKind;
    this.excluded = excluded;
  }
}

export type SettingsIntent =
  | LoadUserProfile
  | ToggleNotifications
  | ToggleNotificationScope
  | LoadNotificationSettings
  | NotificationSettingsLoaded
  | NotificationSettingsUpdated
  | NotificationSettingsUpdateFailed
  | NotificationScopeUpdated
  | NotificationScopeUpdateFailed
  | ChangeThemeMode
  | ChangeChatFontSize
  | ChangeLanguage
  | SetLanguage
  | RequestLogout
  | CancelLogout
  | ConfirmLogout
  | ClearCacheRequested
  | LoadStorageStats
  | StorageStatsLoaded
  | CacheCleared
  | ProfileLoaded
  | SetErrorMessage
  | SwitchAccount
  | RequestAddAccount
  | OpenAccountSwitcher
  | CloseAccountSwitcher
  | SetAvailableAccounts
  | OpenDevicesPage
  | CloseDevicesPage
  | LoadActiveSessions
  | ActiveSessionsLoaded
  | ActiveSessionsLoadFailed
  | TerminateSessionIntent
  | TerminateAllOtherSessionsIntent
  | OpenPrivacyPage
  | ClosePrivacyPage
  | LoadPrivacySettings
  | PrivacySettingsLoaded
  | TogglePrivacySetting
  | PrivacySettingUpdated
  | PrivacySettingUpdateFailed
  | OpenProxyPage
  | CloseProxyPage
  | LoadProxies
  | ProxiesLoaded
  | SelectProxy
  | SaveProxy
  | RemoveProxyRequested
  | ProxyPingUpdated
  | ProxyConnectionStateChanged
  | OpenAutoDownloadPage
  | CloseAutoDownloadPage
  | LoadAutoDownloadPolicy
  | AutoDownloadPolicyLoaded
  | SetAutoDownloadKind
  | LoadDataSaverSettings
  | DataSaverSettingsLoaded
  | SetDataSaverFlag
  | LoadDownloadLimits
  | DownloadLimitsLoaded
  | SetDownloadLimitSize
  | SetDownloadLimitExclusion
  | SectionFocused;
