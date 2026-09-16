/**
 * feature/profile — 群组/频道资料页副作用（PROFILE-102）。
 */

export class FetchChatDetailsEffect {
  readonly type: 'fetchChatDetailsEffect' = 'fetchChatDetailsEffect';
  readonly chatId: number;

  constructor(chatId: number) {
    this.chatId = chatId;
  }
}

export class NavigateToUserProfileEffect {
  readonly type: 'navigateToUserProfileEffect' = 'navigateToUserProfileEffect';
  readonly userId: number;

  constructor(userId: number) {
    this.userId = userId;
  }
}

export class CopyInviteLinkEffect {
  readonly type: 'copyInviteLinkEffect' = 'copyInviteLinkEffect';
  readonly link: string;

  constructor(link: string) {
    this.link = link;
  }
}

export class NavigateBackEffect {
  readonly type: 'navigateBackEffect' = 'navigateBackEffect';
}

export type ChatProfileEffect =
  | FetchChatDetailsEffect
  | NavigateToUserProfileEffect
  | CopyInviteLinkEffect
  | NavigateBackEffect;
