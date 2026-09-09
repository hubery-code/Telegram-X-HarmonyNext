/**
 * feature/chat_list — 会话列表纯 Reducer（CHATLIST-002）。
 *
 * 遵循计划 §5.11 / UI-003：
 * - 纯函数：(state, intent, env) -> ReducerResult<ChatListUiState, ChatListEffect>
 * - 禁止直接修改 state；无变化返回原引用 reduced(state)
 * - 禁止在 reducer 内做 I/O 或异步，加载请求只产出 FetchChatList 描述
 */

import { Reducer, ReducerEnv, ReducerResult, reduced } from '@tgx/feature-template';
import { ChatListUiState } from '../contract/ChatListUiState';
import {
  ChatListIntent,
  ChatSelected,
  OnChatsLoaded,
  OnChatsLoadFailed
} from '../contract/ChatListIntent';
import {
  ChatListEffect,
  FetchChatList,
  NavigateToChat,
  ShowToast
} from '../contract/ChatListEffect';

export const CHAT_LIST_PAGE_SIZE: number = 20;

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
      const effects: ChatListEffect[] = [new FetchChatList(CHAT_LIST_PAGE_SIZE)];
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
        errorMessage: null
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
  }

  return reduced(state);
};
