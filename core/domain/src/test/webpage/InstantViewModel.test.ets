/**
 * core/domain — Instant View 数据层单测（IV-101）。
 *
 * 守住的回归：
 * 1. 46 种 PageBlock* @type 全量归并映射 —— 每个类型都有明确去处
 *    （EXPECTED_KINDS 独立对照表 + classify 双向核对 + 36 个 union 成员
 *    实例过 flatten 后 kind 一致），TDLib 升级新增块型落 unknown 而不是漏归并；
 * 2. 嵌套块递归投影：quote 内层段落拍平为文本、details/collage 保 children、
 *    list item 文本拍平、table 单元格拍平、related 文章卡与按钮 URL 提取；
 * 3. unknown 兜底：TdUnknownObject / pageBlockUnsupported 保留原始 @type，
 *    渲染层可安全跳过而不是崩溃；
 * 4. fetchInstantView 参数校验：空 url / 非 http(s) 判 parameter 错误且
 *    **不发请求**（bridge.sent 为空是硬证据）；合法 url 组包形状正确。
 *
 * 注意：测试辅助全部放文件顶层（ArkTS 不允许 describe 内嵌套函数声明）。
 */

import { describe, it, expect } from '@ohos/hypium';
import {
  Animation,
  Audio,
  ChatPhotoInfo,
  Document,
  File,
  InlineButton,
  InlineKeyboardButtonTypeCallback,
  InlineKeyboardButtonTypeUrl,
  Location,
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
  PageBlockDivider,
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
  PageBlockTableCell,
  PageBlockThinking,
  PageBlockTitle,
  PageBlockUnsupported,
  PageBlockVideo,
  PageBlockVoiceNote,
  Photo,
  PhotoSize,
  RichTextAnchorLink,
  RichTextBold,
  RichTextButton,
  RichTextCustomEmoji,
  RichTextIcon,
  RichTextPlain,
  RichTexts,
  TdJsonRaw,
  TdPageBlock,
  TdRichText,
  TdUnknownObject,
  Video,
  VoiceNote,
  WebPageInstantView,
  encodeWebPageInstantView,
  decodeWebPageInstantView
} from '@tgx/core-td-api-generated';
import {
  AccountScope,
  buildAccountDirectories,
  createDescriptor,
  AccountDirectoryLayout
} from '@tgx/core-account';
import { FakeAppFiles } from '@tgx/platform-ports';
import {
  TdNativeBridgeLike,
  TdNativeBridgeMetrics,
  TdNativeEventSink,
  TdPendingRequest,
  TdWireObject,
  TdWireValue
} from '@tgx/td-gateway';
import { Result, AppError } from '@tgx/core-common';
import {
  ALL_PAGE_BLOCK_TYPES,
  InstantViewBlock,
  InstantViewBlockKind,
  InstantViewPage,
  classifyPageBlockType,
  flattenInstantViewBlocks,
  projectInstantViewPage,
  richTextToPlain
} from '../../main/ets/webpage/InstantViewModel';
import { WebPageProjection } from '../../main/ets/webpage/WebPageProjection';

// ---- 桥与账号夹具（同 MessageProjection.test 的既定模式） ----

interface SentBridgeRequest {
  readonly clientId: number;
  readonly utf8: string;
}

class TestNativeBridge implements TdNativeBridgeLike {
  version: string = '1.8.67-test';
  readonly sent: SentBridgeRequest[] = [];
  private nextSubId: number = 1;

  getVersion(): string {
    return this.version;
  }

  createClient(): number {
    return 1;
  }

  send(clientId: number, requestUtf8: string): void {
    const entry: SentBridgeRequest = { clientId: clientId, utf8: requestUtf8 };
    this.sent.push(entry);
  }

  execute(requestUtf8: string): string | null {
    return '{"@type":"ok"}';
  }

  subscribeUpdates(sink: TdNativeEventSink): number {
    const id: number = this.nextSubId;
    this.nextSubId += 1;
    return id;
  }

  unsubscribe(subscriptionId: number): void {
    //本测试不消费 update 流，无需记录退订。
  }

  getMetrics(): TdNativeBridgeMetrics {
    return {
      queueSize: 0,
      overflowWaitCount: 0,
      droppedCount: 0,
      eventsForwarded: 0,
      subscriptions: 0,
      dispatcherRunning: true
    };
  }

  lastSentJson(): Record<string, TdWireValue> {
    const last: SentBridgeRequest = this.sent[this.sent.length - 1];
    return JSON.parse(last.utf8) as Record<string, TdWireValue>;
  }
}

function createScope(bridge: TestNativeBridge): AccountScope {
  const layoutRes: Result<AccountDirectoryLayout, AppError> = buildAccountDirectories('test_webpage_projection');
  if (layoutRes.ok === false) {
    throw new Error('Failed to build directories');
  }
  const scopeRes: Result<AccountScope, AppError> = AccountScope.open({
    bridge: bridge,
    files: new FakeAppFiles(),
    descriptor: createDescriptor('test_webpage_projection', 'acct_user_1', 0, true),
    directories: layoutRes.value,
    startActive: true
  });
  if (scopeRes.ok === false) {
    throw new Error('Failed to open AccountScope');
  }
  return scopeRes.value;
}

// ---- RichText / 媒体夹具 ----

function makeText(value: string): TdRichText {
  const plain: RichTextPlain = new RichTextPlain();
  plain.text = value;
  return plain;
}

function makeBold(inner: TdRichText): TdRichText {
  const bold: RichTextBold = new RichTextBold();
  bold.text = inner;
  return bold;
}

function makeFile(fileId: number): File {
  const file: File = new File();
  file.id = fileId;
  return file;
}

function makePhotoSize(width: number, height: number, fileId: number): PhotoSize {
  const size: PhotoSize = new PhotoSize();
  size.type_ = 'x';
  size.width = width;
  size.height = height;
  size.photo = makeFile(fileId);
  return size;
}

function makePhoto(sizes: PhotoSize[]): Photo {
  const photo: Photo = new Photo();
  photo.sizes = sizes;
  return photo;
}

function makePhotoBlock(fileId: number, width: number, height: number): PageBlockPhoto {
  const block: PageBlockPhoto = new PageBlockPhoto();
  block.photo = makePhoto([makePhotoSize(width, height, fileId)]);
  return block;
}

function makeCaption(text: string, credit: string): PageBlockCaption {
  const caption: PageBlockCaption = new PageBlockCaption();
  caption.text = makeText(text);
  caption.credit = credit.length === 0 ? null : makeText(credit);
  return caption;
}

function makeParagraph(text: string): PageBlockParagraph {
  const para: PageBlockParagraph = new PageBlockParagraph();
  para.text = makeText(text);
  return para;
}

function makeUrlButton(text: string, url: string): InlineButton {
  const button: InlineButton = new InlineButton();
  button.text = makeText(text);
  const urlType: InlineKeyboardButtonTypeUrl = new InlineKeyboardButtonTypeUrl();
  urlType.url = url;
  button.type_ = urlType;
  return button;
}

function makeCallbackButton(text: string): InlineButton {
  const button: InlineButton = new InlineButton();
  button.text = makeText(text);
  button.type_ = new InlineKeyboardButtonTypeCallback();
  return button;
}

function makeChatPhoto(fileId: number): ChatPhotoInfo {
  const info: ChatPhotoInfo = new ChatPhotoInfo();
  info.big = makeFile(fileId);
  return info;
}

// ---- 全量归并对照表（独立于实现维护，防 classify 漏归并） ----

class TypeExpectation {
  readonly sourceType: string;
  readonly expected: InstantViewBlockKind;

  constructor(sourceType: string, expected: InstantViewBlockKind) {
    this.sourceType = sourceType;
    this.expected = expected;
  }
}

const EXPECTED_KINDS: TypeExpectation[] = [
  new TypeExpectation('pageBlockAnchor', 'anchor'),
  new TypeExpectation('pageBlockAnimation', 'figure'),
  new TypeExpectation('pageBlockAudio', 'figure'),
  new TypeExpectation('pageBlockAuthorDate', 'byline'),
  new TypeExpectation('pageBlockBlockQuote', 'quote'),
  new TypeExpectation('pageBlockButtonRow', 'buttons'),
  new TypeExpectation('pageBlockCaption', 'caption'),
  new TypeExpectation('pageBlockChatLink', 'chatLink'),
  new TypeExpectation('pageBlockCollage', 'figure'),
  new TypeExpectation('pageBlockCover', 'figure'),
  new TypeExpectation('pageBlockDetails', 'details'),
  new TypeExpectation('pageBlockDivider', 'divider'),
  new TypeExpectation('pageBlockDocument', 'figure'),
  new TypeExpectation('pageBlockEmbedded', 'figure'),
  new TypeExpectation('pageBlockEmbeddedPost', 'figure'),
  new TypeExpectation('pageBlockExpandableBlockQuote', 'quote'),
  new TypeExpectation('pageBlockFooter', 'paragraph'),
  new TypeExpectation('pageBlockHeader', 'header'),
  new TypeExpectation('pageBlockHorizontalAlignmentCenter', 'tableAlign'),
  new TypeExpectation('pageBlockHorizontalAlignmentLeft', 'tableAlign'),
  new TypeExpectation('pageBlockHorizontalAlignmentRight', 'tableAlign'),
  new TypeExpectation('pageBlockKicker', 'kicker'),
  new TypeExpectation('pageBlockList', 'list'),
  new TypeExpectation('pageBlockListItem', 'listItem'),
  new TypeExpectation('pageBlockMap', 'figure'),
  new TypeExpectation('pageBlockMathematicalExpression', 'paragraph'),
  new TypeExpectation('pageBlockParagraph', 'paragraph'),
  new TypeExpectation('pageBlockPhoto', 'figure'),
  new TypeExpectation('pageBlockPreformatted', 'preformatted'),
  new TypeExpectation('pageBlockPullQuote', 'pullquote'),
  new TypeExpectation('pageBlockRelatedArticle', 'related'),
  new TypeExpectation('pageBlockRelatedArticles', 'related'),
  new TypeExpectation('pageBlockSectionHeading', 'header'),
  new TypeExpectation('pageBlockSlideshow', 'figure'),
  new TypeExpectation('pageBlockSubheader', 'header'),
  new TypeExpectation('pageBlockSubtitle', 'subtitle'),
  new TypeExpectation('pageBlockTable', 'table'),
  new TypeExpectation('pageBlockTableCell', 'tableCell'),
  new TypeExpectation('pageBlockThinking', 'paragraph'),
  new TypeExpectation('pageBlockTitle', 'title'),
  new TypeExpectation('pageBlockUnsupported', 'unknown'),
  new TypeExpectation('pageBlockVerticalAlignmentBottom', 'tableAlign'),
  new TypeExpectation('pageBlockVerticalAlignmentMiddle', 'tableAlign'),
  new TypeExpectation('pageBlockVerticalAlignmentTop', 'tableAlign'),
  new TypeExpectation('pageBlockVideo', 'figure'),
  new TypeExpectation('pageBlockVoiceNote', 'figure')
];

// 36 个 PageBlock union 成员（TdUnions_P 的 TdPageBlock，不含 10 个吸收型辅助块）。
const UNION_BLOCK_TYPES: string[] = [
  'pageBlockAnchor',
  'pageBlockAnimation',
  'pageBlockAudio',
  'pageBlockAuthorDate',
  'pageBlockBlockQuote',
  'pageBlockButtonRow',
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
  'pageBlockKicker',
  'pageBlockList',
  'pageBlockMap',
  'pageBlockMathematicalExpression',
  'pageBlockParagraph',
  'pageBlockPhoto',
  'pageBlockPreformatted',
  'pageBlockPullQuote',
  'pageBlockRelatedArticles',
  'pageBlockSectionHeading',
  'pageBlockSlideshow',
  'pageBlockSubheader',
  'pageBlockSubtitle',
  'pageBlockTable',
  'pageBlockThinking',
  'pageBlockTitle',
  'pageBlockUnsupported',
  'pageBlockVideo',
  'pageBlockVoiceNote'
];

/** 为 36 个 union 成员各造一个最小实例（media 挂真实 File，文本挂 RichText）。 */
function makeUnionSample(sourceType: string): TdPageBlock {
  switch (sourceType) {
    case 'pageBlockAnchor': {
      const b: PageBlockAnchor = new PageBlockAnchor();
      b.name = '锚点';
      return b;
    }
    case 'pageBlockAnimation': {
      const b: PageBlockAnimation = new PageBlockAnimation();
      const anim: Animation = new Animation();
      anim.animation = makeFile(21);
      anim.width = 320;
      anim.height = 240;
      b.animation = anim;
      b.caption = makeCaption('动图', '');
      return b;
    }
    case 'pageBlockAudio': {
      const b: PageBlockAudio = new PageBlockAudio();
      const audio: Audio = new Audio();
      audio.audio = makeFile(30);
      b.audio = audio;
      b.caption = makeCaption('音频', '');
      return b;
    }
    case 'pageBlockAuthorDate': {
      const b: PageBlockAuthorDate = new PageBlockAuthorDate();
      b.author = makeText('作者');
      b.publish_date = 1700000000;
      return b;
    }
    case 'pageBlockBlockQuote': {
      const b: PageBlockBlockQuote = new PageBlockBlockQuote();
      b.blocks = [makeParagraph('引用')];
      b.credit = makeText('出处');
      return b;
    }
    case 'pageBlockButtonRow': {
      const b: PageBlockButtonRow = new PageBlockButtonRow();
      b.buttons = [makeUrlButton('打开', 'https://example.com')];
      return b;
    }
    case 'pageBlockChatLink': {
      const b: PageBlockChatLink = new PageBlockChatLink();
      b.title = '频道';
      b.username = 'example';
      b.photo = makeChatPhoto(44);
      return b;
    }
    case 'pageBlockCollage': {
      const b: PageBlockCollage = new PageBlockCollage();
      b.blocks = [makePhotoBlock(77, 800, 600), makePhotoBlock(88, 400, 300)];
      b.caption = makeCaption('拼图', '');
      return b;
    }
    case 'pageBlockCover': {
      const b: PageBlockCover = new PageBlockCover();
      b.cover = makePhotoBlock(77, 800, 600);
      return b;
    }
    case 'pageBlockDetails': {
      const b: PageBlockDetails = new PageBlockDetails();
      b.header = makeText('更多');
      b.blocks = [makeParagraph('内层')];
      b.is_open = true;
      return b;
    }
    case 'pageBlockDivider': {
      return new PageBlockDivider();
    }
    case 'pageBlockDocument': {
      const b: PageBlockDocument = new PageBlockDocument();
      const doc: Document = new Document();
      doc.document = makeFile(9);
      b.document = doc;
      b.caption = makeCaption('文件', '');
      return b;
    }
    case 'pageBlockEmbedded': {
      const b: PageBlockEmbedded = new PageBlockEmbedded();
      b.url = 'https://youtube.com/watch?v=x';
      b.width = 640;
      b.height = 360;
      b.caption = makeCaption('嵌入', '');
      return b;
    }
    case 'pageBlockEmbeddedPost': {
      const b: PageBlockEmbeddedPost = new PageBlockEmbeddedPost();
      b.url = 'https://t.me/s/channel/12';
      b.author = 'user';
      b.date = 1700000000;
      b.blocks = [makeParagraph('帖子内容')];
      b.caption = makeCaption('帖子', '');
      return b;
    }
    case 'pageBlockExpandableBlockQuote': {
      const b: PageBlockExpandableBlockQuote = new PageBlockExpandableBlockQuote();
      b.text = makeText('展开引用');
      b.credit = makeText('来源');
      return b;
    }
    case 'pageBlockFooter': {
      const b: PageBlockFooter = new PageBlockFooter();
      b.footer = makeText('页脚');
      return b;
    }
    case 'pageBlockHeader': {
      const b: PageBlockHeader = new PageBlockHeader();
      b.header = makeText('标题头');
      return b;
    }
    case 'pageBlockKicker': {
      const b: PageBlockKicker = new PageBlockKicker();
      b.kicker = makeText('眉题');
      return b;
    }
    case 'pageBlockList': {
      const b: PageBlockList = new PageBlockList();
      const item: PageBlockListItem = new PageBlockListItem();
      item.label = '1';
      item.blocks = [makeParagraph('条目一')];
      b.items = [item];
      return b;
    }
    case 'pageBlockMap': {
      const b: PageBlockMap = new PageBlockMap();
      const loc: Location = new Location();
      loc.latitude = 31.2;
      loc.longitude = 121.4;
      b.location = loc;
      b.zoom = 12;
      b.width = 320;
      b.height = 240;
      b.caption = makeCaption('地图', '');
      return b;
    }
    case 'pageBlockMathematicalExpression': {
      const b: PageBlockMathematicalExpression = new PageBlockMathematicalExpression();
      b.expression = 'E=mc^2';
      return b;
    }
    case 'pageBlockParagraph': {
      return makeParagraph('段落');
    }
    case 'pageBlockPhoto': {
      const b: PageBlockPhoto = new PageBlockPhoto();
      b.photo = makePhoto([makePhotoSize(400, 300, 33), makePhotoSize(800, 600, 77)]);
      b.caption = makeCaption('图注', '来源');
      b.url = 'https://t.me/x';
      return b;
    }
    case 'pageBlockPreformatted': {
      const b: PageBlockPreformatted = new PageBlockPreformatted();
      b.text = makeText('code()');
      b.language = 'python';
      return b;
    }
    case 'pageBlockPullQuote': {
      const b: PageBlockPullQuote = new PageBlockPullQuote();
      b.text = makeText('拉引');
      b.credit = makeText('署名');
      return b;
    }
    case 'pageBlockRelatedArticles': {
      const b: PageBlockRelatedArticles = new PageBlockRelatedArticles();
      b.header = makeText('相关阅读');
      const article: PageBlockRelatedArticle = new PageBlockRelatedArticle();
      article.url = 'https://t.me/a';
      article.title = '文章一';
      article.description = '摘要';
      article.photo = makePhoto([makePhotoSize(100, 100, 66)]);
      article.publish_date = 1700000000;
      b.articles = [article];
      return b;
    }
    case 'pageBlockSectionHeading': {
      const b: PageBlockSectionHeading = new PageBlockSectionHeading();
      b.text = makeText('小节');
      b.size = 1;
      return b;
    }
    case 'pageBlockSlideshow': {
      const b: PageBlockSlideshow = new PageBlockSlideshow();
      b.blocks = [makePhotoBlock(77, 800, 600), makePhotoBlock(88, 400, 300)];
      b.caption = makeCaption('幻灯', '');
      return b;
    }
    case 'pageBlockSubheader': {
      const b: PageBlockSubheader = new PageBlockSubheader();
      b.subheader = makeText('副标头');
      return b;
    }
    case 'pageBlockSubtitle': {
      const b: PageBlockSubtitle = new PageBlockSubtitle();
      b.subtitle = makeText('副标题');
      return b;
    }
    case 'pageBlockTable': {
      const b: PageBlockTable = new PageBlockTable();
      b.caption = makeText('表格');
      const headerCell: PageBlockTableCell = new PageBlockTableCell();
      headerCell.text = makeText('列一');
      headerCell.is_header = true;
      const dataCell: PageBlockTableCell = new PageBlockTableCell();
      dataCell.text = makeText('甲');
      b.cells = [[headerCell, dataCell]];
      b.is_bordered = true;
      b.is_striped = true;
      return b;
    }
    case 'pageBlockThinking': {
      const b: PageBlockThinking = new PageBlockThinking();
      b.text = makeText('思考中');
      return b;
    }
    case 'pageBlockTitle': {
      const b: PageBlockTitle = new PageBlockTitle();
      b.title = makeText('页面标题');
      return b;
    }
    case 'pageBlockUnsupported': {
      return new PageBlockUnsupported();
    }
    case 'pageBlockVideo': {
      const b: PageBlockVideo = new PageBlockVideo();
      const video: Video = new Video();
      video.video = makeFile(55);
      video.width = 1280;
      video.height = 720;
      b.video = video;
      b.caption = makeCaption('视频', '');
      return b;
    }
    case 'pageBlockVoiceNote': {
      const b: PageBlockVoiceNote = new PageBlockVoiceNote();
      const voice: VoiceNote = new VoiceNote();
      voice.voice = makeFile(12);
      b.voice_note = voice;
      b.caption = makeCaption('语音', '');
      return b;
    }
    default: {
      //占位：样本表漏造实例时会让 kind 一致性测试直接失败。
      return new TdUnknownObject(sourceType, {});
    }
  }
}

// ---- InstantViewModel ----

export default function instantViewModelTest() {
  describe('InstantViewModel', () => {

    it('classify_coversAllFortySixPageBlockTypes', 0, (): void => {
      expect(ALL_PAGE_BLOCK_TYPES.length).assertEqual(46);
      expect(EXPECTED_KINDS.length).assertEqual(46);
      //双向集合一致：ALL_PAGE_BLOCK_TYPES 与对照表逐项对齐（顺序+数量+无重复）。
      for (let i = 0; i < EXPECTED_KINDS.length; i++) {
        expect(EXPECTED_KINDS[i].sourceType).assertEqual(ALL_PAGE_BLOCK_TYPES[i]);
      }
      for (let i = 0; i < ALL_PAGE_BLOCK_TYPES.length; i++) {
        for (let j = i + 1; j < ALL_PAGE_BLOCK_TYPES.length; j++) {
          expect(ALL_PAGE_BLOCK_TYPES[i] === ALL_PAGE_BLOCK_TYPES[j]).assertFalse();
        }
      }
      //每个已知 @type 都有明确去处（含 10 个吸收型辅助块与 pageBlockUnsupported）。
      for (const expectation of EXPECTED_KINDS) {
        expect(classifyPageBlockType(expectation.sourceType)).assertEqual(expectation.expected);
      }
      //未知 @type（TDLib 升级新增块型）必须落 unknown 兜底。
      expect(classifyPageBlockType('pageBlockHologram')).assertEqual('unknown');
      expect(classifyPageBlockType('')).assertEqual('unknown');
    });

    it('flatten_mapsEveryUnionBlockToItsClassifiedKind', 0, (): void => {
      expect(UNION_BLOCK_TYPES.length).assertEqual(36);
      for (const sourceType of UNION_BLOCK_TYPES) {
        const out: InstantViewBlock[] = flattenInstantViewBlocks([makeUnionSample(sourceType)], []);
        expect(out.length).assertEqual(1);
        expect(out[0].kind).assertEqual(classifyPageBlockType(sourceType));
        expect(out[0].sourceType).assertEqual(sourceType);
      }
    });

    it('flatten_textBlocksCarryPlainTextAndMetadata', 0, (): void => {
      const out: InstantViewBlock[] = flattenInstantViewBlocks([
        makeUnionSample('pageBlockTitle'),
        makeUnionSample('pageBlockParagraph'),
        makeUnionSample('pageBlockPreformatted'),
        makeUnionSample('pageBlockMathematicalExpression'),
        makeUnionSample('pageBlockAuthorDate'),
        makeUnionSample('pageBlockAnchor'),
        makeUnionSample('pageBlockFooter'),
        makeUnionSample('pageBlockKicker'),
        makeUnionSample('pageBlockSubtitle')
      ], []);

      expect(out.length).assertEqual(9);
      expect(out[0].text).assertEqual('页面标题');
      expect(out[0].level).assertEqual(1);
      expect(out[1].text).assertEqual('段落');
      expect(out[1].level).assertEqual(0);
      expect(out[2].kind).assertEqual('preformatted');
      expect(out[2].language).assertEqual('python');
      expect(out[3].kind).assertEqual('paragraph');
      expect(out[3].text).assertEqual('E=mc^2');
      expect(out[4].kind).assertEqual('byline');
      expect(out[4].text).assertEqual('作者');
      expect(out[4].publishDate).assertEqual(1700000000);
      expect(out[5].kind).assertEqual('anchor');
      expect(out[5].text).assertEqual('锚点');
      expect(out[6].kind).assertEqual('paragraph');
      expect(out[6].text).assertEqual('页脚');
      expect(out[7].kind).assertEqual('kicker');
      expect(out[7].text).assertEqual('眉题');
      expect(out[8].kind).assertEqual('subtitle');
      expect(out[8].text).assertEqual('副标题');
    });

    it('flatten_headingsCollapseToHeaderWithLevels', 0, (): void => {
      const out: InstantViewBlock[] = flattenInstantViewBlocks([
        makeUnionSample('pageBlockHeader'),
        makeUnionSample('pageBlockSubheader'),
        makeUnionSample('pageBlockSectionHeading')
      ], []);
      expect(out.length).assertEqual(3);
      expect(out[0].kind).assertEqual('header');
      expect(out[0].level).assertEqual(2);
      expect(out[1].kind).assertEqual('header');
      expect(out[1].level).assertEqual(3);
      expect(out[2].kind).assertEqual('header');
      expect(out[2].level).assertEqual(4);
    });

    it('flatten_flattensQuoteInnerBlocksAndListItems', 0, (): void => {
      //quote：内层段落递归拍平按 \n 连接，credit 独立保留。
      const quote: PageBlockBlockQuote = new PageBlockBlockQuote();
      quote.blocks = [makeParagraph('第一段'), makeParagraph('第二段')];
      quote.credit = makeText('某记者');
      const out: InstantViewBlock[] = flattenInstantViewBlocks([quote], []);
      expect(out.length).assertEqual(1);
      expect(out[0].kind).assertEqual('quote');
      expect(out[0].text).assertEqual('第一段\n第二段');
      expect(out[0].credit).assertEqual('某记者');

      //list：item 内层块拍平为文本，label 与勾选态保留。
      const list: PageBlockList = new PageBlockList();
      const item1: PageBlockListItem = new PageBlockListItem();
      item1.label = '1';
      item1.blocks = [makeParagraph('条目一')];
      const item2: PageBlockListItem = new PageBlockListItem();
      item2.blocks = [makeParagraph('条目二')];
      item2.has_checkbox = true;
      item2.is_checked = true;
      list.items = [item1, item2];
      const out2: InstantViewBlock[] = flattenInstantViewBlocks([list], []);
      expect(out2.length).assertEqual(1);
      expect(out2[0].kind).assertEqual('list');
      expect(out2[0].items.length).assertEqual(2);
      expect(out2[0].items[0].label).assertEqual('1');
      expect(out2[0].items[0].text).assertEqual('条目一');
      expect(out2[0].items[0].hasCheckbox).assertFalse();
      expect(out2[0].items[1].text).assertEqual('条目二');
      expect(out2[0].items[1].hasCheckbox).assertTrue();
      expect(out2[0].items[1].isChecked).assertTrue();
    });

    it('flatten_detailsCollageAndCoverKeepChildrenTree', 0, (): void => {
      //details：header 进 text，内层块递归成 children，展开态保留。
      const out: InstantViewBlock[] = flattenInstantViewBlocks([makeUnionSample('pageBlockDetails')], []);
      expect(out.length).assertEqual(1);
      expect(out[0].kind).assertEqual('details');
      expect(out[0].text).assertEqual('更多');
      expect(out[0].isOpen).assertTrue();
      expect(out[0].children.length).assertEqual(1);
      expect(out[0].children[0].kind).assertEqual('paragraph');
      expect(out[0].children[0].text).assertEqual('内层');

      //collage：子图递归成 figure children，caption 上提到父块。
      const out2: InstantViewBlock[] = flattenInstantViewBlocks([makeUnionSample('pageBlockCollage')], []);
      expect(out2[0].kind).assertEqual('figure');
      expect(out2[0].mediaType).assertEqual('collage');
      expect(out2[0].caption).assertEqual('拼图');
      expect(out2[0].children.length).assertEqual(2);
      expect(out2[0].children[0].kind).assertEqual('figure');
      expect(out2[0].children[0].mediaType).assertEqual('photo');
      expect(out2[0].children[0].fileId).assertEqual(77);

      //cover：内嵌封面块递归进 children。
      const out3: InstantViewBlock[] = flattenInstantViewBlocks([makeUnionSample('pageBlockCover')], []);
      expect(out3[0].mediaType).assertEqual('cover');
      expect(out3[0].children.length).assertEqual(1);
      expect(out3[0].children[0].mediaType).assertEqual('photo');
      expect(out3[0].children[0].fileId).assertEqual(77);
    });

    it('flatten_mediaBlocksExtractLargestFileIdAndCaption', 0, (): void => {
      //photo：多尺寸取面积最大一档的 fileId 与尺寸，caption/credit/url 齐备。
      const out: InstantViewBlock[] = flattenInstantViewBlocks([makeUnionSample('pageBlockPhoto')], []);
      expect(out[0].kind).assertEqual('figure');
      expect(out[0].mediaType).assertEqual('photo');
      expect(out[0].fileId).assertEqual(77);
      expect(out[0].width).assertEqual(800);
      expect(out[0].height).assertEqual(600);
      expect(out[0].caption).assertEqual('图注');
      expect(out[0].credit).assertEqual('来源');
      expect(out[0].url).assertEqual('https://t.me/x');

      //video / animation：fileId 与固有宽高来自媒体对象本身。
      const out2: InstantViewBlock[] = flattenInstantViewBlocks([
        makeUnionSample('pageBlockVideo'),
        makeUnionSample('pageBlockAnimation'),
        makeUnionSample('pageBlockAudio'),
        makeUnionSample('pageBlockVoiceNote'),
        makeUnionSample('pageBlockDocument')
      ], []);
      expect(out2.length).assertEqual(5);
      expect(out2[0].mediaType).assertEqual('video');
      expect(out2[0].fileId).assertEqual(55);
      expect(out2[0].width).assertEqual(1280);
      expect(out2[0].height).assertEqual(720);
      expect(out2[0].caption).assertEqual('视频');
      expect(out2[1].mediaType).assertEqual('animation');
      expect(out2[1].fileId).assertEqual(21);
      expect(out2[1].width).assertEqual(320);
      expect(out2[1].height).assertEqual(240);
      expect(out2[2].mediaType).assertEqual('audio');
      expect(out2[2].fileId).assertEqual(30);
      expect(out2[3].mediaType).assertEqual('voiceNote');
      expect(out2[3].fileId).assertEqual(12);
      expect(out2[4].mediaType).assertEqual('document');
      expect(out2[4].fileId).assertEqual(9);
    });

    it('flatten_mapCarriesLocationAndSize', 0, (): void => {
      const out: InstantViewBlock[] = flattenInstantViewBlocks([makeUnionSample('pageBlockMap')], []);
      expect(out[0].mediaType).assertEqual('map');
      expect(out[0].latitude).assertEqual(31.2);
      expect(out[0].longitude).assertEqual(121.4);
      expect(out[0].width).assertEqual(320);
      expect(out[0].height).assertEqual(240);
      expect(out[0].caption).assertEqual('地图');
    });

    it('flatten_tableCarriesRowsAndStyles', 0, (): void => {
      const out: InstantViewBlock[] = flattenInstantViewBlocks([makeUnionSample('pageBlockTable')], []);
      expect(out[0].kind).assertEqual('table');
      expect(out[0].caption).assertEqual('表格');
      expect(out[0].rows.length).assertEqual(1);
      expect(out[0].rows[0].length).assertEqual(2);
      expect(out[0].rows[0][0]).assertEqual('列一');
      expect(out[0].rows[0][1]).assertEqual('甲');
      expect(out[0].isBordered).assertTrue();
      expect(out[0].isStriped).assertTrue();
    });

    it('flatten_relatedArticlesBuildArticleCards', 0, (): void => {
      const out: InstantViewBlock[] = flattenInstantViewBlocks([makeUnionSample('pageBlockRelatedArticles')], []);
      expect(out.length).assertEqual(1);
      expect(out[0].kind).assertEqual('related');
      expect(out[0].text).assertEqual('相关阅读');
      expect(out[0].children.length).assertEqual(1);
      const card: InstantViewBlock = out[0].children[0];
      expect(card.kind).assertEqual('related');
      expect(card.sourceType).assertEqual('pageBlockRelatedArticle');
      expect(card.text).assertEqual('文章一');
      expect(card.caption).assertEqual('摘要');
      expect(card.url).assertEqual('https://t.me/a');
      expect(card.fileId).assertEqual(66);
      expect(card.publishDate).assertEqual(1700000000);
    });

    it('flatten_buttonRowExtractsUrlFromButtonType', 0, (): void => {
      const row: PageBlockButtonRow = new PageBlockButtonRow();
      row.buttons = [makeUrlButton('打开', 'https://example.com'), makeCallbackButton('反馈')];
      const out: InstantViewBlock[] = flattenInstantViewBlocks([row], []);
      expect(out.length).assertEqual(1);
      expect(out[0].kind).assertEqual('buttons');
      expect(out[0].children.length).assertEqual(2);
      expect(out[0].children[0].kind).assertEqual('button');
      expect(out[0].children[0].text).assertEqual('打开');
      expect(out[0].children[0].url).assertEqual('https://example.com');
      //非 URL 型按钮不臆造链接。
      expect(out[0].children[1].url).assertEqual('');
      expect(out[0].children[1].text).assertEqual('反馈');
    });

    it('flatten_unknownTypeKeepsRawTypeForGracefulSkip', 0, (): void => {
      //TDLib 升级新增块型 → TdUnknownObject：kind=unknown 且原始 @type 保留。
      const future: TdPageBlock = new TdUnknownObject('pageBlockHologram', {});
      const out: InstantViewBlock[] = flattenInstantViewBlocks([future], []);
      expect(out.length).assertEqual(1);
      expect(out[0].kind).assertEqual('unknown');
      expect(out[0].sourceType).assertEqual('pageBlockHologram');
      expect(out[0].text).assertEqual('');

      //pageBlockUnsupported：已知协议块型，同样归 unknown 走降级占位。
      const out2: InstantViewBlock[] = flattenInstantViewBlocks([new PageBlockUnsupported()], []);
      expect(out2.length).assertEqual(1);
      expect(out2[0].kind).assertEqual('unknown');
      expect(out2[0].sourceType).assertEqual('pageBlockUnsupported');
    });

    it('flatten_emptyBlocksAppendsNothingAndReusesOut', 0, (): void => {
      const out: InstantViewBlock[] = [];
      const returned: InstantViewBlock[] = flattenInstantViewBlocks([], out);
      expect(returned.length).assertEqual(0);
      //out 缓冲复用语义：传入既有内容保留，新块追加其后。
      const preexisting: InstantViewBlock[] = flattenInstantViewBlocks([makeUnionSample('pageBlockTitle')], []);
      expect(preexisting.length).assertEqual(1);
      const again: InstantViewBlock[] = flattenInstantViewBlocks([], preexisting);
      expect(again.length).assertEqual(1);
      expect(again[0].kind).assertEqual('title');
    });

    it('richTextToPlain_walksNestedStylesAndEntities', 0, (): void => {
      const texts: RichTexts = new RichTexts();
      const emoji: RichTextCustomEmoji = new RichTextCustomEmoji();
      emoji.alternative_text = '表情';
      texts.texts = [makeBold(makeText('加粗')), makeText('普通'), emoji];
      expect(richTextToPlain(texts)).assertEqual('加粗普通表情');

      const anchorLink: RichTextAnchorLink = new RichTextAnchorLink();
      anchorLink.text = makeText('链接');
      anchorLink.url = 'https://t.me/x';
      expect(richTextToPlain(anchorLink)).assertEqual('链接');

      const icon: RichTextIcon = new RichTextIcon();
      expect(richTextToPlain(icon)).assertEqual('');

      const button: RichTextButton = new RichTextButton();
      button.button = makeUrlButton('按钮', 'https://t.me/y');
      expect(richTextToPlain(button)).assertEqual('按钮');

      expect(richTextToPlain(null)).assertEqual('');
      expect(richTextToPlain(new TdUnknownObject('richTextFuture', {}))).assertEqual('');
    });

    it('projectInstantView_mapsPageMetadataAndBlocks', 0, (): void => {
      const instantView: WebPageInstantView = new WebPageInstantView();
      instantView.blocks = [makeUnionSample('pageBlockTitle'), makeUnionSample('pageBlockParagraph')];
      instantView.version = 2;
      instantView.is_rtl = true;
      instantView.is_full = false;
      instantView.view_count = 5;

      const page: InstantViewPage = projectInstantViewPage(instantView);
      expect(page.blocks.length).assertEqual(2);
      expect(page.version).assertEqual(2);
      expect(page.isRtl).assertTrue();
      expect(page.isFull).assertFalse();
      expect(page.viewCount).assertEqual(5);
      expect(page.blocks[0].kind).assertEqual('title');
      expect(page.blocks[1].kind).assertEqual('paragraph');
    });

    it('projectInstantView_roundTripsThroughWireEncoding', 0, (): void => {
      //走一遍 encode → decode 全链路，验证 decodeTdPageBlock 分发后的块型
      //仍能被投影正确识别（防「解码产物与投影入参类型不一致」回归）。
      const instantView: WebPageInstantView = new WebPageInstantView();
      instantView.blocks = [makeUnionSample('pageBlockPhoto'), makeUnionSample('pageBlockDivider')];
      instantView.version = 1;

      const decoded: WebPageInstantView | null = decodeWebPageInstantView(encodeWebPageInstantView(instantView));
      if (decoded === null) {
        // decode 失败要在这一行让用例失败（hypium 无 assertNotNull，按仓库口径断言布尔）
        expect(decoded !== null).assertTrue();
        return;
      }
      const page: InstantViewPage = projectInstantViewPage(decoded);
      expect(page.blocks.length).assertEqual(2);
      expect(page.blocks[0].kind).assertEqual('figure');
      expect(page.blocks[0].mediaType).assertEqual('photo');
      expect(page.blocks[0].fileId).assertEqual(77);
      expect(page.blocks[1].kind).assertEqual('divider');
    });
  });

  // ---- WebPageProjection ----

  describe('WebPageProjection', () => {

    it('fetchInstantView_rejectsEmptyUrlWithoutSending', 0, (): void => {
      const bridge: TestNativeBridge = new TestNativeBridge();
      const projection: WebPageProjection = new WebPageProjection(createScope(bridge));

      const emptyRes: Result<TdPendingRequest, AppError> = projection.fetchInstantView('');
      expect(emptyRes.ok).assertFalse();
      if (emptyRes.ok === false && emptyRes.error.kind === 'parameter') {
        expect(emptyRes.error.code).assertEqual('missing');
        expect(emptyRes.error.field).assertEqual('url');
      }

      const blankRes: Result<TdPendingRequest, AppError> = projection.fetchInstantView('   ');
      expect(blankRes.ok).assertFalse();
      //两种空串都不发起请求（桥上零字节是硬证据）。
      expect(bridge.sent.length).assertEqual(0);
    });

    it('fetchInstantView_rejectsNonHttpUrlWithoutSending', 0, (): void => {
      const bridge: TestNativeBridge = new TestNativeBridge();
      const projection: WebPageProjection = new WebPageProjection(createScope(bridge));

      const badUrls: string[] = [
        'ftp://example.com/a',
        'tg://resolve?domain=telegram',
        'example.com/page',
        'javascript:alert(1)',
        'httpx://example.com'
      ];
      for (const bad of badUrls) {
        const res: Result<TdPendingRequest, AppError> = projection.fetchInstantView(bad);
        expect(res.ok).assertFalse();
        if (res.ok === false && res.error.kind === 'parameter') {
          expect(res.error.code).assertEqual('invalid');
          expect(res.error.field).assertEqual('url');
        }
      }
      expect(bridge.sent.length).assertEqual(0);
    });

    it('fetchInstantView_sendsGetWebPageInstantViewRequest', 0, (): void => {
      const bridge: TestNativeBridge = new TestNativeBridge();
      const projection: WebPageProjection = new WebPageProjection(createScope(bridge));

      const res: Result<TdPendingRequest, AppError> = projection.fetchInstantView('https://telegra.ph/Post-01');
      expect(res.ok).assertTrue();
      expect(bridge.sent.length).assertEqual(1);

      const sent: Record<string, TdWireValue> = bridge.lastSentJson();
      expect(sent['@type']).assertEqual('getWebPageInstantView');
      expect(sent['url']).assertEqual('https://telegra.ph/Post-01');
      expect(sent['only_local']).assertEqual(false);
    });

    it('fetchInstantView_trimsUrlAndHonorsOnlyLocal', 0, (): void => {
      const bridge: TestNativeBridge = new TestNativeBridge();
      const projection: WebPageProjection = new WebPageProjection(createScope(bridge));

      const res: Result<TdPendingRequest, AppError> = projection.fetchInstantView('  https://t.me/faq  ', true);
      expect(res.ok).assertTrue();
      const sent: Record<string, TdWireValue> = bridge.lastSentJson();
      expect(sent['url']).assertEqual('https://t.me/faq');
      expect(sent['only_local']).assertEqual(true);
    });

    it('projectInstantView_degradesLenientlyOnBrokenPayload', 0, (): void => {
      const bridge: TestNativeBridge = new TestNativeBridge();
      const projection: WebPageProjection = new WebPageProjection(createScope(bridge));

      //null / undefined 回包 → null（无 Instant View，调用方降级开浏览器）。
      expect(projection.projectInstantView(null)).assertNull();
      //生成解码器对形状残缺的 payload 是宽松的：字段缺失退默认值，
      //得到空 blocks 的页模型而不是抛异常 —— 阅读器渲染空页不崩。
      const broken: TdWireObject = {};
      broken['@type'] = 'notAWebPageInstantView';
      const page: InstantViewPage | null = projection.projectInstantView(broken as TdJsonRaw);
      expect(page === null).assertFalse();
      if (page !== null) {
        expect(page.blocks.length).assertEqual(0);
      }
    });
  });
}
