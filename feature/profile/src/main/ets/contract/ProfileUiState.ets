/**
 * feature/profile — 用户资料页 UI 状态（PROFILE-101）。
 *
 * 不可变 + copyWith，对齐 feature/chat 的 ChatUiState 约定。
 */

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
    errorMessage: string | null = null
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
      options.errorMessage !== undefined ? options.errorMessage : this.errorMessage
    );
  }
}
