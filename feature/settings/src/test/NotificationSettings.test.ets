import { describe, it, expect } from '@ohos/hypium';
import { ScopeNotificationSettings } from '@tgx/core-td-api-generated';
import {
  NOTIFICATIONS_MUTED_FOREVER_SECONDS,
  areNotificationsEnabled,
  isNotificationScopeEnabled,
  withNotificationsEnabled
} from '../main/ets/model/NotificationSettings';

function sampleSettings(muteFor: number): ScopeNotificationSettings {
  const settings: ScopeNotificationSettings = new ScopeNotificationSettings();
  settings.mute_for = muteFor;
  settings.sound_id = '42';
  settings.show_preview = true;
  settings.use_default_mute_stories = true;
  settings.mute_stories = true;
  settings.story_sound_id = '99';
  settings.show_story_poster = true;
  settings.disable_pinned_message_notifications = true;
  settings.disable_mention_notifications = true;
  return settings;
}

export default function notificationSettingsTest(): void {
  describe('NotificationSettingsTest', () => {
    it('withNotificationsEnabled_changesOnlyMuteDuration', 0, () => {
      const source: ScopeNotificationSettings = sampleSettings(120);
      const enabled: ScopeNotificationSettings = withNotificationsEnabled(source, true);

      expect(enabled.mute_for).assertEqual(0);
      expect(enabled.sound_id).assertEqual('42');
      expect(enabled.show_preview).assertTrue();
      expect(enabled.use_default_mute_stories).assertTrue();
      expect(enabled.mute_stories).assertTrue();
      expect(enabled.story_sound_id).assertEqual('99');
      expect(enabled.show_story_poster).assertTrue();
      expect(enabled.disable_pinned_message_notifications).assertTrue();
      expect(enabled.disable_mention_notifications).assertTrue();
      expect(source.mute_for).assertEqual(120);
    });

    it('withNotificationsDisabled_usesTdlibPermanentMute', 0, () => {
      const disabled: ScopeNotificationSettings = withNotificationsEnabled(sampleSettings(0), false);
      expect(disabled.mute_for).assertEqual(NOTIFICATIONS_MUTED_FOREVER_SECONDS);
    });

    it('areNotificationsEnabled_requiresEveryScopeUnmuted', 0, () => {
      const allEnabled: ScopeNotificationSettings[] = [
        sampleSettings(0),
        sampleSettings(0),
        sampleSettings(0)
      ];
      expect(areNotificationsEnabled(allEnabled)).assertTrue();

      const oneMuted: ScopeNotificationSettings[] = [
        sampleSettings(0),
        sampleSettings(10),
        sampleSettings(0)
      ];
      expect(areNotificationsEnabled(oneMuted)).assertFalse();
      expect(areNotificationsEnabled([])).assertFalse();
    });

    it('isNotificationScopeEnabled_reflectsMuteDuration', 0, () => {
      expect(isNotificationScopeEnabled(sampleSettings(0))).assertTrue();
      expect(isNotificationScopeEnabled(sampleSettings(1))).assertFalse();
    });
  });
}
