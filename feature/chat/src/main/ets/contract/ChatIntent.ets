/**
 * feature/chat — 会话页意图（CHAT-001 + CHAT-003）。
 *
 * 用户动作：LoadInitialMessages（首屏加载）、LoadOlderMessages（滚动到顶翻页）、
 * ComposerTextChanged（输入栏文本变化）、SendCurrentMessage（发送当前输入）、
 * BackToChatList（返回会话列表）；系统事件：OnMessagesLoaded /
 * OnMessagesLoadFailed / OnMessageSendFailed 把异步结果回灌 reducer。
 * 每个类带字面量 kind 判别属性。
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

export class ComposerTextChanged implements Intent {
  readonly kind: 'composerTextChanged' = 'composerTextChanged';
  readonly text: string;

  constructor(text: string) {
    this.text = text;
  }
}

export class SendCurrentMessage implements Intent {
  readonly kind: 'sendCurrentMessage' = 'sendCurrentMessage';
}

export class OnMessageSendFailed implements Intent {
  readonly kind: 'onMessageSendFailed' = 'onMessageSendFailed';
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
  | ComposerTextChanged
  | SendCurrentMessage
  | OnMessageSendFailed
  | BackToChatList;
