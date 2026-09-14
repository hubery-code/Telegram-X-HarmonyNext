import { describe, it, expect } from '@ohos/hypium';
import { Result, AppError, PlatformAppError, StorageAppError, base64Decode } from '@tgx/core-common';
import {
  FakeSecureKeyStore,
  FakeSecureRandom,
  SECURE_KEY_STORE_LOCKED_PLATFORM_CODE
} from '@tgx/platform-ports';
import {
  AccountDatabaseKeyManager,
  DB_KEY_BYTES_LENGTH,
  DB_KEY_ALIAS_PREFIX
} from '../main/ets/AccountDatabaseKeyManager';

function unwrap<T>(result: Result<T, AppError>): T {
  if (result.ok) {
    return result.value;
  }
  expect(result.ok).assertTrue();
  throw new Error('unreachable: expected ok result');
}

export default function accountDatabaseKeyManagerTest() {
  describe('AccountDatabaseKeyManagerTest', () => {
    it('firstCreate_generatesAndStoresHighEntropy32BytesKey', 0, async () => {
      const keyStore: FakeSecureKeyStore = new FakeSecureKeyStore();
      const secureRandom: FakeSecureRandom = new FakeSecureRandom();
      const manager: AccountDatabaseKeyManager = new AccountDatabaseKeyManager({
        accountKey: 'user1',
        keyStore: keyStore,
        secureRandom: secureRandom
      });

      expect(manager.keyAlias).assertEqual(`${DB_KEY_ALIAS_PREFIX}user1`);

      const hasBefore: boolean = unwrap(await manager.hasKey());
      expect(hasBefore).assertFalse();

      const created: Uint8Array = unwrap(await manager.getOrCreateKey());
      expect(created.length).assertEqual(DB_KEY_BYTES_LENGTH);

      const hasAfter: boolean = unwrap(await manager.hasKey());
      expect(hasAfter).assertTrue();
    });

    it('restartColdBoot_retrievesSameKeyWithoutRegenerating', 0, async () => {
      const keyStore: FakeSecureKeyStore = new FakeSecureKeyStore();
      const secureRandom: FakeSecureRandom = new FakeSecureRandom();

      // 第一次启动运行
      const manager1: AccountDatabaseKeyManager = new AccountDatabaseKeyManager({
        accountKey: 'user_restart',
        keyStore: keyStore,
        secureRandom: secureRandom
      });
      const firstKey: Uint8Array = unwrap(await manager1.getOrCreateKey());

      // 模拟杀进程冷启动：重新创建 manager 实例
      const manager2: AccountDatabaseKeyManager = new AccountDatabaseKeyManager({
        accountKey: 'user_restart',
        keyStore: keyStore,
        secureRandom: secureRandom
      });
      const secondKey: Uint8Array = unwrap(await manager2.getOrCreateKey());

      expect(secondKey.length).assertEqual(firstKey.length);
      for (let i = 0; i < DB_KEY_BYTES_LENGTH; i++) {
        expect(secondKey[i]).assertEqual(firstKey[i]);
      }
    });

    it('multiAccount_isolation_separateKeysAndAliases', 0, async () => {
      const keyStore: FakeSecureKeyStore = new FakeSecureKeyStore();
      const secureRandom: FakeSecureRandom = new FakeSecureRandom();

      const mgrA: AccountDatabaseKeyManager = new AccountDatabaseKeyManager({
        accountKey: 'acc_a',
        keyStore: keyStore,
        secureRandom: secureRandom
      });
      const mgrB: AccountDatabaseKeyManager = new AccountDatabaseKeyManager({
        accountKey: 'acc_b',
        keyStore: keyStore,
        secureRandom: secureRandom
      });

      expect(mgrA.keyAlias).assertEqual('db_key_acc_a');
      expect(mgrB.keyAlias).assertEqual('db_key_acc_b');

      const keyA: Uint8Array = unwrap(await mgrA.getOrCreateKey());
      const keyB: Uint8Array = unwrap(await mgrB.getOrCreateKey());

      // 两个账号的密钥应当互不相同
      let isDifferent: boolean = false;
      for (let i = 0; i < DB_KEY_BYTES_LENGTH; i++) {
        if (keyA[i] !== keyB[i]) {
          isDifferent = true;
          break;
        }
      }
      expect(isDifferent).assertTrue();
    });

    it('base64Export_validAndDecodableToOriginalBytes', 0, async () => {
      const keyStore: FakeSecureKeyStore = new FakeSecureKeyStore();
      const secureRandom: FakeSecureRandom = new FakeSecureRandom();
      const manager: AccountDatabaseKeyManager = new AccountDatabaseKeyManager({
        accountKey: 'acc_b64',
        keyStore: keyStore,
        secureRandom: secureRandom
      });

      const b64: string = unwrap(await manager.getDatabaseEncryptionKeyBase64());
      expect(b64.length).assertEqual(44);

      const decoded: Uint8Array = base64Decode(b64);
      expect(decoded.length).assertEqual(DB_KEY_BYTES_LENGTH);

      const existing: Uint8Array | null = unwrap(await manager.getExistingKey());
      expect(existing !== null).assertTrue();
      const origin: Uint8Array = existing as Uint8Array;

      for (let i = 0; i < DB_KEY_BYTES_LENGTH; i++) {
        expect(decoded[i]).assertEqual(origin[i]);
      }
    });

    it('destroyKey_removesFromStorage', 0, async () => {
      const keyStore: FakeSecureKeyStore = new FakeSecureKeyStore();
      const secureRandom: FakeSecureRandom = new FakeSecureRandom();
      const manager: AccountDatabaseKeyManager = new AccountDatabaseKeyManager({
        accountKey: 'acc_destroy',
        keyStore: keyStore,
        secureRandom: secureRandom
      });

      await manager.getOrCreateKey();
      const hasBefore: boolean = unwrap(await manager.hasKey());
      expect(hasBefore).assertTrue();

      unwrap(await manager.destroyKey());

      const hasAfter: boolean = unwrap(await manager.hasKey());
      expect(hasAfter).assertFalse();
    });

    it('lockedDevice_returnsLockedErrorAndRecoversOnUnlock', 0, async () => {
      const keyStore: FakeSecureKeyStore = new FakeSecureKeyStore();
      const secureRandom: FakeSecureRandom = new FakeSecureRandom();
      const manager: AccountDatabaseKeyManager = new AccountDatabaseKeyManager({
        accountKey: 'acc_locked',
        keyStore: keyStore,
        secureRandom: secureRandom
      });

      // 模拟锁屏
      keyStore.setLocked(true);
      const lockedRes: Result<Uint8Array, AppError> = await manager.getOrCreateKey();
      expect(lockedRes.ok).assertFalse();
      if (lockedRes.ok === false) {
        expect(lockedRes.error.kind).assertEqual('platform');
        const platErr: PlatformAppError = lockedRes.error as PlatformAppError;
        expect(platErr.retryable).assertTrue();
        expect(platErr.code).assertEqual(SECURE_KEY_STORE_LOCKED_PLATFORM_CODE);
      }

      // 模拟解锁
      keyStore.setLocked(false);
      const unlockedKey: Uint8Array = unwrap(await manager.getOrCreateKey());
      expect(unlockedKey.length).assertEqual(DB_KEY_BYTES_LENGTH);
    });

    it('corruptedKey_returnsCorruptedStorageError', 0, async () => {
      const keyStore: FakeSecureKeyStore = new FakeSecureKeyStore();
      const secureRandom: FakeSecureRandom = new FakeSecureRandom();
      const manager: AccountDatabaseKeyManager = new AccountDatabaseKeyManager({
        accountKey: 'acc_corrupt',
        keyStore: keyStore,
        secureRandom: secureRandom
      });

      // 模拟注入非 32 字节损坏密钥（如 16 字节）
      await keyStore.put('db_key_acc_corrupt', new Uint8Array(16));

      const res: Result<Uint8Array | null, AppError> = await manager.getExistingKey();
      expect(res.ok).assertFalse();
      if (res.ok === false) {
        expect(res.error.kind).assertEqual('storage');
        const storErr: StorageAppError = res.error as StorageAppError;
        expect(storErr.code).assertEqual('corrupted');
      }
    });
  });
}
