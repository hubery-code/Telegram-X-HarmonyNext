/**
 * feature/profile — 群组/频道资料页 UI 状态契约（PROFILE-102）。
 *
 * 遵循 Telegram-X ProfileController.Args(chat) 信息面：
 * - 封面大图 / 头像首字母占位 / 调色盘索引；
 * - 群名 / 频道名；
 * - 副标题：成员数（"N members" / "N subscribers"）；
 * - 简介 Description；
 * - 邀请链接 Invite Link；
 * - 成员列表第一页（头像、昵称、在线状态、管理员身份标记）。
 */

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
    errorMessage: string = ''
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
      patch.errorMessage !== undefined ? patch.errorMessage : this.errorMessage
    );
  }
}
