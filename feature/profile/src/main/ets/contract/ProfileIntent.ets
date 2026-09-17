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

export type ProfileIntent =
  | MessageUserRequested
  | OnProfileLoaded
  | OnBioLoaded
  | OnAvatarFileLoaded
  | OnProfileFailed
  | OnBirthdayLoaded
  | OnSharedTabSelected
  | LoadMoreSharedContent
  | OnSharedContentLoaded
  | OnSharedGroupsLoaded;
