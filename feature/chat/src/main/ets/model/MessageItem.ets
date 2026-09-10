/**
 * feature/chat — 单条消息视图模型（CHAT-001/CHAT-002 + CHAT-003）。
 *
 * MessageItem 是渲染一个气泡所需的扁平不可变数据，由领域层 MessageProjection
 * 的 Message 映射产出（ChatCoordinator）。
 */

/** 发送状态：none=已发送/收到的正常消息；pending=发送中；failed=发送失败。 */
export type MessageSendState = 'none' | 'pending' | 'failed';

export class MessageItem {
  readonly messageId: number;
  readonly text: string;
  readonly timestampMs: number;
  readonly isOutgoing: boolean;
  readonly senderName: string;
  readonly sendState: MessageSendState;

  constructor(
    messageId: number,
    text: string,
    timestampMs: number,
    isOutgoing: boolean,
    senderName: string,
    sendState: MessageSendState = 'none'
  ) {
    this.messageId = messageId;
    this.text = text;
    this.timestampMs = timestampMs;
    this.isOutgoing = isOutgoing;
    this.senderName = senderName;
    this.sendState = sendState;
  }
}
