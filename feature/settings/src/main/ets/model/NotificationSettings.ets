import { ScopeNotificationSettings } from '@tgx/core-td-api-generated';

export const NOTIFICATIONS_MUTED_FOREVER_SECONDS: number = 2147483647;
export type NotificationScopeKey = 'private' | 'group' | 'channel';

/**
 * Copy one TDLib scope setting while changing only the global mute duration.
 * Sound, preview, story, mention and pinned-message preferences are preserved.
 */
export function withNotificationsEnabled(
  source: ScopeNotificationSettings,
  enabled: boolean
): ScopeNotificationSettings {
  const next: ScopeNotificationSettings = new ScopeNotificationSettings();
  next.mute_for = enabled ? 0 : NOTIFICATIONS_MUTED_FOREVER_SECONDS;
  next.sound_id = source.sound_id;
  next.show_preview = source.show_preview;
  next.use_default_mute_stories = source.use_default_mute_stories;
  next.mute_stories = source.mute_stories;
  next.story_sound_id = source.story_sound_id;
  next.show_story_poster = source.show_story_poster;
  next.disable_pinned_message_notifications = source.disable_pinned_message_notifications;
  next.disable_mention_notifications = source.disable_mention_notifications;
  return next;
}

/** Global notifications are enabled only when every TDLib chat scope is unmuted. */
export function areNotificationsEnabled(settings: readonly ScopeNotificationSettings[]): boolean {
  if (settings.length === 0) {
    return false;
  }
  for (let i = 0; i < settings.length; i++) {
    if (settings[i].mute_for > 0) {
      return false;
    }
  }
  return true;
}

export function isNotificationScopeEnabled(settings: ScopeNotificationSettings): boolean {
  return settings.mute_for <= 0;
}
