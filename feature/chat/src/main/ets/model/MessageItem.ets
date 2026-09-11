/**
 * feature/chat — 单条消息视图模型（CHAT-001/CHAT-002 + CHAT-003 + CHAT-004）。
 *
 * MessageItem 是渲染一个气泡所需的扁平不可变数据，由领域层 MessageProjection
 * 的 Message 映射产出（ChatCoordinator）。
 *
 * CHAT-004 新增：
 * - isTextMessage：编辑动作只对文本消息开放（editMessageText）；
 * - isEdited：edit_date > 0，气泡时间戳旁附 "edited"；
 * - replyToMessageId / replyToSummary：回复引用（原消息不在当前列表时摘要为空）。
 *
 * MSG-101 新增：
 * - spans：messageText 消息的富文本分段（FormattedText entities 解析结果）；
 *   非文本消息或无 entities 时为空数组，气泡回退到 text 纯文本渲染。
 *
 * MSG-102 新增：
 * - senderColorIndex：群聊署名/头像的调色板索引（0..6），-1 = 无署名/默认色。
 */

import { MessageTextSpan } from './MessageTextSpan';

/** 发送状态：none=已发送/收到的正常消息；pending=发送中；failed=发送失败。 */
export type MessageSendState = 'none' | 'pending' | 'failed';

export class MessageItem {
  readonly messageId: number;
  readonly text: string;
  readonly timestampMs: number;
  readonly isOutgoing: boolean;
  readonly senderName: string;
  readonly sendState: MessageSendState;
  readonly isTextMessage: boolean;
  readonly isEdited: boolean;
  readonly replyToMessageId: number | null;
  readonly replyToSummary: string;
  readonly spans: MessageTextSpan[];
  readonly senderColorIndex: number;

  constructor(
    messageId: number,
    text: string,
    timestampMs: number,
    isOutgoing: boolean,
    senderName: string,
    sendState: MessageSendState = 'none',
    isTextMessage: boolean = true,
    isEdited: boolean = false,
    replyToMessageId: number | null = null,
    replyToSummary: string = '',
    spans: MessageTextSpan[] = [],
    senderColorIndex: number = -1
  ) {
    this.messageId = messageId;
    this.text = text;
    this.timestampMs = timestampMs;
    this.isOutgoing = isOutgoing;
    this.senderName = senderName;
    this.sendState = sendState;
    this.isTextMessage = isTextMessage;
    this.isEdited = isEdited;
    this.replyToMessageId = replyToMessageId;
    this.replyToSummary = replyToSummary;
    this.spans = spans;
    this.senderColorIndex = senderColorIndex;
  }
}
