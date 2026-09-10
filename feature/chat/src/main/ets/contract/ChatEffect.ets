/**
 * feature/chat — 会话页副作用描述（CHAT-001）。
 *
 * Effect 是一次性副作用的描述，由 Coordinator 执行，reducer 严禁执行。
 */

import { Effect } from '@tgx/feature-template';

export class FetchInitialMessages implements Effect {
  readonly kind: 'fetchInitialMessages' = 'fetchInitialMessages';
  readonly chatId: number;

  constructor(chatId: number) {
    this.chatId = chatId;
  }
}

export class FetchOlderMessages implements Effect {
  readonly kind: 'fetchOlderMessages' = 'fetchOlderMessages';
  readonly chatId: number;

  constructor(chatId: number) {
    this.chatId = chatId;
  }
}

export class NavigateBack implements Effect {
  readonly kind: 'navigateBack' = 'navigateBack';
}

export type ChatEffect =
  | FetchInitialMessages
  | FetchOlderMessages
  | NavigateBack;
