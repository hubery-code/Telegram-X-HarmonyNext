/**
 * feature/self — 我的资料页纯 reducer（SELF-101）。
 *
 * 与 ProfileReducer 同约定：未知 kind 走尾部 default 原样返回；
 * EditTapped / SettingsSectionTapped 是占位动作（协调器仅 log），
 * 不产生状态变更与效应；资料获取由协调器 start() 直接驱动，
 * reducer 只负责状态回灌。
 */

import { Reducer, ReducerEnv, ReducerResult, reduced } from '@tgx/feature-template';
import { SelfProfileUiState } from '../contract/SelfProfileUiState';
import {
  OnProfileLoaded,
  OnAvatarFileLoaded,
  OnProfileFailed,
  SelfProfileIntent
} from '../contract/SelfProfileIntent';
import { SelfProfileEffect } from '../contract/SelfProfileEffect';

export const selfProfileReducer: Reducer<SelfProfileUiState, SelfProfileIntent, SelfProfileEffect> = (
  state: SelfProfileUiState,
  intent: SelfProfileIntent,
  _env: ReducerEnv
): ReducerResult<SelfProfileUiState, SelfProfileEffect> => {
  switch (intent.kind) {
    case 'onProfileLoaded': {
      const loaded: OnProfileLoaded = intent as OnProfileLoaded;
      return reduced(state.copyWith({
        displayName: loaded.displayName,
        username: loaded.username,
        phone: loaded.phone,
        birthdayText: loaded.birthdayText,
        bio: loaded.bio,
        statusText: loaded.statusText,
        avatarLetters: loaded.avatarLetters,
        avatarColorIndex: loaded.avatarColorIndex,
        isLoading: false,
        errorMessage: null
      }));
    }

    case 'onAvatarFileLoaded': {
      const avatar: OnAvatarFileLoaded = intent as OnAvatarFileLoaded;
      return reduced(state.copyWith({ avatarPath: avatar.path }));
    }

    case 'onProfileFailed': {
      const failed: OnProfileFailed = intent as OnProfileFailed;
      return reduced(state.copyWith({ isLoading: false, errorMessage: failed.error.message }));
    }

    case 'editTapped':
    case 'settingsSectionTapped':
      // 占位动作：SELF-101 由协调器打日志，无状态变更。
      return reduced(state);

    default:
      return reduced(state);
  }
};
