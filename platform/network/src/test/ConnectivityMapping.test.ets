/**
 * platform/network 测试 — 映射表（PLAT-004 纯逻辑）。
 *
 * 覆盖：bearer → transport 映射、多 bearer 优先级、metered 判定、断网快照形状。
 */

import { describe, it, expect } from '@ohos/hypium';
import { NetworkSnapshot } from '@tgx/platform-ports';
import {
  NET_BEARER_CELLULAR,
  NET_BEARER_WIFI,
  NET_BEARER_BLUETOOTH,
  NET_BEARER_ETHERNET,
  NET_BEARER_VPN,
  NET_CAPABILITY_NOT_METERED,
  DISCONNECTED_SNAPSHOT,
  transportForBearer,
  mapCapabilities,
  sameSnapshot
} from '../main/ets/ConnectivityMapping';

export default function connectivityMappingTest() {
  describe('ConnectivityMapping', () => {
    it('bearer_to_transport', 0, () => {
      expect(transportForBearer(NET_BEARER_WIFI)).assertEqual('wifi');
      expect(transportForBearer(NET_BEARER_CELLULAR)).assertEqual('cellular');
      expect(transportForBearer(NET_BEARER_ETHERNET)).assertEqual('ethernet');
      expect(transportForBearer(NET_BEARER_BLUETOOTH)).assertEqual('other');
      expect(transportForBearer(NET_BEARER_VPN)).assertEqual('other');
      expect(transportForBearer(999)).assertEqual('other');
    });

    it('single_bearer_snapshot_and_metered', 0, () => {
      const wifi: NetworkSnapshot = mapCapabilities({
        bearerTypes: [NET_BEARER_WIFI],
        capabilities: [NET_CAPABILITY_NOT_METERED]
      });
      expect(wifi.connected).assertTrue();
      expect(wifi.transport).assertEqual('wifi');
      expect(wifi.metered).assertFalse();

      // 蜂窝不带 NOT_METERED → 计费
      const cellular: NetworkSnapshot = mapCapabilities({
        bearerTypes: [NET_BEARER_CELLULAR],
        capabilities: [0]
      });
      expect(cellular.transport).assertEqual('cellular');
      expect(cellular.metered).assertTrue();

      const ethernet: NetworkSnapshot = mapCapabilities({
        bearerTypes: [NET_BEARER_ETHERNET],
        capabilities: [NET_CAPABILITY_NOT_METERED]
      });
      expect(ethernet.transport).assertEqual('ethernet');
      expect(ethernet.metered).assertFalse();
    });

    it('multi_bearer_priority_ethernetWifiCellular', 0, () => {
      // 系统默认网络优先级：ethernet > wifi > cellular > other
      const overVpn: NetworkSnapshot = mapCapabilities({
        bearerTypes: [NET_BEARER_VPN, NET_BEARER_WIFI],
        capabilities: [NET_CAPABILITY_NOT_METERED]
      });
      expect(overVpn.transport).assertEqual('wifi');

      const dual: NetworkSnapshot = mapCapabilities({
        bearerTypes: [NET_BEARER_CELLULAR, NET_BEARER_WIFI],
        capabilities: []
      });
      expect(dual.transport).assertEqual('wifi');

      const ethCellular: NetworkSnapshot = mapCapabilities({
        bearerTypes: [NET_BEARER_CELLULAR, NET_BEARER_ETHERNET],
        capabilities: []
      });
      expect(ethCellular.transport).assertEqual('ethernet');

      const cellularOnly: NetworkSnapshot = mapCapabilities({
        bearerTypes: [NET_BEARER_VPN, NET_BEARER_CELLULAR],
        capabilities: []
      });
      expect(cellularOnly.transport).assertEqual('cellular');
    });

    it('empty_bearer_types_is_connected_other', 0, () => {
      const snapshot: NetworkSnapshot = mapCapabilities({ bearerTypes: [], capabilities: [] });
      expect(snapshot.connected).assertTrue();
      expect(snapshot.transport).assertEqual('other');
      expect(snapshot.metered).assertTrue();
    });

    it('metered_true_when_not_metered_capability_absent', 0, () => {
      const snapshot: NetworkSnapshot = mapCapabilities({
        bearerTypes: [NET_BEARER_WIFI],
        capabilities: [4, 12]
      });
      expect(snapshot.metered).assertTrue();
    });

    it('disconnected_snapshot_shape', 0, () => {
      expect(DISCONNECTED_SNAPSHOT.connected).assertFalse();
      expect(DISCONNECTED_SNAPSHOT.transport === null).assertTrue();
      expect(DISCONNECTED_SNAPSHOT.metered).assertFalse();
    });

    it('sameSnapshot_allFieldsCompared', 0, () => {
      const a: NetworkSnapshot = { connected: true, transport: 'wifi', metered: false };
      expect(sameSnapshot(a, { connected: true, transport: 'wifi', metered: false })).assertTrue();
      expect(sameSnapshot(a, { connected: true, transport: 'wifi', metered: true })).assertFalse();
      expect(sameSnapshot(a, { connected: true, transport: 'cellular', metered: false })).assertFalse();
      expect(sameSnapshot(a, { connected: false, transport: null, metered: false })).assertFalse();
    });
  });
}
