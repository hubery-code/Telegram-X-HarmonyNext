/**
 * feature/profile — 用户资料页 UI 状态（PROFILE-101；PROFILE-103 扩展共享内容区）。
 *
 * 不可变 + copyWith，对齐 feature/chat 的 ChatUiState 约定。
 * PROFILE-103 新增字段全部带默认值并置于构造末尾，保持旧调用点兼容。
 */

import { SharedMediaItem, SharedFileItem, SharedLinkItem, SharedGroupItem } from './SharedContentItems';

export interface ProfileUiStateOptions {
  userId?: number;
  /** 展示名：first + last 拼接。 */
  displayName?: string;
  /** '@username'；无用户名为空串。 */
  username?: string;
  /** 手机号（E.164 原样）；无则空串。 */
  phone?: string;
  /** 个人简介 bio；无则空串。 */
  bio?: string;
  /** 在线状态文案：'online' / 'last seen ...' / ''。 */
  statusText?: string;
  /** 大头像本地路径（已下载）；否则 null 出彩色字母底。 */
  avatarPath?: string | null;
  /** 头像占位字母（1-2 个）。 */
  avatarLetters?: string;
  /** 头像/署名调色板索引（0..6），用于无头像时的彩色底。 */
  avatarColorIndex?: number;
  isLoading?: boolean;
  errorMessage?: string | null;
  /** 生日文案：'YYYY年M月D日 (N 岁)'；无生日为空串。 */
  birthdayText?: string;
  /** 通知状态文案（占位，默认 '开启'）。 */
  notificationText?: string;
  /** 共享内容当前选中 Tab：0 媒体 / 1 文件 / 2 链接 / 3 群组。 */
  activeSharedTab?: number;
  /** 共享媒体条目（已加载的缓存页）。 */
  sharedMedia?: SharedMediaItem[];
  /** 共享文件条目。 */
  sharedFiles?: SharedFileItem[];
  /** 共享链接条目。 */
  sharedLinks?: SharedLinkItem[];
  /** 共同群组条目。 */
  sharedGroups?: SharedGroupItem[];
  /** 共享内容加载中（切 Tab 触发请求后为 true，回灌后 false）。 */
  sharedLoading?: boolean;
  /** 当前共享内容 Tab 是否有更多数据可拉取（分页支持）。 */
  sharedHasMore?: boolean;
  /** 共享内容加载更多中（滚动或点击加载更多后为 true）。 */
  sharedLoadingMore?: boolean;
  /** PROFILE-103：emoji 状态角标（custom_emoji 无法渲染时以 '✨' 占位）。 */
  emojiStatusEmoji?: string;
  /** 默认 Tab 的首屏共享内容是否已发起过请求（只发一次，避免订阅回灌反复拉取）。 */
  sharedInitialRequested?: boolean;
  /** 当前 Tab 的共享内容请求失败（与「确实没有内容」区分开，否则页面在撒谎）。 */
  sharedLoadFailed?: boolean;
}

export class ProfileUiState {
  readonly userId: number;
  readonly displayName: string;
  readonly username: string;
  readonly phone: string;
  readonly bio: string;
  readonly statusText: string;
  readonly avatarPath: string | null;
  readonly avatarLetters: string;
  readonly avatarColorIndex: number;
  readonly isLoading: boolean;
  readonly errorMessage: string | null;
  readonly birthdayText: string;
  readonly notificationText: string;
  readonly activeSharedTab: number;
  readonly sharedMedia: SharedMediaItem[];
  readonly sharedFiles: SharedFileItem[];
  readonly sharedLinks: SharedLinkItem[];
  readonly sharedGroups: SharedGroupItem[];
  readonly sharedLoading: boolean;
  readonly sharedHasMore: boolean;
  readonly sharedLoadingMore: boolean;
  readonly emojiStatusEmoji: string;
  readonly sharedInitialRequested: boolean;
  readonly sharedLoadFailed: boolean;

  constructor(
    userId: number = 0,
    displayName: string = '',
    username: string = '',
    phone: string = '',
    bio: string = '',
    statusText: string = '',
    avatarPath: string | null = null,
    avatarLetters: string = '',
    avatarColorIndex: number = 0,
    isLoading: boolean = true,
    errorMessage: string | null = null,
    birthdayText: string = '',
    notificationText: string = '开启',
    activeSharedTab: number = 0,
    sharedMedia: SharedMediaItem[] = [],
    sharedFiles: SharedFileItem[] = [],
    sharedLinks: SharedLinkItem[] = [],
    sharedGroups: SharedGroupItem[] = [],
    sharedLoading: boolean = false,
    sharedHasMore: boolean = true,
    sharedLoadingMore: boolean = false,
    emojiStatusEmoji: string = '',
    sharedInitialRequested: boolean = false,
    sharedLoadFailed: boolean = false
  ) {
    this.userId = userId;
    this.displayName = displayName;
    this.username = username;
    this.phone = phone;
    this.bio = bio;
    this.statusText = statusText;
    this.avatarPath = avatarPath;
    this.avatarLetters = avatarLetters;
    this.avatarColorIndex = avatarColorIndex;
    this.isLoading = isLoading;
    this.errorMessage = errorMessage;
    this.birthdayText = birthdayText;
    this.notificationText = notificationText;
    this.activeSharedTab = activeSharedTab;
    this.sharedMedia = sharedMedia;
    this.sharedFiles = sharedFiles;
    this.sharedLinks = sharedLinks;
    this.sharedGroups = sharedGroups;
    this.sharedLoading = sharedLoading;
    this.sharedHasMore = sharedHasMore;
    this.sharedLoadingMore = sharedLoadingMore;
    this.emojiStatusEmoji = emojiStatusEmoji;
    this.sharedInitialRequested = sharedInitialRequested;
    this.sharedLoadFailed = sharedLoadFailed;
  }

  static initial(userId: number = 0): ProfileUiState {
    return new ProfileUiState(userId);
  }

  copyWith(options: ProfileUiStateOptions): ProfileUiState {
    return new ProfileUiState(
      options.userId !== undefined ? options.userId : this.userId,
      options.displayName !== undefined ? options.displayName : this.displayName,
      options.username !== undefined ? options.username : this.username,
      options.phone !== undefined ? options.phone : this.phone,
      options.bio !== undefined ? options.bio : this.bio,
      options.statusText !== undefined ? options.statusText : this.statusText,
      options.avatarPath !== undefined ? options.avatarPath : this.avatarPath,
      options.avatarLetters !== undefined ? options.avatarLetters : this.avatarLetters,
      options.avatarColorIndex !== undefined ? options.avatarColorIndex : this.avatarColorIndex,
      options.isLoading !== undefined ? options.isLoading : this.isLoading,
      options.errorMessage !== undefined ? options.errorMessage : this.errorMessage,
      options.birthdayText !== undefined ? options.birthdayText : this.birthdayText,
      options.notificationText !== undefined ? options.notificationText : this.notificationText,
      options.activeSharedTab !== undefined ? options.activeSharedTab : this.activeSharedTab,
      options.sharedMedia !== undefined ? options.sharedMedia : this.sharedMedia,
      options.sharedFiles !== undefined ? options.sharedFiles : this.sharedFiles,
      options.sharedLinks !== undefined ? options.sharedLinks : this.sharedLinks,
      options.sharedGroups !== undefined ? options.sharedGroups : this.sharedGroups,
      options.sharedLoading !== undefined ? options.sharedLoading : this.sharedLoading,
      options.sharedHasMore !== undefined ? options.sharedHasMore : this.sharedHasMore,
      options.sharedLoadingMore !== undefined ? options.sharedLoadingMore : this.sharedLoadingMore,
      options.emojiStatusEmoji !== undefined ? options.emojiStatusEmoji : this.emojiStatusEmoji,
      options.sharedInitialRequested !== undefined ? options.sharedInitialRequested : this.sharedInitialRequested,
      options.sharedLoadFailed !== undefined ? options.sharedLoadFailed : this.sharedLoadFailed
    );
  }
}
