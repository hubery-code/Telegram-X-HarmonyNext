/**
 * core/domain — 会话通知静音纯函数模型单元测试（SET-106 用例随模型下沉而迁移）。
 *
 * 守住的回归：
 * 1. 写请求不得把 int64（sound_id / story_sound_id）写成空串 —— TDLib 直接判 bad_request；
 * 2. 以回读快照为底本时只覆盖 mute_for，其余用户设置原样带回；
 * 3. use_default_mute_for=true 时静音由分区设置决定，本会话不认成静音。
 */

import { describe, it, expect } from '@ohos/hypium';
import { ChatNotificationSettings } from '@tgx/core-td-api-generated';
import { CHAT_MUTE_FOREVER_SECONDS, isChatMuted, withChatMuteFor } from '../../main/ets/chat/ChatMute';

function settingsOf(muteFor: number, useDefaultMuteFor: boolean = false): ChatNotificationSettings {
  const settings: ChatNotificationSettings = new ChatNotificationSettings();
  settings.use_default_mute_for = useDefaultMuteFor;
  settings.mute_for = muteFor;
  settings.use_default_sound = true;
  settings.sound_id = '0';
  settings.use_default_show_preview = false;
  settings.show_preview = true;
  settings.use_default_mute_stories = true;
  settings.use_default_story_sound = true;
  settings.story_sound_id = '0';
  settings.use_default_show_story_poster = true;
  settings.use_default_disable_pinned_message_notifications = true;
  settings.use_default_disable_mention_notifications = true;
  return settings;
}

export default function chatMuteTest(): void {
  describe('ChatMuteTest', () => {

    it('isChatMuted_readsMuteForAndHonoursUseDefaultFlag', 0, () => {
      expect(isChatMuted(null)).assertFalse();
      expect(isChatMuted(settingsOf(0))).assertFalse();
      expect(isChatMuted(settingsOf(CHAT_MUTE_FOREVER_SECONDS))).assertTrue();
      expect(isChatMuted(settingsOf(3600, true))).assertFalse();
    });

    it('withChatMuteFor_keepsInt64SoundFieldsParseable', 0, () => {
      const muted: ChatNotificationSettings = withChatMuteFor(null, true);
      expect(muted.mute_for).assertEqual(CHAT_MUTE_FOREVER_SECONDS);
      expect(muted.use_default_mute_for).assertFalse();
      // 回归点：空串会让 TDLib 直接判 bad_request，int64 字段必须可解析。
      expect(muted.sound_id).assertEqual('0');
      expect(muted.story_sound_id).assertEqual('0');
    });

    it('withChatMuteFor_overridesOnlyMuteForOnSnapshot', 0, () => {
      const source: ChatNotificationSettings = settingsOf(0);
      source.use_default_show_preview = false;
      source.show_preview = false;
      source.disable_mention_notifications = true;
      const next: ChatNotificationSettings = withChatMuteFor(source, true);
      expect(next.mute_for).assertEqual(CHAT_MUTE_FOREVER_SECONDS);
      expect(next.show_preview).assertFalse();
      expect(next.disable_mention_notifications).assertTrue();
      const unmuted: ChatNotificationSettings = withChatMuteFor(source, false);
      expect(unmuted.mute_for).assertEqual(0);
      expect(unmuted.use_default_mute_for).assertFalse();
    });
  });
}
