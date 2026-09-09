/**
 * platform/network 设备测试 — Kit 真连接 smoke（PLAT-004 ohosTest 骨架）。
 *
 * 需要真机/模拟器运行（@ohos.net.connection 在本地单测环境不可用）。
 * 前置：应用已声明 ohos.permission.GET_NETWORK_INFO（platform_network 模块 module.json5）。
 *
 * 覆盖：
 * - current() 返回形状合法的快照（不断言具体网络状态——设备环境不可控）；
 * - observe() 注册即派初始快照、返回 ok、注销幂等；
 * - 事件流端到端验证（开关 Wi-Fi/飞行模式观察 wifi/cellular/offline 切换）
 *   需在真机手工执行，见 README「验证矩阵」。
 */

import { describe, it, expect } from '@ohos/hypium';
import { NetworkSnapshot } from '@tgx/platform-ports';
import { ConnectivityAdapter, ConnectivityKitSource } from '../../main/ets/Index';

export default function kitDeviceSmokeTest() {
  describe('ConnectivityKit_DeviceSmoke', () => {
    it('current_returnsWellFormedSnapshot', 0, () => {
      const adapter: ConnectivityAdapter = new ConnectivityAdapter();
      const snapshot: NetworkSnapshot = adapter.current();
      expect(typeof snapshot.connected).assertEqual('boolean');
      if (snapshot.connected) {
        expect(snapshot.transport === 'wifi'
          || snapshot.transport === 'cellular'
          || snapshot.transport === 'ethernet'
          || snapshot.transport === 'other').assertTrue();
      } else {
        expect(snapshot.transport === null).assertTrue();
        expect(snapshot.metered).assertFalse();
      }
    });

    it('observe_emitsInitialAndUnsubscribesCleanly', 0, () => {
      const adapter: ConnectivityAdapter = new ConnectivityAdapter(new ConnectivityKitSource());
      const received: NetworkSnapshot[] = [];
      const subscribed = adapter.observe((snapshot: NetworkSnapshot) => {
        received.push(snapshot);
      });
      expect(subscribed.ok).assertTrue();
      expect(received.length).assertLarger(0);
      if (!subscribed.ok) {
        return;
      }
      const subscription = subscribed.value;
      subscription.unsubscribe();
      expect(subscription.isActive).assertFalse();
      subscription.unsubscribe();
    });
  });
}
