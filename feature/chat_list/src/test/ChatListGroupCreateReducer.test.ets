/**
 * feature/chat_list — 建群/建频道命名段 reducer 单测（GROUP-CREATE-101）。
 *
 * 覆盖：
 * 1. drawerItemClicked(newGroup/newChannel) → DrawerNavigate 对应目标；
 * 2. groupCreateStarted 初始化命名段（重复派发以最新为准）；
 * 3. 标题/简介输入回灌；输入即清错；
 * 4. 提交本地校验：标题空 / 超 128 字 → 内联错误 key、不出请求；
 * 5. 提交合法：按模式产出 CreateBasicGroupChat / CreateSupergroupChat
 *    （trim 后标题），isSubmitting 置位并挡二次提交；
 * 6. onGroupChatCreated 清流程态 + NavigateToChat；onGroupCreateFailed 落
 *    通用错误 key 并复位 isSubmitting；
 * 7. groupCreateCancelled 清态；流程未激活时相关意图一律 no-op；
 * 8. copyWith 不丢 groupCreate（回归）。
 */

import { describe, it, expect } from '@ohos/hypium';
import { ManualClock, SequentialIdGenerator, AppErrors } from '@tgx/core-common';
import { GROUP_TITLE_MAX_LENGTH } from '@tgx/core-domain';
import { ReducerEnv, ReducerResult } from '@tgx/feature-template';
import { ChatListUiState } from '../main/ets/contract/ChatListUiState';
import { GroupCreateState } from '../main/ets/contract/GroupCreateState';
import {
  ChatListIntent,
  DrawerItemClicked,
  GroupCreateStarted,
  GroupCreateTitleChanged,
  GroupCreateDescriptionChanged,
  GroupCreateSubmitRequested,
  GroupCreateCancelled,
  OnGroupChatCreated,
  OnGroupCreateFailed
} from '../main/ets/contract/ChatListIntent';
import {
  ChatListEffect,
  DrawerNavigate,
  NavigateToChat,
  CreateBasicGroupChat,
  CreateSupergroupChat
} from '../main/ets/contract/ChatListEffect';
import {
  chatListReducer,
  groupCreateTitleErrorKey,
  GROUP_CREATE_TITLE_EMPTY_KEY,
  GROUP_CREATE_TITLE_TOO_LONG_KEY,
  GROUP_CREATE_FAILED_KEY
} from '../main/ets/reducer/ChatListReducer';

function makeEnv(): ReducerEnv {
  const env: ReducerEnv = {
    clock: new ManualClock(1000, 500),
    ids: new SequentialIdGenerator('group-create-test-')
  };
  return env;
}

function startedGroupState(): ChatListUiState {
  return chatListReducer(
    ChatListUiState.initial(),
    new GroupCreateStarted('group', [7, 9]),
    makeEnv()
  ).state;
}

function startedChannelState(): ChatListUiState {
  return chatListReducer(
    ChatListUiState.initial(),
    new GroupCreateStarted('channel', []),
    makeEnv()
  ).state;
}

export default function chatListGroupCreateReducerTest(): void {
  describe('ChatListGroupCreateReducerTest', () => {

    it('drawerItemClicked_newGroupAndChannelEmitNavigateTargets', 0, () => {
      const state: ChatListUiState = ChatListUiState.initial();

      const group: ReducerResult<ChatListUiState, ChatListEffect> =
        chatListReducer(state, new DrawerItemClicked('newGroup'), makeEnv());
      expect(group.effects.length).assertEqual(1);
      expect((group.effects[0] as DrawerNavigate).target).assertEqual('newGroup');
      // 入口只导航：不动命名段状态（流程由装配层接力启动）。
      expect(group.state.groupCreate === null).assertTrue();

      const channel: ReducerResult<ChatListUiState, ChatListEffect> =
        chatListReducer(state, new DrawerItemClicked('newChannel'), makeEnv());
      expect(channel.effects.length).assertEqual(1);
      expect((channel.effects[0] as DrawerNavigate).target).assertEqual('newChannel');
    });

    it('groupCreateStarted_initializesNamingStateAndRestarts', 0, () => {
      const state: ChatListUiState = startedGroupState();
      expect(state.groupCreate !== null).assertTrue();
      expect(state.groupCreate!.mode).assertEqual('group');
      expect(state.groupCreate!.memberUserIds.length).assertEqual(2);
      expect(state.groupCreate!.memberUserIds[0]).assertEqual(7);
      expect(state.groupCreate!.isSubmitting).assertFalse();

      // 重复进入（装配层重复派发）：以最新一次为准，不保留旧输入。
      const restarted: ReducerResult<ChatListUiState, ChatListEffect> =
        chatListReducer(state, new GroupCreateStarted('channel', []), makeEnv());
      expect(restarted.state.groupCreate!.mode).assertEqual('channel');
      expect(restarted.state.groupCreate!.memberUserIds.length).assertEqual(0);
    });

    it('groupCreateTitleErrorKey_mapsEmptyAndOverlong', 0, () => {
      expect(groupCreateTitleErrorKey('   ')).assertEqual(GROUP_CREATE_TITLE_EMPTY_KEY);
      expect(groupCreateTitleErrorKey('')).assertEqual(GROUP_CREATE_TITLE_EMPTY_KEY);
      const overlong: string = 'a'.repeat(GROUP_TITLE_MAX_LENGTH + 1);
      expect(groupCreateTitleErrorKey(overlong)).assertEqual(GROUP_CREATE_TITLE_TOO_LONG_KEY);
      expect(groupCreateTitleErrorKey('  Ok ')).assertEqual(null);
    });

    it('groupCreateTitleAndDescriptionChanged_flowIntoStateAndClearError', 0, () => {
      let state: ChatListUiState = startedGroupState();

      // 先制造一条错误（空标题提交）。
      const failed: ReducerResult<ChatListUiState, ChatListEffect> =
        chatListReducer(state, new GroupCreateSubmitRequested(), makeEnv());
      state = failed.state;
      expect(state.groupCreate!.errorMessageKey).assertEqual(GROUP_CREATE_TITLE_EMPTY_KEY);

      // 输入即清错。
      const typed: ReducerResult<ChatListUiState, ChatListEffect> =
        chatListReducer(state, new GroupCreateTitleChanged('My Group'), makeEnv());
      expect(typed.state.groupCreate!.title).assertEqual('My Group');
      expect(typed.state.groupCreate!.errorMessageKey).assertEqual(null);

      const described: ReducerResult<ChatListUiState, ChatListEffect> =
        chatListReducer(typed.state, new GroupCreateDescriptionChanged('Hello'), makeEnv());
      expect(described.state.groupCreate!.description).assertEqual('Hello');
      // 简介输入不清错误：错误条语义是「上一次提交的问题」。
      expect(described.state.groupCreate!.title).assertEqual('My Group');
    });

    it('groupCreateSubmitRequested_emptyTitleSetsErrorWithoutEffect', 0, () => {
      const state: ChatListUiState = startedGroupState();
      const result: ReducerResult<ChatListUiState, ChatListEffect> =
        chatListReducer(state, new GroupCreateSubmitRequested(), makeEnv());
      expect(result.effects.length).assertEqual(0);
      expect(result.state.groupCreate!.isSubmitting).assertFalse();
      expect(result.state.groupCreate!.errorMessageKey).assertEqual(GROUP_CREATE_TITLE_EMPTY_KEY);
    });

    it('groupCreateSubmitRequested_overlongTitleSetsErrorWithoutEffect', 0, () => {
      const state: ChatListUiState = chatListReducer(
        startedGroupState(),
        new GroupCreateTitleChanged('a'.repeat(GROUP_TITLE_MAX_LENGTH + 1)),
        makeEnv()
      ).state;
      const result: ReducerResult<ChatListUiState, ChatListEffect> =
        chatListReducer(state, new GroupCreateSubmitRequested(), makeEnv());
      expect(result.effects.length).assertEqual(0);
      expect(result.state.groupCreate!.errorMessageKey).assertEqual(GROUP_CREATE_TITLE_TOO_LONG_KEY);
    });

    it('groupCreateSubmitRequested_groupModeEmitsCreateBasicGroupChat', 0, () => {
      let state: ChatListUiState = startedGroupState();
      state = chatListReducer(state, new GroupCreateTitleChanged('  My Group  '), makeEnv()).state;

      const result: ReducerResult<ChatListUiState, ChatListEffect> =
        chatListReducer(state, new GroupCreateSubmitRequested(), makeEnv());
      expect(result.effects.length).assertEqual(1);
      const effect: CreateBasicGroupChat = result.effects[0] as CreateBasicGroupChat;
      expect(effect.kind).assertEqual('createBasicGroupChat');
      // effect 带 trim 后标题；成员按点选顺序原样携带。
      expect(effect.title).assertEqual('My Group');
      expect(effect.memberUserIds.length).assertEqual(2);
      expect(effect.memberUserIds[0]).assertEqual(7);
      expect(result.state.groupCreate!.isSubmitting).assertTrue();
    });

    it('groupCreateSubmitRequested_channelModeEmitsCreateSupergroupChat', 0, () => {
      let state: ChatListUiState = startedChannelState();
      state = chatListReducer(state, new GroupCreateTitleChanged('My Channel'), makeEnv()).state;
      state = chatListReducer(state, new GroupCreateDescriptionChanged('  News  '), makeEnv()).state;

      const result: ReducerResult<ChatListUiState, ChatListEffect> =
        chatListReducer(state, new GroupCreateSubmitRequested(), makeEnv());
      expect(result.effects.length).assertEqual(1);
      const effect: CreateSupergroupChat = result.effects[0] as CreateSupergroupChat;
      expect(effect.kind).assertEqual('createSupergroupChat');
      expect(effect.title).assertEqual('My Channel');
      expect(effect.isChannel).assertTrue();
      expect(effect.description).assertEqual('News');
      expect(result.state.groupCreate!.isSubmitting).assertTrue();
    });

    it('groupCreateSubmitRequested_doubleSubmitIsNoOp', 0, () => {
      let state: ChatListUiState = startedGroupState();
      state = chatListReducer(state, new GroupCreateTitleChanged('My Group'), makeEnv()).state;
      const first: ReducerResult<ChatListUiState, ChatListEffect> =
        chatListReducer(state, new GroupCreateSubmitRequested(), makeEnv());
      expect(first.state.groupCreate!.isSubmitting).assertTrue();
      expect(first.effects.length).assertEqual(1);

      // 在途时再点创建：不出第二条请求。
      const second: ReducerResult<ChatListUiState, ChatListEffect> =
        chatListReducer(first.state, new GroupCreateSubmitRequested(), makeEnv());
      expect(second.effects.length).assertEqual(0);
      expect(second.state).assertEqual(first.state);
    });

    it('onGroupChatCreated_clearsFlowAndNavigatesToChat', 0, () => {
      const state: ChatListUiState = startedGroupState();
      const result: ReducerResult<ChatListUiState, ChatListEffect> =
        chatListReducer(state, new OnGroupChatCreated(-1001234), makeEnv());
      expect(result.effects.length).assertEqual(1);
      expect((result.effects[0] as NavigateToChat).chatId).assertEqual(-1001234);
      expect(result.state.groupCreate === null).assertTrue();
    });

    it('onGroupCreateFailed_setsGenericErrorAndResetsSubmitting', 0, () => {
      let state: ChatListUiState = startedGroupState();
      state = chatListReducer(state, new GroupCreateTitleChanged('My Group'), makeEnv()).state;
      state = chatListReducer(state, new GroupCreateSubmitRequested(), makeEnv()).state;
      expect(state.groupCreate!.isSubmitting).assertTrue();

      const result: ReducerResult<ChatListUiState, ChatListEffect> =
        chatListReducer(state, new OnGroupCreateFailed(AppErrors.network('unknown', 'socket failed', true)), makeEnv());
      expect(result.effects.length).assertEqual(0);
      expect(result.state.groupCreate!.isSubmitting).assertFalse();
      expect(result.state.groupCreate!.errorMessageKey).assertEqual(GROUP_CREATE_FAILED_KEY);
      // 输入保留：失败后用户改标题重试，不应被清空。
      expect(result.state.groupCreate!.title).assertEqual('My Group');
    });

    it('groupCreateCancelled_clearsFlowAndIsNoOpWhenInactive', 0, () => {
      const state: ChatListUiState = startedGroupState();
      const cancelled: ReducerResult<ChatListUiState, ChatListEffect> =
        chatListReducer(state, new GroupCreateCancelled(), makeEnv());
      expect(cancelled.state.groupCreate === null).assertTrue();

      const again: ReducerResult<ChatListUiState, ChatListEffect> =
        chatListReducer(cancelled.state, new GroupCreateCancelled(), makeEnv());
      expect(again.state).assertEqual(cancelled.state);
    });

    it('groupCreateIntents_areNoOpWhenFlowInactive', 0, () => {
      const state: ChatListUiState = ChatListUiState.initial();
      const intents: ChatListIntent[] = [
        new GroupCreateTitleChanged('x'),
        new GroupCreateDescriptionChanged('y'),
        new GroupCreateSubmitRequested(),
        new OnGroupChatCreated(1),
        new OnGroupCreateFailed(AppErrors.network('unknown', 'boom', true))
      ];
      for (let i: number = 0; i < intents.length; i++) {
        const result: ReducerResult<ChatListUiState, ChatListEffect> =
          chatListReducer(state, intents[i], makeEnv());
        expect(result.effects.length).assertEqual(0);
        expect(result.state).assertEqual(state);
      }
    });

    it('copyWith_keepsGroupCreateWhenUnspecified', 0, () => {
      const state: ChatListUiState = startedGroupState();
      // 列表刷新等无关更新不得把命名段冲掉。
      const afterChats: ChatListUiState = state.copyWith({ isLoading: false });
      expect(afterChats.groupCreate !== null).assertTrue();
      expect(afterChats.groupCreate!.mode).assertEqual('group');
      expect(afterChats.groupCreate!.memberUserIds.length).assertEqual(2);
    });

    it('groupCreateState_copyWithKeepsFields', 0, () => {
      const base: GroupCreateState = new GroupCreateState('group', [1, 2], 'Title', 'Desc', false, null);
      const patched: GroupCreateState = base.copyWith({ isSubmitting: true });
      expect(patched.isSubmitting).assertTrue();
      expect(patched.mode).assertEqual('group');
      expect(patched.memberUserIds.length).assertEqual(2);
      expect(patched.title).assertEqual('Title');
      expect(patched.description).assertEqual('Desc');
    });
  });
}
