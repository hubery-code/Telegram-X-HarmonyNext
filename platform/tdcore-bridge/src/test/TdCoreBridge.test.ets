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

    // NeedsDevice: the following require libtdcore_napi.so (real TDLib):
    // - TdCoreBridge() with no arg (production native import)
    // - getVersion() returning real TDLib version string
    // - createClient() creating a real TDLib client
    // - send() delivering to real TDLib actor
    // - subscribeUpdates() receiving real TDLib updates via TSFN
  });
}
