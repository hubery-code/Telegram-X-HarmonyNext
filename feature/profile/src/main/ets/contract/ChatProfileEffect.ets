/**
 * feature/profile — 群组/频道资料页副作用（PROFILE-102；CHATPROF-SHARED 扩展共享内容分页）。
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

export class FetchSharedContentEffect {
  readonly type: 'fetchSharedContentEffect' = 'fetchSharedContentEffect';
  readonly tab: number;

  constructor(tab: number) {
    this.tab = tab;
  }
}

/** 同一 Tab 的下一页：与首屏同为 searchChatMessages，区别只在游标与是否清空列表。 */
export class FetchMoreSharedContentEffect {
  readonly type: 'fetchMoreSharedContentEffect' = 'fetchMoreSharedContentEffect';
  readonly tab: number;

  constructor(tab: number) {
    this.tab = tab;
  }
}

export class NavigateBackEffect {
  readonly type: 'navigateBackEffect' = 'navigateBackEffect';
}

export type ChatProfileEffect =
  | FetchChatDetailsEffect
  | NavigateToUserProfileEffect
  | CopyInviteLinkEffect
  | FetchSharedContentEffect
  | FetchMoreSharedContentEffect
  | NavigateBackEffect;
