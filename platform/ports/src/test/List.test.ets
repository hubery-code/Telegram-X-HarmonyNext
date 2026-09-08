import fakePreferencesContractTest from './FakePreferencesStore.test';
import fakeSecureKeyStoreContractTest from './FakeSecureKeyStore.test';
import fakeNetworkStateContractTest from './FakeNetworkState.test';
import fakeAppFilesContractTest from './FakeAppFiles.test';
import fakeMonotonicClockContractTest from './FakeMonotonicClock.test';

export default function testsuite() {
  fakePreferencesContractTest();
  fakeSecureKeyStoreContractTest();
  fakeNetworkStateContractTest();
  fakeAppFilesContractTest();
  fakeMonotonicClockContractTest();
}
