/**
 * core/td_gateway — RequestRegistry（CORE-002）。
 *
 * 计划 §5.2：每个 request 注入唯一 `@extra.requestId`，RequestRegistry 负责
 * Promise 关联、超时、取消和迟到响应：
 * - request() 构造 wire 请求（`@type` + 参数 + `@extra.requestId`），经桥 send 后挂起；
 * - 收到带匹配 requestId 的响应 → resolve 为 Ok(wire 记录)；
 *   收到 TDLib error 对象（`@type:"error", code, message`）→ 经
 *   AppErrors.fromTdlibError 映射为稳定 AppError 后 resolve 为 Err，
 *   原始 error.message 只允许进 cause（§7：禁止直接当用户文案）；
 * - 超时（默认 10s，可配）→ Err(network/timeout, retryable=true)；
 * - 取消（cancel() 句柄或 AbortSignalLike）→ Err 稳定取消错误；
 * - 迟到响应（ settled 之后才到）绝不二次 resolve，计入 lateResponseCount 后丢弃。
 *
 * 契约要点（§7）：
 * - 永不 reject、永不抛异常：一切失败都经 Promise<Result<…, AppError>> 表达；
 * - requestId 由可注入 IdGenerator 生成（生产 RandomIdGenerator，测试 Sequential）；
 * - 超时判定依赖注入的 Clock.monotonicMillis（生产 SystemClock，测试 ManualClock）；
 * - 已 settle 的 requestId 保留在 tombstone 集合用于迟到判定；
 *   tombstone 的修剪策略（按 client 生命周期）留给 CORE-003 AccountScope。
 *
 * 取消错误说明：AppError 七类（core/common CORE-001）无 cancel 专用 kind，
 * 取消映射为 kind='unknown' + 稳定 origin='td_gateway.request_cancelled'，
 * 用 TdGatewayErrors.isCancelledRequest() 判定（见 TdGateway.ets）。
 */

import { AppError, AppErrors, Clock, IdGenerator, RandomIdGenerator, Result, SystemClock, err, ok } from '@tgx/core-common';
import { TdNativeBridgeLike } from './TdNativeBridgeLike';
import { RealTimeoutScheduler, TdTimeoutScheduler } from './TimeoutScheduler';
import { TdWireObject, TdWireValue, copyWireObject, isWireObject, isValidClientId, wireNumber, wireString } from './TdWire';

export const GATEWAY_ORIGIN: string = 'td_gateway';

/** 最小 AbortSignal 形态（ArkTS 无 DOM AbortSignal；只取 aborted 语义）。 */
export interface TdAbortSignal {
  readonly aborted: boolean;
}

export interface RequestRegistryOptions {
  readonly idGenerator?: IdGenerator;
  readonly clock?: Clock;
  readonly scheduler?: TdTimeoutScheduler;
  /** 默认超时，毫秒。计划 §5.2 约定 10s。 */
  readonly defaultTimeoutMillis?: number;
}

export interface TdRequestOptions {
  /** 覆盖 defaultTimeoutMillis（本请求专用）。 */
  readonly timeoutMillis?: number;
  /** 注册时与响应到达时检查；已 aborted 等价于立即取消。 */
  readonly signal?: TdAbortSignal;
}

export interface RequestRegistryMetrics {
  /** 当前挂起中的请求数。 */
  readonly pendingCount: number;
  /** 已正常 resolve（Ok）的请求数。 */
  readonly resolvedCount: number;
  /** 已超时 settle 的请求数。 */
  readonly timedOutCount: number;
  /** 已取消 settle 的请求数。 */
  readonly cancelledCount: number;
  /** 迟到响应数（settled 之后才到达，已安全丢弃）。 */
  readonly lateResponseCount: number;
  /** 带 requestId 但从未注册过的响应数（实现侧 bug / 对端串话）。 */
  readonly unmatchedResponseCount: number;
  /** clientId 与注册时不一致的响应数（严重：跨 client 串话）。 */
  readonly crossClientResponseCount: number;
  /** 桥 send 同步抛异常的次数（已映射为 platform 错误）。 */
  readonly sendFailureCount: number;
}

type SettleReason = 'resolved' | 'timed_out' | 'cancelled';

interface PendingEntry {
  readonly requestId: string;
  readonly clientId: number;
  readonly deadlineMillis: number;
  timeoutHandle: number;
  resolve: (result: Result<TdWireObject, AppError>) => void;
  settled: boolean;
}

/**
 * 挂起的请求句柄。promise 为最终裁决（Result，绝不 reject）；
 * cancel() 幂等，重复调用返回 false。
 */
export class TdPendingRequest {
  readonly requestId: string;
  readonly clientId: number;
  readonly promise: Promise<Result<TdWireObject, AppError>>;
  private readonly entry: PendingEntry;
  private readonly registry: RequestRegistry;

  constructor(registry: RequestRegistry, entry: PendingEntry, promise: Promise<Result<TdWireObject, AppError>>) {
    this.registry = registry;
    this.entry = entry;
    this.requestId = entry.requestId;
    this.clientId = entry.clientId;
    this.promise = promise;
  }

  get settled(): boolean {
    return this.entry.settled;
  }

  cancel(): boolean {
    return this.registry.cancelEntry(this.entry);
  }
}

export class RequestRegistry {
  private readonly bridge: TdNativeBridgeLike;
  private readonly idGenerator: IdGenerator;
  private readonly clock: Clock;
  private readonly scheduler: TdTimeoutScheduler;
  private readonly defaultTimeoutMillis: number;

  private readonly pending: Map<string, PendingEntry> = new Map();
  private readonly tombstones: Map<string, SettleReason> = new Map();

  private resolvedCount: number = 0;
  private timedOutCount: number = 0;
  private cancelledCount: number = 0;
  private lateResponseCount: number = 0;
  private unmatchedResponseCount: number = 0;
  private crossClientResponseCount: number = 0;
  private sendFailureCount: number = 0;

  constructor(bridge: TdNativeBridgeLike, options?: RequestRegistryOptions) {
    this.bridge = bridge;
    this.idGenerator = options?.idGenerator !== undefined ? options.idGenerator : new RandomIdGenerator();
    this.clock = options?.clock !== undefined ? options.clock : new SystemClock();
    this.scheduler = options?.scheduler !== undefined ? options.scheduler : new RealTimeoutScheduler();
    this.defaultTimeoutMillis = options?.defaultTimeoutMillis !== undefined ? options.defaultTimeoutMillis : 10000;
  }

  /**
   * 发送一个 TDLib 请求并挂起，直到响应/错误/超时/取消。
   * 入参为 method 名 + 参数记录（不含 @extra，registry 负责注入）。
   */
  request(clientId: number, method: string, params?: TdWireObject, options?: TdRequestOptions): TdPendingRequest {
    let resolveRef: (result: Result<TdWireObject, AppError>) => void = (): void => {
    };
    const promise: Promise<Result<TdWireObject, AppError>> = new Promise<Result<TdWireObject, AppError>>((resolve: (result: Result<TdWireObject, AppError>) => void): void => {
      resolveRef = resolve;
    });

    // 非法 clientId 是调用方编程错误：不抛异常，按契约 settle 为 parameter 错误。
    if (!isValidClientId(clientId)) {
      const invalidEntry: PendingEntry = {
        requestId: '',
        clientId: clientId,
        deadlineMillis: 0,
        timeoutHandle: -1,
        resolve: resolveRef,
        settled: true
      };
      resolveRef(err<TdWireObject, AppError>(AppErrors.parameter('invalid', 'clientId', 'clientId must be a non-negative int32')));
      return new TdPendingRequest(this, invalidEntry, promise);
    }

    const requestId: string = this.idGenerator.nextRequestId();
    const wire: TdWireObject = copyWireObject(params !== undefined ? params : {});
    wire['@type'] = method;
    const extra: TdWireObject = {};
    const existingExtra: TdWireValue | undefined = wire['@extra'];
    if (existingExtra !== undefined && existingExtra !== null && isWireObject(existingExtra)) {
      const existingObj: TdWireObject = existingExtra as TdWireObject;
      for (const key of Object.keys(existingObj)) {
        extra[key] = existingObj[key];
      }
    }
    extra['requestId'] = requestId;
    wire['@extra'] = extra;

    const timeoutMillis: number = options?.timeoutMillis !== undefined ? options.timeoutMillis : this.defaultTimeoutMillis;
    const entry: PendingEntry = {
      requestId: requestId,
      clientId: clientId,
      deadlineMillis: this.clock.monotonicMillis() + Math.max(0, timeoutMillis),
      timeoutHandle: -1,
      resolve: resolveRef,
      settled: false
    };
    this.pending.set(requestId, entry);

    // send 失败（桥实现抛异常）映射为稳定 platform 错误，不向外抛。
    try {
      this.bridge.send(clientId, JSON.stringify(wire));
    } catch (e) {
      this.pending.delete(requestId);
      entry.settled = true;
      this.tombstones.set(requestId, 'cancelled');
      this.sendFailureCount += 1;
      const message: string = e instanceof Error ? e.message : String(e);
      entry.resolve(err<TdWireObject, AppError>(AppErrors.platform(-1, 'td gateway send failed', true, undefined, message)));
      return new TdPendingRequest(this, entry, promise);
    }

    if (options?.signal !== undefined && options.signal.aborted) {
      this.cancelEntry(entry);
      return new TdPendingRequest(this, entry, promise);
    }

    entry.timeoutHandle = this.scheduler.setTimeout((): void => {
      this.expireIfDue(entry.requestId);
    }, Math.max(0, entry.deadlineMillis - this.clock.monotonicMillis()));

    return new TdPendingRequest(this, entry, promise);
  }

  /** 响应/错误到达入口（由 TdGateway 从事件流中分类后调用，也可直接用于测试）。 */
  handleResponse(clientId: number, response: TdWireObject): void {
    const extra: TdWireObject | null = isWireObject(response['@extra']) ? response['@extra'] as TdWireObject : null;
    const requestId: string = extra !== null ? wireString(extra['requestId']) : '';
    if (requestId.length === 0) {
      this.unmatchedResponseCount += 1;
      return;
    }
    const entry: PendingEntry | undefined = this.pending.get(requestId);
    if (entry === undefined) {
      if (this.tombstones.has(requestId)) {
        this.lateResponseCount += 1;
      } else {
        this.unmatchedResponseCount += 1;
      }
      return;
    }
    if (entry.clientId !== clientId) {
      this.crossClientResponseCount += 1;
      return;
    }
    if (entry.settled) {
      this.lateResponseCount += 1;
      return;
    }
    this.settleResolved(entry, response);
  }

  cancelEntry(entry: PendingEntry): boolean {
    if (entry.settled) {
      return false;
    }
    if (!this.pending.has(entry.requestId)) {
      return false;
    }
    entry.settled = true;
    this.pending.delete(entry.requestId);
    this.tombstones.set(entry.requestId, 'cancelled');
    if (entry.timeoutHandle >= 0) {
      this.scheduler.clearTimeout(entry.timeoutHandle);
      entry.timeoutHandle = -1;
    }
    this.cancelledCount += 1;
    entry.resolve(err<TdWireObject, AppError>(TdGatewayCancelledError(entry.requestId)));
    return true;
  }

  getMetrics(): RequestRegistryMetrics {
    return {
      pendingCount: this.pending.size,
      resolvedCount: this.resolvedCount,
      timedOutCount: this.timedOutCount,
      cancelledCount: this.cancelledCount,
      lateResponseCount: this.lateResponseCount,
      unmatchedResponseCount: this.unmatchedResponseCount,
      crossClientResponseCount: this.crossClientResponseCount,
      sendFailureCount: this.sendFailureCount
    };
  }

  private expireIfDue(requestId: string): void {
    const entry: PendingEntry | undefined = this.pending.get(requestId);
    if (entry === undefined || entry.settled) {
      return;
    }
    const nowMillis: number = this.clock.monotonicMillis();
    if (nowMillis < entry.deadlineMillis) {
      // 时钟源与调度器不同步时按剩余时间重排，保证超时判定以单调时钟为准。
      entry.timeoutHandle = this.scheduler.setTimeout((): void => {
        this.expireIfDue(entry.requestId);
      }, entry.deadlineMillis - nowMillis);
      return;
    }
    this.settleTimedOut(entry);
  }

  private settleTimedOut(entry: PendingEntry): void {
    if (entry.settled) {
      return;
    }
    entry.settled = true;
    this.pending.delete(entry.requestId);
    this.tombstones.set(entry.requestId, 'timed_out');
    entry.timeoutHandle = -1;
    this.timedOutCount += 1;
    entry.resolve(err<TdWireObject, AppError>(AppErrors.network(
      'timeout',
      'TDLib request timed out',
      true,
      undefined,
      `requestId=${entry.requestId}`
    )));
  }

  private settleResolved(entry: PendingEntry, response: TdWireObject): void {
    entry.settled = true;
    this.pending.delete(entry.requestId);
    this.tombstones.set(entry.requestId, 'resolved');
    if (entry.timeoutHandle >= 0) {
      this.scheduler.clearTimeout(entry.timeoutHandle);
      entry.timeoutHandle = -1;
    }
    const type: string = wireString(response['@type']);
    if (type === 'error') {
      const code: number = wireNumber(response['code']);
      const message: string = wireString(response['message']);
      // TDLib 原始 message 只进 cause；对外是稳定错误码（§7）。
      entry.resolve(err<TdWireObject, AppError>(AppErrors.fromTdlibError(code, message)));
      return;
    }
    this.resolvedCount += 1;
    entry.resolve(ok<TdWireObject, AppError>(response));
  }
}

/** 稳定取消错误：kind='unknown' + 固定 origin（AppError 七类无 cancel 专用 kind，见文件头说明）。 */
export function TdGatewayCancelledError(requestId: string): AppError {
  return AppErrors.unknown(`${GATEWAY_ORIGIN}.request_cancelled`, 'request cancelled by caller', `requestId=${requestId}`);
}
