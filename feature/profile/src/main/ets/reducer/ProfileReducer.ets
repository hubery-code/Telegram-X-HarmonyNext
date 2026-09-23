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
  ProfileIntent
} from '../contract/ProfileIntent';
import {
  CreatePrivateChatEffect,
  FetchSharedContent,
  FetchSharedGroups,
  FetchMoreSharedContent,
  ProfileEffect
} from '../contract/ProfileEffect';

/** 共享内容 Tab 数（媒体/文件/链接/群组）。 */
const SHARED_TAB_COUNT: number = 4;

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
      return reduced(state.copyWith({
        displayName: loaded.displayName,
        username: loaded.username,
        phone: loaded.phone,
        statusText: loaded.statusText,
        avatarLetters: loaded.avatarLetters,
        avatarColorIndex: loaded.avatarColorIndex,
        isLoading: false,
        errorMessage: null
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
      if (selected.tab === state.activeSharedTab) {
        return reduced(state);
      }
      // 「未加载过」以该 Tab 条目非空判定（空结果会在下次进入时重试）。
      let alreadyLoaded: boolean = false;
      if (selected.tab === 0) {
        alreadyLoaded = state.sharedMedia.length > 0;
      } else if (selected.tab === 1) {
        alreadyLoaded = state.sharedFiles.length > 0;
      } else if (selected.tab === 2) {
        alreadyLoaded = state.sharedLinks.length > 0;
      } else {
        alreadyLoaded = state.sharedGroups.length > 0;
      }
      if (alreadyLoaded) {
        // 已加载：仅切 Tab，不触发请求也不转圈。
        return reduced(state.copyWith({
          activeSharedTab: selected.tab,
          sharedLoading: false,
          sharedLoadingMore: false,
          sharedHasMore: true
        }));
      }
      const next: ProfileUiState = state.copyWith({
        activeSharedTab: selected.tab,
        sharedLoading: true,
        sharedLoadingMore: false,
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
        sharedHasMore: loaded.hasMore
      }));
    }

    case 'onSharedGroupsLoaded': {
      const loaded: OnSharedGroupsLoaded = intent as OnSharedGroupsLoaded;
      return reduced(state.copyWith({
        sharedGroups: loaded.items,
        sharedLoading: false,
        sharedLoadingMore: false,
        sharedHasMore: loaded.hasMore
      }));
    }

    default:
      return reduced(state);
  }
};
