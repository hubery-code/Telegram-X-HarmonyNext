/**
 * feature/chat_list — 会话列表副作用描述（CHATLIST-002 + MSG-108）。
 *
 * Effect 是一次性副作用的描述，由 Coordinator / Handler 执行，reducer 严禁执行。
 */

import { Effect } from '@tgx/feature-template';
import { ChatListKind } from './ChatListUiState';

export class FetchChatList implements Effect {
  readonly kind: 'fetchChatList' = 'fetchChatList';
  readonly limit: number;
  readonly listKind: ChatListKind;

  constructor(limit: number, listKind: ChatListKind = 'main') {
    this.limit = limit;
    this.listKind = listKind;
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

/** MSG-108：置顶/取消置顶（toggleChatIsPinned）。 */
export class SetChatPinned implements Effect {
  readonly kind: 'setChatPinned' = 'setChatPinned';
  readonly chatId: number;
  readonly isPinned: boolean;

  constructor(chatId: number, isPinned: boolean) {
    this.chatId = chatId;
    this.isPinned = isPinned;
  }
}

/**
 * MSG-108：改会话的已读状态。
 * markAsUnread=true → 只置手动未读标记（toggleChatIsMarkedAsUnread(true)）；
 * markAsUnread=false → 清标记 + 若有未读消息则一并 viewMessages 读掉
 * （两件事都在 coordinator 执行，reducer 只声明意图方向）。
 */
export class SetChatReadState implements Effect {
  readonly kind: 'setChatReadState' = 'setChatReadState';
  readonly chatId: number;
  readonly markAsUnread: boolean;

  constructor(chatId: number, markAsUnread: boolean) {
    this.chatId = chatId;
    this.markAsUnread = markAsUnread;
  }
}

export class SetChatArchived implements Effect {
  readonly kind: 'setChatArchived' = 'setChatArchived';
  readonly chatId: number;
  readonly archived: boolean;

  constructor(chatId: number, archived: boolean) {
    this.chatId = chatId;
    this.archived = archived;
  }
}

export type ChatListEffect =
  | FetchChatList
  | NavigateToChat
  | ShowToast
  | SetChatPinned
  | SetChatReadState
  | SetChatArchived;
