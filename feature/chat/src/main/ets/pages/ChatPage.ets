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
  PickAndSendPhoto
} from '../contract/ChatIntent';
import { isMessageSelected } from '../model/ForwardSelection';

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
/** MSG-106：多选勾选圈直径（vp）。 */
const SELECTION_MARK_SIZE: number = 22;

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

/**
 * 消息行的 LazyForEach key：messageId + 展示相关内容散列
 * （正文/署名/回复摘要/回复缩略图/发送态/已读/编辑标记/多媒体/多选态）。
 *
 * selected 必须参与签名（MSG-106）：多选勾选圈是"同一 messageId 的原地变更"，
 * key 不含它就永远不重渲——这正是 MSG-104 已读勾踩过的坑。
 */
function messageRowKey(item: MessageItem, selected: boolean): string {
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
    mediaSig = `${m.kind}|${m.fileId}|${path}|${thumb}|${m.isDownloaded}|${m.isDownloading}|${Math.round(m.progress * 10)}`;
  }
  const replySig: string =
    `${item.replyToMessageId}|${item.replySenderName}|${item.replySenderColorIndex}|` +
    `${item.replyThumbnailPath !== null ? item.replyThumbnailPath : ''}|${item.replyIsSticker}`;
  const signature: string =
    `${item.sendState}|${item.isRead}|${item.isEdited}|${item.senderColorIndex}|` +
    `${item.text}|${item.senderName}|${item.senderAvatarPath !== null ? item.senderAvatarPath : ''}|` +
    `${item.replyToSummary}|${mediaSig}|${replySig}|${selected}|` +
    `${item.showDateHeader ? item.dateHeaderText : ''}|${item.showUnreadSeparator}`;
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
  /** 标记用户是否已手动滑动过列表；为 false 时新拉取历史保持目标定位。 */
  private hasUserScrolled: boolean = false;
  /** MSG-106：上次渲染的选择集签名，用于在多选态变化时触发列表重载。 */
  private shownSelectionSignature: string = '';

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
    this.dataSource.setItems(this.uiState.messages);
    this.shownMessages = this.uiState.messages;
    this.shownSelectionSignature = this.selectionSignature();
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
    // MSG-106 例外：多选态变化也是"原地变更"，必须重载列表让勾选圈上屏
    // （messages 数组引用不变，但 row key 含 selected，需重新求 key）。
    const selectionSignature: string = this.selectionSignature();
    const selectionChanged: boolean = selectionSignature !== this.shownSelectionSignature;
    const messagesChanged: boolean = messages !== this.shownMessages;
    if (!messagesChanged && !selectionChanged) {
      return;
    }
    if (selectionChanged) {
      this.shownSelectionSignature = selectionSignature;
    }
    if (!messagesChanged) {
      // 只变了选择态：重载数据源让 row key 重算，但不触碰滚动位置，
      // 否则勾选时列表会跳到首条未读/末尾。
      this.dataSource.setItems(messages);
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
    // 首屏出内容 → 定位到首条未读或最新；尾部来了新消息 → 平滑滚到底；
    // 顶部翻页/历史回填时，若用户尚未主动滑动，保持目标定位（未读定位未读，已读定位最新末尾）。
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
    } else if (!this.hasUserScrolled && count > 0) {
      const targetIdx: number = this.computeScrollTargetIndex(messages);
      const align: ScrollAlign = (targetIdx === count - 1) ? ScrollAlign.END : ScrollAlign.START;
      setTimeout(() => {
        this.scroller.scrollToIndex(targetIdx, false, align);
      }, 50);
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
            }, (item: MessageItem) => messageRowKey(item, this.isSelected(item.messageId)))
          }
          .width('100%')
          .layoutWeight(1)
          .cachedCount(5)
          .scrollBar(BarState.Off)
          .onTouch((event: TouchEvent) => {
            if (event.type === TouchType.Down || event.type === TouchType.Move) {
              this.hasUserScrolled = true;
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
        // MSG-106：多选态下不显示输入相关 UI（对齐 Telegram X 的选择态）。
        if (this.uiState.composerMode !== null && !this.uiState.selectionMode) {
          this.ComposerModeBar(this.uiState.composerMode)
        }

        if (!this.uiState.selectionMode) {
          this.ComposerBar()
        }
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
      if (this.uiState.selectionMode) {
        // MSG-106 多选态顶栏：Cancel + "N selected" + Forward
        Text('Cancel')
          .fontSize(T.typography.body.fontSize)
          .fontColor(T.colors.accent)
          .padding({ left: T.spacing.sm, right: T.spacing.sm })
          .onClick(() => {
            this.onDispatch(new ExitMessageSelection());
          })

        Text(`${this.uiState.selectedMessageIds.length} selected`)
          .fontSize(T.typography.title.fontSize)
          .fontWeight(T.typography.title.fontWeight)
          .fontColor(T.colors.textPrimary)
          .textAlign(TextAlign.Center)
          .layoutWeight(1)

        Text('Forward')
          .fontSize(T.typography.body.fontSize)
          .fontWeight(FontWeight.Medium)
          .fontColor(this.uiState.selectedMessageIds.length > 0 ? T.colors.accent : T.colors.textSecondary)
          .padding({ left: T.spacing.sm, right: T.spacing.sm })
          .onClick(() => {
            this.onDispatch(new ConfirmForwardSelection());
          })
      } else {
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

  /** MSG-103：日期胶囊头（居中展示半透明灰色胶囊卡片，如 9月11日 或 2024年9月11日）。 */
  @Builder
  DateHeader(dateText: string) {
    Row() {
      Text(dateText)
        .fontSize(12)
        .fontWeight(FontWeight.Medium)
        .fontColor('#FFFFFFFF')
        .backgroundColor('#4D000000')
        .borderRadius(T.radius.full)
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
        .fontColor(T.colors.accent)

      Text(' ∨')
        .fontSize(13)
        .fontWeight(FontWeight.Bold)
        .fontColor(T.colors.accent)
    }
    .width('100%')
    .height(32)
    .backgroundColor('#E8EEF5')
    .borderWidth({ top: 0.5, bottom: 0.5 })
    .borderColor(T.colors.divider)
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
      if (this.showSenderUi(item)) {
        if (item.senderAvatarPath !== null && item.senderAvatarPath.length > 0) {
          Image(toSandboxUri(item.senderAvatarPath))
            .width(SENDER_AVATAR_SIZE)
            .height(SENDER_AVATAR_SIZE)
            .borderRadius(T.radius.full)
            .objectFit(ImageFit.Cover)
            .margin({ right: T.spacing.xs })
        } else {
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
            .alignSelf(ItemAlign.Start)
            .margin({ bottom: T.spacing.hairline })
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
          .alignSelf(ItemAlign.Start)
          .fontSize(T.typography.body.fontSize)
          .fontColor(T.colors.chatText)
          .margin(item.media !== null ? { top: T.spacing.xs } : { top: 0 })
        } else if (item.text.length > 0) {
          Text(item.text)
            .alignSelf(ItemAlign.Start)
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
    .justifyContent(item.isOutgoing ? FlexAlign.End : FlexAlign.Start)
    .alignItems(VerticalAlign.Bottom)
    .padding({
      left: T.spacing.screenInset,
      right: T.spacing.screenInset,
      top: T.spacing.xs
    })
    }
    .width('100%')
  }

  /** MSG-106：一条消息的勾选圈（选中实心 + ✓，未选中空心）。 */
  @Builder
  SelectionMark(item: MessageItem) {
    Text(this.isSelected(item.messageId) ? '✓' : '')
      .width(SELECTION_MARK_SIZE)
      .height(SELECTION_MARK_SIZE)
      .borderRadius(T.radius.full)
      .borderWidth(1)
      .borderColor(this.isSelected(item.messageId) ? T.colors.accent : T.colors.textSecondary)
      .backgroundColor(this.isSelected(item.messageId) ? T.colors.accent : Color.Transparent)
      .fontColor(T.colors.textOnAccent)
      .fontSize(T.typography.footnote.fontSize)
      .textAlign(TextAlign.Center)
      .margin({ left: T.spacing.xs, right: T.spacing.xs })
      .onClick(() => {
        this.onDispatch(new ToggleMessageSelection(item.messageId));
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
                  Text('🖼️')
                    .fontSize(20)
                }
                .width('100%')
                .height('100%')
                .justifyContent(FlexAlign.Center)
                .alignItems(HorizontalAlign.Center)
                .backgroundColor(T.colors.surfaceVariant)
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
                  .borderRadius(T.radius.full)
                  .backgroundColor('#80000000')
                  .justifyContent(FlexAlign.Center)
                  .alignItems(HorizontalAlign.Center)
                } else {
                  Column() {
                    Text('⬇')
                      .fontSize(16)
                      .fontColor(Color.White)
                  }
                  .width(32)
                  .height(32)
                  .borderRadius(T.radius.full)
                  .backgroundColor('#80000000')
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
                    .backgroundColor('#80000000')
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
              topLeft: geom.needTopLeftRound ? T.radius.md : 0,
              topRight: geom.needTopRightRound ? T.radius.md : 0,
              bottomLeft: geom.needBottomLeftRound ? T.radius.md : 0,
              bottomRight: geom.needBottomRightRound ? T.radius.md : 0
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
    .margin({ bottom: item.text.length > 0 ? T.spacing.xs : 0 })
  }

  /** 多媒体气泡渲染（MEDIA-101 / MEDIA-105）：图片/视频/GIF 动图。 */
  @Builder
  MediaBubble(media: MediaAttachment, messageId: number) {
    Stack({ alignContent: Alignment.Center }) {
      // 1. 底图 / 缩略图 / 占位 / 动图视频
      if (media.localPath !== null && (media.isDownloaded || media.isUploading)) {
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
        if (media.isUploading) {
          Column() {
            LoadingProgress()
              .width(36)
              .height(36)
              .color(Color.White)
            if (media.uploadProgress > 0 && media.uploadProgress < 1) {
              Text(`${Math.round(media.uploadProgress * 100)}%`)
                .fontSize(11)
                .fontColor(Color.White)
                .margin({ top: 4 })
            }
          }
          .width(56)
          .height(56)
          .borderRadius(T.radius.full)
          .backgroundColor('#80000000')
          .justifyContent(FlexAlign.Center)
          .alignItems(HorizontalAlign.Center)
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
          .fontColor(T.colors.textSecondary)
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
    .margin({ bottom: T.spacing.xs })
    .onClick(() => {
      if (item.replyToMessageId !== null) {
        this.scrollToMessageId(item.replyToMessageId);
      }
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

        // MSG-105：复制文本到系统剪贴板（对齐 Telegram X 菜单顺序：Reply → Copy → Copy Link → Forward → Edit → Delete）。
        if (menu.showCopy) {
          Text('Copy')
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
              this.onDispatch(new CopyMessageText());
            })
        }

        // MSG-105：复制消息中的链接到系统剪贴板。
        if (menu.showCopyLink) {
          Text('Copy Link')
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
              this.onDispatch(new CopyMessageLink());
            })
        }

        // MSG-106：Forward 进入多选转发态（仅 can_be_forwarded 时出现）。
        if (menu.showForward) {
          Text('Forward')
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
              this.onDispatch(new ForwardMessagesRequested());
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
      // MEDIA-102：相册选图发送按钮
      Text('📎')
        .fontSize(20)
        .fontColor(T.colors.textSecondary)
        .textAlign(TextAlign.Center)
        .width(COMPOSER_INPUT_HEIGHT)
        .height(COMPOSER_INPUT_HEIGHT)
        .margin({ right: T.spacing.xs })
        .onClick(() => {
          this.onDispatch(new PickAndSendPhoto());
        })

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

  /** 回复引用左侧竖条与发件人昵称颜色：取发送者同款调色板，-1 兜底 accent。 */
  private replyLineColor(item: MessageItem): string {
    return item.replySenderColorIndex >= 0 ? nameColorForIndex(item.replySenderColorIndex) : T.colors.accent;
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
    let targetUrl: string = url.trim();
    if (targetUrl.length === 0) {
      return;
    }
    // MSG-105：协议前缀容错（若既无 :// 且非 mailto:/tel:，自动补全 https://）
    if (!targetUrl.includes('://') && !targetUrl.startsWith('mailto:') && !targetUrl.startsWith('tel:')) {
      targetUrl = 'https://' + targetUrl;
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
