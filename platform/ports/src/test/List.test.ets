import fakePreferencesContractTest from './FakePreferencesStore.test';
import fakeSecureKeyStoreContractTest from './FakeSecureKeyStore.test';
import fakeNetworkStateContractTest from './FakeNetworkState.test';
import fakeAppFilesContractTest from './FakeAppFiles.test';
import fakeMonotonicClockContractTest from './FakeMonotonicClock.test';
import fakeClipboardAndToastTest from './FakeClipboardAndToast.test';
import mediaPickerPortTest from './MediaPickerPort.test';

export default function testsuite() {
  fakePreferencesContractTest();
  fakeSecureKeyStoreContractTest();
  fakeNetworkStateContractTest();
  fakeAppFilesContractTest();
  fakeMonotonicClockContractTest();
  fakeClipboardAndToastTest();
  mediaPickerPortTest();
}


