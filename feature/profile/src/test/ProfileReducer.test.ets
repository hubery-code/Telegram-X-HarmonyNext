/**
 * feature/profile — ProfileReducer 单元测试（PROFILE-101）。
 */

import { describe, it, expect } from '@ohos/hypium';
import { ManualClock, SequentialIdGenerator, AppErrors } from '@tgx/core-common';
import { ReducerEnv, ReducerResult } from '@tgx/feature-template';
import { ProfileUiState } from '../main/ets/contract/ProfileUiState';
import {
  ProfileIntent,
  MessageUserRequested,
  OnProfileLoaded,
  OnBioLoaded,
  OnAvatarFileLoaded,
  OnProfileFailed
} from '../main/ets/contract/ProfileIntent';
import { ProfileEffect, CreatePrivateChatEffect } from '../main/ets/contract/ProfileEffect';
import { profileReducer } from '../main/ets/reducer/ProfileReducer';

function makeEnv(): ReducerEnv {
  return {
    clock: new ManualClock(1000, 500),
    ids: new SequentialIdGenerator('test-')
  };
}

function makeState(userId: number = 42): ProfileUiState {
  return ProfileUiState.initial(userId);
}

export default function profileReducerTest(): void {
  describe('ProfileReducerTest', () => {

    it('messageUserRequested_emitsCreatePrivateChat', 0, () => {
      const state: ProfileUiState = makeState(42);
      const result: ReducerResult<ProfileUiState, ProfileEffect> = profileReducer(
        state,
        new MessageUserRequested(),
        makeEnv()
      );

      expect(result.effects.length).assertEqual(1);
      expect(result.effects[0].kind).assertEqual('createPrivateChat');
      const effect: CreatePrivateChatEffect = result.effects[0] as CreatePrivateChatEffect;
      expect(effect.userId).assertEqual(42);
      expect(result.state === state).assertTrue();
    });

    it('messageUserRequested_withInvalidUserId_isNoOp', 0, () => {
      const state: ProfileUiState = makeState(0);
      const result: ReducerResult<ProfileUiState, ProfileEffect> = profileReducer(
        state,
        new MessageUserRequested(),
        makeEnv()
      );
      expect(result.effects.length).assertEqual(0);
    });

    it('onProfileLoaded_populatesFieldsAndStopsLoading', 0, () => {
      const state: ProfileUiState = makeState(42);
      const result: ReducerResult<ProfileUiState, ProfileEffect> = profileReducer(
        state,
        new OnProfileLoaded('Test User', 'testuser', '+123456', 'online', 'TU', 3),
        makeEnv()
      );

      expect(result.state.isLoading).assertFalse();
      expect(result.state.displayName).assertEqual('Test User');
      expect(result.state.username).assertEqual('testuser');
      expect(result.state.phone).assertEqual('+123456');
      expect(result.state.statusText).assertEqual('online');
      expect(result.state.avatarLetters).assertEqual('TU');
      expect(result.state.avatarColorIndex).assertEqual(3);
      expect(result.effects.length).assertEqual(0);
    });

    it('onBioLoaded_updatesBioOnly', 0, () => {
      const loaded: ProfileUiState = makeState(42).copyWith({ isLoading: false, displayName: 'N' });
      const result: ReducerResult<ProfileUiState, ProfileEffect> = profileReducer(
        loaded,
        new OnBioLoaded('hello bio'),
        makeEnv()
      );
      expect(result.state.bio).assertEqual('hello bio');
      expect(result.state.displayName).assertEqual('N');
    });

    it('onAvatarFileLoaded_updatesAvatarPath', 0, () => {
      const loaded: ProfileUiState = makeState(42).copyWith({ isLoading: false });
      const result: ReducerResult<ProfileUiState, ProfileEffect> = profileReducer(
        loaded,
        new OnAvatarFileLoaded('/data/avatar.jpg'),
        makeEnv()
      );
      expect(result.state.avatarPath).assertEqual('/data/avatar.jpg');
    });

    it('onProfileFailed_setsErrorAndStopsLoading', 0, () => {
      const state: ProfileUiState = makeState(42);
      const result: ReducerResult<ProfileUiState, ProfileEffect> = profileReducer(
        state,
        new OnProfileFailed(AppErrors.network('dns', 'dns failed', true)),
        makeEnv()
      );
      expect(result.state.isLoading).assertFalse();
      expect(result.state.errorMessage !== null).assertTrue();
    });
  });
}
