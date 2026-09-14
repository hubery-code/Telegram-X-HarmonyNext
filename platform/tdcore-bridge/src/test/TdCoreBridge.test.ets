import { describe, it, expect } from '@ohos/hypium';
import { TdCoreBridge } from '../main/ets/TdCoreBridge';
import {
  TdNativeBridgeLike,
  TdNativeEvent,
  TdNativeEventSink,
  TdNativeBridgeMetrics
} from '@tgx/td-gateway';
import { FakeNativeModule } from './FakeNativeModule';

export default function tdCoreBridgeTest() {
  describe('TdCoreBridge', () => {
    it('module_imports_and_class_exists', 0, () => {
      const fake = new FakeNativeModule();
      const bridge: TdCoreBridge = new TdCoreBridge(fake);
      expect(bridge !== null).assertTrue();
      expect(bridge instanceof TdCoreBridge).assertTrue();
    });

    it('implements_TdNativeBridgeLike_contract', 0, () => {
      const fake = new FakeNativeModule();
      const bridge: TdNativeBridgeLike = new TdCoreBridge(fake) as TdNativeBridgeLike;
      expect(bridge !== null).assertTrue();
      expect(typeof bridge.getVersion).assertEqual('function');
      expect(typeof bridge.execute).assertEqual('function');
      expect(typeof bridge.createClient).assertEqual('function');
      expect(typeof bridge.send).assertEqual('function');
      expect(typeof bridge.subscribeUpdates).assertEqual('function');
      expect(typeof bridge.unsubscribe).assertEqual('function');
      expect(typeof bridge.getMetrics).assertEqual('function');
    });

    it('getVersion_returns_nonempty_string', 0, () => {
      const fake = new FakeNativeModule();
      const bridge: TdCoreBridge = new TdCoreBridge(fake);
      const version: string = bridge.getVersion();
      expect(version.length > 0).assertTrue();
    });

    it('createClient_returns_number', 0, () => {
      const fake = new FakeNativeModule();
      const bridge: TdCoreBridge = new TdCoreBridge(fake);
      const clientId: number = bridge.createClient();
      expect(typeof clientId).assertEqual('number');
      expect(clientId > 0).assertTrue();
    });

    it('subscribeUpdates_returns_number_subscriptionId', 0, () => {
      const fake = new FakeNativeModule();
      const bridge: TdCoreBridge = new TdCoreBridge(fake);
      const sink: TdNativeEventSink = (_event: TdNativeEvent): void => {};
      const subscriptionId: number = bridge.subscribeUpdates(sink);
      expect(typeof subscriptionId).assertEqual('number');
      expect(subscriptionId > 0).assertTrue();
    });

    it('unsubscribe_is_idempotent_no_throw', 0, () => {
      const fake = new FakeNativeModule();
      const bridge: TdCoreBridge = new TdCoreBridge(fake);
      const sink: TdNativeEventSink = (_event: TdNativeEvent): void => {};
      const subscriptionId: number = bridge.subscribeUpdates(sink);
      let threw: boolean = false;
      try {
        bridge.unsubscribe(subscriptionId);
        bridge.unsubscribe(subscriptionId);
        bridge.unsubscribe(99999);
      } catch (e) {
        threw = true;
      }
      expect(threw).assertFalse();
    });

    it('getMetrics_returns_object_with_droppedCount', 0, () => {
      const fake = new FakeNativeModule();
      const bridge: TdCoreBridge = new TdCoreBridge(fake);
      const metrics: TdNativeBridgeMetrics = bridge.getMetrics();
      expect(metrics !== null).assertTrue();
      expect(typeof metrics.droppedCount).assertEqual('number');
    });

    it('getMetrics_has_all_required_fields', 0, () => {
      const fake = new FakeNativeModule();
      const bridge: TdCoreBridge = new TdCoreBridge(fake);
      const metrics: TdNativeBridgeMetrics = bridge.getMetrics();
      expect(typeof metrics.queueSize).assertEqual('number');
      expect(typeof metrics.overflowWaitCount).assertEqual('number');
      expect(typeof metrics.droppedCount).assertEqual('number');
      expect(typeof metrics.eventsForwarded).assertEqual('number');
      expect(typeof metrics.subscriptions).assertEqual('number');
      expect(typeof metrics.dispatcherRunning).assertEqual('boolean');
    });

    it('subscribe_delivers_TdNativeEvent_with_string_sequence', 0, () => {
      const fake = new FakeNativeModule();
      const bridge: TdCoreBridge = new TdCoreBridge(fake);
      let capturedSchema: number = 0;
      let capturedClientId: number = 0;
      let capturedSequence: string = '';
      let capturedPayload: string = '';
      const sink: TdNativeEventSink = (event: TdNativeEvent): void => {
        capturedSchema = event.schemaVersion;
        capturedClientId = event.clientId;
        capturedSequence = event.sequence;
        capturedPayload = event.payloadUtf8;
      };
      const subscriptionId: number = bridge.subscribeUpdates(sink);
      fake.deliverEvent(
        subscriptionId,
        1,
        42,
        '12345678901234567890',
        '{"@type":"updateOption"}',
        1700000000000
      );
      expect(capturedSchema).assertEqual(1);
      expect(capturedClientId).assertEqual(42);
      expect(typeof capturedSequence).assertEqual('string');
      expect(capturedSequence).assertEqual('12345678901234567890');
      expect(capturedPayload).assertEqual('{"@type":"updateOption"}');
    });

    it('execute_returns_response_or_null', 0, () => {
      const fake = new FakeNativeModule();
      const bridge: TdCoreBridge = new TdCoreBridge(fake);
      const response: string | null = bridge.execute('{"@type":"getOption","name":"version"}');
      expect(response !== null).assertTrue();
    });

    it('createClient_returns_incrementing_ids', 0, () => {
      const fake = new FakeNativeModule();
      const bridge: TdCoreBridge = new TdCoreBridge(fake);
      const id1: number = bridge.createClient();
      const id2: number = bridge.createClient();
      expect(id2).assertEqual(id1 + 1);
    });

    it('reentrantUnsubscribe_withinCallback_noCrashAndStopsReceiving', 0, () => {
      const fake = new FakeNativeModule();
      const bridge: TdCoreBridge = new TdCoreBridge(fake);
      let eventCount: number = 0;
      let subId: number = 0;
      const sink: TdNativeEventSink = (_event: TdNativeEvent): void => {
        eventCount += 1;
        bridge.unsubscribe(subId);
      };
      subId = bridge.subscribeUpdates(sink);
      fake.deliverBatch([
        { id: subId, payloadUtf8: '{"@type":"update1"}' },
        { id: subId, payloadUtf8: '{"@type":"update2"}' }
      ]);
      // First event was processed and unsubscribed; second event in batch was skipped for subId
      expect(eventCount).assertEqual(1);
      expect(bridge.getMetrics().subscriptions).assertEqual(0);
    });

    it('reentrantSubscribe_withinCallback_registersAndReceivesNextBatch', 0, () => {
      const fake = new FakeNativeModule();
      const bridge: TdCoreBridge = new TdCoreBridge(fake);
      let sub1Events: number = 0;
      let sub2Events: number = 0;
      let sub2Id: number = 0;
      const sink2: TdNativeEventSink = (_event: TdNativeEvent): void => {
        sub2Events += 1;
      };
      const sink1: TdNativeEventSink = (_event: TdNativeEvent): void => {
        sub1Events += 1;
        if (sub2Id === 0) {
          sub2Id = bridge.subscribeUpdates(sink2);
        }
      };
      const sub1Id: number = bridge.subscribeUpdates(sink1);
      fake.deliverBatch([
        { payloadUtf8: '{"@type":"event1"}' },
        { payloadUtf8: '{"@type":"event2"}' }
      ]);
      expect(sub1Events).assertEqual(2);
      expect(sub2Events).assertEqual(1); // sub2 was registered during event1, received event2
      expect(bridge.getMetrics().subscriptions).assertEqual(2);
    });

    it('reentrantClose_withinCallback_cleanTeardown', 0, () => {
      const fake = new FakeNativeModule();
      const bridge: TdCoreBridge = new TdCoreBridge(fake);
      bridge.createClient();
      let eventCount: number = 0;
      const sink: TdNativeEventSink = (_event: TdNativeEvent): void => {
        eventCount += 1;
        bridge.close();
      };
      const subId: number = bridge.subscribeUpdates(sink);
      fake.deliverBatch([
        { id: subId, payloadUtf8: '{"@type":"event1"}' },
        { id: subId, payloadUtf8: '{"@type":"event2"}' }
      ]);
      expect(eventCount).assertEqual(1);
      expect(bridge.lifecycleState).assertEqual('closed');
      expect(bridge.getMetrics().subscriptions).assertEqual(0);
    });

    it('sessionGeneration_discardsStaleEventsAcrossSessions', 0, () => {
      const fake = new FakeNativeModule();
      const bridge: TdCoreBridge = new TdCoreBridge(fake);
      bridge.createClient();
      let sub1Events: number = 0;
      const sub1Id: number = bridge.subscribeUpdates((_event: TdNativeEvent): void => {
        sub1Events += 1;
      });
      // Deliver event for generation 1
      fake.deliverEvent(sub1Id, 1, 1, '1', '{"@type":"gen1"}', 1000, 1);
      expect(sub1Events).assertEqual(1);

      // Close and reset session (bumps to generation 2)
      bridge.close();
      expect(fake.getSessionGeneration()).assertEqual(2);

      // Deliver stale event with generation 1
      fake.deliverEvent(sub1Id, 1, 1, '2', '{"@type":"stale_gen1"}', 2000, 1);
      expect(sub1Events).assertEqual(1); // Stale event was discarded
      expect(fake.getStaleDroppedCount()).assertEqual(1);

      // Reopen session with createClient
      bridge.createClient();
      let sub2Events: number = 0;
      const sub2Id: number = bridge.subscribeUpdates((_event: TdNativeEvent): void => {
        sub2Events += 1;
      });
      // Deliver valid event for generation 2
      fake.deliverEvent(sub2Id, 1, 2, '1', '{"@type":"gen2"}', 3000, 2);
      expect(sub2Events).assertEqual(1);
    });

    // NeedsDevice: the following require libtdcore_napi.so (real TDLib):
    // - TdCoreBridge() with no arg (production native import)
    // - getVersion() returning real TDLib version string
    // - createClient() creating a real TDLib client
    // - send() delivering to real TDLib actor
    // - subscribeUpdates() receiving real TDLib updates via TSFN
  });
}
