/**
 * feature/contact — ContactsReducer 单元测试（CONTACT-101）。
 *
 * 覆盖：加载回灌（双份缓冲）、查询过滤、失败态、contactTapped 效应、
 * 过滤纯函数 filterContactsItems 的归一化与多字段匹配。
 */

import { describe, it, expect } from '@ohos/hypium';
import { ManualClock, SequentialIdGenerator, AppErrors } from '@tgx/core-common';
import { ReducerEnv, ReducerResult } from '@tgx/feature-template';
import { ContactsItem, ContactsUiState } from '../main/ets/contract/ContactsUiState';
import {
  ContactsIntent,
  QueryChanged,
  OnContactsLoaded,
  OnContactsFailed,
  ContactTapped
} from '../main/ets/contract/ContactsIntent';
import { ContactsEffect, OpenUserProfile } from '../main/ets/contract/ContactsEffect';
import { contactsReducer, filterContactsItems } from '../main/ets/reducer/ContactsReducer';

function makeEnv(): ReducerEnv {
  return {
    clock: new ManualClock(1000, 500),
    ids: new SequentialIdGenerator('test-')
  };
}

function makeItem(
  userId: number,
  displayName: string,
  username: string = '',
  statusText: string = ''
): ContactsItem {
  return new ContactsItem(userId, displayName, username, null, '', 0, statusText);
}

function makeLoadedState(): ContactsUiState {
  const items: ContactsItem[] = [
    makeItem(7, 'Alice Anderson', 'alice'),
    makeItem(9, 'Bob Brown', 'bobby'),
    makeItem(11, 'Carol Clark', '', 'online')
  ];
  return contactsReducer(ContactsUiState.initial(), new OnContactsLoaded(items), makeEnv()).state;
}

export default function contactsReducerTest(): void {
  describe('ContactsReducerTest', () => {

    it('onContactsLoaded_fillsAllAndFilteredAndStopsLoading', 0, () => {
      const items: ContactsItem[] = [
        makeItem(7, 'Alice Anderson', 'alice', 'online'),
        makeItem(9, 'Bob Brown', 'bob')
      ];
      const result: ReducerResult<ContactsUiState, ContactsEffect> = contactsReducer(
        ContactsUiState.initial(),
        new OnContactsLoaded(items),
        makeEnv()
      );

      expect(result.state.isLoading).assertFalse();
      expect(result.state.errorMessage === null).assertTrue();
      expect(result.state.allItems.length).assertEqual(2);
      expect(result.state.items.length).assertEqual(2);
      expect(result.state.items[0].displayName).assertEqual('Alice Anderson');
      expect(result.state.items[0].statusText).assertEqual('online');
      expect(result.effects.length).assertEqual(0);
    });

    it('onContactsLoaded_reappliesActiveQueryToFilteredView', 0, () => {
      const queried: ContactsUiState = contactsReducer(
        makeLoadedState(),
        new QueryChanged('ali'),
        makeEnv()
      ).state;
      const items: ContactsItem[] = [
        makeItem(13, 'Alice Smith', 'alicex'),
        makeItem(15, 'Dave Doe', 'dave')
      ];
      const result: ReducerResult<ContactsUiState, ContactsEffect> = contactsReducer(
        queried,
        new OnContactsLoaded(items),
        makeEnv()
      );

      expect(result.state.allItems.length).assertEqual(2);
      expect(result.state.items.length).assertEqual(1);
      expect(result.state.items[0].displayName).assertEqual('Alice Smith');
    });

    it('onContactsFailed_setsErrorAndStopsLoading', 0, () => {
      const result: ReducerResult<ContactsUiState, ContactsEffect> = contactsReducer(
        ContactsUiState.initial(),
        new OnContactsFailed(AppErrors.network('unknown', 'socket failed', true)),
        makeEnv()
      );
      expect(result.state.isLoading).assertFalse();
      expect(result.state.errorMessage).assertEqual('socket failed');
    });

    it('queryChanged_filtersByDisplayNameCaseInsensitively', 0, () => {
      const result: ReducerResult<ContactsUiState, ContactsEffect> = contactsReducer(
        makeLoadedState(),
        new QueryChanged('  ALI  '),
        makeEnv()
      );
      expect(result.state.query).assertEqual('  ALI  ');
      expect(result.state.allItems.length).assertEqual(3);
      expect(result.state.items.length).assertEqual(1);
      expect(result.state.items[0].userId).assertEqual(7);
    });

    it('queryChanged_matchesUsernameAsFallback', 0, () => {
      const result: ReducerResult<ContactsUiState, ContactsEffect> = contactsReducer(
        makeLoadedState(),
        new QueryChanged('bobby'),
        makeEnv()
      );
      expect(result.state.items.length).assertEqual(1);
      expect(result.state.items[0].userId).assertEqual(9);
    });

    it('queryChanged_emptyQueryRestoresFullList', 0, () => {
      const filtered: ContactsUiState = contactsReducer(
        makeLoadedState(),
        new QueryChanged('zzz'),
        makeEnv()
      ).state;
      expect(filtered.items.length).assertEqual(0);

      const result: ReducerResult<ContactsUiState, ContactsEffect> = contactsReducer(
        filtered,
        new QueryChanged(''),
        makeEnv()
      );
      expect(result.state.items.length).assertEqual(3);
    });

    it('contactTapped_emitsOpenUserProfile', 0, () => {
      const state: ContactsUiState = makeLoadedState();
      const result: ReducerResult<ContactsUiState, ContactsEffect> = contactsReducer(
        state,
        new ContactTapped(9),
        makeEnv()
      );

      expect(result.effects.length).assertEqual(1);
      expect(result.effects[0].kind).assertEqual('openUserProfile');
      const effect: OpenUserProfile = result.effects[0] as OpenUserProfile;
      expect(effect.userId).assertEqual(9);
      expect(result.state === state).assertTrue();
    });

    it('contactTapped_withInvalidUserId_isNoOp', 0, () => {
      const result: ReducerResult<ContactsUiState, ContactsEffect> = contactsReducer(
        makeLoadedState(),
        new ContactTapped(0),
        makeEnv()
      );
      expect(result.effects.length).assertEqual(0);
    });
  });

  describe('FilterContactsItemsTest', () => {

    it('emptyQuery_returnsAllItems', 0, () => {
      const items: ContactsItem[] = [makeItem(1, 'Alpha'), makeItem(2, 'Beta')];
      const out: ContactsItem[] = filterContactsItems(items, '   ');
      expect(out.length).assertEqual(2);
    });

    it('matchesDisplayNameAndUsername', 0, () => {
      const items: ContactsItem[] = [makeItem(1, 'Alpha', 'alpha_user'), makeItem(2, 'Beta')];
      expect(filterContactsItems(items, 'alp').length).assertEqual(1);
      expect(filterContactsItems(items, 'USER').length).assertEqual(1);
      expect(filterContactsItems(items, 'gamma').length).assertEqual(0);
    });
  });
}
