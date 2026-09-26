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
import { TdUserPrivacySettingRule } from '@tgx/core-td-api-generated';
import { PrivacySettingItem, PrivacySettingKey } from '../model/PrivacySettings';
import { PrivacyMode } from '../model/PrivacyRules';
import { PrivacyContactRow, PrivacyExceptionTarget } from '../model/PrivacyDetail';
import { ProxyForm, ProxyItem, ProxyConnectionState } from '../model/ProxySettings';
import {
  AutoDownloadChatScope,
  AutoDownloadMediaKind,
  AutoDownloadPolicy,
  AutoLockChoice,
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

/** SELF-102：规则读取完成（未取到的项 view 为 null，行上显示 Unknown，不冒充默认值）。 */
export class PrivacySettingsLoaded implements Intent {
  readonly kind: 'privacySettingsLoaded' = 'privacySettingsLoaded';
  readonly items: readonly PrivacySettingItem[];

  constructor(items: readonly PrivacySettingItem[]) {
    this.items = items;
  }
}

/**
 * PRIVACY-101：打开某一项的详情页（主档位 + 例外名单）。
 * 对齐 Android `SettingsPrivacyKeyController` 的进入：先读该项的完整规则列表。
 */
export class OpenPrivacyKeyPage implements Intent {
  readonly kind: 'openPrivacyKeyPage' = 'openPrivacyKeyPage';
  readonly key: PrivacySettingKey;

  constructor(key: PrivacySettingKey) {
    this.key = key;
  }
}

/**
 * PRIVACY-101：离开详情页。**唯一一次写回服务端的地方** —— 照 Android
 * `onBlur → saveChanges()`：页内编辑只改本地规则，没有改动就不发请求。
 */
export class ClosePrivacyKeyPage implements Intent {
  readonly kind: 'closePrivacyKeyPage' = 'closePrivacyKeyPage';
}

/** PRIVACY-101：详情页规则与联系人读取完成。 */
export class PrivacyDetailLoaded implements Intent {
  readonly kind: 'privacyDetailLoaded' = 'privacyDetailLoaded';
  readonly key: PrivacySettingKey;
  readonly rules: TdUserPrivacySettingRule[];
  readonly contacts: PrivacyContactRow[];

  constructor(
    key: PrivacySettingKey,
    rules: TdUserPrivacySettingRule[],
    contacts: PrivacyContactRow[]
  ) {
    this.key = key;
    this.rules = rules;
    this.contacts = contacts;
  }
}

/** PRIVACY-101：详情页读取失败（页内横幅 + 返回，不用假数据顶替）。 */
export class PrivacyDetailLoadFailed implements Intent {
  readonly kind: 'privacyDetailLoadFailed' = 'privacyDetailLoadFailed';
  readonly key: PrivacySettingKey;
  readonly errorMessage: string;

  constructor(key: PrivacySettingKey, errorMessage: string) {
    this.key = key;
    this.errorMessage = errorMessage;
  }
}

/** PRIVACY-101：改主档位（例外名单原样保留，见 `PrivacyRules.privacyRulesForMode`）。 */
export class SetPrivacyMode implements Intent {
  readonly kind: 'setPrivacyMode' = 'setPrivacyMode';
  readonly mode: PrivacyMode;

  constructor(mode: PrivacyMode) {
    this.mode = mode;
  }
}

/** PRIVACY-101：在「我的联系人」档下勾选/取消 Premium 用户。 */
export class TogglePrivacyPremium implements Intent {
  readonly kind: 'togglePrivacyPremium' = 'togglePrivacyPremium';
}

/** PRIVACY-101：打开「总是允许 / 从不允许」联系人多选器。 */
export class OpenPrivacyPicker implements Intent {
  readonly kind: 'openPrivacyPicker' = 'openPrivacyPicker';
  readonly target: PrivacyExceptionTarget;

  constructor(target: PrivacyExceptionTarget) {
    this.target = target;
  }
}

/** PRIVACY-101：关闭多选器并丢弃未提交的勾选。 */
export class ClosePrivacyPicker implements Intent {
  readonly kind: 'closePrivacyPicker' = 'closePrivacyPicker';
}

/** PRIVACY-101：多选器里勾选/取消一个联系人。 */
export class TogglePrivacyPickerContact implements Intent {
  readonly kind: 'togglePrivacyPickerContact' = 'togglePrivacyPickerContact';
  readonly userId: number;

  constructor(userId: number) {
    this.userId = userId;
  }
}

/** PRIVACY-101：把多选器的勾选结果写进规则列表（全量替换该侧名单）。 */
export class ApplyPrivacyPicker implements Intent {
  readonly kind: 'applyPrivacyPicker' = 'applyPrivacyPicker';
}

/** PRIVACY-101：详情页规则写回成功，回读值为准（同时刷新列表行的文案）。 */
export class PrivacyRulesSaved implements Intent {
  readonly kind: 'privacyRulesSaved' = 'privacyRulesSaved';
  readonly key: PrivacySettingKey;
  readonly rules: TdUserPrivacySettingRule[];

  constructor(key: PrivacySettingKey, rules: TdUserPrivacySettingRule[]) {
    this.key = key;
    this.rules = rules;
  }
}

/** PRIVACY-101：详情页规则写回失败（列表行报错，不静默退回本地值）。 */
export class PrivacyRulesSaveFailed implements Intent {
  readonly kind: 'privacyRulesSaveFailed' = 'privacyRulesSaveFailed';
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

/**
 * APPLOCK-101 — 应用锁（Passcode）意图。
 *
 * `PasscodeSubmitted` 是这里唯一带用户输入的一条：PIN 只作为**一次事件**的载荷穿过
 * reducer（reducer 只读 `passcodeStepFor` 的判据，绝不把它写进 `SettingsUiState`），
 * 落盘由 coordinator 的 effect 执行。这个方向是刻意的 —— 密码不能成为「可观察状态」的
 * 一部分，否则每次快照、每条日志都会顺手带上它。
 */

/** 打开「屏幕锁定」子页（入口在「隐私和安全」里，对齐 Android 的 Privacy 页）。 */
export class OpenPasscodePage implements Intent {
  readonly kind: 'openPasscodePage' = 'openPasscodePage';
}

export class ClosePasscodePage implements Intent {
  readonly kind: 'closePasscodePage' = 'closePasscodePage';
}

/** 读盘：本机是否已设 PIN + 自动锁定档位 + 密码可见性偏好。 */
export class LoadPasscodeState implements Intent {
  readonly kind: 'loadPasscodeState' = 'loadPasscodeState';
}

export class PasscodeStateLoaded implements Intent {
  readonly kind: 'passcodeStateLoaded' = 'passcodeStateLoaded';
  readonly isSet: boolean;
  readonly autoLock: AutoLockChoice;
  /** APPLOCK-102：Android `pc_visible`；缺省 false，读不到偏好时按圆点显示。 */
  readonly visible: boolean;

  constructor(isSet: boolean, autoLock: AutoLockChoice, visible: boolean = false) {
    this.isSet = isSet;
    this.autoLock = autoLock;
    this.visible = visible;
  }
}

/**
 * 点「显示输入的密码」行：翻转持久偏好（Android `PasscodeSetupController` 的同名设置行）。
 *
 * 刻意**不是**输入框上的临时小眼睛：Android 那里没有小眼睛，可见性是一个跨会话记住的设置，
 * 且对设置流程与锁屏遮罩同时生效。
 */
export class TogglePasscodeVisible implements Intent {
  readonly kind: 'togglePasscodeVisible' = 'togglePasscodeVisible';
}

/** 可见性写盘失败，回滚开关。 */
export class PasscodeVisibleRejected implements Intent {
  readonly kind: 'passcodeVisibleRejected' = 'passcodeVisibleRejected';
  readonly previous: boolean;

  constructor(previous: boolean) {
    this.previous = previous;
  }
}

/** 点「屏幕锁定」行：未开启则开始创建，已开启则开始关闭（先验密码）。 */
export class TogglePasscodeRequested implements Intent {
  readonly kind: 'togglePasscodeRequested' = 'togglePasscodeRequested';
}

/** 点「修改密码」行：先验当前密码，再走两步输入。 */
export class ChangePasscodeRequested implements Intent {
  readonly kind: 'changePasscodeRequested' = 'changePasscodeRequested';
}

/** 点「自动锁定」行：循环到下一档。 */
export class CycleAutoLockChoice implements Intent {
  readonly kind: 'cycleAutoLockChoice' = 'cycleAutoLockChoice';
}

/** 取消当前流程（键盘上的「取消」）。 */
export class CancelPasscodeFlow implements Intent {
  readonly kind: 'cancelPasscodeFlow' = 'cancelPasscodeFlow';
}

/** 键盘提交四位数字。`pin` 不进状态，见文件头。 */
export class PasscodeSubmitted implements Intent {
  readonly kind: 'passcodeSubmitted' = 'passcodeSubmitted';
  readonly pin: string;

  constructor(pin: string) {
    this.pin = pin;
  }
}

/** coordinator 校验当前密码的结论。 */
export class PasscodeVerified implements Intent {
  readonly kind: 'passcodeVerified' = 'passcodeVerified';
  /** 这次校验是为哪个流程做的：'disable' 验完即关闭，'change' 验完转输入新密码。 */
  readonly purpose: 'disable' | 'change';

  constructor(purpose: 'disable' | 'change') {
    this.purpose = purpose;
  }
}

/** 密码不对，或存储层报错。`noticeKey` 是 Lang key，由 core/domain 常量给出。 */
export class PasscodeRejected implements Intent {
  readonly kind: 'passcodeRejected' = 'passcodeRejected';
  readonly noticeKey: string;

  constructor(noticeKey: string) {
    this.noticeKey = noticeKey;
  }
}

/** 两次输入不一致；草稿由 coordinator 清掉。 */
export class PasscodeMismatched implements Intent {
  readonly kind: 'passcodeMismatched' = 'passcodeMismatched';
}

/** 写盘失败（安全存储报错/自校验不通过）。 */
export class PasscodeOperationFailed implements Intent {
  readonly kind: 'passcodeOperationFailed' = 'passcodeOperationFailed';
  readonly noticeKey: string;

  constructor(noticeKey: string) {
    this.noticeKey = noticeKey;
  }
}

/** 流程成功收尾（已创建 / 已修改 / 已关闭）。 */
export class PasscodeOperationDone implements Intent {
  readonly kind: 'passcodeOperationDone' = 'passcodeOperationDone';
  readonly noticeKey: string;
  readonly isSet: boolean;

  constructor(noticeKey: string, isSet: boolean) {
    this.noticeKey = noticeKey;
    this.isSet = isSet;
  }
}

/** 档位写盘失败，回滚到上一个值。 */
export class AutoLockChoiceRejected implements Intent {
  readonly kind: 'autoLockChoiceRejected' = 'autoLockChoiceRejected';
  readonly previous: AutoLockChoice;

  constructor(previous: AutoLockChoice) {
    this.previous = previous;
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
  | OpenPrivacyKeyPage
  | ClosePrivacyKeyPage
  | PrivacyDetailLoaded
  | PrivacyDetailLoadFailed
  | SetPrivacyMode
  | TogglePrivacyPremium
  | OpenPrivacyPicker
  | ClosePrivacyPicker
  | TogglePrivacyPickerContact
  | ApplyPrivacyPicker
  | PrivacyRulesSaved
  | PrivacyRulesSaveFailed
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
  | OpenPasscodePage
  | ClosePasscodePage
  | LoadPasscodeState
  | PasscodeStateLoaded
  | TogglePasscodeRequested
  | ChangePasscodeRequested
  | CycleAutoLockChoice
  | CancelPasscodeFlow
  | PasscodeSubmitted
  | PasscodeVerified
  | PasscodeRejected
  | PasscodeMismatched
  | PasscodeOperationFailed
  | PasscodeOperationDone
  | AutoLockChoiceRejected
  | TogglePasscodeVisible
  | PasscodeVisibleRejected
  | SectionFocused;
