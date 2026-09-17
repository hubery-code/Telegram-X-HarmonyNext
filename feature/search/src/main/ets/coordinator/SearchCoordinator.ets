/**
 * feature/search — 搜索协调器（SEARCH-101）。
 *
 * 桥接 UI 层、Reducer 状态机与底层 TDLib / 数据源：
 * - 支持防抖（默认 300ms）；
 * - 封装 TDLib searchChats / searchMessages 与统一查询契约；
 * - 提供状态订阅 subscribe(listener: (state: SearchUiState) => void): () => void。
 */

import { Logger } from '@tgx/observability';
import {
  AppError,
  AppErrors,
  Result,
  SequentialIdGenerator,
  SystemClock,
  err,
  ok
} from '@tgx/core-common';
import { AccountScope } from '@tgx/core-account';
import {
  Chats,
  FoundMessages,
  Message,
  MessageText,
  SearchChats,
  SearchMessages,
  decodeChats,
  decodeFoundMessages,
  encodeSearchChats,
  encodeSearchMessages
} from '@tgx/core-td-api-generated';
import { TdWireObject } from '@tgx/td-gateway';
import { ReducerEnv, ReducerResult } from '@tgx/feature-template';
import { SearchChatItem } from '../contract/SearchChatItem';
import { SearchMessageItem } from '../contract/SearchMessageItem';
import { SearchTab, SearchUiState } from '../contract/SearchUiState';
import {
  AddRecentSearch,
  ClearQuery,
  ClearRecentSearches,
  PerformSearch,
  SearchFailed,
  SearchIntent,
  SearchSuccess,
  SelectTab,
  UpdateQuery
} from '../contract/SearchIntent';
import {
  ExecuteSearchEffect,
  NavigateToChatEffect,
  SaveRecentSearchEffect,
  SearchEffect
} from '../contract/SearchEffect';
import { searchReducer } from '../reducer/SearchReducer';

const TAG: string = 'SearchCoordinator';

function formatMessageDate(unixSeconds: number): string {
  const date: Date = new Date(unixSeconds * 1000);
  const hours: string = date.getHours() < 10 ? `0${date.getHours()}` : `${date.getHours()}`;
  const minutes: string = date.getMinutes() < 10 ? `0${date.getMinutes()}` : `${date.getMinutes()}`;
  return `${hours}:${minutes}`;
}

export interface SearchQueryProvider {
  searchChats(query: string, limit: number): Promise<Result<SearchChatItem[], AppError>>;
  searchMessages(query: string, limit: number): Promise<Result<SearchMessageItem[], AppError>>;
}

export function searchErrorMessage(error: AppError): string {
  const causeLower: string = (error.cause !== undefined ? error.cause : '').toLowerCase();
  const messageLower: string = (error.message !== undefined ? error.message : '').toLowerCase();
  if (
    (error.kind === 'tdlib' && error.code === 'too_many_requests') ||
    causeLower.indexOf('flood') >= 0 ||
    messageLower.indexOf('flood') >= 0
  ) {
    return 'Too many searches. Please wait a moment and try again.';
  }
  if (error.kind === 'network') {
    return 'Search is temporarily unavailable. Check your connection and try again.';
  }
  return 'Search failed. Please try again.';
}

/**
 * FIX-001：会话元数据解析回调。
 * TDLib 的 searchChats 只回 chat_ids（Chats 对象里没有标题），而会话标题/用户名
 * 在会话列表的本地缓存里。feature/search 不能直接依赖 feature/chat_list，
 * 所以由装配层（entry）注入——命中本地缓存、无网络往返；返回 null 表示该
 * 会话尚未注册（如按用户名搜到的、还不在会话列表里的公开会话）。
 */
export interface SearchChatMetadata {
  readonly title: string;
  readonly username: string;
}

export type SearchChatMetadataResolver = (chatId: number) => SearchChatMetadata | null;

export class TdlibSearchQueryProvider implements SearchQueryProvider {
  private readonly scope: AccountScope;
  private readonly resolveChatMetadata: SearchChatMetadataResolver | null;
  private readonly logger: Logger;

  constructor(scope: AccountScope, resolveChatMetadata?: SearchChatMetadataResolver, logger?: Logger) {
    this.scope = scope;
    this.resolveChatMetadata = resolveChatMetadata !== undefined ? resolveChatMetadata : null;
    this.logger = logger !== undefined ? logger : new Logger();
  }

  /** 标题/用户名：本地缓存命中就用真值，未命中回退占位符（保证列表仍可用）。 */
  private titleOf(chatId: number): string {
    const meta: SearchChatMetadata | null = this.metadataOf(chatId);
    return meta !== null && meta.title.length > 0 ? meta.title : `Chat ${chatId}`;
  }

  private usernameOf(chatId: number): string {
    const meta: SearchChatMetadata | null = this.metadataOf(chatId);
    return meta !== null ? meta.username : '';
  }

  private metadataOf(chatId: number): SearchChatMetadata | null {
    return this.resolveChatMetadata !== null ? this.resolveChatMetadata(chatId) : null;
  }

  async searchChats(query: string, limit: number): Promise<Result<SearchChatItem[], AppError>> {
    const req = new SearchChats();
    req.query = query;
    req.limit = limit;
    const reqObj: TdWireObject = encodeSearchChats(req) as TdWireObject;
    const result = this.scope.request('searchChats', reqObj);

    if (result.ok) {
      const pending = result.value;
      const response = await pending.promise;
      if (response.ok) {
        const chats: Chats | null = decodeChats(response.value);
        if (chats !== null) {
          const items: SearchChatItem[] = [];
          for (let i = 0; i < chats.chat_ids.length; i++) {
            const chatId: number = chats.chat_ids[i];
            items.push(new SearchChatItem(
              chatId,
              this.titleOf(chatId),
              this.usernameOf(chatId),
              null,
              false,
              false
            ));
          }
          return ok<SearchChatItem[], AppError>(items);
        }
        const decodeError: AppError = AppErrors.internal(
          'search_chats_decode',
          'TDLib searchChats response could not be decoded'
        );
        this.logger.logError(TAG, decodeError);
        return err<SearchChatItem[], AppError>(decodeError);
      }
      if (response.err) {
        this.logger.logError(TAG, response.error);
        return err<SearchChatItem[], AppError>(response.error);
      }
    }
    if (result.err) {
      this.logger.logError(TAG, result.error);
      return err<SearchChatItem[], AppError>(result.error);
    }
    return err<SearchChatItem[], AppError>(
      AppErrors.internal('search_chats_result', 'TDLib searchChats returned no result')
    );
  }

  async searchMessages(query: string, limit: number): Promise<Result<SearchMessageItem[], AppError>> {
    const req = new SearchMessages();
    req.query = query;
    req.limit = limit;
    const reqObj: TdWireObject = encodeSearchMessages(req) as TdWireObject;
    const result = this.scope.request('searchMessages', reqObj);

    if (result.ok) {
      const pending = result.value;
      const response = await pending.promise;
      if (response.ok) {
        const found: FoundMessages | null = decodeFoundMessages(response.value);
        if (found !== null) {
          const items: SearchMessageItem[] = [];
          for (let i = 0; i < found.messages.length; i++) {
            const msg: Message = found.messages[i];
            let textSnippet: string = '';
            if (msg.content !== null && msg.content.type === 'messageText') {
              const textContent: MessageText = msg.content as MessageText;
              if (textContent.text !== null) {
                textSnippet = textContent.text.text;
              }
            }
            items.push(new SearchMessageItem(
              msg.id,
              msg.chat_id,
              this.titleOf(msg.chat_id),
              'Sender',
              textSnippet,
              formatMessageDate(msg.date)
            ));
          }
          return ok<SearchMessageItem[], AppError>(items);
        }
        const decodeError: AppError = AppErrors.internal(
          'search_messages_decode',
          'TDLib searchMessages response could not be decoded'
        );
        this.logger.logError(TAG, decodeError);
        return err<SearchMessageItem[], AppError>(decodeError);
      }
      if (response.err) {
        this.logger.logError(TAG, response.error);
        return err<SearchMessageItem[], AppError>(response.error);
      }
    }
    if (result.err) {
      this.logger.logError(TAG, result.error);
      return err<SearchMessageItem[], AppError>(result.error);
    }
    return err<SearchMessageItem[], AppError>(
      AppErrors.internal('search_messages_result', 'TDLib searchMessages returned no result')
    );
  }
}

export class MockSearchQueryProvider implements SearchQueryProvider {
  private readonly mockChats: SearchChatItem[];
  private readonly mockMessages: SearchMessageItem[];

  constructor(mockChats?: SearchChatItem[], mockMessages?: SearchMessageItem[]) {
    this.mockChats = mockChats !== undefined ? mockChats : [
      new SearchChatItem(1, 'Telegram News', 'telegram', null, true, false),
      new SearchChatItem(2, 'Telegram X Beta', 'tgxbeta', null, false, true),
      new SearchChatItem(3, 'HarmonyOS Developers', 'harmony_dev', null, false, true),
      new SearchChatItem(4, 'ArkTS Community', 'arkts_chat', null, false, true)
    ];
    this.mockMessages = mockMessages !== undefined ? mockMessages : [
      new SearchMessageItem(101, 1, 'Telegram News', 'Telegram', 'Welcome to Telegram X on HarmonyOS NEXT!', '10:30'),
      new SearchMessageItem(102, 2, 'Telegram X Beta', 'Alice', 'Testing the global search feature', '11:15'),
      new SearchMessageItem(103, 3, 'HarmonyOS Developers', 'Bob', 'ArkTS strict typing rules are important', '12:00'),
      new SearchMessageItem(104, 4, 'ArkTS Community', 'Charlie', 'MVI and Reducer pattern works smoothly', '14:20')
    ];
  }

  async searchChats(query: string, limit: number): Promise<Result<SearchChatItem[], AppError>> {
    const q: string = query.toLowerCase();
    const filtered: SearchChatItem[] = [];
    for (let i = 0; i < this.mockChats.length; i++) {
      const chat: SearchChatItem = this.mockChats[i];
      if (chat.title.toLowerCase().indexOf(q) >= 0 || chat.username.toLowerCase().indexOf(q) >= 0) {
        filtered.push(chat);
        if (filtered.length >= limit) {
          break;
        }
      }
    }
    return ok<SearchChatItem[], AppError>(filtered);
  }

  async searchMessages(query: string, limit: number): Promise<Result<SearchMessageItem[], AppError>> {
    const q: string = query.toLowerCase();
    const filtered: SearchMessageItem[] = [];
    for (let i = 0; i < this.mockMessages.length; i++) {
      const msg: SearchMessageItem = this.mockMessages[i];
      if (
        msg.textSnippet.toLowerCase().indexOf(q) >= 0 ||
        msg.chatTitle.toLowerCase().indexOf(q) >= 0 ||
        msg.senderName.toLowerCase().indexOf(q) >= 0
      ) {
        filtered.push(msg);
        if (filtered.length >= limit) {
          break;
        }
      }
    }
    return ok<SearchMessageItem[], AppError>(filtered);
  }
}

export interface SearchCoordinatorOptions {
  readonly scope?: AccountScope;
  readonly provider?: SearchQueryProvider;
  readonly env?: ReducerEnv;
  readonly onNavigateToChat?: (chatId: number, messageId?: number) => void;
  readonly debounceMs?: number;
  readonly throttleMs?: number;
  /** FIX-001：会话元数据解析（由装配层注入会话列表的本地缓存查询）。 */
  readonly resolveChatMetadata?: SearchChatMetadataResolver;
  readonly logger?: Logger;
}

export type SearchUiStateListener = (state: SearchUiState) => void;

class PendingSearch {
  readonly requestId: number;
  readonly query: string;
  readonly tab: string;
  readonly key: string;

  constructor(requestId: number, query: string, tab: string) {
    this.requestId = requestId;
    this.query = query;
    this.tab = tab;
    this.key = `${tab}:${query}`;
  }
}

export class SearchCoordinator {
  private readonly provider: SearchQueryProvider;
  private readonly env: ReducerEnv;
  private readonly onNavigateToChat: (chatId: number, messageId?: number) => void;
  private readonly debounceMs: number;
  private readonly throttleMs: number;
  private readonly logger: Logger;
  private currentState: SearchUiState;
  private readonly listeners: SearchUiStateListener[] = [];
  private debounceTimerId: number | null = null;
  private throttleTimerId: number | null = null;
  private pendingSearch: PendingSearch | null = null;
  private inFlightSearchKey: string | null = null;
  private inFlightSearchRequestId: number | null = null;
  private lastSearchStartedAtMillis: number | null = null;
  private activeSearchRequestId: number = 0;
  private destroyed: boolean = false;

  constructor(options?: SearchCoordinatorOptions) {
    this.logger = (options !== undefined && options.logger !== undefined) ? options.logger : new Logger();
    if (options !== undefined && options.provider !== undefined) {
      this.provider = options.provider;
    } else if (options !== undefined && options.scope !== undefined) {
      this.provider = new TdlibSearchQueryProvider(options.scope, options.resolveChatMetadata, this.logger);
    } else {
      this.provider = new MockSearchQueryProvider();
    }

    this.env = options !== undefined && options.env !== undefined ? options.env : {
      clock: new SystemClock(),
      ids: new SequentialIdGenerator('search-')
    };

    this.onNavigateToChat = options !== undefined && options.onNavigateToChat !== undefined
      ? options.onNavigateToChat
      : (chatId: number, messageId?: number): void => {};

    this.debounceMs = options !== undefined && options.debounceMs !== undefined
      ? options.debounceMs
      : 300;
    this.throttleMs = options !== undefined && options.throttleMs !== undefined
      ? Math.max(0, options.throttleMs)
      : 750;

    this.currentState = SearchUiState.initial();
  }

  get state(): SearchUiState {
    return this.currentState;
  }

  subscribe(listener: SearchUiStateListener): () => void {
    this.listeners.push(listener);
    listener(this.currentState);
    return () => {
      const idx: number = this.listeners.indexOf(listener);
      if (idx >= 0) {
        this.listeners.splice(idx, 1);
      }
    };
  }

  destroy(): void {
    this.destroyed = true;
    if (this.debounceTimerId !== null) {
      clearTimeout(this.debounceTimerId);
      this.debounceTimerId = null;
    }
    if (this.throttleTimerId !== null) {
      clearTimeout(this.throttleTimerId);
      this.throttleTimerId = null;
    }
    this.pendingSearch = null;
    this.activeSearchRequestId++;
    this.listeners.length = 0;
  }

  dispatch(intent: SearchIntent): void {
    const result: ReducerResult<SearchUiState, SearchEffect> = searchReducer(
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

  updateQuery(query: string): void {
    if (this.debounceTimerId !== null) {
      clearTimeout(this.debounceTimerId);
      this.debounceTimerId = null;
    }

    this.dispatch(new UpdateQuery(query));

    const trimmed: string = query.trim();
    if (trimmed.length === 0) {
      return;
    }

    this.debounceTimerId = setTimeout(() => {
      this.debounceTimerId = null;
      if (!this.destroyed) {
        this.dispatch(new PerformSearch(query));
      }
    }, this.debounceMs);
  }

  performSearchImmediate(query: string): void {
    if (this.debounceTimerId !== null) {
      clearTimeout(this.debounceTimerId);
      this.debounceTimerId = null;
    }
    this.dispatch(new PerformSearch(query));
  }

  clearQuery(): void {
    if (this.debounceTimerId !== null) {
      clearTimeout(this.debounceTimerId);
      this.debounceTimerId = null;
    }
    this.cancelPendingSearch();
    this.dispatch(new ClearQuery());
  }

  selectTab(tab: SearchTab): void {
    this.dispatch(new SelectTab(tab));
  }

  addRecentSearch(term: string): void {
    this.dispatch(new AddRecentSearch(term));
  }

  clearRecentSearches(): void {
    this.dispatch(new ClearRecentSearches());
  }

  navigateToChat(chatId: number, messageId?: number): void {
    this.onNavigateToChat(chatId, messageId);
  }

  private executeEffect(effect: SearchEffect): void {
    switch (effect.kind) {
      case 'executeSearch': {
        const searchEffect: ExecuteSearchEffect = effect as ExecuteSearchEffect;
        this.scheduleSearch(searchEffect.query, searchEffect.tab);
        break;
      }
      case 'saveRecentSearch': {
        const saveEffect: SaveRecentSearchEffect = effect as SaveRecentSearchEffect;
        this.logger.info(TAG, 'saved_recent_search', `len=${saveEffect.term.length}`);
        break;
      }
      case 'navigateToChat': {
        const navEffect: NavigateToChatEffect = effect as NavigateToChatEffect;
        this.onNavigateToChat(navEffect.chatId, navEffect.messageId);
        break;
      }
      default:
        break;
    }
  }

  private cancelPendingSearch(): void {
    if (this.throttleTimerId !== null) {
      clearTimeout(this.throttleTimerId);
      this.throttleTimerId = null;
    }
    this.pendingSearch = null;
    this.activeSearchRequestId++;
  }

  private scheduleSearch(query: string, tab: string): void {
    const trimmedQuery: string = query.trim();
    const key: string = `${tab}:${trimmedQuery}`;
    const sameActiveRequest: boolean = this.inFlightSearchKey === key &&
      this.inFlightSearchRequestId === this.activeSearchRequestId;
    if (sameActiveRequest || (this.pendingSearch !== null && this.pendingSearch.key === key)) {
      return;
    }

    const request: PendingSearch = new PendingSearch(++this.activeSearchRequestId, trimmedQuery, tab);
    this.pendingSearch = request;
    if (this.throttleTimerId !== null) {
      clearTimeout(this.throttleTimerId);
      this.throttleTimerId = null;
    }

    const nowMillis: number = this.env.clock.monotonicMillis();
    const waitMillis: number = this.lastSearchStartedAtMillis === null
      ? 0
      : Math.max(0, this.throttleMs - (nowMillis - this.lastSearchStartedAtMillis));
    if (waitMillis === 0) {
      this.startPendingSearch();
      return;
    }

    this.throttleTimerId = setTimeout(() => {
      this.throttleTimerId = null;
      this.startPendingSearch();
    }, waitMillis);
  }

  private startPendingSearch(): void {
    if (this.destroyed || this.pendingSearch === null) {
      return;
    }
    const request: PendingSearch = this.pendingSearch;
    this.pendingSearch = null;
    this.lastSearchStartedAtMillis = this.env.clock.monotonicMillis();
    this.inFlightSearchKey = request.key;
    this.inFlightSearchRequestId = request.requestId;
    this.executeSearch(request);
  }

  private failSearch(request: PendingSearch, error: AppError): void {
    if (this.destroyed || request.requestId !== this.activeSearchRequestId) {
      return;
    }
    this.logger.logError(TAG, error);
    this.dispatch(new SearchFailed(searchErrorMessage(error)));
  }

  private async executeSearch(request: PendingSearch): Promise<void> {
    try {
      let chats: SearchChatItem[] = [];
      let messages: SearchMessageItem[] = [];

      if (request.tab === 'all' || request.tab === 'chats') {
        const chatLimit: number = request.tab === 'all' ? 20 : 50;
        const chatResult: Result<SearchChatItem[], AppError> =
          await this.provider.searchChats(request.query, chatLimit);
        // DSH 编译修复（SEARCH-103 进行中的窄化问题，逻辑未动）：ArkTS 不支持
        // `if (x.err) return;` 之后的跨 return 收窄，必须 if(x.ok) 正向取 value。
        if (chatResult.ok) {
          chats = chatResult.value;
        }
        if (chatResult.err) {
          this.failSearch(request, chatResult.error);
          return;
        }
      }

      if (this.destroyed || request.requestId !== this.activeSearchRequestId) {
        return;
      }

      if (request.tab === 'all' || request.tab === 'messages' || request.tab === 'media') {
        const msgLimit: number = request.tab === 'all' ? 20 : 50;
        const messageResult: Result<SearchMessageItem[], AppError> =
          await this.provider.searchMessages(request.query, msgLimit);
        if (messageResult.ok) {
          messages = messageResult.value;
        }
        if (messageResult.err) {
          this.failSearch(request, messageResult.error);
          return;
        }
      }

      if (this.destroyed || request.requestId !== this.activeSearchRequestId) {
        return;
      }

      this.dispatch(new SearchSuccess(chats, messages));
    } catch (e) {
      if (this.destroyed || request.requestId !== this.activeSearchRequestId) {
        return;
      }
      const cause: string = e instanceof Error ? e.name : 'non-error';
      const unexpected: AppError = AppErrors.unknown(
        'search-coordinator',
        'Unexpected search failure',
        cause
      );
      this.failSearch(request, unexpected);
    } finally {
      if (this.inFlightSearchRequestId === request.requestId) {
        this.inFlightSearchKey = null;
        this.inFlightSearchRequestId = null;
      }
    }
  }
}
