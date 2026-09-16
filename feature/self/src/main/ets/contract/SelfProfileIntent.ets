/**
 * feature/self — 我的资料页意图（SELF-101）。
 */

import { Intent } from '@tgx/feature-template';
import { AppError } from '@tgx/core-common';

/**
 * 资料帧回灌（getMe + getUserFullInfo 组帧）：展示名、用户名、手机号、
 * 生日文案、个人简介、在线状态、头像占位。头像文件本地路径经
 * OnAvatarFileLoaded 单独回灌。
 */
export class OnProfileLoaded implements Intent {
  readonly kind: 'onProfileLoaded' = 'onProfileLoaded';
  readonly displayName: string;
  readonly username: string;
  readonly phone: string;
  readonly birthdayText: string;
  readonly bio: string;
  readonly statusText: string;
  readonly avatarLetters: string;
  readonly avatarColorIndex: number;

  constructor(
    displayName: string,
    username: string,
    phone: string,
    birthdayText: string,
    bio: string,
    statusText: string,
    avatarLetters: string,
    avatarColorIndex: number
  ) {
    this.displayName = displayName;
    this.username = username;
    this.phone = phone;
    this.birthdayText = birthdayText;
    this.bio = bio;
    this.statusText = statusText;
    this.avatarLetters = avatarLetters;
    this.avatarColorIndex = avatarColorIndex;
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

/** 加载失败（getMe / getUserFullInfo 请求级错误）。 */
export class OnProfileFailed implements Intent {
  readonly kind: 'onProfileFailed' = 'onProfileFailed';
  readonly error: AppError;

  constructor(error: AppError) {
    this.error = error;
  }
}

/** 右下角 ✎ FAB：编辑资料（SELF-101 仅打日志占位）。 */
export class EditTapped implements Intent {
  readonly kind: 'editTapped' = 'editTapped';
}

/** 设置入口组点击（devices / notifications / data_and_storage / privacy_and_security）。 */
export class SettingsSectionTapped implements Intent {
  readonly kind: 'settingsSectionTapped' = 'settingsSectionTapped';
  readonly section: string;

  constructor(section: string) {
    this.section = section;
  }
}

export type SelfProfileIntent =
  | OnProfileLoaded
  | OnAvatarFileLoaded
  | OnProfileFailed
  | EditTapped
  | SettingsSectionTapped;
