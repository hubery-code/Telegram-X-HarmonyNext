/**
 * feature/contact — 联系人多选模式 reducer 单测（GROUP-CREATE-101）。
 *
 * 覆盖：
 * 1. multiSelectEnabled 打开模式并清空旧选中集；
 * 2. memberSelectionToggled 点选追加 / 重复点击移除（保持点选顺序）；
 * 3. memberSelectionConfirmed 空选不出效应；非空出 ConfirmMemberSelection
 *    （名单为点选顺序的副本）；
 * 4. multiSelectReset 退出模式清选中集（未激活时 no-op）；
 * 5. 多选意图在非多选模式下被挡（memberSelectionToggled）；
 * 6. 常规 contactTapped 行为不受多选改动影响（回归）；
 * 7. copyWith 不丢 multiSelect/selectedUserIds。
 */

import { describe, it, expect } from '@ohos/hypium';
import { ManualClock, SequentialIdGenerator, AppErrors } from '@tgx/core-common';
import { ReducerEnv, ReducerResult } from '@tgx/feature-template';
import { ContactsItem, ContactsUiState } from '../main/ets/contract/ContactsUiState';
import {
  ContactsIntent,
  ContactTapped,
  OnContactsLoaded,
  OnContactsFailed,
  MultiSelectEnabled,
  MemberSelectionToggled,
  MemberSelectionConfirmed,
  MultiSelectReset
} from '../main/ets/contract/ContactsIntent';
import { ContactsEffect, OpenUserProfile, ConfirmMemberSelection } from '../main/ets/contract/ContactsEffect';
import { contactsReducer } from '../main/ets/reducer/ContactsReducer';

function makeEnv(): ReducerEnv {
  return {
    clock: new ManualClock(1000, 500),
    ids: new SequentialIdGenerator('multiselect-test-')
  };
}

function makeItem(userId: number, displayName: string): ContactsItem {
  return new ContactsItem(userId, displayName, '', null, '', 0, '', '');
}

function makeLoadedState(): ContactsUiState {
  const items: ContactsItem[] = [
    makeItem(7, 'Alice Anderson'),
    makeItem(9, 'Bob Brown'),
    makeItem(11, 'Carol Clark')
  ];
  return contactsReducer(ContactsUiState.initial(), new OnContactsLoaded(items), makeEnv()).state;
}

function makeMultiState(): ContactsUiState {
  return contactsReducer(makeLoadedState(), new MultiSelectEnabled(), makeEnv()).state;
}

export default function contactsMultiSelectReducerTest(): void {
  describe('ContactsMultiSelectReducerTest', () => {

    it('multiSelectEnabled_turnsOnAndClearsSelection', 0, () => {
      const state: ContactsUiState = makeMultiState();
      expect(state.multiSelect).assertTrue();
      expect(state.selectedUserIds.length).assertEqual(0);
      // 列表数据不动：多选复用同一份 sections。
      expect(state.items.length).assertEqual(3);
    });

    it('memberSelectionToggled_appendsInTapOrderAndRemovesOnRepeat', 0, () => {
      let state: ContactsUiState = makeMultiState();
      state = contactsReducer(state, new MemberSelectionToggled(9), makeEnv()).state;
      state = contactsReducer(state, new MemberSelectionToggled(7), makeEnv()).state;
      state = contactsReducer(state, new MemberSelectionToggled(11), makeEnv()).state;
      // 点选顺序即成员顺序（TDLib user_ids 按此携带）。
      expect(state.selectedUserIds.length).assertEqual(3);
      expect(state.selectedUserIds[0]).assertEqual(9);
      expect(state.selectedUserIds[1]).assertEqual(7);
      expect(state.selectedUserIds[2]).assertEqual(11);

      // 重复点击移除。
      state = contactsReducer(state, new MemberSelectionToggled(7), makeEnv()).state;
      expect(state.selectedUserIds.length).assertEqual(2);
      expect(state.selectedUserIds[0]).assertEqual(9);
      expect(state.selectedUserIds[1]).assertEqual(11);
    });

    it('memberSelectionToggled_ignoredOutsideMultiSelect', 0, () => {
      const state: ContactsUiState = makeLoadedState();
      const result: ReducerResult<ContactsUiState, ContactsEffect> =
        contactsReducer(state, new MemberSelectionToggled(7), makeEnv());
      expect(result.effects.length).assertEqual(0);
      expect(result.state).assertEqual(state);
    });

    it('memberSelectionConfirmed_emptySelectionIsNoOp', 0, () => {
      const state: ContactsUiState = makeMultiState();
      const result: ReducerResult<ContactsUiState, ContactsEffect> =
        contactsReducer(state, new MemberSelectionConfirmed(), makeEnv());
      expect(result.effects.length).assertEqual(0);
      expect(result.state).assertEqual(state);
    });

    it('memberSelectionConfirmed_emitsSelectionInTapOrder', 0, () => {
      let state: ContactsUiState = makeMultiState();
      state = contactsReducer(state, new MemberSelectionToggled(9), makeEnv()).state;
      state = contactsReducer(state, new MemberSelectionToggled(7), makeEnv()).state;

      const result: ReducerResult<ContactsUiState, ContactsEffect> =
        contactsReducer(state, new MemberSelectionConfirmed(), makeEnv());
      expect(result.effects.length).assertEqual(1);
      const effect: ConfirmMemberSelection = result.effects[0] as ConfirmMemberSelection;
      expect(effect.kind).assertEqual('confirmMemberSelection');
      expect(effect.userIds.length).assertEqual(2);
      expect(effect.userIds[0]).assertEqual(9);
      expect(effect.userIds[1]).assertEqual(7);
      // 确认不动模式：去留由装配层决定（接力命名段后自行 reset/销毁）。
      expect(result.state.multiSelect).assertTrue();
    });

    it('multiSelectReset_exitsAndClearsSelection', 0, () => {
      let state: ContactsUiState = makeMultiState();
      state = contactsReducer(state, new MemberSelectionToggled(7), makeEnv()).state;
      const result: ReducerResult<ContactsUiState, ContactsEffect> =
        contactsReducer(state, new MultiSelectReset(), makeEnv());
      expect(result.state.multiSelect).assertFalse();
      expect(result.state.selectedUserIds.length).assertEqual(0);
    });

    it('multiSelectReset_isNoOpWhenInactive', 0, () => {
      const state: ContactsUiState = makeLoadedState();
      const result: ReducerResult<ContactsUiState, ContactsEffect> =
        contactsReducer(state, new MultiSelectReset(), makeEnv());
      expect(result.state).assertEqual(state);
    });

    it('contactTapped_stillOpensProfileInSingleSelectMode', 0, () => {
      const state: ContactsUiState = makeLoadedState();
      const result: ReducerResult<ContactsUiState, ContactsEffect> =
        contactsReducer(state, new ContactTapped(9), makeEnv());
      expect(result.effects.length).assertEqual(1);
      expect((result.effects[0] as OpenUserProfile).userId).assertEqual(9);
    });

    it('contactTapped_invalidUserIdIsNoOp', 0, () => {
      const result: ReducerResult<ContactsUiState, ContactsEffect> =
        contactsReducer(makeLoadedState(), new ContactTapped(0), makeEnv());
      expect(result.effects.length).assertEqual(0);
    });

    it('copyWith_keepsMultiSelectFieldsWhenUnspecified', 0, () => {
      let state: ContactsUiState = makeMultiState();
      state = contactsReducer(state, new MemberSelectionToggled(9), makeEnv()).state;
      // 取数回灌等无关更新不得把多选模式与选中集冲掉。
      const refreshed: ContactsUiState = contactsReducer(
        state,
        new OnContactsFailed(AppErrors.network('unknown', 'socket failed', true)),
        makeEnv()
      ).state;
      expect(refreshed.multiSelect).assertTrue();
      expect(refreshed.selectedUserIds.length).assertEqual(1);
      expect(refreshed.selectedUserIds[0]).assertEqual(9);
    });
  });
}
