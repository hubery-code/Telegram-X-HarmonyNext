/**
 * core/td_gateway — OrderedEventRouter（CORE-002）。
 *
 * 计划 §5.4「事件顺序、并发与背压」的 ArkTS 侧执行点：
 * - native 层对每个 client 的 sequence 单调递增，事件经 TSFN 已按序到达；
 *   router 校验单调性（不盲信）：sequence 必须严格大于该 client 上一条，
 *   发现乱序走 onProtocolError 上报 AppError(internal)——不允许静默吞掉；
 * - 重复 sequence（== 上一条）视为重复投递：丢弃并计数（幂等，不重复分发）；
 * - 分发本身按到达顺序同步进行（单 ArkTS 线程），天然严格有序；
 * - 订阅按 @type / clientId 过滤；未匹配任何过滤条件的监听不接收事件。
 *
 * 64 位约定：sequence 为十进制 string，比较走 compareDecimalString，
 * 不经过 JS number/bigint（§5.2）。
 */

import { AppError, AppErrors } from '@tgx/core-common';
import { TdWireObject, compareDecimalString, wireString } from './TdWire';

/** 路由后的事件（payload 保持 wire 记录，decode 成 DTO 是消费方职责）。 */
export interface TdRoutedEvent {
  readonly clientId: number;
  readonly sequence: string;
  readonly type: string;
  readonly payload: TdWireObject;
}

export interface TdUpdateFilter {
  /** 只接收该 client 的事件；缺省 = 全部 client。 */
  readonly clientId?: number;
  /** 只接收这些 @type；缺省/空数组 = 全部类型。 */
  readonly types?: string[];
}

export type TdUpdateListener = (event: TdRoutedEvent) => void;

export interface OrderedRouterMetrics {
  /** 实际分发到监听的事件总数。 */
  readonly deliveredCount: number;
  /** 重复 sequence 被丢弃的事件数。 */
  readonly duplicateCount: number;
  /** 乱序（sequence 回退）被丢弃并上报的事件数。 */
  readonly outOfOrderCount: number;
}

/** 订阅句柄。unsubscribe 幂等。 */
export class TdUpdateSubscription {
  private readonly router: OrderedEventRouter;
  private readonly filter: TdUpdateFilter;
  private readonly listener: TdUpdateListener;
  private active: boolean = true;

  constructor(router: OrderedEventRouter, filter: TdUpdateFilter, listener: TdUpdateListener) {
    this.router = router;
    this.filter = filter;
    this.listener = listener;
  }

  get isActive(): boolean {
    return this.active;
  }

  deliver(event: TdRoutedEvent): boolean {
    if (this.active && this.matches(this.filter, event)) {
      this.listener(event);
      return true;
    }
    return false;
  }

  unsubscribe(): void {
    if (!this.active) {
      return;
    }
    this.active = false;
    this.router.removeSubscriber(this);
  }

  private matches(filter: TdUpdateFilter, event: TdRoutedEvent): boolean {
    if (filter.clientId !== undefined && filter.clientId !== event.clientId) {
      return false;
    }
    if (filter.types !== undefined && filter.types.length > 0) {
      return filter.types.indexOf(event.type) >= 0;
    }
    return true;
  }
}

export class OrderedEventRouter {
  private readonly onProtocolError: (error: AppError, event: TdRoutedEvent) => void;
  private readonly subscribers: TdUpdateSubscription[] = [];
  private readonly lastSequenceByClient: Map<number, string> = new Map();

  private deliveredCount: number = 0;
  private duplicateCount: number = 0;
  private outOfOrderCount: number = 0;

  constructor(onProtocolError?: (error: AppError, event: TdRoutedEvent) => void) {
    this.onProtocolError = onProtocolError !== undefined ? onProtocolError : (): void => {
    };
  }

  subscribe(filter: TdUpdateFilter, listener: TdUpdateListener): TdUpdateSubscription {
    const subscription: TdUpdateSubscription = new TdUpdateSubscription(this, filter, listener);
    this.subscribers.push(subscription);
    return subscription;
  }

  /** 单事件入口。返回是否被正常分发（false = 重复/乱序被丢弃）。 */
  route(event: TdRoutedEvent): boolean {
    const last: string | undefined = this.lastSequenceByClient.get(event.clientId);
    if (last !== undefined) {
      const cmp: number = compareDecimalString(event.sequence, last);
      if (cmp === 0) {
        this.duplicateCount += 1;
        return false;
      }
      if (cmp < 0) {
        this.outOfOrderCount += 1;
        this.onProtocolError(
          AppErrors.internal(
            'td_gateway.sequence_monotonic',
            `out-of-order event: client=${event.clientId} sequence=${event.sequence} last=${last}`,
            `type=${event.type}`
          ),
          event
        );
        return false;
      }
    }
    this.lastSequenceByClient.set(event.clientId, event.sequence);
    for (const subscriber of this.subscribers) {
      if (subscriber.deliver(event)) {
        this.deliveredCount += 1;
      }
    }
    return true;
  }

  /** 从 wire 记录路由（便捷入口，取 @type 作为事件类型）。 */
  routePayload(clientId: number, sequence: string, payload: TdWireObject): boolean {
    const event: TdRoutedEvent = {
      clientId: clientId,
      sequence: sequence,
      type: wireString(payload['@type']),
      payload: payload
    };
    return this.route(event);
  }

  /** client 重建/换号时重置该 client 的单调游标（幂等连接的 CORE-003 扩展点）。 */
  resetClient(clientId: number): void {
    this.lastSequenceByClient.delete(clientId);
  }

  getMetrics(): OrderedRouterMetrics {
    return {
      deliveredCount: this.deliveredCount,
      duplicateCount: this.duplicateCount,
      outOfOrderCount: this.outOfOrderCount
    };
  }

  removeSubscriber(subscription: TdUpdateSubscription): void {
    const index: number = this.subscribers.indexOf(subscription);
    if (index >= 0) {
      this.subscribers.splice(index, 1);
    }
  }
}
