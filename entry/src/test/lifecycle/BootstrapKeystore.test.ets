import { describe, it, expect } from '@ohos/hypium';
import { Result, AppError, base64Decode } from '@tgx/core-common';
import { FakeSecureKeyStore, FakeSecureRandom, FakeNetworkState, FakeAppFiles } from '@tgx/platform-ports';
import { TdlibParametersConfig } from '@tgx/feature-auth';
import { bootstrap, BootstrapResult } from '../../main/ets/Bootstrap';
import { FakeAccountBridge } from './FakeAccountBridge';

function unwrap<T>(result: Result<T, AppError>): T {
  if (result.ok) {
    return result.value;
  }
  expect(result.ok).assertTrue();
  throw new Error('unreachable: expected ok result');
}

export default function bootstrapKeystoreTest() {
  describe('BootstrapKeystoreIntegrationTest', () => {
    it('bootstrap_injectsKeyStoreAndInitializesHighEntropyDatabaseKey', 0, async () => {
      const keyStore: FakeSecureKeyStore = new FakeSecureKeyStore();
      const secureRandom: FakeSecureRandom = new FakeSecureRandom();
      const network: FakeNetworkState = new FakeNetworkState();
      const bridge: FakeAccountBridge = new FakeAccountBridge();
      const files: FakeAppFiles = new FakeAppFiles();

      const tdlibParams: TdlibParametersConfig = {
        apiId: 1000,
        apiHash: 'test_hash',
        databaseDirectory: '/data/storage/el2/base/files/tdlib/db',
        filesDirectory: '/data/storage/el2/base/files/tdlib/files',
        systemLanguageCode: 'en',
        deviceModel: 'Test Device',
        applicationVersion: '1.0.0',
        useTestDc: false
      };

      const result: BootstrapResult = bootstrap(
        '/data/storage/el2/base/files',
        '/data/storage/el2/base/cache',
        tdlibParams,
        network,
        keyStore,
        secureRandom,
        bridge,
        files
      );

      // 验证 primary scope 已成功挂载 databaseKeyManager
      expect(result.scope.databaseKeyManager !== null).assertTrue();

      // 获取 Base64 密钥
      const keyBase64Res: Result<string, AppError> = await result.scope.getDatabaseEncryptionKeyBase64();
      expect(keyBase64Res.ok).assertTrue();
      const keyBase64: string = unwrap(keyBase64Res);
      expect(keyBase64.length).assertEqual(44);

      const decoded: Uint8Array = base64Decode(keyBase64);
      expect(decoded.length).assertEqual(32);

      // 验证 FakeSecureKeyStore 中已持久化该密钥
      const storedRes: Result<Uint8Array | null, AppError> = await keyStore.get(`db_key_${result.scope.accountKey}`);
      expect(storedRes.ok).assertTrue();
      const storedKeyNullable: Uint8Array | null = unwrap(storedRes);
      expect(storedKeyNullable !== null).assertTrue();
      const storedKey: Uint8Array = storedKeyNullable as Uint8Array;
      expect(storedKey.length).assertEqual(32);

      for (let i = 0; i < 32; i++) {
        expect(storedKey[i]).assertEqual(decoded[i]);
      }

      result.coordinator.destroy();
      result.lifecycle.onDestroy();
    });
  });
}
