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
 *
 * GROUP-CREATE-101 新增建群/建频道流程：抽屉 newGroup/newChannel → 装配层接力
 * 成员多选（feature/contact）→ GroupCreateStarted 进入命名段；标题/简介经
 * GroupCreateTitleChanged / GroupCreateDescriptionChanged 进状态，提交经
 * GroupCreateSubmitRequested 本地校验后产出创建 effect；OnGroupChatCreated /
 * OnGroupCreateFailed 回灌结果（成功即 NavigateToChat 进新会话）。
 */

import { Intent } from '@tgx/feature-template';
import { AppError } from '@tgx/core-common';
import { ChatListItem } from '../model/ChatListItem';
import { DrawerItemKey } from './DrawerState';
import { GroupCreateMode } from './GroupCreateState';
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

// ---- GROUP-CREATE-101 建群/建频道流程 ----

/**
 * GROUP-CREATE-101：进入命名段。装配层在成员多选确认后派发（频道创建无
 * 成员段，userIds 传空数组），reducer 用它初始化 ChatListUiState.groupCreate。
 */
export class GroupCreateStarted implements Intent {
  readonly kind: 'groupCreateStarted' = 'groupCreateStarted';
  readonly mode: GroupCreateMode;
  readonly memberUserIds: number[];

  constructor(mode: GroupCreateMode, memberUserIds: number[]) {
    this.mode = mode;
    this.memberUserIds = memberUserIds;
  }
}

/** GROUP-CREATE-101：标题输入变化（原文存入，校验推迟到提交）。 */
export class GroupCreateTitleChanged implements Intent {
  readonly kind: 'groupCreateTitleChanged' = 'groupCreateTitleChanged';
  readonly title: string;

  constructor(title: string) {
    this.title = title;
  }
}

/** GROUP-CREATE-101：频道简介输入变化。 */
export class GroupCreateDescriptionChanged implements Intent {
  readonly kind: 'groupCreateDescriptionChanged' = 'groupCreateDescriptionChanged';
  readonly description: string;

  constructor(description: string) {
    this.description = description;
  }
}

/**
 * GROUP-CREATE-101：点「创建」。reducer 本地先拦标题（空/超 128 字 →
 * errorMessageKey 内联提示、不发请求），合法才产出创建 effect。
 */
export class GroupCreateSubmitRequested implements Intent {
  readonly kind: 'groupCreateSubmitRequested' = 'groupCreateSubmitRequested';
}

/** GROUP-CREATE-101：用户放弃命名段（返回键 / 关闭），流程状态整体清空。 */
export class GroupCreateCancelled implements Intent {
  readonly kind: 'groupCreateCancelled' = 'groupCreateCancelled';
}

/**
 * GROUP-CREATE-101：TDLib 回包（Chat）解码后回灌。reducer 清掉流程状态并
 * 产出 NavigateToChat——进会话与列表点击走同一条导航链路。
 */
export class OnGroupChatCreated implements Intent {
  readonly kind: 'onGroupChatCreated' = 'onGroupChatCreated';
  readonly chatId: number;

  constructor(chatId: number) {
    this.chatId = chatId;
  }
}

/** GROUP-CREATE-101：请求级/响应级失败统一回灌；reducer 落通用错误 key。 */
export class OnGroupCreateFailed implements Intent {
  readonly kind: 'onGroupCreateFailed' = 'onGroupCreateFailed';
  readonly error: AppError;

  constructor(error: AppError) {
    this.error = error;
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
  | DrawerNightModeSet
  | GroupCreateStarted
  | GroupCreateTitleChanged
  | GroupCreateDescriptionChanged
  | GroupCreateSubmitRequested
  | GroupCreateCancelled
  | OnGroupChatCreated
  | OnGroupCreateFailed;
