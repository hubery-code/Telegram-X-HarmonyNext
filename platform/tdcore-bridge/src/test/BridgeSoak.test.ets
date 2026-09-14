/**
 * SPIKE-002: ArkTS TdCoreBridge High-Volume Update Soak & Stress Suite.
 *
 * Validates:
 * 1. 10,000+ continuous burst events with strict monotonicity & zero loss.
 * 2. Reentrancy under load (dynamic subscribe / unsubscribe inside callbacks).
 * 3. Session generation transitions (stale event filtering across generations).
 * 4. 64-bit sequence numbers exceeding IEEE-754 precision (> 2^53).
 * 5. Rapid close & reopen lifecycle stress loops.
 */

import { describe, it, expect } from '@ohos/hypium';
import { TdCoreBridge } from '../main/ets/TdCoreBridge';
import {
  TdNativeEvent,
  TdNativeEventSink,
  TdNativeBridgeMetrics
} from '@tgx/td-gateway';
import { FakeNativeModule, FakeRawEvent } from './FakeNativeModule';

export default function bridgeSoakTest() {
  describe('BridgeSoakTest', () => {

    it('highVolumeBurst_10k_events_strictMonotonicityAndZeroLoss', 0, () => {
      const fake: FakeNativeModule = new FakeNativeModule();
      const bridge: TdCoreBridge = new TdCoreBridge(fake);
      bridge.createClient();

      let receivedCount: number = 0;
      let lastSeq: number = 0;
      let outOfOrderCount: number = 0;
      let duplicateCount: number = 0;

      const sink: TdNativeEventSink = (evt: TdNativeEvent): void => {
        receivedCount += 1;
        const currentSeq: number = parseInt(evt.sequence, 10);
        if (lastSeq !== 0) {
          if (currentSeq <= lastSeq) {
            if (currentSeq === lastSeq) {
              duplicateCount += 1;
            } else {
              outOfOrderCount += 1;
            }
          }
        }
        lastSeq = currentSeq;
      };

      bridge.subscribeUpdates(sink);

      const totalEvents: number = 10000;
      const batchSize: number = 500;
      let seqCounter: number = 1;

      for (let b = 0; b < totalEvents / batchSize; b++) {
        const batch: Array<FakeRawEvent> = [];
        for (let i = 0; i < batchSize; i++) {
          batch.push({
            schemaVersion: 1,
            clientId: 1,
            sequence: seqCounter.toString(),
            payloadUtf8: '{"@type":"updateOption","name":"version"}',
            receivedAtMonotonicMs: 1700000000000 + seqCounter,
            sessionGeneration: 1
          });
          seqCounter += 1;
        }
        fake.deliverBatch(batch);
      }

      expect(receivedCount).assertEqual(totalEvents);
      expect(outOfOrderCount).assertEqual(0);
      expect(duplicateCount).assertEqual(0);
      const metrics: TdNativeBridgeMetrics = bridge.getMetrics();
      expect(metrics.eventsForwarded).assertEqual(totalEvents);
      expect(metrics.droppedCount).assertEqual(0);
    });

    it('rapidReentrancy_subscribeUnsubscribe_underContinuousStream', 0, () => {
      const fake: FakeNativeModule = new FakeNativeModule();
      const bridge: TdCoreBridge = new TdCoreBridge(fake);
      bridge.createClient();

      let mainEvents: number = 0;
      let dynamicEvents: number = 0;
      let dynamicSubId: number = 0;

      const dynamicSink: TdNativeEventSink = (_evt: TdNativeEvent): void => {
        dynamicEvents += 1;
      };

      const mainSink: TdNativeEventSink = (evt: TdNativeEvent): void => {
        mainEvents += 1;
        const seq: number = parseInt(evt.sequence, 10);

        // Every 50 events, dynamically subscribe or unsubscribe auxiliary listener
        if (seq % 100 === 50) {
          if (dynamicSubId === 0) {
            dynamicSubId = bridge.subscribeUpdates(dynamicSink);
          }
        } else if (seq % 100 === 0) {
          if (dynamicSubId !== 0) {
            bridge.unsubscribe(dynamicSubId);
            dynamicSubId = 0;
          }
        }
      };

      bridge.subscribeUpdates(mainSink);

      const totalEvents: number = 2000;
      const batch: Array<FakeRawEvent> = [];
      for (let i = 1; i <= totalEvents; i++) {
        batch.push({
          schemaVersion: 1,
          clientId: 1,
          sequence: i.toString(),
          payloadUtf8: '{"@type":"updateUser"}',
          receivedAtMonotonicMs: 1700000000000 + i,
          sessionGeneration: 1
        });
      }
      fake.deliverBatch(batch);

      expect(mainEvents).assertEqual(totalEvents);
      // Auxiliary listener received subset during its active windows
      expect(dynamicEvents > 0).assertTrue();
      expect(dynamicEvents < totalEvents).assertTrue();
    });

    it('continuousSessionGenerationRollover_dropsStaleOnly', 0, () => {
      const fake: FakeNativeModule = new FakeNativeModule();
      const bridge: TdCoreBridge = new TdCoreBridge(fake);
      bridge.createClient();

      let receivedGen1: number = 0;
      let receivedGen2: number = 0;

      bridge.subscribeUpdates((evt: TdNativeEvent): void => {
        if (evt.payloadUtf8.indexOf('gen1') !== -1) {
          receivedGen1 += 1;
        } else if (evt.payloadUtf8.indexOf('gen2') !== -1) {
          receivedGen2 += 1;
        }
      });

      // Generation 1: 1000 events
      const batch1: Array<FakeRawEvent> = [];
      for (let i = 1; i <= 1000; i++) {
        batch1.push({
          sequence: i.toString(),
          payloadUtf8: '{"@type":"updateGen","tag":"gen1"}',
          sessionGeneration: 1
        });
      }
      fake.deliverBatch(batch1);
      expect(receivedGen1).assertEqual(1000);

      // Rollover to Generation 2
      fake.resetSession();
      expect(fake.getSessionGeneration()).assertEqual(2);

      // Stale Generation 1 events arriving late: 500 events
      const staleBatch: Array<FakeRawEvent> = [];
      for (let i = 1001; i <= 1500; i++) {
        staleBatch.push({
          sequence: i.toString(),
          payloadUtf8: '{"@type":"updateGen","tag":"gen1_stale"}',
          sessionGeneration: 1 // Old generation
        });
      }
      fake.deliverBatch(staleBatch);
      // Stale events were discarded
      expect(fake.getStaleDroppedCount()).assertEqual(500);
      expect(receivedGen1).assertEqual(1000);

      // Fresh Generation 2 events: 1000 events
      const batch2: Array<FakeRawEvent> = [];
      for (let i = 1; i <= 1000; i++) {
        batch2.push({
          sequence: i.toString(),
          payloadUtf8: '{"@type":"updateGen","tag":"gen2"}',
          sessionGeneration: 2 // Current generation
        });
      }
      fake.deliverBatch(batch2);
      expect(receivedGen2).assertEqual(1000);
    });

    it('extremeLarge64BitSequence_preservesPrecisionAsString', 0, () => {
      const fake: FakeNativeModule = new FakeNativeModule();
      const bridge: TdCoreBridge = new TdCoreBridge(fake);
      bridge.createClient();

      const receivedSeqs: Array<string> = [];
      bridge.subscribeUpdates((evt: TdNativeEvent): void => {
        receivedSeqs.push(evt.sequence);
      });

      // 9007199254740992 is 2^53. Numbers above this lose precision in JS Number.
      const bigSeq1: string = '9007199254740993';
      const bigSeq2: string = '9007199254740994';
      const bigSeq3: string = '9007199254740995';

      fake.deliverBatch([
        { sequence: bigSeq1, payloadUtf8: '{"@type":"big1"}' },
        { sequence: bigSeq2, payloadUtf8: '{"@type":"big2"}' },
        { sequence: bigSeq3, payloadUtf8: '{"@type":"big3"}' }
      ]);

      expect(receivedSeqs.length).assertEqual(3);
      expect(receivedSeqs[0]).assertEqual(bigSeq1);
      expect(receivedSeqs[1]).assertEqual(bigSeq2);
      expect(receivedSeqs[2]).assertEqual(bigSeq3);
    });

    it('rapidCloseAndReopen_stressCycle', 0, () => {
      const fake: FakeNativeModule = new FakeNativeModule();
      const bridge: TdCoreBridge = new TdCoreBridge(fake);

      for (let cycle = 0; cycle < 50; cycle++) {
        expect(bridge.lifecycleState === 'idle' || bridge.lifecycleState === 'closed').assertTrue();
        const cid: number = bridge.createClient();
        expect(cid > 0).assertTrue();
        expect(bridge.lifecycleState).assertEqual('active');

        const subId: number = bridge.subscribeUpdates((_evt: TdNativeEvent): void => {});
        expect(subId > 0).assertTrue();

        bridge.close();
        expect(bridge.lifecycleState).assertEqual('closed');
        expect(bridge.getMetrics().subscriptions).assertEqual(0);
      }
    });

  });
}
