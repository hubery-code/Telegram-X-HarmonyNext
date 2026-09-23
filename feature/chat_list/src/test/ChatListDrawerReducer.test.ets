/**
 * feature/chat_list — 抽屉 reducer 单测（DRAWER-101）。
 *
 * 覆盖：
 * 1. drawerAccountRequested 的幂等（账号头回灌前 1 次请求、回灌后 0 次）；
 * 2. onDrawerAccountLoaded / onDrawerAvatarLoaded 写入账号头字段；
 * 3. drawerItemClicked 分流：contacts/settings 纯导航、saved 解析自聊、
 *    calls/invite/help 不产副作用；
 * 4. drawerAccountClicked → 我的资料；
 * 5. drawerNightModeSet 同值 no-op；
 * 6. ChatListUiState.copyWith 不再丢掉 drawer。
 */

import { describe, it, expect } from '@ohos/hypium';
import { ManualClock, SequentialIdGenerator } from '@tgx/core-common';
import { ReducerEnv, ReducerResult } from '@tgx/feature-template';
import { ChatListUiState } from '../main/ets/contract/ChatListUiState';
import { DrawerState, DrawerNavTarget, isDrawerAccountLoaded } from '../main/ets/contract/DrawerState';
import {
  DrawerAccountRequested,
  DrawerItemClicked,
  DrawerAccountClicked,
  OnDrawerAccountLoaded,
  OnDrawerAvatarLoaded,
  DrawerNightModeSet
} from '../main/ets/contract/ChatListIntent';
import {
  ChatListEffect,
  FetchDrawerAccount,
  DrawerNavigate,
  OpenSavedMessages
} from '../main/ets/contract/ChatListEffect';
import { chatListReducer } from '../main/ets/reducer/ChatListReducer';

function makeEnv(): ReducerEnv {
  const env: ReducerEnv = {
    clock: new ManualClock(1000, 500),
    ids: new SequentialIdGenerator('chat-list-drawer-test-')
  };
  return env;
}

function navigateTargetOf(result: ReducerResult<ChatListUiState, ChatListEffect>): DrawerNavTarget {
  expect(result.effects.length).assertEqual(1);
  const navigate: DrawerNavigate = result.effects[0] as DrawerNavigate;
  expect(navigate.kind).assertEqual('drawerNavigate');
  return navigate.target;
}

export default function chatListDrawerReducerTest(): void {
  describe('ChatListDrawerReducerTest', () => {

    it('drawerAccountRequested_emitsFetchOnceAndStopsAfterAccountLoaded', 0, () => {
      const initial: ChatListUiState = ChatListUiState.initial();
      expect(isDrawerAccountLoaded(initial.drawer)).assertFalse();

      const first: ReducerResult<ChatListUiState, ChatListEffect> =
        chatListReducer(initial, new DrawerAccountRequested(), makeEnv());
      expect(first.effects.length).assertEqual(1);
      expect((first.effects[0] as FetchDrawerAccount).kind).assertEqual('fetchDrawerAccount');

      const loaded: ReducerResult<ChatListUiState, ChatListEffect> =
        chatListReducer(first.state, new OnDrawerAccountLoaded(42, 'Alice', '+1 234', 'AL'), makeEnv());
      expect(isDrawerAccountLoaded(loaded.state.drawer)).assertTrue();
      expect(loaded.state.drawer.accountUserId).assertEqual(42);
      expect(loaded.state.drawer.accountName).assertEqual('Alice');
      expect(loaded.state.drawer.accountPhone).assertEqual('+1 234');
      expect(loaded.state.drawer.accountAvatarLetters).assertEqual('AL');
      expect(loaded.effects.length).assertEqual(0);

      // ≡ 再次开合：账号头已有数据，不再发请求。
      const again: ReducerResult<ChatListUiState, ChatListEffect> =
        chatListReducer(loaded.state, new DrawerAccountRequested(), makeEnv());
      expect(again.effects.length).assertEqual(0);
      expect(again.state).assertEqual(loaded.state);
    });

    it('onDrawerAvatarLoaded_setsPathAndIgnoresSameValue', 0, () => {
      const base: ChatListUiState = ChatListUiState.initial()
        .copyWith({ drawer: new DrawerState('Alice', '+1', null, 'AL', false, 42) });

      const withAvatar: ReducerResult<ChatListUiState, ChatListEffect> =
        chatListReducer(base, new OnDrawerAvatarLoaded('/data/avatar.jpg'), makeEnv());
      expect(withAvatar.state.drawer.accountAvatarPath).assertEqual('/data/avatar.jpg');
      // 头像回灌不得动掉账号字段。
      expect(withAvatar.state.drawer.accountUserId).assertEqual(42);
      expect(withAvatar.state.drawer.accountName).assertEqual('Alice');

      const same: ReducerResult<ChatListUiState, ChatListEffect> =
        chatListReducer(withAvatar.state, new OnDrawerAvatarLoaded('/data/avatar.jpg'), makeEnv());
      expect(same.state).assertEqual(withAvatar.state);
    });

    it('drawerItemClicked_routesContactsSettingsAndSaved', 0, () => {
      const state: ChatListUiState = ChatListUiState.initial();

      expect(navigateTargetOf(chatListReducer(state, new DrawerItemClicked('contacts'), makeEnv())))
        .assertEqual('contacts');
      expect(navigateTargetOf(chatListReducer(state, new DrawerItemClicked('settings'), makeEnv())))
        .assertEqual('settings');
      expect(navigateTargetOf(chatListReducer(state, new DrawerAccountClicked(), makeEnv())))
        .assertEqual('selfProfile');

      const saved: ReducerResult<ChatListUiState, ChatListEffect> =
        chatListReducer(state, new DrawerItemClicked('saved'), makeEnv());
      expect(saved.effects.length).assertEqual(1);
      expect((saved.effects[0] as OpenSavedMessages).kind).assertEqual('openSavedMessages');
    });

    it('drawerItemClicked_unimplementedItemsProduceNoEffect', 0, () => {
      const state: ChatListUiState = ChatListUiState.initial();
      const keys: ('calls' | 'invite' | 'help')[] = ['calls', 'invite', 'help'];
      for (let i = 0; i < keys.length; i++) {
        const result: ReducerResult<ChatListUiState, ChatListEffect> =
          chatListReducer(state, new DrawerItemClicked(keys[i]), makeEnv());
        expect(result.effects.length).assertEqual(0);
        expect(result.state).assertEqual(state);
      }
    });

    it('drawerNightModeSet_updatesFlagAndNoOpOnSameValue', 0, () => {
      const state: ChatListUiState = ChatListUiState.initial();
      const on: ReducerResult<ChatListUiState, ChatListEffect> =
        chatListReducer(state, new DrawerNightModeSet(true), makeEnv());
      expect(on.state.drawer.nightMode).assertTrue();
      expect(on.effects.length).assertEqual(0);

      const same: ReducerResult<ChatListUiState, ChatListEffect> =
        chatListReducer(on.state, new DrawerNightModeSet(true), makeEnv());
      expect(same.state).assertEqual(on.state);
    });

    it('copyWith_keepsDrawerWhenUnspecified', 0, () => {
      const withDrawer: ChatListUiState = ChatListUiState.initial()
        .copyWith({ drawer: new DrawerState('Alice', '+1', '/a.png', 'AL', true, 7) });
      // 会话加载等无关更新不得把账号头冲掉（此前抽屉状态在 reducer 之外，
      // 每次 items 刷新都会重建，是这轮的回归点）。
      const afterChats: ChatListUiState = withDrawer.copyWith({ isLoading: false });
      expect(afterChats.drawer.accountUserId).assertEqual(7);
      expect(afterChats.drawer.accountAvatarPath).assertEqual('/a.png');
      expect(afterChats.drawer.nightMode).assertTrue();
    });
  });
}
