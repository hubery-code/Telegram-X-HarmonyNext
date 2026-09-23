/**
 * feature/profile — 用户资料页意图（PROFILE-101）。
 */

import { Intent } from '@tgx/feature-template';
import { AppError } from '@tgx/core-common';
import { SharedMediaItem, SharedFileItem, SharedLinkItem, SharedGroupItem } from './SharedContentItems';

/** 点「发消息」→ 创建/打开与该用户的私聊。 */
export class MessageUserRequested implements Intent {
  readonly kind: 'messageUserRequested' = 'messageUserRequested';
}

/**
 * 基础信息回灌（getUser 缓存命中或回包）：展示名、用户名、手机号、
 * 在线状态、头像占位。头像文件本地路径经 OnAvatarFileLoaded 单独回灌。
 */
export class OnProfileLoaded implements Intent {
  readonly kind: 'onProfileLoaded' = 'onProfileLoaded';
  readonly displayName: string;
  readonly username: string;
  readonly phone: string;
  readonly statusText: string;
  readonly avatarLetters: string;
  readonly avatarColorIndex: number;

  constructor(
    displayName: string,
    username: string,
    phone: string,
    statusText: string,
    avatarLetters: string,
    avatarColorIndex: number
  ) {
    this.displayName = displayName;
    this.username = username;
    this.phone = phone;
    this.statusText = statusText;
    this.avatarLetters = avatarLetters;
    this.avatarColorIndex = avatarColorIndex;
  }
}

/** getUserFullInfo 回灌：个人简介 bio。 */
export class OnBioLoaded implements Intent {
  readonly kind: 'onBioLoaded' = 'onBioLoaded';
  readonly bio: string;

  constructor(bio: string) {
    this.bio = bio;
  }
}

/** PROFILE-103：emoji 状态回灌（有 emoji status 时为 '✨'，否则空串）。 */
export class OnEmojiStatusLoaded implements Intent {
  readonly kind: 'onEmojiStatusLoaded' = 'onEmojiStatusLoaded';
  readonly emoji: string;

  constructor(emoji: string) {
    this.emoji = emoji;
  }
}

/** 头像文件下载完成/本地路径就绪。 */
export class OnAvatarFileLoaded implements Intent {
  readonly kind: 'onAvatarFileLoaded' = 'onAvatarFileLoaded';
  readonly path: string;

  constructor(path: string) {
    this.path = path;
  }
}

/** 加载失败（getUser / getUserFullInfo 请求级错误）。 */
export class OnProfileFailed implements Intent {
  readonly kind: 'onProfileFailed' = 'onProfileFailed';
  readonly error: AppError;

  constructor(error: AppError) {
    this.error = error;
  }
}

/** PROFILE-103：getUserFullInfo 回灌生日文案（'YYYY年M月D日 (N 岁)'；空串=无生日）。 */
export class OnBirthdayLoaded implements Intent {
  readonly kind: 'onBirthdayLoaded' = 'onBirthdayLoaded';
  readonly birthdayText: string;

  constructor(birthdayText: string) {
    this.birthdayText = birthdayText;
  }
}

/** PROFILE-103：用户点选共享内容 Tab（0 媒体 / 1 文件 / 2 链接 / 3 群组）。 */
export class OnSharedTabSelected implements Intent {
  readonly kind: 'onSharedTabSelected' = 'onSharedTabSelected';
  readonly tab: number;

  constructor(tab: number) {
    this.tab = tab;
  }
}

/** PROFILE-103：用户触发加载更多共享内容（滚动触底或点击加载更多）。 */
export class LoadMoreSharedContent implements Intent {
  readonly kind: 'loadMoreSharedContent' = 'loadMoreSharedContent';
  readonly tab: number;

  constructor(tab: number) {
    this.tab = tab;
  }
}

/**
 * PROFILE-103：searchChatMessages 回灌（Tab 0..2）。
 * media/files/links 为全量缓存：协调器只覆盖本次拉取的 Tab，其余透传旧数组，
 * reducer 原样整体替换并清 sharedLoading。
 */
export class OnSharedContentLoaded implements Intent {
  readonly kind: 'onSharedContentLoaded' = 'onSharedContentLoaded';
  readonly tab: number;
  readonly media: SharedMediaItem[];
  readonly files: SharedFileItem[];
  readonly links: SharedLinkItem[];
  readonly hasMore: boolean;

  constructor(tab: number, media: SharedMediaItem[], files: SharedFileItem[], links: SharedLinkItem[], hasMore: boolean = false) {
    this.tab = tab;
    this.media = media;
    this.files = files;
    this.links = links;
    this.hasMore = hasMore;
  }
}

/** PROFILE-103：getGroupsInCommon 回灌（Tab 3）。 */
export class OnSharedGroupsLoaded implements Intent {
  readonly kind: 'onSharedGroupsLoaded' = 'onSharedGroupsLoaded';
  readonly items: SharedGroupItem[];
  readonly hasMore: boolean;

  constructor(items: SharedGroupItem[], hasMore: boolean = false) {
    this.items = items;
    this.hasMore = hasMore;
  }
}

/**
 * PROFILE-103：某个共享内容 Tab 拉取失败。必须与「确实没有内容」分开，
 * 否则请求挂了页面照样显示「暂无媒体文件」，用户无从知道是没内容还是没拉到。
 */
export class OnSharedContentFailed implements Intent {
  readonly kind: 'onSharedContentFailed' = 'onSharedContentFailed';
  readonly tab: number;

  constructor(tab: number) {
    this.tab = tab;
  }
}

/** PROFILE-103：点共同群组行，跳转进该会话。 */
export class OpenSharedChatRequested implements Intent {
  readonly kind: 'openSharedChatRequested' = 'openSharedChatRequested';
  readonly chatId: number;

  constructor(chatId: number) {
    this.chatId = chatId;
  }
}

/**
 * PROFILE-103 收尾：通知行真实态。点行切换该私聊会话的静音态；
 * reducer 在「未回读到真值」或「写请求在途」时判 no-op，
 * 因此这一击的落点永远是 TDLib 的当前值，不是本地猜的值。
 */
export class NotificationRowTapped implements Intent {
  readonly kind: 'notificationRowTapped' = 'notificationRowTapped';
}

/**
 * getChat.notification_settings / updateChatNotificationSettings 回灌真实静音态。
 * muted 为本会话是否静音（use_default_mute_for=true 视为未静音，与 feature/chat 同口径）。
 */
export class OnChatNotificationLoaded implements Intent {
  readonly kind: 'onChatNotificationLoaded' = 'onChatNotificationLoaded';
  readonly muted: boolean;

  constructor(muted: boolean) {
    this.muted = muted;
  }
}

/** 通知态读不到/写失败：行必须退回「未知」，不能继续显示上一个真值。 */
export class OnChatNotificationFailed implements Intent {
  readonly kind: 'onChatNotificationFailed' = 'onChatNotificationFailed';
}

export type ProfileIntent =
  | MessageUserRequested
  | OnProfileLoaded
  | OnBioLoaded
  | OnEmojiStatusLoaded
  | OnAvatarFileLoaded
  | OnProfileFailed
  | OnBirthdayLoaded
  | OnSharedTabSelected
  | LoadMoreSharedContent
  | OnSharedContentLoaded
  | OnSharedGroupsLoaded
  | OnSharedContentFailed
  | OpenSharedChatRequested
  | NotificationRowTapped
  | OnChatNotificationLoaded
  | OnChatNotificationFailed;
