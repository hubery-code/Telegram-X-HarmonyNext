/**
 * feature/profile — 群组/频道资料页意图（PROFILE-102；CHATPROF-SHARED 扩展共享内容）。
 */

import { AppError } from '@tgx/core-common';
import { Chat, BasicGroupFullInfo, SupergroupFullInfo } from '@tgx/core-td-api-generated';
import { ChatMemberUiItem } from './ChatProfileUiState';
import { SharedFileItem, SharedLinkItem, SharedMediaItem } from './SharedContentItems';

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

export class OnSharedTabSelected {
  readonly type: 'onSharedTabSelected' = 'onSharedTabSelected';
  readonly tab: number;

  constructor(tab: number) {
    this.tab = tab;
  }
}

export class LoadMoreSharedContent {
  readonly type: 'loadMoreSharedContent' = 'loadMoreSharedContent';
  readonly tab: number;

  constructor(tab: number) {
    this.tab = tab;
  }
}

export class OnSharedContentLoaded {
  readonly type: 'onSharedContentLoaded' = 'onSharedContentLoaded';
  readonly tab: number;
  readonly media: SharedMediaItem[];
  readonly files: SharedFileItem[];
  readonly links: SharedLinkItem[];
  readonly hasMore: boolean;

  constructor(
    tab: number,
    media: SharedMediaItem[],
    files: SharedFileItem[],
    links: SharedLinkItem[],
    hasMore: boolean = false
  ) {
    this.tab = tab;
    this.media = media;
    this.files = files;
    this.links = links;
    this.hasMore = hasMore;
  }
}

export class OnSharedContentFailed {
  readonly type: 'onSharedContentFailed' = 'onSharedContentFailed';
  readonly tab: number;

  constructor(tab: number) {
    this.tab = tab;
  }
}

export type ChatProfileIntent =
  | OpenChatProfile
  | OnChatLoaded
  | OnBasicGroupFullInfoLoaded
  | OnSupergroupFullInfoLoaded
  | OnChatMembersLoaded
  | OnChatAvatarLoaded
  | OnChatProfileError
  | OnSharedTabSelected
  | LoadMoreSharedContent
  | OnSharedContentLoaded
  | OnSharedContentFailed
  | SelectChatMember
  | CopyInviteLinkRequested
  | BackRequested;
