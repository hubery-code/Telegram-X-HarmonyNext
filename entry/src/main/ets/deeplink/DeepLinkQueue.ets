/**
 * entry/src/main/ets/deeplink/DeepLinkQueue.ets — 深链排队（DEEPLINK-101）。
 *
 * 存在理由是**时序**：`EntryAbility.onCreate(want)` 跑的时候页面还没 `aboutToAppear`，
 * 而解析一条 `t.me/xxx` 需要 `AccountScope` 与路由栈都在。所以链接先入队，等页面 ready
 * 再一次性交付；热启动（`onNewWant`）时页面已在，直接命中 handler。
 *
 * 三条纪律：
 * 1. **去重只针对「还没交出去的部分」**。系统在同一次冷启动里可能既给 `onCreate` 又给
 *    `onNewWant` 送同一个 uri；已经交付过的链接再来一次是真想再去一趟，不该被吞。
 * 2. **有上限并丢最旧**（`MAX_PENDING`）。队列没有消费者时（auth 未完成、页面没起）
 *    不能无界攒着，否则恢复后一次性压出 N 层会话栈。
 * 3. **handler 抛异常不能让队列卡住**：交付循环里逐条 try，坏一条丢一条。
 */

export type DeepLinkHandler = (uri: string) => void;

/** 队列里最多攒几条；超出丢最旧。 */
export const DEEP_LINK_MAX_PENDING: number = 8;

export type DeepLinkEnqueueResult = 'delivered' | 'queued' | 'duplicate' | 'empty';

export class DeepLinkQueue {
  private readonly pending: string[] = [];
  private handler: DeepLinkHandler | null = null;

  /**
   * 装上消费者，并立刻把积压按入队顺序交付。
   * 返回值是本次交付的条数（页面 ready 时才可能 > 0）。
   */
  attach(handler: DeepLinkHandler): number {
    this.handler = handler;
    const batch: string[] = this.pending.slice();
    this.pending.length = 0;
    for (let i: number = 0; i < batch.length; i++) {
      try {
        handler(batch[i]);
      } catch (e) {
        // 一条坏链接不能连带后面几条不交付。
        continue;
      }
    }
    return batch.length;
  }

  /** 卸下消费者（页面销毁时调用，避免 handler 闭包吊着已销毁的协调器）。 */
  detach(): void {
    this.handler = null;
  }

  isAttached(): boolean {
    return this.handler !== null;
  }

  enqueue(uri: string): DeepLinkEnqueueResult {
    const trimmed: string = uri.trim();
    if (trimmed.length === 0) {
      return 'empty';
    }
    if (this.handler === null) {
      if (this.pending.indexOf(trimmed) >= 0) {
        return 'duplicate';
      }
      this.pending.push(trimmed);
      while (this.pending.length > DEEP_LINK_MAX_PENDING) {
        this.pending.shift();
      }
      return 'queued';
    }
    try {
      this.handler(trimmed);
    } catch (e) {
      // 交付失败不入队重试：调用方（router）已经把原因报出来了。
    }
    return 'delivered';
  }

  pendingCount(): number {
    return this.pending.length;
  }

  pendingUris(): string[] {
    return this.pending.slice();
  }

  clear(): void {
    this.pending.length = 0;
  }
}

/**
 * 进程级队列。`EntryAbility` 与 `pages/Index` 是两个互不知晓的生命周期点，
 * 深链必须在它们之间交接，所以这里放一个单例而不是层层传参。
 */
export const appDeepLinkQueue: DeepLinkQueue = new DeepLinkQueue();
