/**
 * feature/profile — ChatProfileReducer 单元测试（PROFILE-102）。
 */

import { describe, it, expect } from '@ohos/hypium';
import { ReducerEnv, ReducerResult } from '@tgx/feature-template';
import { AppError, AppErrors, ManualClock, SequentialIdGenerator } from '@tgx/core-common';
import {
  Chat,
  BasicGroupFullInfo,
  SupergroupFullInfo,
  ChatTypeBasicGroup,
  ChatTypeSupergroup,
  ChatInviteLink
} from '@tgx/core-td-api-generated';
import {
  ChatProfileUiState,
  ChatProfileUiStateOptions,
  ChatMemberUiItem
} from '../main/ets/contract/ChatProfileUiState';
import {
  OpenChatProfile,
  OnChatLoaded,
  OnBasicGroupFullInfoLoaded,
  OnSupergroupFullInfoLoaded,
  OnChatMembersLoaded,
  OnChatAvatarLoaded,
  OnChatProfileError,
  SelectChatMember,
  CopyInviteLinkRequested,
  BackRequested
} from '../main/ets/contract/ChatProfileIntent';
import {
  ChatProfileEffect,
  FetchChatDetailsEffect,
  NavigateToUserProfileEffect,
  CopyInviteLinkEffect,
  NavigateBackEffect
} from '../main/ets/contract/ChatProfileEffect';
import { chatProfileReducer } from '../main/ets/reducer/ChatProfileReducer';

function makeEnv(): ReducerEnv {
  return {
    clock: new ManualClock(1000, 500),
    ids: new SequentialIdGenerator('test-chat-profile-')
  };
}

export default function chatProfileReducerTest(): void {
  describe('ChatProfileReducer', (): void => {
    it('openChatProfile sets loading and emits FetchChatDetailsEffect', 0, (): void => {
      const state: ChatProfileUiState = ChatProfileUiState.initial();
      const res: ReducerResult<ChatProfileUiState, ChatProfileEffect> =
        chatProfileReducer(state, new OpenChatProfile(12345), makeEnv());

      expect(res.state.chatId).assertEqual(12345);
      expect(res.state.isLoading).assertTrue();
      expect(res.effects.length).assertEqual(1);
      expect(res.effects[0].type).assertEqual('fetchChatDetailsEffect');
      const fetchEffect: FetchChatDetailsEffect = res.effects[0] as FetchChatDetailsEffect;
      expect(fetchEffect.chatId).assertEqual(12345);
    });

    it('onChatLoaded resolves basic group properties', 0, (): void => {
      const opt: ChatProfileUiStateOptions = { chatId: 12345 };
      const state: ChatProfileUiState = ChatProfileUiState.initial().copyWith(opt);
      const chat: Chat = new Chat();
      chat.id = 12345;
      chat.title = 'Harmony Dev Group';
      const bgType: ChatTypeBasicGroup = new ChatTypeBasicGroup();
      bgType.basic_group_id = 999;
      chat.type_ = bgType;

      const res: ReducerResult<ChatProfileUiState, ChatProfileEffect> =
        chatProfileReducer(state, new OnChatLoaded(chat), makeEnv());

      expect(res.state.title).assertEqual('Harmony Dev Group');
      expect(res.state.isGroup).assertTrue();
      expect(res.state.isChannel).assertFalse();
      expect(res.state.avatarLetters).assertEqual('HD');
      expect(res.state.isLoading).assertFalse();
      // chatId 已知即拉默认 Tab（媒体）：不主动拉，用户看到的空网格是在撒谎。
      expect(res.effects.length).assertEqual(1);
      expect(res.effects[0].type).assertEqual('fetchSharedContentEffect');
      expect(res.state.sharedInitialRequested).assertTrue();
      expect(res.state.sharedLoading).assertTrue();
    });

    it('onChatLoaded resolves channel properties', 0, (): void => {
      const opt: ChatProfileUiStateOptions = { chatId: 23456 };
      const state: ChatProfileUiState = ChatProfileUiState.initial().copyWith(opt);
      const chat: Chat = new Chat();
      chat.id = 23456;
      chat.title = 'News Channel';
      const sgType: ChatTypeSupergroup = new ChatTypeSupergroup();
      sgType.supergroup_id = 888;
      sgType.is_channel = true;
      chat.type_ = sgType;

      const res: ReducerResult<ChatProfileUiState, ChatProfileEffect> =
        chatProfileReducer(state, new OnChatLoaded(chat), makeEnv());

      expect(res.state.title).assertEqual('News Channel');
      expect(res.state.isGroup).assertFalse();
      expect(res.state.isChannel).assertTrue();
      expect(res.state.avatarLetters).assertEqual('NC');
      expect(res.effects.length).assertEqual(1);
      expect(res.effects[0].type).assertEqual('fetchSharedContentEffect');
    });

    it('onChatLoaded_does_not_refetch_shared_content_when_already_requested', 0, (): void => {
      // 晚到的回灌帧（full info / 成员）会再次触发 onChatLoaded：不闩住就反复重发首屏。
      const opt: ChatProfileUiStateOptions = { chatId: 23456, sharedInitialRequested: true };
      const state: ChatProfileUiState = ChatProfileUiState.initial().copyWith(opt);
      const chat: Chat = new Chat();
      chat.id = 23456;
      chat.title = 'News Channel';
      const sgType: ChatTypeSupergroup = new ChatTypeSupergroup();
      sgType.supergroup_id = 888;
      sgType.is_channel = true;
      chat.type_ = sgType;

      const res: ReducerResult<ChatProfileUiState, ChatProfileEffect> =
        chatProfileReducer(state, new OnChatLoaded(chat), makeEnv());

      expect(res.effects.length).assertEqual(0);
    });

    it('onBasicGroupFullInfoLoaded updates description and inviteLink', 0, (): void => {
      const opt: ChatProfileUiStateOptions = { isGroup: true };
      const state: ChatProfileUiState = ChatProfileUiState.initial().copyWith(opt);
      const info: BasicGroupFullInfo = new BasicGroupFullInfo();
      info.description = 'A cool group description';
      const link: ChatInviteLink = new ChatInviteLink();
      link.invite_link = 'https://t.me/+AbCdEf';
      info.invite_link = link;

      const res: ReducerResult<ChatProfileUiState, ChatProfileEffect> =
        chatProfileReducer(state, new OnBasicGroupFullInfoLoaded(info), makeEnv());

      expect(res.state.description).assertEqual('A cool group description');
      expect(res.state.inviteLink).assertEqual('https://t.me/+AbCdEf');
      expect(res.state.isLoading).assertFalse();
    });

    it('onSupergroupFullInfoLoaded updates member count and subtitle', 0, (): void => {
      const opt: ChatProfileUiStateOptions = { isChannel: false };
      const state: ChatProfileUiState = ChatProfileUiState.initial().copyWith(opt);
      const info: SupergroupFullInfo = new SupergroupFullInfo();
      info.description = 'Supergroup info';
      info.member_count = 150;

      const res: ReducerResult<ChatProfileUiState, ChatProfileEffect> =
        chatProfileReducer(state, new OnSupergroupFullInfoLoaded(info), makeEnv());

      expect(res.state.description).assertEqual('Supergroup info');
      expect(res.state.memberCount).assertEqual(150);
      expect(res.state.memberCountText).assertEqual('150 members');
    });

    it('onChatMembersLoaded updates members list', 0, (): void => {
      const state: ChatProfileUiState = ChatProfileUiState.initial();
      const member1: ChatMemberUiItem = {
        userId: 1,
        fullName: 'Alice',
        username: 'alice',
        avatarLetters: 'A',
        avatarColorIndex: 0,
        avatarPath: null,
        role: 'Owner',
        isOnline: true,
        statusText: 'online'
      };
      const member2: ChatMemberUiItem = {
        userId: 2,
        fullName: 'Bob',
        username: 'bob',
        avatarLetters: 'B',
        avatarColorIndex: 1,
        avatarPath: null,
        role: '',
        isOnline: false,
        statusText: 'last seen recently'
      };

      const res: ReducerResult<ChatProfileUiState, ChatProfileEffect> =
        chatProfileReducer(state, new OnChatMembersLoaded([member1, member2]), makeEnv());

      expect(res.state.members.length).assertEqual(2);
      expect(res.state.members[0].fullName).assertEqual('Alice');
      expect(res.state.members[0].role).assertEqual('Owner');
      expect(res.state.members[1].fullName).assertEqual('Bob');
    });

    it('onChatAvatarLoaded updates photoPath', 0, (): void => {
      const state: ChatProfileUiState = ChatProfileUiState.initial();
      const res: ReducerResult<ChatProfileUiState, ChatProfileEffect> =
        chatProfileReducer(state, new OnChatAvatarLoaded('/cache/photos/group.jpg'), makeEnv());

      expect(res.state.photoPath).assertEqual('/cache/photos/group.jpg');
    });

    it('onChatProfileError sets error message and clears loading', 0, (): void => {
      const opt: ChatProfileUiStateOptions = { isLoading: true };
      const state: ChatProfileUiState = ChatProfileUiState.initial().copyWith(opt);
      const error: AppError = AppErrors.tdlib('not_found', 'Chat does not exist', false);
      const res: ReducerResult<ChatProfileUiState, ChatProfileEffect> =
        chatProfileReducer(state, new OnChatProfileError(error), makeEnv());

      expect(res.state.isLoading).assertFalse();
      expect(res.state.errorMessage).assertEqual('Chat does not exist');
    });

    it('selectChatMember emits NavigateToUserProfileEffect', 0, (): void => {
      const state: ChatProfileUiState = ChatProfileUiState.initial();
      const res: ReducerResult<ChatProfileUiState, ChatProfileEffect> =
        chatProfileReducer(state, new SelectChatMember(42), makeEnv());

      expect(res.effects.length).assertEqual(1);
      expect(res.effects[0].type).assertEqual('navigateToUserProfileEffect');
      const nav: NavigateToUserProfileEffect = res.effects[0] as NavigateToUserProfileEffect;
      expect(nav.userId).assertEqual(42);
    });

    it('copyInviteLinkRequested emits CopyInviteLinkEffect when link is non-empty', 0, (): void => {
      const opt: ChatProfileUiStateOptions = { inviteLink: 'https://t.me/+join123' };
      const state: ChatProfileUiState = ChatProfileUiState.initial().copyWith(opt);
      const res: ReducerResult<ChatProfileUiState, ChatProfileEffect> =
        chatProfileReducer(state, new CopyInviteLinkRequested(), makeEnv());

      expect(res.effects.length).assertEqual(1);
      expect(res.effects[0].type).assertEqual('copyInviteLinkEffect');
      const copy: CopyInviteLinkEffect = res.effects[0] as CopyInviteLinkEffect;
      expect(copy.link).assertEqual('https://t.me/+join123');
    });

    it('backRequested emits NavigateBackEffect', 0, (): void => {
      const state: ChatProfileUiState = ChatProfileUiState.initial();
      const res: ReducerResult<ChatProfileUiState, ChatProfileEffect> =
        chatProfileReducer(state, new BackRequested(), makeEnv());

      expect(res.effects.length).assertEqual(1);
      expect(res.effects[0].type).assertEqual('navigateBackEffect');
    });
  });
}
