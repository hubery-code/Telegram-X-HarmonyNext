/**
 * feature/profile — 群组/频道资料页 Reducer 纯函数（PROFILE-102）。
 *
 * 遵循 MVI 架构，100% Kit-free。
 */

import { Reducer, ReducerEnv, ReducerResult, reduced } from '@tgx/feature-template';
import { ChatProfileUiState } from '../contract/ChatProfileUiState';
import {
  ChatProfileIntent,
  OpenChatProfile,
  OnChatLoaded,
  OnBasicGroupFullInfoLoaded,
  OnSupergroupFullInfoLoaded,
  OnChatMembersLoaded,
  OnChatAvatarLoaded,
  OnChatProfileError,
  SelectChatMember
} from '../contract/ChatProfileIntent';
import {
  ChatProfileEffect,
  FetchChatDetailsEffect,
  NavigateToUserProfileEffect,
  CopyInviteLinkEffect,
  NavigateBackEffect
} from '../contract/ChatProfileEffect';
import { getGroupAvatarLetters, formatMemberCount } from '@tgx/core-domain';
import { ChatTypeSupergroup } from '@tgx/core-td-api-generated';

export const chatProfileReducer: Reducer<ChatProfileUiState, ChatProfileIntent, ChatProfileEffect> = (
  state: ChatProfileUiState,
  intent: ChatProfileIntent,
  _env: ReducerEnv
): ReducerResult<ChatProfileUiState, ChatProfileEffect> => {
  switch (intent.type) {
    case 'openChatProfile': {
      const open: OpenChatProfile = intent as OpenChatProfile;
      const next: ChatProfileUiState = state.copyWith({
        chatId: open.chatId,
        isLoading: true,
        errorMessage: ''
      });
      return reduced(next, [new FetchChatDetailsEffect(open.chatId)]);
    }

    case 'onChatLoaded': {
      const loaded: OnChatLoaded = intent as OnChatLoaded;
      const chat = loaded.chat;
      let isChannel: boolean = false;
      let isGroup: boolean = false;

      if (chat.type_) {
        if (chat.type_.type === 'chatTypeSupergroup') {
          const sgType: ChatTypeSupergroup = chat.type_ as ChatTypeSupergroup;
          isChannel = sgType.is_channel;
          isGroup = !isChannel;
        } else if (chat.type_.type === 'chatTypeBasicGroup') {
          isGroup = true;
          isChannel = false;
        }
      }

      const letters: string = getGroupAvatarLetters(chat.title);
      const colorIndex: number = Math.abs(chat.id) % 7;

      const next: ChatProfileUiState = state.copyWith({
        title: chat.title,
        isChannel: isChannel,
        isGroup: isGroup,
        avatarLetters: letters,
        avatarColorIndex: colorIndex,
        isLoading: false
      });
      return reduced(next);
    }

    case 'onBasicGroupFullInfoLoaded': {
      const loaded: OnBasicGroupFullInfoLoaded = intent as OnBasicGroupFullInfoLoaded;
      const info = loaded.info;
      const inviteUrl: string = info.invite_link ? info.invite_link.invite_link : '';
      const count: number = info.members ? info.members.length : 0;
      const next: ChatProfileUiState = state.copyWith({
        description: info.description,
        inviteLink: inviteUrl,
        memberCount: count,
        memberCountText: formatMemberCount(count, false),
        isLoading: false
      });
      return reduced(next);
    }

    case 'onSupergroupFullInfoLoaded': {
      const loaded: OnSupergroupFullInfoLoaded = intent as OnSupergroupFullInfoLoaded;
      const info = loaded.info;
      const inviteUrl: string = info.invite_link ? info.invite_link.invite_link : '';
      const count: number = info.member_count;
      const countText: string = formatMemberCount(count, state.isChannel);
      const next: ChatProfileUiState = state.copyWith({
        description: info.description,
        inviteLink: inviteUrl,
        memberCount: count,
        memberCountText: countText,
        isLoading: false
      });
      return reduced(next);
    }

    case 'onChatMembersLoaded': {
      const loaded: OnChatMembersLoaded = intent as OnChatMembersLoaded;
      const next: ChatProfileUiState = state.copyWith({
        members: loaded.members
      });
      return reduced(next);
    }

    case 'onChatAvatarLoaded': {
      const loaded: OnChatAvatarLoaded = intent as OnChatAvatarLoaded;
      const next: ChatProfileUiState = state.copyWith({
        photoPath: loaded.path
      });
      return reduced(next);
    }

    case 'onChatProfileError': {
      const errorIntent: OnChatProfileError = intent as OnChatProfileError;
      const next: ChatProfileUiState = state.copyWith({
        isLoading: false,
        errorMessage: errorIntent.error.message
      });
      return reduced(next);
    }

    case 'selectChatMember': {
      const select: SelectChatMember = intent as SelectChatMember;
      return reduced(state, [new NavigateToUserProfileEffect(select.userId)]);
    }

    case 'copyInviteLinkRequested': {
      if (state.inviteLink && state.inviteLink.length > 0) {
        return reduced(state, [new CopyInviteLinkEffect(state.inviteLink)]);
      }
      return reduced(state);
    }

    case 'backRequested': {
      return reduced(state, [new NavigateBackEffect()]);
    }

    default:
      return reduced(state);
  }
};
