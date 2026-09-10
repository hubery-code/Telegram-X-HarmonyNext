/**
 * feature/chat — ChatPage：单会话消息页（CHAT-001 + CHAT-002 基础）。
 *
 * 顶部：返回箭头 + 会话标题；主体：LazyForEach 消息气泡列表（最旧在前、
 * 最新在底，首屏/新消息自动滚到底）；文本气泡：发出的右对齐 chatOutgoing、
 * 收到的左对齐 chatIncoming，时间戳 HH:mm；滚动到顶 onReachStart 翻更早历史；
 * 空/加载/错误三态。全部色彩/字号/间距用 design_system token，不硬编码。
 */

import { LightTheme } from '@tgx/core-design-system';
import { MessageItem } from '../model/MessageItem';
import { ChatUiState } from '../contract/ChatUiState';
import { LoadInitialMessages, LoadOlderMessages, BackToChatList } from '../contract/ChatIntent';

const T = LightTheme;

const BUBBLE_MAX_WIDTH: string = '78%';
const BACK_ARROW_SIZE: number = 44;

function pad2(value: number): string {
  return value < 10 ? `0${value}` : `${value}`;
}

/** 消息气泡内时间戳：HH:mm。 */
function formatMessageTime(timestampMs: number): string {
  const date: Date = new Date(timestampMs);
  return `${pad2(date.getHours())}:${pad2(date.getMinutes())}`;
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
  private shownCount: number = 0;
  private lastTailMessageId: number = 0;

  aboutToAppear(): void {
    this.dataSource.setItems(this.uiState.messages);
    this.shownCount = this.uiState.messages.length;
    if (this.shownCount > 0) {
      this.lastTailMessageId = this.uiState.messages[this.shownCount - 1].messageId;
    }
  }

  onUiStateChanged(): void {
    const count: number = this.uiState.messages.length;
    const tailId: number = count > 0 ? this.uiState.messages[count - 1].messageId : 0;
    const firstContent: boolean = this.shownCount === 0 && count > 0;
    const grewAtTail: boolean = count > 0 && tailId !== this.lastTailMessageId;
    this.dataSource.setItems(this.uiState.messages);
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
        Text(item.text)
          .fontSize(T.typography.body.fontSize)
          .fontColor(T.colors.chatText)

        Text(formatMessageTime(item.timestampMs))
          .fontSize(T.typography.caption.fontSize)
          .fontColor(T.colors.textSecondary)
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
    }
    .width('100%')
    .justifyContent(item.isOutgoing ? FlexAlign.End : FlexAlign.Start)
    .padding({
      left: T.spacing.screenInset,
      right: T.spacing.screenInset,
      top: T.spacing.xs
    })
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
