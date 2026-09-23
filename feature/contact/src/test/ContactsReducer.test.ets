/**
 * feature/contact — ContactsReducer 单元测试（CONTACT-101）。
 *
 * 覆盖：加载回灌（双份缓冲）、查询过滤、失败态、contactTapped 效应、
 * 过滤纯函数 filterContactsItems 的归一化与多字段匹配。
 */

import { describe, it, expect } from '@ohos/hypium';
import { ManualClock, SequentialIdGenerator, AppErrors } from '@tgx/core-common';
import { ReducerEnv, ReducerResult } from '@tgx/feature-template';
import { ContactsItem, ContactsSection, ContactsUiState } from '../main/ets/contract/ContactsUiState';
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
  statusText: string = '',
  phoneNumber: string = ''
): ContactsItem {
  return new ContactsItem(userId, displayName, username, null, '', 0, statusText, phoneNumber);
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

    // 索引条与分组列表都渲染 state.sections：分段必须在 reducer 里跟 items 一起算出，
    // 页面再算一份会和跳转位移对不上（且页面无法单测）。
    // 输入按 coordinator 排序后的顺序给出：reducer 只负责按相邻同字母归段，不排序。
    it('onContactsLoaded_buildsLetterSectionsAlongsideItems', 0, () => {
      const items: ContactsItem[] = [
        makeItem(7, 'Alice Anderson', 'alice'),
        makeItem(13, 'Anna Cross', ''),
        makeItem(9, 'Bob Brown', 'bob'),
        makeItem(11, 'Carol Clark', '')
      ];
      const result: ReducerResult<ContactsUiState, ContactsEffect> = contactsReducer(
        ContactsUiState.initial(),
        new OnContactsLoaded(items),
        makeEnv()
      );
      const sections: ContactsSection[] = result.state.sections;

      expect(sections.length).assertEqual(3);
      expect(sections[0].letter).assertEqual('A');
      expect(sections[0].items.length).assertEqual(2);
      expect(sections[0].startIndex).assertEqual(0);
      expect(sections[1].letter).assertEqual('B');
      expect(sections[1].startIndex).assertEqual(2);
      expect(sections[2].letter).assertEqual('C');
      expect(sections[2].startIndex).assertEqual(3);

      // 分段必须平铺出整份展示列表，不能漏条目也不能重复。
      let flat: number = 0;
      for (let i: number = 0; i < sections.length; i++) {
        flat += sections[i].items.length;
      }
      expect(flat).assertEqual(result.state.items.length);
    });

    it('queryChanged_rebuildsSectionsFromFilteredList', 0, () => {
      const filtered: ContactsUiState = contactsReducer(
        makeLoadedState(),
        new QueryChanged('alice'),
        makeEnv()
      ).state;
      expect(filtered.items.length).assertEqual(1);
      expect(filtered.sections.length).assertEqual(1);
      expect(filtered.sections[0].letter).assertEqual('A');
      expect(filtered.sections[0].items.length).assertEqual(1);

      const restored: ContactsUiState = contactsReducer(
        filtered,
        new QueryChanged(''),
        makeEnv()
      ).state;
      expect(restored.sections.length).assertEqual(3);
      expect(restored.sections[2].letter).assertEqual('C');
    });

    it('onContactsFailed_keepsSectionsUntouched', 0, () => {
      const loaded: ContactsUiState = makeLoadedState();
      const result: ReducerResult<ContactsUiState, ContactsEffect> = contactsReducer(
        loaded,
        new OnContactsFailed(AppErrors.network('unknown', 'socket failed', true)),
        makeEnv()
      );
      expect(result.state.sections.length).assertEqual(3);
      expect(result.state.errorMessage).assertEqual('socket failed');
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
      // 空查询走「原样返回引用」，不新建数组（避免每次输入都整表重排）。
      expect(out === items).assertTrue();
    });

    it('matchesDisplayNameAndUsername', 0, () => {
      const items: ContactsItem[] = [makeItem(1, 'Alpha', 'alpha_user'), makeItem(2, 'Beta')];
      expect(filterContactsItems(items, 'alp').length).assertEqual(1);
      expect(filterContactsItems(items, 'gamma').length).assertEqual(0);
    });

    /**
     * CONTACT-102 的行为变更：过滤从子串匹配改成 Android 的**词首前缀**匹配，
     * 所以用户名中间的片段不再命中（'USER' 找不到 'alpha_user'）。
     * 号码同理不参与匹配 —— Android 联系人页只比展示名与用户名。
     */
    it('wordPrefixOnly_midWordFragmentDoesNotMatch', 0, () => {
      const items: ContactsItem[] = [makeItem(1, 'Alpha', 'alpha_user'), makeItem(2, 'Beta')];
      expect(filterContactsItems(items, 'USER').length).assertEqual(0);
      expect(filterContactsItems(items, 'lph').length).assertEqual(0);
      expect(filterContactsItems(items, 'alpha_').length).assertEqual(1);
    });

    it('wordPrefix_matchesAnyWordOfDisplayName', 0, () => {
      const items: ContactsItem[] = [makeItem(1, 'Alice Anderson'), makeItem(2, 'Bob Brown')];
      expect(filterContactsItems(items, 'and').length).assertEqual(1);
      // 整个 query 作为**一个**前缀参与比较：'Alice A' 是展示名的整体前缀
      expect(filterContactsItems(items, 'Alice A').length).assertEqual(1);
      // 'A b' 既不是整体前缀，也不是任何词的词首（词首比较同样带整个前缀，含空格）
      expect(filterContactsItems(items, 'A b').length).assertEqual(0);
    });

    it('onContactsLoaded_keepsPhoneNumberOnItems', 0, () => {
      const items: ContactsItem[] = [makeItem(7, 'be hu', 'hu_bery', 'last seen recently', '+447741417158')];
      const state: ContactsUiState = contactsReducer(
        ContactsUiState.initial(),
        new OnContactsLoaded(items),
        makeEnv()
      ).state;
      expect(state.items[0].phoneNumber).assertEqual('+447741417158');
    });
  });
}
