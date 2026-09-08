import secureKeyStorePortContract, { SecureKeyStoreDriver } from './contract/SecureKeyStorePortContract';
import { FakeSecureKeyStore } from '../main/ets/fakes/FakeSecureKeyStore';
import { SecureKeyStorePort } from '../main/ets/SecureKeyStorePort';

export default function fakeSecureKeyStoreContractTest() {
  secureKeyStorePortContract(
    'FakeSecureKeyStore',
    () => new FakeSecureKeyStore(),
    (store: SecureKeyStorePort): SecureKeyStoreDriver | undefined => {
      if (store instanceof FakeSecureKeyStore) {
        return store;
      }
      return undefined;
    }
  );
}
