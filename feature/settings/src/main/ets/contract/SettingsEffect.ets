/**
 * feature/settings — 设置页副作用描述（SET-101）。
 *
 * 遵循计划 §5.11 / UI-003：
 * - Effect 是一次性副作用的声明式描述，由 Coordinator 执行；
 * - reducer 是纯函数，严禁执行副作用；
 * - 纯 ArkTS 契约层。
 */

import { Effect } from '@tgx/feature-template';
import { NotificationScopeKey } from '../model/NotificationSettings';
import { PrivacyChoice, PrivacySettingKey } from '../model/PrivacySettings';
import { ProxyForm } from '../model/ProxySettings';
import { AutoDownloadPolicy, AutoLockChoice, DataSaverSettings, DownloadLimitsByNetwork } from '@tgx/core-domain';

export class LoadProfileEffect implements Effect {
  readonly kind: 'loadProfile' = 'loadProfile';
}

export class LoadNotificationSettingsEffect implements Effect {
  readonly kind: 'loadNotificationSettings' = 'loadNotificationSettings';
}

export class SetNotificationsEnabledEffect implements Effect {
  readonly kind: 'setNotificationsEnabled' = 'setNotificationsEnabled';
  readonly enabled: boolean;

  constructor(enabled: boolean) {
    this.enabled = enabled;
  }
}

export class SetNotificationScopeEnabledEffect implements Effect {
  readonly kind: 'setNotificationScopeEnabled' = 'setNotificationScopeEnabled';
  readonly scope: NotificationScopeKey;
  readonly enabled: boolean;

  constructor(scope: NotificationScopeKey, enabled: boolean) {
    this.scope = scope;
    this.enabled = enabled;
  }
}

export class LogoutEffect implements Effect {
  readonly kind: 'logout' = 'logout';
}

export class ClearCacheEffect implements Effect {
  readonly kind: 'clearCache' = 'clearCache';
}

/** SET-104：拉取存储占用统计（getStorageStatistics）。 */
export class LoadStorageStatsEffect implements Effect {
  readonly kind: 'loadStorageStats' = 'loadStorageStats';
}

export class ShowToastEffect implements Effect {
  readonly kind: 'showToast' = 'showToast';
  readonly message: string;

  constructor(message: string) {
    this.message = message;
  }
}

export class NavigateToAuthEffect implements Effect {
  readonly kind: 'navigateToAuth' = 'navigateToAuth';
}

export class SwitchAccountEffect implements Effect {
  readonly kind: 'switchAccount' = 'switchAccount';
  readonly accountKey: string;

  constructor(accountKey: string) {
    this.accountKey = accountKey;
  }
}

export class RequestAddAccountEffect implements Effect {
  readonly kind: 'requestAddAccount' = 'requestAddAccount';
}

/** FEAT-P2-008：拉取活跃设备/会话列表（getActiveSessions）。 */
export class LoadActiveSessionsEffect implements Effect {
  readonly kind: 'loadActiveSessions' = 'loadActiveSessions';
}

/** FEAT-P2-008：终止指定设备会话（terminateSession）。 */
export class TerminateSessionEffect implements Effect {
  readonly kind: 'terminateSession' = 'terminateSession';
  readonly sessionId: string;

  constructor(sessionId: string) {
    this.sessionId = sessionId;
  }
}

/** FEAT-P2-008：终止除当前设备外的所有会话（terminateAllOtherSessions）。 */
export class TerminateAllOtherSessionsEffect implements Effect {
  readonly kind: 'terminateAllOtherSessions' = 'terminateAllOtherSessions';
}

/** SELF-102：逐项读取 getUserPrivacySettingRules。 */
export class LoadPrivacySettingsEffect implements Effect {
  readonly kind: 'loadPrivacySettings' = 'loadPrivacySettings';
}

/** SELF-102：写回 setUserPrivacySettingRules 后回读该项。 */
export class SetPrivacySettingEffect implements Effect {
  readonly kind: 'setPrivacySetting' = 'setPrivacySetting';
  readonly key: PrivacySettingKey;
  readonly choice: PrivacyChoice;

  constructor(key: PrivacySettingKey, choice: PrivacyChoice) {
    this.key = key;
    this.choice = choice;
  }
}

/** PROXY-101：读取代理列表（getProxies）。 */
export class LoadProxiesEffect implements Effect {
  readonly kind: 'loadProxies' = 'loadProxies';
}

/** PROXY-101：启用代理（enableProxy），随后回读列表校正单选态。 */
export class EnableProxyEffect implements Effect {
  readonly kind: 'enableProxy' = 'enableProxy';
  readonly proxyId: number;

  constructor(proxyId: number) {
    this.proxyId = proxyId;
  }
}

/** PROXY-101：停用当前代理（disableProxy）。 */
export class DisableProxyEffect implements Effect {
  readonly kind: 'disableProxy' = 'disableProxy';
}

/** PROXY-101：保存代理；`form.id === PROXY_NEW_ID` 走 addProxy，否则走 editProxy。 */
export class SaveProxyEffect implements Effect {
  readonly kind: 'saveProxy' = 'saveProxy';
  readonly form: ProxyForm;

  constructor(form: ProxyForm) {
    this.form = form;
  }
}

/** PROXY-101：删除代理（removeProxy）。 */
export class RemoveProxyEffect implements Effect {
  readonly kind: 'removeProxy' = 'removeProxy';
  readonly proxyId: number;

  constructor(proxyId: number) {
    this.proxyId = proxyId;
  }
}

/**
 * PROXY-102：探测列表里每一行的连通性（含「不使用代理」行的直连探测）。
 * 与 TGX 同规则：列表每次（重）建都要 ping 一遍，这样「可用性」是测出来的，不是猜的。
 */
export class PingProxiesEffect implements Effect {
  readonly kind: 'pingProxies' = 'pingProxies';
}

/** AUTODL-101：读取自动下载策略（本地偏好，同步返回）。 */
export class LoadAutoDownloadPolicyEffect implements Effect {
  readonly kind: 'loadAutoDownloadPolicy' = 'loadAutoDownloadPolicy';
}

/**
 * AUTODL-101：写回自动下载策略。
 * 勾选即落盘（对齐 TGX：对话框里没有「应用」按钮），所以这里带的是整份策略而不是单项。
 */
export class PersistAutoDownloadPolicyEffect implements Effect {
  readonly kind: 'persistAutoDownloadPolicy' = 'persistAutoDownloadPolicy';
  readonly policy: AutoDownloadPolicy;

  constructor(policy: AutoDownloadPolicy) {
    this.policy = policy;
  }
}

/**
 * AUTODL-102：读取省流量设置（本地偏好，同步返回）。
 * 与自动下载策略分开两个意图：两者存在两个不同的偏好键里，读盘也各自失败。
 */
export class LoadDataSaverSettingsEffect implements Effect {
  readonly kind: 'loadDataSaverSettings' = 'loadDataSaverSettings';
}

/**
 * AUTODL-102：写回省流量设置。
 * 同样是「勾选即落盘」，一份整数掩码（对齐 Android 的 `settings_datasaver`）。
 */
export class PersistDataSaverSettingsEffect implements Effect {
  readonly kind: 'persistDataSaverSettings' = 'persistDataSaverSettings';
  readonly settings: DataSaverSettings;

  constructor(settings: DataSaverSettings) {
    this.settings = settings;
  }
}

/**
 * AUTODL-103：读取按网络档的自动下载限制（本地偏好，同步返回）。
 * 第三份独立设置：与前两者各自读盘、各自失败，不共用一个意图。
 */
export class LoadDownloadLimitsEffect implements Effect {
  readonly kind: 'loadDownloadLimits' = 'loadDownloadLimits';
}

/**
 * AUTODL-103：写回整份限制。
 * 同样是「勾选即落盘」；一写就是三档六格，避免只写半套留下不一致的状态。
 */
export class PersistDownloadLimitsEffect implements Effect {
  readonly kind: 'persistDownloadLimits' = 'persistDownloadLimits';
  readonly limits: DownloadLimitsByNetwork;

  constructor(limits: DownloadLimitsByNetwork) {
    this.limits = limits;
  }
}

/**
 * APPLOCK-101 — 应用锁副作用。
 *
 * 三条带 `pin` 的 effect 与 `PasscodeSubmitted` 同理：PIN 只在「reducer → coordinator →
 * 安全存储」这条一次性通道上路过，不落脚任何可观察状态。`storePasscodeDraft` 的草稿
 * 存在 coordinator 的私有字段里，流程取消或结束时清空。
 */

/** 读盘：本机是否已设 PIN + 档位。 */
export class LoadPasscodeStateEffect implements Effect {
  readonly kind: 'loadPasscodeState' = 'loadPasscodeState';
}

/** 暂存第一次输入的新密码，供确认步比对。 */
export class StorePasscodeDraftEffect implements Effect {
  readonly kind: 'storePasscodeDraft' = 'storePasscodeDraft';
  readonly pin: string;

  constructor(pin: string) {
    this.pin = pin;
  }
}

/** 与草稿比对后落盘（创建或修改）。 */
export class CommitPasscodeEffect implements Effect {
  readonly kind: 'commitPasscode' = 'commitPasscode';
  readonly pin: string;

  constructor(pin: string) {
    this.pin = pin;
  }
}

/** 校验当前密码；`purpose` 决定验完是关闭还是转修改。 */
export class VerifyPasscodeEffect implements Effect {
  readonly kind: 'verifyPasscode' = 'verifyPasscode';
  readonly pin: string;
  readonly purpose: 'disable' | 'change';

  constructor(pin: string, purpose: 'disable' | 'change') {
    this.pin = pin;
    this.purpose = purpose;
  }
}

/**
 * 清掉确认步的草稿。取消、关闭子页、写盘失败都要走这一条：草稿留着，
 * 下一次走到确认步就会拿上一次的输入来比对，等于用旧密码确认新密码。
 */
export class ClearPasscodeDraftEffect implements Effect {
  readonly kind: 'clearPasscodeDraft' = 'clearPasscodeDraft';
}

/** 写自动锁定档位。 */
export class PersistAutoLockChoiceEffect implements Effect {
  readonly kind: 'persistAutoLockChoice' = 'persistAutoLockChoice';
  readonly choice: AutoLockChoice;

  constructor(choice: AutoLockChoice) {
    this.choice = choice;
  }
}

/** 写「显示输入的密码」偏好（APPLOCK-102）。 */
export class PersistPasscodeVisibleEffect implements Effect {
  readonly kind: 'persistPasscodeVisible' = 'persistPasscodeVisible';
  readonly visible: boolean;

  constructor(visible: boolean) {
    this.visible = visible;
  }
}

export type SettingsEffect =
  | LoadProfileEffect
  | LoadNotificationSettingsEffect
  | SetNotificationsEnabledEffect
  | SetNotificationScopeEnabledEffect
  | LogoutEffect
  | ClearCacheEffect
  | LoadStorageStatsEffect
  | ShowToastEffect
  | NavigateToAuthEffect
  | SwitchAccountEffect
  | RequestAddAccountEffect
  | LoadActiveSessionsEffect
  | TerminateSessionEffect
  | TerminateAllOtherSessionsEffect
  | LoadPrivacySettingsEffect
  | SetPrivacySettingEffect
  | LoadProxiesEffect
  | EnableProxyEffect
  | DisableProxyEffect
  | SaveProxyEffect
  | RemoveProxyEffect
  | PingProxiesEffect
  | LoadAutoDownloadPolicyEffect
  | PersistAutoDownloadPolicyEffect
  | LoadDataSaverSettingsEffect
  | PersistDataSaverSettingsEffect
  | LoadDownloadLimitsEffect
  | PersistDownloadLimitsEffect
  | LoadPasscodeStateEffect
  | StorePasscodeDraftEffect
  | CommitPasscodeEffect
  | VerifyPasscodeEffect
  | ClearPasscodeDraftEffect
  | PersistAutoLockChoiceEffect
  | PersistPasscodeVisibleEffect;
