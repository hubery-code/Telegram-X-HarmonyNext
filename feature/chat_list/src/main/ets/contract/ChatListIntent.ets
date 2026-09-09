/**
 * feature/chat_list — 会话列表意图（CHATLIST-002）。
 *
 * 用户动作：LoadChats（首屏/分页加载）、RefreshChats（下拉刷新）、
 * ChatSelected（点击行）；系统事件：OnChatsLoaded / OnChatsLoadFailed
 * 把异步结果回灌 reducer。每个类带字面量 kind 判别属性。
 */

import { Intent } from '@tgx/feature-template';
import { AppError } from '@tgx/core-common';
import { ChatListItem } from '../model/ChatListItem';

export class LoadChats implements Intent {
  readonly kind: 'loadChats' = 'loadChats';
}

export class RefreshChats implements Intent {
  readonly kind: 'refreshChats' = 'refreshChats';
}

export class ChatSelected implements Intent {
  readonly kind: 'chatSelected' = 'chatSelected';
  readonly chatId: number;

  constructor(chatId: number) {
    this.chatId = chatId;
  }
}

export class OnChatsLoaded implements Intent {
  readonly kind: 'onChatsLoaded' = 'onChatsLoaded';
  readonly items: readonly ChatListItem[];

  constructor(items: readonly ChatListItem[]) {
    this.items = items;
  }
}

export class OnChatsLoadFailed implements Intent {
  readonly kind: 'onChatsLoadFailed' = 'onChatsLoadFailed';
  readonly error: AppError;

  constructor(error: AppError) {
    this.error = error;
  }
}

export type ChatListIntent =
  | LoadChats
  | RefreshChats
  | ChatSelected
  | OnChatsLoaded
  | OnChatsLoadFailed;
