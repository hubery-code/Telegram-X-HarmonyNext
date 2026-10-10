/**
 * feature/search — 搜索消息条目模型（SEARCH-101 / I18N-HOTSWITCH-102）。
 *
 * 条目只存**与语言无关的原始输入**：时间存 unix 秒而不是已解析的 `HH:mm`。
 * 理由与 `ChatListItem.timestampMs` 同一条 —— 形态串是视图侧现算的，语言或系统
 * 时制一变，只要重渲染就跟着变；把已解析串存进状态里，换语言后它就一直旧着，
 * 除非重新取数（而换语言不该触发取数）。
 */

export class SearchMessageItem {
  readonly messageId: number;
  readonly chatId: number;
  readonly chatTitle: string;
  readonly senderName: string;
  readonly textSnippet: string;
  readonly dateUnix: number;

  constructor(
    messageId: number,
    chatId: number,
    chatTitle: string,
    senderName: string,
    textSnippet: string,
    dateUnix: number
  ) {
    this.messageId = messageId;
    this.chatId = chatId;
    this.chatTitle = chatTitle;
    this.senderName = senderName;
    this.textSnippet = textSnippet;
    this.dateUnix = dateUnix;
  }
}
