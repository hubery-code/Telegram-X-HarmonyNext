/**
 * feature/settings — 设置页副作用描述（SET-101）。
 *
 * 遵循计划 §5.11 / UI-003：
 * - Effect 是一次性副作用的声明式描述，由 Coordinator 执行；
 * - reducer 是纯函数，严禁执行副作用；
 * - 纯 ArkTS 契约层。
 */

import { Effect } from '@tgx/feature-template';

export class LoadProfileEffect implements Effect {
  readonly kind: 'loadProfile' = 'loadProfile';
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

export type SettingsEffect =
  | LoadProfileEffect
  | LogoutEffect
  | ClearCacheEffect
  | LoadStorageStatsEffect
  | ShowToastEffect
  | NavigateToAuthEffect
  | SwitchAccountEffect
  | RequestAddAccountEffect;
