/**
 * feature/search — 搜索副作用描述（SEARCH-101）。
 *
 * Effect 是一次性副作用描述，由 Coordinator / Handler 执行，Reducer 严禁直接执行。
 */

import { Effect } from '@tgx/feature-template';

export class ExecuteSearchEffect implements Effect {
  readonly kind: 'executeSearch' = 'executeSearch';
  readonly query: string;
  readonly tab: string;

  constructor(query: string, tab: string) {
    this.query = query;
    this.tab = tab;
  }
}

export class SaveRecentSearchEffect implements Effect {
  readonly kind: 'saveRecentSearch' = 'saveRecentSearch';
  readonly term: string;

  constructor(term: string) {
    this.term = term;
  }
}

export class NavigateToChatEffect implements Effect {
  readonly kind: 'navigateToChat' = 'navigateToChat';
  readonly chatId: number;
  readonly messageId?: number;

  constructor(chatId: number, messageId?: number) {
    this.chatId = chatId;
    this.messageId = messageId;
  }
}

export type SearchEffect =
  | ExecuteSearchEffect
  | SaveRecentSearchEffect
  | NavigateToChatEffect;
