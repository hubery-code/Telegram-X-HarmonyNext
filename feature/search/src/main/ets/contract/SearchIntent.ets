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

export class OnSearchLoaded implements Intent {
  readonly kind: 'onSearchLoaded' = 'onSearchLoaded';
  readonly chats: SearchChatItem[];
  readonly messages: SearchMessageItem[];

  constructor(chats: SearchChatItem[], messages: SearchMessageItem[]) {
    this.chats = chats;
    this.messages = messages;
  }
}

export class SearchFailed implements Intent {
  readonly kind: 'searchFailed' = 'searchFailed';
  /** 词典 key（I18N-HOTSWITCH-102）：状态里传 key 不传串，由页面 `t()` 现取。 */
  readonly errorMessageKey: string;

  constructor(errorMessageKey: string) {
    this.errorMessageKey = errorMessageKey;
  }
}

export class OnSearchFailed implements Intent {
  readonly kind: 'onSearchFailed' = 'onSearchFailed';
  readonly errorMessageKey: string;

  constructor(errorMessageKey: string) {
    this.errorMessageKey = errorMessageKey;
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
  | OnSearchLoaded
  | SearchFailed
  | OnSearchFailed
  | AddRecentSearch
  | ClearRecentSearches;
