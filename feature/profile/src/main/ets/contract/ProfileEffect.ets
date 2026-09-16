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

/** PROFILE-103：拉取共享内容（Tab 0 媒体 / 1 文件 / 2 链接），协调器内先 createPrivateChat 再 searchChatMessages。 */
export class FetchSharedContent implements Effect {
  readonly kind: 'fetchSharedContent' = 'fetchSharedContent';
  readonly tab: number;

  constructor(tab: number) {
    this.tab = tab;
  }
}

/** PROFILE-103：拉取与该用户的共同群组（getGroupsInCommon）。 */
export class FetchSharedGroups implements Effect {
  readonly kind: 'fetchSharedGroups' = 'fetchSharedGroups';
}

export type ProfileEffect = CreatePrivateChatEffect | FetchSharedContent | FetchSharedGroups;
