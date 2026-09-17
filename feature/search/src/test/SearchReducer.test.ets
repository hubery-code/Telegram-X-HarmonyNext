import { describe, it, expect } from '@ohos/hypium';
import { ManualClock, SequentialIdGenerator } from '@tgx/core-common';
import { ReducerEnv } from '@tgx/feature-template';
import { SearchChatItem } from '../main/ets/contract/SearchChatItem';
import { SearchMessageItem } from '../main/ets/contract/SearchMessageItem';
import { SearchUiState } from '../main/ets/contract/SearchUiState';
import {
  AddRecentSearch,
  ClearQuery,
  ClearRecentSearches,
  OnSearchFailed,
  OnSearchLoaded,
  PerformSearch,
  SearchFailed,
  SearchIntent,
  SearchSuccess,
  SelectTab,
  UpdateQuery
} from '../main/ets/contract/SearchIntent';
import {
  ExecuteSearchEffect,
  SaveRecentSearchEffect,
  SearchEffect
} from '../main/ets/contract/SearchEffect';
import { searchReducer, updateRecentSearches } from '../main/ets/reducer/SearchReducer';

function makeEnv(): ReducerEnv {
  const env: ReducerEnv = {
    clock: new ManualClock(1000, 500),
    ids: new SequentialIdGenerator('test-search-')
  };
  return env;
}

function sampleChats(): SearchChatItem[] {
  return [
    new SearchChatItem(1, 'Telegram News', 'telegram', null, true, false),
    new SearchChatItem(2, 'Community Group', 'community', null, false, true)
  ];
}

function sampleMessages(): SearchMessageItem[] {
  return [
    new SearchMessageItem(101, 1, 'Telegram News', 'Admin', 'Announcement', '12:00'),
    new SearchMessageItem(102, 2, 'Community Group', 'Bob', 'Hello everyone', '12:05')
  ];
}

export default function searchReducerTest() {
  describe('SearchReducerTest', () => {

    it('initialState_hasExpectedDefaults', 0, () => {
      const state = SearchUiState.initial();
      expect(state.query).assertEqual('');
      expect(state.isLoading).assertFalse();
      expect(state.activeTab).assertEqual('all');
      expect(state.chatResults.length).assertEqual(0);
      expect(state.messageResults.length).assertEqual(0);
      expect(state.recentSearches.length).assertEqual(0);
      expect(state.errorMessage).assertNull();
    });

    it('updateQuery_withNonEmptyQuery_updatesQueryAndClearsError', 0, () => {
      const env = makeEnv();
      const initial = SearchUiState.initial().copyWith({ errorMessage: 'old error' });
      const result = searchReducer(initial, new UpdateQuery('hello'), env);

      expect(result.state.query).assertEqual('hello');
      expect(result.state.errorMessage).assertNull();
      expect(result.effects.length).assertEqual(0);
    });

    it('updateQuery_withEmptyQuery_clearsResultsAndLoading', 0, () => {
      const env = makeEnv();
      const activeState = SearchUiState.initial().copyWith({
        query: 'previous',
        isLoading: true,
        chatResults: sampleChats(),
        messageResults: sampleMessages()
      });

      const result = searchReducer(activeState, new UpdateQuery('   '), env);

      expect(result.state.query).assertEqual('   ');
      expect(result.state.isLoading).assertFalse();
      expect(result.state.chatResults.length).assertEqual(0);
      expect(result.state.messageResults.length).assertEqual(0);
      expect(result.state.errorMessage).assertNull();
      expect(result.effects.length).assertEqual(0);
    });

    it('clearQuery_resetsQueryAndResults', 0, () => {
      const env = makeEnv();
      const activeState = SearchUiState.initial().copyWith({
        query: 'search term',
        isLoading: true,
        chatResults: sampleChats(),
        messageResults: sampleMessages(),
        errorMessage: 'some error'
      });

      const result = searchReducer(activeState, new ClearQuery(), env);

      expect(result.state.query).assertEqual('');
      expect(result.state.isLoading).assertFalse();
      expect(result.state.chatResults.length).assertEqual(0);
      expect(result.state.messageResults.length).assertEqual(0);
      expect(result.state.errorMessage).assertNull();
      expect(result.effects.length).assertEqual(0);
    });

    it('selectTab_sameTab_returnsSameStateReference', 0, () => {
      const env = makeEnv();
      const state = SearchUiState.initial().copyWith({ activeTab: 'chats' });
      const result = searchReducer(state, new SelectTab('chats'), env);

      expect(result.state === state).assertTrue();
      expect(result.effects.length).assertEqual(0);
    });

    it('selectTab_differentTab_whenQueryEmpty_updatesTabWithoutEffect', 0, () => {
      const env = makeEnv();
      const state = SearchUiState.initial().copyWith({ activeTab: 'all', query: '' });
      const result = searchReducer(state, new SelectTab('messages'), env);

      expect(result.state.activeTab).assertEqual('messages');
      expect(result.state.isLoading).assertFalse();
      expect(result.effects.length).assertEqual(0);
    });

    it('selectTab_differentTab_whenQueryNotEmpty_emitsExecuteSearchEffect', 0, () => {
      const env = makeEnv();
      const state = SearchUiState.initial().copyWith({
        activeTab: 'all',
        query: 'telegram'
      });

      const result = searchReducer(state, new SelectTab('chats'), env);

      expect(result.state.activeTab).assertEqual('chats');
      expect(result.state.isLoading).assertTrue();
      expect(result.state.errorMessage).assertNull();
      expect(result.effects.length).assertEqual(1);

      const effect: SearchEffect = result.effects[0];
      expect(effect.kind).assertEqual('executeSearch');
      const searchEffect = effect as ExecuteSearchEffect;
      expect(searchEffect.query).assertEqual('telegram');
      expect(searchEffect.tab).assertEqual('chats');
    });

    it('performSearch_emptyQuery_clearsResultsAndLoading', 0, () => {
      const env = makeEnv();
      const state = SearchUiState.initial().copyWith({
        chatResults: sampleChats(),
        messageResults: sampleMessages(),
        isLoading: true
      });

      const result = searchReducer(state, new PerformSearch(''), env);

      expect(result.state.query).assertEqual('');
      expect(result.state.isLoading).assertFalse();
      expect(result.state.chatResults.length).assertEqual(0);
      expect(result.state.messageResults.length).assertEqual(0);
      expect(result.effects.length).assertEqual(0);
    });

    it('performSearch_nonEmptyQuery_emitsExecuteAndSaveEffects_andUpdatesRecent', 0, () => {
      const env = makeEnv();
      const state = SearchUiState.initial().copyWith({
        activeTab: 'all',
        recentSearches: ['existing']
      });

      const result = searchReducer(state, new PerformSearch('ArkTS'), env);

      expect(result.state.query).assertEqual('ArkTS');
      expect(result.state.isLoading).assertTrue();
      expect(result.state.errorMessage).assertNull();
      expect(result.state.recentSearches.length).assertEqual(2);
      expect(result.state.recentSearches[0]).assertEqual('ArkTS');
      expect(result.state.recentSearches[1]).assertEqual('existing');

      expect(result.effects.length).assertEqual(2);
      const executeEffect = result.effects[0] as ExecuteSearchEffect;
      expect(executeEffect.kind).assertEqual('executeSearch');
      expect(executeEffect.query).assertEqual('ArkTS');
      expect(executeEffect.tab).assertEqual('all');

      const saveEffect = result.effects[1] as SaveRecentSearchEffect;
      expect(saveEffect.kind).assertEqual('saveRecentSearch');
      expect(saveEffect.term).assertEqual('ArkTS');
    });

    it('performSearch_deduplicatesAndCapsRecentSearchesAt10', 0, () => {
      const env = makeEnv();
      const initialSearches: string[] = ['1', '2', '3', '4', '5', '6', '7', '8', '9', '10'];
      const state = SearchUiState.initial().copyWith({ recentSearches: initialSearches });

      // Search existing item '5' -> should move to front without exceeding 10
      const res1 = searchReducer(state, new PerformSearch('5'), env);
      expect(res1.state.recentSearches.length).assertEqual(10);
      expect(res1.state.recentSearches[0]).assertEqual('5');
      expect(res1.state.recentSearches[1]).assertEqual('1');

      // Search new item '11' -> should be at front, '10' should be dropped, length 10
      const res2 = searchReducer(state, new PerformSearch('11'), env);
      expect(res2.state.recentSearches.length).assertEqual(10);
      expect(res2.state.recentSearches[0]).assertEqual('11');
      expect(res2.state.recentSearches[1]).assertEqual('1');
      expect(res2.state.recentSearches.indexOf('10')).assertEqual(-1);
    });

    it('searchSuccess_updatesResultsAndSetsLoadingFalse', 0, () => {
      const env = makeEnv();
      const state = SearchUiState.initial().copyWith({
        isLoading: true,
        errorMessage: 'prior error'
      });
      const chats = sampleChats();
      const messages = sampleMessages();

      const result = searchReducer(state, new SearchSuccess(chats, messages), env);

      expect(result.state.isLoading).assertFalse();
      expect(result.state.chatResults.length).assertEqual(2);
      expect(result.state.messageResults.length).assertEqual(2);
      expect(result.state.chatResults[0].title).assertEqual('Telegram News');
      expect(result.state.messageResults[0].textSnippet).assertEqual('Announcement');
      expect(result.state.errorMessage).assertNull();
      expect(result.effects.length).assertEqual(0);
    });

    it('onSearchLoaded_updatesResultsAndSetsLoadingFalse', 0, () => {
      const env = makeEnv();
      const state = SearchUiState.initial().copyWith({
        isLoading: true,
        errorMessage: 'prior error'
      });
      const chats = sampleChats();
      const messages = sampleMessages();

      const result = searchReducer(state, new OnSearchLoaded(chats, messages), env);

      expect(result.state.isLoading).assertFalse();
      expect(result.state.chatResults.length).assertEqual(2);
      expect(result.state.messageResults.length).assertEqual(2);
      expect(result.state.chatResults[0].title).assertEqual('Telegram News');
      expect(result.state.messageResults[0].textSnippet).assertEqual('Announcement');
      expect(result.state.errorMessage).assertNull();
      expect(result.effects.length).assertEqual(0);
    });

    it('searchFailed_setsErrorMessageAndClearsStaleResults', 0, () => {
      const env = makeEnv();
      const state = SearchUiState.initial().copyWith({
        isLoading: true,
        chatResults: sampleChats(),
        messageResults: sampleMessages()
      });

      const result = searchReducer(state, new SearchFailed('Network timeout'), env);

      expect(result.state.isLoading).assertFalse();
      expect(result.state.errorMessage).assertEqual('Network timeout');
      expect(result.state.chatResults.length).assertEqual(0);
      expect(result.state.messageResults.length).assertEqual(0);
      expect(result.effects.length).assertEqual(0);
    });

    it('onSearchFailed_setsErrorMessageAndClearsStaleResults', 0, () => {
      const env = makeEnv();
      const state = SearchUiState.initial().copyWith({
        isLoading: true,
        chatResults: sampleChats(),
        messageResults: sampleMessages()
      });

      const result = searchReducer(state, new OnSearchFailed('Flood wait error'), env);

      expect(result.state.isLoading).assertFalse();
      expect(result.state.errorMessage).assertEqual('Flood wait error');
      expect(result.state.chatResults.length).assertEqual(0);
      expect(result.state.messageResults.length).assertEqual(0);
      expect(result.effects.length).assertEqual(0);
    });

    it('addRecentSearch_addsDeduplicatedTermAndEmitsSaveEffect', 0, () => {
      const env = makeEnv();
      const state = SearchUiState.initial().copyWith({ recentSearches: ['old1', 'old2'] });

      const result = searchReducer(state, new AddRecentSearch('newTerm'), env);

      expect(result.state.recentSearches.length).assertEqual(3);
      expect(result.state.recentSearches[0]).assertEqual('newTerm');
      expect(result.effects.length).assertEqual(1);
      const effect = result.effects[0] as SaveRecentSearchEffect;
      expect(effect.kind).assertEqual('saveRecentSearch');
      expect(effect.term).assertEqual('newTerm');
    });

    it('addRecentSearch_emptyOrWhitespaceTerm_returnsSameStateRef', 0, () => {
      const env = makeEnv();
      const state = SearchUiState.initial().copyWith({ recentSearches: ['term'] });

      const result = searchReducer(state, new AddRecentSearch('   '), env);

      expect(result.state === state).assertTrue();
      expect(result.effects.length).assertEqual(0);
    });

    it('clearRecentSearches_clearsList', 0, () => {
      const env = makeEnv();
      const state = SearchUiState.initial().copyWith({ recentSearches: ['a', 'b'] });

      const result = searchReducer(state, new ClearRecentSearches(), env);

      expect(result.state.recentSearches.length).assertEqual(0);
      expect(result.effects.length).assertEqual(0);
    });

    it('clearRecentSearches_whenAlreadyEmpty_returnsSameStateRef', 0, () => {
      const env = makeEnv();
      const state = SearchUiState.initial().copyWith({ recentSearches: [] });

      const result = searchReducer(state, new ClearRecentSearches(), env);

      expect(result.state === state).assertTrue();
      expect(result.effects.length).assertEqual(0);
    });

    it('reducer_doesNotMutateInputState', 0, () => {
      const env = makeEnv();
      const state = SearchUiState.initial().copyWith({
        query: 'original',
        isLoading: false,
        activeTab: 'all',
        chatResults: sampleChats(),
        messageResults: sampleMessages(),
        recentSearches: ['first'],
        errorMessage: null
      });

      const queryBefore = state.query;
      const isLoadingBefore = state.isLoading;
      const tabBefore = state.activeTab;
      const chatsCountBefore = state.chatResults.length;
      const msgsCountBefore = state.messageResults.length;
      const recentCountBefore = state.recentSearches.length;

      const intents: SearchIntent[] = [
        new UpdateQuery('next'),
        new SelectTab('chats'),
        new PerformSearch('search'),
        new SearchSuccess([], []),
        new SearchFailed('err'),
        new AddRecentSearch('item'),
        new ClearRecentSearches(),
        new ClearQuery()
      ];

      for (let i = 0; i < intents.length; i++) {
        searchReducer(state, intents[i], env);
      }

      expect(state.query).assertEqual(queryBefore);
      expect(state.isLoading).assertEqual(isLoadingBefore);
      expect(state.activeTab).assertEqual(tabBefore);
      expect(state.chatResults.length).assertEqual(chatsCountBefore);
      expect(state.messageResults.length).assertEqual(msgsCountBefore);
      expect(state.recentSearches.length).assertEqual(recentCountBefore);
    });

    it('reducer_isPure_sameInputsProduceIdenticalOutputs', 0, () => {
      const env = makeEnv();
      const state = SearchUiState.initial().copyWith({ query: 'hello', activeTab: 'all' });
      const intent = new PerformSearch('hello');

      const r1 = searchReducer(state, intent, env);
      const r2 = searchReducer(state, intent, env);

      expect(r1.state.query).assertEqual(r2.state.query);
      expect(r1.state.isLoading).assertEqual(r2.state.isLoading);
      expect(r1.state.recentSearches.length).assertEqual(r2.state.recentSearches.length);
      expect(r1.effects.length).assertEqual(r2.effects.length);

      const e1 = r1.effects[0] as ExecuteSearchEffect;
      const e2 = r2.effects[0] as ExecuteSearchEffect;
      expect(e1.query).assertEqual(e2.query);
      expect(e1.tab).assertEqual(e2.tab);
    });

    it('updateRecentSearches_helperFunctionsCorrectly', 0, () => {
      const list = ['a', 'b', 'c'];
      const updated = updateRecentSearches(list, 'd');
      expect(updated.length).assertEqual(4);
      expect(updated[0]).assertEqual('d');
      expect(updated[1]).assertEqual('a');

      // Dedupe
      const deduped = updateRecentSearches(updated, 'b');
      expect(deduped.length).assertEqual(4);
      expect(deduped[0]).assertEqual('b');
      expect(deduped[1]).assertEqual('d');
      expect(deduped[2]).assertEqual('a');
      expect(deduped[3]).assertEqual('c');
    });

  });
}
