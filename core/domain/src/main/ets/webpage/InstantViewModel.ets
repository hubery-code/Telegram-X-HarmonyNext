/**
 * core/domain — Instant View 数据层与纯逻辑层（IV-101，UI 待接）。
 *
 * 职责：把 TDLib `webPageInstantView` 里的 46 种 PageBlock* 协议块
 * 投影成「阅读器就绪」的语义块树（InstantViewBlock）：
 * - 46 种协议块按阅读语义归并为 ~19 种 kind（title/subtitle/header/paragraph/
 *   figure/list/quote/...），不是 1:1 映射 —— 渲染层按 kind 布局，按
 *   mediaType/sourceType 细分播放器与样式；
 * - 归并是**保结构的深投影**：details/collage/slideshow/cover/embeddedPost/
 *   relatedArticles 的内嵌块递归投影进 children，树里不残留任何 TDLib DTO；
 * - TDLib 版本升级出现新块型时经 decodeTdPageBlock 落到 TdUnknownObject，
 *   归并为 kind='unknown' 且 sourceType 保留原始 @type —— 阅读器跳过该块
 *   而不是崩溃（classifyPageBlockType + ALL_PAGE_BLOCK_TYPES 的全量枚举
 *   由单测兜住「已知块型漏归并」回归）；
 * - RichText 统一拍平为纯文本进 text/caption/credit（样式投影是 UI 包的事）。
 *
 * 本文件纯逻辑：不 import ArkUI / @kit.* / @ohos.*（core 层红线）。
 */

import {
  WebPageInstantView,
  TdPageBlock,
  TdRichText,
  TdUnknownObject,
  TdInlineKeyboardButtonType,
  RichTextAnchor,
  RichTextAnchorLink,
  RichTextBankCardNumber,
  RichTextBold,
  RichTextBotCommand,
  RichTextButton,
  RichTextCashtag,
  RichTextCustomEmoji,
  RichTextDateTime,
  RichTextDiff,
  RichTextEmailAddress,
  RichTextFixed,
  RichTextHashtag,
  RichTextIcon,
  RichTextItalic,
  RichTextMarked,
  RichTextMathematicalExpression,
  RichTextMention,
  RichTextMentionName,
  RichTextPhoneNumber,
  RichTextPlain,
  RichTextReference,
  RichTextReferenceLink,
  RichTextSpoiler,
  RichTextStrikethrough,
  RichTextSubscript,
  RichTextSuperscript,
  RichTextUnderline,
  RichTextUrl,
  RichTexts,
  InlineButton,
  InlineKeyboardButtonTypeUrl,
  PageBlockAnchor,
  PageBlockAnimation,
  PageBlockAudio,
  PageBlockAuthorDate,
  PageBlockBlockQuote,
  PageBlockButtonRow,
  PageBlockCaption,
  PageBlockChatLink,
  PageBlockCollage,
  PageBlockCover,
  PageBlockDetails,
  PageBlockDocument,
  PageBlockEmbedded,
  PageBlockEmbeddedPost,
  PageBlockExpandableBlockQuote,
  PageBlockFooter,
  PageBlockHeader,
  PageBlockKicker,
  PageBlockList,
  PageBlockListItem,
  PageBlockMap,
  PageBlockMathematicalExpression,
  PageBlockParagraph,
  PageBlockPhoto,
  PageBlockPreformatted,
  PageBlockPullQuote,
  PageBlockRelatedArticle,
  PageBlockRelatedArticles,
  PageBlockSectionHeading,
  PageBlockSlideshow,
  PageBlockSubheader,
  PageBlockSubtitle,
  PageBlockTable,
  PageBlockThinking,
  PageBlockTitle,
  PageBlockVideo,
  PageBlockVoiceNote,
  Photo,
  PhotoSize
} from '@tgx/core-td-api-generated';

/**
 * 阅读器语义块类。'caption' / 'listItem' / 'tableCell' / 'tableAlign' 是
 * **被吸收的角色**：它们只作为 classifyPageBlockType 的去处出现（其协议块
 * 被父块吃进 caption/items/rows 等字段），永远不会作为独立块出现在投影输出里。
 */
export type InstantViewBlockKind =
  'title'
  | 'subtitle'
  | 'kicker'
  | 'byline'
  | 'header'
  | 'paragraph'
  | 'preformatted'
  | 'quote'
  | 'pullquote'
  | 'figure'
  | 'list'
  | 'details'
  | 'table'
  | 'related'
  | 'buttons'
  | 'button'
  | 'divider'
  | 'anchor'
  | 'chatLink'
  | 'unknown'
  | 'caption'
  | 'listItem'
  | 'tableCell'
  | 'tableAlign';

/** figure 内的媒体细分（渲染层据此选图片/播放器/文件卡，布局上同属 figure 家族）。 */
export type InstantViewMediaKind =
  'photo'
  | 'video'
  | 'animation'
  | 'audio'
  | 'voiceNote'
  | 'document'
  | 'map'
  | 'embedded'
  | 'embeddedPost'
  | 'collage'
  | 'slideshow'
  | 'cover';

/** 列表项（PageBlockListItem 的投影；label 为编号/项目符号标记串）。 */
export class InstantViewListItem {
  label: string = '';
  text: string = '';
  hasCheckbox: boolean = false;
  isChecked: boolean = false;

  constructor(label: string = '', text: string = '', hasCheckbox: boolean = false, isChecked: boolean = false) {
    this.label = label;
    this.text = text;
    this.hasCheckbox = hasCheckbox;
    this.isChecked = isChecked;
  }
}

/**
 * 阅读器块模型。字段只留渲染层真正要用的：
 * - text/caption/credit：RichText 已拍平为纯文本；
 * - fileId：媒体文件句柄（渲染层走下载链路），0 = 无媒体；
 * - url：块级跳转链接（photo/embedded/relatedArticle/button 的 http(s) 链接，
 *   chatLink 存原始 username，渲染层自行决定拼 t.me 链接还是走搜索）；
 * - imageUrl 预留直链位 —— 当前 TDLib 页面块媒体一律走 fileId 下载，
 *   投影恒置空，供未来出现直链块型时免改渲染契约；
 * - children：嵌套块的递归投影（details/collage/slideshow/cover/
 *   embeddedPost/relatedArticles/buttonRow 专用），树内无 TDLib DTO 残留；
 * - sourceType：原始 @type，unknown 块靠它保留 TDLib 原名供诊断/降级。
 */
export class InstantViewBlock {
  kind: InstantViewBlockKind;
  sourceType: string;
  mediaType: InstantViewMediaKind | '' = '';
  text: string = '';
  caption: string = '';
  credit: string = '';
  url: string = '';
  imageUrl: string = '';
  fileId: number = 0;
  width: number = 0;
  height: number = 0;
  latitude: number = 0;
  longitude: number = 0;
  level: number = 0;
  language: string = '';
  publishDate: number = 0;
  isOpen: boolean = false;
  isBordered: boolean = false;
  isStriped: boolean = false;
  items: InstantViewListItem[] = [];
  rows: string[][] = [];
  children: InstantViewBlock[] = [];

  constructor(kind: InstantViewBlockKind = 'unknown', sourceType: string = '') {
    this.kind = kind;
    this.sourceType = sourceType;
  }
}

/** Instant View 页投影（阅读器页级元数据 + 块树）。 */
export class InstantViewPage {
  blocks: InstantViewBlock[] = [];
  /** TDLib instant view 版本（1 或 2），渲染规则略有差异。 */
  version: number = 0;
  /** 从右到左排版（RTL 语言页面）。 */
  isRtl: boolean = false;
  /** 是否已含全文；false 表示可能还要网络请求取完整版。 */
  isFull: boolean = false;
  /** 页面浏览数；0 = 未知。 */
  viewCount: number = 0;
}

/**
 * 当前 TDLib schema 里 PageBlock 家族的全部 46 个 @type（TdTypes_P 全量，
 * 含 10 个非 union 成员的辅助块型）。与 classifyPageBlockType 必须同步维护，
 * 单测用全量枚举断言防「新增/漏归并」。
 */
export const ALL_PAGE_BLOCK_TYPES: string[] = [
  'pageBlockAnchor',
  'pageBlockAnimation',
  'pageBlockAudio',
  'pageBlockAuthorDate',
  'pageBlockBlockQuote',
  'pageBlockButtonRow',
  'pageBlockCaption',
  'pageBlockChatLink',
  'pageBlockCollage',
  'pageBlockCover',
  'pageBlockDetails',
  'pageBlockDivider',
  'pageBlockDocument',
  'pageBlockEmbedded',
  'pageBlockEmbeddedPost',
  'pageBlockExpandableBlockQuote',
  'pageBlockFooter',
  'pageBlockHeader',
  'pageBlockHorizontalAlignmentCenter',
  'pageBlockHorizontalAlignmentLeft',
  'pageBlockHorizontalAlignmentRight',
  'pageBlockKicker',
  'pageBlockList',
  'pageBlockListItem',
  'pageBlockMap',
  'pageBlockMathematicalExpression',
  'pageBlockParagraph',
  'pageBlockPhoto',
  'pageBlockPreformatted',
  'pageBlockPullQuote',
  'pageBlockRelatedArticle',
  'pageBlockRelatedArticles',
  'pageBlockSectionHeading',
  'pageBlockSlideshow',
  'pageBlockSubheader',
  'pageBlockSubtitle',
  'pageBlockTable',
  'pageBlockTableCell',
  'pageBlockThinking',
  'pageBlockTitle',
  'pageBlockUnsupported',
  'pageBlockVerticalAlignmentBottom',
  'pageBlockVerticalAlignmentMiddle',
  'pageBlockVerticalAlignmentTop',
  'pageBlockVideo',
  'pageBlockVoiceNote'
];

/**
 * 46 种 PageBlock* @type → 阅读器语义类 的完整归并表（classify 侧）。
 * 未列出的 @type（TDLib 升级新增块型）落 default → 'unknown'，阅读器跳过。
 */
export function classifyPageBlockType(sourceType: string): InstantViewBlockKind {
  switch (sourceType) {
    case 'pageBlockTitle':
      return 'title';
    case 'pageBlockSubtitle':
      return 'subtitle';
    case 'pageBlockAuthorDate':
      return 'byline';
    case 'pageBlockHeader':
    case 'pageBlockSubheader':
    case 'pageBlockSectionHeading':
      return 'header';
    case 'pageBlockKicker':
      return 'kicker';
    case 'pageBlockParagraph':
    case 'pageBlockFooter':
    case 'pageBlockThinking':
    case 'pageBlockMathematicalExpression':
      return 'paragraph';
    case 'pageBlockPreformatted':
      return 'preformatted';
    case 'pageBlockBlockQuote':
    case 'pageBlockExpandableBlockQuote':
      return 'quote';
    case 'pageBlockPullQuote':
      return 'pullquote';
    case 'pageBlockPhoto':
    case 'pageBlockVideo':
    case 'pageBlockAnimation':
    case 'pageBlockAudio':
    case 'pageBlockVoiceNote':
    case 'pageBlockDocument':
    case 'pageBlockMap':
    case 'pageBlockEmbedded':
    case 'pageBlockEmbeddedPost':
    case 'pageBlockCollage':
    case 'pageBlockSlideshow':
    case 'pageBlockCover':
      return 'figure';
    case 'pageBlockList':
      return 'list';
    case 'pageBlockDetails':
      return 'details';
    case 'pageBlockTable':
      return 'table';
    case 'pageBlockRelatedArticles':
    case 'pageBlockRelatedArticle':
      return 'related';
    case 'pageBlockButtonRow':
      return 'buttons';
    case 'pageBlockDivider':
      return 'divider';
    case 'pageBlockAnchor':
      return 'anchor';
    case 'pageBlockChatLink':
      return 'chatLink';
    // pageBlockUnsupported 是已知协议块型，语义上就是「当前版本不支持」，
    // 归 unknown 让阅读器走统一的降级占位。
    case 'pageBlockUnsupported':
      return 'unknown';
    // 吸收型角色：被父块吃进字段，不产生独立块。
    case 'pageBlockCaption':
      return 'caption';
    case 'pageBlockListItem':
      return 'listItem';
    case 'pageBlockTableCell':
      return 'tableCell';
    case 'pageBlockHorizontalAlignmentCenter':
    case 'pageBlockHorizontalAlignmentLeft':
    case 'pageBlockHorizontalAlignmentRight':
    case 'pageBlockVerticalAlignmentBottom':
    case 'pageBlockVerticalAlignmentMiddle':
    case 'pageBlockVerticalAlignmentTop':
      return 'tableAlign';
    default:
      return 'unknown';
  }
}

/**
 * RichText → 纯文本。样式（粗体/斜体/链接等）在此丢弃，只留可读字符流；
 * 富文本 span 级样式投影归 UI 包。
 */
export function richTextToPlain(text: TdRichText | null): string {
  if (text === null || text === undefined) {
    return '';
  }
  if (text instanceof TdUnknownObject) {
    return '';
  }
  if (text instanceof RichTextPlain) {
    return text.text;
  }
  if (text instanceof RichTexts) {
    let joined: string = '';
    for (const part of text.texts) {
      joined += richTextToPlain(part);
    }
    return joined;
  }
  //RichTextButton 的可见文本藏在 InlineButton.text 里。
  if (text instanceof RichTextButton) {
    return richTextToPlain(text.button === null ? null : text.button.text);
  }
  //纯图片节点，无可见字符。
  if (text instanceof RichTextIcon) {
    return '';
  }
  //Anchor 只有锚点名，不产生可见文本。
  if (text instanceof RichTextAnchor) {
    return '';
  }
  //自定义 emoji 的可见文本是替代文案。
  if (text instanceof RichTextCustomEmoji) {
    return text.alternative_text;
  }
  //数学表达式直接用表达式串。
  if (text instanceof RichTextMathematicalExpression) {
    return text.expression;
  }
  //以下节点全部是「样式/实体包裹内层文本」，递归取 text。
  if (text instanceof RichTextBold
    || text instanceof RichTextItalic
    || text instanceof RichTextUnderline
    || text instanceof RichTextStrikethrough
    || text instanceof RichTextMarked
    || text instanceof RichTextFixed
    || text instanceof RichTextSubscript
    || text instanceof RichTextSuperscript
    || text instanceof RichTextSpoiler
    || text instanceof RichTextAnchorLink
    || text instanceof RichTextUrl
    || text instanceof RichTextEmailAddress
    || text instanceof RichTextHashtag
    || text instanceof RichTextCashtag
    || text instanceof RichTextBotCommand
    || text instanceof RichTextMention
    || text instanceof RichTextMentionName
    || text instanceof RichTextPhoneNumber
    || text instanceof RichTextBankCardNumber
    || text instanceof RichTextDateTime
    || text instanceof RichTextDiff
    || text instanceof RichTextReference
    || text instanceof RichTextReferenceLink) {
    return richTextToPlain(text.text);
  }
  return '';
}

/**
 * 46 种 PageBlock* → 阅读器块树的投影主入口。
 * out 作为复用缓冲传入并返回（调用方传 [] 即可）。
 */
export function flattenInstantViewBlocks(blocks: TdPageBlock[], out: InstantViewBlock[]): InstantViewBlock[] {
  for (const block of blocks) {
    if (block === null || block === undefined) {
      continue;
    }
    projectBlock(block, out);
  }
  return out;
}

/** 把内嵌块递归投影后按 text 连接成段落串（quote / list item 用）。 */
function flattenToJoinedText(blocks: TdPageBlock[]): string {
  const inner: InstantViewBlock[] = flattenInstantViewBlocks(blocks, []);
  let joined: string = '';
  for (const innerBlock of inner) {
    if (innerBlock.text.length > 0) {
      if (joined.length > 0) {
        joined += '\n';
      }
      joined += innerBlock.text;
    }
  }
  return joined;
}

/** PageBlockCaption（media caption）→ 块的 caption/credit 字段。 */
function applyCaption(target: InstantViewBlock, caption: PageBlockCaption | null): void {
  if (caption === null) {
    return;
  }
  target.caption = richTextToPlain(caption.text);
  target.credit = richTextToPlain(caption.credit);
}

/** Photo 多尺寸里取面积最大的一档（fileId 与展示尺寸同源，避免错配）。 */
function largestPhotoSize(photo: Photo | null): PhotoSize | null {
  if (photo === null) {
    return null;
  }
  let best: PhotoSize | null = null;
  let bestArea: number = -1;
  for (const size of photo.sizes) {
    const area: number = size.width * size.height;
    if (size.photo !== null && area > bestArea) {
      bestArea = area;
      best = size;
    }
  }
  return best;
}

/** InlineButton → button 子块（url 只识别 inlineKeyboardButtonTypeUrl）。 */
function projectInlineButton(button: InlineButton): InstantViewBlock {
  const block: InstantViewBlock = new InstantViewBlock('button', 'inlineButton');
  block.text = richTextToPlain(button.text);
  const buttonType: TdInlineKeyboardButtonType | null = button.type_;
  if (buttonType instanceof InlineKeyboardButtonTypeUrl) {
    block.url = buttonType.url;
  }
  return block;
}

/** 单块投影分发（switch @type + 具名类断言，与生成解码器风格一致）。 */
function projectBlock(block: TdPageBlock, out: InstantViewBlock[]): void {
  switch (block.type) {
    case 'pageBlockTitle': {
      const b: PageBlockTitle = block as PageBlockTitle;
      const item: InstantViewBlock = new InstantViewBlock('title', 'pageBlockTitle');
      item.text = richTextToPlain(b.title);
      item.level = 1;
      out.push(item);
      return;
    }
    case 'pageBlockSubtitle': {
      const b: PageBlockSubtitle = block as PageBlockSubtitle;
      const item: InstantViewBlock = new InstantViewBlock('subtitle', 'pageBlockSubtitle');
      item.text = richTextToPlain(b.subtitle);
      out.push(item);
      return;
    }
    case 'pageBlockAuthorDate': {
      const b: PageBlockAuthorDate = block as PageBlockAuthorDate;
      const item: InstantViewBlock = new InstantViewBlock('byline', 'pageBlockAuthorDate');
      item.text = richTextToPlain(b.author);
      item.publishDate = b.publish_date;
      out.push(item);
      return;
    }
    case 'pageBlockHeader': {
      const b: PageBlockHeader = block as PageBlockHeader;
      const item: InstantViewBlock = new InstantViewBlock('header', 'pageBlockHeader');
      item.text = richTextToPlain(b.header);
      item.level = 2;
      out.push(item);
      return;
    }
    case 'pageBlockSubheader': {
      const b: PageBlockSubheader = block as PageBlockSubheader;
      const item: InstantViewBlock = new InstantViewBlock('header', 'pageBlockSubheader');
      item.text = richTextToPlain(b.subheader);
      item.level = 3;
      out.push(item);
      return;
    }
    case 'pageBlockSectionHeading': {
      const b: PageBlockSectionHeading = block as PageBlockSectionHeading;
      const item: InstantViewBlock = new InstantViewBlock('header', 'pageBlockSectionHeading');
      item.text = richTextToPlain(b.text);
      //小节标题固定最小一级；TDLib 的 size(0-6) 量纲未稳定，暂不透传（见遗留）。
      item.level = 4;
      out.push(item);
      return;
    }
    case 'pageBlockKicker': {
      const b: PageBlockKicker = block as PageBlockKicker;
      const item: InstantViewBlock = new InstantViewBlock('kicker', 'pageBlockKicker');
      item.text = richTextToPlain(b.kicker);
      out.push(item);
      return;
    }
    case 'pageBlockParagraph': {
      const b: PageBlockParagraph = block as PageBlockParagraph;
      const item: InstantViewBlock = new InstantViewBlock('paragraph', 'pageBlockParagraph');
      item.text = richTextToPlain(b.text);
      out.push(item);
      return;
    }
    case 'pageBlockFooter': {
      const b: PageBlockFooter = block as PageBlockFooter;
      const item: InstantViewBlock = new InstantViewBlock('paragraph', 'pageBlockFooter');
      item.text = richTextToPlain(b.footer);
      out.push(item);
      return;
    }
    case 'pageBlockThinking': {
      const b: PageBlockThinking = block as PageBlockThinking;
      const item: InstantViewBlock = new InstantViewBlock('paragraph', 'pageBlockThinking');
      item.text = richTextToPlain(b.text);
      out.push(item);
      return;
    }
    case 'pageBlockMathematicalExpression': {
      const b: PageBlockMathematicalExpression = block as PageBlockMathematicalExpression;
      const item: InstantViewBlock = new InstantViewBlock('paragraph', 'pageBlockMathematicalExpression');
      item.text = b.expression;
      out.push(item);
      return;
    }
    case 'pageBlockPreformatted': {
      const b: PageBlockPreformatted = block as PageBlockPreformatted;
      const item: InstantViewBlock = new InstantViewBlock('preformatted', 'pageBlockPreformatted');
      item.text = richTextToPlain(b.text);
      item.language = b.language;
      out.push(item);
      return;
    }
    case 'pageBlockBlockQuote': {
      const b: PageBlockBlockQuote = block as PageBlockBlockQuote;
      const item: InstantViewBlock = new InstantViewBlock('quote', 'pageBlockBlockQuote');
      item.text = flattenToJoinedText(b.blocks);
      item.credit = richTextToPlain(b.credit);
      out.push(item);
      return;
    }
    case 'pageBlockExpandableBlockQuote': {
      const b: PageBlockExpandableBlockQuote = block as PageBlockExpandableBlockQuote;
      const item: InstantViewBlock = new InstantViewBlock('quote', 'pageBlockExpandableBlockQuote');
      item.text = richTextToPlain(b.text);
      item.credit = richTextToPlain(b.credit);
      out.push(item);
      return;
    }
    case 'pageBlockPullQuote': {
      const b: PageBlockPullQuote = block as PageBlockPullQuote;
      const item: InstantViewBlock = new InstantViewBlock('pullquote', 'pageBlockPullQuote');
      item.text = richTextToPlain(b.text);
      item.credit = richTextToPlain(b.credit);
      out.push(item);
      return;
    }
    case 'pageBlockPhoto': {
      const b: PageBlockPhoto = block as PageBlockPhoto;
      const item: InstantViewBlock = new InstantViewBlock('figure', 'pageBlockPhoto');
      item.mediaType = 'photo';
      item.url = b.url;
      const best: PhotoSize | null = largestPhotoSize(b.photo);
      if (best !== null && best.photo !== null) {
        item.fileId = best.photo.id;
        item.width = best.width;
        item.height = best.height;
      }
      applyCaption(item, b.caption);
      out.push(item);
      return;
    }
    case 'pageBlockVideo': {
      const b: PageBlockVideo = block as PageBlockVideo;
      const item: InstantViewBlock = new InstantViewBlock('figure', 'pageBlockVideo');
      item.mediaType = 'video';
      if (b.video !== null) {
        //Video 的文件句柄在内层 video.file 字段，宽高在 Video 对象上。
        item.fileId = b.video.video === null ? 0 : b.video.video.id;
        item.width = b.video.width;
        item.height = b.video.height;
      }
      applyCaption(item, b.caption);
      out.push(item);
      return;
    }
    case 'pageBlockAnimation': {
      const b: PageBlockAnimation = block as PageBlockAnimation;
      const item: InstantViewBlock = new InstantViewBlock('figure', 'pageBlockAnimation');
      item.mediaType = 'animation';
      if (b.animation !== null) {
        //Animation 的文件句柄同样在内层 animation.file 字段。
        item.fileId = b.animation.animation === null ? 0 : b.animation.animation.id;
        item.width = b.animation.width;
        item.height = b.animation.height;
      }
      applyCaption(item, b.caption);
      out.push(item);
      return;
    }
    case 'pageBlockAudio': {
      const b: PageBlockAudio = block as PageBlockAudio;
      const item: InstantViewBlock = new InstantViewBlock('figure', 'pageBlockAudio');
      item.mediaType = 'audio';
      if (b.audio !== null) {
        item.fileId = b.audio.audio === null ? 0 : b.audio.audio.id;
      }
      applyCaption(item, b.caption);
      out.push(item);
      return;
    }
    case 'pageBlockVoiceNote': {
      const b: PageBlockVoiceNote = block as PageBlockVoiceNote;
      const item: InstantViewBlock = new InstantViewBlock('figure', 'pageBlockVoiceNote');
      item.mediaType = 'voiceNote';
      if (b.voice_note !== null) {
        item.fileId = b.voice_note.voice === null ? 0 : b.voice_note.voice.id;
      }
      applyCaption(item, b.caption);
      out.push(item);
      return;
    }
    case 'pageBlockDocument': {
      const b: PageBlockDocument = block as PageBlockDocument;
      const item: InstantViewBlock = new InstantViewBlock('figure', 'pageBlockDocument');
      item.mediaType = 'document';
      if (b.document !== null) {
        item.fileId = b.document.document === null ? 0 : b.document.document.id;
      }
      applyCaption(item, b.caption);
      out.push(item);
      return;
    }
    case 'pageBlockMap': {
      const b: PageBlockMap = block as PageBlockMap;
      const item: InstantViewBlock = new InstantViewBlock('figure', 'pageBlockMap');
      item.mediaType = 'map';
      item.width = b.width;
      item.height = b.height;
      if (b.location !== null) {
        item.latitude = b.location.latitude;
        item.longitude = b.location.longitude;
      }
      applyCaption(item, b.caption);
      out.push(item);
      return;
    }
    case 'pageBlockEmbedded': {
      const b: PageBlockEmbedded = block as PageBlockEmbedded;
      const item: InstantViewBlock = new InstantViewBlock('figure', 'pageBlockEmbedded');
      item.mediaType = 'embedded';
      item.url = b.url;
      item.width = b.width;
      item.height = b.height;
      applyCaption(item, b.caption);
      out.push(item);
      return;
    }
    case 'pageBlockEmbeddedPost': {
      const b: PageBlockEmbeddedPost = block as PageBlockEmbeddedPost;
      const item: InstantViewBlock = new InstantViewBlock('figure', 'pageBlockEmbeddedPost');
      item.mediaType = 'embeddedPost';
      item.url = b.url;
      item.text = b.author;
      item.publishDate = b.date;
      item.children = flattenInstantViewBlocks(b.blocks, []);
      applyCaption(item, b.caption);
      out.push(item);
      return;
    }
    case 'pageBlockCollage': {
      const b: PageBlockCollage = block as PageBlockCollage;
      const item: InstantViewBlock = new InstantViewBlock('figure', 'pageBlockCollage');
      item.mediaType = 'collage';
      item.children = flattenInstantViewBlocks(b.blocks, []);
      applyCaption(item, b.caption);
      out.push(item);
      return;
    }
    case 'pageBlockSlideshow': {
      const b: PageBlockSlideshow = block as PageBlockSlideshow;
      const item: InstantViewBlock = new InstantViewBlock('figure', 'pageBlockSlideshow');
      item.mediaType = 'slideshow';
      item.children = flattenInstantViewBlocks(b.blocks, []);
      applyCaption(item, b.caption);
      out.push(item);
      return;
    }
    case 'pageBlockCover': {
      const b: PageBlockCover = block as PageBlockCover;
      const item: InstantViewBlock = new InstantViewBlock('figure', 'pageBlockCover');
      item.mediaType = 'cover';
      if (b.cover !== null) {
        item.children = flattenInstantViewBlocks([b.cover], []);
      }
      out.push(item);
      return;
    }
    case 'pageBlockList': {
      const b: PageBlockList = block as PageBlockList;
      const item: InstantViewBlock = new InstantViewBlock('list', 'pageBlockList');
      for (const listItem of b.items) {
        item.items.push(new InstantViewListItem(
          listItem.label,
          flattenToJoinedText(listItem.blocks),
          listItem.has_checkbox,
          listItem.is_checked
        ));
      }
      out.push(item);
      return;
    }
    case 'pageBlockDetails': {
      const b: PageBlockDetails = block as PageBlockDetails;
      const item: InstantViewBlock = new InstantViewBlock('details', 'pageBlockDetails');
      item.text = richTextToPlain(b.header);
      item.isOpen = b.is_open;
      item.children = flattenInstantViewBlocks(b.blocks, []);
      out.push(item);
      return;
    }
    case 'pageBlockTable': {
      const b: PageBlockTable = block as PageBlockTable;
      const item: InstantViewBlock = new InstantViewBlock('table', 'pageBlockTable');
      item.caption = richTextToPlain(b.caption);
      item.isBordered = b.is_bordered;
      item.isStriped = b.is_striped;
      for (const row of b.cells) {
        const rowTexts: string[] = [];
        for (const cell of row) {
          rowTexts.push(richTextToPlain(cell.text));
        }
        item.rows.push(rowTexts);
      }
      out.push(item);
      return;
    }
    case 'pageBlockRelatedArticles': {
      const b: PageBlockRelatedArticles = block as PageBlockRelatedArticles;
      const item: InstantViewBlock = new InstantViewBlock('related', 'pageBlockRelatedArticles');
      item.text = richTextToPlain(b.header);
      for (const article of b.articles) {
        const card: InstantViewBlock = new InstantViewBlock('related', 'pageBlockRelatedArticle');
        card.text = article.title;
        card.caption = article.description;
        card.url = article.url;
        card.publishDate = article.publish_date;
        const best: PhotoSize | null = largestPhotoSize(article.photo);
        if (best !== null && best.photo !== null) {
          card.fileId = best.photo.id;
        }
        item.children.push(card);
      }
      out.push(item);
      return;
    }
    case 'pageBlockButtonRow': {
      const b: PageBlockButtonRow = block as PageBlockButtonRow;
      const item: InstantViewBlock = new InstantViewBlock('buttons', 'pageBlockButtonRow');
      for (const button of b.buttons) {
        item.children.push(projectInlineButton(button));
      }
      out.push(item);
      return;
    }
    case 'pageBlockDivider': {
      out.push(new InstantViewBlock('divider', 'pageBlockDivider'));
      return;
    }
    case 'pageBlockAnchor': {
      const b: PageBlockAnchor = block as PageBlockAnchor;
      const item: InstantViewBlock = new InstantViewBlock('anchor', 'pageBlockAnchor');
      item.text = b.name;
      out.push(item);
      return;
    }
    case 'pageBlockChatLink': {
      const b: PageBlockChatLink = block as PageBlockChatLink;
      const item: InstantViewBlock = new InstantViewBlock('chatLink', 'pageBlockChatLink');
      item.text = b.title;
      item.url = b.username;
      if (b.photo !== null && b.photo.big !== null) {
        item.fileId = b.photo.big.id;
      }
      out.push(item);
      return;
    }
    case 'pageBlockUnsupported': {
      //已知协议块型但本版本不支持 —— 语义归 unknown，靠 sourceType 区分诊断。
      out.push(new InstantViewBlock('unknown', 'pageBlockUnsupported'));
      return;
    }
    default: {
      //TdUnknownObject（TDLib 升级出现的新块型）或任何未识别对象：
      //保留原始 @type 让阅读器安全跳过，绝不崩渲染。
      out.push(new InstantViewBlock('unknown', block.type));
      return;
    }
  }
}

/** 解码后的 WebPageInstantView → 阅读器页模型（纯函数，无 IO）。 */
export function projectInstantViewPage(instantView: WebPageInstantView): InstantViewPage {
  const page: InstantViewPage = new InstantViewPage();
  page.version = instantView.version;
  page.isRtl = instantView.is_rtl;
  page.isFull = instantView.is_full;
  page.viewCount = instantView.view_count;
  page.blocks = flattenInstantViewBlocks(instantView.blocks, []);
  return page;
}
