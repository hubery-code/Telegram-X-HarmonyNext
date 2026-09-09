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
 *
 * 关闭生命周期（BRG-005，状态机 idle → active → closing → closed）：
 * - close()：幂等终态。退订桥事件流（stop()）+ RequestRegistry.close()
 *   （全部挂起请求 settle 为稳定取消错误，此后新请求立即 closed 错误）；
 * - close 后订阅回调里迟到的桥事件在入口丢弃并计 discardedEventCount，
 *   绝不进入分流（直喂 handleNativeEvent 的测试入口不受影响，仍按既有
 *   tombstone/scope 守卫语义路由与计数）；
 * - close 后 start() 返回 -1 不再订阅，createClient() 返回 -1（非法 id 哨兵），
 *   executeSync() 返回 TDLib 形 error JSON——全部返回错误，不崩溃；
 * - gateway 实例关闭即终态：快速 close → reopen 语义由桥层
 *   （TdCoreBridge.createClient 开新代）+ 新建 gateway（AccountScope 重建）承载。
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
  /** BRG-005 关闭生命周期状态。 */
  readonly lifecycleState: TdGatewayState;
  /** close 后在订阅回调入口被丢弃的迟到桥事件数。 */
  readonly discardedEventCount: number;
}

/** gateway 关闭生命周期状态。idle = 未订阅（含 stop 后）；active = 订阅中；closed = 终态。 */
export type TdGatewayState = 'idle' | 'active' | 'closing' | 'closed';

/** closed 后 executeSync 的返回：TDLib 形 error 对象（与 native 对非法请求的既有做法一致）。 */
const GATEWAY_CLOSED_EXECUTE_RESPONSE: string =
  '{"@type":"error","code":400,"message":"td gateway is closed"}';

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
  private state: TdGatewayState = 'idle';
  private discardedEventCountValue: number = 0;

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

  /**
   * 订阅桥事件流并开始分流。幂等：重复调用不产生重复订阅。
   * closed 后返回 -1（不再订阅，不抛异常）。
   */
  start(): number {
    if (this.state === 'closing' || this.state === 'closed') {
      return -1;
    }
    if (this.subscriptionId >= 0) {
      return this.subscriptionId;
    }
    const self: TdGateway = this;
    this.subscriptionId = this.bridge.subscribeUpdates((event: TdNativeEvent): void => {
      // 迟到回调守卫（BRG-005）：close 期间/之后到达本订阅的事件丢弃并计数，绝不进入分流。
      if (self.state === 'closing' || self.state === 'closed') {
        self.discardedEventCountValue += 1;
        return;
      }
      self.handleNativeEvent(event);
    });
    this.state = 'active';
    return this.subscriptionId;
  }

  /** 退订桥事件流（active → idle，可经 start() 恢复）。幂等。closed 为终态不受影响。 */
  stop(): void {
    if (this.subscriptionId >= 0) {
      this.bridge.unsubscribe(this.subscriptionId);
      this.subscriptionId = -1;
    }
    if (this.state === 'active') {
      this.state = 'idle';
    }
  }

  /**
   * 关闭（BRG-005，终态）：退订桥事件流 + 取消全部挂起请求（稳定取消错误），
   * 此后新请求立即 closed 错误。幂等：重复调用为 no-op。
   */
  close(): void {
    if (this.state === 'closing' || this.state === 'closed') {
      return;
    }
    this.state = 'closing';
    this.stop();
    this.registry.close();
    this.state = 'closed';
  }

  get lifecycleState(): TdGatewayState {
    return this.state;
  }

  get discardedEventCount(): number {
    return this.discardedEventCountValue;
  }

  get started(): boolean {
    return this.subscriptionId >= 0;
  }

  getVersion(): string {
    return this.bridge.getVersion();
  }

  /** closed 后返回 -1（非法 clientId 哨兵，isValidClientId 拒绝），不抛异常。 */
  createClient(): number {
    if (this.state === 'closing' || this.state === 'closed') {
      return -1;
    }
    return this.bridge.createClient();
  }

  /** 同步 execute 直通（TDLib 全局请求，如 getTextEntities），透传桥语义。closed 后返回 TDLib 形 error JSON。 */
  executeSync(requestUtf8: string): string | null {
    if (this.state === 'closing' || this.state === 'closed') {
      return GATEWAY_CLOSED_EXECUTE_RESPONSE;
    }
    return this.bridge.execute(requestUtf8);
  }

  /** 异步请求：注入 @extra.requestId → send → 挂起直到响应/错误/超时/取消。closed 后立即 closed 错误，绝不发送。 */
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
      decodeErrorCount: this.decodeErrorCount,
      lifecycleState: this.state,
      discardedEventCount: this.discardedEventCountValue
    };
  }
}

/** 判定一个 AppError 是否为 gateway 稳定取消错误（AppError 无 cancel 专用 kind）。 */
export function isCancelledRequestError(error: AppError): boolean {
  return error.kind === 'unknown' && error.origin === 'td_gateway.request_cancelled';
}
