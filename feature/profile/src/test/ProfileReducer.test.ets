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
  OnProfileFailed,
  OnBirthdayLoaded,
  OnSharedTabSelected,
  OnSharedContentLoaded,
  OnSharedGroupsLoaded
} from '../main/ets/contract/ProfileIntent';
import {
  ProfileEffect,
  CreatePrivateChatEffect,
  FetchSharedContent,
  FetchSharedGroups
} from '../main/ets/contract/ProfileEffect';
import {
  SharedMediaItem,
  SharedFileItem,
  SharedLinkItem,
  SharedGroupItem
} from '../main/ets/contract/SharedContentItems';
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

    it('onBirthdayLoaded_updatesBirthdayText', 0, () => {
      const state: ProfileUiState = makeState(42);
      const result: ReducerResult<ProfileUiState, ProfileEffect> = profileReducer(
        state,
        new OnBirthdayLoaded('1990年5月20日 (34 岁)'),
        makeEnv()
      );
      expect(result.state.birthdayText).assertEqual('1990年5月20日 (34 岁)');
      expect(result.effects.length).assertEqual(0);
    });

    it('onSharedTabSelected_switchesTabAndEmitsFetchSharedContent', 0, () => {
      const state: ProfileUiState = makeState(42);
      const result: ReducerResult<ProfileUiState, ProfileEffect> = profileReducer(
        state,
        new OnSharedTabSelected(1),
        makeEnv()
      );
      expect(result.state.activeSharedTab).assertEqual(1);
      expect(result.state.sharedLoading).assertTrue();
      expect(result.effects.length).assertEqual(1);
      expect(result.effects[0].kind).assertEqual('fetchSharedContent');
      const effect: FetchSharedContent = result.effects[0] as FetchSharedContent;
      expect(effect.tab).assertEqual(1);
    });

    it('onSharedTabSelected_groupsTabEmitsFetchSharedGroups', 0, () => {
      const state: ProfileUiState = makeState(42);
      const result: ReducerResult<ProfileUiState, ProfileEffect> = profileReducer(
        state,
        new OnSharedTabSelected(3),
        makeEnv()
      );
      expect(result.state.activeSharedTab).assertEqual(3);
      expect(result.state.sharedLoading).assertTrue();
      expect(result.effects.length).assertEqual(1);
      expect(result.effects[0].kind).assertEqual('fetchSharedGroups');
      const effect: FetchSharedGroups = result.effects[0] as FetchSharedGroups;
      expect(effect !== null).assertTrue();
    });

    it('onSharedTabSelected_alreadyLoadedTabEmitsNoEffect', 0, () => {
      const loaded: ProfileUiState = makeState(42).copyWith({
        sharedFiles: [new SharedFileItem('a.pdf', '1.0 MB', '12.05', null)]
      });
      const result: ReducerResult<ProfileUiState, ProfileEffect> = profileReducer(
        loaded,
        new OnSharedTabSelected(1),
        makeEnv()
      );
      expect(result.state.activeSharedTab).assertEqual(1);
      expect(result.state.sharedLoading).assertFalse();
      expect(result.effects.length).assertEqual(0);
    });

    it('onSharedTabSelected_sameTabIsNoOp', 0, () => {
      const state: ProfileUiState = makeState(42);
      const result: ReducerResult<ProfileUiState, ProfileEffect> = profileReducer(
        state,
        new OnSharedTabSelected(0),
        makeEnv()
      );
      expect(result.state === state).assertTrue();
      expect(result.effects.length).assertEqual(0);
    });

    it('onSharedTabSelected_invalidTabIsNoOp', 0, () => {
      const state: ProfileUiState = makeState(42);
      const result: ReducerResult<ProfileUiState, ProfileEffect> = profileReducer(
        state,
        new OnSharedTabSelected(4),
        makeEnv()
      );
      expect(result.state === state).assertTrue();
      expect(result.effects.length).assertEqual(0);
    });

    it('onSharedContentLoaded_replacesArraysAndStopsSharedLoading', 0, () => {
      const loading: ProfileUiState = makeState(42).copyWith({ activeSharedTab: 0, sharedLoading: true });
      const media: SharedMediaItem[] = [new SharedMediaItem(7, '/data/photo.jpg', true)];
      const files: SharedFileItem[] = [new SharedFileItem('a.pdf', '1.0 MB', '12.05', null)];
      const links: SharedLinkItem[] = [new SharedLinkItem('https://example.com', 'Example', 'desc')];
      const result: ReducerResult<ProfileUiState, ProfileEffect> = profileReducer(
        loading,
        new OnSharedContentLoaded(0, media, files, links),
        makeEnv()
      );
      expect(result.state.sharedMedia.length).assertEqual(1);
      expect(result.state.sharedMedia[0].fileId).assertEqual(7);
      expect(result.state.sharedFiles.length).assertEqual(1);
      expect(result.state.sharedLinks.length).assertEqual(1);
      expect(result.state.sharedLoading).assertFalse();
      expect(result.effects.length).assertEqual(0);
    });

    it('onSharedContentLoaded_keepsGroupsUntouched', 0, () => {
      const groups: SharedGroupItem[] = [new SharedGroupItem(99, 'Group', 'subtitle')];
      const loading: ProfileUiState = makeState(42).copyWith({
        activeSharedTab: 2,
        sharedLoading: true,
        sharedGroups: groups
      });
      const result: ReducerResult<ProfileUiState, ProfileEffect> = profileReducer(
        loading,
        new OnSharedContentLoaded(2, [], [], [new SharedLinkItem('https://a.b', '', '')]),
        makeEnv()
      );
      expect(result.state.sharedLinks.length).assertEqual(1);
      expect(result.state.sharedGroups.length).assertEqual(1);
      expect(result.state.sharedGroups[0].chatId).assertEqual(99);
      expect(result.state.sharedLoading).assertFalse();
    });

    it('onSharedGroupsLoaded_replacesGroupsAndStopsSharedLoading', 0, () => {
      const loading: ProfileUiState = makeState(42).copyWith({ activeSharedTab: 3, sharedLoading: true });
      const items: SharedGroupItem[] = [
        new SharedGroupItem(1, 'Group A', 'hello'),
        new SharedGroupItem(2, 'Group B', '群组')
      ];
      const result: ReducerResult<ProfileUiState, ProfileEffect> = profileReducer(
        loading,
        new OnSharedGroupsLoaded(items),
        makeEnv()
      );
      expect(result.state.sharedGroups.length).assertEqual(2);
      expect(result.state.sharedGroups[1].title).assertEqual('Group B');
      expect(result.state.sharedLoading).assertFalse();
      expect(result.effects.length).assertEqual(0);
    });
  });
}
