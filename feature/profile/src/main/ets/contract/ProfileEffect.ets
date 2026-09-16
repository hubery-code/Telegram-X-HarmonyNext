/**
 * feature/profile — 用户资料页效应（PROFILE-101）。
 */

import { Effect } from '@tgx/feature-template';

/** 创建（或复用）与目标用户的私聊，成功后由装配层导航过去。 */
export class CreatePrivateChatEffect implements Effect {
  readonly kind: 'createPrivateChat' = 'createPrivateChat';
  readonly userId: number;

  constructor(userId: number) {
    this.userId = userId;
  }
}

export type ProfileEffect = CreatePrivateChatEffect;
