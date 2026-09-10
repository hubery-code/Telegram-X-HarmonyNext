/**
 * feature/chat — 会话页协调器（CHAT-001 + CHAT-002 基础）。
 *
 * 桥接 core/domain 的 MessageProjection 与本模块的 MVI：
 * - dispatch 经 chatReducer 驱动 ChatUiState，并执行 Effect
 *   （FetchInitialMessages / FetchOlderMessages → projection 的 getChatHistory 分页；
 *   NavigateBack → onBack 回调，由装配层销毁本 coordinator 并切回会话列表）；
 * - projection 状态变化时把 Message 映射为 MessageItem[]（文本消息取原文，
 *   多媒体按类型出占位标签），经 OnMessagesLoaded 回灌 reducer；
 * - TDLib 更新成批到达，经 setTimeout(0) 合并为一个同步点，避免反复重绘。
 *
 * 生命周期：start() 打开会话（openChat + 首屏加载），destroy() 关闭（closeChat）。
 */

import { hilog } from '@kit.PerformanceAnalysisKit';
import { ManualClock, SequentialIdGenerator, AppError } from '@tgx/core-common';
import { AccountScope } from '@tgx/core-account';
import {
  Message,
  MessageText,
  TdMessageContent
} from '@tgx/core-td-api-generated';
import { MessageListState, MessageProjection } from '@tgx/core-domain';
import { TdPendingRequest, TdWireObject } from '@tgx/td-gateway';
import { Result } from '@tgx/core-common';
import { ReducerEnv, ReducerResult } from '@tgx/feature-template';
import { MessageItem } from '../model/MessageItem';
import { ChatUiState } from '../contract/ChatUiState';
import {
  ChatIntent,
  LoadInitialMessages,
  OnMessagesLoaded,
  OnMessagesLoadFailed
} from '../contract/ChatIntent';
import { ChatEffect } from '../contract/ChatEffect';
import { chatReducer } from '../reducer/ChatReducer';

const DOMAIN: number = 0x0000;
const TAG: string = 'ChatCoordinator';
const INITIAL_PAGE_SIZE: number = 30;
const OLDER_PAGE_SIZE: number = 20;

export type ChatUiStateListener = (state: ChatUiState) => void;

/** 气泡正文：文本消息取原文；多媒体/服务消息用占位标签（CHAT-002 后续替换为真实 renderer）。 */
export function messageContentText(content: TdMessageContent | null): string {
  if (content === null) {
    return '';
  }
  switch (content.type) {
    case 'messageText': {
      const text = (content as MessageText).text;
      return text !== null ? text.text : '';
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
    case 'messageUnsupported':
      return '[Unsupported message]';
    default:
      return '';
  }
}

export class ChatCoordinator {
  private readonly projection: MessageProjection;
  private readonly env: ReducerEnv;
  private readonly onBack: () => void;
  private currentState: ChatUiState;
  private readonly listeners: ChatUiStateListener[] = [];
  private syncScheduled: boolean = false;
  private destroyed: boolean = false;

  constructor(
    scope: AccountScope,
    chatId: number,
    chatTitle: string,
    onBack?: () => void,
    env?: ReducerEnv
  ) {
    this.projection = new MessageProjection(chatId, scope);
    this.onBack = onBack !== undefined ? onBack : (): void => {};
    this.env = env !== undefined ? env : {
      clock: new ManualClock(1000, 500),
      ids: new SequentialIdGenerator('chat-')
    };
    this.currentState = new ChatUiState(chatId, chatTitle, [], false, true, null);
  }

  get state(): ChatUiState {
    return this.currentState;
  }

  start(): void {
    this.projection.setOnStateChanged(() => {
      this.scheduleSyncFromProjection();
    });
    this.projection.start();
    this.dispatch(new LoadInitialMessages());
  }

  destroy(): void {
    this.destroyed = true;
    this.projection.setOnStateChanged(null);
    this.projection.stop();
    this.listeners.length = 0;
  }

  subscribe(listener: ChatUiStateListener): () => void {
    this.listeners.push(listener);
    listener(this.currentState);
    return () => {
      const idx: number = this.listeners.indexOf(listener);
      if (idx >= 0) {
        this.listeners.splice(idx, 1);
      }
    };
  }

  dispatch(intent: ChatIntent): void {
    const result: ReducerResult<ChatUiState, ChatEffect> = chatReducer(
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
    const projectionState: MessageListState = this.projection.state;
    const items: MessageItem[] = [];
    for (let i = 0; i < projectionState.messages.length; i++) {
      items.push(this.mapMessageToItem(projectionState.messages[i]));
    }
    this.dispatch(new OnMessagesLoaded(items, projectionState.hasMoreOlder));
  }

  private mapMessageToItem(message: Message): MessageItem {
    return new MessageItem(
      message.id,
      messageContentText(message.content),
      message.date * 1000,
      message.is_outgoing,
      '' // senderName：user registry 未建（CHAT-002 后续）
    );
  }

  private executeEffect(effect: ChatEffect): void {
    switch (effect.kind) {
      case 'fetchInitialMessages': {
        hilog.info(DOMAIN, TAG, 'fetch initial messages chatId=%{public}s', `${this.currentState.chatId}`);
        this.runFetch(this.projection.loadInitialMessages(INITIAL_PAGE_SIZE));
        break;
      }

      case 'fetchOlderMessages': {
        hilog.info(DOMAIN, TAG, 'fetch older messages chatId=%{public}s', `${this.currentState.chatId}`);
        this.runFetch(this.projection.loadOlderMessages(OLDER_PAGE_SIZE));
        break;
      }

      case 'navigateBack': {
        hilog.info(DOMAIN, TAG, 'back to chat list from chatId=%{public}s', `${this.currentState.chatId}`);
        this.onBack();
        break;
      }

      default:
        break;
    }
  }

  /** null = 投影侧跳过（正在加载/已到顶端）；请求级与响应级失败都回灌 OnMessagesLoadFailed。 */
  private runFetch(result: Result<TdPendingRequest, AppError> | null): void {
    if (result === null) {
      return;
    }
    if (result.err) {
      hilog.error(DOMAIN, TAG, 'getChatHistory rejected: %{public}s', result.error.message);
      this.dispatch(new OnMessagesLoadFailed(result.error));
    }
    if (result.ok) {
      result.value.promise.then((res: Result<TdWireObject, AppError>) => {
        if (res.err) {
          hilog.error(DOMAIN, TAG, 'getChatHistory failed: %{public}s', res.error.message);
          if (!this.destroyed) {
            this.dispatch(new OnMessagesLoadFailed(res.error));
          }
        }
      }).catch(() => {
      });
    }
  }
}
