/**
 * feature/chat_list — 会话列表协调器（CHATLIST-003）。
 *
 * 桥接 core/domain 的 ChatListProjection 与本模块的 MVI：
 * - dispatch 经 chatListReducer 驱动 ChatListUiState，并执行 Effect
 *   （FetchChatList → projection.loadNextPage）；
 * - projection 状态变化时把 registry 中的 Chat 映射为 ChatListItem[]，
 *   经 OnChatsLoaded 回灌 reducer；
 * - TDLib 更新在登录初期成批到达，经 setTimeout(0) 合并为一个同步点，
 *   避免整表反复重绘。
 */

import { hilog } from '@kit.PerformanceAnalysisKit';
import { ManualClock, SequentialIdGenerator } from '@tgx/core-common';
import { AccountScope } from '@tgx/core-account';
import {
  Chat,
  ChatListMain,
  Message,
  MessageText,
  TdMessageContent
} from '@tgx/core-td-api-generated';
import { ChatListProjection, ChatListState, ChatRegistry } from '@tgx/core-domain';
import { ReducerEnv, ReducerResult } from '@tgx/feature-template';
import { ChatListItem, avatarColorForChatId, avatarLetterForTitle } from '../model/ChatListItem';
import { ChatListUiState } from '../contract/ChatListUiState';
import {
  ChatListIntent,
  LoadChats,
  OnChatsLoaded,
  OnChatsLoadFailed
} from '../contract/ChatListIntent';
import {
  ChatListEffect,
  FetchChatList,
  NavigateToChat,
  ShowToast
} from '../contract/ChatListEffect';
import { chatListReducer } from '../reducer/ChatListReducer';

const DOMAIN: number = 0x0000;
const TAG: string = 'ChatListCoordinator';

export type ChatListUiStateListener = (state: ChatListUiState) => void;

/** 最后一条消息的一行预览文案；多媒体消息用占位标签。 */
function messagePreview(message: Message | null): string {
  if (message === null || message.content === null) {
    return '';
  }
  const content: TdMessageContent = message.content;
  switch (content.type) {
    case 'messageText': {
      const text = (content as MessageText).text;
      return text !== null ? text.text.split('\n').join(' ') : '';
    }
    case 'messagePhoto':
      return '[Photo]';
    case 'messageVideo':
      return '[Video]';
    case 'messageAnimation':
      return '[GIF]';
    case 'messageAudio':
      return '[Audio]';
    case 'messageVoiceNote':
      return '[Voice message]';
    case 'messageVideoNote':
      return '[Video message]';
    case 'messageDocument':
      return '[Document]';
    case 'messageSticker':
      return '[Sticker]';
    case 'messageLocation':
    case 'messageLiveLocation':
      return '[Location]';
    case 'messageVenue':
      return '[Venue]';
    case 'messageContact':
      return '[Contact]';
    case 'messagePoll':
      return '[Poll]';
    case 'messageCall':
      return '[Call]';
    case 'messageGame':
      return '[Game]';
    default:
      return '';
  }
}

export class ChatListCoordinator {
  private readonly registry: ChatRegistry;
  private readonly projection: ChatListProjection;
  private readonly env: ReducerEnv;
  private currentState: ChatListUiState;
  private readonly listeners: ChatListUiStateListener[] = [];
  private syncScheduled: boolean = false;
  private destroyed: boolean = false;

  constructor(scope: AccountScope, env?: ReducerEnv) {
    this.registry = new ChatRegistry();
    this.projection = new ChatListProjection(new ChatListMain(), this.registry, scope);
    this.env = env !== undefined ? env : {
      clock: new ManualClock(1000, 500),
      ids: new SequentialIdGenerator('chat-list-')
    };
    this.currentState = ChatListUiState.initial();
  }

  get state(): ChatListUiState {
    return this.currentState;
  }

  start(): void {
    this.projection.setOnStateChanged(() => {
      this.scheduleSyncFromProjection();
    });
    this.projection.start();
    this.dispatch(new LoadChats());
  }

  destroy(): void {
    this.destroyed = true;
    this.projection.setOnStateChanged(null);
    this.projection.stop();
    this.listeners.length = 0;
  }

  subscribe(listener: ChatListUiStateListener): () => void {
    this.listeners.push(listener);
    listener(this.currentState);
    return () => {
      const idx: number = this.listeners.indexOf(listener);
      if (idx >= 0) {
        this.listeners.splice(idx, 1);
      }
    };
  }

  dispatch(intent: ChatListIntent): void {
    const result: ReducerResult<ChatListUiState, ChatListEffect> = chatListReducer(
      this.currentState,
      intent,
      this.env
    );

    const stateChanged: boolean = result.state !== this.currentState;
    this.currentState = result.state;

    if (stateChanged) {
      for (let i = 0; i < this.listeners.length; i++) {
        this.listeners[i](this.currentState);
      }
    }

    if (result.effects.length > 0) {
      for (let i = 0; i < result.effects.length; i++) {
        this.executeEffect(result.effects[i]);
      }
    }
  }

  private scheduleSyncFromProjection(): void {
    if (this.syncScheduled || this.destroyed) {
      return;
    }
    this.syncScheduled = true;
    setTimeout(() => {
      this.syncScheduled = false;
      if (!this.destroyed) {
        this.syncFromProjection();
      }
    }, 0);
  }

  private syncFromProjection(): void {
    const projectionState: ChatListState = this.projection.state;
    const items: ChatListItem[] = this.mapChatsToItems(projectionState.chatIds);
    this.dispatch(new OnChatsLoaded(items));
  }

  private mapChatsToItems(chatIds: readonly number[]): ChatListItem[] {
    const items: ChatListItem[] = [];
    for (let i = 0; i < chatIds.length; i++) {
      const chat: Chat | undefined = this.registry.getChat(chatIds[i]);
      if (chat === undefined) {
        continue;
      }
      items.push(new ChatListItem(
        chat.id,
        chat.title,
        messagePreview(chat.last_message),
        chat.last_message !== null ? chat.last_message.date * 1000 : 0,
        chat.unread_count,
        avatarColorForChatId(chat.id),
        avatarLetterForTitle(chat.title)
      ));
    }
    return items;
  }

  private executeEffect(effect: ChatListEffect): void {
    switch (effect.kind) {
      case 'fetchChatList': {
        const fetchEffect: FetchChatList = effect as FetchChatList;
        hilog.info(DOMAIN, TAG, 'executing loadChats limit=%{public}d', fetchEffect.limit);
        const result = this.projection.loadNextPage(fetchEffect.limit);
        if (result.err) {
          hilog.error(DOMAIN, TAG, 'loadChats rejected: %{public}s', result.error.message);
          this.dispatch(new OnChatsLoadFailed(result.error));
        }
        break;
      }

      case 'navigateToChat': {
        // 会话页（CHAT-001）尚未落地，先记录日志
        const navigateEffect: NavigateToChat = effect as NavigateToChat;
        hilog.info(DOMAIN, TAG, 'chat selected: %{public}s', `${navigateEffect.chatId}`);
        break;
      }

      case 'showToast': {
        const toastEffect: ShowToast = effect as ShowToast;
        hilog.info(DOMAIN, TAG, 'toast: %{public}s', toastEffect.messageKey);
        break;
      }

      default:
        break;
    }
  }
}
