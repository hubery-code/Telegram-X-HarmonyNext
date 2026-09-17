/**
 * feature/search — SearchReducer（SEARCH-101）。
 *
 * 纯函数实现：(state, intent, env) -> { state, effects }。
 * - query 为空时清空 results；
 * - 非空时派发 ExecuteSearchEffect；
 * - 维护 recentSearches（去重且最新置顶，上限 10 条）。
 */

import { Reducer, ReducerEnv, ReducerResult, reduced } from '@tgx/feature-template';
import { SearchUiState, SearchUiStateOptions } from '../contract/SearchUiState';
import {
  AddRecentSearch,
  OnSearchFailed,
  OnSearchLoaded,
  PerformSearch,
  SearchFailed,
  SearchIntent,
  SearchSuccess,
  SelectTab,
  UpdateQuery
} from '../contract/SearchIntent';
import {
  ExecuteSearchEffect,
  SaveRecentSearchEffect,
  SearchEffect
} from '../contract/SearchEffect';

export const MAX_RECENT_SEARCHES: number = 10;

export function updateRecentSearches(existing: readonly string[], term: string): string[] {
  const result: string[] = [term];
  for (let i = 0; i < existing.length; i++) {
    if (existing[i] !== term && result.length < MAX_RECENT_SEARCHES) {
      result.push(existing[i]);
    }
  }
  return result;
}

export const searchReducer: Reducer<SearchUiState, SearchIntent, SearchEffect> = (
  state: SearchUiState,
  intent: SearchIntent,
  env: ReducerEnv
): ReducerResult<SearchUiState, SearchEffect> => {
  switch (intent.kind) {
    case 'updateQuery': {
      const updateIntent: UpdateQuery = intent as UpdateQuery;
      if (updateIntent.query.trim().length === 0) {
        const opts: SearchUiStateOptions = {
          query: updateIntent.query,
          isLoading: false,
          chatResults: [],
          messageResults: [],
          errorMessage: null
        };
        return reduced(state.copyWith(opts));
      }
      const opts: SearchUiStateOptions = {
        query: updateIntent.query,
        errorMessage: null
      };
      return reduced(state.copyWith(opts));
    }

    case 'clearQuery': {
      const opts: SearchUiStateOptions = {
        query: '',
        isLoading: false,
        chatResults: [],
        messageResults: [],
        errorMessage: null
      };
      return reduced(state.copyWith(opts));
    }

    case 'selectTab': {
      const tabIntent: SelectTab = intent as SelectTab;
      if (state.activeTab === tabIntent.tab) {
        return reduced(state);
      }
      const trimmedQuery: string = state.query.trim();
      if (trimmedQuery.length === 0) {
        const opts: SearchUiStateOptions = {
          activeTab: tabIntent.tab
        };
        return reduced(state.copyWith(opts));
      }
      const opts: SearchUiStateOptions = {
        activeTab: tabIntent.tab,
        isLoading: true,
        errorMessage: null
      };
      const effects: SearchEffect[] = [
        new ExecuteSearchEffect(trimmedQuery, tabIntent.tab)
      ];
      return reduced(state.copyWith(opts), effects);
    }

    case 'performSearch': {
      const searchIntent: PerformSearch = intent as PerformSearch;
      const trimmedQuery: string = searchIntent.query.trim();
      if (trimmedQuery.length === 0) {
        const opts: SearchUiStateOptions = {
          query: searchIntent.query,
          isLoading: false,
          chatResults: [],
          messageResults: [],
          errorMessage: null
        };
        return reduced(state.copyWith(opts));
      }
      const updatedRecent: string[] = updateRecentSearches(state.recentSearches, trimmedQuery);
      const opts: SearchUiStateOptions = {
        query: searchIntent.query,
        isLoading: true,
        errorMessage: null,
        recentSearches: updatedRecent
      };
      const effects: SearchEffect[] = [
        new ExecuteSearchEffect(trimmedQuery, state.activeTab),
        new SaveRecentSearchEffect(trimmedQuery)
      ];
      return reduced(state.copyWith(opts), effects);
    }

    case 'searchSuccess': {
      const successIntent: SearchSuccess = intent as SearchSuccess;
      const opts: SearchUiStateOptions = {
        isLoading: false,
        chatResults: successIntent.chats,
        messageResults: successIntent.messages,
        errorMessage: null
      };
      return reduced(state.copyWith(opts));
    }

    case 'onSearchLoaded': {
      const loadedIntent: OnSearchLoaded = intent as OnSearchLoaded;
      const opts: SearchUiStateOptions = {
        isLoading: false,
        chatResults: loadedIntent.chats,
        messageResults: loadedIntent.messages,
        errorMessage: null
      };
      return reduced(state.copyWith(opts));
    }

    case 'searchFailed': {
      const failedIntent: SearchFailed = intent as SearchFailed;
      const opts: SearchUiStateOptions = {
        isLoading: false,
        chatResults: [],
        messageResults: [],
        errorMessage: failedIntent.errorMessage
      };
      return reduced(state.copyWith(opts));
    }

    case 'onSearchFailed': {
      const failedIntent: OnSearchFailed = intent as OnSearchFailed;
      const opts: SearchUiStateOptions = {
        isLoading: false,
        chatResults: [],
        messageResults: [],
        errorMessage: failedIntent.errorMessage
      };
      return reduced(state.copyWith(opts));
    }

    case 'addRecentSearch': {
      const addIntent: AddRecentSearch = intent as AddRecentSearch;
      const trimmedTerm: string = addIntent.term.trim();
      if (trimmedTerm.length === 0) {
        return reduced(state);
      }
      const updatedRecent: string[] = updateRecentSearches(state.recentSearches, trimmedTerm);
      const opts: SearchUiStateOptions = {
        recentSearches: updatedRecent
      };
      const effects: SearchEffect[] = [
        new SaveRecentSearchEffect(trimmedTerm)
      ];
      return reduced(state.copyWith(opts), effects);
    }

    case 'clearRecentSearches': {
      if (state.recentSearches.length === 0) {
        return reduced(state);
      }
      const opts: SearchUiStateOptions = {
        recentSearches: []
      };
      return reduced(state.copyWith(opts));
    }

    default:
      return reduced(state);
  }
};
