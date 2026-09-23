/**
 * feature/chat — 会话级通知静音的纯函数模型（SET-106）。
 *
 * TDLib 的 chatNotificationSettings 用「剩余静音秒数」表达静音：mute_for 超过 366 天
 * 即视为永久静音，因此这里统一写 Int32 最大值（与 feature/settings 的
 * NOTIFICATIONS_MUTED_FOREVER_SECONDS 同值），避免同一功能两套「永久」口径。
 *
 * 关键约束：sound_id / story_sound_id 是 int64（本项目建模为 string），空串会被
 * TDLib JSON 解析拒绝（bad_request）。写请求必须携带可解析的值，故一律以当前设置
 * 为底本、只改 mute_for，其余字段原样回传。
 */

import { ChatNotificationSettings } from '@tgx/core-td-api-generated';

export const CHAT_MUTE_FOREVER_SECONDS: number = 2147483647;

/** 本会话是否处于静音态（use_default_mute_for=true 时静音由分区设置决定）。 */
export function isChatMuted(settings: ChatNotificationSettings | null): boolean {
  if (settings === null) {
    return false;
  }
  if (settings.use_default_mute_for) {
    return false;
  }
  return settings.mute_for > 0;
}

/**
 * 以当前设置为底本生成「静音/取消静音」后的新设置；只覆盖 mute_for 与
 * use_default_mute_for，声音/预览/故事/提及等保持用户原值。
 * 底本缺失（尚未拿到 getChat 响应）时退化为「其余全部走默认」，
 * 但 int64 字段仍写 '0' 而不是空串。
 */
export function withChatMuteFor(
  source: ChatNotificationSettings | null,
  muted: boolean
): ChatNotificationSettings {
  const next: ChatNotificationSettings = new ChatNotificationSettings();
  if (source !== null) {
    next.use_default_sound = source.use_default_sound;
    next.sound_id = source.sound_id;
    next.use_default_show_preview = source.use_default_show_preview;
    next.show_preview = source.show_preview;
    next.use_default_mute_stories = source.use_default_mute_stories;
    next.mute_stories = source.mute_stories;
    next.use_default_story_sound = source.use_default_story_sound;
    next.story_sound_id = source.story_sound_id;
    next.use_default_show_story_poster = source.use_default_show_story_poster;
    next.show_story_poster = source.show_story_poster;
    next.use_default_disable_pinned_message_notifications =
      source.use_default_disable_pinned_message_notifications;
    next.disable_pinned_message_notifications = source.disable_pinned_message_notifications;
    next.use_default_disable_mention_notifications = source.use_default_disable_mention_notifications;
    next.disable_mention_notifications = source.disable_mention_notifications;
  } else {
    next.use_default_sound = true;
    next.sound_id = '0';
    next.use_default_show_preview = true;
    next.use_default_mute_stories = true;
    next.use_default_story_sound = true;
    next.story_sound_id = '0';
    next.use_default_show_story_poster = true;
    next.use_default_disable_pinned_message_notifications = true;
    next.use_default_disable_mention_notifications = true;
  }
  next.use_default_mute_for = false;
  next.mute_for = muted ? CHAT_MUTE_FOREVER_SECONDS : 0;
  return next;
}
