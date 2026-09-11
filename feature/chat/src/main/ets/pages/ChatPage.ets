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
 */

import { LightTheme } from '@tgx/core-design-system';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { common } from '@kit.AbilityKit';
import { BusinessError } from '@kit.BasicServicesKit';
import { fileUri } from '@kit.CoreFileKit';
import { MessageItem } from '../model/MessageItem';
import { MessageTextSpan } from '../model/MessageTextSpan';
import { MediaAttachment } from '../model/MediaAttachment';
import { MediaViewerItem } from '../model/MediaViewerItem';
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
  EditMessage,
  DeleteMessage,
  CancelComposerMode,
  DismissMessageActionMenu,
  OnVisibleRangeChanged,
  TapFailedMessage,
  OpenMediaViewer,
  CloseMediaViewer,
  ChangeViewerIndex,
  RequestMediaDownload
} from '../contract/ChatIntent';

const T = LightTheme;

const DOMAIN: number = 0x0000;
const TAG: string = 'ChatPage';

const BUBBLE_MAX_WIDTH: string = '78%';
const BACK_ARROW_SIZE: number = 44;
const COMPOSER_INPUT_HEIGHT: number = 40;
const SEND_BUTTON_SIZE: number = 40;
/** 等宽（code/pre）span 字号：比正文小 2vp。 */
const CODE_FONT_SIZE: number = T.typography.body.fontSize - 2;
/** spoiler 遮罩色（token）：遮罩态文字同色不可读。 */
const SPOILER_MASK_COLOR: string = T.colors.textPrimary;
/** 群聊署名小圆头像直径（vp）。 */
const SENDER_AVATAR_SIZE: number = 28;

function pad2(value: number): string {
  return value < 10 ? `0${value}` : `${value}`;
}

/** 消息气泡内时间戳：HH:mm。 */
function formatMessageTime(timestampMs: number): string {
  const date: Date = new Date(timestampMs);
  return `${pad2(date.getHours())}:${pad2(date.getMinutes())}`;
}

/** 气泡时间戳 + 发送状态：pending 附 "…"，failed 只显 "!"；MSG-104 己方消息附已读勾（✓/✓✓）。 */
function formatMessageStatus(item: MessageItem): string {
  if (item.sendState === 'pending') {
    return item.timestampMs > 0 ? `${formatMessageTime(item.timestampMs)} …` : '…';
  }
  if (item.sendState === 'failed') {
    return '!';
  }
  const time: string = formatMessageTime(item.timestampMs);
  const edited: string = item.isEdited ? `${time} edited` : time;
  if (!item.isOutgoing) {
    return edited;
  }
  return item.isRead ? `${edited} ✓✓` : `${edited} ✓`;
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

/** 消息行的 LazyForEach key：messageId + 展示相关内容散列（正文/署名/回复摘要/发送态/已读/编辑标记/多媒体）。 */
function messageRowKey(item: MessageItem): string {
  let mediaSig: string = '';
  if (item.media !== null) {
    const m: MediaAttachment = item.media;
    const path: string = m.localPath !== null ? m.localPath : '';
    const thumb: string = m.thumbnailPath !== null ? m.thumbnailPath : '';
    mediaSig = `${m.kind}|${m.fileId}|${path}|${thumb}|${m.isDownloaded}|${m.isDownloading}|${Math.round(m.progress * 10)}`;
  }
  const signature: string =
    `${item.sendState}|${item.isRead}|${item.isEdited}|${item.senderColorIndex}|` +
    `${item.text}|${item.senderName}|${item.replyToSummary}|${mediaSig}`;
  return `${item.messageId}:${fnv1a32(signature)}`;
}

/** LazyForEach 数据源：整体替换 items 并触发全量刷新。 */
export class MessageListDataSource implements IDataSource {  private items: MessageItem[] = [];
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

  setItems(items: readonly MessageItem[]): void {
    this.items = items.slice(0);
    this.listeners.forEach((listener: DataChangeListener) => {
      listener.onDataReloaded();
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
  @Prop @Watch('onUiStateChanged') uiState: ChatUiState = ChatUiState.initial();

  onDispatch: (intent: Object) => void = () => {};

  private dataSource: MessageListDataSource = new MessageListDataSource();
  private scroller: Scroller = new Scroller();
  private shownMessages: readonly MessageItem[] = [];
  private shownCount: number = 0;
  private lastTailMessageId: number = 0;
  /** 已揭开的 spoiler span 集合，key = `${messageId}:${spanIndex}`（MSG-101）。 */
  @State private revealedSpoilers: string[] = [];
  /** MEDIA-103：全屏媒体查看器缩放比例与工具栏显隐状态。 */
  @State private viewerScale: number = 1.0;
  @State private pinchStartScale: number = 1.0;
  @State private viewerBarsVisible: boolean = true;
  private swiperController: SwiperController = new SwiperController();

  private computeScrollTargetIndex(messages: readonly MessageItem[]): number {
    if (messages.length === 0) {
      return 0;
    }
    const lastReadInbox: number = this.uiState.lastReadInboxMessageId;
    if (lastReadInbox > 0) {
      for (let i = 0; i < messages.length; i++) {
        const item: MessageItem = messages[i];
        if (!item.isOutgoing && item.messageId > lastReadInbox) {
          return i;
        }
      }
    }
    return messages.length - 1;
  }

  aboutToAppear(): void {
    this.dataSource.setItems(this.uiState.messages);
    this.shownMessages = this.uiState.messages;
    this.shownCount = this.uiState.messages.length;
    if (this.shownCount > 0) {
      this.lastTailMessageId = this.uiState.messages[this.shownCount - 1].messageId;
      const targetIdx: number = this.computeScrollTargetIndex(this.uiState.messages);
      const align: ScrollAlign = (targetIdx === this.shownCount - 1) ? ScrollAlign.END : ScrollAlign.START;
      setTimeout(() => {
        this.scroller.scrollToIndex(targetIdx, false, align);
      }, 50);
    }
  }

  onUiStateChanged(): void {
    if (this.uiState.activeViewerIndex < 0) {
      this.viewerScale = 1.0;
      this.viewerBarsVisible = true;
    }
    const messages: readonly MessageItem[] = this.uiState.messages;
    // composerText 等变化不触碰列表：仅 messages 引用变化才刷新数据源，
    // 避免输入栏每次击键都触发 LazyForEach 全量重载。
    if (messages === this.shownMessages) {
      return;
    }
    const count: number = messages.length;
    const tailId: number = count > 0 ? messages[count - 1].messageId : 0;
    const firstContent: boolean = this.shownCount === 0 && count > 0;
    const grewAtTail: boolean = count > 0 && tailId !== this.lastTailMessageId;
    this.dataSource.setItems(messages);
    this.shownMessages = messages;
    this.shownCount = count;
    this.lastTailMessageId = tailId;
    // 首屏出内容 → 定位到首条未读或最新；尾部来了新消息 → 平滑滚到底；顶部翻页（前插）不打断阅读位置。
    if (firstContent) {
      const targetIdx: number = this.computeScrollTargetIndex(messages);
      const align: ScrollAlign = (targetIdx === count - 1) ? ScrollAlign.END : ScrollAlign.START;
      setTimeout(() => {
        this.scroller.scrollToIndex(targetIdx, false, align);
      }, 50);
    } else if (grewAtTail) {
      setTimeout(() => {
        this.scroller.scrollToIndex(count - 1, true, ScrollAlign.END);
      }, 40);
    }
  }

  build() {
    Stack() {
      Column() {
        this.Header()

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
                .color(T.colors.accent)
            }
            .width('100%')
            .justifyContent(FlexAlign.Center)
            .padding({ top: T.spacing.xs })
          }

          List({ initialIndex: this.computeScrollTargetIndex(this.uiState.messages), scroller: this.scroller }) {
            LazyForEach(this.dataSource, (item: MessageItem) => {
              ListItem() {
                this.MessageRow(item)
              }
            }, (item: MessageItem) => messageRowKey(item))
          }
          .width('100%')
          .layoutWeight(1)
          .cachedCount(5)
          .scrollBar(BarState.Off)
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
            .fontSize(T.typography.footnote.fontSize)
            .fontColor(T.colors.destructive)
            .maxLines(1)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
            .width('100%')
            .padding({
              left: T.spacing.screenInset,
              right: T.spacing.screenInset,
              top: T.spacing.xs
            })
        }

        // 回复/编辑预览条（CHAT-004）：标题 + 摘要 + 取消 X。
        if (this.uiState.composerMode !== null) {
          this.ComposerModeBar(this.uiState.composerMode)
        }

        this.ComposerBar()
      }
      .width('100%')
      .height('100%')

      // 长按气泡的操作菜单（CHAT-004）：全屏遮罩 + 底部动作面板。
      if (this.uiState.actionMenu !== null) {
        this.ActionMenuSheet(this.uiState.actionMenu)
      }

      // 全屏媒体查看器（MEDIA-103 / FEAT-MEDIA-006）
      if (this.uiState.activeViewerIndex >= 0) {
        this.MediaViewerOverlay()
      }
    }
    .width('100%')
    .height('100%')
    .backgroundColor(T.colors.background)
  }

  @Builder
  Header() {
    Row() {
      Text('‹')
        .fontSize(T.typography.largeTitle.fontSize)
        .fontWeight(T.typography.title.fontWeight)
        .fontColor(T.colors.accent)
        .width(BACK_ARROW_SIZE)
        .height(BACK_ARROW_SIZE)
        .textAlign(TextAlign.Center)
        .onClick(() => {
          this.onDispatch(new BackToChatList());
        })

      Text(this.uiState.chatTitle)
        .fontSize(T.typography.title.fontSize)
        .fontWeight(T.typography.title.fontWeight)
        .fontColor(T.colors.textPrimary)
        .maxLines(1)
        .textOverflow({ overflow: TextOverflow.Ellipsis })
        .layoutWeight(1)
    }
    .width('100%')
    .alignItems(VerticalAlign.Center)
    .padding({
      left: T.spacing.sm,
      right: T.spacing.screenInset,
      top: T.spacing.sm,
      bottom: T.spacing.sm
    })
    .borderWidth({ bottom: 1 })
    .borderColor(T.colors.divider)
  }

  @Builder
  MessageRow(item: MessageItem) {
    Row() {
      // MSG-102：群聊收到的消息在气泡左侧出小圆头像（彩色底 + 首字母，配色同会话列表）。
      if (this.showSenderUi(item)) {
        Text(avatarLettersForName(item.senderName))
          .width(SENDER_AVATAR_SIZE)
          .height(SENDER_AVATAR_SIZE)
          .borderRadius(T.radius.full)
          .backgroundColor(this.senderAvatarColor(item))
          .fontColor(T.colors.textOnAccent)
          .fontSize(T.typography.footnote.fontSize)
          .textAlign(TextAlign.Center)
          .margin({ right: T.spacing.xs })
      }

      Column() {
        // MSG-102：署名行（气泡最顶部，回复引用之上）。
        if (this.showSenderUi(item)) {
          Text(item.senderName)
            .fontSize(T.typography.subheadline.fontSize)
            .fontWeight(FontWeight.Medium)
            .fontColor(this.senderNameColor(item))
            .maxLines(1)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
            .margin({ bottom: T.spacing.hairline })
        }

        // 回复引用行（CHAT-004）：原消息不在当前列表时摘要退化为占位文案。
        if (item.replyToMessageId !== null) {
          Text(item.replyToSummary.length > 0 ? `↪ ${item.replyToSummary}` : '↪ message')
            .fontSize(T.typography.caption.fontSize)
            .fontColor(T.colors.textSecondary)
            .maxLines(1)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
            .margin({ bottom: T.spacing.hairline })
        }

        // 多媒体附件（MEDIA-101 / MEDIA-105）：图片、视频、GIF 动图；贴纸（STICKER-101）。
        if (item.media !== null) {
          if (this.isSticker(item)) {
            this.StickerBubble(item.media, item)
          } else {
            this.MediaBubble(item.media, item.messageId)
          }
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
                    radius: T.radius.sm
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
                    radius: T.radius.sm
                  })
              }
            }, (span: MessageTextSpan, spanIndex: number) => `${item.messageId}:${spanIndex}`)
          }
          .fontSize(T.typography.body.fontSize)
          .fontColor(T.colors.chatText)
          .margin(item.media !== null ? { top: T.spacing.xs } : { top: 0 })
        } else if (item.text.length > 0) {
          Text(item.text)
            .fontSize(T.typography.body.fontSize)
            .fontColor(T.colors.chatText)
            .margin(item.media !== null ? { top: T.spacing.xs } : { top: 0 })
        }

        if (!this.isSticker(item)) {
          Text(formatMessageStatus(item))
            .fontSize(T.typography.caption.fontSize)
            .fontColor(item.sendState === 'failed' ? T.colors.destructive : T.colors.textSecondary)
            .margin({ top: T.spacing.hairline })
        }
      }
      .alignItems(HorizontalAlign.End)
      .backgroundColor(this.isSticker(item) ? Color.Transparent : (item.isOutgoing ? T.colors.chatOutgoing : T.colors.chatIncoming))
      .borderRadius(this.isSticker(item) ? 0 : T.radius.lg)
      .padding(this.isSticker(item) ? 0 : {
        left: T.spacing.md,
        right: T.spacing.md,
        top: T.spacing.sm,
        bottom: T.spacing.xs
      })
      .constraintSize({ maxWidth: BUBBLE_MAX_WIDTH })
      .onClick(() => {
        // MSG-104：点击发送失败的气泡重发；正常气泡点击无动作。
        if (item.sendState === 'failed') {
          this.onDispatch(new TapFailedMessage(item.messageId));
        }
      })
      .gesture(
        LongPressGesture({ duration: 350 })
          .onAction(() => {
            this.onDispatch(new MessageActionRequested(item.messageId));
          })
      )
    }
    .width('100%')
    .justifyContent(item.isOutgoing ? FlexAlign.End : FlexAlign.Start)
    .alignItems(VerticalAlign.Bottom)
    .padding({
      left: T.spacing.screenInset,
      right: T.spacing.screenInset,
      top: T.spacing.xs
    })
  }

  private mediaCardWidth(media: MediaAttachment): number {
    if (media.width <= 0 || media.height <= 0) {
      return 220;
    }
    const ratio: number = media.width / media.height;
    if (ratio >= 1.0) {
      return 240;
    }
    return Math.max(140, Math.min(240, Math.round(240 * ratio)));
  }

  private mediaCardHeight(media: MediaAttachment): number {
    if (media.width <= 0 || media.height <= 0) {
      return 160;
    }
    const ratio: number = media.width / media.height;
    if (ratio >= 1.0) {
      return Math.max(120, Math.min(240, Math.round(240 / ratio)));
    }
    return 240;
  }

  private isSticker(item: MessageItem): boolean {
    return item.media !== null && item.media.kind === 'sticker';
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
          .borderRadius(T.radius.full)
          .backgroundColor('#80000000')
          .justifyContent(FlexAlign.Center)
          .alignItems(HorizontalAlign.Center)
        }
      } else {
        Column() {
          Text(media.caption.length > 0 ? media.caption : '🎭')
            .fontSize(36)
        }
        .width('100%')
        .height('100%')
        .justifyContent(FlexAlign.Center)
        .alignItems(HorizontalAlign.Center)
      }

      // 右下角半透明胶囊时间戳（Telegram X 标准：drawBubbleTimeOverContent）
      Row() {
        Text(formatMessageStatus(item))
          .fontSize(10)
          .fontColor(Color.White)
      }
      .padding({ left: 6, right: 6, top: 2, bottom: 2 })
      .backgroundColor('#66000000')
      .borderRadius(T.radius.full)
      .margin({ right: 4, bottom: 4 })
    }
    .width(this.stickerWidth(media))
    .height(this.stickerHeight(media))
  }

  /** 多媒体气泡渲染（MEDIA-101 / MEDIA-105）：图片/视频/GIF 动图。 */
  @Builder
  MediaBubble(media: MediaAttachment, messageId: number) {
    Stack({ alignContent: Alignment.Center }) {
      // 1. 底图 / 缩略图 / 占位 / 动图视频
      if (media.localPath !== null && media.isDownloaded) {
        if (media.kind === 'animation' && (media.localPath.endsWith('.mp4') || media.localPath.indexOf('.mp4') >= 0)) {
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
            .borderRadius(T.radius.md)
        } else if (media.kind === 'video') {
          // 视频气泡：优先展示封面图（缩略图），若无缩略图则以 Video 组件首帧占位
          if (media.thumbnailPath !== null) {
            Image(toSandboxUri(media.thumbnailPath))
              .width('100%')
              .height('100%')
              .objectFit(ImageFit.Cover)
              .borderRadius(T.radius.md)
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
              .borderRadius(T.radius.md)
          }
        } else {
          // 普通图片或原生 GIF 格式图片
          Image(toSandboxUri(media.localPath))
            .width('100%')
            .height('100%')
            .objectFit(ImageFit.Cover)
            .borderRadius(T.radius.md)
        }
      } else if (media.thumbnailPath !== null) {
        Image(toSandboxUri(media.thumbnailPath))
          .width('100%')
          .height('100%')
          .objectFit(ImageFit.Cover)
          .borderRadius(T.radius.md)
      } else {
        Column() {
          Text(media.kind === 'video' ? '🎬' : (media.kind === 'animation' ? '👾' : '🖼️'))
            .fontSize(32)
        }
        .width('100%')
        .height('100%')
        .justifyContent(FlexAlign.Center)
        .alignItems(HorizontalAlign.Center)
        .backgroundColor(T.colors.surfaceVariant)
        .borderRadius(T.radius.md)
      }

      // 2. 状态与角标覆盖层
      if (media.kind === 'photo') {
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
            .borderRadius(T.radius.full)
            .backgroundColor('#80000000')
            .justifyContent(FlexAlign.Center)
            .alignItems(HorizontalAlign.Center)
          } else {
            Column() {
              Text('⬇')
                .fontSize(20)
                .fontColor(Color.White)
            }
            .width(44)
            .height(44)
            .borderRadius(T.radius.full)
            .backgroundColor('#80000000')
            .justifyContent(FlexAlign.Center)
            .alignItems(HorizontalAlign.Center)
          }
        }
      } else if (media.kind === 'animation') {
        // GIF 动图：左上角出 GIF 角标
        Row() {
          Text('GIF')
            .fontSize(10)
            .fontWeight(FontWeight.Bold)
            .fontColor(Color.White)
            .backgroundColor('#80000000')
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
            .borderRadius(T.radius.full)
            .backgroundColor('#80000000')
            .justifyContent(FlexAlign.Center)
            .alignItems(HorizontalAlign.Center)
          } else {
            Column() {
              Text('⬇')
                .fontSize(20)
                .fontColor(Color.White)
            }
            .width(44)
            .height(44)
            .borderRadius(T.radius.full)
            .backgroundColor('#80000000')
            .justifyContent(FlexAlign.Center)
            .alignItems(HorizontalAlign.Center)
          }
        }
      } else if (media.kind === 'video') {
        // 视频：居中下载/播放按钮
        if (!media.isDownloaded && media.isDownloading) {
          Column() {
            LoadingProgress()
              .width(36)
              .height(36)
              .color(Color.White)
          }
          .width(48)
          .height(48)
          .borderRadius(T.radius.full)
          .backgroundColor('#80000000')
          .justifyContent(FlexAlign.Center)
          .alignItems(HorizontalAlign.Center)
        } else {
          Column() {
            Text('▶')
              .fontSize(20)
              .fontColor(Color.White)
              .margin({ left: 3 })
          }
          .width(48)
          .height(48)
          .borderRadius(T.radius.full)
          .backgroundColor('#80000000')
          .justifyContent(FlexAlign.Center)
          .alignItems(HorizontalAlign.Center)
        }

        // 右下角时长标签
        Row() {
          Text(formatDuration(media.duration))
            .fontSize(11)
            .fontWeight(FontWeight.Medium)
            .fontColor(Color.White)
            .backgroundColor('#80000000')
            .padding({ left: 6, right: 6, top: 2, bottom: 2 })
            .borderRadius(4)
        }
        .width('100%')
        .height('100%')
        .alignItems(VerticalAlign.Bottom)
        .justifyContent(FlexAlign.End)
        .padding(8)
      }
    }
    .width(this.mediaCardWidth(media))
    .height(this.mediaCardHeight(media))
    .borderRadius(T.radius.md)
    .clip(true)
    .margin({ bottom: T.spacing.xs })
    .onClick(() => {
      this.onDispatch(new OpenMediaViewer(messageId));
    })
  }

  /** 回复/编辑预览条（CHAT-004）：accent 竖条 + 标题/摘要 + 取消 X。 */
  @Builder
  ComposerModeBar(mode: ComposerMode) {
    Row() {
      Column()
        .width(3)
        .height(32)
        .backgroundColor(T.colors.accent)
        .borderRadius(T.radius.full)

      Column() {
        Text(mode.kind === 'edit' ? 'Edit Message' : `Reply to ${(mode as ComposerReplyMode).previewTitle}`)
          .fontSize(T.typography.subheadline.fontSize)
          .fontWeight(T.typography.headline.fontWeight)
          .fontColor(T.colors.accent)
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })

        Text(mode.previewText)
          .fontSize(T.typography.footnote.fontSize)
          .fontColor(T.colors.textSecondary)
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
      }
      .alignItems(HorizontalAlign.Start)
      .layoutWeight(1)
      .margin({ left: T.spacing.sm })

      Text('✕')
        .fontSize(T.typography.title.fontSize)
        .fontColor(T.colors.textSecondary)
        .textAlign(TextAlign.Center)
        .width(32)
        .height(32)
        .onClick(() => {
          this.onDispatch(new CancelComposerMode());
        })
    }
    .width('100%')
    .alignItems(VerticalAlign.Center)
    .padding({
      left: T.spacing.screenInset,
      right: T.spacing.screenInset,
      top: T.spacing.xs,
      bottom: T.spacing.xs
    })
    .backgroundColor(T.colors.surfaceVariant)
  }

  /** 长按操作菜单（CHAT-004）：全屏遮罩 + 底部动作面板；可见项已由 reducer 按权限过滤。 */
  @Builder
  ActionMenuSheet(menu: MessageActionMenuState) {
    Stack() {
      Column()
        .width('100%')
        .height('100%')
        .backgroundColor(T.colors.scrim)
        .onClick(() => {
          this.onDispatch(new DismissMessageActionMenu());
        })

      Column() {
        if (menu.showReply) {
          Text('Reply')
            .fontSize(T.typography.body.fontSize)
            .fontColor(T.colors.textPrimary)
            .width('100%')
            .padding({
              left: T.spacing.screenInset,
              right: T.spacing.screenInset,
              top: T.spacing.md,
              bottom: T.spacing.md
            })
            .onClick(() => {
              this.onDispatch(new ReplyToMessage());
            })
        }

        if (menu.showEdit) {
          Text('Edit')
            .fontSize(T.typography.body.fontSize)
            .fontColor(T.colors.textPrimary)
            .width('100%')
            .padding({
              left: T.spacing.screenInset,
              right: T.spacing.screenInset,
              top: T.spacing.md,
              bottom: T.spacing.md
            })
            .onClick(() => {
              this.onDispatch(new EditMessage());
            })
        }

        if (menu.showDelete) {
          Text('Delete')
            .fontSize(T.typography.body.fontSize)
            .fontColor(T.colors.destructive)
            .width('100%')
            .padding({
              left: T.spacing.screenInset,
              right: T.spacing.screenInset,
              top: T.spacing.md,
              bottom: T.spacing.md
            })
            .onClick(() => {
              this.onDispatch(new DeleteMessage());
            })
        }
      }
      .width('100%')
      .backgroundColor(T.colors.surface)
      .borderRadius({ topLeft: T.radius.xl, topRight: T.radius.xl })
      .padding({ top: T.spacing.sm, bottom: T.spacing.lg })
    }
    .width('100%')
    .height('100%')
    .alignContent(Alignment.Bottom)
  }

  /** 全屏多媒体画廊查看器（MEDIA-103 / FEAT-MEDIA-006）。 */
  @Builder
  MediaViewerOverlay() {
    Stack({ alignContent: Alignment.Center }) {
      // 1. 底层：多图 Swiper 翻页与手势缩放
      Swiper(this.swiperController) {
        ForEach(this.uiState.viewerItems, (item: MediaViewerItem) => {
          Stack({ alignContent: Alignment.Center }) {
            if (item.media.kind === 'video') {
              if (item.media.localPath !== null && item.media.isDownloaded) {
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
                  .scale({ x: this.viewerScale, y: this.viewerScale })
              } else {
                Stack({ alignContent: Alignment.Center }) {
                  if (item.media.thumbnailPath !== null) {
                    Image(toSandboxUri(item.media.thumbnailPath))
                      .objectFit(ImageFit.Contain)
                      .width('100%')
                      .height('100%')
                      .scale({ x: this.viewerScale, y: this.viewerScale })
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
                      Text('⬇')
                        .fontSize(24)
                        .fontColor(Color.White)
                      Text('Download Video')
                        .fontSize(12)
                        .fontColor(Color.White)
                        .margin({ top: 6 })
                    }
                  }
                  .padding(16)
                  .borderRadius(16)
                  .backgroundColor('#99000000')
                  .onClick(() => {
                    this.onDispatch(new RequestMediaDownload(item.media.fileId));
                  })
                }
                .width('100%')
                .height('100%')
              }
            } else if (item.media.kind === 'animation' && (item.media.localPath !== null && (item.media.localPath.endsWith('.mp4') || item.media.localPath.indexOf('.mp4') >= 0))) {
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
                .scale({ x: this.viewerScale, y: this.viewerScale })
            } else if (item.media.localPath !== null && item.media.isDownloaded) {
              Image(toSandboxUri(item.media.localPath))
                .objectFit(ImageFit.Contain)
                .width('100%')
                .height('100%')
                .scale({ x: this.viewerScale, y: this.viewerScale })
            } else if (item.media.thumbnailPath !== null) {
              Stack({ alignContent: Alignment.Center }) {
                Image(toSandboxUri(item.media.thumbnailPath))
                  .objectFit(ImageFit.Contain)
                  .width('100%')
                  .height('100%')
                  .blur(8)
                  .scale({ x: this.viewerScale, y: this.viewerScale })

                Column() {
                  LoadingProgress()
                    .width(44)
                    .height(44)
                    .color(Color.White)
                }
                .width(56)
                .height(56)
                .borderRadius(T.radius.full)
                .backgroundColor('#80000000')
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
        }, (item: MediaViewerItem) => `${item.messageId}`)
      }
      .index(this.uiState.activeViewerIndex)
      .onChange((index: number) => {
        if (index !== this.uiState.activeViewerIndex) {
          this.onDispatch(new ChangeViewerIndex(index));
          this.viewerScale = 1.0;
        }
      })
      .disableSwipe(this.viewerScale > 1.05)
      .indicator(false)
      .loop(false)
      .width('100%')
      .height('100%')
      .priorityGesture(
        GestureGroup(
          GestureMode.Parallel,
          PinchGesture({ fingers: 2 })
            .onActionStart(() => {
              this.pinchStartScale = this.viewerScale;
            })
            .onActionUpdate((event: GestureEvent) => {
              let nextScale: number = this.pinchStartScale * event.scale;
              if (nextScale < 0.8) {
                nextScale = 0.8;
              } else if (nextScale > 3.5) {
                nextScale = 3.5;
              }
              this.viewerScale = nextScale;
            })
            .onActionEnd(() => {
              if (this.viewerScale < 1.0) {
                this.viewerScale = 1.0;
              } else if (this.viewerScale > 3.0) {
                this.viewerScale = 3.0;
              }
            }),
          GestureGroup(
            GestureMode.Exclusive,
            TapGesture({ count: 2 })
              .onAction(() => {
                if (this.viewerScale > 1.05) {
                  this.viewerScale = 1.0;
                } else {
                  this.viewerScale = 2.0;
                }
              }),
            TapGesture({ count: 1 })
              .onAction(() => {
                this.viewerBarsVisible = !this.viewerBarsVisible;
              })
          )
        )
      )

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
    .backgroundColor('#000000')
    .hitTestBehavior(HitTestMode.Block)
  }

  @Builder
  ViewerTopBar() {
    Row() {
      Text('‹')
        .fontSize(T.typography.largeTitle.fontSize)
        .fontWeight(T.typography.title.fontWeight)
        .fontColor(Color.White)
        .width(BACK_ARROW_SIZE)
        .height(BACK_ARROW_SIZE)
        .textAlign(TextAlign.Center)
        .onClick(() => {
          this.onDispatch(new CloseMediaViewer());
        })

      Column() {
        Text(this.getViewerTitle())
          .fontSize(T.typography.title.fontSize)
          .fontWeight(T.typography.title.fontWeight)
          .fontColor(Color.White)
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })

        if (this.getViewerSubtitle().length > 0) {
          Text(this.getViewerSubtitle())
            .fontSize(T.typography.caption.fontSize)
            .fontColor('#B3FFFFFF')
            .margin({ top: 2 })
        }
      }
      .layoutWeight(1)
      .alignItems(HorizontalAlign.Start)
      .margin({ left: T.spacing.xs })
    }
    .width('100%')
    .padding({
      left: T.spacing.sm,
      right: T.spacing.md,
      top: 36,
      bottom: T.spacing.sm
    })
    .backgroundColor('#99000000')
  }

  @Builder
  ViewerBottomBar() {
    Column() {
      Scroll() {
        Text(this.getViewerCaption())
          .fontSize(T.typography.body.fontSize)
          .fontColor(Color.White)
          .width('100%')
      }
      .scrollBar(BarState.Off)
      .constraintSize({ maxHeight: 180 })
    }
    .width('100%')
    .padding({
      left: T.spacing.screenInset,
      right: T.spacing.screenInset,
      top: T.spacing.md,
      bottom: 28
    })
    .backgroundColor('#99000000')
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
      Row() {
        TextInput({
          text: this.uiState.composerText,
          placeholder: 'Message'
        })
          .fontSize(T.typography.body.fontSize)
          .fontColor(T.colors.textPrimary)
          .placeholderColor(T.colors.textSecondary)
          .backgroundColor(Color.Transparent)
          .width('100%')
          .height(COMPOSER_INPUT_HEIGHT)
          .padding({ left: T.spacing.lg, right: T.spacing.lg })
          .onChange((value: string) => {
            this.onDispatch(new ComposerTextChanged(value));
          })
          .onSubmit(() => {
            this.dispatchSend();
          })
      }
      .layoutWeight(1)
      .height(COMPOSER_INPUT_HEIGHT)
      .backgroundColor(T.colors.surfaceVariant)
      .borderRadius(T.radius.full)

      Text('↑')
        .fontSize(T.typography.title.fontSize)
        .fontWeight(T.typography.title.fontWeight)
        .fontColor(T.colors.textOnAccent)
        .textAlign(TextAlign.Center)
        .width(SEND_BUTTON_SIZE)
        .height(SEND_BUTTON_SIZE)
        .backgroundColor(this.canSend() ? T.colors.accent : T.colors.disabled)
        .borderRadius(T.radius.full)
        .margin({ left: T.spacing.sm })
        .enabled(this.canSend())
        .onClick(() => {
          this.dispatchSend();
        })
    }
    .width('100%')
    .alignItems(VerticalAlign.Center)
    .padding({
      left: T.spacing.screenInset,
      right: T.spacing.screenInset,
      top: T.spacing.xs,
      bottom: T.spacing.sm
    })
    .borderWidth({ top: 1 })
    .borderColor(T.colors.divider)
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
    return item.senderColorIndex >= 0 ? nameColorForIndex(item.senderColorIndex) : T.colors.accent;
  }

  /** 头像底色：与署名同色调色板取色。 */
  private senderAvatarColor(item: MessageItem): string {
    return item.senderColorIndex >= 0 ? nameColorForIndex(item.senderColorIndex) : T.colors.accent;
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

  private spanFontSize(span: MessageTextSpan): number {
    return span.isCode || span.isPre ? CODE_FONT_SIZE : T.typography.body.fontSize;
  }

  private spanFontFamily(span: MessageTextSpan): string {
    // 'sans-serif' 是 ArkUI 通用族名，解析为系统默认字体，保持与非 code 文本一致。
    return span.isCode || span.isPre ? 'monospace' : 'sans-serif';
  }

  private spanFontColor(span: MessageTextSpan, messageId: number, spanIndex: number): string {
    if (span.isSpoiler && !this.isSpoilerRevealed(messageId, spanIndex)) {
      return SPOILER_MASK_COLOR; // 遮罩态：文字与遮罩同色，内容不可读
    }
    if (span.linkUrl !== null) {
      return T.colors.link;
    }
    if (span.isAccent) {
      return T.colors.accent;
    }
    return T.colors.chatText;
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
      return SPOILER_MASK_COLOR; // 遮罩态深色块
    }
    if (span.isSpoiler || span.isCode || span.isPre) {
      return T.colors.surfaceVariant; // 揭开后 / code 的浅底提示
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
    const hostContext = this.getUIContext().getHostContext();
    if (hostContext === undefined) {
      // 只记失败事件，不记 URL 正文。
      hilog.warn(DOMAIN, TAG, 'openLink failed: no host context');
      return;
    }
    const context = hostContext as common.UIAbilityContext;
    context.openLink(url, { appLinkingOnly: false })
      .then(() => {
      })
      .catch((err: BusinessError) => {
        // 只记失败事件与错误码，不记 URL 正文。
        hilog.warn(DOMAIN, TAG, 'openLink failed: %{public}d', err.code);
      });
  }

  @Builder
  LoadingView() {
    Column() {
      LoadingProgress()
        .width(48)
        .height(48)
        .color(T.colors.accent)
        .margin({ bottom: T.spacing.lg })

      Text('Loading messages...')
        .fontSize(T.typography.body.fontSize)
        .fontColor(T.colors.textSecondary)
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
        .fontSize(T.typography.body.fontSize)
        .fontColor(T.colors.textSecondary)
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
        .fontSize(T.typography.title.fontSize)
        .fontWeight(T.typography.title.fontWeight)
        .fontColor(T.colors.destructive)
        .margin({ bottom: T.spacing.md })

      Text(errorMessage)
        .fontSize(T.typography.footnote.fontSize)
        .fontColor(T.colors.textSecondary)
        .textAlign(TextAlign.Center)
        .margin({
          bottom: T.spacing.xxl,
          left: T.spacing.xxl,
          right: T.spacing.xxl
        })

      Button('Try Again')
        .width('60%')
        .height(44)
        .backgroundColor(T.colors.accent)
        .borderRadius(T.radius.full)
        .onClick(() => {
          this.onDispatch(new LoadInitialMessages());
        })
    }
    .width('100%')
    .layoutWeight(1)
    .justifyContent(FlexAlign.Center)
    .alignItems(HorizontalAlign.Center)
  }
}
