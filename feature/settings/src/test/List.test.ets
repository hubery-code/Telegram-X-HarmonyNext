import settingsReducerTest from './SettingsReducer.test';
import storageSizeTest from './StorageSize.test';
import settingsThemeTest from './SettingsTheme.test';

export default function testsuite(): void {
  settingsReducerTest();
  storageSizeTest();
  settingsThemeTest();
}
