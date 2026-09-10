/**
 * feature/search — 搜索意图（SEARCH-101）。
 *
 * 用户动作与系统事件均以带 kind 判别字面量的 Intent 形式传递给 Reducer。
 */

import { Intent } from '@tgx/feature-template';
import { SearchChatItem } from './SearchChatItem';
import { SearchMessageItem } from './SearchMessageItem';
import { SearchTab } from './SearchUiState';

export class UpdateQuery implements Intent {
  readonly kind: 'updateQuery' = 'updateQuery';
  readonly query: string;

  constructor(query: string) {
    this.query = query;
  }
}

export class ClearQuery implements Intent {
  readonly kind: 'clearQuery' = 'clearQuery';
}

export class SelectTab implements Intent {
  readonly kind: 'selectTab' = 'selectTab';
  readonly tab: SearchTab;

  constructor(tab: SearchTab) {
    this.tab = tab;
  }
}

export class PerformSearch implements Intent {
  readonly kind: 'performSearch' = 'performSearch';
  readonly query: string;

  constructor(query: string) {
    this.query = query;
  }
}

export class SearchSuccess implements Intent {
  readonly kind: 'searchSuccess' = 'searchSuccess';
  readonly chats: SearchChatItem[];
  readonly messages: SearchMessageItem[];

  constructor(chats: SearchChatItem[], messages: SearchMessageItem[]) {
    this.chats = chats;
    this.messages = messages;
  }
}

export class SearchFailed implements Intent {
  readonly kind: 'searchFailed' = 'searchFailed';
  readonly errorMessage: string;

  constructor(errorMessage: string) {
    this.errorMessage = errorMessage;
  }
}

export class AddRecentSearch implements Intent {
  readonly kind: 'addRecentSearch' = 'addRecentSearch';
  readonly term: string;

  constructor(term: string) {
    this.term = term;
  }
}

export class ClearRecentSearches implements Intent {
  readonly kind: 'clearRecentSearches' = 'clearRecentSearches';
}

export type SearchIntent =
  | UpdateQuery
  | ClearQuery
  | SelectTab
  | PerformSearch
  | SearchSuccess
  | SearchFailed
  | AddRecentSearch
  | ClearRecentSearches;
