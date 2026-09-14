/**
 * Fake TdCoreNativeModule for unit tests (no .so required).
 * Mimics the native module's behavior:
 * - createClient returns incrementing ids
 * - subscribeUpdates registers sinks and returns incrementing subscription ids
 * - reentrancy safety: snapshot dispatch and deferred unsubscribe cleanup (P1-BRG-001)
 * - session generation: increment generation and drop stale events (P1-BRG-002)
 * - getMetrics returns a well-formed metrics object
 */

import {
  TdCoreNativeModule,
  TdEventSinkRaw
} from '../main/ets/TdCoreBridge';
import {
  TdNativeBridgeMetrics
} from '@tgx/td-gateway';

export interface FakeRawEvent {
  id?: number;
  schemaVersion?: number;
  clientId?: number;
  sequence?: string;
  payloadUtf8: string;
  receivedAtMonotonicMs?: number;
  sessionGeneration?: number;
}

interface SinkEntry {
  subId: number;
  sink: TdEventSinkRaw;
}

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
  private readonly pendingUnsubscribes: Set<number> = new Set();
  private nextSubscriptionId: number = 1;
  private dispatchDepth: number = 0;
  private sessionGeneration: number = 1;
  private staleDroppedCount: number = 0;
  private eventsForwarded: number = 0;

  subscribeUpdates(sink: TdEventSinkRaw): number {
    const id: number = this.nextSubscriptionId;
    this.nextSubscriptionId += 1;
    this.sinks.set(id, sink);
    return id;
  }

  unsubscribe(subscriptionId: number): void {
    if (this.dispatchDepth > 0) {
      if (this.sinks.has(subscriptionId)) {
        this.pendingUnsubscribes.add(subscriptionId);
      }
    } else {
      this.sinks.delete(subscriptionId);
    }
  }

  resetSession(): void {
    this.sessionGeneration += 1;
  }

  getSessionGeneration(): number {
    return this.sessionGeneration;
  }

  getStaleDroppedCount(): number {
    return this.staleDroppedCount;
  }

  getMetrics(): TdNativeBridgeMetrics {
    const activeSubs: number = Math.max(0, this.sinks.size - this.pendingUnsubscribes.size);
    return {
      queueSize: 0,
      overflowWaitCount: 0,
      droppedCount: 0,
      eventsForwarded: this.eventsForwarded,
      subscriptions: activeSubs,
      dispatcherRunning: activeSubs > 0
    };
  }

  getSink(id: number): TdEventSinkRaw | undefined {
    return this.sinks.get(id);
  }

  deliverBatch(events: Array<FakeRawEvent>): void {
    this.dispatchDepth += 1;
    try {
      for (const evt of events) {
        const gen: number = evt.sessionGeneration !== undefined ? evt.sessionGeneration : this.sessionGeneration;
        if (gen !== this.sessionGeneration) {
          this.staleDroppedCount += 1;
          continue;
        }
        this.eventsForwarded += 1;

        // Snapshot current sinks
        const currentSinks: Array<SinkEntry> = [];
        for (const subId of Array.from(this.sinks.keys())) {
          if (!this.pendingUnsubscribes.has(subId)) {
            if (evt.id === undefined || evt.id === subId) {
              const sink: TdEventSinkRaw | undefined = this.sinks.get(subId);
              if (sink !== undefined) {
                currentSinks.push({ subId: subId, sink: sink });
              }
            }
          }
        }

        for (const item of currentSinks) {
          if (this.pendingUnsubscribes.has(item.subId)) {
            continue;
          }
          try {
            item.sink(
              evt.schemaVersion !== undefined ? evt.schemaVersion : 1,
              evt.clientId !== undefined ? evt.clientId : 0,
              evt.sequence !== undefined ? evt.sequence : '0',
              evt.payloadUtf8,
              evt.receivedAtMonotonicMs !== undefined ? evt.receivedAtMonotonicMs : Date.now()
            );
          } catch (e) {
            // Guard against JS callback exception
          }
        }
      }
    } finally {
      this.dispatchDepth -= 1;
      if (this.dispatchDepth === 0) {
        for (const id of Array.from(this.pendingUnsubscribes)) {
          this.sinks.delete(id);
        }
        this.pendingUnsubscribes.clear();
      }
    }
  }

  deliverEvent(
    id: number,
    schemaVersion: number,
    clientId: number,
    sequence: string,
    payloadUtf8: string,
    receivedAtMonotonicMs: number,
    sessionGeneration?: number
  ): void {
    this.deliverBatch([{
      id: id,
      schemaVersion: schemaVersion,
      clientId: clientId,
      sequence: sequence,
      payloadUtf8: payloadUtf8,
      receivedAtMonotonicMs: receivedAtMonotonicMs,
      sessionGeneration: sessionGeneration
    }]);
  }
}
