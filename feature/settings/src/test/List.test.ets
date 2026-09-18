import settingsReducerTest from './SettingsReducer.test';
import storageSizeTest from './StorageSize.test';
import settingsThemeTest from './SettingsTheme.test';
import notificationSettingsTest from './NotificationSettings.test';
import devicesSubPageTest from './DevicesSubPage.test';

export default function testsuite(): void {
  settingsReducerTest();
  storageSizeTest();
  settingsThemeTest();
  notificationSettingsTest();
  devicesSubPageTest();
}
