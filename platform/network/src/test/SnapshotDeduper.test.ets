/**
 * platform/network 测试 — SnapshotDeduper 去重状态机（PLAT-004 纯逻辑）。
 *
 * 场景：Kit 天然重复上报（netCapabilitiesChange 连发同值）、
 * 字段级变化才派发、断网/恢复序列。
 */

import { describe, it, expect } from '@ohos/hypium';
import { NetworkSnapshot } from '@tgx/platform-ports';
import { SnapshotDeduper, DISCONNECTED_SNAPSHOT } from '../main/ets/ConnectivityMapping';

export default function snapshotDeduperTest() {
  describe('SnapshotDeduper', () => {
    it('first_snapshot_always_emitted', 0, () => {
      const deduper: SnapshotDeduper = new SnapshotDeduper();
      const out: NetworkSnapshot | null = deduper.next(DISCONNECTED_SNAPSHOT);
      expect(out === null).assertFalse();
      expect(out!.connected).assertFalse();
    });

    it('consecutive_duplicates_dropped', 0, () => {
      const deduper: SnapshotDeduper = new SnapshotDeduper();
      const wifi: NetworkSnapshot = { connected: true, transport: 'wifi', metered: false };
      deduper.next(wifi);
      // Kit 重复上报同值 → 去重
      expect(deduper.next({ connected: true, transport: 'wifi', metered: false }) === null).assertTrue();
      expect(deduper.next({ connected: true, transport: 'wifi', metered: false }) === null).assertTrue();
    });

    it('field_level_change_emitted', 0, () => {
      const deduper: SnapshotDeduper = new SnapshotDeduper();
      deduper.next({ connected: true, transport: 'wifi', metered: false });
      // 仅 metered 变化也算新快照
      const out: NetworkSnapshot | null = deduper.next({ connected: true, transport: 'wifi', metered: true });
      expect(out === null).assertFalse();
      expect(out!.metered).assertTrue();
    });

    it('wifi_cellular_offline_flap', 0, () => {
      const deduper: SnapshotDeduper = new SnapshotDeduper();
      let count: number = 0;
      const feed = (s: NetworkSnapshot): void => {
        if (deduper.next(s) !== null) {
          count += 1;
        }
      };
      feed(DISCONNECTED_SNAPSHOT); // 1
      feed({ connected: true, transport: 'wifi', metered: false }); // 2
      feed({ connected: true, transport: 'wifi', metered: false }); // 去重
      feed({ connected: true, transport: 'cellular', metered: true }); // 3
      feed(DISCONNECTED_SNAPSHOT); // 4
      feed(DISCONNECTED_SNAPSHOT); // 去重
      feed({ connected: true, transport: 'wifi', metered: false }); // 5
      expect(count).assertEqual(5);
    });
  });
}
