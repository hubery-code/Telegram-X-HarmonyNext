import settingsReducerTest from './SettingsReducer.test';
import storageSizeTest from './StorageSize.test';
import settingsThemeTest from './SettingsTheme.test';
import notificationSettingsTest from './NotificationSettings.test';
import privacySettingsTest from './PrivacySettings.test';
import devicesSubPageTest from './DevicesSubPage.test';
import settingsSectionTest from './SettingsSection.test';
import proxySettingsTest from './ProxySettings.test';
import autoDownloadRowsTest from './AutoDownloadRows.test';
import dataSaverRowsTest from './DataSaverRows.test';
import downloadLimitRowsTest from './DownloadLimitRows.test';

export default function testsuite(): void {
  settingsReducerTest();
  storageSizeTest();
  settingsThemeTest();
  notificationSettingsTest();
  privacySettingsTest();
  devicesSubPageTest();
  settingsSectionTest();
  proxySettingsTest();
  autoDownloadRowsTest();
  dataSaverRowsTest();
  downloadLimitRowsTest();
}
