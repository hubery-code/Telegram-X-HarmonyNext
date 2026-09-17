/**
 * feature/chat — 置顶消息摘要模型（MSG-108）。
 *
 * 纯领域展示模型（Kit-free）：
 * 封装在会话顶部 PinnedMessagesBar 渲染所需的置顶消息元信息。
 * 点击时依据 messageId 触发会话内消息跳转与居中高亮。
 */

export class PinnedMessageInfo {
  readonly messageId: number;
  readonly senderTitle: string;
  readonly contentSnippet: string;

  constructor(messageId: number, senderTitle: string, contentSnippet: string) {
    this.messageId = messageId;
    this.senderTitle = senderTitle;
    this.contentSnippet = contentSnippet;
  }
}
