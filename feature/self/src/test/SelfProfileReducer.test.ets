/**
 * feature/self — SelfProfileReducer 单元测试（SELF-101）。
 */

import { describe, it, expect } from '@ohos/hypium';
import { ManualClock, SequentialIdGenerator, AppErrors } from '@tgx/core-common';
import { ReducerEnv, ReducerResult } from '@tgx/feature-template';
import { SelfProfileUiState } from '../main/ets/contract/SelfProfileUiState';
import {
  OnProfileLoaded,
  OnAvatarFileLoaded,
  OnProfileFailed,
  EditTapped,
  SettingsSectionTapped
} from '../main/ets/contract/SelfProfileIntent';
import { SelfProfileEffect } from '../main/ets/contract/SelfProfileEffect';
import { selfProfileReducer } from '../main/ets/reducer/SelfProfileReducer';

function makeEnv(): ReducerEnv {
  return {
    clock: new ManualClock(1000, 500),
    ids: new SequentialIdGenerator('test-')
  };
}

function makeState(): SelfProfileUiState {
  return SelfProfileUiState.initial();
}

export default function selfProfileReducerTest(): void {
  describe('SelfProfileReducerTest', () => {

    it('onProfileLoaded_populatesFieldsAndStopsLoading', 0, () => {
      const state: SelfProfileUiState = makeState();
      const result: ReducerResult<SelfProfileUiState, SelfProfileEffect> = selfProfileReducer(
        state,
        new OnProfileLoaded('Test User', 'testuser', '+123456', '1990年1月2日 (35 岁)', 'hello bio', '在线', 'TU', 3),
        makeEnv()
      );

      expect(result.state.isLoading).assertFalse();
      expect(result.state.displayName).assertEqual('Test User');
      expect(result.state.username).assertEqual('testuser');
      expect(result.state.phone).assertEqual('+123456');
      expect(result.state.birthdayText).assertEqual('1990年1月2日 (35 岁)');
      expect(result.state.bio).assertEqual('hello bio');
      expect(result.state.statusText).assertEqual('在线');
      expect(result.state.avatarLetters).assertEqual('TU');
      expect(result.state.avatarColorIndex).assertEqual(3);
      expect(result.effects.length).assertEqual(0);
    });

    it('onAvatarFileLoaded_updatesAvatarPath', 0, () => {
      const loaded: SelfProfileUiState = makeState().copyWith({ isLoading: false, displayName: 'N' });
      const result: ReducerResult<SelfProfileUiState, SelfProfileEffect> = selfProfileReducer(
        loaded,
        new OnAvatarFileLoaded('/data/avatar.jpg'),
        makeEnv()
      );
      expect(result.state.avatarPath).assertEqual('/data/avatar.jpg');
      expect(result.state.displayName).assertEqual('N');
    });

    it('onProfileFailed_setsErrorAndStopsLoading', 0, () => {
      const state: SelfProfileUiState = makeState();
      const result: ReducerResult<SelfProfileUiState, SelfProfileEffect> = selfProfileReducer(
        state,
        new OnProfileFailed(AppErrors.network('dns', 'dns failed', true)),
        makeEnv()
      );
      expect(result.state.isLoading).assertFalse();
      expect(result.state.errorMessage !== null).assertTrue();
    });

    it('editTapped_isNoOp', 0, () => {
      const state: SelfProfileUiState = makeState().copyWith({ isLoading: false, displayName: 'N' });
      const result: ReducerResult<SelfProfileUiState, SelfProfileEffect> = selfProfileReducer(
        state,
        new EditTapped(),
        makeEnv()
      );
      expect(result.state === state).assertTrue();
      expect(result.effects.length).assertEqual(0);
    });

    it('settingsSectionTapped_eachSection_isNoOp', 0, () => {
      const sections: string[] = ['devices', 'notifications', 'data_and_storage', 'privacy_and_security'];
      for (let i = 0; i < sections.length; i++) {
        const state: SelfProfileUiState = makeState().copyWith({ isLoading: false, displayName: 'N' });
        const result: ReducerResult<SelfProfileUiState, SelfProfileEffect> = selfProfileReducer(
          state,
          new SettingsSectionTapped(sections[i]),
          makeEnv()
        );
        expect(result.state === state).assertTrue();
        expect(result.effects.length).assertEqual(0);
      }
    });
  });
}
