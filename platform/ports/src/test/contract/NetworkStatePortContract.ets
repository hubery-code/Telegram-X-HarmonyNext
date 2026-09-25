/**
 * platform/ports — NetworkStatePort 同套契约测试（PLAT-001）。
 *
 * 任何 NetworkStatePort 实现（当前 FakeNetworkState，未来 PLAT-004 的
 * Network Kit adapter）都通过 `networkStatePortContract('name', factory, driver)`
 * 套用同一组断言。driver.push 模拟底层网络切换。
 */

import { describe, it, expect } from '@ohos/hypium';
import { NetworkSnapshot, NetworkStatePort } from '../../main/ets/NetworkStatePort';

export interface NetworkStateDriver {
  push(snapshot: NetworkSnapshot): void;
}

export default function networkStatePortContract(
  name: string,
  factory: () => NetworkStatePort,
  driver: NetworkStateDriver
) {
  describe(`${name}_NetworkStatePortContract`, () => {
    it('current_reflectsInitialState', 0, () => {
      const port: NetworkStatePort = factory();
      const snapshot: NetworkSnapshot = port.current();
      expect(snapshot.connected).assertFalse();
      expect(snapshot.transport === null).assertTrue();
    });

    it('observe_emitsCurrentSnapshotImmediately', 0, () => {
      const port: NetworkStatePort = factory();
      const received: NetworkSnapshot[] = [];
      const subscribed = port.observe((snapshot: NetworkSnapshot) => {
        received.push(snapshot);
      });
      expect(subscribed.ok).assertTrue();
      expect(received.length).assertEqual(1);
      expect(received[0].connected).assertFalse();
    });

    it('push_emitsOnChange_dedupsEqualSnapshots', 0, () => {
      const port: NetworkStatePort = factory();
      const received: NetworkSnapshot[] = [];
      port.observe((snapshot: NetworkSnapshot) => {
        received.push(snapshot);
      });

      const wifi: NetworkSnapshot = { connected: true, transport: 'wifi', metered: false, roaming: false };
      driver.push(wifi);
      expect(received.length).assertEqual(2);
      expect(received[1].transport).assertEqual('wifi');

      // 相同快照重复推送必须被去重
      driver.push({ connected: true, transport: 'wifi', metered: false, roaming: false });
      expect(received.length).assertEqual(2);

      // 部分字段不同即视为变化
      driver.push({ connected: true, transport: 'wifi', metered: true, roaming: false });
      expect(received.length).assertEqual(3);
    });

    it('wifiToCellularToOffline_transitions', 0, () => {
      const port: NetworkStatePort = factory();
      const received: NetworkSnapshot[] = [];
      port.observe((snapshot: NetworkSnapshot) => {
        received.push(snapshot);
      });

      driver.push({ connected: true, transport: 'wifi', metered: false, roaming: false });
      driver.push({ connected: true, transport: 'cellular', metered: true, roaming: false });
      driver.push({ connected: false, transport: null, metered: false, roaming: false });

      expect(received.length).assertEqual(4);
      expect(received[1].transport).assertEqual('wifi');
      expect(received[2].transport).assertEqual('cellular');
      expect(received[2].metered).assertTrue();
      expect(received[3].connected).assertFalse();
      expect(received[3].transport === null).assertTrue();
    });

    it('unsubscribe_stopsNotifications_andIsIdempotent', 0, () => {
      const port: NetworkStatePort = factory();
      const received: NetworkSnapshot[] = [];
      const subscribed = port.observe((snapshot: NetworkSnapshot) => {
        received.push(snapshot);
      });
      if (!subscribed.ok) {
        expect(false).assertTrue();
        return;
      }
      const subscription = subscribed.value;
      subscription.unsubscribe();
      expect(subscription.isActive).assertFalse();
      subscription.unsubscribe();

      driver.push({ connected: true, transport: 'wifi', metered: false, roaming: false });
      expect(received.length).assertEqual(1);
    });

    it('current_reflectsPushedSnapshot', 0, () => {
      const port: NetworkStatePort = factory();
      driver.push({ connected: true, transport: 'cellular', metered: true, roaming: false });
      const snapshot: NetworkSnapshot = port.current();
      expect(snapshot.connected).assertTrue();
      expect(snapshot.transport).assertEqual('cellular');
      expect(snapshot.metered).assertTrue();
    });
  });
}
