/**
 * feature/chat — 会话页副作用描述（CHAT-001 + CHAT-003 + CHAT-004）。
 *
 * Effect 是一次性副作用的描述，由 Coordinator 执行，reducer 严禁执行。
 *
 * CHAT-004 新增：FetchMessagePermissions（长按后拉 TDLib messageProperties
 * 权限位）、EditMessageText（编辑模式发送）、DeleteMessages（删除消息）；
 * SendTextMessage 扩展 replyToMessageId 支持回复。
 */

import { Effect } from '@tgx/feature-template';

export class FetchInitialMessages implements Effect {
  readonly kind: 'fetchInitialMessages' = 'fetchInitialMessages';
  readonly chatId: number;

  constructor(chatId: number) {
    this.chatId = chatId;
  }
}

export class FetchOlderMessages implements Effect {
  readonly kind: 'fetchOlderMessages' = 'fetchOlderMessages';
  readonly chatId: number;

  constructor(chatId: number) {
    this.chatId = chatId;
  }
}

export class SendTextMessage implements Effect {
  readonly kind: 'sendTextMessage' = 'sendTextMessage';
  readonly chatId: number;
  readonly text: string;
  /** 回复目标消息 id；0 = 非回复。 */
  readonly replyToMessageId: number;

  constructor(chatId: number, text: string, replyToMessageId: number = 0) {
    this.chatId = chatId;
    this.text = text;
    this.replyToMessageId = replyToMessageId;
  }
}

export class FetchMessagePermissions implements Effect {
  readonly kind: 'fetchMessagePermissions' = 'fetchMessagePermissions';
  readonly chatId: number;
  readonly messageId: number;

  constructor(chatId: number, messageId: number) {
    this.chatId = chatId;
    this.messageId = messageId;
  }
}

export class EditMessageText implements Effect {
  readonly kind: 'editMessageText' = 'editMessageText';
  readonly chatId: number;
  readonly messageId: number;
  readonly text: string;

  constructor(chatId: number, messageId: number, text: string) {
    this.chatId = chatId;
    this.messageId = messageId;
    this.text = text;
  }
}

export class DeleteMessages implements Effect {
  readonly kind: 'deleteMessages' = 'deleteMessages';
  readonly chatId: number;
  readonly messageIds: number[];
  /** true = 对所有人删除（revoke），false = 仅自己删除。 */
  readonly revoke: boolean;

  constructor(chatId: number, messageIds: number[], revoke: boolean) {
    this.chatId = chatId;
    this.messageIds = messageIds;
    this.revoke = revoke;
  }
}

export class NavigateBack implements Effect {
  readonly kind: 'navigateBack' = 'navigateBack';
}

/** MSG-104：已读上报（viewMessages），上报到 messageId（含）为止。 */
export class ReportMessagesRead implements Effect {
  readonly kind: 'reportMessagesRead' = 'reportMessagesRead';
  readonly chatId: number;
  readonly messageId: number;

  constructor(chatId: number, messageId: number) {
    this.chatId = chatId;
    this.messageId = messageId;
  }
}

/** MSG-104：重发发送失败的消息（resendMessages）。 */
export class ResendMessage implements Effect {
  readonly kind: 'resendMessage' = 'resendMessage';
  readonly chatId: number;
  readonly messageId: number;

  constructor(chatId: number, messageId: number) {
    this.chatId = chatId;
    this.messageId = messageId;
  }
}

export type ChatEffect =
  | FetchInitialMessages
  | FetchOlderMessages
  | SendTextMessage
  | FetchMessagePermissions
  | EditMessageText
  | DeleteMessages
  | NavigateBack
  | ReportMessagesRead
  | ResendMessage;
