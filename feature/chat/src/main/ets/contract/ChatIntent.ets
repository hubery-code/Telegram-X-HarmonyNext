/**
 * feature/chat — 会话页意图（CHAT-001）。
 *
 * 用户动作：LoadInitialMessages（首屏加载）、LoadOlderMessages（滚动到顶翻页）、
 * BackToChatList（返回会话列表）；系统事件：OnMessagesLoaded / OnMessagesLoadFailed
 * 把异步结果回灌 reducer。每个类带字面量 kind 判别属性。
 */

import { Intent } from '@tgx/feature-template';
import { AppError } from '@tgx/core-common';
import { MessageItem } from '../model/MessageItem';

export class LoadInitialMessages implements Intent {
  readonly kind: 'loadInitialMessages' = 'loadInitialMessages';
}

export class LoadOlderMessages implements Intent {
  readonly kind: 'loadOlderMessages' = 'loadOlderMessages';
}

export class OnMessagesLoaded implements Intent {
  readonly kind: 'onMessagesLoaded' = 'onMessagesLoaded';
  readonly messages: readonly MessageItem[];
  readonly hasMoreOlder: boolean;

  constructor(messages: readonly MessageItem[], hasMoreOlder: boolean) {
    this.messages = messages;
    this.hasMoreOlder = hasMoreOlder;
  }
}

export class OnMessagesLoadFailed implements Intent {
  readonly kind: 'onMessagesLoadFailed' = 'onMessagesLoadFailed';
  readonly error: AppError;

  constructor(error: AppError) {
    this.error = error;
  }
}

export class BackToChatList implements Intent {
  readonly kind: 'backToChatList' = 'backToChatList';
}

export type ChatIntent =
  | LoadInitialMessages
  | LoadOlderMessages
  | OnMessagesLoaded
  | OnMessagesLoadFailed
  | BackToChatList;
