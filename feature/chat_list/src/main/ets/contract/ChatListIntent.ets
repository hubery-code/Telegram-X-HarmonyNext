/**
 * feature/chat_list — 会话列表意图（CHATLIST-002 + MSG-108）。
 *
 * 用户动作：LoadChats（首屏/分页加载）、RefreshChats（下拉刷新）、
 * ChatSelected（点击行）；系统事件：OnChatsLoaded / OnChatsLoadFailed
 * 把异步结果回灌 reducer。每个类带字面量 kind 判别属性。
 *
 * MSG-108 新增单会话操作流：
 * ChatActionRequested（长按行）→ reducer 按该行当前状态算出菜单文案 →
 * ToggleChatPinned / ToggleChatMarkedUnread（点选）→ SetChatPinned /
 * SetChatReadState effect → OnChatActionFailed 把失败回灌 errorMessage。
 * DismissChatActionMenu 关闭菜单（点遮罩 / 返回键）。
 *
 * DRAWER-101 新增抽屉流：DrawerAccountRequested（点 ≡ / 首屏预热）→ FetchDrawerAccount；
 * DrawerItemClicked / DrawerAccountClicked 把菜单项转成导航意图；
 * OnDrawerAccountLoaded / OnDrawerAvatarLoaded 回灌账号头。
 */

import { Intent } from '@tgx/feature-template';
import { AppError } from '@tgx/core-common';
import { ChatListItem } from '../model/ChatListItem';
import { DrawerItemKey } from './DrawerState';
import { ChatFolderTab, DEFAULT_CHAT_FOLDERS } from './ChatListUiState';

export class LoadChats implements Intent {
  readonly kind: 'loadChats' = 'loadChats';
}

export class RefreshChats implements Intent {
  readonly kind: 'refreshChats' = 'refreshChats';
}

export class ChatSelected implements Intent {
  readonly kind: 'chatSelected' = 'chatSelected';
  readonly chatId: number;

  constructor(chatId: number) {
    this.chatId = chatId;
  }
}

export class OnChatsLoaded implements Intent {
  readonly kind: 'onChatsLoaded' = 'onChatsLoaded';
  readonly items: readonly ChatListItem[];
  readonly archiveUnreadCount: number;
  readonly archiveChatCount: number;
  readonly folders: readonly ChatFolderTab[];

  constructor(
    items: readonly ChatListItem[],
    archiveUnreadCount: number = 0,
    archiveChatCount: number = 0,
    folders: readonly ChatFolderTab[] = DEFAULT_CHAT_FOLDERS
  ) {
    this.items = items;
    this.archiveUnreadCount = archiveUnreadCount;
    this.archiveChatCount = archiveChatCount;
    this.folders = folders;
  }
}

export class SelectChatFolder implements Intent {
  readonly kind: 'selectChatFolder' = 'selectChatFolder';
  readonly folderId: string;

  constructor(folderId: string) {
    this.folderId = folderId;
  }
}

export class OpenArchivedChats implements Intent {
  readonly kind: 'openArchivedChats' = 'openArchivedChats';
}

export class CloseArchivedChats implements Intent {
  readonly kind: 'closeArchivedChats' = 'closeArchivedChats';
}

export class OnChatsLoadFailed implements Intent {
  readonly kind: 'onChatsLoadFailed' = 'onChatsLoadFailed';
  readonly error: AppError;

  constructor(error: AppError) {
    this.error = error;
  }
}

/** MSG-108：长按会话行 → 打开该行的操作菜单（文案由 reducer 定稿）。 */
export class ChatActionRequested implements Intent {
  readonly kind: 'chatActionRequested' = 'chatActionRequested';
  readonly chatId: number;

  constructor(chatId: number) {
    this.chatId = chatId;
  }
}

/** MSG-108：菜单点选 Pin/Unpin——目标状态取反 actionMenu.isPinned。 */
export class ToggleChatPinned implements Intent {
  readonly kind: 'toggleChatPinned' = 'toggleChatPinned';
}

/** MSG-108：菜单点选 Mark as read/unread——方向取反 actionMenu.canMarkAsRead。 */
export class ToggleChatMarkedUnread implements Intent {
  readonly kind: 'toggleChatMarkedUnread' = 'toggleChatMarkedUnread';
}

export class ToggleChatArchived implements Intent {
  readonly kind: 'toggleChatArchived' = 'toggleChatArchived';
}

/** MSG-108：关闭操作菜单（点遮罩 / 返回键）。 */
export class DismissChatActionMenu implements Intent {
  readonly kind: 'dismissChatActionMenu' = 'dismissChatActionMenu';
}

/** MSG-108：置顶/标未读请求失败，回灌 errorMessage。 */
export class OnChatActionFailed implements Intent {
  readonly kind: 'onChatActionFailed' = 'onChatActionFailed';
  readonly error: AppError;

  constructor(error: AppError) {
    this.error = error;
  }
}

/**
 * DRAWER-101：确保抽屉账号头有数据。点 ≡ 与首屏 start() 各派发一次，
 * reducer 用 accountUserId 做幂等守卫，重复派发不再产生请求。
 */
export class DrawerAccountRequested implements Intent {
  readonly kind: 'drawerAccountRequested' = 'drawerAccountRequested';
}

/** DRAWER-101：点击抽屉菜单项。'calls'/'invite'/'help' 尚无落地页，reducer 不产出 effect。 */
export class DrawerItemClicked implements Intent {
  readonly kind: 'drawerItemClicked' = 'drawerItemClicked';
  readonly item: DrawerItemKey;

  constructor(item: DrawerItemKey) {
    this.item = item;
  }
}

/** DRAWER-101：点击抽屉账号头 → 我的资料（对齐 TGX 点头像进自己资料页）。 */
export class DrawerAccountClicked implements Intent {
  readonly kind: 'drawerAccountClicked' = 'drawerAccountClicked';
}

/** DRAWER-101：getMe 回灌（头像路径由 OnDrawerAvatarLoaded 单独回灌，下载是异步的）。 */
export class OnDrawerAccountLoaded implements Intent {
  readonly kind: 'onDrawerAccountLoaded' = 'onDrawerAccountLoaded';
  readonly userId: number;
  readonly name: string;
  readonly phone: string;
  readonly avatarLetters: string;

  constructor(userId: number, name: string, phone: string, avatarLetters: string) {
    this.userId = userId;
    this.name = name;
    this.phone = phone;
    this.avatarLetters = avatarLetters;
  }
}

/**
 * DRAWER-101：账号头像本地文件下载完成后回灌（FileRegistry.subscribeFile）。
 * 夜间模式开关的真实偏好在装配层 ThemeManager，切换后回灌本意图，
 * 让抽屉渲染只依赖 uiState.drawer（不再由装配层另建一份 DrawerState）。
 */
export class OnDrawerAvatarLoaded implements Intent {
  readonly kind: 'onDrawerAvatarLoaded' = 'onDrawerAvatarLoaded';
  readonly avatarPath: string;

  constructor(avatarPath: string) {
    this.avatarPath = avatarPath;
  }
}

/** DRAWER-101：夜间模式开关状态回灌。 */
export class DrawerNightModeSet implements Intent {
  readonly kind: 'drawerNightModeSet' = 'drawerNightModeSet';
  readonly on: boolean;

  constructor(on: boolean) {
    this.on = on;
  }
}

export type ChatListIntent =
  | LoadChats
  | RefreshChats
  | ChatSelected
  | OnChatsLoaded
  | OnChatsLoadFailed
  | OpenArchivedChats
  | CloseArchivedChats
  | SelectChatFolder
  | ChatActionRequested
  | ToggleChatPinned
  | ToggleChatMarkedUnread
  | ToggleChatArchived
  | DismissChatActionMenu
  | OnChatActionFailed
  | DrawerAccountRequested
  | DrawerItemClicked
  | DrawerAccountClicked
  | OnDrawerAccountLoaded
  | OnDrawerAvatarLoaded
  | DrawerNightModeSet;
