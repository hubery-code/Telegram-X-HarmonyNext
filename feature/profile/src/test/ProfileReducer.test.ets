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
  LoadMoreSharedContent,
  OnSharedContentLoaded,
  OnSharedGroupsLoaded,
  OnSharedContentFailed,
  OpenSharedChatRequested,
  NotificationRowTapped,
  OnChatNotificationLoaded,
  OnChatNotificationFailed
} from '../main/ets/contract/ProfileIntent';
import {
  ProfileEffect,
  CreatePrivateChatEffect,
  FetchSharedContent,
  FetchSharedGroups,
  FetchMoreSharedContent,
  OpenSharedChatEffect,
  SetChatNotification
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
      // PROFILE-103 收尾：默认 Tab（媒体）与通知态必须在首屏回灌后真的去问 TDLib，
      // 否则页面直接显示「暂无媒体文件」和写死的「开启」是在替两个从未发出的请求撒谎。
      expect(result.effects.length).assertEqual(2);
      expect(result.effects[0].kind).assertEqual('fetchSharedContent');
      expect((result.effects[0] as FetchSharedContent).tab).assertEqual(0);
      expect(result.effects[1].kind).assertEqual('fetchChatNotification');
      expect(result.state.sharedLoading).assertTrue();
      expect(result.state.sharedInitialRequested).assertTrue();
      expect(result.state.notificationRequested).assertTrue();
      // 未回读到真值前，通知行既不许显示「开启」也不许被点成静音。
      expect(result.state.notificationReady).assertFalse();
    });

    it('notificationRowTapped_beforeReady_isNoOp', 0, () => {
      const result: ReducerResult<ProfileUiState, ProfileEffect> = profileReducer(
        makeState(42),
        new NotificationRowTapped(),
        makeEnv()
      );
      expect(result.effects.length).assertEqual(0);
      expect(result.state.notificationUpdating).assertFalse();
    });

    it('notificationRowTapped_whenReady_emitsOppositeOfReadValue', 0, () => {
      const ready: ProfileUiState = makeState(42).copyWith({
        notificationMuted: false,
        notificationReady: true
      });
      const toMute: ReducerResult<ProfileUiState, ProfileEffect> = profileReducer(
        ready, new NotificationRowTapped(), makeEnv()
      );
      expect(toMute.effects.length).assertEqual(1);
      expect(toMute.effects[0].kind).assertEqual('setChatNotification');
      expect((toMute.effects[0] as SetChatNotification).muted).assertTrue();
      expect(toMute.state.notificationUpdating).assertTrue();

      const muted: ProfileUiState = ready.copyWith({ notificationMuted: true });
      const toUnmute: ReducerResult<ProfileUiState, ProfileEffect> = profileReducer(
        muted, new NotificationRowTapped(), makeEnv()
      );
      expect((toUnmute.effects[0] as SetChatNotification).muted).assertFalse();
    });

    it('notificationRowTapped_whileUpdating_isSerialized', 0, () => {
      const busy: ProfileUiState = makeState(42).copyWith({
        notificationMuted: false,
        notificationReady: true,
        notificationUpdating: true
      });
      const result: ReducerResult<ProfileUiState, ProfileEffect> = profileReducer(
        busy, new NotificationRowTapped(), makeEnv()
      );
      // 两次点击会打出两条 setChatNotificationSettings，回灌顺序不确定 → 必须串行。
      expect(result.effects.length).assertEqual(0);
    });

    it('onChatNotificationLoaded_setsRealValueAndClearsUpdating', 0, () => {
      const busy: ProfileUiState = makeState(42).copyWith({ notificationUpdating: true });
      const result: ReducerResult<ProfileUiState, ProfileEffect> = profileReducer(
        busy, new OnChatNotificationLoaded(true), makeEnv()
      );
      expect(result.state.notificationMuted).assertTrue();
      expect(result.state.notificationReady).assertTrue();
      expect(result.state.notificationUpdating).assertFalse();
    });

    /** 读不到/写失败必须退回「未知」，继续显示上一个真值同样是撒谎。 */
    it('onChatNotificationFailed_hidesStaleValue', 0, () => {
      const shown: ProfileUiState = makeState(42).copyWith({
        notificationMuted: true,
        notificationReady: true
      });
      const result: ReducerResult<ProfileUiState, ProfileEffect> = profileReducer(
        shown, new OnChatNotificationFailed(), makeEnv()
      );
      expect(result.state.notificationReady).assertFalse();
      expect(result.state.notificationUpdating).assertFalse();
    });

    it('onProfileLoaded_secondDeliveryDoesNotRefetch', 0, () => {
      const first: ReducerResult<ProfileUiState, ProfileEffect> = profileReducer(
        makeState(42),
        new OnProfileLoaded('Test User', 'testuser', '+123456', 'online', 'TU', 3),
        makeEnv()
      );
      const second: ReducerResult<ProfileUiState, ProfileEffect> = profileReducer(
        first.state,
        new OnProfileLoaded('Test User', 'testuser', '+123456', 'last seen recently', 'TU', 3),
        makeEnv()
      );
      // 订阅会反复回灌资料，共享内容只允许拉一次。
      expect(second.effects.length).assertEqual(0);
      expect(second.state.statusText).assertEqual('last seen recently');
    });

    it('onSharedTabSelected_sameEmptyTabRefetchesAsRetry', 0, () => {
      const failed: ProfileUiState = makeState(42).copyWith({
        sharedInitialRequested: true,
        sharedLoadFailed: true,
        sharedLoading: false
      });
      const result: ReducerResult<ProfileUiState, ProfileEffect> = profileReducer(
        failed,
        new OnSharedTabSelected(0),
        makeEnv()
      );
      expect(result.effects.length).assertEqual(1);
      expect((result.effects[0] as FetchSharedContent).tab).assertEqual(0);
      expect(result.state.sharedLoading).assertTrue();
      expect(result.state.sharedLoadFailed).assertFalse();
    });

    it('onSharedTabSelected_sameLoadedTabIsNoOp', 0, () => {
      const loaded: ProfileUiState = makeState(42).copyWith({
        sharedInitialRequested: true,
        sharedMedia: [new SharedMediaItem(7, null, true)]
      });
      const result: ReducerResult<ProfileUiState, ProfileEffect> = profileReducer(
        loaded,
        new OnSharedTabSelected(0),
        makeEnv()
      );
      expect(result.state === loaded).assertTrue();
      expect(result.effects.length).assertEqual(0);
    });

    it('onSharedContentFailed_marksFailureAndStopsLoading', 0, () => {
      const state: ProfileUiState = makeState(42).copyWith({ sharedLoading: true });
      const result: ReducerResult<ProfileUiState, ProfileEffect> = profileReducer(
        state,
        new OnSharedContentFailed(0),
        makeEnv()
      );
      expect(result.state.sharedLoading).assertFalse();
      expect(result.state.sharedLoadFailed).assertTrue();
    });

    it('onSharedContentFailed_forOtherTab_isNoOp', 0, () => {
      const state: ProfileUiState = makeState(42).copyWith({ activeSharedTab: 2 });
      const result: ReducerResult<ProfileUiState, ProfileEffect> = profileReducer(
        state,
        new OnSharedContentFailed(0),
        makeEnv()
      );
      expect(result.state === state).assertTrue();
    });

    it('onSharedContentLoaded_clearsFailure', 0, () => {
      const state: ProfileUiState = makeState(42).copyWith({
        sharedLoadFailed: true,
        sharedLoading: true
      });
      const result: ReducerResult<ProfileUiState, ProfileEffect> = profileReducer(
        state,
        new OnSharedContentLoaded(0, [new SharedMediaItem(1, null, true)], [], [], false),
        makeEnv()
      );
      expect(result.state.sharedLoadFailed).assertFalse();
      expect(result.state.sharedMedia.length).assertEqual(1);
    });

    it('openSharedChatRequested_emitsOpenSharedChatEffect', 0, () => {
      const state: ProfileUiState = makeState(42);
      const result: ReducerResult<ProfileUiState, ProfileEffect> = profileReducer(
        state,
        new OpenSharedChatRequested(-1001785291444),
        makeEnv()
      );
      expect(result.effects.length).assertEqual(1);
      expect(result.effects[0].kind).assertEqual('openSharedChat');
      expect((result.effects[0] as OpenSharedChatEffect).chatId).assertEqual(-1001785291444);
    });

    it('openSharedChatRequested_withZeroChatId_isNoOp', 0, () => {
      const result: ReducerResult<ProfileUiState, ProfileEffect> = profileReducer(
        makeState(42),
        new OpenSharedChatRequested(0),
        makeEnv()
      );
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

    it('loadMoreSharedContent_emitsFetchMoreSharedContent', 0, () => {
      const state: ProfileUiState = makeState(42).copyWith({
        activeSharedTab: 1,
        sharedLoading: false,
        sharedLoadingMore: false,
        sharedHasMore: true
      });
      const result: ReducerResult<ProfileUiState, ProfileEffect> = profileReducer(
        state,
        new LoadMoreSharedContent(1),
        makeEnv()
      );
      expect(result.state.sharedLoadingMore).assertTrue();
      expect(result.effects.length).assertEqual(1);
      expect(result.effects[0].kind).assertEqual('fetchMoreSharedContent');
      const effect: FetchMoreSharedContent = result.effects[0] as FetchMoreSharedContent;
      expect(effect.tab).assertEqual(1);
    });

    it('loadMoreSharedContent_whenAlreadyLoading_isNoOp', 0, () => {
      const state: ProfileUiState = makeState(42).copyWith({
        sharedLoadingMore: true
      });
      const result: ReducerResult<ProfileUiState, ProfileEffect> = profileReducer(
        state,
        new LoadMoreSharedContent(0),
        makeEnv()
      );
      expect(result.state === state).assertTrue();
      expect(result.effects.length).assertEqual(0);
    });

    it('loadMoreSharedContent_whenNoMore_isNoOp', 0, () => {
      const state: ProfileUiState = makeState(42).copyWith({
        sharedHasMore: false
      });
      const result: ReducerResult<ProfileUiState, ProfileEffect> = profileReducer(
        state,
        new LoadMoreSharedContent(0),
        makeEnv()
      );
      expect(result.state === state).assertTrue();
      expect(result.effects.length).assertEqual(0);
    });

    it('onSharedContentLoaded_updatesHasMoreAndStopsLoadingMore', 0, () => {
      const state: ProfileUiState = makeState(42).copyWith({
        sharedLoadingMore: true,
        sharedHasMore: true
      });
      const result: ReducerResult<ProfileUiState, ProfileEffect> = profileReducer(
        state,
        new OnSharedContentLoaded(0, [], [], [], false),
        makeEnv()
      );
      expect(result.state.sharedLoadingMore).assertFalse();
      expect(result.state.sharedHasMore).assertFalse();
    });

    it('onSharedGroupsLoaded_updatesHasMoreAndStopsLoadingMore', 0, () => {
      const state: ProfileUiState = makeState(42).copyWith({
        sharedLoadingMore: true,
        sharedHasMore: true
      });
      const result: ReducerResult<ProfileUiState, ProfileEffect> = profileReducer(
        state,
        new OnSharedGroupsLoaded([], false),
        makeEnv()
      );
      expect(result.state.sharedLoadingMore).assertFalse();
      expect(result.state.sharedHasMore).assertFalse();
    });
  });
}
