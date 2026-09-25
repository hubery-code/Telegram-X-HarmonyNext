import { describe, it, expect } from '@ohos/hypium';
import { ManualClock } from '@tgx/core-common';
import {
  AccountRegistry,
  AccountRegistryOptions,
  AccountScope
} from '@tgx/core-account';
import { FakeAppFiles, FakeNetworkState, NetworkSnapshot } from '@tgx/platform-ports';
import {
  LifecycleCoordinator,
  LifecycleCoordinatorOptions,
  LifecycleBootstrapReport,
  mapSnapshotToNetworkType
} from '../../main/ets/lifecycle/LifecycleCoordinator';
import { FakeAccountBridge } from './FakeAccountBridge';

class LifecycleTestHarness {
  readonly bridge: FakeAccountBridge;
  readonly files: FakeAppFiles;
  readonly network: FakeNetworkState;
  readonly registry: AccountRegistry;
  readonly clock: ManualClock;
  readonly coordinator: LifecycleCoordinator;

  constructor(
    bridge: FakeAccountBridge,
    files: FakeAppFiles,
    network: FakeNetworkState,
    registry: AccountRegistry,
    clock: ManualClock,
    coordinator: LifecycleCoordinator
  ) {
    this.bridge = bridge;
    this.files = files;
    this.network = network;
    this.registry = registry;
    this.clock = clock;
    this.coordinator = coordinator;
  }
}

function createHarness(initialNetwork?: NetworkSnapshot): LifecycleTestHarness {
  const bridge: FakeAccountBridge = new FakeAccountBridge();
  const files: FakeAppFiles = new FakeAppFiles();
  const clock: ManualClock = new ManualClock(1000, 100);
  const network: FakeNetworkState = new FakeNetworkState(initialNetwork);

  const options: AccountRegistryOptions = {
    bridge: bridge,
    files: files,
    clock: clock
  };
  const registry: AccountRegistry = new AccountRegistry(options);
  registry.start();

  const coordinatorOptions: LifecycleCoordinatorOptions = {
    registry: registry,
    network: network,
    clock: clock
  };
  const coordinator: LifecycleCoordinator = new LifecycleCoordinator(coordinatorOptions);

  return new LifecycleTestHarness(
    bridge,
    files,
    network,
    registry,
    clock,
    coordinator
  );
}

export default function lifecycleCoordinatorTest() {
  describe('LifecycleCoordinator', () => {

    it('mapSnapshotToNetworkType maps correctly', 0, () => {
      const disconnected: NetworkSnapshot = { connected: false, transport: null, metered: false, roaming: false };
      expect(mapSnapshotToNetworkType(disconnected).type).assertEqual('networkTypeNone');

      const wifi: NetworkSnapshot = { connected: true, transport: 'wifi', metered: false, roaming: false };
      expect(mapSnapshotToNetworkType(wifi).type).assertEqual('networkTypeWiFi');

      const cellular: NetworkSnapshot = { connected: true, transport: 'cellular', metered: true, roaming: false };
      expect(mapSnapshotToNetworkType(cellular).type).assertEqual('networkTypeMobile');

      const roaming: NetworkSnapshot = { connected: true, transport: 'cellular', metered: true, roaming: true };
      expect(mapSnapshotToNetworkType(roaming).type).assertEqual('networkTypeMobileRoaming');

      const ethernet: NetworkSnapshot = { connected: true, transport: 'ethernet', metered: false, roaming: false };
      expect(mapSnapshotToNetworkType(ethernet).type).assertEqual('networkTypeOther');
    });

    it('cold start with empty manifest creates default account', 0, () => {
      const h = createHarness({ connected: true, transport: 'wifi', metered: false, roaming: false });
      const report: LifecycleBootstrapReport = h.coordinator.start();

      expect(report.primaryScope.accountKey).assertEqual('default');
      expect(report.primaryScope.lifecycle).assertEqual('active');
      expect(report.scopes.length).assertEqual(1);
      expect(report.failures.length).assertEqual(0);
      expect(report.isForeground).assertTrue();
      expect(h.coordinator.isForeground).assertTrue();
      expect(h.coordinator.primaryAccountScope?.accountKey).assertEqual('default');

      // Check setNetworkType was sent
      let hasSetNetworkType: boolean = false;
      for (let i = 0; i < h.bridge.sent.length; i++) {
        if (h.bridge.sent[i].utf8.indexOf('setNetworkType') >= 0) {
          hasSetNetworkType = true;
          break;
        }
      }
      expect(hasSetNetworkType).assertTrue();
    });

    it('cold start restores persisted accounts', 0, () => {
      const h = createHarness({ connected: true, transport: 'wifi', metered: false, roaming: false });
      // Pre-create two accounts in registry
      h.registry.create('primary_user');
      h.registry.create('secondary_user');
      h.registry.hibernate('secondary_user');

      // Cold start: fresh registry on same files (manifest preserved)
      const freshRegistry = new AccountRegistry({
        bridge: h.bridge,
        files: h.files,
        clock: h.clock
      });
      freshRegistry.start();

      // Now create a fresh coordinator on the fresh registry
      const freshCoordinator = new LifecycleCoordinator({
        registry: freshRegistry,
        network: h.network,
        clock: h.clock
      });

      const report: LifecycleBootstrapReport = freshCoordinator.start();
      expect(report.primaryScope.accountKey).assertEqual('primary_user');
      expect(report.primaryScope.lifecycle).assertEqual('active');
      expect(report.scopes.length).assertEqual(2);

      const secondary = freshRegistry.get('secondary_user');
      expect(secondary?.lifecycle).assertEqual('hibernating');
    });

    it('onForeground and onBackground transitions correctly', 0, () => {
      let foregroundChanges: boolean[] = [];
      const bridge = new FakeAccountBridge();
      const files = new FakeAppFiles();
      const clock = new ManualClock(1000, 100);
      const network = new FakeNetworkState({ connected: true, transport: 'wifi', metered: false, roaming: false });

      const registry = new AccountRegistry({ bridge: bridge, files: files, clock: clock });
      registry.start();

      const coordinator = new LifecycleCoordinator({
        registry: registry,
        network: network,
        clock: clock,
        onForegroundChanged: (fg: boolean) => {
          foregroundChanges.push(fg);
        }
      });

      coordinator.start();
      expect(coordinator.isForeground).assertTrue();

      // Enter background
      coordinator.onBackground();
      expect(coordinator.isForeground).assertFalse();
      expect(foregroundChanges.length).assertEqual(1);
      expect(foregroundChanges[0]).assertFalse();

      // Duplicate background call is ignored
      coordinator.onBackground();
      expect(foregroundChanges.length).assertEqual(1);

      // Return to foreground
      bridge.sent.length = 0;
      coordinator.onForeground();
      expect(coordinator.isForeground).assertTrue();
      expect(foregroundChanges.length).assertEqual(2);
      expect(foregroundChanges[1]).assertTrue();

      // Duplicate foreground call is ignored
      coordinator.onForeground();
      expect(foregroundChanges.length).assertEqual(2);

      // Verify network type broadcasted on foreground
      let setNetCount: number = 0;
      for (let i = 0; i < bridge.sent.length; i++) {
        if (bridge.sent[i].utf8.indexOf('setNetworkType') >= 0) {
          setNetCount += 1;
        }
      }
      expect(setNetCount).assertEqual(1);
    });

    it('dynamic network change broadcasts to active scopes', 0, () => {
      const h = createHarness({ connected: true, transport: 'wifi', metered: false, roaming: false });
      h.coordinator.start();
      h.bridge.sent.length = 0;

      // Switch to cellular
      h.network.push({ connected: true, transport: 'cellular', metered: true, roaming: false });
      expect(h.bridge.sent.length).assertEqual(1);
      expect(h.bridge.sent[0].utf8.indexOf('networkTypeMobile') >= 0).assertTrue();

      // Switch to disconnected
      h.bridge.sent.length = 0;
      h.network.push({ connected: false, transport: null, metered: false, roaming: false });
      expect(h.bridge.sent.length).assertEqual(1);
      expect(h.bridge.sent[0].utf8.indexOf('networkTypeNone') >= 0).assertTrue();
    });

    /**
     * AUTODL-102：自动下载门读的是这里的缓存快照，而不是自己去订阅网络。
     * 三条都要钉住：没启动过是 null（门按「无网络信息」放行给主开关判定）、
     * start() 用 current() 兜一次底（首帧不等异步回调）、推来的新快照能刷新缓存。
     */
    it('caches snapshots for the auto-download gate', 0, () => {
      const h = createHarness({ connected: true, transport: 'wifi', metered: false, roaming: false });
      expect(h.coordinator.lastNetworkSnapshot === null).assertTrue();

      h.coordinator.start();
      const seeded: NetworkSnapshot | null = h.coordinator.lastNetworkSnapshot;
      expect(seeded !== null).assertTrue();
      if (seeded !== null) {
        expect(seeded.transport).assertEqual('wifi');
        expect(seeded.roaming).assertFalse();
      }

      h.network.push({ connected: true, transport: 'cellular', metered: true, roaming: true });
      const roaming: NetworkSnapshot | null = h.coordinator.lastNetworkSnapshot;
      expect(roaming !== null).assertTrue();
      if (roaming !== null) {
        expect(roaming.transport).assertEqual('cellular');
        expect(roaming.roaming).assertTrue();
      }

      // 销毁后不再刷新：门读到的应当是最后一次有效快照，而不是半路状态
      h.coordinator.onDestroy();
      h.network.push({ connected: false, transport: null, metered: false, roaming: false });
      const frozen: NetworkSnapshot | null = h.coordinator.lastNetworkSnapshot;
      expect(frozen !== null).assertTrue();
      if (frozen !== null) {
        expect(frozen.roaming).assertTrue();
      }
    });

    it('onDestroy tears down coordinator, closes scopes, and unregisters network', 0, () => {
      const h = createHarness({ connected: true, transport: 'wifi', metered: false, roaming: false });
      const report = h.coordinator.start();
      const scope = report.primaryScope;

      expect(scope.lifecycle).assertEqual('active');
      expect(h.coordinator.isDestroyed).assertFalse();

      h.coordinator.onDestroy();
      expect(h.coordinator.isDestroyed).assertTrue();
      expect(h.coordinator.isForeground).assertFalse();
      expect(scope.lifecycle).assertEqual('closed');

      // Pushing network after destroy does not emit requests
      h.bridge.sent.length = 0;
      h.network.push({ connected: true, transport: 'wifi', metered: false, roaming: false });
      expect(h.bridge.sent.length).assertEqual(0);
    });

  });
}
