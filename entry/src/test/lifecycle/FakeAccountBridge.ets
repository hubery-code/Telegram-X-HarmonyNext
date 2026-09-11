import {
  TdNativeBridgeLike,
  TdNativeBridgeMetrics,
  TdNativeEvent,
  TdNativeEventSink
} from '@tgx/td-gateway';

export interface SentRecord {
  readonly clientId: number;
  readonly utf8: string;
}

class FakeAccountBridgeMetrics implements TdNativeBridgeMetrics {
  readonly queueSize: number = 0;
  readonly overflowWaitCount: number = 0;
  readonly droppedCount: number = 0;
  readonly eventsForwarded: number = 0;
  readonly subscriptions: number = 0;
  readonly dispatcherRunning: boolean = true;
}

export class FakeAccountBridge implements TdNativeBridgeLike {
  version: string = '1.8.67-fake';
  readonly sent: SentRecord[] = [];
  private readonly sinks: Map<number, TdNativeEventSink> = new Map();
  private nextSubscriptionId: number = 1;
  private nextClientId: number = 1;

  getVersion(): string {
    return this.version;
  }

  createClient(): number {
    const id: number = this.nextClientId;
    this.nextClientId += 1;
    return id;
  }

  send(clientId: number, requestUtf8: string): void {
    const record: SentRecord = { clientId: clientId, utf8: requestUtf8 };
    this.sent.push(record);
  }

  execute(requestUtf8: string): string | null {
    return `{"@type":"ok"}`;
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
    return new FakeAccountBridgeMetrics();
  }
}
