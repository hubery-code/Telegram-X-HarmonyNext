/**
 * feature/chat_list — 会话列表副作用描述（CHATLIST-002）。
 *
 * Effect 是一次性副作用的描述，由 Coordinator / Handler 执行，reducer 严禁执行。
 */

import { Effect } from '@tgx/feature-template';

export class FetchChatList implements Effect {
  readonly kind: 'fetchChatList' = 'fetchChatList';
  readonly limit: number;

  constructor(limit: number) {
    this.limit = limit;
  }
}

export class NavigateToChat implements Effect {
  readonly kind: 'navigateToChat' = 'navigateToChat';
  readonly chatId: number;

  constructor(chatId: number) {
    this.chatId = chatId;
  }
}

export class ShowToast implements Effect {
  readonly kind: 'showToast' = 'showToast';
  readonly messageKey: string;

  constructor(messageKey: string) {
    this.messageKey = messageKey;
  }
}

export type ChatListEffect =
  | FetchChatList
  | NavigateToChat
  | ShowToast;
