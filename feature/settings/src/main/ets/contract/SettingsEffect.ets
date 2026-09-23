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
  | SetPrivacySettingEffect;
