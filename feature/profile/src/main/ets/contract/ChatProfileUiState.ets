/**
 * feature/profile — 群组/频道资料页 UI 状态契约（PROFILE-102；CHATPROF-SHARED 扩展共享内容区）。
 *
 * 遵循 Telegram-X ProfileController.Args(chat) 信息面：
 * - 封面大图 / 头像首字母占位 / 调色盘索引；
 * - 群名 / 频道名；
 * - 副标题：成员数（"N members" / "N subscribers"）；
 * - 简介 Description；
 * - 邀请链接 Invite Link；
 * - 成员列表第一页（头像、昵称、在线状态、管理员身份标记）；
 * - 共享内容三 Tab（媒体/文件/链接；「共同群组」是私聊资料页专属，本页没有）。
 */

import { SharedFileItem, SharedLinkItem, SharedMediaItem } from './SharedContentItems';

export interface ChatMemberUiItem {
  readonly userId: number;
  readonly fullName: string;
  readonly username: string;
  readonly avatarLetters: string;
  readonly avatarColorIndex: number;
  readonly avatarPath: string | null;
  readonly role: string;
  readonly isOnline: boolean;
  readonly statusText: string;
}

export interface ChatProfileUiStateOptions {
  chatId?: number;
  title?: string;
  photoPath?: string | null;
  avatarLetters?: string;
  avatarColorIndex?: number;
  description?: string;
  memberCount?: number;
  memberCountText?: string;
  isChannel?: boolean;
  isGroup?: boolean;
  inviteLink?: string;
  members?: ChatMemberUiItem[];
  isLoading?: boolean;
  errorMessage?: string;
  /** 共享内容当前选中 Tab：0 媒体 / 1 文件 / 2 链接。 */
  activeSharedTab?: number;
  sharedMedia?: SharedMediaItem[];
  sharedFiles?: SharedFileItem[];
  sharedLinks?: SharedLinkItem[];
  /** 共享内容加载中（切 Tab 触发请求后为 true，回灌后 false）。 */
  sharedLoading?: boolean;
  /** 当前共享内容 Tab 是否还有下一页。 */
  sharedHasMore?: boolean;
  /** 加载更多在途。 */
  sharedLoadingMore?: boolean;
  /** 首屏是否已发起过共享内容请求（只发一次，避免订阅回灌反复拉取）。 */
  sharedInitialRequested?: boolean;
  /** 当前 Tab 的共享内容请求失败（与「确实没有内容」区分开，否则页面在撒谎）。 */
  sharedLoadFailed?: boolean;
}

export class ChatProfileUiState {
  readonly chatId: number;
  readonly title: string;
  readonly photoPath: string | null;
  readonly avatarLetters: string;
  readonly avatarColorIndex: number;
  readonly description: string;
  readonly memberCount: number;
  readonly memberCountText: string;
  readonly isChannel: boolean;
  readonly isGroup: boolean;
  readonly inviteLink: string;
  readonly members: ChatMemberUiItem[];
  readonly isLoading: boolean;
  readonly errorMessage: string;
  readonly activeSharedTab: number;
  readonly sharedMedia: SharedMediaItem[];
  readonly sharedFiles: SharedFileItem[];
  readonly sharedLinks: SharedLinkItem[];
  readonly sharedLoading: boolean;
  readonly sharedHasMore: boolean;
  readonly sharedLoadingMore: boolean;
  readonly sharedInitialRequested: boolean;
  readonly sharedLoadFailed: boolean;

  constructor(
    chatId: number = 0,
    title: string = '',
    photoPath: string | null = null,
    avatarLetters: string = '',
    avatarColorIndex: number = 0,
    description: string = '',
    memberCount: number = 0,
    memberCountText: string = '',
    isChannel: boolean = false,
    isGroup: boolean = false,
    inviteLink: string = '',
    members: ChatMemberUiItem[] = [],
    isLoading: boolean = false,
    errorMessage: string = '',
    activeSharedTab: number = 0,
    sharedMedia: SharedMediaItem[] = [],
    sharedFiles: SharedFileItem[] = [],
    sharedLinks: SharedLinkItem[] = [],
    sharedLoading: boolean = false,
    sharedHasMore: boolean = true,
    sharedLoadingMore: boolean = false,
    sharedInitialRequested: boolean = false,
    sharedLoadFailed: boolean = false
  ) {
    this.chatId = chatId;
    this.title = title;
    this.photoPath = photoPath;
    this.avatarLetters = avatarLetters;
    this.avatarColorIndex = avatarColorIndex;
    this.description = description;
    this.memberCount = memberCount;
    this.memberCountText = memberCountText;
    this.isChannel = isChannel;
    this.isGroup = isGroup;
    this.inviteLink = inviteLink;
    this.members = members;
    this.isLoading = isLoading;
    this.errorMessage = errorMessage;
    this.activeSharedTab = activeSharedTab;
    this.sharedMedia = sharedMedia;
    this.sharedFiles = sharedFiles;
    this.sharedLinks = sharedLinks;
    this.sharedLoading = sharedLoading;
    this.sharedHasMore = sharedHasMore;
    this.sharedLoadingMore = sharedLoadingMore;
    this.sharedInitialRequested = sharedInitialRequested;
    this.sharedLoadFailed = sharedLoadFailed;
  }

  static initial(): ChatProfileUiState {
    return new ChatProfileUiState();
  }

  copyWith(patch: ChatProfileUiStateOptions): ChatProfileUiState {
    return new ChatProfileUiState(
      patch.chatId !== undefined ? patch.chatId : this.chatId,
      patch.title !== undefined ? patch.title : this.title,
      patch.photoPath !== undefined ? patch.photoPath : this.photoPath,
      patch.avatarLetters !== undefined ? patch.avatarLetters : this.avatarLetters,
      patch.avatarColorIndex !== undefined ? patch.avatarColorIndex : this.avatarColorIndex,
      patch.description !== undefined ? patch.description : this.description,
      patch.memberCount !== undefined ? patch.memberCount : this.memberCount,
      patch.memberCountText !== undefined ? patch.memberCountText : this.memberCountText,
      patch.isChannel !== undefined ? patch.isChannel : this.isChannel,
      patch.isGroup !== undefined ? patch.isGroup : this.isGroup,
      patch.inviteLink !== undefined ? patch.inviteLink : this.inviteLink,
      patch.members !== undefined ? patch.members : this.members,
      patch.isLoading !== undefined ? patch.isLoading : this.isLoading,
      patch.errorMessage !== undefined ? patch.errorMessage : this.errorMessage,
      patch.activeSharedTab !== undefined ? patch.activeSharedTab : this.activeSharedTab,
      patch.sharedMedia !== undefined ? patch.sharedMedia : this.sharedMedia,
      patch.sharedFiles !== undefined ? patch.sharedFiles : this.sharedFiles,
      patch.sharedLinks !== undefined ? patch.sharedLinks : this.sharedLinks,
      patch.sharedLoading !== undefined ? patch.sharedLoading : this.sharedLoading,
      patch.sharedHasMore !== undefined ? patch.sharedHasMore : this.sharedHasMore,
      patch.sharedLoadingMore !== undefined ? patch.sharedLoadingMore : this.sharedLoadingMore,
      patch.sharedInitialRequested !== undefined ? patch.sharedInitialRequested : this.sharedInitialRequested,
      patch.sharedLoadFailed !== undefined ? patch.sharedLoadFailed : this.sharedLoadFailed
    );
  }
}
