/**
 * feature/search — 搜索消息条目模型（SEARCH-101）。
 */

export class SearchMessageItem {
  readonly messageId: number;
  readonly chatId: number;
  readonly chatTitle: string;
  readonly senderName: string;
  readonly textSnippet: string;
  readonly dateFormatted: string;

  constructor(
    messageId: number,
    chatId: number,
    chatTitle: string,
    senderName: string,
    textSnippet: string,
    dateFormatted: string
  ) {
    this.messageId = messageId;
    this.chatId = chatId;
    this.chatTitle = chatTitle;
    this.senderName = senderName;
    this.textSnippet = textSnippet;
    this.dateFormatted = dateFormatted;
  }
}
