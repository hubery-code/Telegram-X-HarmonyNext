import { describe, it, expect } from '@ohos/hypium';
import { Result, AppError, ok, err, AppErrors } from '@tgx/core-common';
import { PREFERENCES_CLEAR_ALL_KEY, PreferenceValue } from '@tgx/platform-ports';
import {
  PreferenceStoreCore,
  PreferencePersistence,
  PreferenceWrite
} from '../main/ets/core/PreferenceStoreCore';

class MapPersistence implements PreferencePersistence {
  readonly map: Map<string, PreferenceValue> = new Map();
  readonly batches: PreferenceWrite[][] = [];
  failNext: boolean = false;
  calls: number = 0;

  async persist(writes: PreferenceWrite[]): Promise<Result<void, AppError>> {
    this.calls++;
    if (this.failNext) {
      this.failNext = false;
      return err(AppErrors.storage('io', 'injected persist failure', true));
    }
    this.batches.push(writes);
    for (const write of writes) {
      if (write.kind === 'put') {
        this.map.set(write.key, write.value);
      } else {
        this.map.delete(write.key);
      }
    }
    return ok(undefined);
  }
}

interface StoreFixture {
  readonly core: PreferenceStoreCore;
  readonly persistence: MapPersistence;
}

function newStore(): StoreFixture {
  const persistence: MapPersistence = new MapPersistence();
  const core: PreferenceStoreCore = new PreferenceStoreCore(new Map(), persistence);
  const fixture: StoreFixture = { core: core, persistence: persistence };
  return fixture;
}

export default function preferenceStoreCoreTest() {
  describe('PreferenceStoreCore', () => {
    it('typedPutGet_roundTrips', 0, () => {
      const fixture: StoreFixture = newStore();
      fixture.core.put('s', 'hello');
      fixture.core.put('n', 42);
      fixture.core.put('b', true);

      expect(fixture.core.getString('s').getOrNull()).assertEqual('hello');
      expect(fixture.core.getNumber('n').getOrNull()).assertEqual(42);
      expect(fixture.core.getBoolean('b').getOrNull()).assertTrue();
    });

    it('missingKey_returnsNull', 0, () => {
      const fixture: StoreFixture = newStore();
      expect(fixture.core.getString('absent').getOrNull() === null).assertTrue();
      expect(fixture.core.getNumber('absent').getOrNull() === null).assertTrue();
      expect(fixture.core.getBoolean('absent').getOrNull() === null).assertTrue();
    });

    it('typeMismatch_returnsParameterError', 0, () => {
      const fixture: StoreFixture = newStore();
      fixture.core.put('key', 'text');
      const asNumber = fixture.core.getNumber('key');
      expect(asNumber.err).assertTrue();
      if (asNumber.err) {
        expect(asNumber.error.kind).assertEqual('parameter');
        if (asNumber.error.kind === 'parameter') {
          expect(asNumber.error.code).assertEqual('invalid');
        }
      }
    });

    it('put_validatesKeyAndValue', 0, () => {
      const fixture: StoreFixture = newStore();
      expect(fixture.core.put('', 'v').err).assertTrue();
      const nan = fixture.core.put('nan', NaN);
      expect(nan.err).assertTrue();
      if (nan.err) {
        expect(nan.error.kind).assertEqual('parameter');
      }
      const inf = fixture.core.put('inf', Infinity);
      expect(inf.err).assertTrue();
    });

    it('changesDispatchedOnlyAfterFlush', 0, async () => {
      const fixture: StoreFixture = newStore();
      const keys: string[] = [];
      fixture.core.observeChanges((change) => {
        keys.push(change.key);
      });

      fixture.core.put('k1', 'v1');
      expect(keys.length).assertEqual(0);
      expect(fixture.core.hasPendingChanges()).assertTrue();
      expect(fixture.persistence.calls).assertEqual(0);

      const flushed = await fixture.core.flush();
      expect(flushed.isOk()).assertTrue();
      expect(keys.length).assertEqual(1);
      expect(keys[0]).assertEqual('k1');
      expect(fixture.persistence.map.get('k1')).assertEqual('v1');
    });

    it('sameKeyChanges_mergedToLastInOneFlush', 0, async () => {
      const fixture: StoreFixture = newStore();
      const values: Array<PreferenceValue | null> = [];
      fixture.core.observeChanges((change) => {
        values.push(change.value);
      });

      fixture.core.put('k', 'v1');
      fixture.core.put('k', 'v2');
      fixture.core.put('k', 'v3');
      await fixture.core.flush();

      expect(values.length).assertEqual(1);
      expect(values[0]).assertEqual('v3');
    });

    it('remove_emitsNullValueEventAfterFlush', 0, async () => {
      const fixture: StoreFixture = newStore();
      const events: string[] = [];
      fixture.core.observeChanges((change) => {
        events.push(change.key + '=' + String(change.value));
      });

      fixture.core.put('k', 'v');
      await fixture.core.flush();
      expect(events.length).assertEqual(1);

      fixture.core.remove('k');
      expect(fixture.core.getString('k').getOrNull() === null).assertTrue();
      await fixture.core.flush();

      expect(events.length).assertEqual(2);
      expect(events[1]).assertEqual('k=null');
      expect(fixture.core.hasPendingChanges()).assertFalse();
    });

    it('remove_absentKey_isNoOpSuccess', 0, async () => {
      const fixture: StoreFixture = newStore();
      expect(fixture.core.remove('never-existed').isOk()).assertTrue();
      expect(fixture.core.hasPendingChanges()).assertTrue();
      const flushed = await fixture.core.flush();
      expect(flushed.isOk()).assertTrue();
    });

    it('clear_emitsSingleWildcardEventAndSwallowsKeyEvents', 0, async () => {
      const fixture: StoreFixture = newStore();
      const keys: string[] = [];
      fixture.core.observeChanges((change) => {
        keys.push(change.key);
      });

      fixture.core.put('a', 1);
      fixture.core.put('b', 2);
      fixture.core.clear();
      await fixture.core.flush();

      expect(keys.length).assertEqual(1);
      expect(keys[0]).assertEqual(PREFERENCES_CLEAR_ALL_KEY);
      expect(fixture.core.getNumber('a').getOrNull() === null).assertTrue();
    });

    it('putAfterClear_resumesKeyEvents', 0, async () => {
      const fixture: StoreFixture = newStore();
      const keys: string[] = [];
      fixture.core.observeChanges((change) => {
        keys.push(change.key);
      });

      fixture.core.put('a', 1);
      fixture.core.clear();
      fixture.core.put('c', 3);
      await fixture.core.flush();

      expect(keys.length).assertEqual(1);
      expect(keys[0]).assertEqual('c');
      expect(fixture.core.getNumber('c').getOrNull()).assertEqual(3);
      expect(fixture.core.getNumber('a').getOrNull() === null).assertTrue();
    });

    it('failedFlush_dispatchesNoEventsKeepsPendingAndRetrySucceeds', 0, async () => {
      const fixture: StoreFixture = newStore();
      const keys: string[] = [];
      fixture.core.observeChanges((change) => {
        keys.push(change.key);
      });

      fixture.core.put('k', 'v');
      fixture.persistence.failNext = true;
      const failed = await fixture.core.flush();
      expect(failed.err).assertTrue();
      expect(keys.length).assertEqual(0);
      expect(fixture.core.hasPendingChanges()).assertTrue();
      expect(fixture.persistence.map.has('k')).assertFalse();

      const retry = await fixture.core.flush();
      expect(retry.ok).assertTrue();
      expect(keys.length).assertEqual(1);
      expect(fixture.persistence.map.get('k')).assertEqual('v');
    });

    it('failedClearFlush_keepsWildcardPending', 0, async () => {
      const fixture: StoreFixture = newStore();
      const keys: string[] = [];
      fixture.core.observeChanges((change) => {
        keys.push(change.key);
      });

      fixture.core.put('a', 1);
      await fixture.core.flush();
      fixture.persistence.failNext = true;
      fixture.core.clear();
      const failed = await fixture.core.flush();
      expect(failed.err).assertTrue();
      expect(keys.length).assertEqual(1);

      const retry = await fixture.core.flush();
      expect(retry.ok).assertTrue();
      expect(keys.length).assertEqual(2);
      expect(keys[1]).assertEqual(PREFERENCES_CLEAR_ALL_KEY);
    });

    it('flushWithNoPending_isOkAndSkipsPersistence', 0, async () => {
      const fixture: StoreFixture = newStore();
      const flushed = await fixture.core.flush();
      expect(flushed.isOk()).assertTrue();
      expect(fixture.persistence.calls).assertEqual(0);
    });

    it('unsubscribe_stopsEvents_andIsIdempotent', 0, async () => {
      const fixture: StoreFixture = newStore();
      const keys: string[] = [];
      const subscription = fixture.core.observeChanges((change) => {
        keys.push(change.key);
      });

      subscription.unsubscribe();
      expect(subscription.isActive).assertFalse();
      subscription.unsubscribe();

      fixture.core.put('k', 'v');
      await fixture.core.flush();
      expect(keys.length).assertEqual(0);
    });

    it('initialData_isVisibleImmediately', 0, () => {
      const initial: Map<string, PreferenceValue> = new Map();
      initial.set('theme', 'dark');
      const core: PreferenceStoreCore = new PreferenceStoreCore(initial, new MapPersistence());
      expect(core.getString('theme').getOrNull()).assertEqual('dark');
    });
  });
}
