/**
 * feature/chat_list — 会话列表纯 Reducer（CHATLIST-002 + MSG-108）。
 *
 * 遵循计划 §5.11 / UI-003：
 * - 纯函数：(state, intent, env) -> ReducerResult<ChatListUiState, ChatListEffect>
 * - 禁止直接修改 state；无变化返回原引用 reduced(state)
 * - 禁止在 reducer 内做 I/O 或异步，加载请求只产出 FetchChatList 描述
 *
 * MSG-108 新增单会话操作流：
 * - chatActionRequested → 从当前行算菜单文案（isPinned / canMarkAsRead），
 *   行已不存在则忽略；
 * - toggleChatPinned → SetChatPinned(chatId, !menu.isPinned)；
 * - toggleChatMarkedUnread → SetChatReadState(chatId, markAsUnread = !canMarkAsRead)，
 *   即"菜单显示 Mark as read 时执行读、显示 Mark as unread 时执行标未读"；
 * - 两个动作都顺手收起菜单（点击即离场，不等异步回执）；
 * - onChatActionFailed → errorMessage 细条。
 */

import { Reducer, ReducerEnv, ReducerResult, reduced } from '@tgx/feature-template';
import { ChatListUiState, ChatActionMenuState } from '../contract/ChatListUiState';
import { ChatListItem } from '../model/ChatListItem';
import {
  ChatListIntent,
  ChatSelected,
  OnChatsLoaded,
  OnChatsLoadFailed,
  ChatActionRequested,
  OnChatActionFailed
} from '../contract/ChatListIntent';
import {
  ChatListEffect,
  FetchChatList,
  NavigateToChat,
  ShowToast,
  SetChatArchived,
  SetChatPinned,
  SetChatReadState
} from '../contract/ChatListEffect';

export const CHAT_LIST_PAGE_SIZE: number = 20;

/** 按 chatId 取当前行；不存在返回 null。 */
function findItem(state: ChatListUiState, chatId: number): ChatListItem | null {
  for (let i = 0; i < state.items.length; i++) {
    if (state.items[i].chatId === chatId) {
      return state.items[i];
    }
  }
  return null;
}

/**
 * 是否该显示 "Mark as read"（MSG-108）。
 * 对齐 Android `Tdlib.canMarkAsRead`：`unread_count > 0 || is_marked_as_unread`。
 * 纯函数导出供单测与 UI 复用。
 */
export function canMarkChatAsRead(item: ChatListItem): boolean {
  return item.unreadCount > 0 || item.isMarkedAsUnread;
}

export const chatListReducer: Reducer<ChatListUiState, ChatListIntent, ChatListEffect> = (
  state: ChatListUiState,
  intent: ChatListIntent,
  env: ReducerEnv
): ReducerResult<ChatListUiState, ChatListEffect> => {
  switch (intent.kind) {
    case 'loadChats':
    case 'refreshChats': {
      if (state.isLoading) {
        return reduced(state);
      }
      const nextState: ChatListUiState = state.copyWith({
        isLoading: true,
        errorMessage: null
      });
      const effects: ChatListEffect[] = [new FetchChatList(CHAT_LIST_PAGE_SIZE, state.listKind)];
      return reduced(nextState, effects);
    }

    case 'chatSelected': {
      const selectIntent: ChatSelected = intent as ChatSelected;
      const effects: ChatListEffect[] = [new NavigateToChat(selectIntent.chatId)];
      return reduced(state, effects);
    }

    case 'onChatsLoaded': {
      const loadedIntent: OnChatsLoaded = intent as OnChatsLoaded;
      const nextState: ChatListUiState = state.copyWith({
        items: loadedIntent.items,
        isLoading: false,
        errorMessage: null,
        archiveUnreadCount: loadedIntent.archiveUnreadCount,
        archiveChatCount: loadedIntent.archiveChatCount
      });
      return reduced(nextState);
    }

    case 'onChatsLoadFailed': {
      const failedIntent: OnChatsLoadFailed = intent as OnChatsLoadFailed;
      const nextState: ChatListUiState = state.copyWith({
        isLoading: false,
        errorMessage: failedIntent.error.message
      });
      const effects: ChatListEffect[] = [new ShowToast(failedIntent.error.message)];
      return reduced(nextState, effects);
    }

    case 'openArchivedChats': {
      if (state.listKind === 'archive') {
        return reduced(state);
      }
      const nextState: ChatListUiState = state.copyWith({
        items: [],
        listKind: 'archive',
        isLoading: true,
        actionMenu: null,
        errorMessage: null
      });
      const effects: ChatListEffect[] = [new FetchChatList(CHAT_LIST_PAGE_SIZE, 'archive')];
      return reduced(nextState, effects);
    }

    case 'closeArchivedChats': {
      if (state.listKind === 'main') {
        return reduced(state);
      }
      const nextState: ChatListUiState = state.copyWith({
        items: [],
        listKind: 'main',
        isLoading: true,
        actionMenu: null,
        errorMessage: null
      });
      const effects: ChatListEffect[] = [new FetchChatList(CHAT_LIST_PAGE_SIZE, 'main')];
      return reduced(nextState, effects);
    }

    // ---- MSG-108 单会话操作 ----

    case 'chatActionRequested': {
      const requested: ChatActionRequested = intent as ChatActionRequested;
      const item: ChatListItem | null = findItem(state, requested.chatId);
      if (item === null) {
        return reduced(state);
      }
      const menu: ChatActionMenuState = new ChatActionMenuState(
        item.chatId,
        item.title,
        item.isPinned,
        canMarkChatAsRead(item),
        state.listKind === 'archive'
      );
      return reduced(state.copyWith({ actionMenu: menu }));
    }

    case 'toggleChatPinned': {
      const menu: ChatActionMenuState | null = state.actionMenu;
      if (menu === null) {
        return reduced(state);
      }
      // 菜单记录的是"当前"态，动作是取反。
      const effects: ChatListEffect[] = [new SetChatPinned(menu.chatId, !menu.isPinned)];
      return reduced(state.copyWith({ actionMenu: null, errorMessage: null }), effects);
    }

    case 'toggleChatMarkedUnread': {
      const menu: ChatActionMenuState | null = state.actionMenu;
      if (menu === null) {
        return reduced(state);
      }
      // canMarkAsRead=true（当前有未读/已标未读）→ 执行"标记已读"（markAsUnread=false）
      const markAsUnread: boolean = !menu.canMarkAsRead;
      const effects: ChatListEffect[] = [new SetChatReadState(menu.chatId, markAsUnread)];
      return reduced(state.copyWith({ actionMenu: null, errorMessage: null }), effects);
    }

    case 'toggleChatArchived': {
      const menu: ChatActionMenuState | null = state.actionMenu;
      if (menu === null) {
        return reduced(state);
      }
      const effects: ChatListEffect[] = [new SetChatArchived(menu.chatId, !menu.isArchived)];
      return reduced(state.copyWith({ actionMenu: null, errorMessage: null }), effects);
    }

    case 'dismissChatActionMenu': {
      if (state.actionMenu === null) {
        return reduced(state);
      }
      return reduced(state.copyWith({ actionMenu: null }));
    }

    case 'onChatActionFailed': {
      const failed: OnChatActionFailed = intent as OnChatActionFailed;
      const nextState: ChatListUiState = state.copyWith({
        errorMessage: failed.error.message
      });
      return reduced(nextState);
    }
  }

  return reduced(state);
};
