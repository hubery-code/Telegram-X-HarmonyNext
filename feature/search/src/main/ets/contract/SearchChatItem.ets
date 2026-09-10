/**
 * feature/search — 搜索会话条目模型（SEARCH-101）。
 */

export class SearchChatItem {
  readonly chatId: number;
  readonly title: string;
  readonly username: string;
  readonly avatarPath: string | null;
  readonly isChannel: boolean;
  readonly isGroup: boolean;

  constructor(
    chatId: number,
    title: string,
    username: string,
    avatarPath: string | null,
    isChannel: boolean,
    isGroup: boolean
  ) {
    this.chatId = chatId;
    this.title = title;
    this.username = username;
    this.avatarPath = avatarPath;
    this.isChannel = isChannel;
    this.isGroup = isGroup;
  }
}
