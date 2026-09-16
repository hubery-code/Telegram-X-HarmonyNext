/**
 * feature/profile — 群组/频道资料页意图（PROFILE-102）。
 */

import { AppError } from '@tgx/core-common';
import { Chat, BasicGroupFullInfo, SupergroupFullInfo } from '@tgx/core-td-api-generated';
import { ChatMemberUiItem } from './ChatProfileUiState';

export class OpenChatProfile {
  readonly type: 'openChatProfile' = 'openChatProfile';
  readonly chatId: number;

  constructor(chatId: number) {
    this.chatId = chatId;
  }
}

export class OnChatLoaded {
  readonly type: 'onChatLoaded' = 'onChatLoaded';
  readonly chat: Chat;

  constructor(chat: Chat) {
    this.chat = chat;
  }
}

export class OnBasicGroupFullInfoLoaded {
  readonly type: 'onBasicGroupFullInfoLoaded' = 'onBasicGroupFullInfoLoaded';
  readonly info: BasicGroupFullInfo;

  constructor(info: BasicGroupFullInfo) {
    this.info = info;
  }
}

export class OnSupergroupFullInfoLoaded {
  readonly type: 'onSupergroupFullInfoLoaded' = 'onSupergroupFullInfoLoaded';
  readonly info: SupergroupFullInfo;

  constructor(info: SupergroupFullInfo) {
    this.info = info;
  }
}

export class OnChatMembersLoaded {
  readonly type: 'onChatMembersLoaded' = 'onChatMembersLoaded';
  readonly members: ChatMemberUiItem[];

  constructor(members: ChatMemberUiItem[]) {
    this.members = members;
  }
}

export class OnChatAvatarLoaded {
  readonly type: 'onChatAvatarLoaded' = 'onChatAvatarLoaded';
  readonly path: string;

  constructor(path: string) {
    this.path = path;
  }
}

export class OnChatProfileError {
  readonly type: 'onChatProfileError' = 'onChatProfileError';
  readonly error: AppError;

  constructor(error: AppError) {
    this.error = error;
  }
}

export class SelectChatMember {
  readonly type: 'selectChatMember' = 'selectChatMember';
  readonly userId: number;

  constructor(userId: number) {
    this.userId = userId;
  }
}

export class CopyInviteLinkRequested {
  readonly type: 'copyInviteLinkRequested' = 'copyInviteLinkRequested';
}

export class BackRequested {
  readonly type: 'backRequested' = 'backRequested';
}

export type ChatProfileIntent =
  | OpenChatProfile
  | OnChatLoaded
  | OnBasicGroupFullInfoLoaded
  | OnSupergroupFullInfoLoaded
  | OnChatMembersLoaded
  | OnChatAvatarLoaded
  | OnChatProfileError
  | SelectChatMember
  | CopyInviteLinkRequested
  | BackRequested;
