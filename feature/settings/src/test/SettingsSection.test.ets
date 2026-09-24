import { describe, it, expect } from '@ohos/hypium';
import {
  parseSettingsSection,
  settingsSectionTitleKey,
  settingsCardsForSection,
  sectionShowsCard
} from '../main/ets/model/SettingsSection';

export default function settingsSectionTest(): void {
  describe('SettingsSection', () => {
    it('parse_acceptsKnownSections', 0, () => {
      expect(parseSettingsSection('notifications')).assertEqual('notifications');
      expect(parseSettingsSection('data_and_storage')).assertEqual('data_and_storage');
    });

    it('parse_fallsBackToAllForUnknownOrEmpty', 0, () => {
      // 'devices' 由 reducer 转成打开活跃会话子页，不是一种分区渲染。
      expect(parseSettingsSection('devices')).assertEqual('all');
      expect(parseSettingsSection('privacy_and_security')).assertEqual('all');
      expect(parseSettingsSection('')).assertEqual('all');
      expect(parseSettingsSection('NoPe')).assertEqual('all');
    });

    it('titleKey_mapsSectionToHeading', 0, () => {
      expect(settingsSectionTitleKey('all')).assertEqual('Settings');
      expect(settingsSectionTitleKey('notifications')).assertEqual('NOTIFICATIONS');
      expect(settingsSectionTitleKey('data_and_storage')).assertEqual('DATA AND STORAGE');
    });

    it('cards_notificationSectionShowsOnlyNotificationsCard', 0, () => {
      const cards = settingsCardsForSection('notifications');
      expect(cards.length).assertEqual(1);
      expect(cards[0]).assertEqual('notifications');
      expect(sectionShowsCard('notifications', 'storage')).assertFalse();
      expect(sectionShowsCard('notifications', 'profile')).assertFalse();
    });

    it('cards_dataStorageSectionShowsStorageAutoDownloadAndProxy', 0, () => {
      // PROXY-101：TGX 把「代理」归在 Data and Storage 的 Connection 组。
      // AUTODL-101：自动下载同样是 TGX 在该页的 AutomaticMediaDownload 组。
      const cards = settingsCardsForSection('data_and_storage');
      expect(cards.length).assertEqual(3);
      expect(cards[0]).assertEqual('storage');
      expect(cards[1]).assertEqual('auto_download');
      expect(cards[2]).assertEqual('proxy');
      expect(sectionShowsCard('data_and_storage', 'logout')).assertFalse();
    });

    it('cards_autoDownloadCardOnlyInDataStorageAndAll', 0, () => {
      expect(sectionShowsCard('data_and_storage', 'auto_download')).assertTrue();
      expect(sectionShowsCard('all', 'auto_download')).assertTrue();
      expect(sectionShowsCard('notifications', 'auto_download')).assertFalse();
    });

    it('cards_proxyCardOnlyInDataStorageAndAll', 0, () => {
      expect(sectionShowsCard('data_and_storage', 'proxy')).assertTrue();
      expect(sectionShowsCard('all', 'proxy')).assertTrue();
      expect(sectionShowsCard('notifications', 'proxy')).assertFalse();
    });

    it('cards_allSectionShowsEveryBlock', 0, () => {
      expect(settingsCardsForSection('all').length).assertEqual(11);
      expect(sectionShowsCard('all', 'logout')).assertTrue();
      // SELF-102：隐私行只在完整设置页出现，不单独成区（落点是整屏子页）。
      expect(sectionShowsCard('all', 'privacy')).assertTrue();
      expect(sectionShowsCard('notifications', 'privacy')).assertFalse();
      expect(sectionShowsCard('data_and_storage', 'privacy')).assertFalse();
    });
  });
}
