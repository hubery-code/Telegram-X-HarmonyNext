/**
 * feature/chat — 单条消息视图模型（CHAT-001/CHAT-002）。
 *
 * MessageItem 是渲染一个气泡所需的扁平不可变数据，由领域层 MessageProjection
 * 的 Message 映射产出（ChatCoordinator）。
 */

export class MessageItem {
  readonly messageId: number;
  readonly text: string;
  readonly timestampMs: number;
  readonly isOutgoing: boolean;
  readonly senderName: string;

  constructor(
    messageId: number,
    text: string,
    timestampMs: number,
    isOutgoing: boolean,
    senderName: string
  ) {
    this.messageId = messageId;
    this.text = text;
    this.timestampMs = timestampMs;
    this.isOutgoing = isOutgoing;
    this.senderName = senderName;
  }
}
