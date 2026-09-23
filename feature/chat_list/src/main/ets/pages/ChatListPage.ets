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

import { LightTheme, Theme } from '@tgx/core-design-system';
import { ChatListItem } from '../model/ChatListItem';
import { ChatListUiState, ChatActionMenuState, ChatFolderTab, filterChatsByFolder } from '../contract/ChatListUiState';
import { DrawerItemKey } from '../contract/DrawerState';
import { DrawerMenu } from './DrawerMenu';
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
  DismissChatActionMenu,
  SelectChatFolder,
  DrawerAccountRequested,
  DrawerItemClicked,
  DrawerAccountClicked,
  DrawerNightModeSet
} from '../contract/ChatListIntent';


const AVATAR_SIZE: number = 52;
const BADGE_HEIGHT: number = 20;
const SETTINGS_BUTTON_SIZE: number = 44;
/** INTEG-002：搜索入口行高（vp）。 */
const SEARCH_BAR_HEIGHT: number = 40;
/** FOLDERS-101：Folder 标签栏高（vp）。 */
const FOLDER_TAB_HEIGHT: number = 40;
const FAB_SIZE: number = 56;
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
 * （标题/预览/未读数/时间戳/置顶态/手动未读标记/头像路径/类别）。
 */
function chatRowKey(item: ChatListItem): string {
  const signature: string =
    `${item.title}|${item.lastMessagePreview}|${item.unreadCount}|${item.timestampMs}|` +
    `${item.isPinned}|${item.isMuted}|${item.isMarkedAsUnread}|${item.category}|${item.avatarPath !== null ? item.avatarPath : ''}|${item.draftText !== null ? item.draftText : ''}`;
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
  /**
   * FEAT-UI-001 全局深色主题：entry 装配层把 ThemeManager 的当前主题写入
   * AppStorage('activeTheme')，本页以 @StorageProp 订阅。该值变化会触发本页
   * 重渲染。此前写死 `const T = LightTheme`，主题切换后引用不变，深色不生效。
   * 短名 T 直接落在装饰器成员上——ArkUI 的 build 转换不接管 struct 内自定义
   * getter，写成 getter 会在渲染闭包里取到 undefined 并抛 TypeError。
   */
  @StorageProp('activeTheme') T: Theme = LightTheme;
  @Prop @Watch('onUiStateChanged') uiState: ChatListUiState = ChatListUiState.initial();

  onDispatch: (intent: Object) => void = () => {};

  /** 打开设置页（纯导航回调，由装配层接线）。 */
  onOpenSettings: () => void = () => {};

  /** INTEG-002：打开搜索页（纯导航回调，由装配层接线）。 */
  onOpenSearch: () => void = () => {};

  /** 打开新会话/撰写页（纯导航回调，由装配层接线）。 */
  onCompose: () => void = () => {};

  /**
   * DRAWER-101：夜间模式开关变更（真实切换逻辑在装配层 ThemeManager）。
   * 本页只负责派发 DrawerNightModeSet 让抽屉状态与主题保持一致。
   */
  onDrawerNightModeChanged: (on: boolean) => void = () => {};

  /** DRAWER-101：账号切换（装配层弹账号选择器）。 */
  onDrawerSwitchAccount: () => void = () => {};

  @State private isRefreshing: boolean = false;

  /** DRAWER-101：≡ 抽屉面板可见性。 */
  @State private showDrawer: boolean = false;
  private dataSource: ChatListDataSource = new ChatListDataSource();

  private getFilteredItems(): readonly ChatListItem[] {
    if (this.uiState.listKind === 'archive') {
      return this.uiState.items;
    }
    return filterChatsByFolder(this.uiState.items, this.uiState.selectedFolderId);
  }

  aboutToAppear(): void {
    this.dataSource.setItems(this.getFilteredItems());
    if (this.uiState.items.length === 0 && !this.uiState.isLoading && this.uiState.errorMessage === null) {
      this.onDispatch(new LoadChats());
    }
    // DRAWER-101：夜间模式初值取自当前主题（ThemeManager 才是主题权威，
    // 抽屉里的开关只是它的投影），否则冷启动后开关与真实主题相反。
    this.onDispatch(new DrawerNightModeSet(this.T.mode === 'dark'));
  }

  onUiStateChanged(): void {
    this.dataSource.setItems(this.getFilteredItems());
    if (!this.uiState.isLoading) {
      this.isRefreshing = false;
    }
  }

  private handleSwipeFolder(deltaX: number): void {
    if (this.uiState.listKind !== 'main') {
      return;
    }
    const folders: readonly ChatFolderTab[] = this.uiState.folders;
    if (folders === undefined || folders.length <= 1) {
      return;
    }
    let currentIndex: number = -1;
    for (let i = 0; i < folders.length; i++) {
      if (folders[i].id === this.uiState.selectedFolderId) {
        currentIndex = i;
        break;
      }
    }
    if (currentIndex < 0) {
      return;
    }
    if (deltaX < -30 && currentIndex < folders.length - 1) {
      this.onDispatch(new SelectChatFolder(folders[currentIndex + 1].id));
    } else if (deltaX > 30 && currentIndex > 0) {
      this.onDispatch(new SelectChatFolder(folders[currentIndex - 1].id));
    }
  }

  /**
   * DRAWER-101：抽屉菜单项点击——先收起抽屉再派发 intent（对齐 TGX 点项即收）。
   * 去向由 reducer 判定并经装配层执行，本页不再持有路由知识。
   */
  private handleDrawerItem(item: DrawerItemKey): void {
    this.showDrawer = false;
    this.onDispatch(new DrawerItemClicked(item));
  }

  /** DRAWER-101：点账号头 → 我的资料。 */
  private handleDrawerAccountClicked(): void {
    this.showDrawer = false;
    this.onDispatch(new DrawerAccountClicked());
  }

  build() {
    Stack({ alignContent: Alignment.BottomEnd }) {
      Column() {
        if (this.uiState.listKind === 'archive') {
          // CHAT-003：归档列表顶部导航栏（返回按钮 + 标题）
          Row() {
            Image($r('app.media.ic_back'))
              .width(SETTINGS_BUTTON_SIZE * 0.6)
              .height(SETTINGS_BUTTON_SIZE * 0.6)
              .fillColor(this.T.colors.accent)
              .margin({ right: this.T.spacing.sm })
              .onClick(() => {
                this.onDispatch(new CloseArchivedChats());
              })

            Text('Archived Chats')
              .fontSize(this.T.typography.largeTitle.fontSize)
              .fontWeight(this.T.typography.largeTitle.fontWeight)
              .fontColor(this.T.colors.textPrimary)
              .layoutWeight(1)

            Image($r('app.media.ic_settings'))
              .width(22)
              .height(22)
              .fillColor(this.T.colors.accent)
              .onClick(() => {
                this.onOpenSettings();
              })
          }
          .width('100%')
          .alignItems(VerticalAlign.Center)
          .padding({
            left: this.T.spacing.screenInset,
            right: this.T.spacing.screenInset,
            top: this.T.spacing.lg,
            bottom: this.T.spacing.md
          })
        } else {
          Row() {
            // DRAWER-101：TGX 抽屉导航入口。
            Image($r('app.media.ic_menu'))
              .width(22)
              .height(22)
              .fillColor(this.T.colors.accent)
              .margin({ right: this.T.spacing.sm })
              .onClick(() => {
                this.showDrawer = true;
                // DRAWER-101：开抽屉时确保账号头有数据（reducer 幂等）。
                this.onDispatch(new DrawerAccountRequested());
              })

            Text('Chats')
              .fontSize(this.T.typography.largeTitle.fontSize)
              .fontWeight(this.T.typography.largeTitle.fontWeight)
              .fontColor(this.T.colors.textPrimary)
              .layoutWeight(1)

            // TGX 对齐：顶栏右侧为搜索入口（与 ChatsController.fillMenuItems 对齐），设置收敛至抽屉导航。
            Image($r('app.media.ic_search'))
              .width(22)
              .height(22)
              .fillColor(this.T.colors.accent)
              .onClick(() => {
                this.onOpenSearch();
              })
          }
          .width('100%')
          .alignItems(VerticalAlign.Center)
          .padding({
            left: this.T.spacing.screenInset,
            right: this.T.spacing.screenInset,
            top: this.T.spacing.lg,
            bottom: this.T.spacing.md
          })

          // INTEG-002：搜索入口。
          Row() {
            Image($r('app.media.ic_search'))
              .width(18)
              .height(18)
              .fillColor(this.T.colors.textSecondary)
              .margin({ right: this.T.spacing.xs })

            Text('Search')
              .fontSize(this.T.typography.body.fontSize)
              .fontColor(this.T.colors.textSecondary)
              .layoutWeight(1)
          }
          .width('100%')
          .height(SEARCH_BAR_HEIGHT)
          .alignItems(VerticalAlign.Center)
          .padding({ left: this.T.spacing.md, right: this.T.spacing.md })
          .backgroundColor(this.T.colors.surfaceVariant)
          .borderRadius(this.T.radius.md)
          .margin({
            left: this.T.spacing.screenInset,
            right: this.T.spacing.screenInset,
            bottom: this.T.spacing.sm
          })
          .onClick(() => {
            this.onOpenSearch();
          })
        }

        // FOLDERS-101：主列表展示 Folder 标签栏
        if (this.uiState.listKind === 'main') {
          this.FolderTabBar()
        }

        // MSG-108：置顶/标未读失败的错误细条（不挡列表）。
        if (this.uiState.errorMessage !== null && this.uiState.items.length > 0) {
          Text(this.uiState.errorMessage)
            .fontSize(this.T.typography.footnote.fontSize)
            .fontColor(this.T.colors.destructive)
            .maxLines(1)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
            .width('100%')
            .padding({
              left: this.T.spacing.screenInset,
              right: this.T.spacing.screenInset,
              bottom: this.T.spacing.xs
            })
        }

        if (this.uiState.errorMessage !== null && this.uiState.items.length === 0) {
          this.ErrorView(this.uiState.errorMessage)
        } else if (this.uiState.isLoading && this.uiState.items.length === 0) {
          this.LoadingView()
        } else if (this.getFilteredItems().length === 0) {
          this.FolderEmptyView()
        } else {
          Refresh({ refreshing: $$this.isRefreshing }) {
            List() {
              // CHAT-003 / FOLDERS-101：仅在 All 分类下且存在归档会话时，顶部展示归档区入口行
              if (this.uiState.listKind === 'main' && this.uiState.selectedFolderId === 'all' && (this.uiState.archiveChatCount > 0 || this.uiState.archiveUnreadCount > 0)) {
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
              color: this.T.colors.divider,
              startMargin: this.T.spacing.screenInset + AVATAR_SIZE + this.T.spacing.md,
              endMargin: this.T.spacing.none
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
      .backgroundColor(this.T.colors.background)
      .parallelGesture(
        PanGesture({ direction: PanDirection.Horizontal, distance: 30 })
          .onActionEnd((event: GestureEvent) => {
            this.handleSwipeFolder(event.offsetX);
          })
      )

      // TGX 标志性悬浮按钮 (Floating Action Button FAB)：圆形 56x56，背景 this.T.colors.accent，内嵌 24x24 白色 ic_compose 图标，带阴影
      Column() {
        Image($r('app.media.ic_compose'))
          .width(24)
          .height(24)
          .fillColor(this.T.colors.textOnAccent)
      }
      .width(FAB_SIZE)
      .height(FAB_SIZE)
      .borderRadius(this.T.radius.full)
      .backgroundColor(this.T.colors.accent)
      .justifyContent(FlexAlign.Center)
      .alignItems(HorizontalAlign.Center)
      .shadow({
        radius: 8,
        color: this.T.colors.scrim,
        offsetX: 0,
        offsetY: 4
      })
      .margin({
        right: this.T.spacing.screenInset,
        bottom: this.T.spacing.xxl
      })
      .onClick(() => {
        this.onCompose();
      })

      // MSG-108：长按会话行的操作菜单（遮罩 + 底部动作面板）。
      if (this.uiState.actionMenu !== null) {
        this.ChatActionSheet(this.uiState.actionMenu)
      }

      // DRAWER-101：TGX 抽屉导航（≡ 滑出 72% 面板 + 半透明 scrim）。
      // 注意：根 Stack 的 alignContent 为 BottomEnd（供右下角 FAB 使用），抽屉若直接作为其子节点
      // 会被一并推到右下角。故抽屉层用独立 Stack 显式声明 TopStart，与 FAB 的对齐互不干扰。
      if (this.showDrawer) {
        Stack({ alignContent: Alignment.TopStart }) {
          // 半透明遮罩：点击关闭抽屉。
          Column()
            .width('100%')
            .height('100%')
            .backgroundColor(this.T.colors.scrim)
            .onClick(() => {
              this.showDrawer = false;
            })

          DrawerMenu({
            state: this.uiState.drawer,
            onItem: (item: DrawerItemKey): void => {
              this.handleDrawerItem(item);
            },
            onNightModeChanged: (on: boolean): void => {
              this.onDispatch(new DrawerNightModeSet(on));
              this.onDrawerNightModeChanged(on);
            },
            onClose: (): void => {
              this.showDrawer = false;
            },
            onAccountClicked: (): void => {
              this.handleDrawerAccountClicked();
            },
            onSwitchAccount: (): void => {
              this.onDrawerSwitchAccount();
            }
          })
        }
        .width('100%')
        .height('100%')
      }
    }
    .width('100%')
    .height('100%')
    .backgroundColor(this.T.colors.background)
  }

  /**
   * CHAT-003：主列表顶部的归档区入口行。
   */
  @Builder
  ArchivedChatsRow() {
    Row() {
      Column() {
        Image($r('app.media.ic_archive'))
          .width(26)
          .height(26)
          .fillColor(this.T.colors.textSecondary)
      }
      .width(AVATAR_SIZE)
      .height(AVATAR_SIZE)
      .borderRadius(this.T.radius.full)
      .backgroundColor(this.T.colors.surfaceVariant)
      .justifyContent(FlexAlign.Center)
      .alignItems(HorizontalAlign.Center)
      .margin({ right: this.T.spacing.md })

      Column() {
        Row() {
          Text('Archived Chats')
            .fontSize(this.T.typography.headline.fontSize)
            .fontWeight(this.T.typography.headline.fontWeight)
            .fontColor(this.T.colors.textPrimary)
            .layoutWeight(1)

          if (this.uiState.archiveUnreadCount > 0) {
            Text(this.uiState.archiveUnreadCount > 99 ? '99+' : `${this.uiState.archiveUnreadCount}`)
              .fontSize(this.T.typography.caption.fontSize)
              .fontWeight(this.T.typography.headline.fontWeight)
              .fontColor(this.T.colors.textOnAccent)
              .backgroundColor(this.T.colors.accent)
              .borderRadius(this.T.radius.full)
              .height(BADGE_HEIGHT)
              .constraintSize({ minWidth: BADGE_HEIGHT })
              .padding({ left: this.T.spacing.xs + this.T.spacing.hairline, right: this.T.spacing.xs + this.T.spacing.hairline })
              .textAlign(TextAlign.Center)
              .margin({ left: this.T.spacing.sm })
          }
        }
        .width('100%')
        .margin({ bottom: this.T.spacing.xs })

        Row() {
          Text(this.uiState.archiveChatCount > 0 ? `${this.uiState.archiveChatCount} chats` : 'Archived chats')
            .fontSize(this.T.typography.subheadline.fontSize)
            .fontColor(this.T.colors.textSecondary)
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
      left: this.T.spacing.screenInset,
      right: this.T.spacing.screenInset,
      top: this.T.spacing.md,
      bottom: this.T.spacing.md
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
        .backgroundColor(this.T.colors.scrim)
        .onClick(() => {
          this.onDispatch(new DismissChatActionMenu());
        })

      Column() {
        Text(menu.title)
          .fontSize(this.T.typography.footnote.fontSize)
          .fontColor(this.T.colors.textSecondary)
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
          .width('100%')
          .padding({
            left: this.T.spacing.screenInset,
            right: this.T.spacing.screenInset,
            top: this.T.spacing.md,
            bottom: this.T.spacing.xs
          })

        Text(menu.isPinned ? 'Unpin' : 'Pin')
          .fontSize(this.T.typography.body.fontSize)
          .fontColor(this.T.colors.textPrimary)
          .width('100%')
          .padding({
            left: this.T.spacing.screenInset,
            right: this.T.spacing.screenInset,
            top: this.T.spacing.md,
            bottom: this.T.spacing.md
          })
          .onClick(() => {
            this.onDispatch(new ToggleChatPinned());
          })

        Text(menu.canMarkAsRead ? 'Mark as read' : 'Mark as unread')
          .fontSize(this.T.typography.body.fontSize)
          .fontColor(this.T.colors.textPrimary)
          .width('100%')
          .padding({
            left: this.T.spacing.screenInset,
            right: this.T.spacing.screenInset,
            top: this.T.spacing.md,
            bottom: this.T.spacing.md
          })
          .onClick(() => {
            this.onDispatch(new ToggleChatMarkedUnread());
          })

        Text(menu.isArchived ? 'Unarchive' : 'Archive')
          .fontSize(this.T.typography.body.fontSize)
          .fontColor(this.T.colors.textPrimary)
          .width('100%')
          .padding({
            left: this.T.spacing.screenInset,
            right: this.T.spacing.screenInset,
            top: this.T.spacing.md,
            bottom: this.T.spacing.md
          })
          .onClick(() => {
            this.onDispatch(new ToggleChatArchived());
          })
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

  @Builder
  ChatRow(item: ChatListItem) {
    Row() {
      if (item.avatarPath !== null && item.avatarPath.length > 0) {
        Image(toSandboxUri(item.avatarPath))
          .width(AVATAR_SIZE)
          .height(AVATAR_SIZE)
          .borderRadius(this.T.radius.full)
          .objectFit(ImageFit.Cover)
          .margin({ right: this.T.spacing.md })
      } else {
        Text(item.avatarLetter)
          .width(AVATAR_SIZE)
          .height(AVATAR_SIZE)
          .borderRadius(this.T.radius.full)
          .backgroundColor(item.avatarColor)
          .fontColor(this.T.colors.textOnAccent)
          .fontSize(this.T.typography.title.fontSize)
          .fontWeight(this.T.typography.title.fontWeight)
          .textAlign(TextAlign.Center)
          .margin({ right: this.T.spacing.md })
      }

      Column() {
        Row() {
          Text(item.title)
            .fontSize(this.T.typography.headline.fontSize)
            .fontWeight(this.T.typography.headline.fontWeight)
            .fontColor(this.T.colors.textPrimary)
            .maxLines(1)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
            .layoutWeight(1)

          // MSG-108：置顶标（时间戳左侧，对齐 Telegram X 的位置）。
          if (item.isPinned) {
            Image($r('app.media.ic_pin'))
              .width(14)
              .height(14)
              .fillColor(this.T.colors.textSecondary)
              .margin({ left: this.T.spacing.sm })
          }

          if (item.isMuted) {
            Image($r('app.media.ic_mute'))
              .width(14)
              .height(14)
              .fillColor(this.T.colors.textSecondary)
              .margin({ left: this.T.spacing.sm })
          }

          Text(formatChatTimestamp(item.timestampMs))
            .fontSize(this.T.typography.footnote.fontSize)
            .fontColor(this.T.colors.textSecondary)
            .margin({ left: this.T.spacing.sm })
        }
        .width('100%')
        .margin({ bottom: this.T.spacing.xs })

        Row() {
          if (item.draftText !== null && item.draftText.length > 0) {
            Text('Draft: ')
              .fontSize(this.T.typography.subheadline.fontSize)
              .fontWeight(this.T.typography.headline.fontWeight)
              .fontColor(this.T.colors.destructive)

            Text(item.draftText)
              .fontSize(this.T.typography.subheadline.fontSize)
              .fontColor(this.T.colors.textSecondary)
              .maxLines(1)
              .textOverflow({ overflow: TextOverflow.Ellipsis })
              .layoutWeight(1)
          } else {
            Text(item.lastMessagePreview)
              .fontSize(this.T.typography.subheadline.fontSize)
              .fontColor(this.T.colors.textSecondary)
              .maxLines(1)
              .textOverflow({ overflow: TextOverflow.Ellipsis })
              .layoutWeight(1)
          }

          if (item.unreadCount > 0) {
            Text(item.unreadCount > 99 ? '99+' : `${item.unreadCount}`)
              .fontSize(this.T.typography.caption.fontSize)
              .fontWeight(this.T.typography.headline.fontWeight)
              .fontColor(this.T.colors.textOnAccent)
              .backgroundColor(this.T.colors.accent)
              .borderRadius(this.T.radius.full)
              .height(BADGE_HEIGHT)
              .constraintSize({ minWidth: BADGE_HEIGHT })
              .padding({ left: this.T.spacing.xs + this.T.spacing.hairline, right: this.T.spacing.xs + this.T.spacing.hairline })
              .textAlign(TextAlign.Center)
              .margin({ left: this.T.spacing.sm })
          } else if (item.isMarkedAsUnread) {
            // MSG-108：手动标未读但不含未读消息 → 实心圆点（标未读不产生未读数）。
            Text('')
              .width(BADGE_HEIGHT - 8)
              .height(BADGE_HEIGHT - 8)
              .borderRadius(this.T.radius.full)
              .backgroundColor(this.T.colors.accent)
              .margin({ left: this.T.spacing.sm })
          }
        }
        .width('100%')
      }
      .layoutWeight(1)
      .alignItems(HorizontalAlign.Start)
    }
    .width('100%')
    .padding({
      left: this.T.spacing.screenInset,
      right: this.T.spacing.screenInset,
      top: this.T.spacing.md,
      bottom: this.T.spacing.md
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
        .color(this.T.colors.accent)
        .margin({ bottom: this.T.spacing.lg })

      Text('Loading chats...')
        .fontSize(this.T.typography.body.fontSize)
        .fontColor(this.T.colors.textSecondary)
    }
    .width('100%')
    .layoutWeight(1)
    .justifyContent(FlexAlign.Center)
    .alignItems(HorizontalAlign.Center)
  }

  private getFoldersList(): ChatFolderTab[] {
    return this.uiState.folders.slice(0);
  }

  @Builder
  FolderTabBar() {
    Scroll() {
      Row() {
        ForEach(this.getFoldersList(), (folder: ChatFolderTab) => {
          Column() {
            Row() {
              Text(folder.title)
                .fontSize(this.T.typography.subheadline.fontSize)
                .fontWeight(this.uiState.selectedFolderId === folder.id ? FontWeight.Bold : FontWeight.Medium)
                .fontColor(this.uiState.selectedFolderId === folder.id ? this.T.colors.accent : this.T.colors.textSecondary)

              if (folder.unreadCount > 0) {
                Text(folder.unreadCount > 99 ? '99+' : `${folder.unreadCount}`)
                  .fontSize(this.T.typography.caption.fontSize)
                  .fontWeight(FontWeight.Bold)
                  .fontColor(this.uiState.selectedFolderId === folder.id ? this.T.colors.textOnAccent : this.T.colors.textSecondary)
                  .backgroundColor(this.uiState.selectedFolderId === folder.id ? this.T.colors.accent : this.T.colors.surfaceVariant)
                  .borderRadius(this.T.radius.full)
                  .height(18)
                  .constraintSize({ minWidth: 18 })
                  .padding({ left: 5, right: 5 })
                  .textAlign(TextAlign.Center)
                  .margin({ left: this.T.spacing.xs })
              }
            }
            .alignItems(VerticalAlign.Center)
            .padding({
              left: this.T.spacing.md,
              right: this.T.spacing.md,
              top: this.T.spacing.sm,
              bottom: this.T.spacing.sm
            })
          }
          .border({
            width: { bottom: 3 },
            color: { bottom: this.uiState.selectedFolderId === folder.id ? this.T.colors.accent : Color.Transparent }
          })
          .alignItems(HorizontalAlign.Center)
          .onClick(() => {
            this.onDispatch(new SelectChatFolder(folder.id));
          })
        }, (folder: ChatFolderTab) => `${folder.id}:${folder.unreadCount}:${this.uiState.selectedFolderId === folder.id}`)
      }
      .padding({
        left: this.T.spacing.sm,
        right: this.T.spacing.sm
      })
    }
    .scrollable(ScrollDirection.Horizontal)
    .scrollBar(BarState.Off)
    .width('100%')
    .height(FOLDER_TAB_HEIGHT)
  }

  @Builder
  FolderEmptyView() {
    Column() {
      Image(this.getEmptyIcon())
        .width(56)
        .height(56)
        .fillColor(this.T.colors.textSecondary)
        .opacity(0.5)
        .margin({ bottom: this.T.spacing.md })

      Text(this.getEmptyTitle())
        .fontSize(this.T.typography.title.fontSize)
        .fontWeight(this.T.typography.title.fontWeight)
        .fontColor(this.T.colors.textPrimary)
        .margin({ bottom: this.T.spacing.xs })

      Text(this.getEmptySubtitle())
        .fontSize(this.T.typography.body.fontSize)
        .fontColor(this.T.colors.textSecondary)
        .textAlign(TextAlign.Center)
        .padding({ left: this.T.spacing.xxl, right: this.T.spacing.xxl })
    }
    .width('100%')
    .layoutWeight(1)
    .justifyContent(FlexAlign.Center)
    .alignItems(HorizontalAlign.Center)
  }

  private getEmptyIcon(): Resource {
    if (this.uiState.listKind === 'archive') {
      return $r('app.media.ic_archive');
    }
    switch (this.uiState.selectedFolderId) {
      case 'personal':
        return $r('app.media.ic_contacts');
      case 'groups':
        return $r('app.media.ic_group');
      case 'channels':
        return $r('app.media.ic_comments');
      case 'unread':
        return $r('app.media.ic_check_double');
      case 'all':
      default:
        return $r('app.media.ic_folder');
    }
  }

  private getEmptyTitle(): string {
    if (this.uiState.listKind === 'archive') {
      return 'No archived chats';
    }
    switch (this.uiState.selectedFolderId) {
      case 'personal':
        return 'No personal chats';
      case 'groups':
        return 'No groups yet';
      case 'channels':
        return 'No channels yet';
      case 'unread':
        return 'All caught up';
      case 'all':
      default:
        return 'No chats yet';
    }
  }

  private getEmptySubtitle(): string {
    if (this.uiState.listKind === 'archive') {
      return 'Chats you archive will appear here.';
    }
    switch (this.uiState.selectedFolderId) {
      case 'personal':
        return 'Your direct messages with people will appear here.';
      case 'groups':
        return 'Group conversations will appear here.';
      case 'channels':
        return 'Channels you subscribe to will appear here.';
      case 'unread':
        return 'You have read all incoming messages.';
      case 'all':
      default:
        return 'Start a conversation using the button below.';
    }
  }

  @Builder
  EmptyView() {
    this.FolderEmptyView()
  }

  @Builder
  ErrorView(errorMessage: string) {
    Column() {
      Text('Failed to load chats')
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
          this.onDispatch(new LoadChats());
        })
    }
    .width('100%')
    .layoutWeight(1)
    .justifyContent(FlexAlign.Center)
    .alignItems(HorizontalAlign.Center)
  }
}
