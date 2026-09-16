/**
 * feature/chat_list — ChatListPage：会话列表页（CHATLIST-002 + MSG-108）。
 *
 * LazyForEach 懒加载列表，每行：头像占位（色板圆 + 首字母）、标题、
 * 最后一条消息预览（单行截断）、时间戳、未读徽标（>99 显示 99+）。
 * 支持下拉刷新（RefreshChats）、点击行（ChatSelected）、空/加载/错误三态。
 * header 右侧齿轮按钮经 onOpenSettings 回调打开设置页（INTEG-001，纯导航，
 * 不经 reducer）。全部色彩/字号/间距用 design_system token，不硬编码。
 *
 * MSG-108：长按行出操作菜单（Pin/Unpin、Mark as read/unread，文案由 reducer
 * 按当前状态定稿）。置顶行在时间戳左侧出置顶标；手动标未读且未读数为 0 时
 * 未读徽标退化为圆点（标未读不产生未读消息数）。
 *
 * INTEG-002：header 下方加搜索入口（可点行，样式像输入框），经 onOpenSearch
 * 回调交给装配层切到 SearchPage——本页不做内联搜索。
 */

import { LightTheme } from '@tgx/core-design-system';
import { ChatListItem } from '../model/ChatListItem';
import { ChatListUiState, ChatActionMenuState } from '../contract/ChatListUiState';
import {
  LoadChats,
  RefreshChats,
  ChatSelected,
  ChatActionRequested,
  ToggleChatPinned,
  ToggleChatMarkedUnread,
  ToggleChatArchived,
  OpenArchivedChats,
  CloseArchivedChats,
  DismissChatActionMenu
} from '../contract/ChatListIntent';

const T = LightTheme;

const AVATAR_SIZE: number = 52;
const BADGE_HEIGHT: number = 20;
const SETTINGS_BUTTON_SIZE: number = 44;
/** INTEG-002：搜索入口行高（vp）。 */
const SEARCH_BAR_HEIGHT: number = 40;
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

function toSandboxUri(path: string | null): string {
  if (path === null || path.length === 0) {
    return '';
  }
  if (path.startsWith('file://')) {
    return path;
  }
  return 'file://' + path;
}

/**
 * 会话行的 LazyForEach key：chatId + 展示相关内容散列
 * （标题/预览/未读数/时间戳/置顶态/手动未读标记/头像路径）。
 *
 * MSG-108：置顶标与未读圆点都是"同一 chatId 的原地变更"（置顶时 chatId 不变），
 * 必须进 key 才会重渲——与 MSG-104 已读勾/ MSG-106 勾选圈同源的坑。
 * 注意置顶导致的**重排序**由 items 顺序变化驱动，不依赖 key。
 */
function chatRowKey(item: ChatListItem): string {
  const signature: string =
    `${item.title}|${item.lastMessagePreview}|${item.unreadCount}|${item.timestampMs}|` +
    `${item.isPinned}|${item.isMarkedAsUnread}|${item.avatarPath !== null ? item.avatarPath : ''}|${item.draftText !== null ? item.draftText : ''}`;
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

  /** 打开设置页（纯导航回调，由装配层接线）。 */
  onOpenSettings: () => void = () => {};

  /** INTEG-002：打开搜索页（纯导航回调，由装配层接线）。 */
  onOpenSearch: () => void = () => {};

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
    Stack() {
      Column() {
        if (this.uiState.listKind === 'archive') {
          // CHAT-003：归档列表顶部导航栏（返回按钮 + 标题）
          Row() {
            Text('←')
              .fontSize(T.typography.largeTitle.fontSize)
              .fontWeight(T.typography.title.fontWeight)
              .fontColor(T.colors.accent)
              .width(SETTINGS_BUTTON_SIZE)
              .height(SETTINGS_BUTTON_SIZE)
              .textAlign(TextAlign.Center)
              .margin({ right: T.spacing.sm })
              .onClick(() => {
                this.onDispatch(new CloseArchivedChats());
              })

            Text('Archived Chats')
              .fontSize(T.typography.largeTitle.fontSize)
              .fontWeight(T.typography.largeTitle.fontWeight)
              .fontColor(T.colors.textPrimary)
              .layoutWeight(1)
          }
          .width('100%')
          .alignItems(VerticalAlign.Center)
          .padding({
            left: T.spacing.screenInset,
            right: T.spacing.screenInset,
            top: T.spacing.lg,
            bottom: T.spacing.md
          })
        } else {
          Row() {
            Text('Chats')
              .fontSize(T.typography.largeTitle.fontSize)
              .fontWeight(T.typography.largeTitle.fontWeight)
              .fontColor(T.colors.textPrimary)
              .layoutWeight(1)

            Text('⚙')
              .fontSize(T.typography.largeTitle.fontSize)
              .fontWeight(T.typography.title.fontWeight)
              .fontColor(T.colors.accent)
              .width(SETTINGS_BUTTON_SIZE)
              .height(SETTINGS_BUTTON_SIZE)
              .textAlign(TextAlign.Center)
              .onClick(() => {
                this.onOpenSettings();
              })
          }
          .width('100%')
          .alignItems(VerticalAlign.Center)
          .padding({
            left: T.spacing.screenInset,
            right: T.spacing.screenInset,
            top: T.spacing.lg,
            bottom: T.spacing.md
          })

          // INTEG-002：搜索入口。
          Row() {
            Text('🔍')
              .fontSize(T.typography.subheadline.fontSize)
              .margin({ right: T.spacing.xs })

            Text('Search')
              .fontSize(T.typography.body.fontSize)
              .fontColor(T.colors.textSecondary)
              .layoutWeight(1)
          }
          .width('100%')
          .height(SEARCH_BAR_HEIGHT)
          .alignItems(VerticalAlign.Center)
          .padding({ left: T.spacing.md, right: T.spacing.md })
          .backgroundColor(T.colors.surfaceVariant)
          .borderRadius(T.radius.md)
          .margin({
            left: T.spacing.screenInset,
            right: T.spacing.screenInset,
            bottom: T.spacing.sm
          })
          .onClick(() => {
            this.onOpenSearch();
          })
        }

        // MSG-108：置顶/标未读失败的错误细条（不挡列表）。
        if (this.uiState.errorMessage !== null && this.uiState.items.length > 0) {
          Text(this.uiState.errorMessage)
            .fontSize(T.typography.footnote.fontSize)
            .fontColor(T.colors.destructive)
            .maxLines(1)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
            .width('100%')
            .padding({
              left: T.spacing.screenInset,
              right: T.spacing.screenInset,
              bottom: T.spacing.xs
            })
        }

        if (this.uiState.errorMessage !== null && this.uiState.items.length === 0) {
          this.ErrorView(this.uiState.errorMessage)
        } else if (this.uiState.isLoading && this.uiState.items.length === 0) {
          this.LoadingView()
        } else if (this.uiState.items.length === 0) {
          this.EmptyView()
        } else {
          Refresh({ refreshing: $$this.isRefreshing }) {
            List() {
              // CHAT-003：主列表中且存在归档会话时，顶部展示归档区入口行
              if (this.uiState.listKind === 'main' && (this.uiState.archiveChatCount > 0 || this.uiState.archiveUnreadCount > 0)) {
                ListItem() {
                  this.ArchivedChatsRow()
                }
              }

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

      // MSG-108：长按会话行的操作菜单（遮罩 + 底部动作面板）。
      if (this.uiState.actionMenu !== null) {
        this.ChatActionSheet(this.uiState.actionMenu)
      }
    }
    .width('100%')
    .height('100%')
    .backgroundColor(T.colors.background)
  }

  /**
   * CHAT-003：主列表顶部的归档区入口行。
   */
  @Builder
  ArchivedChatsRow() {
    Row() {
      Text('🗄️')
        .width(AVATAR_SIZE)
        .height(AVATAR_SIZE)
        .borderRadius(T.radius.full)
        .backgroundColor(T.colors.surfaceVariant)
        .fontSize(T.typography.title.fontSize)
        .textAlign(TextAlign.Center)
        .margin({ right: T.spacing.md })

      Column() {
        Row() {
          Text('Archived Chats')
            .fontSize(T.typography.headline.fontSize)
            .fontWeight(T.typography.headline.fontWeight)
            .fontColor(T.colors.textPrimary)
            .layoutWeight(1)

          if (this.uiState.archiveUnreadCount > 0) {
            Text(this.uiState.archiveUnreadCount > 99 ? '99+' : `${this.uiState.archiveUnreadCount}`)
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
        .margin({ bottom: T.spacing.xs })

        Row() {
          Text(this.uiState.archiveChatCount > 0 ? `${this.uiState.archiveChatCount} chats` : 'Archived chats')
            .fontSize(T.typography.subheadline.fontSize)
            .fontColor(T.colors.textSecondary)
            .maxLines(1)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
            .layoutWeight(1)
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
      this.onDispatch(new OpenArchivedChats());
    })
  }

  /**
   * MSG-108 / CHAT-003：单会话操作菜单。
   * 项与文案对齐 Android ChatsController 单会话菜单：
   * Pin/Unpin + Mark as read/unread + Archive/Unarchive。
   */
  @Builder
  ChatActionSheet(menu: ChatActionMenuState) {
    Stack() {
      Column()
        .width('100%')
        .height('100%')
        .backgroundColor(T.colors.scrim)
        .onClick(() => {
          this.onDispatch(new DismissChatActionMenu());
        })

      Column() {
        Text(menu.title)
          .fontSize(T.typography.footnote.fontSize)
          .fontColor(T.colors.textSecondary)
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
          .width('100%')
          .padding({
            left: T.spacing.screenInset,
            right: T.spacing.screenInset,
            top: T.spacing.md,
            bottom: T.spacing.xs
          })

        Text(menu.isPinned ? 'Unpin' : 'Pin')
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
            this.onDispatch(new ToggleChatPinned());
          })

        Text(menu.canMarkAsRead ? 'Mark as read' : 'Mark as unread')
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
            this.onDispatch(new ToggleChatMarkedUnread());
          })

        Text(menu.isArchived ? 'Unarchive' : 'Archive')
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
            this.onDispatch(new ToggleChatArchived());
          })
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

  @Builder
  ChatRow(item: ChatListItem) {
    Row() {
      if (item.avatarPath !== null && item.avatarPath.length > 0) {
        Image(toSandboxUri(item.avatarPath))
          .width(AVATAR_SIZE)
          .height(AVATAR_SIZE)
          .borderRadius(T.radius.full)
          .objectFit(ImageFit.Cover)
          .margin({ right: T.spacing.md })
      } else {
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
      }

      Column() {
        Row() {
          Text(item.title)
            .fontSize(T.typography.headline.fontSize)
            .fontWeight(T.typography.headline.fontWeight)
            .fontColor(T.colors.textPrimary)
            .maxLines(1)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
            .layoutWeight(1)

          // MSG-108：置顶标（时间戳左侧，对齐 Telegram X 的位置）。
          if (item.isPinned) {
            Text('📌')
              .fontSize(T.typography.caption.fontSize)
              .margin({ left: T.spacing.sm })
          }

          Text(formatChatTimestamp(item.timestampMs))
            .fontSize(T.typography.footnote.fontSize)
            .fontColor(T.colors.textSecondary)
            .margin({ left: T.spacing.sm })
        }
        .width('100%')
        .margin({ bottom: T.spacing.xs })

        Row() {
          if (item.draftText !== null && item.draftText.length > 0) {
            Text('Draft: ')
              .fontSize(T.typography.subheadline.fontSize)
              .fontWeight(T.typography.headline.fontWeight)
              .fontColor(T.colors.destructive)

            Text(item.draftText)
              .fontSize(T.typography.subheadline.fontSize)
              .fontColor(T.colors.textSecondary)
              .maxLines(1)
              .textOverflow({ overflow: TextOverflow.Ellipsis })
              .layoutWeight(1)
          } else {
            Text(item.lastMessagePreview)
              .fontSize(T.typography.subheadline.fontSize)
              .fontColor(T.colors.textSecondary)
              .maxLines(1)
              .textOverflow({ overflow: TextOverflow.Ellipsis })
              .layoutWeight(1)
          }

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
          } else if (item.isMarkedAsUnread) {
            // MSG-108：手动标未读但不含未读消息 → 实心圆点（标未读不产生未读数）。
            Text('')
              .width(BADGE_HEIGHT - 8)
              .height(BADGE_HEIGHT - 8)
              .borderRadius(T.radius.full)
              .backgroundColor(T.colors.accent)
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
    .gesture(
      LongPressGesture({ duration: 350 })
        .onAction(() => {
          // MSG-108：长按出单会话操作菜单（Pin / Mark as unread）。
          this.onDispatch(new ChatActionRequested(item.chatId));
        })
    )
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
      Text(this.uiState.listKind === 'archive' ? 'No archived chats' : 'No chats yet')
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
