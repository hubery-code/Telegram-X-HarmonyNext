/**
 * 设备测试 — RdbPreferencesAdapter（PLAT-002，待真机执行）。
 *
 * 验证 Kit 集成关键点（本地 panda 单测无法覆盖的部分）：
 * - open 走真实 relationalStore 建库、写 user_version、建 tgx_kv；
 * - flush → close → 重新 open（含版本标记读取 + 全量加载）数据落盘可读
 *   —— 持久化闭环 + 中断/重启恢复的结构路径；
 * - 变更事件按契约语义派发；
 * - remove/clear 落盘后重开生效。
 *
 * 未覆盖：PLAT-001 全量参数化 contract 断言（原因与接入方式同
 * HarmonyPreferencesAdapter.device.test.ets，见 README 验证矩阵）；
 * 真实多版本升级/回滚路径待 schema v2 落地后用同 harness 扩展
 * （本地 fake 已覆盖 runner 语义：中断续跑/版本跳跃/回滚）。
 *
 * 运行前提：接入测试宿主（entry ohosTest 或专用 Test HAP）后真机执行。
 */

import { describe, it, expect } from '@ohos/hypium';
import { abilityDelegatorRegistry } from '@kit.TestKit';
import { common } from '@kit.AbilityKit';
import { PREFERENCES_CLEAR_ALL_KEY } from '@tgx/platform-ports';
import { RdbPreferencesAdapter } from '../../../main/ets/adapter/RdbPreferencesAdapter';

const DB_NAME: string = 'tgx_device_rdb_test';

function appContext(): common.Context {
  return abilityDelegatorRegistry.getAbilityDelegator().getAppContext();
}

export default function rdbPreferencesAdapterDeviceTest() {
  describe('RdbPreferencesAdapter_device', () => {
    it('flush_close_reopen_persistsValues', 0, async () => {
      const first = await RdbPreferencesAdapter.open(appContext(), { dbName: DB_NAME });
      expect(first.ok).assertTrue();
      if (!first.ok) {
        return;
      }
      await first.value.clear();
      await first.value.flush();

      first.value.put('s', 'hello');
      first.value.put('n', 42.5);
      first.value.put('b', true);
      const flushed = await first.value.flush();
      expect(flushed.ok).assertTrue();
      const closed = await first.value.close();
      expect(closed.ok).assertTrue();

      const second = await RdbPreferencesAdapter.open(appContext(), { dbName: DB_NAME });
      expect(second.ok).assertTrue();
      if (second.ok) {
        expect(second.value.getString('s').getOrNull()).assertEqual('hello');
        expect(second.value.getNumber('n').getOrNull()).assertEqual(42.5);
        expect(second.value.getBoolean('b').getOrNull()).assertTrue();

        second.value.remove('s');
        await second.value.flush();
        const third = await RdbPreferencesAdapter.open(appContext(), { dbName: DB_NAME });
        expect(third.ok).assertTrue();
        if (third.ok) {
          expect(third.value.getString('s').getOrNull() === null).assertTrue();
          expect(third.value.getNumber('n').getOrNull()).assertEqual(42.5);
          await third.value.close();
        }
        await second.value.close();
      }
    });

    it('clearFlushSurvivesReopen', 0, async () => {
      const opened = await RdbPreferencesAdapter.open(appContext(), { dbName: DB_NAME });
      expect(opened.ok).assertTrue();
      if (!opened.ok) {
        return;
      }
      const store = opened.value;
      store.put('a', 1);
      store.put('b', 2);
      await store.flush();

      const keys: string[] = [];
      store.observeChanges((change) => {
        keys.push(change.key);
      });
      store.clear();
      await store.flush();
      expect(keys.length).assertEqual(1);
      expect(keys[0]).assertEqual(PREFERENCES_CLEAR_ALL_KEY);

      const reopened = await RdbPreferencesAdapter.open(appContext(), { dbName: DB_NAME });
      expect(reopened.ok).assertTrue();
      if (reopened.ok) {
        expect(reopened.value.getNumber('a').getOrNull() === null).assertTrue();
        expect(reopened.value.getNumber('b').getOrNull() === null).assertTrue();
        await reopened.value.close();
      }
    });
  });
}
