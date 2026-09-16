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
  OnAvatarFileLoaded,
  OnProfileFailed,
  ProfileIntent
} from '../contract/ProfileIntent';
import { CreatePrivateChatEffect, ProfileEffect } from '../contract/ProfileEffect';

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

    case 'onAvatarFileLoaded': {
      const avatar: OnAvatarFileLoaded = intent as OnAvatarFileLoaded;
      return reduced(state.copyWith({ avatarPath: avatar.path }));
    }

    case 'onProfileFailed': {
      const failed: OnProfileFailed = intent as OnProfileFailed;
      return reduced(state.copyWith({ isLoading: false, errorMessage: failed.error.message }));
    }

    default:
      return reduced(state);
  }
};
