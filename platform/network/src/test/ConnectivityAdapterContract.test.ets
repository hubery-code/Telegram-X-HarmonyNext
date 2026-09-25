/**
 * platform/network 测试 — ConnectivityAdapter 契约镜像（PLAT-004）。
 *
 * ⚠️ 同步义务：本文件镜像 platform/ports/src/test/contract/NetworkStatePortContract.ets
 * （PLAT-001 的 NetworkStatePort 同套契约）。platform/ports 契约变更时此处必须同步；
 * 理想形态是把契约函数提到可跨模块复用的位置（当前在 ports 的 src/test，跨模块不可导入，
 * 且 hypium 依赖不宜进 har 主代码）——已登记为后续优化。
 *
 * driver 为 FakeConnectivitySource.pushRaw：故意不做底层去重，
 * 契约断言（含「相同快照重复推送必须被去重」）验证的是 ConnectivityAdapter 的去重逻辑。
 */

import { describe, it, expect } from '@ohos/hypium';
import { NetworkSnapshot } from '@tgx/platform-ports';
import { ConnectivityAdapter } from '../main/ets/ConnectivityAdapter';
import { FakeConnectivitySource } from './FakeConnectivitySource';

export default function connectivityAdapterContractTest() {
  describe('ConnectivityAdapter_NetworkStatePortContract', () => {
    it('current_reflectsInitialState', 0, () => {
      const adapter: ConnectivityAdapter = new ConnectivityAdapter(new FakeConnectivitySource());
      const snapshot: NetworkSnapshot = adapter.current();
      expect(snapshot.connected).assertFalse();
      expect(snapshot.transport === null).assertTrue();
    });

    it('observe_emitsCurrentSnapshotImmediately', 0, () => {
      const adapter: ConnectivityAdapter = new ConnectivityAdapter(new FakeConnectivitySource());
      const received: NetworkSnapshot[] = [];
      const subscribed = adapter.observe((snapshot: NetworkSnapshot) => {
        received.push(snapshot);
      });
      expect(subscribed.ok).assertTrue();
      expect(received.length).assertEqual(1);
      expect(received[0].connected).assertFalse();
    });

    it('push_emitsOnChange_dedupsEqualSnapshots', 0, () => {
      const source: FakeConnectivitySource = new FakeConnectivitySource();
      const adapter: ConnectivityAdapter = new ConnectivityAdapter(source);
      const received: NetworkSnapshot[] = [];
      adapter.observe((snapshot: NetworkSnapshot) => {
        received.push(snapshot);
      });

      const wifi: NetworkSnapshot = { connected: true, transport: 'wifi', metered: false, roaming: false };
      source.pushRaw(wifi);
      expect(received.length).assertEqual(2);
      expect(received[1].transport).assertEqual('wifi');

      // 相同快照重复推送必须被去重（底层不去重，adapter 负责）
      source.pushRaw({ connected: true, transport: 'wifi', metered: false, roaming: false });
      expect(received.length).assertEqual(2);

      // 部分字段不同即视为变化
      source.pushRaw({ connected: true, transport: 'wifi', metered: true, roaming: false });
      expect(received.length).assertEqual(3);
    });

    it('wifiToCellularToOffline_transitions', 0, () => {
      const source: FakeConnectivitySource = new FakeConnectivitySource();
      const adapter: ConnectivityAdapter = new ConnectivityAdapter(source);
      const received: NetworkSnapshot[] = [];
      adapter.observe((snapshot: NetworkSnapshot) => {
        received.push(snapshot);
      });

      source.pushRaw({ connected: true, transport: 'wifi', metered: false, roaming: false });
      source.pushRaw({ connected: true, transport: 'cellular', metered: true, roaming: false });
      source.pushRaw({ connected: false, transport: null, metered: false, roaming: false });

      expect(received.length).assertEqual(4);
      expect(received[1].transport).assertEqual('wifi');
      expect(received[2].transport).assertEqual('cellular');
      expect(received[2].metered).assertTrue();
      expect(received[3].connected).assertFalse();
      expect(received[3].transport === null).assertTrue();
    });

    it('unsubscribe_stopsNotifications_andIsIdempotent', 0, () => {
      const source: FakeConnectivitySource = new FakeConnectivitySource();
      const adapter: ConnectivityAdapter = new ConnectivityAdapter(source);
      const received: NetworkSnapshot[] = [];
      const subscribed = adapter.observe((snapshot: NetworkSnapshot) => {
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

      source.pushRaw({ connected: true, transport: 'wifi', metered: false, roaming: false });
      expect(received.length).assertEqual(1);
    });

    it('current_reflectsPushedSnapshot', 0, () => {
      const source: FakeConnectivitySource = new FakeConnectivitySource();
      const adapter: ConnectivityAdapter = new ConnectivityAdapter(source);
      source.pushRaw({ connected: true, transport: 'cellular', metered: true, roaming: false });
      const snapshot: NetworkSnapshot = adapter.current();
      expect(snapshot.connected).assertTrue();
      expect(snapshot.transport).assertEqual('cellular');
      expect(snapshot.metered).assertTrue();
    });

    it('observe_propagatesRegisterFailure', 0, () => {
      const source: FakeConnectivitySource = new FakeConnectivitySource();
      source.setRegisterEnabled(false);
      const adapter: ConnectivityAdapter = new ConnectivityAdapter(source);
      const received: NetworkSnapshot[] = [];
      const subscribed = adapter.observe((snapshot: NetworkSnapshot) => {
        received.push(snapshot);
      });
      expect(subscribed.ok).assertFalse();
      expect(received.length).assertEqual(0);
    });
  });
}
