/**
 * feature/chat_list — 会话列表可观察状态（CHATLIST-002 + MSG-108）。
 *
 * 遵循计划 §5.11 / UI-003：所有字段只读，不可变更新经 copyWith() 派生。
 *
 * MSG-108 新增 actionMenu：长按会话行的操作菜单状态（可见项与文案已在
 * reducer 内按权限/当前状态算好），null = 不显示。
 */

import { UiState } from '@tgx/feature-template';
import { ChatListItem } from '../model/ChatListItem';

export type ChatListKind = 'main' | 'archive';

/**
 * 长按会话行的操作菜单状态。
 * 文案在 reducer 内定稿（与 Android ChatsController 的单会话菜单一致）：
 * - isPinned → 显示 "Unpin"，否则 "Pin"；
 * - canMarkAsRead → 显示 "Mark as read"，否则 "Mark as unread"。
 *   canMarkAsRead 的判定对齐 Android `Tdlib.canMarkAsRead`：
 *   `unread_count > 0 || is_marked_as_unread`。
 */
export class ChatActionMenuState {
  readonly chatId: number;
  readonly title: string;
  readonly isPinned: boolean;
  readonly canMarkAsRead: boolean;
  readonly isArchived: boolean;

  constructor(
    chatId: number,
    title: string,
    isPinned: boolean,
    canMarkAsRead: boolean,
    isArchived: boolean = false
  ) {
    this.chatId = chatId;
    this.title = title;
    this.isPinned = isPinned;
    this.canMarkAsRead = canMarkAsRead;
    this.isArchived = isArchived;
  }
}

export interface ChatListUiStateOptions {
  readonly items?: readonly ChatListItem[];
  readonly isLoading?: boolean;
  readonly errorMessage?: string | null;
  readonly actionMenu?: ChatActionMenuState | null;
  readonly listKind?: ChatListKind;
  readonly archiveUnreadCount?: number;
  readonly archiveChatCount?: number;
}

export class ChatListUiState implements UiState {
  readonly items: readonly ChatListItem[];
  readonly isLoading: boolean;
  readonly errorMessage: string | null;
  readonly actionMenu: ChatActionMenuState | null;
  readonly listKind: ChatListKind;
  readonly archiveUnreadCount: number;
  readonly archiveChatCount: number;

  constructor(
    items: readonly ChatListItem[],
    isLoading: boolean,
    errorMessage: string | null,
    actionMenu: ChatActionMenuState | null = null,
    listKind: ChatListKind = 'main',
    archiveUnreadCount: number = 0,
    archiveChatCount: number = 0
  ) {
    this.items = items;
    this.isLoading = isLoading;
    this.errorMessage = errorMessage;
    this.actionMenu = actionMenu;
    this.listKind = listKind;
    this.archiveUnreadCount = archiveUnreadCount;
    this.archiveChatCount = archiveChatCount;
  }

  static initial(): ChatListUiState {
    return new ChatListUiState([], false, null, null, 'main', 0, 0);
  }

  copyWith(options: ChatListUiStateOptions): ChatListUiState {
    return new ChatListUiState(
      options.items !== undefined ? options.items : this.items,
      options.isLoading !== undefined ? options.isLoading : this.isLoading,
      options.errorMessage !== undefined ? options.errorMessage : this.errorMessage,
      options.actionMenu !== undefined ? options.actionMenu : this.actionMenu,
      options.listKind !== undefined ? options.listKind : this.listKind,
      options.archiveUnreadCount !== undefined ? options.archiveUnreadCount : this.archiveUnreadCount,
      options.archiveChatCount !== undefined ? options.archiveChatCount : this.archiveChatCount
    );
  }
}
