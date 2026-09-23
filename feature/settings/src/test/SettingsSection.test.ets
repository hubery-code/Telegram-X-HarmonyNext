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

    it('cards_dataStorageSectionShowsOnlyStorageCard', 0, () => {
      const cards = settingsCardsForSection('data_and_storage');
      expect(cards.length).assertEqual(1);
      expect(sectionShowsCard('data_and_storage', 'storage')).assertTrue();
      expect(sectionShowsCard('data_and_storage', 'logout')).assertFalse();
    });

    it('cards_allSectionShowsEveryBlock', 0, () => {
      expect(settingsCardsForSection('all').length).assertEqual(8);
      expect(sectionShowsCard('all', 'logout')).assertTrue();
    });
  });
}
