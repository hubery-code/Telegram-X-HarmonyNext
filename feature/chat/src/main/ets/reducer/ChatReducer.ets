/**
 * feature/chat — 会话页纯 Reducer（CHAT-001）。
 *
 * 遵循计划 §5.11 / UI-003：
 * - 纯函数：(state, intent, env) -> ReducerResult<ChatUiState, ChatEffect>
 * - 禁止直接修改 state；无变化返回原引用 reduced(state)
 * - 禁止在 reducer 内做 I/O 或异步，加载请求只产出 Fetch* 描述
 */

import { Reducer, ReducerEnv, ReducerResult, reduced } from '@tgx/feature-template';
import { ChatUiState } from '../contract/ChatUiState';
import {
  ChatIntent,
  OnMessagesLoaded,
  OnMessagesLoadFailed
} from '../contract/ChatIntent';
import {
  ChatEffect,
  FetchInitialMessages,
  FetchOlderMessages,
  NavigateBack
} from '../contract/ChatEffect';

export const chatReducer: Reducer<ChatUiState, ChatIntent, ChatEffect> = (
  state: ChatUiState,
  intent: ChatIntent,
  env: ReducerEnv
): ReducerResult<ChatUiState, ChatEffect> => {
  switch (intent.kind) {
    case 'loadInitialMessages': {
      if (state.isLoading || state.messages.length > 0) {
        return reduced(state);
      }
      const nextState: ChatUiState = state.copyWith({
        isLoading: true,
        errorMessage: null
      });
      const effects: ChatEffect[] = [new FetchInitialMessages(state.chatId)];
      return reduced(nextState, effects);
    }

    case 'loadOlderMessages': {
      if (state.isLoading || !state.hasMoreOlder) {
        return reduced(state);
      }
      const nextState: ChatUiState = state.copyWith({
        isLoading: true,
        errorMessage: null
      });
      const effects: ChatEffect[] = [new FetchOlderMessages(state.chatId)];
      return reduced(nextState, effects);
    }

    case 'onMessagesLoaded': {
      const loadedIntent: OnMessagesLoaded = intent as OnMessagesLoaded;
      const nextState: ChatUiState = state.copyWith({
        messages: loadedIntent.messages,
        hasMoreOlder: loadedIntent.hasMoreOlder,
        isLoading: false,
        errorMessage: null
      });
      return reduced(nextState);
    }

    case 'onMessagesLoadFailed': {
      const failedIntent: OnMessagesLoadFailed = intent as OnMessagesLoadFailed;
      const nextState: ChatUiState = state.copyWith({
        isLoading: false,
        errorMessage: failedIntent.error.message
      });
      return reduced(nextState);
    }

    case 'backToChatList': {
      const effects: ChatEffect[] = [new NavigateBack()];
      return reduced(state, effects);
    }
  }

  return reduced(state);
};
