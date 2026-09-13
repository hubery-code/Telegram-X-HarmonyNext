import settingsReducerTest from './SettingsReducer.test';
import storageSizeTest from './StorageSize.test';

export default function testsuite(): void {
  settingsReducerTest();
  storageSizeTest();
}
