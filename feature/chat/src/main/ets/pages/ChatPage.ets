/**
 * feature/chat — ChatPage：单会话消息页（CHAT-001 + CHAT-002 基础 + CHAT-003 输入栏 + CHAT-004 消息动作）。
 *
 * 顶部：返回箭头 + 会话标题；主体：LazyForEach 消息气泡列表（最旧在前、
 * 最新在底，首屏/新消息自动滚到底）；文本气泡：发出的右对齐 chatOutgoing、
 * 收到的左对齐 chatIncoming，时间戳 HH:mm（发送中附 "…"、失败附 "!"、
 * 已编辑附 "edited"）；回复消息在气泡顶部出 "↪ 摘要" 引用行。
 * 滚动到顶 onReachStart 翻更早历史；空/加载/错误三态；底部：圆角输入栏 +
 * 圆形发送按钮（受控输入经 ComposerTextChanged / SendCurrentMessage 驱动）。
 * 键盘避让依赖系统默认 adjustResize，输入栏固定于根 Column 底部。
 *
 * CHAT-004：长按气泡出操作菜单（根 Stack 上的遮罩 + 底部动作面板，可见项由
 * reducer 按 TDLib messageProperties 权限过滤：回复/编辑/删除）；输入栏上方
 * 的回复/编辑预览条（标题 + 摘要 + 取消 X）；点遮罩或 X 撤销，返回箭头在
 * 回复/编辑模式激活时先退出模式再返回（reducer 保证）。
 * 全部色彩/字号/间距用 design_system token，不硬编码。
 *
 * MSG-101：正文富文本。spans 非空时 Text + ForEach(Span) 渲染
 * bold/italic/underline/strikethrough/code/pre/accent/link；spoiler 遮罩块
 * 点击揭开/再点还原（Span.onClick，ContainerSpan 在本 SDK 不支持点击），
 * 状态存本组件 @State（key=messageId:spanIndex）；链接点击经
 * UIAbilityContext.openLink 打开，失败静默 catch 只记错误码。
 *
 * MSG-102：群聊署名。收到的群消息且 senderName 非空 → 气泡内顶部名字行
 * （颜色按 senderColorIndex 取 NAME_PALETTE），气泡左侧小圆头像（彩底 +
 * 首字母，配色与会话列表 AVATAR_PALETTE 一致）；私聊/自己消息布局不变。
 *
 * MSG-104：已读上报与回执。List.onScrollIndex → OnVisibleRangeChanged →
 * ReportMessagesRead（入屏即读，节流在 coordinator）；己方消息时间戳旁
 * 显 ✓/✓✓（isRead）；点击 sendState=failed 的气泡 → TapFailedMessage →
 * ResendMessage 重发。
 *
 * MSG-106：多选转发。长按菜单 Forward → 进入选择态（顶栏变成
 * "N selected" + Cancel/Forward，气泡左侧出勾选圈）；点击气泡切换选中，
 * 取消最后一条自动退出；顶栏 Forward → ConfirmForwardSelection →
 * 装配层弹出 ForwardPickerPage 选目标会话（含 Send as copy 隐藏来源）。
 * 注意：勾选圈是原地变更，selection 必须进 LazyForEach 的 key 才会重渲
 * （见 messageRowKey 与 onUiStateChanged 的 selectionSignature 分支）。
 *
 * MSG-109：头部信息区。标题下方出副标题行（headerSubtitle 非空时，私聊在线
 * 状态 / 群成员数+在线人数）；私聊头部右侧 🔍 旁出 📞 通话占位；私聊/群/频道
 * 标题点击 → OpenChatProfile（纯导航）；头部右侧 ⋮ 按 chatKind 弹菜单
 * （删除聊天 destructive 色），菜单动作统一走 ChatMenuAction 占位入口。
 */

import { LightTheme, Theme, chatTextSizeOf } from '@tgx/core-design-system';
import { Lang } from '@tgx/core-common';
import { isTelegramLinkCandidate } from '@tgx/core-navigation';
import {
  AttachmentEntry,
  ATTACHMENT_FILE,
  ATTACHMENT_GALLERY,
  ATTACHMENT_POLL,
  ATTACHMENT_VIDEO,
  attachmentRestrictionLabel,
  buildAttachmentEntries,
  canRecordVoice,
  canSendAnyMedia,
  CONTENT_GIF,
  CONTENT_STICKER,
  sendVetoLabel
} from '@tgx/core-domain';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { common } from '@kit.AbilityKit';
import { display } from '@kit.ArkUI';
import { BusinessError } from '@kit.BasicServicesKit';
import { fileUri } from '@kit.CoreFileKit';
import { MessageItem } from '../model/MessageItem';
import { ReactionChip } from '../model/ReactionChip';
import { MessageTextSpan } from '../model/MessageTextSpan';
import { MediaAttachment, MediaFullSource, formatFileSize, normalizeWaveform } from '../model/MediaAttachment';
import { MediaViewerItem, mediaViewerItemKey } from '../model/MediaViewerItem';
import {
  ViewerOffset,
  ViewerRect,
  clampViewerOffset,
  clampViewerScale,
  viewerContentRect,
  viewerDoubleTapScale,
  viewerMaxScale,
  viewerNativeScale,
  viewerOffsetForZoom
} from '../model/ViewerTransform';
import {
  ViewerMotionRender,
  animationContainer,
  viewerMotionRender,
  viewerRendersPlayer,
  viewerZoomable
} from '../model/ViewerPlayback';
import { LinkPreviewInfo } from '../model/LinkPreviewInfo';
import {
  calculateMosaicLayout,
  MosaicLayoutResult,
  MosaicLine,
  MosaicItemGeometry
} from '../model/MosaicLayout';
import { avatarLettersForName, nameColorForIndex } from '../model/SenderInfo';
import {
  ChatUiState,
  ComposerMode,
  ComposerReplyMode,
  MessageActionMenuState
} from '../contract/ChatUiState';
import {
  LoadInitialMessages,
  LoadOlderMessages,
  BackToChatList,
  ComposerTextChanged,
  SendCurrentMessage,
  MessageActionRequested,
  ReplyToMessage,
  CopyMessageText,
  CopyMessageLink,
  EditMessage,
  DeleteMessage,
  CancelComposerMode,
  DismissMessageActionMenu,
  ForwardMessagesRequested,
  ToggleMessageSelection,
  ExitMessageSelection,
  ConfirmForwardSelection,
  OnVisibleRangeChanged,
  TapFailedMessage,
  OpenMediaViewer,
  CloseMediaViewer,
  ChangeViewerIndex,
  RequestMediaDownload,
  PickAndSendPhoto,
  PickAndSendFile,
  PickAndSendVideo,
  CancelMediaUpload,
  OpenAttachmentMenu,
  CloseAttachmentMenu,
  ToggleAttachmentMenu,
  OpenEmojiBoard,
  CloseEmojiBoard,
  ToggleEmojiBoard,
  InsertEmoji,
  DeleteLastEmojiChar,
  ClearRecentEmojis,
  CancelMediaDownload,
  ResendFailedMessage,
  OpenChatSearch,
  CloseChatSearch,
  ChatSearchQueryChanged,
  PerformChatSearch,
  JumpToSearchResult,
  ClearJumpToMessage,
  OpenUserProfile,
  OpenAppLink,
  OpenChatProfile,
  ChatMenuAction,
  ConfirmMenuAction,
  DismissMenuConfirmDialog,
  DismissPinnedBar,
  JumpToPinnedMessage,
  PinMessage,
  UnpinMessage,
  JoinChannel,
  OpenMessageComments,
  ToggleMessageReaction,
  OpenStickerSet,
  OpenStickerBoard,
  CloseStickerSetPreview,
  InstallStickerSet,
  UninstallStickerSet,
  SendStickerFromPreview,
  SendSticker,
  ClearRecentStickers,
  SendGif,
  ClearRecentGifs,
  StartVoiceRecord,
  StopAndSendVoiceRecord,
  CancelVoiceRecord,
  PlayVoiceNote,
  PauseVoiceNote,
  OpenPollComposer,
  ClosePollComposer,
  PollQuestionChanged,
  PollOptionTextChanged,
  AddPollComposerOption,
  RemovePollComposerOption,
  TogglePollComposerAnonymous,
  TogglePollComposerMultiple,
  SubmitPollComposer,
  VotePollOption
} from '../contract/ChatIntent';
import { isMessageSelected } from '../model/ForwardSelection';
import { ChatSearchResultItem } from '../model/ChatSearchResultItem';
import { PinnedMessageInfo } from '../model/PinnedMessageInfo';
import { StickerSetItem, isUnicodeEmojiSticker } from '../model/StickerSetPreviewState';
import { GifItem } from '../model/GifItem';
import {
  PollComposerState,
  PollOptionView,
  PollView,
  POLL_MIN_OPTIONS,
  POLL_MAX_OPTIONS,
  POLL_QUESTION_MAX_LENGTH,
  POLL_OPTION_MAX_LENGTH
} from '../model/PollView';
import { EmojiBoard } from './EmojiBoard';
import { StickerSetPreviewSheet } from './StickerSetPreviewSheet';


const DOMAIN: number = 0x0000;
const TAG: string = 'ChatPage';

const BUBBLE_MAX_WIDTH: string = '78%';
const BACK_ARROW_SIZE: number = 44;
const COMPOSER_INPUT_HEIGHT: number = 40;
const SEND_BUTTON_SIZE: number = 40;
/** 群聊署名小圆头像直径（vp）。 */
const SENDER_AVATAR_SIZE: number = 28;
/** MSG-106：多选勾选圈直径（vp）。 */
const SELECTION_MARK_SIZE: number = 22;
/** SEARCH-102：顶栏搜索入口按钮尺寸（vp）。 */
const SEARCH_BUTTON_SIZE: number = 44;
/**
 * SEARCH-102：搜索结果跳转后目标消息的高亮时长（ms）。会话内短会话（几十条）里
 * 跳转前后画面差别很小，没有高亮用户根本看不出落点，故落位后整行着色一段时间。
 * 颜色用 `this.T.colors.chatOutgoing`：浅色主题 #FFD9F1FF、深色主题 #FF1D3D52，
 * 两套主题下都是明显的蓝色调，比中性灰底更容易被注意到。
 */
const JUMP_HIGHLIGHT_MS: number = 4000;

function pad2(value: number): string {
  return value < 10 ? `0${value}` : `${value}`;
}

/** 消息气泡内时间戳：HH:mm。 */
function formatMessageTime(timestampMs: number): string {
  const date: Date = new Date(timestampMs);
  return `${pad2(date.getHours())}:${pad2(date.getMinutes())}`;
}



/**
 * FNV-1a 32 位字符串散列（MSG-104 修复）：给 LazyForEach keyGenerator 用。
 * ArkUI LazyForEach 以 key 判定行身份，key 不变则复用组件、不重渲染——
 * 只按 messageId 做 key 时，已读勾/编辑/发送状态等原地变更不会上屏。
 * key 里必须携带会变化的内容摘要。
 */
function fnv1a32(input: string): string {
  let hash: number = 0x811c9dc5;
  for (let i = 0; i < input.length; i++) {
    hash ^= input.charCodeAt(i) & 0xff;
    hash = Math.imul(hash, 0x01000193);
  }
  return (hash >>> 0).toString(16);
}

function formatDuration(seconds: number): string {
  if (seconds <= 0) {
    return '0:00';
  }
  const mins: number = Math.floor(seconds / 60);
  const secs: number = Math.floor(seconds % 60);
  const secsStr: string = secs < 10 ? `0${secs}` : `${secs}`;
  return `${mins}:${secsStr}`;
}

/**
 * 消息行的 LazyForEach key：messageId + 展示相关内容散列
 * （正文/署名/回复摘要/回复缩略图/发送态/已读/编辑标记/多媒体/多选态）。
 *
 * selected 必须参与签名（MSG-106）：多选勾选圈是"同一 messageId 的原地变更"，
 * key 不含它就永远不重渲——这正是 MSG-104 已读勾踩过的坑。
 */
function messageRowKey(
  item: MessageItem,
  selected: boolean,
  highlighted: boolean = false,
  extraVoiceSig: string = ''
): string {
  let mediaSig: string = '';
  if (item.albumItems.length > 0) {
    const parts: string[] = [];
    for (let k = 0; k < item.albumItems.length; k++) {
      const m: MediaAttachment = item.albumItems[k];
      const path: string = m.localPath !== null ? m.localPath : '';
      const thumb: string = m.thumbnailPath !== null ? m.thumbnailPath : '';
      parts.push(`${m.fileId}|${path}|${thumb}|${m.isDownloaded}|${m.isDownloading}`);
    }
    mediaSig = `album:${parts.join(';')}`;
  } else if (item.media !== null) {
    const m: MediaAttachment = item.media;
    const path: string = m.localPath !== null ? m.localPath : '';
    const thumb: string = m.thumbnailPath !== null ? m.thumbnailPath : '';
    // MEDIA-107：进度按 1% 分桶入签名（原先 10%），否则环上的百分比文字会在
    // 两次重绘之间跳一大截；失败态同样要参与签名，不然错误标画不出来。
    mediaSig = `${m.kind}|${m.fileId}|${path}|${thumb}|${m.isDownloaded}|${m.isDownloading}|${Math.round(m.progress * 100)}|${m.isUploading}|${Math.round(m.uploadProgress * 100)}|${m.fileName}|${m.isDownloadFailed}`;
  }
  const replySig: string =
    `${item.replyToMessageId}|${item.replySenderName}|${item.replySenderColorIndex}|` +
    `${item.replyThumbnailPath !== null ? item.replyThumbnailPath : ''}|${item.replyIsSticker}`;
  let linkPreviewSig: string = '';
  if (item.linkPreview !== null) {
    const lp: LinkPreviewInfo = item.linkPreview;
    const thumb: string = lp.thumbnailPath !== null ? lp.thumbnailPath : '';
    linkPreviewSig = `${lp.url}|${lp.siteName}|${lp.title}|${lp.description}|${thumb}|${lp.showAboveText}|${lp.isLargeMedia}|${lp.showMediaAboveDescription}|${lp.mediaWidth}|${lp.mediaHeight}`;
  }
  let reactionSig: string = '';
  if (item.reactionChips.length > 0) {
    reactionSig = item.reactionChips.map((c: ReactionChip) => `${c.emoji}:${c.count}:${c.isChosen}`).join(',');
  }
  // POLL-101：投票计数/选中态参与签名，否则投完票那一行不重绘（服务端回灌也看不见）。
  let pollSig: string = '';
  if (item.poll !== null) {
    const optParts: string[] = [];
    for (let k: number = 0; k < item.poll.options.length; k++) {
      const o: PollOptionView = item.poll.options[k];
      optParts.push(`${o.voterCount}|${o.votePercentage}|${o.isChosen}`);
    }
    pollSig = `${item.poll.totalVoterCount}|${item.poll.hasVoted}|${item.poll.isClosed}|${optParts.join(';')}`;
  }
  const signature: string =
    `${item.sendState}|${item.isRead}|${item.isEdited}|${item.senderColorIndex}|` +
    `${item.text}|${item.senderName}|${item.senderAvatarPath !== null ? item.senderAvatarPath : ''}|` +
    `${item.replyToSummary}|${mediaSig}|${replySig}|${linkPreviewSig}|${selected}|` +
    `${pollSig}|` +
    `${item.showDateHeader ? item.dateHeaderText : ''}|${item.showUnreadSeparator}|` +
    `${reactionSig}|${item.commentCount}|${item.isChannelPost}|${item.isPinned}|` +
    // SEARCH-102：高亮态参与 key，落位后该行才会局部重绘。
    // VOICE-101：语音播放态参与 key，进度推进时局部重绘波形条。
    `${highlighted}|${extraVoiceSig}`;
  return `${item.messageId}:${fnv1a32(signature)}`;
}

/**
 * LazyForEach 数据源：按「行签名」做差分，只通知真正变化的行。
 *
 * 原实现无条件 `onDataReloaded()`（全量重建）。而上传进度每 200ms
 * （coordinator 的 scheduleThrottledSync）就推一次新 items，于是整张列表的
 * ListItem 全部销毁重建、图片与视频重新解码——肉眼就是「上传的时候一闪一闪」。
 * 改成逐行 onDataChange 后，只有签名真正变化的那一行会重绘。
 */
export class MessageListDataSource implements IDataSource {
  private items: MessageItem[] = [];
  private keys: string[] = [];
  private listeners: DataChangeListener[] = [];

  totalCount(): number {
    return this.items.length;
  }

  getData(index: number): MessageItem {
    return this.items[index];
  }

  registerDataChangeListener(listener: DataChangeListener): void {
    if (this.listeners.indexOf(listener) < 0) {
      this.listeners.push(listener);
    }
  }

  unregisterDataChangeListener(listener: DataChangeListener): void {
    const idx: number = this.listeners.indexOf(listener);
    if (idx >= 0) {
      this.listeners.splice(idx, 1);
    }
  }

  /**
   * 同步数据源。keys 必须与 items 同长同序（来自 ChatPage.rowKeyAt）。
   * - 长度不变：逐行比签名，只对变化的行发 onDataChange（行节点按 key 原地重绘）；
   * - 长度变化：列表结构变了（新消息 / 翻页前插 / 删除），仍走 onDataReloaded。
   */
  setItems(items: readonly MessageItem[], keys: readonly string[]): void {
    const next: MessageItem[] = items.slice(0);
    const nextKeys: string[] = keys.slice(0);
    if (this.items.length !== next.length || this.keys.length !== nextKeys.length) {
      this.items = next;
      this.keys = nextKeys;
      this.listeners.forEach((listener: DataChangeListener) => {
        listener.onDataReloaded();
      });
      return;
    }
    const changed: number[] = [];
    for (let i = 0; i < next.length; i++) {
      if (this.keys[i] !== nextKeys[i]) {
        changed.push(i);
      }
    }
    this.items = next;
    this.keys = nextKeys;
    if (changed.length === 0) {
      return;
    }
    this.listeners.forEach((listener: DataChangeListener) => {
      for (let k = 0; k < changed.length; k++) {
        listener.onDataChange(changed[k]);
      }
    });
  }
}

function toSandboxUri(path: string | null): string {
  if (path === null || path.length === 0) {
    return '';
  }
  if (path.startsWith('file://')) {
    return path;
  }
  const normalized: string = path.startsWith('/') ? path : '/' + path;
  try {
    return fileUri.getUriFromPath(normalized);
  } catch (_e) {
    return 'file://org.telegram.x.harmony' + normalized;
  }
}

@Component
export struct ChatPage {
  /**
   * FEAT-UI-001 全局深色主题：entry 装配层把 ThemeManager 的当前主题写入
   * AppStorage('activeTheme')，本页以 @StorageProp 订阅。该值变化会触发本页
   * 重渲染。此前写死 `const T = LightTheme`，主题切换后引用不变，深色不生效。
   * 短名 T 直接落在装饰器成员上——ArkUI 的 build 转换不接管 struct 内自定义
   * getter，写成 getter 会在渲染闭包里取到 undefined 并抛 TypeError。
   */
  @StorageProp('activeTheme') T: Theme = LightTheme;
  @Prop @Watch('onUiStateChanged') uiState: ChatUiState = ChatUiState.initial();

  onDispatch: (intent: Object) => void = () => {};

  private dataSource: MessageListDataSource = new MessageListDataSource();
  private scroller: Scroller = new Scroller();
  private shownMessages: readonly MessageItem[] = [];
  private shownCount: number = 0;
  private lastTailMessageId: number = 0;
  /** SEARCH-102：搜索面板独立滚动器（避免与主列表 scroller 共享滚动位置）。 */
  private searchScroller: Scroller = new Scroller();
  /** SEARCH-102：搜索输入防抖定时器句柄（undefined=无在途定时器）。 */
  private searchDebounceTimer: number | undefined = undefined;
  /** 已揭开的 spoiler span 集合，key = `${messageId}:${spanIndex}`（MSG-101）。 */
  @State private revealedSpoilers: string[] = [];
  /** MEDIA-103：全屏媒体查看器缩放比例与工具栏显隐状态。 */
  @State private viewerScale: number = 1.0;
  @State private pinchStartScale: number = 1.0;
  @State private viewerBarsVisible: boolean = true;
  @State private activeVideoNoteId: number | null = null;
  private swiperController: SwiperController = new SwiperController();
  /**
   * MEDIA-VIEWER-101：放大后的位移（vp）与视口尺寸（vp）。
   * 视口由 `onAreaChange` 测得 —— 贴合矩形和位移夹紧都以它为准；
   * 缩放上限不落 @State，按「当前真正在画的那一档的真实像素」随算随用，
   * 这样大图档落盘换源之后上限自动变大，不需要任何同步逻辑。
   */
  @State private viewerOffsetX: number = 0;
  @State private viewerOffsetY: number = 0;
  @State private viewerViewportW: number = 0;
  @State private viewerViewportH: number = 0;
  private panStartOffsetX: number = 0;
  private panStartOffsetY: number = 0;
  private pinchStartOffsetX: number = 0;
  private pinchStartOffsetY: number = 0;
  private pinchFocalX: number = 0;
  private pinchFocalY: number = 0;
  /** 标记用户是否已手动滑动过列表；为 false 时新拉取历史保持目标定位。 */
  private hasUserScrolled: boolean = false;
  /**
   * SEARCH-102：跳转锚定锁。搜索结果跳转落位后置位，抑制"首屏未读/尾部新消息"
   * 的自动定位把视图拉回；用户一旦手动滑动列表即释放（之后恢复既有的跟随行为）。
   */
  private jumpAnchorLock: boolean = false;
  /** SEARCH-102：跳转落位后高亮的消息 id（0 = 无）。让用户一眼看到"跳到哪了"。 */
  @State private highlightedMessageId: number = 0;
  private highlightTimer: number | undefined = undefined;
  /** MSG-106：上次渲染的选择集签名，用于在多选态变化时触发列表重载。 */
  private shownSelectionSignature: string = '';
  /**
   * POLL-101：@Builder 按值传参不会随外部状态刷新（面板会停在初始空草稿），
   * 故把 reducer 的编辑态镜像成 @State，面板内部一律读 this.pollDraft。
   */
  @State private showPollComposer: boolean = false;
  @State private pollDraft: PollComposerState = PollComposerState.draft();
  /** VOICE-101：上次渲染的正在播放语音消息 ID 与进度采样。 */
  private shownPlayingVoiceMessageId: number | null = null;
  private shownVoiceProgress: number = 0;
  /** 屏幕宽度（vp），aboutToAppear 时取一次。气泡内容区宽度上限由它算出，见 contentMaxVp()。 */
  private screenWidthVp: number = 360;
  /**
   * 1vp 对应的物理像素数（`display.densityPixels`），与屏宽同一次取样。
   * 查看器的 1:1 像素档位必须按真实像素算，所以不能省；
   * 全局 `vp2px` 已标记 deprecated，这里直接用底层密度。
   */
  private densityPxPerVp: number = 3;

  /**
   * 气泡「内容区」的最大宽度（vp）。
   *
   * 为什么必须有这个数：气泡容器（ChatRow 里那个 Column）带
   * `padding({ left/right: spacing.md })`，而宽度只由 `constraintSize({ maxWidth: '78%' })`
   * 限制——是百分比、不是确定值。于是当内容比内容区更宽时，ArkUI 把子节点的可用宽度按
   * 「边框宽 − 右内边距」计算，再按 Column 的 alignItems(End) 右对齐摆放：子节点整体向左
   * 溢出 spacing.md，被容器的 `.clip(true)` 一刀切掉。
   *
   * 实测（MEDIA-105 联调：360vp 屏 / 密度 3.4889 的模拟器，uinode 树）：
   *   气泡容器 892px(255.7vp = 78% × 328)，内容区应为 808px(231.7vp)
   *   文档气泡内容行实际 850px(243.6vp)，左边缘压在容器左边缘 308px（应为 350px）
   *   → 左溢出 42px(12vp = spacing.md)；44vp 圆钮同时被挤成 108×154px 的椭圆
   *   视频卡片硬编码 240vp > 231.7vp → 同样左溢出，卡片中心比气泡中心偏左约 4vp
   *
   * 所以凡是用「具体数值宽度」的子组件（媒体卡片、文档/语音/音频行的文字列）都必须用
   * 这里的上限收敛，不能再写死 240/260。
   */
  private contentMaxVp(): number {
    const rowContentVp: number = this.screenWidthVp - 2 * this.T.spacing.screenInset;
    const bubbleFrac: number = parseFloat(BUBBLE_MAX_WIDTH) / 100;
    return Math.max(120, Math.floor(rowContentVp * bubbleFrac) - 2 * this.T.spacing.md);
  }

  /**
   * 气泡内「定宽图标 + layoutWeight 文字列」横排时，文字列的宽度上限。
   *
   * 文字列带 layoutWeight，在过度约束的 Row 里会先占满自己的理想宽度（长文件名可达 200vp），
   * 反过来把定宽图标挤到剩余空间——44vp 圆钮实测只有 31vp。显式给出上限后，
   * Row 的「图标 + 间距 + 文字」恰好等于可用宽度，图标不再被挤。
   */
  private rowTextMaxVp(iconBox: number, iconGap: number): number {
    return Math.max(80, this.contentMaxVp() - 2 * this.T.spacing.xs - iconBox - iconGap);
  }

  /** 媒体卡片（图片/视频/动图）的边长上限：既要 ≤ 设计上限 240vp，也要 ≤ 气泡内容区宽度。 */
  private mediaCardBaseVp(): number {
    return Math.min(240, this.contentMaxVp());
  }

  /** MSG-106：当前选择集签名（含模式开关；未进入多选态恒为空串）。 */
  private selectionSignature(): string {
    if (!this.uiState.selectionMode) {
      return '';
    }
    return `${this.uiState.selectedMessageIds.join(',')}`;
  }

  /** MSG-106：该消息是否被勾选（未进入多选态恒 false）。 */
  private isSelected(messageId: number): boolean {
    if (!this.uiState.selectionMode) {
      return false;
    }
    return isMessageSelected(this.uiState.selectedMessageIds, messageId);
  }

  /**
   * 单行渲染签名（== LazyForEach key）。
   *
   * 这里是唯一真源：LazyForEach 的 keyGenerator 与数据源差分的比较都走它。
   * 两处若各写一份，差分结果会和 LazyForEach 的 key 判断不一致，行就会漏刷或空刷。
   */
  private rowKeyAt(item: MessageItem): string {
    return messageRowKey(
      item,
      this.isSelected(item.messageId),
      this.highlightedMessageId === item.messageId,
      this.uiState.playingVoiceMessageId === item.messageId ?
        `play:${Math.floor(this.uiState.voicePlaybackProgress * 28)}:${this.uiState.voicePlaybackTimeSec}` : ''
    );
  }

  private buildRowKeys(messages: readonly MessageItem[]): string[] {
    const keys: string[] = [];
    for (let i = 0; i < messages.length; i++) {
      keys.push(this.rowKeyAt(messages[i]));
    }
    return keys;
  }

  /** 对齐 Telegram X（canGoUnread）：未读数 > 0 且存在已读水位时才定位未读。 */
  private canGoUnread(): boolean {
    return this.uiState.unreadCount > 0 && this.uiState.lastReadInboxMessageId > 0;
  }

  private computeScrollTargetIndex(messages: readonly MessageItem[]): number {
    if (messages.length === 0) {
      return 0;
    }
    // 未读会话：优先定位到带有未读分隔线的消息，次选首条未读消息
    if (this.canGoUnread()) {
      for (let i = 0; i < messages.length; i++) {
        if (messages[i].showUnreadSeparator) {
          return i;
        }
      }
      const lastReadInbox: number = this.uiState.lastReadInboxMessageId;
      for (let i = 0; i < messages.length; i++) {
        const item: MessageItem = messages[i];
        if (!item.isOutgoing && item.messageId > lastReadInbox) {
          return i;
        }
      }
    }
    // 已读会话：一律定位到末尾最新消息
    return messages.length - 1;
  }

  aboutToAppear(): void {
    this.hasUserScrolled = false;
    // 气泡内容区宽度上限依赖屏宽，取一次即可（避免每帧查 display）。
    // 用 densityPixels 自己换算：全局 px2vp 已标记 deprecated。
    try {
      const info: display.Display = display.getDefaultDisplaySync();
      this.densityPxPerVp = info.densityPixels > 0 ? info.densityPixels : 3;
      this.screenWidthVp = info.densityPixels > 0 ? Math.round(info.width / info.densityPixels) : 360;
    } catch (_e) {
      this.screenWidthVp = 360;
    }
    this.dataSource.setItems(this.uiState.messages, this.buildRowKeys(this.uiState.messages));
    this.shownMessages = this.uiState.messages;
    this.shownSelectionSignature = this.selectionSignature();
    this.shownCount = this.uiState.messages.length;
    if (this.shownCount > 0) {
      this.lastTailMessageId = this.uiState.messages[this.shownCount - 1].messageId;
      const targetIdx: number = this.computeScrollTargetIndex(this.uiState.messages);
      const align: ScrollAlign = (targetIdx === this.shownCount - 1) ? ScrollAlign.END : ScrollAlign.START;
      // 首屏锚点同样要让位给搜索结果跳转（从搜索进会话时二者几乎同时发生）。
      this.autoScrollUnlessJumped(targetIdx, false, align, 50);
    }
    // SEARCH-102：目标命中首屏缓存时，跳转早在首帧之前就解析完了（@Watch 不会触发），
    // 这里补一次；目标还没进数组时留给后续状态变更处理。
    const pendingJump: number = this.uiState.jumpToMessageId;
    if (pendingJump > 0 && this.indexOfMessageId(pendingJump) >= 0) {
      hilog.info(DOMAIN, TAG, 'chat_jump_from_first_frame messageId=%{public}s', `${pendingJump}`);
      this.armJumpScroll(pendingJump);
    }
  }

  onUiStateChanged(): void {
    // POLL-101：@Builder 按值传参不随外部状态刷新，编辑态镜像成 @State 后由面板直接读取。
    const composer: PollComposerState | null = this.uiState.pollComposer;
    this.showPollComposer = composer !== null;
    if (composer !== null) {
      this.pollDraft = composer;
    }
    // SEARCH-102：待跳转定位的消息 id 回灌后滚到目标（围绕历史已由 coordinator
    // 通过 loadHistoryAround 拉好）。跳转必须压过"首屏未读/尾部新消息"的自动定位——
    // 后者是 40-50ms 的延迟滚动，若走同一条路径会把跳转结果覆盖掉（表现为
    // "点了搜索结果却停在最新消息处"）。命中目标时在此独占处理并 return。
    const jumpTarget: number = this.uiState.jumpToMessageId;
    let jumpIndex: number = -1;
    if (jumpTarget > 0) {
      for (let i = 0; i < this.uiState.messages.length; i++) {
        if (this.uiState.messages[i].messageId === jumpTarget) {
          jumpIndex = i;
          break;
        }
      }
    }
    if (this.uiState.activeViewerIndex < 0) {
      this.resetViewerTransform();
      this.viewerBarsVisible = true;
    }
    const messages: readonly MessageItem[] = this.uiState.messages;
    const selectionSignature: string = this.selectionSignature();
    const selectionChanged: boolean = selectionSignature !== this.shownSelectionSignature;
    const messagesChanged: boolean = messages !== this.shownMessages;
    if (jumpIndex >= 0) {
      // 数据源先同步到最新，再延迟一帧居中定位（等列表完成一次布局）。
      if (messagesChanged) {
        this.dataSource.setItems(messages, this.buildRowKeys(messages));
        this.shownMessages = messages;
        this.shownCount = messages.length;
        this.lastTailMessageId = messages.length > 0 ? messages[messages.length - 1].messageId : 0;
      } else if (selectionChanged) {
        this.dataSource.setItems(messages, this.buildRowKeys(messages));
      }
      if (selectionChanged) {
        this.shownSelectionSignature = selectionSignature;
      }
      // 跳转是用户显式位移：置位后不再让"保持未读/末尾定位"把视图拉回。
      this.armJumpScroll(jumpTarget);
      return;
    }
    // composerText 等变化不触碰列表：仅 messages 引用变化才刷新数据源，
    // 避免输入栏每次击键都触发列表刷新。
    // MSG-106 例外：多选态变化也是"原地变更"，但 messages 数组引用不变。
    // VOICE-101 例外：语音播放态与进度变化同样是"原地变更"。
    // 这两类变化都写进了行签名（见 rowKeyAt），交给 setItems 的行级差分处理，
    // 只重绘勾选圈/波形所在的那几行，不再全量重载。
    const playingVoiceChanged: boolean = (this.uiState.playingVoiceMessageId !== this.shownPlayingVoiceMessageId) ||
      (this.uiState.playingVoiceMessageId !== null && Math.floor(this.uiState.voicePlaybackProgress * 28) !== Math.floor(this.shownVoiceProgress * 28));

    if (!messagesChanged && !selectionChanged && !playingVoiceChanged) {
      return;
    }
    if (selectionChanged) {
      this.shownSelectionSignature = selectionSignature;
    }
    if (playingVoiceChanged) {
      this.shownPlayingVoiceMessageId = this.uiState.playingVoiceMessageId;
      this.shownVoiceProgress = this.uiState.voicePlaybackProgress;
    }
    if (!messagesChanged) {
      // 只变了选择态或语音播放态：让行签名差分把这几行重绘，滚动位置不动。
      this.dataSource.setItems(messages, this.buildRowKeys(messages));
      return;
    }
    const count: number = messages.length;
    const tailId: number = count > 0 ? messages[count - 1].messageId : 0;
    const firstContent: boolean = this.shownCount === 0 && count > 0;
    const grewAtTail: boolean = count > 0 && tailId !== this.lastTailMessageId;
    this.dataSource.setItems(messages, this.buildRowKeys(messages));
    this.shownMessages = messages;
    this.shownCount = count;
    this.lastTailMessageId = tailId;
    // 首屏出内容 → 定位到首条未读或最新；尾部来了新消息 → 平滑滚到底；
    // 顶部翻页/历史回填时，若用户尚未主动滑动，保持目标定位（未读定位未读，已读定位最新末尾）。
    // SEARCH-102：跳转锚定期间（jumpAnchorLock）一律不执行这些自动定位——刚进会话时
    // 首屏 preload 会让"尾部变化"，若照常滚到底就会把搜索结果跳转覆盖掉。
    if (firstContent) {
      const targetIdx: number = this.computeScrollTargetIndex(messages);
      const align: ScrollAlign = (targetIdx === count - 1) ? ScrollAlign.END : ScrollAlign.START;
      this.autoScrollUnlessJumped(targetIdx, false, align, 50);
    } else if (grewAtTail) {
      this.autoScrollUnlessJumped(count - 1, true, ScrollAlign.END, 40);
    } else if (!this.hasUserScrolled && count > 0) {
      const targetIdx: number = this.computeScrollTargetIndex(messages);
      const align: ScrollAlign = (targetIdx === count - 1) ? ScrollAlign.END : ScrollAlign.START;
      this.autoScrollUnlessJumped(targetIdx, false, align, 50);
    }
  }

  /**
   * SEARCH-102：执行跳转落位（置锚定锁 → 延迟居中滚动 → 高亮 → 清标记）。
   *
   * 两处调用，缺一不可：
   * - `onUiStateChanged`：常规路径（目标需要拉历史时，Ready 晚于首帧到达）；
   * - `aboutToAppear`：**目标命中首屏缓存时的快路径**——打开会话 → 首屏回包 → Ready
   *   可能在 3ms 内全部跑完，比 ChatPage 首帧创建还早，此时 @Watch 只在"创建后的变化"
   *   上触发，这个 transition 会被完全跳过（表现为"点了搜索结果完全没反应"）。
   *
   * 下标在滚动时刻重新解析：这段延迟里投影可能前插更早历史导致下标整体位移。
   * 落位成功才清标记；清不掉（目标还没进数组）就留待下一次状态变更再跳。
   */
  private armJumpScroll(targetMessageId: number): void {
    this.hasUserScrolled = true;
    this.jumpAnchorLock = true;
    setTimeout(() => {
      if (this.uiState.jumpToMessageId !== targetMessageId) {
        // 已由更早的回调完成落位：过期回调不得再把用户拉回。
        return;
      }
      const currentIndex: number = this.indexOfMessageId(targetMessageId);
      if (currentIndex < 0) {
        return;
      }
      hilog.info(DOMAIN, TAG, 'chat_jump_scroll messageId=%{public}s index=%{public}s total=%{public}s',
        `${targetMessageId}`, `${currentIndex}`, `${this.uiState.messages.length}`);
      this.scroller.scrollToIndex(currentIndex, false, ScrollAlign.CENTER);
      this.highlightJumpTarget(targetMessageId);
      this.onDispatch(new ClearJumpToMessage());
    }, 80);
  }

  /**
   * SEARCH-102：落位后高亮目标消息一段时间（并记日志便于取证）。
   * 用户手动滑动或再次跳转会立即结束上一次高亮，避免多处着色。
   */
  private highlightJumpTarget(messageId: number): void {
    if (this.highlightTimer !== undefined) {
      clearTimeout(this.highlightTimer);
      this.highlightTimer = undefined;
    }
    this.highlightedMessageId = messageId;
    hilog.info(DOMAIN, TAG, 'chat_jump_highlight messageId=%{public}s', `${messageId}`);
    this.highlightTimer = setTimeout(() => {
      this.highlightTimer = undefined;
      this.highlightedMessageId = 0;
    }, JUMP_HIGHLIGHT_MS);
  }

  /** SEARCH-102：立即结束跳转高亮（用户接管视图时调用）。 */
  private clearJumpHighlight(): void {
    if (this.highlightTimer !== undefined) {
      clearTimeout(this.highlightTimer);
      this.highlightTimer = undefined;
    }
    this.highlightedMessageId = 0;
  }

  /** PROFILE-101：群聊头像点按 → 用户资料页（仅用户发送者可进；频道身份/未知忽略）。 */
  private onSenderAvatarClick(item: MessageItem): void {
    if (item.senderUserId > 0) {
      this.onDispatch(new OpenUserProfile(item.senderUserId));
    }
  }

  private t(key: string, ...args: (string | number)[]): string {
    return Lang.getInstance().getString(key, ...args);
  }

  /**
   * SEARCH-102：按消息 id 在**当前**上屏数组里求下标；未命中返回 -1。
   * 跳转必须在滚动时刻现算（而不是用状态变更时算好的值），否则这段延迟里
   * 投影前插更早历史会让下标整体位移，滚到错误的消息。
   */
  private indexOfMessageId(messageId: number): number {
    const messages: readonly MessageItem[] = this.uiState.messages;
    for (let i = 0; i < messages.length; i++) {
      if (messages[i].messageId === messageId) {
        return i;
      }
    }
    return -1;
  }

  /**
   * SEARCH-102：延迟执行的"自动定位"（未读/末尾）。已在跳转锚定期间则跳过——
   * 回调是延迟 40–50ms 才跑的，必须在触发时刻再判断一次，否则跳转（无论先后）
   * 都可能被这一枪打回最新消息处。
   */
  private autoScrollUnlessJumped(index: number, smooth: boolean, align: ScrollAlign, delayMs: number): void {
    setTimeout(() => {
      // 跳转锚定中，或还有待落位的跳转目标（Ready 还没到）→ 让位给跳转。
      if (this.jumpAnchorLock || this.uiState.jumpToMessageId > 0) {
        return;
      }
      this.scroller.scrollToIndex(index, smooth, align);
    }, delayMs);
  }

  build() {
    Stack() {
      Column() {
        this.Header()

        if (this.uiState.showPinnedBar && this.uiState.pinnedMessage !== null) {
          this.PinnedMessageBar(this.uiState.pinnedMessage)
        }

        if (this.uiState.errorMessage !== null && this.uiState.messages.length === 0) {
          this.ErrorView(this.uiState.errorMessage)
        } else if (this.uiState.isLoading && this.uiState.messages.length === 0) {
          this.LoadingView()
        } else if (this.uiState.messages.length === 0) {
          this.EmptyView()
        } else {
          if (this.uiState.isLoading) {
            Row() {
              LoadingProgress()
                .width(20)
                .height(20)
                .color(this.T.colors.accent)
            }
            .width('100%')
            .justifyContent(FlexAlign.Center)
            .padding({ top: this.T.spacing.xs })
          }

          List({ initialIndex: this.computeScrollTargetIndex(this.uiState.messages), scroller: this.scroller }) {
            LazyForEach(this.dataSource, (item: MessageItem) => {
              ListItem() {
                this.MessageRow(item)
              }
            }, (item: MessageItem) => this.rowKeyAt(item))
          }
          .width('100%')
          .layoutWeight(1)
          .cachedCount(5)
          .scrollBar(BarState.Off)
          .onTouch((event: TouchEvent) => {
            if (event.type === TouchType.Down || event.type === TouchType.Move) {
              this.hasUserScrolled = true;
              // SEARCH-102：用户接管视图，解除跳转锚定与高亮，恢复既有的自动跟随。
              this.jumpAnchorLock = false;
              this.clearJumpHighlight();
              if (this.uiState.showEmojiBoard) {
                this.onDispatch(new CloseEmojiBoard());
              }
              if (this.uiState.showAttachmentMenu) {
                this.onDispatch(new CloseAttachmentMenu());
              }
            }
          })
          .onScrollIndex((start: number, end: number) => {
            // MSG-104：入屏即读，最后可见下标变化即上报（节流在 coordinator）。
            this.onDispatch(new OnVisibleRangeChanged(end));
          })
          .onReachStart(() => {
            this.onDispatch(new LoadOlderMessages());
          })
        }

        // 发送失败等错误：已有消息时不挡列表，仅在输入栏上方出细条提示。
        if (this.uiState.errorMessage !== null && this.uiState.messages.length > 0) {
          Text(this.uiState.errorMessage)
            .fontSize(this.T.typography.footnote.fontSize)
            .fontColor(this.T.colors.destructive)
            .maxLines(1)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
            .width('100%')
            .padding({
              left: this.T.spacing.screenInset,
              right: this.T.spacing.screenInset,
              top: this.T.spacing.xs
            })
        }

        // 回复/编辑预览条（CHAT-004）：标题 + 摘要 + 取消 X。
        // MSG-106：多选态下不显示输入相关 UI（对齐 Telegram X 的选择态）。
        // CHANNEL-101 / CHAN-SEND：频道覆盖态（未加入=加入条、只读=静音条）下不出输入栏模式条。
        if (this.uiState.composerMode !== null && !this.uiState.selectionMode && !this.isChannelOverlayBar()) {
          this.ComposerModeBar(this.uiState.composerMode)
        }

        if (!this.uiState.selectionMode) {
          if (this.uiState.chatKind === 'channel' && !this.uiState.isChannelMember) {
            this.JoinChannelBar()
          } else if (this.isChannelReadOnly()) {
            // CHAN-SEND：只有 TDLib 明确给出 can_send_basic_messages=false 的频道成员才收成静音条；
            // 有发言权（管理员/可发帖频道）走正常输入栏，静音开关在 ⋮ 菜单与频道资料页。
            this.ChannelMuteBar()
          } else if (this.uiState.isRecordingVoice) {
            this.VoiceRecordingBar()
          } else {
            this.ComposerBar()
          }
        }

        // EMOJI-101 & STICKER-101：表情与贴纸面板（非多选态且非频道覆盖态）
        if (this.uiState.showEmojiBoard && !this.uiState.selectionMode && !this.isChannelOverlayBar()) {
          EmojiBoard({
            recentEmojis: this.uiState.recentEmojis.slice(),
            recentStickers: this.uiState.recentStickers.slice(),
            recentGifs: this.uiState.recentGifs.slice(),
            // STICKER-BOARD-101：真实贴纸包（getInstalledStickerSets 装盘结果）
            stickerPacks: this.uiState.stickerBoard.packs.slice(),
            stickerBoardLoading: this.uiState.stickerBoard.isLoading,
            stickerBoardError: this.uiState.stickerBoard.errorMessage,
            // STICKER-BOARD-102：热门区与在途那一包
            stickerTrending: this.uiState.stickerBoard.trending.slice(),
            stickerInstallingSetId: this.uiState.stickerBoard.installingSetId,
            onInstallStickerSet: (setId: string) => {
              this.onDispatch(new InstallStickerSet(setId));
            },
            onUninstallStickerSet: (setId: string) => {
              this.onDispatch(new UninstallStickerSet(setId));
            },
            onStickerBoardVisible: () => {
              this.onDispatch(new OpenStickerBoard());
            },
            onSelectEmoji: (emoji: string) => {
              this.onDispatch(new InsertEmoji(emoji));
            },
            onDeleteChar: () => {
              this.onDispatch(new DeleteLastEmojiChar());
            },
            onClearRecent: () => {
              this.onDispatch(new ClearRecentEmojis());
            },
            onSelectSticker: (emoji: string) => {
              // 兼容老调用
            },
            onSendSticker: (item: StickerSetItem) => {
              this.sendContentWithVeto(CONTENT_STICKER, item.fileId, (): void => {
                this.onDispatch(new SendSticker(item));
              });
            },
            onClearRecentStickers: () => {
              this.onDispatch(new ClearRecentStickers());
            },
            onSendGif: (item: GifItem) => {
              this.sendContentWithVeto(CONTENT_GIF, item.fileId, (): void => {
                this.onDispatch(new SendGif(item));
              });
            },
            onClearRecentGifs: () => {
              this.onDispatch(new ClearRecentGifs());
            },
            onOpenStickerSet: (setId: string) => {
              this.onDispatch(new OpenStickerSet(setId));
            }
          })
        }
      }
      .width('100%')
      .height('100%')

      // 长按气泡的操作菜单（CHAT-004）：全屏遮罩 + 底部动作面板。
      if (this.uiState.actionMenu !== null) {
        this.ActionMenuSheet(this.uiState.actionMenu)
      }

      // COMPOSER-102：附件选择面板（半透明遮罩 + 底部抽屉）。
      if (this.uiState.showAttachmentMenu) {
        this.AttachmentMenuSheet()
      }

      // POLL-101：发起投票面板（半透明遮罩 + 底部抽屉）。
      if (this.showPollComposer) {
        this.PollComposerSheet()
      }

      // 全屏媒体查看器（MEDIA-103 / FEAT-MEDIA-006）
      if (this.uiState.activeViewerIndex >= 0) {
        this.MediaViewerOverlay()
      }

      // SEARCH-102：聊天内搜索面板（顶栏 🔍 展开的覆盖层：搜索栏 + 结果列表）。
      if (this.uiState.showSearch) {
        this.SearchPanel()
      }

      // STICKER-PREVIEW-101：贴纸包详情与添加弹窗（全屏遮罩 + 底部抽屉）。
      if (this.uiState.stickerSetPreview !== null) {
        StickerSetPreviewSheet({
          preview: this.uiState.stickerSetPreview,
          onClose: () => {
            this.onDispatch(new CloseStickerSetPreview());
          },
          onInstall: (setId: string) => {
            this.onDispatch(new InstallStickerSet(setId));
          },
          onUninstall: (setId: string) => {
            this.onDispatch(new UninstallStickerSet(setId));
          },
          onSelectSticker: (stickerItem: StickerSetItem) => {
            this.sendContentWithVeto(CONTENT_STICKER, stickerItem.fileId, (): void => {
              this.onDispatch(new SendStickerFromPreview(stickerItem));
            });
          },
          onRetry: (setId: string) => {
            this.onDispatch(new OpenStickerSet(setId));
          }
        })
      }

      // MENU-101：⋮ 菜单破坏性操作确认弹窗（遮罩 + 居中卡片）。
      if (this.uiState.showMenuConfirmDialog) {
        this.MenuConfirmDialogOverlay()
      }
    }
    .width('100%')
    .height('100%')
    .backgroundColor(this.T.colors.background)
  }

  @Builder
  Header() {
    Row() {
      if (this.uiState.selectionMode) {
        // MSG-106 多选态顶栏：ic_close + "N selected" + ic_forward
        Row() {
          Image($r('app.media.ic_close'))
            .width(24)
            .height(24)
            .fillColor(this.T.colors.textPrimary)
        }
        .width(BACK_ARROW_SIZE)
        .height(BACK_ARROW_SIZE)
        .justifyContent(FlexAlign.Center)
        .alignItems(VerticalAlign.Center)
        .onClick(() => {
          this.onDispatch(new ExitMessageSelection());
        })

        Text(`${this.uiState.selectedMessageIds.length} selected`)
          .fontSize(this.T.typography.title.fontSize)
          .fontWeight(this.T.typography.title.fontWeight)
          .fontColor(this.T.colors.textPrimary)
          .textAlign(TextAlign.Center)
          .layoutWeight(1)

        Row() {
          Image($r('app.media.ic_forward'))
            .width(24)
            .height(24)
            .fillColor(this.uiState.selectedMessageIds.length > 0 ? this.T.colors.accent : this.T.colors.disabled)
        }
        .width(BACK_ARROW_SIZE)
        .height(BACK_ARROW_SIZE)
        .justifyContent(FlexAlign.Center)
        .alignItems(VerticalAlign.Center)
        .onClick(() => {
          if (this.uiState.selectedMessageIds.length > 0) {
            this.onDispatch(new ConfirmForwardSelection());
          }
        })
      } else {
        Row() {
          Image($r('app.media.ic_back'))
            .width(24)
            .height(24)
            .fillColor(this.T.colors.accent)
        }
        .width(BACK_ARROW_SIZE)
        .height(BACK_ARROW_SIZE)
        .justifyContent(FlexAlign.Center)
        .alignItems(VerticalAlign.Center)
        .onClick(() => {
          this.onDispatch(new BackToChatList());
        })

        // MSG-109：标题 + 副标题（副标题非空时显示，subheadline 字号 textSecondary）。
        Column() {
          Text(this.uiState.chatTitle)
            .fontSize(this.T.typography.title.fontSize)
            .fontWeight(this.T.typography.title.fontWeight)
            .fontColor(this.T.colors.textPrimary)
            .maxLines(1)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
            .onClick(() => {
              // MSG-109：私聊/群/频道标题点击 → 打开会话资料页（纯导航意图）。
              this.onDispatch(new OpenChatProfile(this.uiState.chatId));
            })

          if (this.uiState.headerSubtitle.length > 0) {
            Text(this.uiState.headerSubtitle)
              .fontSize(this.T.typography.subheadline.fontSize)
              .fontColor(this.T.colors.textSecondary)
              .maxLines(1)
              .textOverflow({ overflow: TextOverflow.Ellipsis })
          }
        }
        .layoutWeight(1)
        .alignItems(HorizontalAlign.Start)

        // MSG-109：私聊头部语音通话占位入口（📞，语义后续泳道实现）。
        if (this.uiState.chatKind === 'private') {
          Row() {
            Image($r('app.media.ic_call'))
              .width(22)
              .height(22)
              .fillColor(this.T.colors.accent)
          }
          .width(SEARCH_BUTTON_SIZE)
          .height(SEARCH_BUTTON_SIZE)
          .justifyContent(FlexAlign.Center)
          .alignItems(VerticalAlign.Center)
          .onClick(() => {
            hilog.info(DOMAIN, TAG, 'chat_call_placeholder');
          })
        }

        // SEARCH-102：聊天内搜索入口（🔍 图标 → 展开搜索面板）。
        Row() {
          Image($r('app.media.ic_search'))
            .width(22)
            .height(22)
            .fillColor(this.T.colors.accent)
        }
        .width(SEARCH_BUTTON_SIZE)
        .height(SEARCH_BUTTON_SIZE)
        .justifyContent(FlexAlign.Center)
        .alignItems(VerticalAlign.Center)
        .onClick(() => {
          this.onDispatch(new OpenChatSearch());
        })

        // MSG-109：头部 ⋮ 溢出菜单（按 chatKind 出项，删除聊天 destructive 色）。
        Row() {
          Image($r('app.media.ic_more_vert'))
            .width(22)
            .height(22)
            .fillColor(this.T.colors.accent)
        }
        .width(SEARCH_BUTTON_SIZE)
        .height(SEARCH_BUTTON_SIZE)
        .justifyContent(FlexAlign.Center)
        .alignItems(VerticalAlign.Center)
        .bindMenu(this.HeaderOverflowMenu)
      }
    }
    .width('100%')
    .alignItems(VerticalAlign.Center)
    .padding({
      left: this.T.spacing.sm,
      right: this.T.spacing.screenInset,
      top: this.T.spacing.sm,
      bottom: this.T.spacing.sm
    })
    .borderWidth({ bottom: 1 })
    .borderColor(this.T.colors.divider)
  }

  /**
   * MSG-109：头部 ⋮ 溢出菜单（CustomBuilder 形式：MenuElement 数组不支持逐项着色，
   * 删除聊天需 destructive 色，故用 Menu + MenuItem 构建，点击统一走 ChatMenuAction 占位）。
   */
  @Builder
  HeaderOverflowMenu() {
    Menu() {
      MenuItem({ content: '搜索' })
        .onClick(() => {
          this.onDispatch(new OpenChatSearch());
        })
      if (this.uiState.chatKind === 'private') {
        MenuItem({ content: this.muteMenuLabel() })
          .onClick(() => {
            this.onDispatch(new ChatMenuAction(this.muteMenuAction()));
          })
        MenuItem({ content: '清空历史记录' })
          .onClick(() => {
            this.onDispatch(new ChatMenuAction('clear_history'));
          })
        MenuItem({ content: '删除聊天' })
          .contentFontColor(this.T.colors.destructive)
          .onClick(() => {
            this.onDispatch(new ChatMenuAction('delete_chat'));
          })
      } else if (this.uiState.chatKind === 'group' || this.uiState.chatKind === 'channel') {
        MenuItem({ content: this.muteMenuLabel() })
          .onClick(() => {
            this.onDispatch(new ChatMenuAction(this.muteMenuAction()));
          })
        MenuItem({ content: '举报' })
          .onClick(() => {
            this.onDispatch(new ChatMenuAction('report'));
          })
        MenuItem({ content: this.uiState.chatKind === 'channel' ? '退出频道' : '退出群组' })
          .onClick(() => {
            this.onDispatch(new ChatMenuAction('leave'));
          })
        if (this.uiState.chatKind === 'group') {
          MenuItem({ content: '已关联的频道' })
            .onClick(() => {
              this.onDispatch(new ChatMenuAction('linked_channel'));
            })
        }
      }
    }
  }

  /**
   * MENU-101：⋮ 菜单破坏性操作确认弹窗（全屏半透明遮罩 + 居中白色卡片）。
   * 标题与按钮文案按 pendingMenuAction 分流：
   * - clear_history → "清空历史记录？" / "清空" / "取消"
   * - delete_chat → "删除聊天？" / "删除" / "取消"（destructive 色）
   * - report → "举报此聊天？" / "举报" / "取消"
   * - leave → "退出群组/频道？" / "退出" / "取消"
   */
  @Builder
  MenuConfirmDialogOverlay() {
    Stack() {
      Column()
        .width('100%')
        .height('100%')
        .backgroundColor('#66000000')
        .onClick(() => {
          this.onDispatch(new DismissMenuConfirmDialog());
        })

      Column() {
        Text(this.menuConfirmTitle())
          .fontSize(this.T.typography.body.fontSize)
          .fontWeight(FontWeight.Medium)
          .fontColor(this.T.colors.textPrimary)
          .margin({ bottom: this.T.spacing.md })

        Row() {
          Text('取消')
            .fontSize(this.T.typography.body.fontSize)
            .fontColor(this.T.colors.textSecondary)
            .layoutWeight(1)
            .textAlign(TextAlign.Center)
            .padding({ top: this.T.spacing.sm, bottom: this.T.spacing.sm })
            .onClick(() => {
              this.onDispatch(new DismissMenuConfirmDialog());
            })

          Text(this.menuConfirmActionLabel())
            .fontSize(this.T.typography.body.fontSize)
            .fontWeight(FontWeight.Medium)
            .fontColor(this.menuConfirmIsDestructive() ? this.T.colors.destructive : this.T.colors.accent)
            .layoutWeight(1)
            .textAlign(TextAlign.Center)
            .padding({ top: this.T.spacing.sm, bottom: this.T.spacing.sm })
            .onClick(() => {
              this.onDispatch(new ConfirmMenuAction());
            })
        }
        .width('100%')
      }
      .width('75%')
      .padding(this.T.spacing.lg)
      .backgroundColor(this.T.colors.surface)
      .borderRadius(12)
    }
    .width('100%')
    .height('100%')
  }

  private menuConfirmTitle(): string {
    const action: string = this.uiState.pendingMenuAction;
    if (action === 'clear_history') {
      return '清空历史记录？';
    } else if (action === 'delete_chat') {
      return '删除聊天？';
    } else if (action === 'report') {
      return '举报此聊天？';
    } else if (action === 'leave') {
      return this.uiState.chatKind === 'channel' ? '退出频道？' : '退出群组？';
    }
    return '';
  }

  private menuConfirmActionLabel(): string {
    const action: string = this.uiState.pendingMenuAction;
    if (action === 'clear_history') {
      return '清空';
    } else if (action === 'delete_chat') {
      return '删除';
    } else if (action === 'report') {
      return '举报';
    } else if (action === 'leave') {
      return '退出';
    }
    return '确认';
  }

  private menuConfirmIsDestructive(): boolean {
    const action: string = this.uiState.pendingMenuAction;
    return action === 'delete_chat';
  }

  /** MSG-108：会话内置顶消息横条（彩条 + 发送者 + 摘要 + 展开∨ + ✕ 关闭）。 */
  @Builder
  PinnedMessageBar(pinned: PinnedMessageInfo) {
    Row() {
      // 1. 左侧竖彩条 (2vp 宽，accent 色)
      // 竖条跟随栏内文字放大：默认档 34vp 不变，高档位下与两行摘要等高，避免出现
      // 「栏长条短」的失衡（SET-105）。
      Column()
        .width(2)
        .height(this.chatText(34))
        .backgroundColor(this.T.colors.accent)
        .borderRadius(1)
        .margin({ right: this.T.spacing.sm })

      // 2. 中间：发送者标题 + 内容摘要（点击触发跳转定位）
      Column() {
        Row() {
          Text(pinned.senderTitle)
            .fontSize(this.chatText(this.T.typography.caption.fontSize, -1))
            .fontWeight(FontWeight.Medium)
            .fontColor(this.T.colors.accent)
            .maxLines(1)
            .textOverflow({ overflow: TextOverflow.Ellipsis })

          Image($r('app.media.ic_chevron_down'))
            .width(12)
            .height(12)
            .fillColor(this.T.colors.textSecondary)
            .margin({ left: 2 })
        }
        .width('100%')
        .alignItems(VerticalAlign.Center)

        Text(pinned.contentSnippet)
          .fontSize(this.chatText(this.T.typography.body.fontSize, -1))
          .fontColor(this.T.colors.textPrimary)
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
          .margin({ top: 2 })
      }
      .layoutWeight(1)
      .alignItems(HorizontalAlign.Start)
      .justifyContent(FlexAlign.Center)
      .onClick(() => {
        this.onDispatch(new JumpToPinnedMessage());
      })

      // 3. 右侧：✕ 临时收起按钮
      Row() {
        Image($r('app.media.ic_close'))
          .width(16)
          .height(16)
          .fillColor(this.T.colors.textSecondary)
      }
      .width(36)
      .height(36)
      .justifyContent(FlexAlign.Center)
      .alignItems(VerticalAlign.Center)
      .onClick(() => {
        this.onDispatch(new DismissPinnedBar());
      })
    }
    .width('100%')
    // SET-105：栏高不能写死。栏内两行文字（发送者标题 + 内容摘要）已接入聊天字号，
    // 26 档时两行合计 ≈48vp + 间距/内边距 ≈ 58vp，写死 48vp 会把内容压回去并溢出到
    // 下方消息列表（模拟器实测溢出 66px）。这里改成「最小 48vp、随内容增长」：
    // 默认档内容装得下，视觉与改造前一致；高档位栏体自然变高，不再压字。
    .constraintSize({ minHeight: 48 })
    .padding({
      left: this.T.spacing.screenInset,
      right: this.T.spacing.xs,
      top: 4,
      bottom: 4
    })
    .backgroundColor(this.T.colors.surface)
    .border({
      width: { bottom: 0.5 },
      color: { bottom: this.T.colors.divider }
    })
    .alignItems(VerticalAlign.Center)
  }

  /** MSG-103：日期胶囊头（居中展示半透明灰色胶囊卡片，如 9月11日 或 2024年9月11日）。 */
  @Builder
  DateHeader(dateText: string) {
    Row() {
      Text(dateText)
        .fontSize(12)
        .fontWeight(FontWeight.Medium)
        .fontColor(Color.White)
        .backgroundColor(this.T.colors.scrim)
        .borderRadius(this.T.radius.full)
        .padding({
          left: 10,
          right: 10,
          top: 4,
          bottom: 4
        })
    }
    .width('100%')
    .justifyContent(FlexAlign.Center)
    .margin({ top: 10, bottom: 6 })
  }

  /** MSG-103：未读消息分隔线（全宽浅灰蓝背景横条 + 居中 Telegram 蓝 "新消息 ∨"）。 */
  @Builder
  UnreadSeparator() {
    Row() {
      Text('新消息')
        .fontSize(13)
        .fontWeight(FontWeight.Medium)
        .fontColor(this.T.colors.accent)

      Image($r('app.media.ic_arrow_down'))
        .width(14)
        .height(14)
        .fillColor(this.T.colors.accent)
        .margin({ left: 4 })
    }
    .width('100%')
    .height(32)
    .backgroundColor(this.T.colors.chatOutgoing)
    .borderWidth({ top: 0.5, bottom: 0.5 })
    .borderColor(this.T.colors.divider)
    .justifyContent(FlexAlign.Center)
    .alignItems(VerticalAlign.Center)
    .margin({ top: 6, bottom: 6 })
    .onClick(() => {
      this.scroller.scrollToIndex(this.shownCount - 1, true, ScrollAlign.END);
    })
  }

  @Builder
  MessageRow(item: MessageItem) {
    Column() {
      // MSG-103：日期胶囊头（跨天或列表顶端最旧消息）
      if (item.showDateHeader) {
        this.DateHeader(item.dateHeaderText)
      }

      // MSG-103：未读消息分隔线（进入会话时的首条未读）
      if (item.showUnreadSeparator) {
        this.UnreadSeparator()
      }

      Row() {
        // MSG-106：多选态下勾选圈落在气泡外侧（收到的在左、发出的在右），
        // 与 Telegram X 的选择态一致；非多选态不占位。
        if (this.uiState.selectionMode && !item.isOutgoing) {
          this.SelectionMark(item)
        }

      // MSG-102 & MSG-102-AVATAR：群聊收到的消息在气泡左侧出小圆头像（真实头像 Cover 裁剪，缺省或下载中出彩色底 + 首字母）。
      // PROFILE-101：头像可点击 → 打开发送者用户资料页（对齐 Android onAvatarClick）。
      if (this.showSenderUi(item)) {
        if (item.senderAvatarPath !== null && item.senderAvatarPath.length > 0) {
          Image(toSandboxUri(item.senderAvatarPath))
            .width(SENDER_AVATAR_SIZE)
            .height(SENDER_AVATAR_SIZE)
            .borderRadius(this.T.radius.full)
            .objectFit(ImageFit.Cover)
            .margin({ right: this.T.spacing.xs })
            .onClick(() => this.onSenderAvatarClick(item))
        } else {
          Text(avatarLettersForName(item.senderName))
            .width(SENDER_AVATAR_SIZE)
            .height(SENDER_AVATAR_SIZE)
            .borderRadius(this.T.radius.full)
            .backgroundColor(this.senderAvatarColor(item))
            .fontColor(this.T.colors.textOnAccent)
            .fontSize(this.T.typography.footnote.fontSize)
            .textAlign(TextAlign.Center)
            .margin({ right: this.T.spacing.xs })
            .onClick(() => this.onSenderAvatarClick(item))
        }
      }

      Column() {
        // MSG-102：署名行（气泡最顶部，回复引用之上）。
        if (this.showSenderUi(item)) {
          Text(item.senderName)
            .fontSize(this.chatText(this.T.typography.subheadline.fontSize))
            .fontWeight(FontWeight.Medium)
            .fontColor(this.senderNameColor(item))
            .maxLines(1)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
            .alignSelf(ItemAlign.Start)
            .margin({ bottom: this.T.spacing.hairline })
        }

        // 回复引用行（CHAT-004）：微缩图（贴纸/照片）+ 细色条 + 署名与摘要
        if (item.replyToMessageId !== null) {
          this.ReplyReference(item)
        }

        // 多媒体附件（MEDIA-101 / MEDIA-105）：图片、视频、GIF 动图；贴纸（STICKER-101）；相册九宫格（MSG-107）。
        if (item.albumItems.length > 1) {
          this.MediaAlbumBubble(item)
        } else if (item.media !== null) {
          if (this.isSticker(item)) {
            this.StickerBubble(item.media, item)
          } else if (item.media.kind === 'document') {
            this.DocumentBubble(item.media, item.messageId, item.sendState === 'failed')
          } else if (item.media.kind === 'voiceNote') {
            this.VoiceNoteBubble(item.media, item)
          } else if (item.media.kind === 'audio') {
            this.AudioBubble(item.media, item.messageId, item.sendState === 'failed')
          } else if (item.media.kind === 'videoNote') {
            this.VideoNoteBubble(item.media, item, item.sendState === 'failed')
          } else {
            this.MediaBubble(item.media, item.messageId, item.sendState === 'failed')
          }
        }

        // POLL-101：投票卡片（messagePoll），替代正文文本行。
        if (item.poll !== null) {
          this.PollBubble(item.messageId, item.poll)
        }

        // 链接预览卡片（MSG-107）：showAboveText 为 true 时在正文上方渲染
        if (item.linkPreview !== null && item.linkPreview.showAboveText) {
          this.LinkPreviewBubble(item.linkPreview)
        }

        // 正文/说明文字（MSG-101）：有富文本 spans 时按 span 渲染，否则回退纯文本。
        if (item.spans.length > 0) {
          Text() {
            ForEach(item.spans, (span: MessageTextSpan, spanIndex: number) => {
              if (span.linkUrl !== null || span.isSpoiler) {
                // 可交互 span（链接 / spoiler）：本 SDK 的 ContainerSpan 不支持
                // onClick（universal events 不可用），Span 继承 CommonMethod 支持 onClick。
                Span(span.text)
                  .fontSize(this.spanFontSize(span))
                  .fontColor(this.spanFontColor(span, item.messageId, spanIndex))
                  .fontWeight(span.bold ? FontWeight.Bold : FontWeight.Normal)
                  .fontStyle(span.italic ? FontStyle.Italic : FontStyle.Normal)
                  .fontFamily(this.spanFontFamily(span))
                  .decoration({
                    type: this.spanDecorationType(span),
                    color: this.spanFontColor(span, item.messageId, spanIndex)
                  })
                  .textBackgroundStyle({
                    color: this.spanBackgroundColor(span, item.messageId, spanIndex),
                    radius: this.T.radius.sm
                  })
                  .onClick(() => {
                    this.onSpanClick(item.messageId, span, spanIndex);
                  })
              } else {
                Span(span.text)
                  .fontSize(this.spanFontSize(span))
                  .fontColor(this.spanFontColor(span, item.messageId, spanIndex))
                  .fontWeight(span.bold ? FontWeight.Bold : FontWeight.Normal)
                  .fontStyle(span.italic ? FontStyle.Italic : FontStyle.Normal)
                  .fontFamily(this.spanFontFamily(span))
                  .decoration({
                    type: this.spanDecorationType(span),
                    color: this.spanFontColor(span, item.messageId, spanIndex)
                  })
                  .textBackgroundStyle({
                    color: this.spanBackgroundColor(span, item.messageId, spanIndex),
                    radius: this.T.radius.sm
                  })
              }
            }, (span: MessageTextSpan, spanIndex: number) => `${item.messageId}:${spanIndex}`)
          }
          .alignSelf(ItemAlign.Start)
          .fontSize(this.chatText(this.T.typography.body.fontSize))
          .fontColor(this.T.colors.chatText)
          .margin(item.media !== null ? { top: this.T.spacing.xs } : { top: 0 })
        } else if (item.text.length > 0) {
          Text(item.text)
            .alignSelf(ItemAlign.Start)
            .fontSize(this.chatText(this.T.typography.body.fontSize))
            .fontColor(this.T.colors.chatText)
            .margin(item.media !== null ? { top: this.T.spacing.xs } : { top: 0 })
        }

        // 链接预览卡片（MSG-107）：默认在正文下方渲染
        if (item.linkPreview !== null && !item.linkPreview.showAboveText) {
          this.LinkPreviewBubble(item.linkPreview)
        }

        if (!this.isStandaloneBubble(item)) {
          this.MessageStatusBadge(item, false)
        }

        // CHANNEL-101：消息反应 chips
        if (item.reactionChips.length > 0) {
          this.ReactionsRow(item)
        }

        // CHANNEL-101：频道帖子评论入口行
        if (item.commentCount > 0) {
          this.CommentsRow(item)
        }
      }
      .alignItems(HorizontalAlign.End)
      .backgroundColor(item.isChannelPost ? Color.Transparent : (this.isStandaloneBubble(item) ? Color.Transparent : (item.isOutgoing ? this.T.colors.chatOutgoing : this.T.colors.chatIncoming)))
      .borderRadius(item.isChannelPost ? 0 : (this.isStandaloneBubble(item) ? 0 : this.T.radius.lg))
      .clip(this.isStandaloneBubble(item) ? false : true)
      .padding(item.isChannelPost ? {
        left: this.T.spacing.xs,
        right: this.T.spacing.xs,
        top: this.T.spacing.xs,
        bottom: this.T.spacing.xs
      } : (this.isStandaloneBubble(item) ? 0 : {
        left: this.T.spacing.md,
        right: this.T.spacing.md,
        top: this.T.spacing.sm,
        bottom: this.T.spacing.xs
      }))
      .width(item.isChannelPost ? '100%' : (item.linkPreview !== null ? BUBBLE_MAX_WIDTH : undefined))
      .constraintSize({ maxWidth: item.isChannelPost ? '100%' : BUBBLE_MAX_WIDTH })
      .onClick(() => {
        // MSG-106：多选态下点击气泡 = 切换勾选（不再触发重发）。
        if (this.uiState.selectionMode) {
          this.onDispatch(new ToggleMessageSelection(item.messageId));
          return;
        }
        // MSG-104：点击发送失败的气泡重发；正常气泡点击无动作。
        if (item.sendState === 'failed') {
          this.onDispatch(new TapFailedMessage(item.messageId));
        }
      })
      .gesture(
        LongPressGesture({ duration: 350 })
          .onAction(() => {
            // MSG-106：多选态下长按不弹菜单，与点击一致地切换勾选。
            if (this.uiState.selectionMode) {
              this.onDispatch(new ToggleMessageSelection(item.messageId));
              return;
            }
            this.onDispatch(new MessageActionRequested(item.messageId));
          })
      )

      if (this.uiState.selectionMode && item.isOutgoing) {
        this.SelectionMark(item)
      }
    }
    .width('100%')
    .justifyContent(item.isChannelPost ? FlexAlign.Start : (item.isOutgoing ? FlexAlign.End : FlexAlign.Start))
    .alignItems(VerticalAlign.Bottom)
    .padding({
      left: this.T.spacing.screenInset,
      right: this.T.spacing.screenInset,
      top: this.T.spacing.xs
    })
    }
    .width('100%')
    // SEARCH-102：跳转落位后目标行整行着色，让用户看清"跳到了哪条"
    // （短会话里跳转前后画面差别小，仅靠滚动位置无法辨认）。
    .backgroundColor(this.highlightedMessageId === item.messageId
      ? this.T.colors.chatOutgoing
      : Color.Transparent)
  }

  /** 消息气泡内时间与发送/已读状态徽章（原生矢量图标：ic_clock / ic_warning / ic_check_single / ic_check_double）。 */
  @Builder
  MessageStatusBadge(item: MessageItem, isOverlay: boolean = false) {
    Row() {
      if (item.isEdited) {
        Text('edited')
          .fontSize(isOverlay ? 10 : this.T.typography.caption.fontSize)
          .fontColor(isOverlay ? Color.White : (item.sendState === 'failed' ? this.T.colors.destructive : this.T.colors.textSecondary))
          .margin({ right: 3 })
      }

      if (item.timestampMs > 0) {
        Text(formatMessageTime(item.timestampMs))
          .fontSize(isOverlay ? 10 : this.T.typography.caption.fontSize)
          .fontColor(isOverlay ? Color.White : (item.sendState === 'failed' ? this.T.colors.destructive : this.T.colors.textSecondary))
      }

      if (item.sendState === 'pending') {
        Image($r('app.media.ic_clock'))
          .width(isOverlay ? 10 : 12)
          .height(isOverlay ? 10 : 12)
          .fillColor(isOverlay ? Color.White : this.T.colors.textSecondary)
          .margin({ left: 3 })
      } else if (item.sendState === 'failed') {
        Image($r('app.media.ic_warning'))
          .width(isOverlay ? 11 : 13)
          .height(isOverlay ? 11 : 13)
          .fillColor(this.T.colors.destructive)
          .margin({ left: 3 })
      } else if (item.isOutgoing) {
        if (item.isRead) {
          Image($r('app.media.ic_check_double'))
            .width(isOverlay ? 12 : 14)
            .height(isOverlay ? 12 : 14)
            .fillColor(isOverlay ? Color.White : this.T.colors.accent)
            .margin({ left: 3 })
        } else {
          Image($r('app.media.ic_check_single'))
            .width(isOverlay ? 11 : 13)
            .height(isOverlay ? 11 : 13)
            .fillColor(isOverlay ? Color.White : this.T.colors.textSecondary)
            .margin({ left: 3 })
        }
      }
    }
    .alignItems(VerticalAlign.Center)
    .margin(isOverlay ? 0 : { top: this.T.spacing.hairline })
  }

  /** MSG-106：一条消息的勾选圈（选中实心 + 矢量勾，未选中空心）。 */
  @Builder
  SelectionMark(item: MessageItem) {
    Row() {
      if (this.isSelected(item.messageId)) {
        Image($r('app.media.ic_check_single'))
          .width(14)
          .height(14)
          .fillColor(this.T.colors.textOnAccent)
      }
    }
    .width(SELECTION_MARK_SIZE)
    .height(SELECTION_MARK_SIZE)
    .borderRadius(this.T.radius.full)
    .borderWidth(1)
    .borderColor(this.isSelected(item.messageId) ? this.T.colors.accent : this.T.colors.textSecondary)
    .backgroundColor(this.isSelected(item.messageId) ? this.T.colors.accent : Color.Transparent)
    .justifyContent(FlexAlign.Center)
    .alignItems(VerticalAlign.Center)
    .margin({ left: this.T.spacing.xs, right: this.T.spacing.xs })
    .onClick(() => {
      this.onDispatch(new ToggleMessageSelection(item.messageId));
    })
  }

  /**
   * 媒体卡片宽度（vp）。上限必须同时受「设计上限 240」与「气泡内容区宽度」约束：
   * 写死 240 会让卡片比气泡内容区更宽，容器右对齐后卡片向左溢出并被 `.clip(true)` 裁掉，
   * 卡片里的上传进度圈 / 播放钮跟着整体偏左，看起来就是"没居中"。
   */
  private mediaCardWidth(media: MediaAttachment): number {
    const base: number = this.mediaCardBaseVp();
    if (media.width <= 0 || media.height <= 0) {
      return Math.min(220, base);
    }
    const ratio: number = media.width / media.height;
    if (ratio >= 1.0) {
      return base;
    }
    return Math.max(Math.min(140, base), Math.min(base, Math.round(base * ratio)));
  }

  /** 媒体卡片高度（vp）。宽高比以 base 为基准算，保证卡片不变形。 */
  private mediaCardHeight(media: MediaAttachment): number {
    const base: number = this.mediaCardBaseVp();
    if (media.width <= 0 || media.height <= 0) {
      return Math.min(160, base);
    }
    const ratio: number = media.width / media.height;
    if (ratio >= 1.0) {
      return Math.max(120, Math.min(240, Math.round(base / ratio)));
    }
    return base;
  }

  private isSticker(item: MessageItem): boolean {
    return item.media !== null && item.media.kind === 'sticker';
  }

  private isVideoNote(item: MessageItem): boolean {
    return item.media !== null && item.media.kind === 'videoNote';
  }

  private isStandaloneBubble(item: MessageItem): boolean {
    return this.isSticker(item) || this.isVideoNote(item);
  }

  private stickerWidth(media: MediaAttachment): number {
    const maxDim: number = 180;
    if (media.width <= 0 || media.height <= 0) {
      return maxDim;
    }
    const ratio: number = Math.min(maxDim / media.width, maxDim / media.height);
    return Math.max(60, Math.round(media.width * ratio));
  }

  private stickerHeight(media: MediaAttachment): number {
    const maxDim: number = 180;
    if (media.width <= 0 || media.height <= 0) {
      return maxDim;
    }
    const ratio: number = Math.min(maxDim / media.width, maxDim / media.height);
    return Math.max(60, Math.round(media.height * ratio));
  }

  /** 贴纸渲染（STICKER-101）：对齐 Telegram X 标准，无气泡框透明渲染，右下角半透明胶囊时间戳。 */
  @Builder
  StickerBubble(media: MediaAttachment, item: MessageItem) {
    Stack({ alignContent: Alignment.BottomEnd }) {
      if (media.localPath !== null && media.isDownloaded) {
        if (media.localPath.endsWith('.webm') || media.localPath.indexOf('.webm') >= 0 || media.localPath.endsWith('.mp4')) {
          Video({
            src: toSandboxUri(media.localPath),
            previewUri: toSandboxUri(media.thumbnailPath)
          })
            .autoPlay(true)
            .loop(true)
            .controls(false)
            .muted(true)
            .objectFit(ImageFit.Contain)
            .hitTestBehavior(HitTestMode.Transparent)
            .width('100%')
            .height('100%')
        } else {
          Image(toSandboxUri(media.localPath))
            .objectFit(ImageFit.Contain)
            .width('100%')
            .height('100%')
        }
      } else if (media.thumbnailPath !== null) {
        Image(toSandboxUri(media.thumbnailPath))
          .objectFit(ImageFit.Contain)
          .width('100%')
          .height('100%')

        if (media.isDownloading) {
          Column() {
            LoadingProgress()
              .width(28)
              .height(28)
              .color(Color.White)
          }
          .width(36)
          .height(36)
          .borderRadius(this.T.radius.full)
          .backgroundColor(this.T.colors.scrim)
          .justifyContent(FlexAlign.Center)
          .alignItems(HorizontalAlign.Center)
        }
      } else {
        Column() {
          if (media.caption.length > 0) {
            Text(media.caption)
              .fontSize(72)
          } else {
            Image($r('app.media.ic_photo'))
              .width(36)
              .height(36)
              .fillColor(this.T.colors.textSecondary)
          }
        }
        .width('100%')
        .height('100%')
        .justifyContent(FlexAlign.Center)
        .alignItems(HorizontalAlign.Center)
      }

      // 右下角半透明胶囊时间戳（Telegram X 标准：drawBubbleTimeOverContent）
      Row() {
        this.MessageStatusBadge(item, true)
      }
      .padding({ left: 6, right: 6, top: 2, bottom: 2 })
      .backgroundColor(this.T.colors.scrim)
      .borderRadius(this.T.radius.full)
      .margin({ right: 4, bottom: 4 })
    }
    .width(this.stickerWidth(media))
    .height(this.stickerHeight(media))
    .onClick(() => {
      if (this.uiState.selectionMode) {
        return;
      }
      if (media.stickerSetId.length > 0 && media.stickerSetId !== '0') {
        this.onDispatch(new OpenStickerSet(media.stickerSetId));
      }
    })
  }

  /** 文件消息气泡渲染（MEDIA-104 / FILE-103 / FEAT-MEDIA-003）：文件名、大小、下载/上传进度、失败重试、点击动作。 */
  @Builder
  DocumentBubble(media: MediaAttachment, messageId: number, isFailed: boolean = false) {
    Row() {
      // 左侧圆形图标与状态交互按钮（直径 44）
      Stack({ alignContent: Alignment.Center }) {
        if (isFailed) {
          // FILE-103：发送失败态：红色底色 + 重试图标
          Column() {
            Image($r('app.media.ic_refresh'))
              .width(22)
              .height(22)
              .fillColor(this.T.colors.textOnAccent)
          }
          .width(44)
          .height(44)
          .borderRadius(this.T.radius.full)
          .backgroundColor(this.T.colors.destructive)
          .justifyContent(FlexAlign.Center)
          .alignItems(HorizontalAlign.Center)
        } else if (media.isUploading) {
          // 上传中：进度转圈
          Column() {
            LoadingProgress()
              .width(28)
              .height(28)
              .color(this.T.colors.textOnAccent)
          }
          .width(44)
          .height(44)
          .borderRadius(this.T.radius.full)
          .backgroundColor(this.T.colors.accent)
          .justifyContent(FlexAlign.Center)
          .alignItems(HorizontalAlign.Center)
        } else if (media.isDownloading) {
          // 下载中：进度转圈
          Column() {
            LoadingProgress()
              .width(28)
              .height(28)
              .color(this.T.colors.textOnAccent)
          }
          .width(44)
          .height(44)
          .borderRadius(this.T.radius.full)
          .backgroundColor(this.T.colors.accent)
          .justifyContent(FlexAlign.Center)
          .alignItems(HorizontalAlign.Center)
        } else if (media.isDownloaded) {
          // 已下载：强调底色 + 文档图标
          Column() {
            Image($r('app.media.ic_file'))
              .width(22)
              .height(22)
              .fillColor(this.T.colors.accent)
          }
          .width(44)
          .height(44)
          .borderRadius(this.T.radius.full)
          .backgroundColor(this.T.colors.surfaceVariant)
          .justifyContent(FlexAlign.Center)
          .alignItems(HorizontalAlign.Center)
        } else {
          // 未下载：强调底色 + 白色向下箭头
          Column() {
            Image($r('app.media.ic_download'))
              .width(20)
              .height(20)
              .fillColor(this.T.colors.textOnAccent)
          }
          .width(44)
          .height(44)
          .borderRadius(this.T.radius.full)
          .backgroundColor(this.T.colors.accent)
          .justifyContent(FlexAlign.Center)
          .alignItems(HorizontalAlign.Center)
        }
      }
      .width(44)
      .height(44)
      // 定宽圆钮：不让它参与 Row 的宽度分配，否则会被 layoutWeight 文字列挤成椭圆。
      .flexShrink(0)
      .constraintSize({ minWidth: 44, maxWidth: 44 })
      .margin({ right: this.T.spacing.sm })
      .onClick(() => {
        if (isFailed) {
          // FILE-103：失败重试发送
          this.onDispatch(new TapFailedMessage(messageId));
        } else if (media.isUploading) {
          // 上传中点击：取消上传并撤回
          this.onDispatch(new CancelMediaUpload(messageId));
        } else if (media.isDownloading) {
          // FILE-103：下载中点击：取消下载
          this.onDispatch(new CancelMediaDownload(media.fileId));
        } else if (!media.isDownloaded) {
          this.onDispatch(new RequestMediaDownload(media.fileId));
        } else {
          hilog.info(DOMAIN, TAG, `open document: ${media.fileName}, path: ${media.localPath}`);
        }
      })

      // 右侧：文件名与文件大小 / 进度信息 / 失败提示
      Column() {
        Text(media.fileName.length > 0 ? media.fileName : 'Document')
          .fontSize(this.chatText(this.T.typography.body.fontSize))
          .fontWeight(FontWeight.Medium)
          .fontColor(this.T.colors.textPrimary)
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })

        Text(isFailed ? 'Failed · Tap to retry' : this.documentSubtitle(media))
          .fontSize(this.chatText(this.T.typography.caption.fontSize, -2))
          .fontColor(isFailed ? this.T.colors.destructive : this.T.colors.textSecondary)
          .margin({ top: this.T.spacing.xs })
      }
      .alignItems(HorizontalAlign.Start)
      .layoutWeight(1)
      // 显式收窄文字列：长文件名（不可断行）理想宽度可达 200vp，
      // 若让它先占满，44vp 图标就只剩 30vp（实测 108×154px）。
      .constraintSize({ maxWidth: this.rowTextMaxVp(44, this.T.spacing.sm) })
    }
    .width('100%')
    // maxWidth 用气泡内容区宽度（而不是 260）：行内文字列带 layoutWeight，
    // 行若比内容区宽就会左溢被裁，并把定宽图标挤扁。
    .constraintSize({ minWidth: 180, maxWidth: this.contentMaxVp() })
    .padding({
      top: this.T.spacing.xs,
      bottom: this.T.spacing.xs,
      left: this.T.spacing.xs,
      right: this.T.spacing.xs
    })
  }

  private documentSubtitle(media: MediaAttachment): string {
    if (media.isUploading) {
      const pct: number = Math.round(media.uploadProgress * 100);
      return `Uploading ${pct}%`;
    }
    if (media.isDownloading) {
      return `${formatFileSize(media.fileSize * media.progress)} / ${formatFileSize(media.fileSize)}`;
    }
    if (media.fileSize > 0) {
      return formatFileSize(media.fileSize);
    }
    return 'File';
  }

  /** 语音消息气泡渲染（VOICE-101）：播放控制、波形条可视化、时长与未收听标记。 */
  @Builder
  VoiceNoteBubble(media: MediaAttachment, item: MessageItem) {
    Row() {
      // 播放/下载控制按钮
      Stack({ alignContent: Alignment.Center }) {
        if (media.isDownloading) {
          LoadingProgress()
            .width(22)
            .height(22)
            .color(this.T.colors.textOnAccent)
        } else if (this.uiState.playingVoiceMessageId === item.messageId) {
          Image($r('app.media.ic_pause'))
            .width(20)
            .height(20)
            .fillColor(this.T.colors.textOnAccent)
        } else {
          Image($r('app.media.ic_play'))
            .width(20)
            .height(20)
            .fillColor(this.T.colors.textOnAccent)
        }
      }
      .width(40)
      .height(40)
      .borderRadius(this.T.radius.full)
      .backgroundColor(this.T.colors.accent)
      // 定宽播放钮：不参与 Row 的宽度分配，避免被文字列挤扁（与文档气泡同因）。
      .flexShrink(0)
      .constraintSize({ minWidth: 40, maxWidth: 40 })
      .margin({ right: this.T.spacing.sm })
      .onClick(() => {
        if (media.isDownloading) {
          this.onDispatch(new CancelMediaDownload(media.fileId));
        } else if (!media.isDownloaded && (media.localPath === null || media.localPath.length === 0)) {
          this.onDispatch(new RequestMediaDownload(media.fileId));
        } else {
          if (this.uiState.playingVoiceMessageId === item.messageId) {
            this.onDispatch(new PauseVoiceNote(item.messageId));
          } else {
            this.onDispatch(new PlayVoiceNote(item.messageId, media.fileId, media.localPath));
          }
        }
      })

      // 右侧：波形栏与时长信息
      Column() {
        // 波形条（28 柱动态高亮）
        Row() {
          ForEach(normalizeWaveform(media.waveform, 28), (sample: number, index: number) => {
            Column()
              .width(2)
              .height(Math.max(3, Math.round((sample / 31) * 20)))
              .borderRadius(1)
              .backgroundColor(
                (this.uiState.playingVoiceMessageId === item.messageId)
                  ? (index <= Math.floor(this.uiState.voicePlaybackProgress * 28) ? this.T.colors.accent : (item.isOutgoing ? '#802AABEE' : '#80999999'))
                  : this.T.colors.accent
              )
              .margin({ right: 2 })
          }, (_sample: number, index: number) => `${index}`)
        }
        .alignItems(VerticalAlign.Center)
        .height(24)

        // 时长与未收听蓝点
        Row() {
          Text(
            (this.uiState.playingVoiceMessageId === item.messageId && this.uiState.voicePlaybackTimeSec > 0)
              ? formatDuration(this.uiState.voicePlaybackTimeSec)
              : formatDuration(media.duration)
          )
            .fontSize(this.chatText(this.T.typography.caption.fontSize, -2))
            .fontColor(this.T.colors.textSecondary)

          if (!media.isListened && !item.isOutgoing) {
            Row()
              .width(6)
              .height(6)
              .borderRadius(this.T.radius.full)
              .backgroundColor(this.T.colors.accent)
              .margin({ left: this.T.spacing.xs })
          }
        }
        .alignItems(VerticalAlign.Center)
        .margin({ top: this.T.spacing.hairline })
      }
      .alignItems(HorizontalAlign.Start)
      .layoutWeight(1)
      // 显式收窄：否则波形/时长列先占满理想宽度，把 40vp 播放钮挤成椭圆（与文档气泡同因）。
      .constraintSize({ maxWidth: this.rowTextMaxVp(40, this.T.spacing.sm) })
    }
    .alignItems(VerticalAlign.Center)
    // maxWidth 用气泡内容区宽度，不用 260——行比内容区宽会左溢被 .clip(true) 裁掉。
    .constraintSize({ minWidth: 200, maxWidth: this.contentMaxVp() })
    .padding({
      top: this.T.spacing.xs,
      bottom: this.T.spacing.xs,
      left: this.T.spacing.xs,
      right: this.T.spacing.xs
    })
  }

  /** 音乐/音频消息气泡渲染（AUDIO-101）：专辑封面/音乐图标、歌曲名、演奏者、时长。 */
  @Builder
  AudioBubble(media: MediaAttachment, messageId: number, isFailed: boolean = false) {
    Row() {
      // 左侧：封面/播放控制按钮
      Stack({ alignContent: Alignment.Center }) {
        if (isFailed) {
          Image($r('app.media.ic_refresh'))
            .width(22)
            .height(22)
            .fillColor(this.T.colors.textOnAccent)
        } else if (media.isUploading || media.isDownloading) {
          LoadingProgress()
            .width(24)
            .height(24)
            .color(this.T.colors.textOnAccent)
        } else if (media.isDownloaded) {
          if (this.uiState.playingVoiceMessageId === messageId) {
            Image($r('app.media.ic_pause'))
              .width(22)
              .height(22)
              .fillColor(this.T.colors.textOnAccent)
          } else {
            Image($r('app.media.ic_play'))
              .width(22)
              .height(22)
              .fillColor(this.T.colors.textOnAccent)
          }
        } else {
          Image($r('app.media.ic_download'))
            .width(20)
            .height(20)
            .fillColor(this.T.colors.textOnAccent)
        }
      }
      .width(44)
      .height(44)
      .borderRadius(this.T.radius.full)
      .backgroundColor(isFailed ? this.T.colors.destructive : this.T.colors.accent)
      // 定宽圆钮：不参与 Row 的宽度分配，避免被文字列挤扁（与文档气泡同因）。
      .flexShrink(0)
      .constraintSize({ minWidth: 44, maxWidth: 44 })
      .margin({ right: this.T.spacing.sm })
      .onClick(() => {
        if (isFailed) {
          this.onDispatch(new TapFailedMessage(messageId));
        } else if (media.isUploading) {
          this.onDispatch(new CancelMediaUpload(messageId));
        } else if (media.isDownloading) {
          this.onDispatch(new CancelMediaDownload(media.fileId));
        } else if (!media.isDownloaded) {
          this.onDispatch(new RequestMediaDownload(media.fileId));
        } else {
          if (this.uiState.playingVoiceMessageId === messageId) {
            this.onDispatch(new PauseVoiceNote(messageId));
          } else {
            if (this.activeVideoNoteId !== null) {
              this.activeVideoNoteId = null;
            }
            this.onDispatch(new PlayVoiceNote(messageId, media.fileId, media.localPath));
          }
        }
      })

      // 右侧：标题与演奏者/时长
      Column() {
        Text(media.audioTitle.length > 0 ? media.audioTitle : (media.fileName.length > 0 ? media.fileName : this.t('Audio')))
          .fontSize(this.chatText(this.T.typography.body.fontSize))
          .fontWeight(FontWeight.Medium)
          .fontColor(this.T.colors.textPrimary)
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })

        if (this.uiState.playingVoiceMessageId === messageId) {
          Row() {
            Progress({
              value: Math.min(100, Math.max(0, this.uiState.voicePlaybackProgress * 100)),
              total: 100,
              type: ProgressType.Linear
            })
              .color(this.T.colors.accent)
              .backgroundColor(this.T.colors.divider)
              .height(3)
              .layoutWeight(1)
          }
          .width('100%')
          .margin({ top: this.T.spacing.xs, bottom: 2 })
        }

        Text(this.audioSubtitle(media, isFailed, messageId))
          .fontSize(this.chatText(this.T.typography.caption.fontSize, -2))
          .fontColor(isFailed ? this.T.colors.destructive : this.T.colors.textSecondary)
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
          .margin({ top: this.uiState.playingVoiceMessageId === messageId ? 0 : this.T.spacing.xs })
      }
      .alignItems(HorizontalAlign.Start)
      .layoutWeight(1)
      // 显式收窄：否则曲目/歌手列先占满理想宽度，把 44vp 封面钮挤成椭圆（与文档气泡同因）。
      .constraintSize({ maxWidth: this.rowTextMaxVp(44, this.T.spacing.sm) })
    }
    .width('100%')
    .alignItems(VerticalAlign.Center)
    // maxWidth 用气泡内容区宽度，不用 260——行比内容区宽会左溢被 .clip(true) 裁掉。
    .constraintSize({ minWidth: 200, maxWidth: this.contentMaxVp() })
    .padding({
      top: this.T.spacing.xs,
      bottom: this.T.spacing.xs,
      left: this.T.spacing.xs,
      right: this.T.spacing.xs
    })
  }

  private audioSubtitle(media: MediaAttachment, isFailed: boolean = false, messageId?: number): string {
    if (isFailed) {
      return 'Failed · Tap to retry';
    }
    if (media.isUploading) {
      const pct: number = Math.round(media.uploadProgress * 100);
      return `Uploading ${pct}%`;
    }
    if (media.isDownloading) {
      return `${formatFileSize(media.fileSize * media.progress)} / ${formatFileSize(media.fileSize)}`;
    }
    if (messageId !== undefined && this.uiState.playingVoiceMessageId === messageId) {
      const curDur: string = formatDuration(this.uiState.voicePlaybackTimeSec);
      const totalDur: string = media.duration > 0 ? formatDuration(media.duration) : '';
      if (totalDur.length > 0) {
        return `${curDur} / ${totalDur}`;
      }
      return curDur;
    }
    const artist: string = media.audioPerformer.length > 0 ? media.audioPerformer : this.t('Unknown artist');
    const dur: string = media.duration > 0 ? formatDuration(media.duration) : formatFileSize(media.fileSize);
    return `${artist} · ${dur}`;
  }

  /** 圆形视频消息气泡渲染（VIDEONOTE-101）：对齐 Telegram X 标准，无外层矩形气泡框，独立圆形 220x220 裁切播放，右下角浮动半透明胶囊时间戳。 */
  @Builder
  VideoNoteBubble(media: MediaAttachment, item: MessageItem, isFailed: boolean = false) {
    Stack({ alignContent: Alignment.BottomEnd }) {
      // 220x220 圆形裁切容器
      Stack({ alignContent: Alignment.Center }) {
        if (media.localPath !== null && media.isDownloaded) {
          Video({
            src: toSandboxUri(media.localPath),
            previewUri: toSandboxUri(media.thumbnailPath)
          })
            .autoPlay(true)
            .loop(true)
            .controls(false)
            .muted(this.activeVideoNoteId !== item.messageId)
            .objectFit(ImageFit.Cover)
            .width(220)
            .height(220)
        } else if (media.thumbnailPath !== null) {
          Image(toSandboxUri(media.thumbnailPath))
            .objectFit(ImageFit.Cover)
            .width(220)
            .height(220)

          if (media.isDownloading) {
            Column() {
              LoadingProgress()
                .width(28)
                .height(28)
                .color(this.T.colors.textOnAccent)
            }
            .width(44)
            .height(44)
            .borderRadius(this.T.radius.full)
            .backgroundColor(this.T.colors.scrim)
            .justifyContent(FlexAlign.Center)
            .alignItems(HorizontalAlign.Center)
          } else {
            Column() {
              Image($r('app.media.ic_download'))
                .width(22)
                .height(22)
                .fillColor(this.T.colors.textOnAccent)
            }
            .width(44)
            .height(44)
            .borderRadius(this.T.radius.full)
            .backgroundColor(this.T.colors.scrim)
            .justifyContent(FlexAlign.Center)
            .alignItems(HorizontalAlign.Center)
          }
        } else {
          Column() {
            Image($r('app.media.ic_camera'))
              .width(36)
              .height(36)
              .fillColor(this.T.colors.textSecondary)
          }
          .width(220)
          .height(220)
          .backgroundColor(this.T.colors.surfaceVariant)
          .justifyContent(FlexAlign.Center)
          .alignItems(HorizontalAlign.Center)
        }
      }
      .width(220)
      .height(220)
      .borderRadius(110)
      .clip(true)
      .onClick(() => {
        if (isFailed) {
          this.onDispatch(new TapFailedMessage(item.messageId));
        } else if (media.isDownloading) {
          this.onDispatch(new CancelMediaDownload(media.fileId));
        } else if (!media.isDownloaded) {
          this.onDispatch(new RequestMediaDownload(media.fileId));
        } else {
          // 点击切换有声/静音播放
          if (this.activeVideoNoteId === item.messageId) {
            this.activeVideoNoteId = null;
          } else {
            if (this.uiState.playingVoiceMessageId !== null) {
              this.onDispatch(new PauseVoiceNote(this.uiState.playingVoiceMessageId));
            }
            this.activeVideoNoteId = item.messageId;
          }
        }
      })

      // 左上角半透明扬声器状态角标
      if (media.localPath !== null && media.isDownloaded) {
        Row() {
          Image(this.activeVideoNoteId === item.messageId ? $r('app.media.ic_volume_up') : $r('app.media.ic_mute'))
            .width(14)
            .height(14)
            .fillColor(this.T.colors.textOnAccent)
        }
        .padding(5)
        .backgroundColor(this.T.colors.scrim)
        .borderRadius(this.T.radius.full)
        .position({ x: 10, y: 10 })
        .onClick(() => {
          if (this.activeVideoNoteId === item.messageId) {
            this.activeVideoNoteId = null;
          } else {
            if (this.uiState.playingVoiceMessageId !== null) {
              this.onDispatch(new PauseVoiceNote(this.uiState.playingVoiceMessageId));
            }
            this.activeVideoNoteId = item.messageId;
          }
        })
      }

      // 右下角半透明胶囊时间戳与状态
      Row() {
        this.MessageStatusBadge(item, true)
      }
      .padding({ left: 6, right: 6, top: 2, bottom: 2 })
      .backgroundColor(this.T.colors.scrim)
      .borderRadius(this.T.radius.full)
      .margin({ right: 6, bottom: 6 })
      .onClick(() => {
        this.onDispatch(new OpenMediaViewer(item.messageId));
      })
    }
    .width(220)
    .height(220)
  }

  private getMosaicLayout(item: MessageItem): MosaicLayoutResult {
    return calculateMosaicLayout(item.albumItems, 256, 2, item.text.length > 0);
  }

  /** 相册多图九宫格气泡渲染（FEAT-MEDIA-002 / MSG-107）。 */
  @Builder
  MediaAlbumBubble(item: MessageItem) {
    Column({ space: 2 }) {
      ForEach(this.getMosaicLayout(item).lines, (line: MosaicLine) => {
        Row({ space: 2 }) {
          ForEach(line.items, (geom: MosaicItemGeometry) => {
            Stack({ alignContent: Alignment.Center }) {
              if (item.albumItems[geom.index].localPath !== null && item.albumItems[geom.index].isDownloaded) {
                Image(toSandboxUri(item.albumItems[geom.index].localPath))
                  .width('100%')
                  .height('100%')
                  .objectFit(ImageFit.Cover)
              } else if (item.albumItems[geom.index].thumbnailPath !== null) {
                Image(toSandboxUri(item.albumItems[geom.index].thumbnailPath))
                  .width('100%')
                  .height('100%')
                  .objectFit(ImageFit.Cover)
              } else {
                Column() {
                  Image($r('app.media.ic_photo'))
                    .width(22)
                    .height(22)
                    .fillColor(this.T.colors.textSecondary)
                }
                .width('100%')
                .height('100%')
                .justifyContent(FlexAlign.Center)
                .alignItems(HorizontalAlign.Center)
                .backgroundColor(this.T.colors.surfaceVariant)
              }

              if (!item.albumItems[geom.index].isDownloaded) {
                if (item.albumItems[geom.index].isDownloading) {
                  Column() {
                    LoadingProgress()
                      .width(28)
                      .height(28)
                      .color(Color.White)
                  }
                  .width(36)
                  .height(36)
                  .borderRadius(this.T.radius.full)
                  .backgroundColor(this.T.colors.scrim)
                  .justifyContent(FlexAlign.Center)
                  .alignItems(HorizontalAlign.Center)
                } else {
                  Column() {
                    Image($r('app.media.ic_download'))
                      .width(18)
                      .height(18)
                      .fillColor(Color.White)
                  }
                  .width(32)
                  .height(32)
                  .borderRadius(this.T.radius.full)
                  .backgroundColor(this.T.colors.scrim)
                  .justifyContent(FlexAlign.Center)
                  .alignItems(HorizontalAlign.Center)
                }
              }

              if (item.albumItems[geom.index].kind === 'video') {
                Row() {
                  Text(formatDuration(item.albumItems[geom.index].duration))
                    .fontSize(10)
                    .fontWeight(FontWeight.Medium)
                    .fontColor(Color.White)
                    .backgroundColor(this.T.colors.scrim)
                    .padding({ left: 4, right: 4, top: 1, bottom: 1 })
                    .borderRadius(3)
                }
                .width('100%')
                .height('100%')
                .alignItems(VerticalAlign.Bottom)
                .justifyContent(FlexAlign.End)
                .padding(4)
              }
            }
            .width(geom.width)
            .height(geom.height)
            .borderRadius({
              topLeft: geom.needTopLeftRound ? this.T.radius.md : 0,
              topRight: geom.needTopRightRound ? this.T.radius.md : 0,
              bottomLeft: geom.needBottomLeftRound ? this.T.radius.md : 0,
              bottomRight: geom.needBottomRightRound ? this.T.radius.md : 0
            })
            .clip(true)
            .onClick(() => {
              this.onDispatch(new OpenMediaViewer(item.messageId, item.albumItems[geom.index].fileId));
            })
          }, (geom: MosaicItemGeometry) => `${geom.index}:${geom.width}x${geom.height}`)
        }
        .height(line.lineHeight)
      }, (line: MosaicLine, idx: number) => `line_${idx}_${line.lineHeight}`)
    }
    .width(this.getMosaicLayout(item).width)
    .margin({ bottom: item.text.length > 0 ? this.T.spacing.xs : 0 })
  }

  /** 多媒体气泡渲染（MEDIA-101 / MEDIA-105 / FILE-103）：图片/视频/GIF 动图。 */
  @Builder
  MediaBubble(media: MediaAttachment, messageId: number, isFailed: boolean = false) {
    Stack({ alignContent: Alignment.Center }) {
      // 1. 底图 / 缩略图 / 占位 / 动图视频
      if (media.localPath !== null && (media.isDownloaded || media.isUploading)) {
        // MEDIA-VIEWER-102：容器按 mime（缺失时退回结尾扩展名）判定，不再用
        // `localPath.indexOf('.mp4') >= 0` 碰运气 —— GIF 容器的动图走下面的 Image 分支原生逐帧播。
        if (media.kind === 'animation' && animationContainer(media) === 'video') {
          // Telegram 动图通常为 MP4 格式，无声循环播放
          Video({
            src: toSandboxUri(media.localPath),
            previewUri: toSandboxUri(media.thumbnailPath)
          })
            .autoPlay(true)
            .loop(true)
            .controls(false)
            .muted(true)
            .objectFit(ImageFit.Cover)
            .width('100%')
            .height('100%')
            .borderRadius(this.T.radius.md)
        } else if (media.kind === 'video') {
          // 视频气泡：优先展示封面图（缩略图），若无缩略图则以 Video 组件首帧占位
          if (media.thumbnailPath !== null) {
            Image(toSandboxUri(media.thumbnailPath))
              .width('100%')
              .height('100%')
              .objectFit(ImageFit.Cover)
              .borderRadius(this.T.radius.md)
              // MEDIA-107：上传进度按 1% 分桶会让整行节点反复重建，异步解码的封面
              // 每帧都来不及上屏（表现为封面整段消失），故上传期间同步加载。
              .syncLoad(media.isUploading)
          } else {
            Video({
              src: toSandboxUri(media.localPath)
            })
              .autoPlay(false)
              .controls(false)
              .muted(true)
              .objectFit(ImageFit.Cover)
              .width('100%')
              .height('100%')
              .borderRadius(this.T.radius.md)
          }
        } else {
          // 普通图片或原生 GIF 格式图片
          Image(toSandboxUri(media.localPath))
            .width('100%')
            .height('100%')
            .objectFit(ImageFit.Cover)
            .borderRadius(this.T.radius.md)
        }
      } else if (media.thumbnailPath !== null) {
        Image(toSandboxUri(media.thumbnailPath))
          .width('100%')
          .height('100%')
          .objectFit(ImageFit.Cover)
          .borderRadius(this.T.radius.md)
          // MEDIA-107：同上，下载进度 1% 分桶重建整行时封面必须同步加载才不会被刷白。
          .syncLoad(media.isDownloading)
      } else {
        Column() {
          if (media.kind === 'video') {
            Image($r('app.media.ic_play'))
              .width(32)
              .height(32)
              .fillColor(this.T.colors.textSecondary)
          } else if (media.kind === 'animation') {
            Image($r('app.media.ic_play'))
              .width(32)
              .height(32)
              .fillColor(this.T.colors.textSecondary)
          } else {
            Image($r('app.media.ic_photo'))
              .width(32)
              .height(32)
              .fillColor(this.T.colors.textSecondary)
          }
        }
        .width('100%')
        .height('100%')
        .justifyContent(FlexAlign.Center)
        .alignItems(HorizontalAlign.Center)
        .backgroundColor(this.T.colors.surfaceVariant)
        .borderRadius(this.T.radius.md)
      }

      // 2. 状态与角标覆盖层
      if (isFailed) {
        // FILE-103：发送失败态：红色重试圆钮
        Column() {
          Image($r('app.media.ic_refresh'))
            .width(24)
            .height(24)
            .fillColor(this.T.colors.textOnAccent)
        }
        .width(52)
        .height(52)
        .borderRadius(this.T.radius.full)
        .backgroundColor(this.T.colors.destructive)
        .justifyContent(FlexAlign.Center)
        .alignItems(HorizontalAlign.Center)
        .onClick(() => {
          this.onDispatch(new TapFailedMessage(messageId));
        })
      } else if (media.kind === 'photo') {
        // 同视频：只判 isUploading，进度为 0 时也先把圈画出来，避免"等一会才出现进度条"。
        if (media.isUploading) {
          Column() {
            LoadingProgress()
              .width(36)
              .height(36)
              .color(Color.White)
            Text(`${Math.round(media.uploadProgress * 100)}%`)
              .fontSize(11)
              .fontColor(Color.White)
              .margin({ top: 4 })
          }
          .width(56)
          .height(56)
          .borderRadius(this.T.radius.full)
          .backgroundColor(this.T.colors.scrim)
          .justifyContent(FlexAlign.Center)
          .alignItems(HorizontalAlign.Center)
          .onClick(() => {
            this.onDispatch(new CancelMediaUpload(messageId));
          })
        } else if (!media.isDownloaded) {
          if (media.isDownloading) {
            Column() {
              LoadingProgress()
                .width(36)
                .height(36)
                .color(Color.White)
            }
            .width(48)
            .height(48)
            .borderRadius(this.T.radius.full)
            .backgroundColor(this.T.colors.scrim)
            .justifyContent(FlexAlign.Center)
            .alignItems(HorizontalAlign.Center)
            .onClick(() => {
              this.onDispatch(new CancelMediaDownload(media.fileId));
            })
          } else {
            Column() {
              Image($r('app.media.ic_download'))
                .width(22)
                .height(22)
                .fillColor(Color.White)
            }
            .width(44)
            .height(44)
            .borderRadius(this.T.radius.full)
            .backgroundColor(this.T.colors.scrim)
            .justifyContent(FlexAlign.Center)
            .alignItems(HorizontalAlign.Center)
            .onClick(() => {
              this.onDispatch(new RequestMediaDownload(media.fileId));
            })
          }
        }
      } else if (media.kind === 'animation') {
        // GIF 动图：左上角出 GIF 角标
        Row() {
          Text('GIF')
            .fontSize(10)
            .fontWeight(FontWeight.Bold)
            .fontColor(Color.White)
            .backgroundColor(this.T.colors.scrim)
            .padding({ left: 6, right: 6, top: 2, bottom: 2 })
            .borderRadius(4)
        }
        .width('100%')
        .height('100%')
        .alignItems(VerticalAlign.Top)
        .justifyContent(FlexAlign.Start)
        .padding(8)

        if (!media.isDownloaded) {
          if (media.isDownloading) {
            Column() {
              LoadingProgress()
                .width(36)
                .height(36)
                .color(Color.White)
            }
            .width(48)
            .height(48)
            .borderRadius(this.T.radius.full)
            .backgroundColor(this.T.colors.scrim)
            .justifyContent(FlexAlign.Center)
            .alignItems(HorizontalAlign.Center)
            .onClick(() => {
              this.onDispatch(new CancelMediaDownload(media.fileId));
            })
          } else {
            Column() {
              Image($r('app.media.ic_download'))
                .width(22)
                .height(22)
                .fillColor(Color.White)
            }
            .width(44)
            .height(44)
            .borderRadius(this.T.radius.full)
            .backgroundColor(this.T.colors.scrim)
            .justifyContent(FlexAlign.Center)
            .alignItems(HorizontalAlign.Center)
            .onClick(() => {
              this.onDispatch(new RequestMediaDownload(media.fileId));
            })
          }
        }
      } else if (media.kind === 'video') {
        // 视频：上传中 → 上传环（可取消）；未下载 → 下载环/下载钮；已就绪 → 播放钮。
        // MEDIA-105：上传态必须优先于「已下载」判断——出站视频的本地文件天然"已下载"，
        // 若先判 isDownloaded 就会直接显示播放钮，上传进度完全不可见。
        // 判据只留 isUploading（原先还要求 uploadProgress < 1）：进度尚为 0 时也要先把
        // 圈画出来，否则从"发起上传"到"首个进度回调"之间是一段没有任何指示的空窗期。
        if (media.isUploading) {
          Column() {
            LoadingProgress()
              .width(36)
              .height(36)
              .color(Color.White)
            Text(`${Math.round(media.uploadProgress * 100)}%`)
              .fontSize(11)
              .fontColor(Color.White)
              .margin({ top: 4 })
          }
          .width(56)
          .height(56)
          .borderRadius(this.T.radius.full)
          .backgroundColor(this.T.colors.scrim)
          .justifyContent(FlexAlign.Center)
          .alignItems(HorizontalAlign.Center)
          .onClick(() => {
            this.onDispatch(new CancelMediaUpload(messageId));
          })
        } else if (!media.isDownloaded && media.isDownloadFailed) {
          // MEDIA-107：下载失败要出错误态与重试入口。原先 TDLib 回了错误只打日志，
          // 气泡静默退回下载按钮，用户分不清「没下」和「下挂了」。
          Column() {
            Image($r('app.media.ic_warning'))
              .width(22)
              .height(22)
              .fillColor(Color.White)
            Text('重试')
              .fontSize(11)
              .fontColor(Color.White)
              .margin({ top: 2 })
          }
          .width(56)
          .height(56)
          .borderRadius(this.T.radius.full)
          .backgroundColor(this.T.colors.scrim)
          .justifyContent(FlexAlign.Center)
          .alignItems(HorizontalAlign.Center)
          .onClick(() => {
            this.onDispatch(new RequestMediaDownload(media.fileId));
          })
        } else if (!media.isDownloaded && media.isDownloading) {
          Column() {
            LoadingProgress()
              .width(36)
              .height(36)
              .color(Color.White)
            // MEDIA-107：下载进度要可读 —— 一条 20 秒的视频只转圈等于没有进度，
            // 与上传环对齐出百分比。
            Text(`${Math.round(media.progress * 100)}%`)
              .fontSize(11)
              .fontColor(Color.White)
              .margin({ top: 4 })
          }
          .width(56)
          .height(56)
          .borderRadius(this.T.radius.full)
          .backgroundColor(this.T.colors.scrim)
          .justifyContent(FlexAlign.Center)
          .alignItems(HorizontalAlign.Center)
          .onClick(() => {
            this.onDispatch(new CancelMediaDownload(media.fileId));
          })
        } else if (!media.isDownloaded) {
          Column() {
            Image($r('app.media.ic_download'))
              .width(24)
              .height(24)
              .fillColor(Color.White)
          }
          .width(48)
          .height(48)
          .borderRadius(this.T.radius.full)
          .backgroundColor(this.T.colors.scrim)
          .justifyContent(FlexAlign.Center)
          .alignItems(HorizontalAlign.Center)
          .onClick(() => {
            this.onDispatch(new RequestMediaDownload(media.fileId));
          })
        } else {
          Column() {
            Image($r('app.media.ic_play'))
              .width(26)
              .height(26)
              .fillColor(Color.White)
              .margin({ left: 3 })
          }
          .width(48)
          .height(48)
          .borderRadius(this.T.radius.full)
          .backgroundColor(this.T.colors.scrim)
          .justifyContent(FlexAlign.Center)
          .alignItems(HorizontalAlign.Center)
        }

        // 右下角时长标签
        Row() {
          Text(formatDuration(media.duration))
            .fontSize(11)
            .fontWeight(FontWeight.Medium)
            .fontColor(Color.White)
            .backgroundColor(this.T.colors.scrim)
            .padding({ left: 6, right: 6, top: 2, bottom: 2 })
            .borderRadius(4)
        }
        .width('100%')
        .height('100%')
        .alignItems(VerticalAlign.Bottom)
        .justifyContent(FlexAlign.End)
        .padding(8)
        // SET-104：角标层后于下载钮声明，默认会吃掉整颗气泡的点击，导致
        // 「清理缓存后点下载没反应」；纯装饰层必须让出命中测试。
        .hitTestBehavior(HitTestMode.None)
      }
    }
    .width(this.mediaCardWidth(media))
    .height(this.mediaCardHeight(media))
    .borderRadius(this.T.radius.md)
    .clip(true)
    .margin({ bottom: this.T.spacing.xs })
    .onClick(() => {
      if (isFailed || media.isUploading || media.isDownloading || !media.isDownloaded) {
        return;
      }
      this.onDispatch(new OpenMediaViewer(messageId));
    })
  }

  /** 回复引用区域（CHAT-004 / 对齐 Telegram X）：左侧细竖条 + 缩略图（34x34vp）+ 被回复者昵称与摘要 */
  @Builder
  ReplyReference(item: MessageItem) {
    Row() {
      // 左侧细条（宽 2vp，高 34vp，色值与被回复者同色）
      Column()
        .width(2)
        .height(item.replyThumbnailPath !== null ? 34 : 30)
        .backgroundColor(this.replyLineColor(item))
        .borderRadius(1)

      // 缩略图（贴纸 Contain，照片/视频 Cover，圆角 4vp）
      if (item.replyThumbnailPath !== null) {
        Image(toSandboxUri(item.replyThumbnailPath))
          .width(34)
          .height(34)
          .borderRadius(4)
          .objectFit(item.replyIsSticker ? ImageFit.Contain : ImageFit.Cover)
          .margin({ left: 6, right: 6 })
      }

      // 右侧文本列：首行发件人昵称，次行摘要文案
      Column() {
        Text(item.replySenderName.length > 0 ? item.replySenderName : 'Message')
          .fontSize(12)
          .fontWeight(FontWeight.Medium)
          .fontColor(this.replyLineColor(item))
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })

        Text(item.replyToSummary.length > 0 ? item.replyToSummary : 'Message')
          .fontSize(12)
          .fontColor(this.T.colors.textSecondary)
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
          .margin({ top: 2 })
      }
      .alignItems(HorizontalAlign.Start)
      .justifyContent(FlexAlign.Center)
      .margin(item.replyThumbnailPath !== null ? { left: 0 } : { left: 6 })
      .layoutWeight(1)
    }
    .alignSelf(ItemAlign.Start)
    .alignItems(VerticalAlign.Center)
    .margin({ bottom: this.T.spacing.xs })
    .onClick(() => {
      if (item.replyToMessageId !== null) {
        this.scrollToMessageId(item.replyToMessageId);
      }
    })
  }

  /** 链接预览卡片（MSG-107 / FEAT-COMP-002）：左侧 accent 竖条贯穿 + 站点/标题/描述 + 媒体自适应比例展示。 */
  @Builder
  LinkPreviewBubble(preview: LinkPreviewInfo) {
    Row() {
      // 1. 左侧 Telegram 风格细竖条（宽 3vp，accent 强调色，圆角 1.5vp，贯穿整个卡片包括大图/小图）
      Column()
        .width(3)
        .backgroundColor(this.T.colors.accent)
        .borderRadius(1.5)
        .alignSelf(ItemAlign.Stretch)

      // 2. 右侧主体内容区（站点名、标题、媒体大图、描述文本、媒体小图）
      Column() {
        // 站点名称（如 GitHub、Baidu）
        if (preview.siteName.length > 0) {
          Text(preview.siteName)
            .fontSize(12)
            .fontWeight(FontWeight.Bold)
            .fontColor(this.T.colors.accent)
            .maxLines(1)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
        }

        // 页面标题
        if (preview.title.length > 0) {
          Text(preview.title)
            .fontSize(14)
            .fontWeight(FontWeight.Bold)
            .fontColor(this.T.colors.chatText)
            .maxLines(2)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
            .margin({ top: preview.siteName.length > 0 ? 2 : 0 })
        }

        // 大图模式 - 若 showMediaAboveDescription 为 true，则大图放于描述上方
        if (preview.isLargeMedia && preview.showMediaAboveDescription && preview.thumbnailPath !== null) {
          Image(toSandboxUri(preview.thumbnailPath))
            .width('100%')
            .aspectRatio(preview.aspectRatio)
            .borderRadius(this.T.radius.sm)
            .clip(true)
            .objectFit(ImageFit.Cover)
            .constraintSize({ maxHeight: 220 })
            .margin({ top: 4, bottom: 4 })
        }

        // 描述区域
        if (preview.isLargeMedia) {
          // 大图模式：描述为单列文本
          if (preview.description.length > 0) {
            Text(preview.description)
              .fontSize(13)
              .fontColor(this.T.colors.textSecondary)
              .maxLines(3)
              .textOverflow({ overflow: TextOverflow.Ellipsis })
              .margin({ top: 2 })
          }

          // 大图模式 - 若 showMediaAboveDescription 为 false，则大图放于描述下方
          if (!preview.showMediaAboveDescription && preview.thumbnailPath !== null) {
            Image(toSandboxUri(preview.thumbnailPath))
              .width('100%')
              .aspectRatio(preview.aspectRatio)
              .borderRadius(this.T.radius.sm)
              .clip(true)
              .objectFit(ImageFit.Cover)
              .constraintSize({ maxHeight: 220 })
              .margin({ top: 4 })
          }
        } else {
          // 小图模式：描述文本在左，52x52 方形缩略图在右
          Row() {
            if (preview.description.length > 0) {
              Text(preview.description)
                .fontSize(13)
                .fontColor(this.T.colors.textSecondary)
                .maxLines(4)
                .textOverflow({ overflow: TextOverflow.Ellipsis })
                .layoutWeight(1)
            }

            if (preview.thumbnailPath !== null) {
              Image(toSandboxUri(preview.thumbnailPath))
                .width(52)
                .height(52)
                .borderRadius(this.T.radius.sm)
                .clip(true)
                .objectFit(ImageFit.Cover)
                .margin({ left: preview.description.length > 0 ? 6 : 0 })
            }
          }
          .width('100%')
          .alignItems(VerticalAlign.Center)
          .margin({ top: (preview.siteName.length > 0 || preview.title.length > 0) ? 2 : 0 })
        }
      }
      .alignItems(HorizontalAlign.Start)
      .layoutWeight(1)
      .margin({ left: 8 })
    }
    .alignSelf(ItemAlign.Start)
    .width('100%')
    .padding({
      left: 1,
      right: 2,
      top: 2,
      bottom: 2
    })
    .margin({ top: 6, bottom: 4 })
    .onClick(() => {
      if (preview.url.length > 0) {
        this.openLink(preview.url);
      }
    })
  }

  /** CHANNEL-101：消息反应 chips 横排/折行 */
  @Builder
  ReactionsRow(item: MessageItem) {
    Flex({ wrap: FlexWrap.Wrap }) {
      ForEach(item.reactionChips, (chip: ReactionChip) => {
        Row() {
          Text(chip.emoji)
            .fontSize(this.chatText(this.T.typography.footnote.fontSize, -4))
          Text(` ${chip.count}`)
            .fontSize(this.chatText(this.T.typography.caption.fontSize, -4))
            .fontWeight(FontWeight.Medium)
            .fontColor(chip.isChosen ? this.T.colors.textOnAccent : this.T.colors.textSecondary)
        }
        .padding({
          left: this.T.spacing.sm,
          right: this.T.spacing.sm,
          top: this.T.spacing.hairline,
          bottom: this.T.spacing.hairline
        })
        .height(26)
        .alignItems(VerticalAlign.Center)
        .backgroundColor(chip.isChosen ? this.T.colors.accent : this.T.colors.surfaceVariant)
        .borderRadius(this.T.radius.full)
        .margin({ right: this.T.spacing.xs, top: this.T.spacing.xs })
        .onClick(() => {
          this.onDispatch(new ToggleMessageReaction(item.messageId, chip.emoji));
        })
      }, (chip: ReactionChip) => `${chip.emoji}:${chip.count}:${chip.isChosen}`)
    }
    .margin({ top: this.T.spacing.xs })
  }

  /** CHANNEL-101：频道帖子评论入口行 */
  @Builder
  CommentsRow(item: MessageItem) {
    Row() {
      Image($r('app.media.ic_comments'))
        .width(16)
        .height(16)
        .fillColor(this.T.colors.accent)
        .margin({ right: this.T.spacing.xs })
      Text(`${item.commentCount} 条评论`)
        .fontSize(this.T.typography.footnote.fontSize)
        .fontWeight(FontWeight.Medium)
        .fontColor(this.T.colors.accent)
        .layoutWeight(1)
      Image($r('app.media.ic_chevron_right'))
        .width(14)
        .height(14)
        .fillColor(this.T.colors.accent)
    }
    .width('100%')
    .alignItems(VerticalAlign.Center)
    .padding({
      top: this.T.spacing.xs,
      bottom: this.T.spacing.hairline,
      left: this.T.spacing.hairline,
      right: this.T.spacing.hairline
    })
    .margin({ top: this.T.spacing.xs })
    .borderWidth({ top: 1 })
    .borderColor(this.T.colors.divider)
    .onClick(() => {
      this.onDispatch(new OpenMessageComments(item.messageId));
    })
  }

  /** 回复/编辑预览条（CHAT-004）：accent 竖条 + 标题/摘要 + 取消 X。 */
  @Builder
  ComposerModeBar(mode: ComposerMode) {
    Row() {
      Column()
        .width(3)
        .height(32)
        .backgroundColor(this.T.colors.accent)
        .borderRadius(this.T.radius.full)

      Column() {
        Text(mode.kind === 'edit' ? 'Edit Message' : `Reply to ${(mode as ComposerReplyMode).previewTitle}`)
          .fontSize(this.T.typography.subheadline.fontSize)
          .fontWeight(this.T.typography.headline.fontWeight)
          .fontColor(this.T.colors.accent)
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })

        Text(mode.previewText)
          .fontSize(this.T.typography.footnote.fontSize)
          .fontColor(this.T.colors.textSecondary)
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
      }
      .alignItems(HorizontalAlign.Start)
      .layoutWeight(1)
      .margin({ left: this.T.spacing.sm })

      Row() {
        Image($r('app.media.ic_close'))
          .width(18)
          .height(18)
          .fillColor(this.T.colors.textSecondary)
      }
      .width(32)
      .height(32)
      .justifyContent(FlexAlign.Center)
      .alignItems(VerticalAlign.Center)
      .onClick(() => {
        this.onDispatch(new CancelComposerMode());
      })
    }
    .width('100%')
    .alignItems(VerticalAlign.Center)
    .padding({
      left: this.T.spacing.screenInset,
      right: this.T.spacing.screenInset,
      top: this.T.spacing.xs,
      bottom: this.T.spacing.xs
    })
    .backgroundColor(this.T.colors.surfaceVariant)
  }

  /** 长按操作菜单（CHAT-004）：全屏遮罩 + 底部动作面板；可见项已由 reducer 按权限过滤。 */
  @Builder
  ActionMenuSheet(menu: MessageActionMenuState) {
    Stack() {
      Column()
        .width('100%')
        .height('100%')
        .backgroundColor(this.T.colors.scrim)
        .onClick(() => {
          this.onDispatch(new DismissMessageActionMenu());
        })

      Column() {
        // REACTION-101：快捷反应面板（对齐 Telegram X: 👍 ❤️ 🔥 🎉 👏 😂，已选反应带 accent 高亮环）
        Row() {
          ForEach(menu.availableReactions, (emoji: string) => {
            Column() {
              Text(emoji)
                .fontSize(22)
            }
            .width(42)
            .height(42)
            .justifyContent(FlexAlign.Center)
            .alignItems(HorizontalAlign.Center)
            .borderRadius(this.T.radius.full)
            .backgroundColor(menu.chosenReactions.indexOf(emoji) !== -1 ? this.T.colors.surface : this.T.colors.surfaceVariant)
            .border({
              width: menu.chosenReactions.indexOf(emoji) !== -1 ? 2 : 0,
              color: this.T.colors.accent
            })
            .onClick(() => {
              this.onDispatch(new ToggleMessageReaction(menu.messageId, emoji));
              this.onDispatch(new DismissMessageActionMenu());
            })
          }, (emoji: string) => `${emoji}:${menu.chosenReactions.indexOf(emoji) !== -1}`)
        }
        .width('100%')
        .justifyContent(FlexAlign.SpaceAround)
        .padding({
          left: this.T.spacing.screenInset,
          right: this.T.spacing.screenInset,
          top: this.T.spacing.md,
          bottom: this.T.spacing.sm
        })

        Divider()
          .color(this.T.colors.divider)
          .strokeWidth(0.5)
          .margin({ top: this.T.spacing.xs, bottom: this.T.spacing.xs })

        // FILE-103：失败消息展示 Resend 重发入口（对齐 Telegram X: Resend → Delete）
        if (menu.showResend) {
          Row() {
            Image($r('app.media.ic_send'))
              .width(22)
              .height(22)
              .fillColor(this.T.colors.accent)
              .margin({ right: this.T.spacing.md })
            Text('Resend')
              .fontSize(this.T.typography.body.fontSize)
              .fontWeight(FontWeight.Medium)
              .fontColor(this.T.colors.accent)
              .layoutWeight(1)
          }
          .width('100%')
          .alignItems(VerticalAlign.Center)
          .padding({
            left: this.T.spacing.screenInset,
            right: this.T.spacing.screenInset,
            top: this.T.spacing.md,
            bottom: this.T.spacing.md
          })
          .onClick(() => {
            this.onDispatch(new ResendFailedMessage(menu.messageId));
          })
        }

        if (menu.showReply) {
          Row() {
            Image($r('app.media.ic_reply'))
              .width(22)
              .height(22)
              .fillColor(this.T.colors.textPrimary)
              .margin({ right: this.T.spacing.md })
            Text('Reply')
              .fontSize(this.T.typography.body.fontSize)
              .fontColor(this.T.colors.textPrimary)
              .layoutWeight(1)
          }
          .width('100%')
          .alignItems(VerticalAlign.Center)
          .padding({
            left: this.T.spacing.screenInset,
            right: this.T.spacing.screenInset,
            top: this.T.spacing.md,
            bottom: this.T.spacing.md
          })
          .onClick(() => {
            this.onDispatch(new ReplyToMessage());
          })
        }

        // MSG-105：复制文本到系统剪贴板（对齐 Telegram X 菜单顺序：Reply → Copy → Copy Link → Forward → Edit → Delete）。
        if (menu.showCopy) {
          Row() {
            Image($r('app.media.ic_copy'))
              .width(22)
              .height(22)
              .fillColor(this.T.colors.textPrimary)
              .margin({ right: this.T.spacing.md })
            Text('Copy')
              .fontSize(this.T.typography.body.fontSize)
              .fontColor(this.T.colors.textPrimary)
              .layoutWeight(1)
          }
          .width('100%')
          .alignItems(VerticalAlign.Center)
          .padding({
            left: this.T.spacing.screenInset,
            right: this.T.spacing.screenInset,
            top: this.T.spacing.md,
            bottom: this.T.spacing.md
          })
          .onClick(() => {
            this.onDispatch(new CopyMessageText());
          })
        }

        // MSG-105：复制消息中的链接到系统剪贴板。
        if (menu.showCopyLink) {
          Row() {
            Image($r('app.media.ic_link'))
              .width(22)
              .height(22)
              .fillColor(this.T.colors.textPrimary)
              .margin({ right: this.T.spacing.md })
            Text('Copy Link')
              .fontSize(this.T.typography.body.fontSize)
              .fontColor(this.T.colors.textPrimary)
              .layoutWeight(1)
          }
          .width('100%')
          .alignItems(VerticalAlign.Center)
          .padding({
            left: this.T.spacing.screenInset,
            right: this.T.spacing.screenInset,
            top: this.T.spacing.md,
            bottom: this.T.spacing.md
          })
          .onClick(() => {
            this.onDispatch(new CopyMessageLink());
          })
        }

        // MSG-106：Forward 进入多选转发态（仅 can_be_forwarded 时出现）。
        if (menu.showForward) {
          Row() {
            Image($r('app.media.ic_forward'))
              .width(22)
              .height(22)
              .fillColor(this.T.colors.textPrimary)
              .margin({ right: this.T.spacing.md })
            Text('Forward')
              .fontSize(this.T.typography.body.fontSize)
              .fontColor(this.T.colors.textPrimary)
              .layoutWeight(1)
          }
          .width('100%')
          .alignItems(VerticalAlign.Center)
          .padding({
            left: this.T.spacing.screenInset,
            right: this.T.spacing.screenInset,
            top: this.T.spacing.md,
            bottom: this.T.spacing.md
          })
          .onClick(() => {
            this.onDispatch(new ForwardMessagesRequested());
          })
        }

        if (menu.showEdit) {
          Row() {
            Image($r('app.media.ic_edit'))
              .width(22)
              .height(22)
              .fillColor(this.T.colors.textPrimary)
              .margin({ right: this.T.spacing.md })
            Text('Edit')
              .fontSize(this.T.typography.body.fontSize)
              .fontColor(this.T.colors.textPrimary)
              .layoutWeight(1)
          }
          .width('100%')
          .alignItems(VerticalAlign.Center)
          .padding({
            left: this.T.spacing.screenInset,
            right: this.T.spacing.screenInset,
            top: this.T.spacing.md,
            bottom: this.T.spacing.md
          })
          .onClick(() => {
            this.onDispatch(new EditMessage());
          })
        }

        // MSG-108：Pin / Unpin 置顶与取消置顶操作
        if (menu.showPin) {
          Row() {
            Image($r('app.media.ic_pin'))
              .width(22)
              .height(22)
              .fillColor(this.T.colors.textPrimary)
              .margin({ right: this.T.spacing.md })
            Text(menu.isPinned ? 'Unpin' : 'Pin')
              .fontSize(this.T.typography.body.fontSize)
              .fontColor(this.T.colors.textPrimary)
              .layoutWeight(1)
          }
          .width('100%')
          .alignItems(VerticalAlign.Center)
          .padding({
            left: this.T.spacing.screenInset,
            right: this.T.spacing.screenInset,
            top: this.T.spacing.md,
            bottom: this.T.spacing.md
          })
          .onClick(() => {
            if (menu.isPinned) {
              this.onDispatch(new UnpinMessage());
            } else {
              this.onDispatch(new PinMessage());
            }
          })
        }

        if (menu.showDelete) {
          Row() {
            Image($r('app.media.ic_delete'))
              .width(22)
              .height(22)
              .fillColor(this.T.colors.destructive)
              .margin({ right: this.T.spacing.md })
            Text('Delete')
              .fontSize(this.T.typography.body.fontSize)
              .fontColor(this.T.colors.destructive)
              .layoutWeight(1)
          }
          .width('100%')
          .alignItems(VerticalAlign.Center)
          .padding({
            left: this.T.spacing.screenInset,
            right: this.T.spacing.screenInset,
            top: this.T.spacing.md,
            bottom: this.T.spacing.md
          })
          .onClick(() => {
            this.onDispatch(new DeleteMessage());
          })
        }
      }
      .width('100%')
      .backgroundColor(this.T.colors.surface)
      .borderRadius({ topLeft: this.T.radius.xl, topRight: this.T.radius.xl })
      .padding({ top: this.T.spacing.sm, bottom: this.T.spacing.lg })
    }
    .width('100%')
    .height('100%')
    .alignContent(Alignment.Bottom)
  }

  /** COMPOSER-102：附件选择面板（半透明遮罩 + 底部圆角抽屉）。 */
  @Builder
  AttachmentMenuSheet() {
    Stack() {
      // 1. 半透明全屏遮罩：点击关闭
      Column()
        .width('100%')
        .height('100%')
        .backgroundColor(this.T.colors.scrim)
        .onClick(() => {
          this.onDispatch(new CloseAttachmentMenu());
        })

      // 2. 底部抽屉面板
      Column() {
        // 顶部小手柄 indicator
        Row()
          .width(36)
          .height(4)
          .borderRadius(this.T.radius.full)
          .backgroundColor(this.T.colors.disabled)
          .margin({ top: this.T.spacing.sm, bottom: this.T.spacing.md })

        // 标题行
        Row() {
          Text('Attach')
            .fontSize(this.T.typography.title.fontSize)
            .fontWeight(this.T.typography.title.fontWeight)
            .fontColor(this.T.colors.textPrimary)
        }
        .width('100%')
        .padding({
          left: this.T.spacing.screenInset,
          right: this.T.spacing.screenInset,
          bottom: this.T.spacing.md
        })

        // 附件选项网格：各项可用性由 chat.permissions 的各位驱动（CHAN-SEND-2）。
        // 不可用的条目保持可见但置灰，点击时出限制提示 —— 对齐 Android：入口不藏起来，
        // 点了再由 Tdlib.showRestriction 说明为什么不行（MessagesController.java:10324）。
        Row() {
          ForEach(this.attachmentEntries(), (entry: AttachmentEntry) => {
            Column() {
              Column() {
                Image(this.attachmentIcon(entry.key))
                  .width(28)
                  .height(28)
                  .fillColor(entry.enabled ? this.T.colors.accent : this.T.colors.disabled)
              }
              .width(56)
              .height(56)
              .borderRadius(this.T.radius.full)
              .backgroundColor(this.T.colors.surfaceVariant)
              .justifyContent(FlexAlign.Center)
              .alignItems(HorizontalAlign.Center)
              .margin({ bottom: this.T.spacing.xs })

              Text(this.attachmentLabel(entry.key))
                .fontSize(this.T.typography.footnote.fontSize)
                .fontColor(entry.enabled ? this.T.colors.textPrimary : this.T.colors.textSecondary)
            }
            .alignItems(HorizontalAlign.Center)
            .opacity(entry.enabled ? 1 : 0.45)
            .margin({ right: this.T.spacing.xl })
            .onClick(() => {
              this.onAttachmentTap(entry);
            })
          }, (entry: AttachmentEntry): string => `${entry.key}:${entry.enabled}`)
        }
        .width('100%')
        .padding({
          left: this.T.spacing.screenInset,
          right: this.T.spacing.screenInset,
          top: this.T.spacing.sm,
          bottom: this.T.spacing.xl
        })
      }
      .width('100%')
      .backgroundColor(this.T.colors.surface)
      .borderRadius({
        topLeft: this.T.radius.xl,
        topRight: this.T.radius.xl
      })
      .padding({ bottom: this.T.spacing.screenInset })
    }
    .width('100%')
    .height('100%')
    .alignContent(Alignment.Bottom)
  }

  // ---- CHAN-SEND-2：附件面板与录音入口的权限驱动 ----

  /** 面板条目及其可用性（纯函数在 core/domain，便于单测覆盖九位组合）。 */
  private attachmentEntries(): AttachmentEntry[] {
    return buildAttachmentEntries(this.uiState.sendRights);
  }

  private attachmentIcon(key: string): Resource {
    if (key === ATTACHMENT_GALLERY) {
      return $r('app.media.ic_photo');
    }
    if (key === ATTACHMENT_VIDEO) {
      return $r('app.media.ic_video');
    }
    if (key === ATTACHMENT_FILE) {
      return $r('app.media.ic_file');
    }
    return $r('app.media.ic_poll');
  }

  private attachmentLabel(key: string): string {
    if (key === ATTACHMENT_GALLERY) {
      return 'Gallery';
    }
    if (key === ATTACHMENT_VIDEO) {
      return 'Video';
    }
    if (key === ATTACHMENT_FILE) {
      return 'File';
    }
    return 'Poll';
  }

  /** 受限点击的统一提示：拿不到 UIContext 时静默（不因为提示失败而打断交互）。 */
  private showHintToast(message: string): void {
    try {
      this.getUIContext().getPromptAction().showToast({ message: message, duration: 2000 });
    } catch (toastErr) {
    }
  }

  /** 受限条目不静默失效：出提示说明为什么点不动，可用条目才分发选择动作。 */
  private onAttachmentTap(entry: AttachmentEntry): void {
    const hint: string = attachmentRestrictionLabel(entry);
    if (hint.length > 0) {
      this.showHintToast(hint);
      return;
    }
    if (entry.key === ATTACHMENT_GALLERY) {
      this.onDispatch(new PickAndSendPhoto());
    } else if (entry.key === ATTACHMENT_VIDEO) {
      this.onDispatch(new PickAndSendVideo());
    } else if (entry.key === ATTACHMENT_FILE) {
      this.onDispatch(new PickAndSendFile());
    } else {
      this.onDispatch(new OpenPollComposer());
    }
  }

  /** 九位媒体权限全被禁时，附件入口本身没有意义（对齐 Android canSendSendSomeMedia）。 */
  private showAttachButton(): boolean {
    return canSendAnyMedia(this.uiState.sendRights);
  }

  /**
   * CHAN-SEND-3：贴纸 / GIF 的**发送时**否决。Android 的表情面板从不限贴纸/GIF 页签
   * （`EmojiLayout.java` 里零 `RightId` 引用），否决发生在选中要发出去那一张时
   * （`MessagesController.java:9230` sendSticker、`:9238` sendAnimation → `showRestriction`），
   * 所以这里照原样：页签照常可点，否决只出句子、不发东西。
   */
  private sendContentWithVeto(contentKey: string, fileId: number, send: () => void): void {
    if (contentKey === CONTENT_STICKER && isUnicodeEmojiSticker(fileId)) {
      // 内置「unicode 表情贴纸」由 coordinator 走 sendTextMessage，那是文本、受 basic 位管，
      // 不能因为会话禁贴纸就把表情也扣下。
      send();
      return;
    }
    const hint: string = sendVetoLabel(this.uiState.sendRights, contentKey);
    if (hint.length > 0) {
      this.showHintToast(hint);
      return;
    }
    send();
  }

  /** 无输入文本时的麦克风按钮是否被权限挡住；挡住时点击出提示而不是开始录音。 */
  private canRecordVoiceNow(): boolean {
    return canRecordVoice(this.uiState.sendRights);
  }

  /** POLL-101：投票卡片的底部统计文案。 */
  private pollFooterText(poll: PollView): string {
    const parts: string[] = [`${poll.totalVoterCount} vote${poll.totalVoterCount === 1 ? '' : 's'}`];
    if (poll.isAnonymous) {
      parts.push('Anonymous poll');
    }
    if (poll.allowsMultipleAnswers) {
      parts.push('Multiple answers');
    }
    if (poll.isClosed) {
      parts.push('Finished');
    }
    return parts.join(' · ');
  }

  /**
   * POLL-101：投票卡片气泡。题目 + 选项行（选中高亮/计数/百分比/进度条）+ 统计脚注。
   * 点选项分发 VotePollOption（reducer 乐观翻转选中态并出 setPollAnswer），
   * 权威计数与百分比由 TDLib updateMessageContent 回灌覆盖。
   */
  @Builder
  PollBubble(messageId: number, poll: PollView) {
    Column() {
      Text(poll.question)
        .fontSize(this.chatText(this.T.typography.body.fontSize))
        .fontWeight(FontWeight.Medium)
        .fontColor(this.T.colors.chatText)
        .width('100%')
        .margin({ bottom: this.T.spacing.sm })

      ForEach(poll.options, (option: PollOptionView) => {
        Column() {
          Row() {
            if (poll.showResults) {
              Image(option.isChosen ? $r('app.media.ic_check_single') : $r('app.media.ic_radio_empty'))
                .width(18)
                .height(18)
                .fillColor(option.isChosen ? this.T.colors.accent : this.T.colors.textSecondary)
                .margin({ right: this.T.spacing.sm })
            }
            Text(option.text)
              .fontSize(this.chatText(this.T.typography.body.fontSize))
              .fontColor(option.isChosen ? this.T.colors.accent : this.T.colors.chatText)
              .maxLines(2)
              .textOverflow({ overflow: TextOverflow.Ellipsis })
              .layoutWeight(1)
            if (poll.showResults) {
              Text(`${option.voterCount}`)
                .fontSize(this.chatText(this.T.typography.footnote.fontSize))
                .fontColor(option.isChosen ? this.T.colors.accent : this.T.colors.textSecondary)
                .width(28)
                .textAlign(TextAlign.End)
              Text(`${option.votePercentage}%`)
                .fontSize(this.chatText(this.T.typography.footnote.fontSize))
                .fontColor(option.isChosen ? this.T.colors.accent : this.T.colors.textSecondary)
                .margin({ left: this.T.spacing.xs })
            }
          }
          .width('100%')

          if (poll.showResults) {
            Stack({ alignContent: Alignment.Start }) {
              Row()
                .width('100%')
                .height(3)
                .borderRadius(this.T.radius.full)
                .backgroundColor(this.T.colors.divider)
              Row()
                .width(`${Math.max(2, Math.min(100, option.votePercentage))}%`)
                .height(3)
                .borderRadius(this.T.radius.full)
                .backgroundColor(option.isChosen ? this.T.colors.accent : this.T.colors.textSecondary)
            }
            .width('100%')
            .margin({ top: this.T.spacing.xs })
          }
        }
        .width('100%')
        .alignItems(HorizontalAlign.Start)
        .padding({ top: this.T.spacing.xs, bottom: this.T.spacing.xs })
        .onClick(() => {
          if (!poll.isClosed) {
            this.onDispatch(new VotePollOption(messageId, option.index));
          }
        })
      }, (option: PollOptionView): string =>
        `${messageId}:${option.index}:${option.isChosen}:${option.voterCount}:${option.votePercentage}:${poll.showResults}`)

      Row() {
        Image($r('app.media.ic_poll'))
          .width(14)
          .height(14)
          .fillColor(this.T.colors.textSecondary)
          .margin({ right: this.T.spacing.xs })
        Text(this.pollFooterText(poll))
          .fontSize(this.chatText(this.T.typography.footnote.fontSize))
          .fontColor(this.T.colors.textSecondary)
      }
      .width('100%')
      .margin({ top: this.T.spacing.sm })
    }
    .width(BUBBLE_MAX_WIDTH)
    .constraintSize({ maxWidth: 360 })
    .alignItems(HorizontalAlign.Start)
    .padding({ top: this.T.spacing.xs, bottom: this.T.spacing.xs })
  }

  /**
   * POLL-101：发起投票面板（受控：全部编辑动作走 reducer 的 pollComposer 态）。
   * 问题 + 2..10 选项 + 匿名/多选开关；Create 仅在 isValid() 时可用。
   * 结构对齐 AttachmentMenuSheet（scrim 遮罩 + 底部抽屉）。
   */
  @Builder
  PollComposerSheet() {
    Stack() {
      Column()
        .width('100%')
        .height('100%')
        .backgroundColor(this.T.colors.scrim)
        .onClick(() => {
          this.onDispatch(new ClosePollComposer());
        })

      // 键盘会压缩窗口高度：面板铺满可用区域，编辑区用 layoutWeight(1) 拿到确定高度后才可滚动，
      // 否则 Create 会被压缩/顶到键盘背后无法点击。
      Column() {
        Row() {
          Text('Create Poll')
            .fontSize(this.T.typography.title.fontSize)
            .fontWeight(this.T.typography.title.fontWeight)
            .fontColor(this.T.colors.textPrimary)
            .layoutWeight(1)
          Text('Cancel')
            .fontSize(this.T.typography.subheadline.fontSize)
            .fontColor(this.T.colors.accent)
            .onClick(() => {
              this.onDispatch(new ClosePollComposer());
            })
        }
        .width('100%')
        .flexShrink(0)
        .padding({
          left: this.T.spacing.screenInset,
          right: this.T.spacing.screenInset,
          top: this.T.spacing.xl,
          bottom: this.T.spacing.md
        })

        Scroll() {
          Column() {
            // 问题输入
            Column() {
              TextInput({
                text: this.pollDraft.question,
                placeholder: 'Question'
              })
                .fontSize(this.T.typography.body.fontSize)
                .fontColor(this.T.colors.textPrimary)
                .placeholderColor(this.T.colors.textSecondary)
                .backgroundColor(Color.Transparent)
                .width('100%')
                .maxLength(POLL_QUESTION_MAX_LENGTH)
                .onChange((value: string) => {
                  this.onDispatch(new PollQuestionChanged(value));
                })
            }
            .width('100%')
            .padding({ left: this.T.spacing.md, right: this.T.spacing.md })
            .backgroundColor(this.T.colors.surfaceVariant)
            .borderRadius(this.T.radius.md)
            .margin({
              left: this.T.spacing.screenInset,
              right: this.T.spacing.screenInset,
              bottom: this.T.spacing.sm
            })

            // 选项输入行
            Column() {
              ForEach(this.pollDraft.options, (optionText: string, index: number) => {
                Row() {
                  Text(`${index + 1}`)
                    .fontSize(this.T.typography.footnote.fontSize)
                    .fontColor(this.T.colors.textSecondary)
                    .width(20)
                  TextInput({
                    text: optionText,
                    placeholder: `Option ${index + 1}`
                  })
                    .fontSize(this.T.typography.body.fontSize)
                    .fontColor(this.T.colors.textPrimary)
                    .placeholderColor(this.T.colors.textSecondary)
                    .backgroundColor(Color.Transparent)
                    .layoutWeight(1)
                    .maxLength(POLL_OPTION_MAX_LENGTH)
                    .onChange((value: string) => {
                      this.onDispatch(new PollOptionTextChanged(index, value));
                    })
                  if (this.pollDraft.options.length > POLL_MIN_OPTIONS) {
                    Image($r('app.media.ic_close'))
                      .width(18)
                      .height(18)
                      .fillColor(this.T.colors.textSecondary)
                      .onClick(() => {
                        this.onDispatch(new RemovePollComposerOption(index));
                      })
                  }
                }
                .width('100%')
                .height(44)
                .padding({ left: this.T.spacing.md, right: this.T.spacing.md })
                .margin({ bottom: this.T.spacing.xs })
                .backgroundColor(this.T.colors.surfaceVariant)
                .borderRadius(this.T.radius.md)
              }, (optionText: string, index: number): string => {
                // 键里带选项数：增删后整组重建（键不变则 ForEach 不刷新，行内会留旧文本）；
                // 单纯击键不改长度，避免输入框被重建而丢焦点。
                return `${this.pollDraft.options.length}:${index}`;
              })

              if (this.pollDraft.options.length < POLL_MAX_OPTIONS) {
                Row() {
                  Text('＋ Add Option')
                    .fontSize(this.T.typography.subheadline.fontSize)
                    .fontColor(this.T.colors.accent)
                }
                .width('100%')
                .height(40)
                .justifyContent(FlexAlign.Center)
                .onClick(() => {
                  this.onDispatch(new AddPollComposerOption());
                })
              }
            }
            .width('100%')
            .padding({
              left: this.T.spacing.screenInset,
              right: this.T.spacing.screenInset
            })

            // 设置行：匿名 / 多选（点击整行切换；Toggle 仅呈现，不吃事件避免双触发）
            Row() {
              Text('Anonymous Poll')
                .fontSize(this.T.typography.body.fontSize)
                .fontColor(this.T.colors.textPrimary)
                .layoutWeight(1)
              Toggle({ type: ToggleType.Switch, isOn: this.pollDraft.isAnonymous })
                .selectedColor(this.T.colors.accent)
                .hitTestBehavior(HitTestMode.None)
            }
            .width('100%')
            .height(48)
            .padding({
              left: this.T.spacing.screenInset,
              right: this.T.spacing.screenInset
            })
            .onClick(() => {
              this.onDispatch(new TogglePollComposerAnonymous());
            })

            Row() {
              Text('Multiple Answers')
                .fontSize(this.T.typography.body.fontSize)
                .fontColor(this.T.colors.textPrimary)
                .layoutWeight(1)
              Toggle({ type: ToggleType.Switch, isOn: this.pollDraft.allowsMultiple })
                .selectedColor(this.T.colors.accent)
                .hitTestBehavior(HitTestMode.None)
            }
            .width('100%')
            .height(48)
            .padding({
              left: this.T.spacing.screenInset,
              right: this.T.spacing.screenInset
            })
            .onClick(() => {
              this.onDispatch(new TogglePollComposerMultiple());
            })

            // 提交
            Column() {
              Text(this.pollDraft.isValid() ? 'Create' : 'Add a question and 2 options')
                .fontSize(this.T.typography.subheadline.fontSize)
                .fontWeight(FontWeight.Medium)
                .fontColor(this.pollDraft.isValid() ? this.T.colors.textOnAccent : this.T.colors.textSecondary)
                .width('100%')
                .height(44)
                .borderRadius(this.T.radius.full)
                .backgroundColor(this.pollDraft.isValid() ? this.T.colors.accent : this.T.colors.surfaceVariant)
                .textAlign(TextAlign.Center)
                .onClick(() => {
                  this.onDispatch(new SubmitPollComposer());
                })
            }
            .width('100%')
            .padding({
              left: this.T.spacing.screenInset,
              right: this.T.spacing.screenInset,
              top: this.T.spacing.sm,
              bottom: this.T.spacing.xl
            })
          }
          .width('100%')
        }
        .width('100%')
        .layoutWeight(1)
        .scrollBar(BarState.Auto)
        .align(Alignment.Top)
      }
      .width('100%')
      .height('100%')
      .backgroundColor(this.T.colors.surface)
      .padding({ bottom: this.T.spacing.screenInset })
    }
    .width('100%')
    .height('100%')
    .alignContent(Alignment.Bottom)
  }

  /** MEDIA-VIEWER-101：缩放与位移一起归零（翻页、关闭查看器都走这里）。 */
  private resetViewerTransform(): void {
    this.viewerScale = 1.0;
    this.viewerOffsetX = 0;
    this.viewerOffsetY = 0;
    this.pinchStartScale = 1.0;
  }

  private activeViewerItem(): MediaViewerItem | null {
    const index: number = this.uiState.activeViewerIndex;
    if (index < 0 || index >= this.uiState.viewerItems.length) {
      return null;
    }
    return this.uiState.viewerItems[index];
  }

  /**
   * 此刻真正画在屏幕上的图源（沙箱 uri）。
   *
   * 最大档已落盘就用最大档，否则退回显示档 —— 气泡只吃 320~960px，放大到 1:1
   * 必然糊；查看器等大图到了再换。没有可渲染的本地文件时返回 ''，由分支画缩略图/占位。
   */
  private viewerRenderSrc(item: MediaViewerItem): string {
    const full: MediaFullSource | null = item.media.fullSource;
    if (full !== null && full.isDownloaded && full.localPath !== null) {
      return toSandboxUri(full.localPath);
    }
    if (item.media.isDownloaded && item.media.localPath !== null) {
      return toSandboxUri(item.media.localPath);
    }
    return '';
  }

  /** 当前渲染档的真实像素宽（缩放上限按它算，不按显示档蒙）。 */
  private viewerRenderedWidth(item: MediaViewerItem): number {
    const full: MediaFullSource | null = item.media.fullSource;
    if (item.media.kind !== 'photo' || full === null || !full.isDownloaded) {
      return item.media.width;
    }
    return full.width;
  }

  private viewerRenderedHeight(item: MediaViewerItem): number {
    const full: MediaFullSource | null = item.media.fullSource;
    if (item.media.kind !== 'photo' || full === null || !full.isDownloaded) {
      return item.media.height;
    }
    return full.height;
  }

  /** 贴合态（scale=1）下内容在视口内的矩形，vp。 */
  private viewerContentRectOf(item: MediaViewerItem): ViewerRect {
    return viewerContentRect(
      this.viewerRenderedWidth(item),
      this.viewerRenderedHeight(item),
      this.viewerViewportW,
      this.viewerViewportH
    );
  }

  private viewerNativeScaleOf(item: MediaViewerItem): number {
    return viewerNativeScale(
      this.viewerRenderedWidth(item),
      this.viewerContentRectOf(item).width,
      this.densityPxPerVp
    );
  }

  /** 缩放上限 = 1:1 像素再乘余量；尺寸或视口还没测到时内部退回固定值。 */
  private viewerMaxScaleOf(item: MediaViewerItem): number {
    return viewerMaxScale(
      this.viewerRenderedWidth(item),
      this.viewerContentRectOf(item).width,
      this.densityPxPerVp
    );
  }

  /** 位移写入前一律夹紧（PAN_LIMIT_INSIDE）：内容比视口小的那一轴只能居中。 */
  private setViewerOffset(offsetX: number, offsetY: number): void {
    const item: MediaViewerItem | null = this.activeViewerItem();
    if (item === null || this.viewerViewportW <= 0 || this.viewerViewportH <= 0) {
      this.viewerOffsetX = 0;
      this.viewerOffsetY = 0;
      return;
    }
    const clamped: ViewerOffset = clampViewerOffset(
      offsetX,
      offsetY,
      this.viewerScale,
      this.viewerContentRectOf(item),
      this.viewerViewportW,
      this.viewerViewportH
    );
    this.viewerOffsetX = clamped.x;
    this.viewerOffsetY = clamped.y;
  }

  /** 双击：贴合 ↔ 1:1 像素两档切换，锚在手指点上（TGX 的双击语义）。 */
  private toggleViewerZoom(event: GestureEvent): void {
    const item: MediaViewerItem | null = this.activeViewerItem();
    if (item === null) {
      return;
    }
    const focal: ViewerOffset = this.viewerFocal(event);
    if (this.viewerScale > 1.05) {
      this.zoomViewerTo(1.0, focal.x, focal.y);
      return;
    }
    this.zoomViewerTo(
      viewerDoubleTapScale(this.viewerMaxScaleOf(item), this.viewerNativeScaleOf(item)),
      focal.x,
      focal.y
    );
  }

  /** 换倍率时保持焦点不动：把 `(focalX, focalY)` 那个内容点钉在原处。 */
  private zoomViewerTo(nextScale: number, focalX: number, focalY: number): void {
    const item: MediaViewerItem | null = this.activeViewerItem();
    if (item === null || !viewerZoomable(item.media.kind)) {
      // 只有照片放大；视频页的倍率永远停在 1（缩放上限是按像素算的，视频不适用）。
      return;
    }
    const clampedScale: number = clampViewerScale(nextScale, this.viewerMaxScaleOf(item));
    if (clampedScale <= 1.0) {
      this.resetViewerTransform();
      return;
    }
    const moved: ViewerOffset = viewerOffsetForZoom(
      focalX,
      focalY,
      this.viewerOffsetX,
      this.viewerOffsetY,
      this.viewerScale,
      clampedScale
    );
    this.viewerScale = clampedScale;
    this.setViewerOffset(moved.x, moved.y);
  }

  /** 触点（多指取中点）相对视口中心的坐标，vp；取不到手指时按视口中心。 */
  private viewerFocal(event: GestureEvent): ViewerOffset {
    if (event.fingerList.length === 0 || this.viewerViewportW <= 0 || this.viewerViewportH <= 0) {
      return { x: 0, y: 0 };
    }
    let sumX: number = 0;
    let sumY: number = 0;
    for (let i = 0; i < event.fingerList.length; i++) {
      sumX += event.fingerList[i].localX;
      sumY += event.fingerList[i].localY;
    }
    return {
      x: sumX / event.fingerList.length - this.viewerViewportW / 2,
      y: sumY / event.fingerList.length - this.viewerViewportH / 2
    };
  }

  /**
   * 这一页的动态内容该画什么（'player' / 'gif' / 'poster' / 'download'）。
   * 「是不是当前页」在这里合成，纯判定全在 model/ViewerPlayback.ets。
   */
  private viewerPageRender(item: MediaViewerItem, index: number): ViewerMotionRender {
    return viewerMotionRender(item.media, viewerRendersPlayer(index, this.uiState.activeViewerIndex));
  }

  /** 缩放与拖拽只开放给照片页：视频页由播放器自己的控制条接管。 */
  private viewerActiveZoomable(): boolean {
    const item: MediaViewerItem | null = this.activeViewerItem();
    return item !== null && viewerZoomable(item.media.kind);
  }

  /** 全屏多媒体画廊查看器（MEDIA-103 / FEAT-MEDIA-006）。 */
  @Builder
  MediaViewerOverlay() {
    Stack({ alignContent: Alignment.Center }) {
      // 1. 底层：多图 Swiper 翻页与手势缩放
      Swiper(this.swiperController) {
        ForEach(this.uiState.viewerItems, (item: MediaViewerItem, index: number) => {
          Stack({ alignContent: Alignment.Center }) {
            if (item.media.kind === 'video' || item.media.kind === 'animation') {
              // MEDIA-VIEWER-102：动态内容按档位画。'player' 只给当前页 —— Swiper 会缓存
              // 相邻页，缓存着的 `autoPlay(true)` 视频会一起开播，于是好几条音轨同时响。
              if (this.viewerPageRender(item, index) === 'gif') {
                // GIF 容器交给 Image 原生逐帧播放：不起播放器、天然无声循环。
                Image(toSandboxUri(item.media.localPath))
                  .objectFit(ImageFit.Contain)
                  .width('100%')
                  .height('100%')
              } else if (this.viewerPageRender(item, index) === 'player') {
                if (item.media.kind === 'video') {
                  Video({
                    src: toSandboxUri(item.media.localPath),
                    previewUri: toSandboxUri(item.media.thumbnailPath)
                  })
                    .autoPlay(true)
                    .loop(false)
                    .controls(true)
                    .muted(false)
                    .objectFit(ImageFit.Contain)
                    .width('100%')
                    .height('100%')
                } else {
                  // 动图（TDLib 已转码的 mp4）：无声循环、不给控制条，和气泡里同一套语义。
                  Video({
                    src: toSandboxUri(item.media.localPath),
                    previewUri: toSandboxUri(item.media.thumbnailPath)
                  })
                    .autoPlay(true)
                    .loop(true)
                    .controls(false)
                    .muted(true)
                    .objectFit(ImageFit.Contain)
                    .width('100%')
                    .height('100%')
                }
              } else if (this.viewerPageRender(item, index) === 'download') {
                Stack({ alignContent: Alignment.Center }) {
                  if (item.media.thumbnailPath !== null) {
                    Image(toSandboxUri(item.media.thumbnailPath))
                      .objectFit(ImageFit.Contain)
                      .width('100%')
                      .height('100%')
                  }
                  Column() {
                    if (item.media.isDownloading) {
                      LoadingProgress()
                        .width(44)
                        .height(44)
                        .color(Color.White)
                      Text(`${Math.round(item.media.progress * 100)}%`)
                        .fontSize(12)
                        .fontColor(Color.White)
                        .margin({ top: 6 })
                    } else {
                      Image($r('app.media.ic_download'))
                        .width(26)
                        .height(26)
                        .fillColor(Color.White)
                      Text(item.media.kind === 'video' ? 'Download Video' : 'Download GIF')
                        .fontSize(12)
                        .fontColor(Color.White)
                        .margin({ top: 6 })
                    }
                  }
                  .padding(16)
                  .borderRadius(16)
                  .backgroundColor(this.T.colors.scrim)
                  .onClick(() => {
                    this.onDispatch(new RequestMediaDownload(item.media.fileId));
                  })
                }
                .width('100%')
                .height('100%')
              } else if (item.media.thumbnailPath !== null) {
                // 'poster'：Swiper 缓存的相邻页只画封面，翻页动画期间不会出现第二个播放器。
                Image(toSandboxUri(item.media.thumbnailPath))
                  .objectFit(ImageFit.Contain)
                  .width('100%')
                  .height('100%')
              }
            } else if (this.viewerRenderSrc(item).length > 0) {
              // MEDIA-VIEWER-101：优先画最大档，大图还在路上时先画显示档。
              Image(this.viewerRenderSrc(item))
                .objectFit(ImageFit.Contain)
                .width('100%')
                .height('100%')
            } else if (item.media.thumbnailPath !== null) {
              Stack({ alignContent: Alignment.Center }) {
                Image(toSandboxUri(item.media.thumbnailPath))
                  .objectFit(ImageFit.Contain)
                  .width('100%')
                  .height('100%')
                  .blur(8)

                Column() {
                  LoadingProgress()
                    .width(44)
                    .height(44)
                    .color(Color.White)
                }
                .width(56)
                .height(56)
                .borderRadius(this.T.radius.full)
                .backgroundColor(this.T.colors.scrim)
                .justifyContent(FlexAlign.Center)
                .alignItems(HorizontalAlign.Center)
              }
              .width('100%')
              .height('100%')
            } else {
              Column() {
                LoadingProgress()
                  .width(48)
                  .height(48)
                  .color(Color.White)
              }
              .width('100%')
              .height('100%')
              .justifyContent(FlexAlign.Center)
              .alignItems(HorizontalAlign.Center)
            }
          }
          .width('100%')
          .height('100%')
          // MEDIA-VIEWER-101：缩放与位移只挂在这一层。挂在各子节点上时
          // translate 会按各自的中心各算一遍，拖起来就对不上手指。
          .scale({ x: this.viewerScale, y: this.viewerScale })
          .translate({ x: this.viewerOffsetX, y: this.viewerOffsetY })
        }, (item: MediaViewerItem, index: number): string => {
          // MEDIA-VIEWER-102：「是不是当前页」要进键 —— 翻页时 item 内容没变，键不变就
          // 不会重渲，刚离开那一页的 Video 节点会一直活着继续出声。
          return mediaViewerItemKey(item, viewerRendersPlayer(index, this.uiState.activeViewerIndex));
        })
      }
      .index(this.uiState.activeViewerIndex)
      .onChange((index: number) => {
        if (index !== this.uiState.activeViewerIndex) {
          this.onDispatch(new ChangeViewerIndex(index));
          this.resetViewerTransform();
        }
      })
      .disableSwipe(this.viewerScale > 1.05)
      .indicator(false)
      .loop(false)
      .width('100%')
      .height('100%')
      .onAreaChange((_oldValue: Area, newValue: Area) => {
        this.viewerViewportW = Number(newValue.width);
        this.viewerViewportH = Number(newValue.height);
      })
      .priorityGesture(
        GestureGroup(
          GestureMode.Parallel,
          PinchGesture({ fingers: 2 })
            .onActionStart((event: GestureEvent) => {
              this.pinchStartScale = this.viewerScale;
              this.pinchStartOffsetX = this.viewerOffsetX;
              this.pinchStartOffsetY = this.viewerOffsetY;
              const focal: ViewerOffset = this.viewerFocal(event);
              this.pinchFocalX = focal.x;
              this.pinchFocalY = focal.y;
            })
            .onActionUpdate((event: GestureEvent) => {
              const item: MediaViewerItem | null = this.activeViewerItem();
              if (item === null) {
                return;
              }
              const nextScale: number = clampViewerScale(
                this.pinchStartScale * event.scale,
                this.viewerMaxScaleOf(item)
              );
              if (nextScale <= 1.0) {
                this.resetViewerTransform();
                return;
              }
              const moved: ViewerOffset = viewerOffsetForZoom(
                this.pinchFocalX,
                this.pinchFocalY,
                this.pinchStartOffsetX,
                this.pinchStartOffsetY,
                this.pinchStartScale,
                nextScale
              );
              this.viewerScale = nextScale;
              this.setViewerOffset(moved.x, moved.y);
            })
            .onActionEnd(() => {
              if (this.viewerScale <= 1.0) {
                this.resetViewerTransform();
              }
            }),
          // 放大后才接管拖拽；未放大时让位给 Swiper 的横滑翻页。
          PanGesture({ fingers: 1, distance: 8 })
            .onActionStart(() => {
              this.panStartOffsetX = this.viewerOffsetX;
              this.panStartOffsetY = this.viewerOffsetY;
            })
            .onActionUpdate((event: GestureEvent) => {
              if (this.viewerScale <= 1.05) {
                return;
              }
              this.setViewerOffset(
                this.panStartOffsetX + event.offsetX,
                this.panStartOffsetY + event.offsetY
              );
            })
        )
      )
      // MEDIA-VIEWER-102：点击必须走 `.gesture` 而不是跟着上面那条 `priorityGesture`。
      // priorityGesture 连**子节点**的识别器一起压，Video 自带的播放/进度条于是永远点不到
      // （设备实测：点播放键只翻了工具栏），'download' 档的下载按钮同理。
      // 普通 `.gesture` 是祖先识别器，子节点（Video 控制条、下载按钮）优先命中。
      .gesture(
        GestureGroup(
          GestureMode.Exclusive,
          TapGesture({ count: 2 })
            .onAction((event: GestureEvent) => {
              this.toggleViewerZoom(event);
            }),
          TapGesture({ count: 1 })
            .onAction(() => {
              this.viewerBarsVisible = !this.viewerBarsVisible;
            })
        )
      )
      // 未放大时把**我们自己那条**拖拽判掉，否则 priorityGesture 会抢走 Swiper 的横滑翻页。
      // 判据必须带 `!isSystemGesture`：Swiper 内置的滑动同样是 PAN_GESTURE（只是 isSystemGesture
      // 为 true），一起判掉就等于把翻页也判死了 —— 设备实测踩过。
      // 视频 / 动图页（MEDIA-VIEWER-102）连捏合一起判掉：那两页不缩放，手势要留给播放器自己的控制条。
      .onGestureJudgeBegin((info: GestureInfo, _event: BaseGestureEvent) => {
        if (!info.isSystemGesture) {
          const zoomable: boolean = this.viewerActiveZoomable();
          if (info.type === GestureControl.GestureType.PAN_GESTURE &&
            (this.viewerScale <= 1.05 || !zoomable)) {
            return GestureJudgeResult.REJECT;
          }
          if (info.type === GestureControl.GestureType.PINCH_GESTURE && !zoomable) {
            return GestureJudgeResult.REJECT;
          }
        }
        return GestureJudgeResult.CONTINUE;
      })

      // 2. 顶部工具栏与底部附言栏（两端对齐浮层）
      if (this.viewerBarsVisible) {
        Column() {
          this.ViewerTopBar()

          Blank()

          if (this.getViewerCaption().length > 0) {
            this.ViewerBottomBar()
          }
        }
        .width('100%')
        .height('100%')
        .justifyContent(FlexAlign.SpaceBetween)
        .hitTestBehavior(HitTestMode.Transparent)
      }
    }
    .width('100%')
    .height('100%')
    .backgroundColor(Color.Black)
    // MEDIA-VIEWER-101：这里必须是 Default 而不是 Block。
    // `HitTestMode.Block` 按 SDK 定义连**子节点**一起挡掉（"blocks the hit test of
    // child nodes, sibling nodes, and ancestor nodes"），整个查看器于是点不动、
    // 捏不动、翻页也不动 —— 只剩系统 Back 能退出。Default 已经足够挡住下层的聊天页。
    .hitTestBehavior(HitTestMode.Default)
  }

  @Builder
  ViewerTopBar() {
    Row() {
      Row() {
        Image($r('app.media.ic_back'))
          .width(24)
          .height(24)
          .fillColor(Color.White)
      }
      .width(BACK_ARROW_SIZE)
      .height(BACK_ARROW_SIZE)
      .justifyContent(FlexAlign.Center)
      .alignItems(VerticalAlign.Center)
      // MEDIA-VIEWER-102：返回键这块热区要独占。浮层根 Column 是 Transparent（否则中间区域
      // 挡死了翻页与点击翻栏），而 Transparent 的语义就是「连祖先的兄弟节点一起放进来做触摸
      // 测试」，下层那台全屏 Swiper 于是和返回键抢同一次点击。Block 在自身这里截断祖先链，
      // 该热区只报给浮层。（SDK：Default 只挡兄弟、不挡祖先；Block 挡子/兄/祖三级。）
      .hitTestBehavior(HitTestMode.Block)
      .onClick(() => {
        this.onDispatch(new CloseMediaViewer());
      })

      Column() {
        Text(this.getViewerTitle())
          .fontSize(this.T.typography.title.fontSize)
          .fontWeight(this.T.typography.title.fontWeight)
          .fontColor(Color.White)
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })

        if (this.getViewerSubtitle().length > 0) {
          Text(this.getViewerSubtitle())
            .fontSize(this.T.typography.caption.fontSize)
            .fontColor(this.T.colors.textSecondary)
            .margin({ top: 2 })
        }
      }
      .layoutWeight(1)
      .alignItems(HorizontalAlign.Start)
      .margin({ left: this.T.spacing.xs })
    }
    .width('100%')
    .padding({
      left: this.T.spacing.sm,
      right: this.T.spacing.md,
      top: 36,
      bottom: this.T.spacing.sm
    })
    .backgroundColor(this.T.colors.scrim)
  }

  @Builder
  ViewerBottomBar() {
    Column() {
      Scroll() {
        Text(this.getViewerCaption())
          .fontSize(this.T.typography.body.fontSize)
          .fontColor(Color.White)
          .width('100%')
      }
      .scrollBar(BarState.Off)
      .constraintSize({ maxHeight: 180 })
    }
    .width('100%')
    .padding({
      left: this.T.spacing.screenInset,
      right: this.T.spacing.screenInset,
      top: this.T.spacing.md,
      bottom: 28
    })
    .backgroundColor(this.T.colors.scrim)
  }

  private getViewerTitle(): string {
    const total: number = this.uiState.viewerItems.length;
    const current: number = this.uiState.activeViewerIndex + 1;
    if (this.uiState.activeViewerIndex < 0 || this.uiState.activeViewerIndex >= total) {
      return '';
    }
    const item: MediaViewerItem = this.uiState.viewerItems[this.uiState.activeViewerIndex];
    const name: string = item.senderName.length > 0 ? item.senderName : this.uiState.chatTitle;
    return `${name} (${current} / ${total})`;
  }

  private getViewerSubtitle(): string {
    if (this.uiState.activeViewerIndex < 0 || this.uiState.activeViewerIndex >= this.uiState.viewerItems.length) {
      return '';
    }
    const item: MediaViewerItem = this.uiState.viewerItems[this.uiState.activeViewerIndex];
    return item.timestampMs > 0 ? formatMessageTime(item.timestampMs) : '';
  }

  private getViewerCaption(): string {
    if (this.uiState.activeViewerIndex < 0 || this.uiState.activeViewerIndex >= this.uiState.viewerItems.length) {
      return '';
    }
    const item: MediaViewerItem = this.uiState.viewerItems[this.uiState.activeViewerIndex];
    return item.media.caption;
  }

  /** 底部输入栏：圆角输入框 + 圆形发送按钮；受控输入，发送经 MVI 分发。 */
  @Builder
  ComposerBar() {
    Row() {
      // EMOJI-101：表情/键盘切换按钮（对齐 Telegram X 输入栏左侧笑脸/键盘图标）
      Row() {
        Image(this.uiState.showEmojiBoard ? $r('app.media.ic_keyboard') : $r('app.media.ic_emoji'))
          .width(24)
          .height(24)
          .fillColor(this.uiState.showEmojiBoard ? this.T.colors.accent : this.T.colors.textSecondary)
      }
      .width(COMPOSER_INPUT_HEIGHT)
      .height(COMPOSER_INPUT_HEIGHT)
      .justifyContent(FlexAlign.Center)
      .alignItems(VerticalAlign.Center)
      .margin({ right: this.T.spacing.xs })
      .onClick(() => {
        this.onDispatch(new ToggleEmojiBoard());
      })

      Row() {
        TextInput({
          text: this.uiState.composerText,
          placeholder: 'Message'
        })
          .fontSize(this.T.typography.body.fontSize)
          .fontColor(this.T.colors.textPrimary)
          .placeholderColor(this.T.colors.textSecondary)
          .backgroundColor(Color.Transparent)
          .width('100%')
          .height(COMPOSER_INPUT_HEIGHT)
          .padding({ left: this.T.spacing.md, right: this.T.spacing.md })
          .onChange((value: string) => {
            this.onDispatch(new ComposerTextChanged(value));
          })
          .onFocus(() => {
            if (this.uiState.showEmojiBoard) {
              this.onDispatch(new CloseEmojiBoard());
            }
          })
          .onSubmit(() => {
            this.dispatchSend();
          })
      }
      .layoutWeight(1)
      .height(COMPOSER_INPUT_HEIGHT)
      .backgroundColor(this.T.colors.surfaceVariant)
      .borderRadius(this.T.radius.full)

      // COMPOSER-102：统一附件入口按钮（展开/收起附件选择面板）
      // CHAN-SEND-2：九位媒体权限全禁时不出附件入口（Android Tdlib.canSendSendSomeMedia）。
      if (this.showAttachButton()) {
        Row() {
          Image($r('app.media.ic_attach'))
            .width(24)
            .height(24)
            .fillColor(this.uiState.showAttachmentMenu ? this.T.colors.accent : this.T.colors.textSecondary)
        }
        .width(COMPOSER_INPUT_HEIGHT)
        .height(COMPOSER_INPUT_HEIGHT)
        .justifyContent(FlexAlign.Center)
        .alignItems(VerticalAlign.Center)
        .margin({ left: this.T.spacing.xs, right: this.T.spacing.xs })
        .onClick(() => {
          this.onDispatch(new ToggleAttachmentMenu());
        })
      }

      Row() {
        Image(this.canSend() ? $r('app.media.ic_send') : $r('app.media.ic_mic'))
          .width(20)
          .height(20)
          .fillColor(this.canSend() || this.canRecordVoiceNow()
            ? this.T.colors.textOnAccent
            : this.T.colors.disabled)
      }
      .width(SEND_BUTTON_SIZE)
      .height(SEND_BUTTON_SIZE)
      .backgroundColor(this.T.colors.accent)
      .borderRadius(this.T.radius.full)
      .justifyContent(FlexAlign.Center)
      .alignItems(VerticalAlign.Center)
      .onClick(() => {
        if (this.canSend()) {
          this.dispatchSend();
        } else if (!this.canRecordVoiceNow()) {
          this.showHintToast('此会话不允许发送语音消息');
        } else {
          this.onDispatch(new StartVoiceRecord());
        }
      })
    }
    .width('100%')
    .alignItems(VerticalAlign.Center)
    .padding({
      left: this.T.spacing.screenInset,
      right: this.T.spacing.screenInset,
      top: this.T.spacing.xs,
      bottom: this.T.spacing.sm
    })
    .borderWidth({ top: 1 })
    .borderColor(this.T.colors.divider)
  }

  /** VOICE-101：录音控制条（全宽：红色录音指示点、秒级计时、放弃取消按钮、发送按钮） */
  @Builder
  VoiceRecordingBar() {
    Row() {
      // 动态红点指示器与录音中计时
      Row() {
        Row()
          .width(10)
          .height(10)
          .borderRadius(this.T.radius.full)
          .backgroundColor(this.T.colors.destructive)
          .margin({ right: this.T.spacing.xs })

        Text(formatDuration(this.uiState.recordingDurationSec))
          .fontSize(this.T.typography.body.fontSize)
          .fontColor(this.T.colors.textPrimary)
          .fontWeight(FontWeight.Medium)
      }
      .alignItems(VerticalAlign.Center)
      .margin({ left: this.T.spacing.sm })

      Blank()

      // 取消放弃按钮（✕）
      Row() {
        Image($r('app.media.ic_close'))
          .width(20)
          .height(20)
          .fillColor(this.T.colors.textSecondary)
      }
      .width(SEND_BUTTON_SIZE)
      .height(SEND_BUTTON_SIZE)
      .borderRadius(this.T.radius.full)
      .justifyContent(FlexAlign.Center)
      .alignItems(VerticalAlign.Center)
      .margin({ right: this.T.spacing.sm })
      .onClick(() => {
        this.onDispatch(new CancelVoiceRecord());
      })

      // 发送按钮（➤）
      Row() {
        Image($r('app.media.ic_send'))
          .width(20)
          .height(20)
          .fillColor(this.T.colors.textOnAccent)
      }
      .width(SEND_BUTTON_SIZE)
      .height(SEND_BUTTON_SIZE)
      .backgroundColor(this.T.colors.accent)
      .borderRadius(this.T.radius.full)
      .justifyContent(FlexAlign.Center)
      .alignItems(VerticalAlign.Center)
      .onClick(() => {
        this.onDispatch(new StopAndSendVoiceRecord());
      })
    }
    .width('100%')
    .height(COMPOSER_INPUT_HEIGHT + this.T.spacing.xs + this.T.spacing.sm)
    .alignItems(VerticalAlign.Center)
    .padding({
      left: this.T.spacing.screenInset,
      right: this.T.spacing.screenInset,
      top: this.T.spacing.xs,
      bottom: this.T.spacing.sm
    })
    .backgroundColor(this.T.colors.surface)
    .borderWidth({ top: 1 })
    .borderColor(this.T.colors.divider)
  }

  /**
   * CHAN-SEND-2：频道只读态 —— 已是成员但 TDLib 明确给出无发言权（permissions.can_send_basic_messages=false）。
   * 对齐 Android TGX 的 `Tdlib.canSendBasicMessage(chat)` 判定：有权限的成员看到正常输入栏，
   * 只有真正被限制发言的频道才把底栏收成静音条。
   */
  private isChannelReadOnly(): boolean {
    return this.uiState.chatKind === 'channel' && this.uiState.isChannelMember && !this.uiState.sendRights.basic;
  }

  /**
   * CHAN-SEND-2：底栏是否被频道条占据（未加入 → 加入条，只读 → 静音条）。
   * 这三种输入相关 UI（模式条 / 输入栏 / 表情面板）互斥，统一走这一个谓词，避免各分支各写一份。
   */
  private isChannelOverlayBar(): boolean {
    return this.uiState.chatKind === 'channel' && (!this.uiState.isChannelMember || !this.uiState.sendRights.basic);
  }

  /** CHANNEL-101：非成员频道底部"加入频道"全宽条 */
  @Builder
  JoinChannelBar() {
    Row() {
      Button('加入频道')
        .width('100%')
        .height(40)
        .backgroundColor(this.T.colors.accent)
        .fontColor(this.T.colors.textOnAccent)
        .fontSize(this.T.typography.headline.fontSize)
        .fontWeight(FontWeight.Medium)
        .borderRadius(this.T.radius.md)
        .onClick(() => {
          this.onDispatch(new JoinChannel());
        })
    }
    .width('100%')
    .padding({
      left: this.T.spacing.screenInset,
      right: this.T.spacing.screenInset,
      top: this.T.spacing.xs,
      bottom: this.T.spacing.sm
    })
    .borderWidth({ top: 1 })
    .borderColor(this.T.colors.divider)
    .backgroundColor(this.T.colors.surface)
  }

  /** CHANNEL-101：已加入频道底部"静音"快捷操作条（Telegram X 广播频道模式） */
  @Builder
  ChannelMuteBar() {
    Row() {
      Row() {
        Image(this.uiState.isMuted ? $r('app.media.ic_notifications') : $r('app.media.ic_mute'))
          .width(20)
          .height(20)
          .fillColor(this.T.colors.accent)
          .margin({ right: this.T.spacing.sm })

        Text(this.uiState.isMuted ? '开启通知' : '静音')
          .fontSize(this.T.typography.headline.fontSize)
          .fontWeight(FontWeight.Medium)
          .fontColor(this.T.colors.accent)
      }
      .width('100%')
      .height(40)
      .justifyContent(FlexAlign.Center)
      .alignItems(VerticalAlign.Center)
      .backgroundColor(this.T.colors.surfaceVariant)
      .borderRadius(this.T.radius.md)
      .onClick(() => {
        this.onDispatch(new ChatMenuAction(this.muteMenuAction()));
      })
    }
    .width('100%')
    .padding({
      left: this.T.spacing.screenInset,
      right: this.T.spacing.screenInset,
      top: this.T.spacing.xs,
      bottom: this.T.spacing.sm
    })
    .borderWidth({ top: 1 })
    .borderColor(this.T.colors.divider)
  }

  /**
   * SET-106：静音菜单项文案与动作随会话静音态切换。
   * 读 this.uiState 而非入参，保证 @Builder 内的 @Prop 变更能驱动重渲染。
   */
  private muteMenuLabel(): string {
    return this.uiState.isMuted ? '取消静音' : '静音';
  }

  private muteMenuAction(): string {
    return this.uiState.isMuted ? 'enable_notifications' : 'mute';
  }

  private canSend(): boolean {
    return this.uiState.composerText.trim().length > 0;
  }

  private dispatchSend(): void {
    this.onDispatch(new SendCurrentMessage());
  }

  // ---- MSG-102 群聊署名与头像 ----

  /** 收到的群聊消息且署名已解析 → 显示署名行 + 头像。 */
  private showSenderUi(item: MessageItem): boolean {
    return !item.isOutgoing && item.senderName.length > 0;
  }

  /** 署名颜色：senderColorIndex 取调色板；-1 兜底 accent。 */
  private senderNameColor(item: MessageItem): string {
    return item.senderColorIndex >= 0 ? nameColorForIndex(item.senderColorIndex) : this.T.colors.accent;
  }

  /** 头像底色：与署名同色调色板取色。 */
  private senderAvatarColor(item: MessageItem): string {
    return item.senderColorIndex >= 0 ? nameColorForIndex(item.senderColorIndex) : this.T.colors.accent;
  }

  /** 回复引用左侧竖条与发件人昵称颜色：取发送者同款调色板，-1 兜底 accent。 */
  private replyLineColor(item: MessageItem): string {
    return item.replySenderColorIndex >= 0 ? nameColorForIndex(item.replySenderColorIndex) : this.T.colors.accent;
  }

  /** 点击回复引用跳转到被回复消息所在位置 */
  private scrollToMessageId(messageId: number): void {
    for (let i = 0; i < this.uiState.messages.length; i++) {
      if (this.uiState.messages[i].messageId === messageId) {
        this.scroller.scrollToIndex(i, true, ScrollAlign.CENTER);
        break;
      }
    }
  }

  // ---- MSG-101 富文本 span：样式与交互 ----

  private isSpoilerRevealed(messageId: number, spanIndex: number): boolean {
    return this.revealedSpoilers.indexOf(`${messageId}:${spanIndex}`) >= 0;
  }

  private toggleSpoiler(messageId: number, spanIndex: number): void {
    const key: string = `${messageId}:${spanIndex}`;
    if (this.revealedSpoilers.indexOf(key) >= 0) {
      this.revealedSpoilers = this.revealedSpoilers.filter((k: string) => k !== key);
    } else {
      this.revealedSpoilers = this.revealedSpoilers.concat([key]);
    }
  }

  /**
   * FEAT-UI-002 / SET-105：消息内容文字的字号。
   *
   * 以现有排版 token 为基准按「聊天字号倍率」等比缩放——默认档（15）倍率为
   * 1.0，故默认视觉与改造前逐像素一致、不引入回归；调档时消息内容区的正文/
   * 署名/时间戳/反应等比联动。`diff` 偏移语义对齐 TGX `TGMessage` 的
   * `setTextSizeDiff`（时间戳 −1~−2、反应 −4）。下限由 `chatTextSizeOf` 守住。
   */
  private chatText(base: number, diff: number = 0): number {
    return chatTextSizeOf(base, this.T.chatFontSize, diff);
  }

  private spanFontSize(span: MessageTextSpan): number {
    const body: number = this.T.typography.body.fontSize;
    // 正文随聊天字号；code/pre 再降 2（对齐 TGX 的 setTextSizeDiff(-2)）。
    return span.isCode || span.isPre ? this.chatText(body, -2) : this.chatText(body);
  }

  private spanFontFamily(span: MessageTextSpan): string {
    // 'sans-serif' 是 ArkUI 通用族名，解析为系统默认字体，保持与非 code 文本一致。
    return span.isCode || span.isPre ? 'monospace' : 'sans-serif';
  }

  private spanFontColor(span: MessageTextSpan, messageId: number, spanIndex: number): string {
    if (span.isSpoiler && !this.isSpoilerRevealed(messageId, spanIndex)) {
      return this.T.colors.textPrimary; // 遮罩态：文字与遮罩同色，内容不可读
    }
    if (span.linkUrl !== null) {
      return this.T.colors.link;
    }
    if (span.isAccent) {
      return this.T.colors.accent;
    }
    return this.T.colors.chatText;
  }

  private spanDecorationType(span: MessageTextSpan): TextDecorationType {
    // ArkUI decoration 只支持单 type：underline 与 strikethrough 同现时取 underline。
    if (span.underline) {
      return TextDecorationType.Underline;
    }
    if (span.strikethrough) {
      return TextDecorationType.LineThrough;
    }
    return TextDecorationType.None;
  }

  private spanBackgroundColor(span: MessageTextSpan, messageId: number, spanIndex: number): ResourceColor {
    if (span.isSpoiler && !this.isSpoilerRevealed(messageId, spanIndex)) {
      return this.T.colors.textPrimary; // 遮罩态深色块
    }
    if (span.isSpoiler || span.isCode || span.isPre) {
      return this.T.colors.surfaceVariant; // 揭开后 / code 的浅底提示
    }
    return Color.Transparent;
  }

  private onSpanClick(messageId: number, span: MessageTextSpan, spanIndex: number): void {
    if (span.isSpoiler && !this.isSpoilerRevealed(messageId, spanIndex)) {
      // 遮罩态点击只揭开，不触发链接（防误触）。
      this.toggleSpoiler(messageId, spanIndex);
      return;
    }
    if (span.linkUrl !== null) {
      this.openLink(span.linkUrl);
    }
  }

  private openLink(url: string): void {
    let targetUrl: string = url.trim();
    if (targetUrl.length === 0) {
      return;
    }
    // MSG-105：协议前缀容错（若既无 :// 且非 mailto:/tel:，自动补全 https://）
    if (!targetUrl.includes('://') && !targetUrl.startsWith('mailto:') && !targetUrl.startsWith('tel:')) {
      targetUrl = 'https://' + targetUrl;
    }
    // DEEPLINK-101：Telegram 自家的链接不交给浏览器 —— 浏览器只会给出一个登录墙。
    // 判据只有 scheme + host（见 core/navigation/TelegramLink），真正的语义由装配层
    // 问 TDLib 的 getInternalLinkType 决定；这里不做解析，避免两套真相。
    if (isTelegramLinkCandidate(targetUrl)) {
      this.onDispatch(new OpenAppLink(targetUrl));
      return;
    }
    const hostContext = this.getUIContext().getHostContext();
    if (hostContext === undefined) {
      // 只记失败事件，不记 URL 正文。
      hilog.warn(DOMAIN, TAG, 'openLink failed: no host context');
      return;
    }
    const context = hostContext as common.UIAbilityContext;
    context.openLink(targetUrl, { appLinkingOnly: false })
      .then(() => {
        hilog.info(DOMAIN, TAG, 'openLink succeeded');
      })
      .catch((err: BusinessError) => {
        // 只记失败事件与错误码，不记 URL 正文。
        hilog.warn(DOMAIN, TAG, 'openLink failed: %{public}d', err.code);
        try {
          this.getUIContext().getPromptAction().showToast({
            message: '无法打开链接',
            duration: 2000
          });
        } catch (toastErr) {
        }
      });
  }

  @Builder
  LoadingView() {
    Column() {
      LoadingProgress()
        .width(48)
        .height(48)
        .color(this.T.colors.accent)
        .margin({ bottom: this.T.spacing.lg })

      Text('Loading messages...')
        .fontSize(this.T.typography.body.fontSize)
        .fontColor(this.T.colors.textSecondary)
    }
    .width('100%')
    .layoutWeight(1)
    .justifyContent(FlexAlign.Center)
    .alignItems(HorizontalAlign.Center)
  }

  @Builder
  EmptyView() {
    Column() {
      Text('No messages yet')
        .fontSize(this.T.typography.body.fontSize)
        .fontColor(this.T.colors.textSecondary)
    }
    .width('100%')
    .layoutWeight(1)
    .justifyContent(FlexAlign.Center)
    .alignItems(HorizontalAlign.Center)
  }

  @Builder
  ErrorView(errorMessage: string) {
    Column() {
      Text('Failed to load messages')
        .fontSize(this.T.typography.title.fontSize)
        .fontWeight(this.T.typography.title.fontWeight)
        .fontColor(this.T.colors.destructive)
        .margin({ bottom: this.T.spacing.md })

      Text(errorMessage)
        .fontSize(this.T.typography.footnote.fontSize)
        .fontColor(this.T.colors.textSecondary)
        .textAlign(TextAlign.Center)
        .margin({
          bottom: this.T.spacing.xxl,
          left: this.T.spacing.xxl,
          right: this.T.spacing.xxl
        })

      Button('Try Again')
        .width('60%')
        .height(44)
        .backgroundColor(this.T.colors.accent)
        .borderRadius(this.T.radius.full)
        .onClick(() => {
          this.onDispatch(new LoadInitialMessages());
        })
    }
    .width('100%')
    .layoutWeight(1)
    .justifyContent(FlexAlign.Center)
    .alignItems(HorizontalAlign.Center)
  }

  /** SEARCH-102：聊天内搜索面板。全屏覆盖：顶部搜索栏（返回 X + 输入框），
   *  中部命中结果列表（含原文摘要 + 日期，点击 → jumpToSearchResult 定位），
   *  空态/加载态，底部由装配层透传的 keyboardAvoidMode 由系统承担。 */
  @Builder
  SearchPanel() {
    Column() {
      // 面板头：返回（收起搜索）+ 搜索输入框
      Row() {
        Row() {
          Image($r('app.media.ic_close'))
            .width(20)
            .height(20)
            .fillColor(this.T.colors.accent)
        }
        .width(BACK_ARROW_SIZE)
        .height(BACK_ARROW_SIZE)
        .justifyContent(FlexAlign.Center)
        .alignItems(VerticalAlign.Center)
        .onClick(() => {
          this.onDispatch(new CloseChatSearch());
        })

        TextInput({ placeholder: 'Search in chat...' })
          .width('100%')
          .height(COMPOSER_INPUT_HEIGHT)
          .fontSize(this.T.typography.body.fontSize)
          .fontColor(this.T.colors.textPrimary)
          .backgroundColor(this.T.colors.backgroundSecondary)
          .borderRadius(this.T.radius.sm)
          .padding({ left: this.T.spacing.sm, right: this.T.spacing.sm })
          .onChange((value: string) => {
            this.onDispatch(new ChatSearchQueryChanged(value));
            // 防抖：输入停顿 300ms 后自动执行搜索（对齐 Telegram X 即时搜索体验）。
            if (this.searchDebounceTimer !== undefined) {
              clearTimeout(this.searchDebounceTimer);
              this.searchDebounceTimer = undefined;
            }
            if (value.trim().length > 0) {
              this.searchDebounceTimer = setTimeout(() => {
                this.searchDebounceTimer = undefined;
                this.onDispatch(new PerformChatSearch());
              }, 300);
            }
          })
      }
      .width('100%')
      .alignItems(VerticalAlign.Center)
      .padding({
        left: this.T.spacing.sm,
        right: this.T.spacing.screenInset,
        top: this.T.spacing.sm,
        bottom: this.T.spacing.sm
      })
      .borderWidth({ bottom: 1 })
      .borderColor(this.T.colors.divider)

      // 结果列表
      if (this.uiState.isSearching) {
        Column() {
          LoadingProgress()
            .width(40)
            .height(40)
            .color(this.T.colors.accent)
        }
        .width('100%')
        .layoutWeight(1)
        .justifyContent(FlexAlign.Center)
        .alignItems(HorizontalAlign.Center)
      } else if (this.uiState.searchResults.length === 0) {
        Column() {
          // 未输入关键词时给引导文案；输入过但无命中才提示 No results
          // （否则一打开面板就是"No results"，看起来像搜索坏了）。
          Text(this.uiState.searchQuery.trim().length === 0
            ? 'Search messages in this chat'
            : 'No results')
            .fontSize(this.T.typography.body.fontSize)
            .fontColor(this.T.colors.textSecondary)
            .textAlign(TextAlign.Center)
        }
        .width('100%')
        .layoutWeight(1)
        .justifyContent(FlexAlign.Center)
        .alignItems(HorizontalAlign.Center)
      } else {
        List({ scroller: this.searchScroller }) {
          ForEach(this.uiState.searchResults.slice(), (result: ChatSearchResultItem) => {
            ListItem() {
              Column() {
                Row() {
                  Text(result.textSnippet.length > 0 ? result.textSnippet : '[Message]')
                    .fontSize(this.T.typography.body.fontSize)
                    .fontColor(this.T.colors.textPrimary)
                    .maxLines(2)
                    .textOverflow({ overflow: TextOverflow.Ellipsis })
                    .layoutWeight(1)

                  Text(result.dateText)
                    .fontSize(this.T.typography.footnote.fontSize)
                    .fontColor(this.T.colors.textSecondary)
                }
                .width('100%')
                .alignItems(VerticalAlign.Center)

                if (!result.jumpable) {
                  Text('Tap to load')
                    .fontSize(this.T.typography.footnote.fontSize)
                    .fontColor(this.T.colors.accent)
                }
              }
              .width('100%')
              .padding({
                left: this.T.spacing.screenInset,
                right: this.T.spacing.screenInset,
                top: this.T.spacing.sm,
                bottom: this.T.spacing.sm
              })
              .backgroundColor(this.T.colors.background)
            }
            .onClick(() => {
              this.onDispatch(new JumpToSearchResult(result.messageId));
            })
          }, (result: ChatSearchResultItem) => `srch_${result.messageId}_${result.textSnippet.length}`)
        }
        .width('100%')
        .layoutWeight(1)
        .scrollBar(BarState.Off)
      }
    }
    .width('100%')
    .height('100%')
    .backgroundColor(this.T.colors.background)
  }
}
