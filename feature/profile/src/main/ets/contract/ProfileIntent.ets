/**
 * feature/profile — 用户资料页意图（PROFILE-101）。
 */

import { Intent } from '@tgx/feature-template';
import { AppError } from '@tgx/core-common';

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

export type ProfileIntent =
  | MessageUserRequested
  | OnProfileLoaded
  | OnBioLoaded
  | OnAvatarFileLoaded
  | OnProfileFailed;
