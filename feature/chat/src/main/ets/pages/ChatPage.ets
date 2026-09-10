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
 */

import { LightTheme } from '@tgx/core-design-system';
import { MessageItem } from '../model/MessageItem';
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
  DismissMessageActionMenu
} from '../contract/ChatIntent';

const T = LightTheme;

const BUBBLE_MAX_WIDTH: string = '78%';
const BACK_ARROW_SIZE: number = 44;
const COMPOSER_INPUT_HEIGHT: number = 40;
const SEND_BUTTON_SIZE: number = 40;

function pad2(value: number): string {
  return value < 10 ? `0${value}` : `${value}`;
}

/** 消息气泡内时间戳：HH:mm。 */
function formatMessageTime(timestampMs: number): string {
  const date: Date = new Date(timestampMs);
  return `${pad2(date.getHours())}:${pad2(date.getMinutes())}`;
}

/** 气泡时间戳 + 发送状态：pending 附 "…"，failed 只显 "!"；pending 消息 date 可能为 0。 */
function formatMessageStatus(item: MessageItem): string {
  if (item.sendState === 'pending') {
    return item.timestampMs > 0 ? `${formatMessageTime(item.timestampMs)} …` : '…';
  }
  if (item.sendState === 'failed') {
    return '!';
  }
  const time: string = formatMessageTime(item.timestampMs);
  return item.isEdited ? `${time} edited` : time;
}

/** LazyForEach 数据源：整体替换 items 并触发全量刷新。 */
export class MessageListDataSource implements IDataSource {
  private items: MessageItem[] = [];
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

@Component
export struct ChatPage {
  @Prop @Watch('onUiStateChanged') uiState: ChatUiState = ChatUiState.initial();

  onDispatch: (intent: Object) => void = () => {};

  private dataSource: MessageListDataSource = new MessageListDataSource();
  private scroller: Scroller = new Scroller();
  private shownMessages: readonly MessageItem[] = [];
  private shownCount: number = 0;
  private lastTailMessageId: number = 0;

  aboutToAppear(): void {
    this.dataSource.setItems(this.uiState.messages);
    this.shownMessages = this.uiState.messages;
    this.shownCount = this.uiState.messages.length;
    if (this.shownCount > 0) {
      this.lastTailMessageId = this.uiState.messages[this.shownCount - 1].messageId;
    }
  }

  onUiStateChanged(): void {
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
    // 首屏出内容或尾部来了新消息 → 滚到底；顶部翻页（前插）不打断阅读位置。
    if (firstContent || grewAtTail) {
      setTimeout(() => {
        this.scroller.scrollToIndex(count - 1, !firstContent);
      }, 0);
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

          List({ scroller: this.scroller }) {
            LazyForEach(this.dataSource, (item: MessageItem) => {
              ListItem() {
                this.MessageRow(item)
              }
            }, (item: MessageItem) => `${item.messageId}`)
          }
          .width('100%')
          .layoutWeight(1)
          .cachedCount(5)
          .scrollBar(BarState.Off)
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
      Column() {
        // 回复引用行（CHAT-004）：原消息不在当前列表时摘要退化为占位文案。
        if (item.replyToMessageId !== null) {
          Text(item.replyToSummary.length > 0 ? `↪ ${item.replyToSummary}` : '↪ message')
            .fontSize(T.typography.caption.fontSize)
            .fontColor(T.colors.textSecondary)
            .maxLines(1)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
            .margin({ bottom: T.spacing.hairline })
        }

        Text(item.text)
          .fontSize(T.typography.body.fontSize)
          .fontColor(T.colors.chatText)

        Text(formatMessageStatus(item))
          .fontSize(T.typography.caption.fontSize)
          .fontColor(item.sendState === 'failed' ? T.colors.destructive : T.colors.textSecondary)
          .margin({ top: T.spacing.hairline })
      }
      .alignItems(HorizontalAlign.End)
      .backgroundColor(item.isOutgoing ? T.colors.chatOutgoing : T.colors.chatIncoming)
      .borderRadius(T.radius.lg)
      .padding({
        left: T.spacing.md,
        right: T.spacing.md,
        top: T.spacing.sm,
        bottom: T.spacing.xs
      })
      .constraintSize({ maxWidth: BUBBLE_MAX_WIDTH })
      .gesture(
        LongPressGesture({ duration: 350 })
          .onAction(() => {
            this.onDispatch(new MessageActionRequested(item.messageId));
          })
      )
    }
    .width('100%')
    .justifyContent(item.isOutgoing ? FlexAlign.End : FlexAlign.Start)
    .padding({
      left: T.spacing.screenInset,
      right: T.spacing.screenInset,
      top: T.spacing.xs
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
