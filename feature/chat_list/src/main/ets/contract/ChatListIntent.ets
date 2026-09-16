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
 */

import { Intent } from '@tgx/feature-template';
import { AppError } from '@tgx/core-common';
import { ChatListItem } from '../model/ChatListItem';

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

  constructor(
    items: readonly ChatListItem[],
    archiveUnreadCount: number = 0,
    archiveChatCount: number = 0
  ) {
    this.items = items;
    this.archiveUnreadCount = archiveUnreadCount;
    this.archiveChatCount = archiveChatCount;
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

export type ChatListIntent =
  | LoadChats
  | RefreshChats
  | ChatSelected
  | OnChatsLoaded
  | OnChatsLoadFailed
  | OpenArchivedChats
  | CloseArchivedChats
  | ChatActionRequested
  | ToggleChatPinned
  | ToggleChatMarkedUnread
  | ToggleChatArchived
  | DismissChatActionMenu
  | OnChatActionFailed;
