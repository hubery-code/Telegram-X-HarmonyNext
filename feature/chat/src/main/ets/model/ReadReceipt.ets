/**
 * feature/chat — 已读回执与已读上报的纯函数（MSG-104）。
 *
 * - isOutgoingMessageRead：己方消息 id <= 对端已读水位（lastReadOutboxMessageId）
 *   即已读；收到的消息、水位 0（未知）一律未读。
 * - incomingIdUpTo：在 [0, lastVisibleIndex] 范围内取最大的 incoming 消息 id
 *   （只上报入屏的消息；越界 index clamp，空列表/负 index 安全返回 0）。
 * - ReadReportThrottle：上报节流器，lastReported 只增不减，poll() 返回本次
 *   应上报的 messageId（无需上报返回 0）。
 */

import { MessageItem } from './MessageItem';

/** 己方消息是否已被对端读：id 不超过已读水位即已读（消息 id 会话内单调递增）。 */
export function isOutgoingMessageRead(
  isOutgoing: boolean,
  messageId: number,
  lastReadOutboxMessageId: number
): boolean {
  if (!isOutgoing || lastReadOutboxMessageId <= 0) {
    return false;
  }
  return messageId <= lastReadOutboxMessageId;
}

/**
 * [0, lastVisibleIndex] 内最大 incoming 消息 id；无 incoming / 空列表 / 负 index → 0。
 * 消息列表按 id 升序，从 lastVisibleIndex 向前扫到第一条 incoming 即可。
 */
export function incomingIdUpTo(items: readonly MessageItem[], lastVisibleIndex: number): number {
  if (items.length === 0 || lastVisibleIndex < 0) {
    return 0;
  }
  const end: number = Math.min(lastVisibleIndex, items.length - 1);
  for (let i = end; i >= 0; i--) {
    if (!items[i].isOutgoing) {
      return items[i].messageId;
    }
  }
  return 0;
}

/**
 * 已读上报节流：lastReported 只增不减；target 超过上次才放行并更新基线，
 * 否则（含 target=0 无 incoming）返回 0 表示本次不上报。
 */
export class ReadReportThrottle {
  private lastReported: number = 0;

  get lastReportedId(): number {
    return this.lastReported;
  }

  /** 按可视范围求值；返回 0 = 无需上报。 */
  poll(items: readonly MessageItem[], lastVisibleIndex: number): number {
    const target: number = incomingIdUpTo(items, lastVisibleIndex);
    if (target <= this.lastReported) {
      return 0;
    }
    this.lastReported = target;
    return target;
  }

  /** 直接按目标 id 判定（reducer 已把 index 映射成 messageId 的 effect 路径用）。 */
  shouldReport(messageId: number): boolean {
    if (messageId <= this.lastReported) {
      return false;
    }
    this.lastReported = messageId;
    return true;
  }
}
