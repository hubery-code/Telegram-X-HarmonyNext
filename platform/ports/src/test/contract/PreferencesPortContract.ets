/**
 * platform/ports — PreferencesPort 同套契约测试（PLAT-001）。
 *
 * 验收「生产/fake 同套 contract」的结构基础：任何 PreferencesPort 实现
 * （当前 FakePreferencesStore，未来 PLAT-002 的 Kit adapter）都通过
 * `preferencesPortContract('name', factory)` 套用同一组断言。
 */

import { describe, it, expect } from '@ohos/hypium';
import { PreferenceChange, PREFERENCES_CLEAR_ALL_KEY, PreferencesPort } from '../../main/ets/PreferencesPort';
import { FakePreferencesStore } from '../../main/ets/fakes/FakePreferencesStore';

export default function preferencesPortContract(name: string, factory: () => PreferencesPort) {
  describe(`${name}_PreferencesPortContract`, () => {
    it('typedPutGet_roundTrips', 0, () => {
      const store: PreferencesPort = factory();
      store.put('s', 'hello');
      store.put('n', 42);
      store.put('b', true);

      const s = store.getString('s');
      expect(s.ok).assertTrue();
      if (s.ok) {
        expect(s.value).assertEqual('hello');
      }
      const n = store.getNumber('n');
      expect(n.ok).assertTrue();
      if (n.ok) {
        expect(n.value).assertEqual(42);
      }
      const b = store.getBoolean('b');
      expect(b.ok).assertTrue();
      if (b.ok) {
        expect(b.value).assertTrue();
      }
    });

    it('missingKey_returnsNull', 0, () => {
      const store: PreferencesPort = factory();
      const r = store.getString('absent');
      expect(r.ok).assertTrue();
      if (r.ok) {
        expect(r.value === null).assertTrue();
      }
    });

    it('typeMismatch_returnsParameterError', 0, () => {
      const store: PreferencesPort = factory();
      store.put('key', 'text');
      const asNumber = store.getNumber('key');
      expect(asNumber.err).assertTrue();
      if (asNumber.err) {
        expect(asNumber.error.kind).assertEqual('parameter');
      }
    });

    it('changesDispatchedOnlyAfterFlush', 0, async () => {
      const store: PreferencesPort = factory();
      const events: PreferenceChange[] = [];
      store.observeChanges((change: PreferenceChange) => {
        events.push(change);
      });

      store.put('k1', 'v1');
      expect(events.length).assertEqual(0);
      expect(store.hasPendingChanges()).assertTrue();

      const flushed = await store.flush();
      expect(flushed.isOk()).assertTrue();
      expect(events.length).assertEqual(1);
      expect(events[0].key).assertEqual('k1');
      expect(events[0].value).assertEqual('v1');
    });

    it('sameKeyChanges_mergedToLastInOneFlush', 0, async () => {
      const store: PreferencesPort = factory();
      const events: PreferenceChange[] = [];
      store.observeChanges((change: PreferenceChange) => {
        events.push(change);
      });

      store.put('k', 'v1');
      store.put('k', 'v2');
      store.put('k', 'v3');
      await store.flush();

      expect(events.length).assertEqual(1);
      expect(events[0].value).assertEqual('v3');
    });

    it('remove_emitsNullValueEventAfterFlush', 0, async () => {
      const store: PreferencesPort = factory();
      const events: PreferenceChange[] = [];
      store.observeChanges((change: PreferenceChange) => {
        events.push(change);
      });

      store.put('k', 'v');
      await store.flush();
      expect(events.length).assertEqual(1);

      store.remove('k');
      expect(store.getString('k').getOrNull() === null).assertTrue();
      await store.flush();

      expect(events.length).assertEqual(2);
      expect(events[1].key).assertEqual('k');
      expect(events[1].value === null).assertTrue();
    });

    it('remove_absentKey_isNoOpSuccess', 0, () => {
      const store: PreferencesPort = factory();
      expect(store.remove('never-existed').isOk()).assertTrue();
    });

    it('clear_emitsWildcardEvent', 0, async () => {
      const store: PreferencesPort = factory();
      const events: PreferenceChange[] = [];
      store.observeChanges((change: PreferenceChange) => {
        events.push(change);
      });

      store.put('a', 1);
      store.put('b', 2);
      store.clear();
      await store.flush();

      expect(events.length).assertEqual(1);
      expect(events[0].key).assertEqual(PREFERENCES_CLEAR_ALL_KEY);
      expect(events[0].value === null).assertTrue();
      expect(store.getNumber('a').getOrNull() === null).assertTrue();
    });

    it('failedFlush_dispatchesNoEventsAndKeepsPending', 0, async () => {
      const store: PreferencesPort = factory();
      if (!(store instanceof FakePreferencesStore)) {
        return;
      }
      const events: PreferenceChange[] = [];
      store.observeChanges((change: PreferenceChange) => {
        events.push(change);
      });

      store.put('k', 'v');
      store.failNextFlush();
      const failed = await store.flush();
      expect(failed.err).assertTrue();
      expect(events.length).assertEqual(0);
      expect(store.hasPendingChanges()).assertTrue();

      const retry = await store.flush();
      expect(retry.ok).assertTrue();
      expect(events.length).assertEqual(1);
    });

    it('unsubscribe_stopsEvents_andIsIdempotent', 0, async () => {
      const store: PreferencesPort = factory();
      const events: PreferenceChange[] = [];
      const subscription = store.observeChanges((change: PreferenceChange) => {
        events.push(change);
      });

      subscription.unsubscribe();
      expect(subscription.isActive).assertFalse();
      subscription.unsubscribe();

      store.put('k', 'v');
      await store.flush();
      expect(events.length).assertEqual(0);
    });
  });
}
