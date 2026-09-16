/**
 * feature/self — 我的资料页效应（SELF-101）。
 */

import { Effect } from '@tgx/feature-template';

/** 拉取当前用户：start() 触发，getMe → decodeUser → putUser → 组帧回灌。 */
export class FetchMeEffect implements Effect {
  readonly kind: 'fetchMe' = 'fetchMe';
}

export type SelfProfileEffect = FetchMeEffect;
