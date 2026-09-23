/**
 * feature/profile — 群组/频道资料页 Reducer 纯函数（PROFILE-102；CHATPROF-SHARED 扩展共享内容）。
 *
 * 遵循 MVI 架构，100% Kit-free。共享内容四态与用户资料页 ProfileReducer 同规则：
 * 切 Tab 只在「该 Tab 还没拉到东西」时才发请求，失败与空区分开。
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
  OnSharedTabSelected,
  LoadMoreSharedContent,
  OnSharedContentLoaded,
  OnSharedContentFailed,
  SelectChatMember
} from '../contract/ChatProfileIntent';
import {
  ChatProfileEffect,
  FetchChatDetailsEffect,
  FetchSharedContentEffect,
  FetchMoreSharedContentEffect,
  NavigateToUserProfileEffect,
  CopyInviteLinkEffect,
  NavigateBackEffect
} from '../contract/ChatProfileEffect';
import { getGroupAvatarLetters, formatMemberCount } from '@tgx/core-domain';
import { ChatTypeSupergroup } from '@tgx/core-td-api-generated';

/** 共享内容 Tab 数（媒体/文件/链接；「共同群组」只在私聊资料页有）。 */
const SHARED_TAB_COUNT: number = 3;

/** 该 Tab 当前是否一条都没拉到（用于「失败后点同一 Tab 重试」的判定）。 */
function isSharedTabEmpty(state: ChatProfileUiState, tab: number): boolean {
  if (tab === 0) {
    return state.sharedMedia.length === 0;
  }
  if (tab === 1) {
    return state.sharedFiles.length === 0;
  }
  return state.sharedLinks.length === 0;
}

export const chatProfileReducer: Reducer<ChatProfileUiState, ChatProfileIntent, ChatProfileEffect> = (
  state: ChatProfileUiState,
  intent: ChatProfileIntent,
  _env: ReducerEnv
): ReducerResult<ChatProfileUiState, ChatProfileEffect> => {
  switch (intent.type) {
    case 'openChatProfile': {
      const open: OpenChatProfile = intent as OpenChatProfile;
      // 换一个会话，上一个会话的共享内容必须清空，否则页面会把旧网格当成新群的数据。
      const next: ChatProfileUiState = state.copyWith({
        chatId: open.chatId,
        isLoading: true,
        errorMessage: '',
        activeSharedTab: 0,
        sharedMedia: [],
        sharedFiles: [],
        sharedLinks: [],
        sharedLoading: false,
        sharedHasMore: true,
        sharedLoadingMore: false,
        sharedInitialRequested: false,
        sharedLoadFailed: false
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
      // 默认 Tab（媒体）是打开页面就要问 TDLib 的东西：不主动拉，用户看到的空网格
      // 是在撒谎。chatId 此刻已知（不像私聊页还要先 createPrivateChat），所以挂在这里。
      // 只发一次 —— full info / 成员的晚到回灌会再触发若干帧。
      // chatId 可以是负数（超级群组/频道用 -100… 规范 id），所以判「未设置」只能看 0。
      if (next.chatId !== 0 && !next.sharedInitialRequested) {
        return reduced(next.copyWith({
          sharedInitialRequested: true,
          sharedLoading: true,
          sharedLoadFailed: false
        }), [new FetchSharedContentEffect(next.activeSharedTab)]);
      }
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

    case 'onSharedTabSelected': {
      const selected: OnSharedTabSelected = intent as OnSharedTabSelected;
      if (selected.tab < 0 || selected.tab >= SHARED_TAB_COUNT) {
        return reduced(state);
      }
      // 「未加载过」以该 Tab 条目非空判定（空结果会在下次进入时重试）。
      if (!isSharedTabEmpty(state, selected.tab)) {
        if (selected.tab === state.activeSharedTab) {
          // 已有内容且就停在这一 Tab：重复点击完全 no-op。
          return reduced(state);
        }
        // 已有内容：仅切 Tab，不触发请求也不转圈。
        return reduced(state.copyWith({
          activeSharedTab: selected.tab,
          sharedLoading: false,
          sharedLoadingMore: false,
          sharedLoadFailed: false,
          sharedHasMore: true
        }));
      }
      const next: ChatProfileUiState = state.copyWith({
        activeSharedTab: selected.tab,
        sharedLoading: true,
        sharedLoadingMore: false,
        sharedLoadFailed: false,
        sharedHasMore: true
      });
      return reduced(next, [new FetchSharedContentEffect(selected.tab)]);
    }

    case 'loadMoreSharedContent': {
      const loadMore: LoadMoreSharedContent = intent as LoadMoreSharedContent;
      if (loadMore.tab < 0 || loadMore.tab >= SHARED_TAB_COUNT) {
        return reduced(state);
      }
      if (state.sharedLoading || state.sharedLoadingMore || !state.sharedHasMore) {
        return reduced(state);
      }
      const next: ChatProfileUiState = state.copyWith({ sharedLoadingMore: true });
      return reduced(next, [new FetchMoreSharedContentEffect(loadMore.tab)]);
    }

    case 'onSharedContentLoaded': {
      const loaded: OnSharedContentLoaded = intent as OnSharedContentLoaded;
      return reduced(state.copyWith({
        sharedMedia: loaded.media,
        sharedFiles: loaded.files,
        sharedLinks: loaded.links,
        sharedLoading: false,
        sharedLoadingMore: false,
        sharedLoadFailed: false,
        sharedHasMore: loaded.hasMore
      }));
    }

    case 'onSharedContentFailed': {
      const failed: OnSharedContentFailed = intent as OnSharedContentFailed;
      if (failed.tab !== state.activeSharedTab) {
        return reduced(state);
      }
      return reduced(state.copyWith({
        sharedLoading: false,
        sharedLoadingMore: false,
        sharedLoadFailed: true
      }));
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
