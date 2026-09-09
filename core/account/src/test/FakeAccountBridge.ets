/**
 * 测试用 FakeAccountBridge：多 client 版 TdNativeBridgeLike。
 * 与 core/td_gateway 的 FakeBridge 不同：createClient 返回递增的全局 clientId
 * （模拟 TDLib 多账号），并可注入 createClient/send 同步失败（restoreAll 隔离测试用）。
 */

import {
  TdNativeBridgeLike,
  TdNativeBridgeMetrics,
  TdNativeEvent,
  TdNativeEventSink,
  TdWireObject
} from '@tgx/td-gateway';

export interface SentAccountRequest {
  readonly clientId: number;
  readonly utf8: string;
}

export class FakeAccountBridge implements TdNativeBridgeLike {
  version: string = '1.8.67-fake';
  failNextCreateClientFlag: boolean = false;
  failNextSendFlag: boolean = false;

  readonly sent: SentAccountRequest[] = [];
  private readonly sinks: Map<number, TdNativeEventSink> = new Map();
  private nextSubscriptionId: number = 1;
  private nextClientId: number = 1;
  private readonly sequenceByClient: Map<number, number> = new Map();

  getVersion(): string {
    return this.version;
  }

  createClient(): number {
    if (this.failNextCreateClientFlag) {
      this.failNextCreateClientFlag = false;
      throw new Error('fake createClient failure');
    }
    const id: number = this.nextClientId;
    this.nextClientId += 1;
    return id;
  }

  createdClientCount(): number {
    return this.nextClientId - 1;
  }

  send(clientId: number, requestUtf8: string): void {
    if (this.failNextSendFlag) {
      this.failNextSendFlag = false;
      throw new Error('fake bridge send failure');
    }
    const record: SentAccountRequest = { clientId: clientId, utf8: requestUtf8 };
    this.sent.push(record);
  }

  execute(requestUtf8: string): string | null {
    return `{"@type":"ok","@extra":${requestUtf8}}`;
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

  subscriptionCount(): number {
    return this.sinks.size;
  }

  lastSentWire(): TdWireObject {
    const record: SentAccountRequest = this.sent[this.sent.length - 1];
    const parsed: Object = JSON.parse(record.utf8);
    return parsed as TdWireObject;
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

  emitPayload(clientId: number, payload: TdWireObject, sequence?: string): void {
    const seq: string = sequence !== undefined ? sequence : this.nextSequence(clientId);
    const event: TdNativeEvent = {
      schemaVersion: 1,
      clientId: clientId,
      sequence: seq,
      payloadUtf8: JSON.stringify(payload),
      receivedAtMonotonicMs: 0
    };
    this.emitRaw(event);
  }

  emitRaw(event: TdNativeEvent): void {
    for (const id of Array.from(this.sinks.keys())) {
      const sink: TdNativeEventSink | undefined = this.sinks.get(id);
      if (sink !== undefined) {
        sink(event);
      }
    }
  }

  private nextSequence(clientId: number): string {
    const current: number = this.sequenceByClient.get(clientId) ?? 0;
    const next: number = current + 1;
    this.sequenceByClient.set(clientId, next);
    return String(next);
  }
}
