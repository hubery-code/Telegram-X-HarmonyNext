/**
 * core/td_gateway — TdGateway facade（CORE-002）。
 *
 * 把 TdNativeBridgeLike 事件流分流成两路（计划 §5.2/§5.4）：
 * - 带 `@extra.requestId` 的负载 → RequestRegistry（响应/TDLib error）；
 * - 其余（update 流，无 requestId）→ OrderedEventRouter（按 client 严格有序分发）。
 *
 * 分类规则即 §6.2 的语义：request Promise 只裁决「请求本身」的结果，
 * update 流独立有序到达，UI 状态以 update/state 为准。
 * 注意：TDLib 对带 @extra 的请求回包会原样带回 @extra；update 不带 @extra。
 *
 * 线程契约：handleNativeEvent 在 ArkTS 线程被调用（native TSFN 保证），
 * 内部全同步、无重入队列；事件严格按 native sequence 顺序进本方法。
 *
 * payload 解析：默认 JSON.parse + 记录形状校验，解析失败计 decodeErrorCount
 * 并走 onProtocolError（AppError internal），不中断后续事件。
 */

import { AppError, AppErrors, Clock, IdGenerator } from '@tgx/core-common';
import { OrderedEventRouter, OrderedRouterMetrics, TdRoutedEvent, TdUpdateFilter, TdUpdateListener, TdUpdateSubscription } from './OrderedEventRouter';
import { RequestRegistry, RequestRegistryMetrics, TdPendingRequest, TdRequestOptions } from './RequestRegistry';
import { TdNativeBridgeLike, TdNativeBridgeMetrics, TdNativeEvent } from './TdNativeBridgeLike';
import { TdTimeoutScheduler } from './TimeoutScheduler';
import { TdWireObject, TdWireValue, isWireObject, wireString } from './TdWire';

export type TdPayloadParser = (payloadUtf8: string) => TdWireObject | null;

export interface TdGatewayOptions {
  readonly idGenerator?: IdGenerator;
  readonly clock?: Clock;
  readonly scheduler?: TdTimeoutScheduler;
  readonly defaultTimeoutMillis?: number;
  readonly payloadParser?: TdPayloadParser;
  /** 协议错误（乱序/payload 解析失败）统一出口；缺省只计数。 */
  readonly onProtocolError?: (error: AppError, detail: string) => void;
}

export interface TdGatewayMetrics {
  readonly registry: RequestRegistryMetrics;
  readonly router: OrderedRouterMetrics;
  readonly bridge: TdNativeBridgeMetrics;
  /** payload JSON 解析失败的次数。 */
  readonly decodeErrorCount: number;
}

function defaultPayloadParser(payloadUtf8: string): TdWireObject | null {
  let parsed: Object;
  try {
    parsed = JSON.parse(payloadUtf8);
  } catch (e) {
    return null;
  }
  if (typeof parsed === 'object' && parsed !== null && !Array.isArray(parsed)) {
    return parsed as TdWireObject;
  }
  return null;
}

export class TdGateway {
  private readonly bridge: TdNativeBridgeLike;
  private readonly registry: RequestRegistry;
  private readonly router: OrderedEventRouter;
  private readonly payloadParser: TdPayloadParser;
  private readonly onProtocolError: (error: AppError, detail: string) => void;

  private subscriptionId: number = -1;
  private decodeErrorCount: number = 0;

  constructor(bridge: TdNativeBridgeLike, options?: TdGatewayOptions) {
    this.bridge = bridge;
    this.payloadParser = options?.payloadParser !== undefined ? options.payloadParser : defaultPayloadParser;
    this.onProtocolError = options?.onProtocolError !== undefined ? options.onProtocolError : (): void => {
    };
    this.registry = new RequestRegistry(bridge, {
      idGenerator: options?.idGenerator,
      clock: options?.clock,
      scheduler: options?.scheduler,
      defaultTimeoutMillis: options?.defaultTimeoutMillis
    });
    const self: TdGateway = this;
    this.router = new OrderedEventRouter((error: AppError, event: TdRoutedEvent): void => {
      self.onProtocolError(error, `client=${event.clientId} sequence=${event.sequence} type=${event.type}`);
    });
  }

  /** 订阅桥事件流并开始分流。幂等：重复调用不产生重复订阅。 */
  start(): number {
    if (this.subscriptionId >= 0) {
      return this.subscriptionId;
    }
    const self: TdGateway = this;
    this.subscriptionId = this.bridge.subscribeUpdates((event: TdNativeEvent): void => {
      self.handleNativeEvent(event);
    });
    return this.subscriptionId;
  }

  /** 退订桥事件流。幂等。 */
  stop(): void {
    if (this.subscriptionId >= 0) {
      this.bridge.unsubscribe(this.subscriptionId);
      this.subscriptionId = -1;
    }
  }

  get started(): boolean {
    return this.subscriptionId >= 0;
  }

  getVersion(): string {
    return this.bridge.getVersion();
  }

  createClient(): number {
    return this.bridge.createClient();
  }

  /** 同步 execute 直通（TDLib 全局请求，如 getTextEntities），透传桥语义。 */
  executeSync(requestUtf8: string): string | null {
    return this.bridge.execute(requestUtf8);
  }

  /** 异步请求：注入 @extra.requestId → send → 挂起直到响应/错误/超时/取消。 */
  request(clientId: number, method: string, params?: TdWireObject, options?: TdRequestOptions): TdPendingRequest {
    return this.registry.request(clientId, method, params, options);
  }

  subscribeUpdates(filter: TdUpdateFilter, listener: TdUpdateListener): TdUpdateSubscription {
    return this.router.subscribe(filter, listener);
  }

  /** 单事件分流入口（生产由 start() 的订阅回调驱动；测试可直接喂事件）。 */
  handleNativeEvent(event: TdNativeEvent): void {
    const payload: TdWireObject | null = this.payloadParser(event.payloadUtf8);
    if (payload === null) {
      this.decodeErrorCount += 1;
      this.onProtocolError(
        AppErrors.internal('td_gateway.payload_decode', 'failed to parse native event payload', `client=${event.clientId} sequence=${event.sequence}`),
        `client=${event.clientId} sequence=${event.sequence}`
      );
      return;
    }
    const extraValue: TdWireValue | undefined = payload['@extra'];
    if (extraValue !== undefined && extraValue !== null && isWireObject(extraValue)) {
      const extra: TdWireObject = extraValue as TdWireObject;
      const requestId: string = wireString(extra['requestId']);
      if (requestId.length > 0) {
        this.registry.handleResponse(event.clientId, payload);
        return;
      }
    }
    this.router.routePayload(event.clientId, event.sequence, payload);
  }

  getMetrics(): TdGatewayMetrics {
    return {
      registry: this.registry.getMetrics(),
      router: this.router.getMetrics(),
      bridge: this.bridge.getMetrics(),
      decodeErrorCount: this.decodeErrorCount
    };
  }
}

/** 判定一个 AppError 是否为 gateway 稳定取消错误（AppError 无 cancel 专用 kind）。 */
export function isCancelledRequestError(error: AppError): boolean {
  return error.kind === 'unknown' && error.origin === 'td_gateway.request_cancelled';
}
