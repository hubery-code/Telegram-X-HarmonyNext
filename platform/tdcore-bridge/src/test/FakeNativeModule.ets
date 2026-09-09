/**
 * Fake TdCoreNativeModule for unit tests (no .so required).
 * Mimics the native module's behavior: createClient returns incrementing ids,
 * subscribeUpdates registers sinks and returns incrementing subscription ids,
 * getMetrics returns a well-formed metrics object.
 */

import {
  TdCoreNativeModule,
  TdEventSinkRaw
} from '../main/ets/TdCoreBridge';
import {
  TdNativeBridgeMetrics
} from '@tgx/td-gateway';

export class FakeNativeModule implements TdCoreNativeModule {
  getVersion(): string {
    return '1.8.67-fake';
  }

  execute(requestUtf8: string): string | null {
    return `{"@type":"ok","@extra":${requestUtf8}}`;
  }

  private nextClientId: number = 1;
  createClient(): number {
    const id: number = this.nextClientId;
    this.nextClientId += 1;
    return id;
  }

  send(clientId: number, requestUtf8: string): void {
    // no-op for test
  }

  private readonly sinks: Map<number, TdEventSinkRaw> = new Map();
  private nextSubscriptionId: number = 1;
  subscribeUpdates(sink: TdEventSinkRaw): number {
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

  getSink(id: number): TdEventSinkRaw | undefined {
    return this.sinks.get(id);
  }

  deliverEvent(
    id: number,
    schemaVersion: number,
    clientId: number,
    sequence: string,
    payloadUtf8: string,
    receivedAtMonotonicMs: number
  ): void {
    const sink: TdEventSinkRaw | undefined = this.sinks.get(id);
    if (sink !== undefined) {
      sink(schemaVersion, clientId, sequence, payloadUtf8, receivedAtMonotonicMs);
    }
  }
}
