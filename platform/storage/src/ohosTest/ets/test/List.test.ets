import harmonyPreferencesAdapterDeviceTest from './HarmonyPreferencesAdapter.device.test';
import rdbPreferencesAdapterDeviceTest from './RdbPreferencesAdapter.device.test';

export default function testsuite() {
  harmonyPreferencesAdapterDeviceTest();
  rdbPreferencesAdapterDeviceTest();
}
