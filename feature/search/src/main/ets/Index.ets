/**
 * feature/search — 模块统一导出入口（SEARCH-101）。
 */

export { SearchChatItem } from './contract/SearchChatItem';
export { SearchMessageItem } from './contract/SearchMessageItem';
export { SearchTab, SearchUiStateOptions, SearchUiState } from './contract/SearchUiState';
export {
  UpdateQuery,
  ClearQuery,
  SelectTab,
  PerformSearch,
  SearchSuccess,
  SearchFailed,
  AddRecentSearch,
  ClearRecentSearches,
  SearchIntent
} from './contract/SearchIntent';
export {
  ExecuteSearchEffect,
  SaveRecentSearchEffect,
  NavigateToChatEffect,
  SearchEffect
} from './contract/SearchEffect';
export {
  MAX_RECENT_SEARCHES,
  updateRecentSearches,
  searchReducer
} from './reducer/SearchReducer';
export {
  SearchQueryProvider,
  TdlibSearchQueryProvider,
  MockSearchQueryProvider,
  SearchCoordinatorOptions,
  SearchUiStateListener,
  SearchCoordinator
} from './coordinator/SearchCoordinator';
export { SearchPage } from './pages/SearchPage';
