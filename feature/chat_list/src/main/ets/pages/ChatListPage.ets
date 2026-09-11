/**
 * feature/chat_list — ChatListPage：会话列表页（CHATLIST-002）。
 *
 * LazyForEach 懒加载列表，每行：头像占位（色板圆 + 首字母）、标题、
 * 最后一条消息预览（单行截断）、时间戳、未读徽标（>99 显示 99+）。
 * 支持下拉刷新（RefreshChats）、点击行（ChatSelected）、空/加载/错误三态。
 * 全部色彩/字号/间距用 design_system token，不硬编码。
 */

import { LightTheme } from '@tgx/core-design-system';
import { ChatListItem } from '../model/ChatListItem';
import { ChatListUiState } from '../contract/ChatListUiState';
import { LoadChats, RefreshChats, ChatSelected } from '../contract/ChatListIntent';

const T = LightTheme;

const AVATAR_SIZE: number = 52;
const BADGE_HEIGHT: number = 20;
const ONE_DAY_MS: number = 24 * 60 * 60 * 1000;
const WEEKDAY_NAMES: string[] = ['Sun', 'Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat'];

function pad2(value: number): string {
  return value < 10 ? `0${value}` : `${value}`;
}

/** 当天显示 HH:mm，一周内显示星期，更早显示 dd.MM.yyyy。 */
function formatChatTimestamp(timestampMs: number): string {
  const date: Date = new Date(timestampMs);
  const now: Date = new Date();
  const sameDay: boolean = date.getFullYear() === now.getFullYear() &&
    date.getMonth() === now.getMonth() &&
    date.getDate() === now.getDate();
  if (sameDay) {
    return `${pad2(date.getHours())}:${pad2(date.getMinutes())}`;
  }
  if (now.getTime() - timestampMs < 7 * ONE_DAY_MS) {
    return WEEKDAY_NAMES[date.getDay()];
  }
  return `${pad2(date.getDate())}.${pad2(date.getMonth() + 1)}.${date.getFullYear()}`;
}

/**
 * FNV-1a 32 位字符串散列：给 LazyForEach keyGenerator 用。
 * key 不变 LazyForEach 会复用行组件不重渲染——只按 chatId 做 key 时，
 * 预览文本/未读数/时间戳等原地变更不上屏（与聊天页 MSG-104 同因）。
 */
function fnv1a32(input: string): string {
  let hash: number = 0x811c9dc5;
  for (let i = 0; i < input.length; i++) {
    hash ^= input.charCodeAt(i) & 0xff;
    hash = Math.imul(hash, 0x01000193);
  }
  return (hash >>> 0).toString(16);
}

/** 会话行的 LazyForEach key：chatId + 展示相关内容散列（标题/预览/未读数/时间戳）。 */
function chatRowKey(item: ChatListItem): string {
  const signature: string =
    `${item.title}|${item.lastMessagePreview}|${item.unreadCount}|${item.timestampMs}`;
  return `${item.chatId}:${fnv1a32(signature)}`;
}

/** LazyForEach 数据源：整体替换 items 并触发全量刷新。 */
export class ChatListDataSource implements IDataSource {
  private items: ChatListItem[] = [];
  private listeners: DataChangeListener[] = [];

  totalCount(): number {
    return this.items.length;
  }

  getData(index: number): ChatListItem {
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

  setItems(items: readonly ChatListItem[]): void {
    this.items = items.slice(0);
    this.listeners.forEach((listener: DataChangeListener) => {
      listener.onDataReloaded();
    });
  }
}

@Component
export struct ChatListPage {
  @Prop @Watch('onUiStateChanged') uiState: ChatListUiState = ChatListUiState.initial();

  onDispatch: (intent: Object) => void = () => {};

  @State private isRefreshing: boolean = false;
  private dataSource: ChatListDataSource = new ChatListDataSource();

  aboutToAppear(): void {
    this.dataSource.setItems(this.uiState.items);
    if (this.uiState.items.length === 0 && !this.uiState.isLoading && this.uiState.errorMessage === null) {
      this.onDispatch(new LoadChats());
    }
  }

  onUiStateChanged(): void {
    this.dataSource.setItems(this.uiState.items);
    if (!this.uiState.isLoading) {
      this.isRefreshing = false;
    }
  }

  build() {
    Column() {
      Row() {
        Text('Chats')
          .fontSize(T.typography.largeTitle.fontSize)
          .fontWeight(T.typography.largeTitle.fontWeight)
          .fontColor(T.colors.textPrimary)
      }
      .width('100%')
      .padding({
        left: T.spacing.screenInset,
        right: T.spacing.screenInset,
        top: T.spacing.lg,
        bottom: T.spacing.md
      })

      if (this.uiState.errorMessage !== null && this.uiState.items.length === 0) {
        this.ErrorView(this.uiState.errorMessage)
      } else if (this.uiState.isLoading && this.uiState.items.length === 0) {
        this.LoadingView()
      } else if (this.uiState.items.length === 0) {
        this.EmptyView()
      } else {
        Refresh({ refreshing: $$this.isRefreshing }) {
          List() {
            LazyForEach(this.dataSource, (item: ChatListItem) => {
              ListItem() {
                this.ChatRow(item)
              }
            }, (item: ChatListItem) => chatRowKey(item))
          }
          .width('100%')
          .height('100%')
          .cachedCount(5)
          .scrollBar(BarState.Off)
          .divider({
            strokeWidth: 1,
            color: T.colors.divider,
            startMargin: T.spacing.screenInset + AVATAR_SIZE + T.spacing.md,
            endMargin: T.spacing.none
          })
        }
        .layoutWeight(1)
        .onRefreshing(() => {
          if (this.uiState.isLoading) {
            this.isRefreshing = false;
            return;
          }
          this.onDispatch(new RefreshChats());
        })
      }
    }
    .width('100%')
    .height('100%')
    .backgroundColor(T.colors.background)
  }

  @Builder
  ChatRow(item: ChatListItem) {
    Row() {
      Text(item.avatarLetter)
        .width(AVATAR_SIZE)
        .height(AVATAR_SIZE)
        .borderRadius(T.radius.full)
        .backgroundColor(item.avatarColor)
        .fontColor(T.colors.textOnAccent)
        .fontSize(T.typography.title.fontSize)
        .fontWeight(T.typography.title.fontWeight)
        .textAlign(TextAlign.Center)
        .margin({ right: T.spacing.md })

      Column() {
        Row() {
          Text(item.title)
            .fontSize(T.typography.headline.fontSize)
            .fontWeight(T.typography.headline.fontWeight)
            .fontColor(T.colors.textPrimary)
            .maxLines(1)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
            .layoutWeight(1)

          Text(formatChatTimestamp(item.timestampMs))
            .fontSize(T.typography.footnote.fontSize)
            .fontColor(T.colors.textSecondary)
            .margin({ left: T.spacing.sm })
        }
        .width('100%')
        .margin({ bottom: T.spacing.xs })

        Row() {
          Text(item.lastMessagePreview)
            .fontSize(T.typography.subheadline.fontSize)
            .fontColor(T.colors.textSecondary)
            .maxLines(1)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
            .layoutWeight(1)

          if (item.unreadCount > 0) {
            Text(item.unreadCount > 99 ? '99+' : `${item.unreadCount}`)
              .fontSize(T.typography.caption.fontSize)
              .fontWeight(T.typography.headline.fontWeight)
              .fontColor(T.colors.textOnAccent)
              .backgroundColor(T.colors.accent)
              .borderRadius(T.radius.full)
              .height(BADGE_HEIGHT)
              .constraintSize({ minWidth: BADGE_HEIGHT })
              .padding({ left: T.spacing.xs + T.spacing.hairline, right: T.spacing.xs + T.spacing.hairline })
              .textAlign(TextAlign.Center)
              .margin({ left: T.spacing.sm })
          }
        }
        .width('100%')
      }
      .layoutWeight(1)
      .alignItems(HorizontalAlign.Start)
    }
    .width('100%')
    .padding({
      left: T.spacing.screenInset,
      right: T.spacing.screenInset,
      top: T.spacing.md,
      bottom: T.spacing.md
    })
    .onClick(() => {
      this.onDispatch(new ChatSelected(item.chatId));
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

      Text('Loading chats...')
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
      Text('No chats yet')
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
      Text('Failed to load chats')
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
          this.onDispatch(new LoadChats());
        })
    }
    .width('100%')
    .layoutWeight(1)
    .justifyContent(FlexAlign.Center)
    .alignItems(HorizontalAlign.Center)
  }
}
