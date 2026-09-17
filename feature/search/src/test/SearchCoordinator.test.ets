import { describe, it, expect } from '@ohos/hypium';
import {
  AppError,
  AppErrors,
  ManualClock,
  Result,
  SequentialIdGenerator,
  err,
  ok
} from '@tgx/core-common';
import { ReducerEnv } from '@tgx/feature-template';
import { SearchChatItem } from '../main/ets/contract/SearchChatItem';
import { SearchMessageItem } from '../main/ets/contract/SearchMessageItem';
import {
  SearchCoordinator,
  SearchQueryProvider,
  searchErrorMessage
} from '../main/ets/coordinator/SearchCoordinator';

function waitFor(millis: number): Promise<void> {
  return new Promise<void>((resolve) => setTimeout(resolve, millis));
}

function makeEnv(clock: ManualClock): ReducerEnv {
  return {
    clock: clock,
    ids: new SequentialIdGenerator('search-test-')
  };
}

class RecordingSearchProvider implements SearchQueryProvider {
  readonly chatQueries: string[] = [];
  readonly messageQueries: string[] = [];
  chatError: AppError | null = null;
  messageError: AppError | null = null;
  delayMs: number = 0;

  async searchChats(query: string, limit: number): Promise<Result<SearchChatItem[], AppError>> {
    this.chatQueries.push(query);
    if (this.delayMs > 0) {
      await waitFor(this.delayMs);
    }
    if (this.chatError !== null) {
      return err<SearchChatItem[], AppError>(this.chatError);
    }
    return ok<SearchChatItem[], AppError>([
      new SearchChatItem(this.chatQueries.length, query, query, null, false, false)
    ]);
  }

  async searchMessages(query: string, limit: number): Promise<Result<SearchMessageItem[], AppError>> {
    this.messageQueries.push(query);
    if (this.delayMs > 0) {
      await waitFor(this.delayMs);
    }
    if (this.messageError !== null) {
      return err<SearchMessageItem[], AppError>(this.messageError);
    }
    return ok<SearchMessageItem[], AppError>([
      new SearchMessageItem(this.messageQueries.length, 1, query, 'Sender', query, '12:00')
    ]);
  }
}

export default function searchCoordinatorTest(): void {
  describe('SearchCoordinatorTest', () => {
    it('rateLimitFailure_isVisibleAndNeverRenderedAsEmptyResults', 0, async (): Promise<void> => {
      const provider = new RecordingSearchProvider();
      provider.messageError = AppErrors.tdlib('too_many_requests', 'TDLib rate limited', true);
      const coordinator = new SearchCoordinator({
        provider: provider,
        throttleMs: 0
      });

      coordinator.performSearchImmediate('aaa');
      await waitFor(20);

      expect(coordinator.state.isLoading).assertFalse();
      expect(coordinator.state.errorMessage).assertEqual(
        'Too many searches. Please wait a moment and try again.'
      );
      expect(coordinator.state.chatResults.length).assertEqual(0);
      expect(coordinator.state.messageResults.length).assertEqual(0);
      coordinator.destroy();
    });

    it('networkFailure_hasStableUserSafeMessage', 0, () => {
      const networkError: AppError = AppErrors.network('timeout', 'diagnostic timeout', true);
      expect(searchErrorMessage(networkError)).assertEqual(
        'Search is temporarily unavailable. Check your connection and try again.'
      );
      expect(searchErrorMessage(AppErrors.internal('decode'))).assertEqual(
        'Search failed. Please try again.'
      );
    });

    it('throttleCoalescesRapidQueriesAndKeepsOnlyLatestResult', 0, async (): Promise<void> => {
      const provider = new RecordingSearchProvider();
      const clock = new ManualClock(1000, 1000);
      const coordinator = new SearchCoordinator({
        provider: provider,
        env: makeEnv(clock),
        throttleMs: 30
      });

      coordinator.performSearchImmediate('one');
      coordinator.performSearchImmediate('two');
      coordinator.performSearchImmediate('three');
      clock.advanceBy(30);
      await waitFor(60);

      expect(provider.chatQueries.length).assertEqual(2);
      expect(provider.chatQueries[0]).assertEqual('one');
      expect(provider.chatQueries[1]).assertEqual('three');
      expect(provider.messageQueries.length).assertEqual(1);
      expect(provider.messageQueries[0]).assertEqual('three');
      expect(coordinator.state.query).assertEqual('three');
      expect(coordinator.state.chatResults[0].title).assertEqual('three');
      expect(coordinator.state.messageResults[0].textSnippet).assertEqual('three');
      coordinator.destroy();
    });

    it('clearingQueryInvalidatesLateSearchResponse', 0, async (): Promise<void> => {
      const provider = new RecordingSearchProvider();
      provider.delayMs = 20;
      const coordinator = new SearchCoordinator({
        provider: provider,
        throttleMs: 0
      });

      coordinator.performSearchImmediate('old');
      coordinator.clearQuery();
      await waitFor(60);

      expect(coordinator.state.query).assertEqual('');
      expect(coordinator.state.isLoading).assertFalse();
      expect(coordinator.state.chatResults.length).assertEqual(0);
      expect(coordinator.state.messageResults.length).assertEqual(0);
      coordinator.destroy();
    });

    it('floodWaitErrorInCauseOrMessage_mapsToRateLimitMessage', 0, () => {
      const floodError1: AppError = AppErrors.tdlib('unknown', 'TDLib request failed', true, undefined, '429:FLOOD_WAIT_15');
      expect(searchErrorMessage(floodError1)).assertEqual(
        'Too many searches. Please wait a moment and try again.'
      );

      const floodError2: AppError = AppErrors.tdlib('internal', 'Search flood exceeded', true);
      expect(searchErrorMessage(floodError2)).assertEqual(
        'Too many searches. Please wait a moment and try again.'
      );
    });

    it('debounceCoalescesRapidKeystrokesInUpdateQuery', 0, async (): Promise<void> => {
      const provider = new RecordingSearchProvider();
      const coordinator = new SearchCoordinator({
        provider: provider,
        debounceMs: 50,
        throttleMs: 0
      });

      coordinator.updateQuery('a');
      await waitFor(10);
      coordinator.updateQuery('ab');
      await waitFor(10);
      coordinator.updateQuery('abc');

      expect(provider.chatQueries.length).assertEqual(0);
      expect(coordinator.state.query).assertEqual('abc');

      await waitFor(80);

      expect(provider.chatQueries.length).assertEqual(1);
      expect(provider.chatQueries[0]).assertEqual('abc');
      expect(coordinator.state.chatResults[0].title).assertEqual('abc');
      coordinator.destroy();
    });
  });
}
