/**
 * feature/self — 我的资料页效应（SELF-101）。
 */

import { Effect } from '@tgx/feature-template';

/** 拉取当前用户：start() 触发，getMe → decodeUser → putUser → 组帧回灌。 */
export class FetchMeEffect implements Effect {
  readonly kind: 'fetchMe' = 'fetchMe';
}

/**
 * SELF-101：入口行点击 → 打开设置页对应分区（'devices' | 'notifications' |
 * 'data_and_storage'）。导航由装配层落地，feature 层不感知路由栈。
 */
export class OpenSettingsSection implements Effect {
  readonly kind: 'openSettingsSection' = 'openSettingsSection';
  readonly section: string;

  constructor(section: string) {
    this.section = section;
  }
}

export type SelfProfileEffect = FetchMeEffect | OpenSettingsSection;
