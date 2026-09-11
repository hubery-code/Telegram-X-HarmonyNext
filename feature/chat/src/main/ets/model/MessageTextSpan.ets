/**
 * feature/chat — 富文本 span 视图模型（MSG-101）。
 *
 * MessageTextSpan 是一段连续文本 + 该段全部样式 flags 的扁平不可变数据，
 * 由 FormattedTextParser 从 TDLib FormattedText（text + entities）切分产出，
 * 供 ChatPage 用 Text + Span/ContainerSpan 渲染：
 * - bold/italic/underline/strikethrough：行内字形样式；
 * - isCode/isPre：等宽字体 + 浅底色（Pre/PreCode 也走行内渲染，不单独成块）；
 * - isSpoiler：遮罩块，点击切换显示/隐藏；
 * - isAccent：mention/hashtag/cashtag/botCommand/email/phoneNumber/
 *   bankCardNumber/mediaTimestamp/mentionName 等只着色不带链接的实体；
 * - linkUrl：TextUrl 实体的 url 字段，或 Url 实体的段文本自身；非 null 即可点击。
 */
export class MessageTextSpan {
  readonly text: string;
  readonly bold: boolean;
  readonly italic: boolean;
  readonly underline: boolean;
  readonly strikethrough: boolean;
  readonly isCode: boolean;
  readonly isPre: boolean;
  readonly isSpoiler: boolean;
  readonly isAccent: boolean;
  readonly linkUrl: string | null;

  constructor(
    text: string,
    bold: boolean = false,
    italic: boolean = false,
    underline: boolean = false,
    strikethrough: boolean = false,
    isCode: boolean = false,
    isPre: boolean = false,
    isSpoiler: boolean = false,
    isAccent: boolean = false,
    linkUrl: string | null = null
  ) {
    this.text = text;
    this.bold = bold;
    this.italic = italic;
    this.underline = underline;
    this.strikethrough = strikethrough;
    this.isCode = isCode;
    this.isPre = isPre;
    this.isSpoiler = isSpoiler;
    this.isAccent = isAccent;
    this.linkUrl = linkUrl;
  }

  /** 样式指纹：flags + linkUrl 完全相同的相邻段可合并为一个 span。 */
  sameStyleAs(other: MessageTextSpan): boolean {
    return this.bold === other.bold &&
      this.italic === other.italic &&
      this.underline === other.underline &&
      this.strikethrough === other.strikethrough &&
      this.isCode === other.isCode &&
      this.isPre === other.isPre &&
      this.isSpoiler === other.isSpoiler &&
      this.isAccent === other.isAccent &&
      this.linkUrl === other.linkUrl;
  }
}
