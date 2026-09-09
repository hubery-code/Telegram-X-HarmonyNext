/**
 * 测试用手写 FakeBridge：实现 TdNativeBridgeLike，模拟异步响应、
 * TDLib error、乱序/重复 sequence、迟到响应与 send 失败。
 *
 * 事件经 sink 同步注入（promise 结算仍走微任务，测试用 await 观察真实异步语义）；
 * 每个 client 的 sequence 默认单调自增，可用 emitRaw 精确构造乱序/重复。
 */

import { TdNativeBridgeLike, TdNativeBridgeMetrics, TdNativeEvent, TdNativeEventSink } from '../main/ets/TdNativeBridgeLike';
import { TdWireObject } from '../main/ets/TdWire';

export interface SentRequest {
  readonly clientId: number;
  readonly utf8: string;
}

export class FakeBridge implements TdNativeBridgeLike {
  version: string = '1.8.67-fake';
  failNextSendFlag: boolean = false;
  failSendForeverFlag: boolean = false;

  /**
   * 直接负载监听（不经事件封套）：RequestRegistry 单测用它把响应直接
   * 喂给被测 registry；TdGateway 集成测试走 start() 的 sink 路径，不设置。
   */
  payloadListener: ((clientId: number, payload: TdWireObject) => void) | null = null;

  readonly sent: SentRequest[] = [];
  private readonly sinks: Map<number, TdNativeEventSink> = new Map();
  private nextSubscriptionId: number = 1;
  private readonly sequenceByClient: Map<number, number> = new Map();

  getVersion(): string {
    return this.version;
  }

  createClient(): number {
    return 1;
  }

  send(clientId: number, requestUtf8: string): void {
    if (this.failNextSendFlag || this.failSendForeverFlag) {
      this.failNextSendFlag = false;
      throw new Error('fake bridge send failure');
    }
    this.sent.push({ clientId: clientId, utf8: requestUtf8 });
  }

  execute(requestUtf8: string): string | null {
    return `{"@type":"textEntities","@extra":${requestUtf8}}`;
  }

  subscribeUpdates(sink: TdNativeEventSink): number {
    const id: number = this.nextSubscriptionId;
    this.nextSubscriptionId += 1;
    this.sinks.set(id, sink);
    return id;
  }

  unsubscribe(subscriptionId: number): void {
    this.sinks.delete(subscriptionId);
  }

  getMetrics(): TdNativeBridgeMetrics {
    return {
      queueSize: 0,
      overflowWaitCount: 0,
      droppedCount: 0,
      eventsForwarded: 0,
      subscriptions: this.sinks.size,
      dispatcherRunning: true
    };
  }

  // ---- 测试驱动辅助 ----

  lastSent(): TdWireObject {
    const record: SentRequest = this.sent[this.sent.length - 1];
    return JSON.parse(record.utf8) as TdWireObject;
  }

  sentAt(index: number): TdWireObject {
    const record: SentRequest = this.sent[index];
    return JSON.parse(record.utf8) as TdWireObject;
  }

  /** 以普通响应（带 @extra.requestId）回应某个请求。 */
  deliverResponse(clientId: number, requestId: string, fields: TdWireObject): void {
    const payload: TdWireObject = {};
    for (const key of Object.keys(fields)) {
      payload[key] = fields[key];
    }
    const extra: TdWireObject = {};
    extra['requestId'] = requestId;
    payload['@extra'] = extra;
    this.emitPayload(clientId, payload);
  }

  /** 以 TDLib error 对象（带 @extra.requestId）回应某个请求。 */
  deliverError(clientId: number, requestId: string, code: number, message: string): void {
    const payload: TdWireObject = {};
    payload['@type'] = 'error';
    payload['code'] = code;
    payload['message'] = message;
    const extra: TdWireObject = {};
    extra['requestId'] = requestId;
    payload['@extra'] = extra;
    this.emitPayload(clientId, payload);
  }

  /** 投递一条 update（无 @extra）。sequence 缺省时该 client 单调自增。 */
  deliverUpdate(clientId: number, type: string, fields: TdWireObject, sequence?: string): void {
    const payload: TdWireObject = {};
    for (const key of Object.keys(fields)) {
      payload[key] = fields[key];
    }
    payload['@type'] = type;
    this.emitPayload(clientId, payload, sequence);
  }

  /** 精确构造原生事件（乱序/重复 sequence、非法 JSON、迟到响应）。 */
  emitRaw(event: TdNativeEvent): void {
    for (const id of Array.from(this.sinks.keys())) {
      const sink: TdNativeEventSink | undefined = this.sinks.get(id);
      if (sink !== undefined) {
        sink(event);
      }
    }
  }

  emitPayload(clientId: number, payload: TdWireObject, sequence?: string): void {
    if (this.payloadListener !== null) {
      this.payloadListener(clientId, payload);
    }
    let seq: string = sequence !== undefined ? sequence : this.nextSequence(clientId);
    const event: TdNativeEvent = {
      schemaVersion: 1,
      clientId: clientId,
      sequence: seq,
      payloadUtf8: JSON.stringify(payload),
      receivedAtMonotonicMs: 0
    };
    this.emitRaw(event);
  }

  private nextSequence(clientId: number): string {
    const current: number = this.sequenceByClient.get(clientId) ?? 0;
    const next: number = current + 1;
    this.sequenceByClient.set(clientId, next);
    return String(next);
  }
}
