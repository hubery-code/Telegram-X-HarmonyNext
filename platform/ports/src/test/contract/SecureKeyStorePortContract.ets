/**
 * platform/ports — SecureKeyStorePort 同套契约测试（PLAT-001）。
 *
 * 任何 SecureKeyStorePort 实现（当前 FakeSecureKeyStore，未来 PLAT-003 的
 * Asset Store/HUKS adapter）都通过 `secureKeyStorePortContract('name', factory)`
 * 套用同一组断言。锁屏/不可用语义通过可选的 driver 钩子驱动；
 * 不支持该能力的实现传 undefined，对应用例自动跳过。
 */

import { describe, it, expect } from '@ohos/hypium';
import { SECURE_KEY_STORE_LOCKED_PLATFORM_CODE, SecureKeyStorePort } from '../../main/ets/SecureKeyStorePort';
import { FakeSecureKeyStore } from '../../main/ets/fakes/FakeSecureKeyStore';

export interface SecureKeyStoreDriver {
  setLocked(locked: boolean): void;
  setAvailable(available: boolean): void;
}

export default function secureKeyStorePortContract(
  name: string,
  factory: () => SecureKeyStorePort,
  driverFor?: (store: SecureKeyStorePort) => SecureKeyStoreDriver | undefined
) {
  describe(`${name}_SecureKeyStorePortContract`, () => {
    it('putGet_roundTripsBinaryValue', 0, async () => {
      const store: SecureKeyStorePort = factory();
      const original: Uint8Array = new Uint8Array([1, 2, 3, 255, 0]);
      const put = await store.put('tdlib-db-key', original);
      expect(put.ok).assertTrue();

      const got = await store.get('tdlib-db-key');
      expect(got.ok).assertTrue();
      if (got.ok && got.value !== null) {
        expect(got.value.length).assertEqual(5);
        expect(got.value[3]).assertEqual(255);
        // 拷贝语义：修改返回值不得影响存储值
        got.value[0] = 99;
      }
      const again = await store.get('tdlib-db-key');
      if (again.ok && again.value !== null) {
        expect(again.value[0]).assertEqual(1);
      }
    });

    it('get_missingKey_returnsNull', 0, async () => {
      const store: SecureKeyStorePort = factory();
      const got = await store.get('never-written');
      expect(got.ok).assertTrue();
      if (got.ok) {
        expect(got.value === null).assertTrue();
      }
    });

    it('put_overwritesExistingValue', 0, async () => {
      const store: SecureKeyStorePort = factory();
      await store.put('k', new Uint8Array([1]));
      await store.put('k', new Uint8Array([2, 3]));
      const got = await store.get('k');
      if (got.ok && got.value !== null) {
        expect(got.value.length).assertEqual(2);
        expect(got.value[1]).assertEqual(3);
      } else {
        expect(false).assertTrue();
      }
    });

    it('remove_isIdempotentAndActuallyRemoves', 0, async () => {
      const store: SecureKeyStorePort = factory();
      await store.put('k', new Uint8Array([7]));
      const first = await store.remove('k');
      expect(first.ok).assertTrue();
      const second = await store.remove('k');
      expect(second.ok).assertTrue();
      const got = await store.get('k');
      if (got.ok) {
        expect(got.value === null).assertTrue();
      } else {
        expect(false).assertTrue();
      }
    });

    it('status_reportsAvailableByDefault', 0, async () => {
      const store: SecureKeyStorePort = factory();
      const status = store.getStatus();
      expect(status.ok).assertTrue();
      if (status.ok) {
        expect(status.value.availability).assertEqual('available');
      }
      const available = store.isAvailable();
      if (available.ok) {
        expect(available.value).assertTrue();
      } else {
        expect(false).assertTrue();
      }
    });

    it('lockedBlocksAccessWithRetryableError', 0, async () => {
      const store: SecureKeyStorePort = factory();
      const driver: SecureKeyStoreDriver | undefined = driverFor ? driverFor(store) : undefined;
      if (driver === undefined) {
        return;
      }
      await store.put('k', new Uint8Array([1]));

      driver.setLocked(true);
      const status = store.getStatus();
      if (status.ok) {
        expect(status.value.availability).assertEqual('locked');
      } else {
        expect(false).assertTrue();
      }

      const got = await store.get('k');
      expect(got.err).assertTrue();
      if (got.err) {
        expect(got.error.kind).assertEqual('platform');
        if (got.error.kind === 'platform') {
          expect(got.error.code).assertEqual(SECURE_KEY_STORE_LOCKED_PLATFORM_CODE);
          expect(got.error.retryable).assertTrue();
        }
      }
      const put = await store.put('k2', new Uint8Array([2]));
      expect(put.err).assertTrue();
      const remove = await store.remove('k');
      expect(remove.err).assertTrue();

      // 解锁后同一数据可访问
      driver.setLocked(false);
      const afterUnlock = await store.get('k');
      expect(afterUnlock.ok).assertTrue();
      if (afterUnlock.ok) {
        expect(afterUnlock.value !== null).assertTrue();
      }
    });

    it('unavailableBlocksAccessWithNonRetryableError', 0, async () => {
      const store: SecureKeyStorePort = factory();
      const driver: SecureKeyStoreDriver | undefined = driverFor ? driverFor(store) : undefined;
      if (driver === undefined) {
        return;
      }
      driver.setAvailable(false);
      const status = store.getStatus();
      if (status.ok) {
        expect(status.value.availability).assertEqual('unavailable_no_hardware');
      } else {
        expect(false).assertTrue();
      }
      const available = store.isAvailable();
      if (available.ok) {
        expect(available.value).assertFalse();
      }
      const got = await store.get('anything');
      expect(got.err).assertTrue();
      if (got.err && got.error.kind === 'platform') {
        expect(got.error.retryable).assertFalse();
      }
    });

    it('lockedErrorMessages_doNotLeakStoredValues', 0, async () => {
      const store: SecureKeyStorePort = factory();
      const secret: Uint8Array = new Uint8Array([83, 69, 67, 82, 69, 84]);
      await store.put('k', secret);
      const driver: SecureKeyStoreDriver | undefined = driverFor ? driverFor(store) : undefined;
      if (driver === undefined) {
        return;
      }
      driver.setLocked(true);
      const got = await store.get('k');
      if (got.err) {
        // 'SECRET' 的 ASCII 不得出现在任何诊断字段
        expect(got.error.message.indexOf('SECRET') < 0).assertTrue();
        const cause: string | undefined = got.error.cause;
        expect(cause === undefined || cause.indexOf('SECRET') < 0).assertTrue();
      }
    });
  });
}
