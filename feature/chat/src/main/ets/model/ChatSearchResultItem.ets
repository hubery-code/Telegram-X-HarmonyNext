/**
 * feature/chat — 聊天内搜索结果条目模型（SEARCH-102，FEAT-SEARCH-002）。
 *
 * 纯 ArkTS 不可变模型：封装命中消息的 id、会话原文摘要与格式化日期，
 * 供会话页搜索面板渲染。Kit-free（feature/chat 约束）。
 */

export class ChatSearchResultItem {
  readonly messageId: number;
  readonly textSnippet: string;
  /** 命中消息日期（当前会话内按 HH:mm 显示，跨天简化为 dd.MM）。 */
  readonly dateText: string;
  /** 是否仍能跳转定位（该消息已被本会话投影缓存/加载）。 */
  readonly jumpable: boolean;

  constructor(messageId: number, textSnippet: string, dateText: string, jumpable: boolean = true) {
    this.messageId = messageId;
    this.textSnippet = textSnippet;
    this.dateText = dateText;
    this.jumpable = jumpable;
  }
}
