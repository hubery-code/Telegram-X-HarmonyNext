/**
 * 设备测试 — HarmonyPreferencesAdapter（PLAT-002，待真机执行）。
 *
 * 验证 Kit 集成关键点（本地 panda 单测无法覆盖的部分）：
 * - openSync 同步打开（getPreferencesSync，API 10+）；
 * - flush 后重新打开（新实例）数据真实落盘可读 —— 持久化闭环；
 * - 变更事件按契约语义派发（flush 后、同 key 合并、clear 通配）。
 *
 * 未覆盖：PLAT-001 全量参数化 contract 断言。contract 函数位于
 * platform/ports 的 src/test，ArkTS 编译器禁止跨模块相对 import，
 * 全量 contract 复用待 test_support 包落地后接入（见 README 验证矩阵）。
 *
 * 运行前提：接入测试宿主（entry ohosTest 或专用 Test HAP）后真机执行。
 */

import { describe, it, expect } from '@ohos/hypium';
import { abilityDelegatorRegistry } from '@kit.TestKit';
import { common } from '@kit.AbilityKit';
import { PREFERENCES_CLEAR_ALL_KEY } from '@tgx/platform-ports';
import { HarmonyPreferencesAdapter } from '../../../main/ets/adapter/HarmonyPreferencesAdapter';

const STORE_NAME: string = 'tgx_device_hp_test';

function appContext(): common.Context {
  return abilityDelegatorRegistry.getAbilityDelegator().getAppContext();
}

export default function harmonyPreferencesAdapterDeviceTest() {
  describe('HarmonyPreferencesAdapter_device', () => {
    it('flush_thenReopen_persistsValues', 0, async () => {
      const first = HarmonyPreferencesAdapter.openSync(appContext(), STORE_NAME);
      expect(first.ok).assertTrue();
      if (!first.ok) {
        return;
      }
      await first.value.clear();
      await first.value.flush();

      first.value.put('s', 'hello');
      first.value.put('n', 42);
      first.value.put('b', true);
      const flushed = await first.value.flush();
      expect(flushed.ok).assertTrue();

      const second = HarmonyPreferencesAdapter.openSync(appContext(), STORE_NAME);
      expect(second.ok).assertTrue();
      if (second.ok) {
        expect(second.value.getString('s').getOrNull()).assertEqual('hello');
        expect(second.value.getNumber('n').getOrNull()).assertEqual(42);
        expect(second.value.getBoolean('b').getOrNull()).assertTrue();
      }
    });

    it('changesDispatchAfterFlush_withMergeAndWildcard', 0, async () => {
      const opened = HarmonyPreferencesAdapter.openSync(appContext(), STORE_NAME);
      expect(opened.ok).assertTrue();
      if (!opened.ok) {
        return;
      }
      const store = opened.value;
      await store.clear();
      await store.flush();

      const keys: string[] = [];
      store.observeChanges((change) => {
        keys.push(change.key);
      });

      store.put('k', 'v1');
      store.put('k', 'v2');
      expect(keys.length).assertEqual(0);
      await store.flush();
      expect(keys.length).assertEqual(1);
      expect(keys[0]).assertEqual('k');

      store.clear();
      await store.flush();
      expect(keys.length).assertEqual(2);
      expect(keys[1]).assertEqual(PREFERENCES_CLEAR_ALL_KEY);
    });

    it('typeMismatch_returnsParameterError', 0, async () => {
      const opened = HarmonyPreferencesAdapter.openSync(appContext(), STORE_NAME);
      expect(opened.ok).assertTrue();
      if (opened.ok) {
        opened.value.put('str', 'text');
        const asNumber = opened.value.getNumber('str');
        expect(asNumber.err).assertTrue();
        if (asNumber.err) {
          expect(asNumber.error.kind).assertEqual('parameter');
        }
      }
    });
  });
}
