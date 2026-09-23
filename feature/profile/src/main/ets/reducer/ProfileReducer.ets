/**
 * feature/profile — 用户资料页纯 reducer（PROFILE-101）。
 *
 * 与 ChatReducer 同约定：未知 kind 走尾部 default 原样返回
 * （MessageUserRequested 出效应；其余均为状态回灌）。
 */

import { Reducer, ReducerEnv, ReducerResult, reduced } from '@tgx/feature-template';
import { ProfileUiState } from '../contract/ProfileUiState';
import {
  MessageUserRequested,
  OnProfileLoaded,
  OnBioLoaded,
  OnEmojiStatusLoaded,
  OnAvatarFileLoaded,
  OnProfileFailed,
  OnBirthdayLoaded,
  OnSharedTabSelected,
  LoadMoreSharedContent,
  OnSharedContentLoaded,
  OnSharedGroupsLoaded,
  OnSharedContentFailed,
  OpenSharedChatRequested,
  OnChatNotificationLoaded,
  OnChatNotificationFailed,
  ProfileIntent
} from '../contract/ProfileIntent';
import {
  CreatePrivateChatEffect,
  FetchSharedContent,
  FetchSharedGroups,
  FetchMoreSharedContent,
  OpenSharedChatEffect,
  FetchChatNotification,
  SetChatNotification,
  ProfileEffect
} from '../contract/ProfileEffect';

/** 共享内容 Tab 数（媒体/文件/链接/群组）。 */
const SHARED_TAB_COUNT: number = 4;

/** 该 Tab 当前是否一条都没拉到（用于「失败后点同一 Tab 重试」的判定）。 */
function isSharedTabEmpty(state: ProfileUiState, tab: number): boolean {
  if (tab === 0) {
    return state.sharedMedia.length === 0;
  }
  if (tab === 1) {
    return state.sharedFiles.length === 0;
  }
  if (tab === 2) {
    return state.sharedLinks.length === 0;
  }
  return state.sharedGroups.length === 0;
}

function loadedProfileState(state: ProfileUiState, loaded: OnProfileLoaded): ProfileUiState {
  return state.copyWith({
    displayName: loaded.displayName,
    username: loaded.username,
    phone: loaded.phone,
    statusText: loaded.statusText,
    avatarLetters: loaded.avatarLetters,
    avatarColorIndex: loaded.avatarColorIndex,
    isLoading: false,
    errorMessage: null
  });
}

export const profileReducer: Reducer<ProfileUiState, ProfileIntent, ProfileEffect> = (
  state: ProfileUiState,
  intent: ProfileIntent,
  _env: ReducerEnv
): ReducerResult<ProfileUiState, ProfileEffect> => {
  switch (intent.kind) {
    case 'messageUserRequested': {
      if (state.userId <= 0) {
        return reduced(state);
      }
      const effect: CreatePrivateChatEffect = new CreatePrivateChatEffect(state.userId);
      return reduced(state, [effect]);
    }

    case 'onProfileLoaded': {
      const loaded: OnProfileLoaded = intent as OnProfileLoaded;
      const next: ProfileUiState = loadedProfileState(state, loaded);
      // 默认 Tab（媒体）与通知态都是页面打开即要问 TDLib 的东西：
      // 不主动拉，用户看到的空网格和写死的「开启」都是在撒谎。各自只发一次
      // （updateUser 订阅晚到还会再回灌一次 profile，不闩住会反复重发）。
      const effects: ProfileEffect[] = [];
      let staged: ProfileUiState = next;
      if (!next.sharedInitialRequested) {
        effects.push(new FetchSharedContent(next.activeSharedTab));
        staged = staged.copyWith({
          sharedInitialRequested: true,
          sharedLoading: true,
          sharedLoadFailed: false
        });
      }
      if (!next.notificationRequested) {
        effects.push(new FetchChatNotification());
        staged = staged.copyWith({ notificationRequested: true });
      }
      if (effects.length === 0) {
        return reduced(next);
      }
      return reduced(staged, effects);
    }

    case 'notificationRowTapped': {
      // 未回读到真值前不响应：此时点一下会把「未知」翻成一个凭空的静音态。
      if (!state.notificationReady || state.notificationUpdating) {
        return reduced(state);
      }
      const effect: SetChatNotification = new SetChatNotification(!state.notificationMuted);
      return reduced(state.copyWith({ notificationUpdating: true }), [effect]);
    }

    case 'onChatNotificationLoaded': {
      const loaded: OnChatNotificationLoaded = intent as OnChatNotificationLoaded;
      return reduced(state.copyWith({
        notificationMuted: loaded.muted,
        notificationReady: true,
        notificationUpdating: false
      }));
    }

    case 'onChatNotificationFailed': {
      // 读不到就退回「未知」，继续显示上一个真值同样是撒谎。
      return reduced(state.copyWith({
        notificationReady: false,
        notificationUpdating: false
      }));
    }

    case 'onBioLoaded': {
      const bio: OnBioLoaded = intent as OnBioLoaded;
      return reduced(state.copyWith({ bio: bio.bio }));
    }

    case 'onEmojiStatusLoaded': {
      const es: OnEmojiStatusLoaded = intent as OnEmojiStatusLoaded;
      return reduced(state.copyWith({ emojiStatusEmoji: es.emoji }));
    }

    case 'onAvatarFileLoaded': {
      const avatar: OnAvatarFileLoaded = intent as OnAvatarFileLoaded;
      return reduced(state.copyWith({ avatarPath: avatar.path }));
    }

    case 'onProfileFailed': {
      const failed: OnProfileFailed = intent as OnProfileFailed;
      return reduced(state.copyWith({ isLoading: false, errorMessage: failed.error.message }));
    }

    case 'onBirthdayLoaded': {
      const birthday: OnBirthdayLoaded = intent as OnBirthdayLoaded;
      return reduced(state.copyWith({ birthdayText: birthday.birthdayText }));
    }

    case 'onSharedTabSelected': {
      const selected: OnSharedTabSelected = intent as OnSharedTabSelected;
      if (selected.tab < 0 || selected.tab >= SHARED_TAB_COUNT) {
        return reduced(state);
      }
      // 「未加载过」以该 Tab 条目非空判定（空结果会在下次进入时重试）。
      const tabIsEmpty: boolean = isSharedTabEmpty(state, selected.tab);
      if (!tabIsEmpty) {
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
      const next: ProfileUiState = state.copyWith({
        activeSharedTab: selected.tab,
        sharedLoading: true,
        sharedLoadingMore: false,
        sharedLoadFailed: false,
        sharedHasMore: true
      });
      if (selected.tab === 3) {
        const effect: FetchSharedGroups = new FetchSharedGroups();
        return reduced(next, [effect]);
      }
      const effect: FetchSharedContent = new FetchSharedContent(selected.tab);
      return reduced(next, [effect]);
    }

    case 'loadMoreSharedContent': {
      const loadMore: LoadMoreSharedContent = intent as LoadMoreSharedContent;
      if (loadMore.tab < 0 || loadMore.tab >= SHARED_TAB_COUNT) {
        return reduced(state);
      }
      if (state.sharedLoading || state.sharedLoadingMore || !state.sharedHasMore) {
        return reduced(state);
      }
      const next: ProfileUiState = state.copyWith({ sharedLoadingMore: true });
      const effect: FetchMoreSharedContent = new FetchMoreSharedContent(loadMore.tab);
      return reduced(next, [effect]);
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

    case 'onSharedGroupsLoaded': {
      const loaded: OnSharedGroupsLoaded = intent as OnSharedGroupsLoaded;
      return reduced(state.copyWith({
        sharedGroups: loaded.items,
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

    case 'openSharedChatRequested': {
      const open: OpenSharedChatRequested = intent as OpenSharedChatRequested;
      if (open.chatId === 0) {
        return reduced(state);
      }
      const effect: OpenSharedChatEffect = new OpenSharedChatEffect(open.chatId);
      return reduced(state, [effect]);
    }

    default:
      return reduced(state);
  }
};
