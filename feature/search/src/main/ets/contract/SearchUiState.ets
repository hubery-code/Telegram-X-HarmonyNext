/**
 * feature/search — 搜索界面状态（SEARCH-101）。
 *
 * 遵循单向数据流与不可变状态约定：
 * 字段均为只读，不可变更新经 copyWith() 派生新实例。
 */

import { UiState } from '@tgx/feature-template';
import { SearchChatItem } from './SearchChatItem';
import { SearchMessageItem } from './SearchMessageItem';

export type SearchTab = 'all' | 'chats' | 'messages' | 'media';

export interface SearchUiStateOptions {
  readonly query?: string;
  readonly isLoading?: boolean;
  readonly activeTab?: SearchTab;
  readonly chatResults?: SearchChatItem[];
  readonly messageResults?: SearchMessageItem[];
  readonly recentSearches?: string[];
  readonly errorMessageKey?: string | null;
}

export class SearchUiState implements UiState {
  readonly query: string;
  readonly isLoading: boolean;
  readonly activeTab: SearchTab;
  readonly chatResults: SearchChatItem[];
  readonly messageResults: SearchMessageItem[];
  readonly recentSearches: string[];
  /**
   * 失败文案的**词典 key**（I18N-HOTSWITCH-102）。以前这里存的是 `searchErrorMessage()`
   * 拼好的英文整句，于是它在状态里一直是旧的：换语言要重新失败一次才换词，
   * 而那三句还从没进过词典（中文界面直接上屏英文）。
   */
  readonly errorMessageKey: string | null;

  constructor(
    query: string,
    isLoading: boolean,
    activeTab: SearchTab,
    chatResults: SearchChatItem[],
    messageResults: SearchMessageItem[],
    recentSearches: string[],
    errorMessageKey: string | null
  ) {
    this.query = query;
    this.isLoading = isLoading;
    this.activeTab = activeTab;
    this.chatResults = chatResults;
    this.messageResults = messageResults;
    this.recentSearches = recentSearches;
    this.errorMessageKey = errorMessageKey;
  }

  static initial(): SearchUiState {
    return new SearchUiState('', false, 'all', [], [], [], null);
  }

  copyWith(options: SearchUiStateOptions): SearchUiState {
    return new SearchUiState(
      options.query !== undefined ? options.query : this.query,
      options.isLoading !== undefined ? options.isLoading : this.isLoading,
      options.activeTab !== undefined ? options.activeTab : this.activeTab,
      options.chatResults !== undefined ? options.chatResults : this.chatResults,
      options.messageResults !== undefined ? options.messageResults : this.messageResults,
      options.recentSearches !== undefined ? options.recentSearches : this.recentSearches,
      options.errorMessageKey !== undefined ? options.errorMessageKey : this.errorMessageKey
    );
  }
}
