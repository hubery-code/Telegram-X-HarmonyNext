/**
 * feature/chat — 会话页纯 Reducer（CHAT-001 + CHAT-003）。
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
  OnMessagesLoadFailed,
  ComposerTextChanged,
  OnMessageSendFailed
} from '../contract/ChatIntent';
import {
  ChatEffect,
  FetchInitialMessages,
  FetchOlderMessages,
  SendTextMessage,
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

    case 'composerTextChanged': {
      const changedIntent: ComposerTextChanged = intent as ComposerTextChanged;
      // 输入即清掉陈旧错误（发送失败/加载失败），不打断正在打的字。
      const nextState: ChatUiState = state.copyWith({
        composerText: changedIntent.text,
        errorMessage: null
      });
      return reduced(nextState);
    }

    case 'sendCurrentMessage': {
      // 空文本（trim 后）不发送；发送后立即清空输入栏（乐观清空，
      // 失败由 OnMessageSendFailed 回灌 errorMessage 提示，不回填文本）。
      const text: string = state.composerText.trim();
      if (text.length === 0) {
        return reduced(state);
      }
      const nextState: ChatUiState = state.copyWith({
        composerText: '',
        errorMessage: null
      });
      const effects: ChatEffect[] = [new SendTextMessage(state.chatId, text)];
      return reduced(nextState, effects);
    }

    case 'onMessageSendFailed': {
      const sendFailedIntent: OnMessageSendFailed = intent as OnMessageSendFailed;
      const nextState: ChatUiState = state.copyWith({
        errorMessage: sendFailedIntent.error.message
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
