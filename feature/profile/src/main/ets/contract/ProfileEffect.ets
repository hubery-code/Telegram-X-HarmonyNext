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

/** PROFILE-103：拉取更多共享内容（Tab 0..3 分页拉取）。 */
export class FetchMoreSharedContent implements Effect {
  readonly kind: 'fetchMoreSharedContent' = 'fetchMoreSharedContent';
  readonly tab: number;

  constructor(tab: number) {
    this.tab = tab;
  }
}

/** PROFILE-103：打开共同群组会话（chatId 已在列表里，无需再 createPrivateChat）。 */
export class OpenSharedChatEffect implements Effect {
  readonly kind: 'openSharedChat' = 'openSharedChat';
  readonly chatId: number;

  constructor(chatId: number) {
    this.chatId = chatId;
  }
}

/**
 * PROFILE-103 收尾：读该私聊会话的通知设置（createPrivateChat → getChat）。
 * 首屏与「写成功后复核」共用这一条 effect —— 通知行不做乐观更新。
 */
export class FetchChatNotification implements Effect {
  readonly kind: 'fetchChatNotification' = 'fetchChatNotification';
}

/** PROFILE-103 收尾：写会话静音态（setChatNotificationSettings，以回读快照为底本只改 mute_for）。 */
export class SetChatNotification implements Effect {
  readonly kind: 'setChatNotification' = 'setChatNotification';
  readonly muted: boolean;

  constructor(muted: boolean) {
    this.muted = muted;
  }
}

/** PROFILE-103 收尾：createNewSecretChat 开密聊，成功后由协调器把密聊 chatId 交给装配层导航。 */
export class CreateSecretChatEffect implements Effect {
  readonly kind: 'createSecretChat' = 'createSecretChat';
}

/** PROFILE-103 收尾：写对端屏蔽态（setMessageSenderBlockList，blocked=true 进主黑名单、false 解除）。 */
export class SetPeerBlock implements Effect {
  readonly kind: 'setPeerBlock' = 'setPeerBlock';
  readonly blocked: boolean;

  constructor(blocked: boolean) {
    this.blocked = blocked;
  }
}

export type ProfileEffect = CreatePrivateChatEffect | FetchSharedContent | FetchSharedGroups |
  FetchMoreSharedContent | OpenSharedChatEffect | FetchChatNotification | SetChatNotification |
  CreateSecretChatEffect | SetPeerBlock;
