/**
 * feature/profile — 共享媒体「不丢条目」单元测试（PROFILE-103 收尾缺陷）。
 *
 * 守住的行为：媒体 Tab 的每一条照片/视频消息都必须在网格里出现一座。
 * 真机证据曾暴露：分页第二页回了 2 条消息，因为缩略图 size 尚未缓存
 * （`photo.sizes` 为空 / video 无 cover 无 thumbnail），旧映射直接返回 null，
 * 条目被静默丢掉 → 网格永远少格子，且翻页回来的数据无法复现。
 * 现在必须落成占位条目（fileId=0, localPath=null），由共享内容分区组件的占位瓦片渲染。
 */

import { describe, it, expect } from '@ohos/hypium';
import { AccountScope } from '@tgx/core-account';
import { TdWireValue } from '@tgx/td-gateway';
import { ProfileCoordinator } from '../main/ets/coordinator/ProfileCoordinator';
import { OnProfileLoaded, LoadMoreSharedContent } from '../main/ets/contract/ProfileIntent';
import { SharedMediaItem } from '../main/ets/contract/SharedContentItems';
import {
  TestNativeBridge,
  createScope,
  foundMessages,
  photoMessage,
  photoSizeValue,
  privateChatResponse,
  settle,
  videoMessageWithoutThumb
} from './ProfileTestHarness';

/** 走完「首屏 → createPrivateChat → searchChatMessages」链路，喂入给定的一页消息。 */
async function openWithPage(
  bridge: TestNativeBridge,
  messages: Record<string, TdWireValue>[],
  nextFromId: number
): Promise<ProfileCoordinator> {
  const scope: AccountScope = createScope(bridge, 'test_shared_media_placeholder');
  const coordinator: ProfileCoordinator = new ProfileCoordinator(scope, 4242);
  coordinator.dispatch(new OnProfileLoaded('Peer', '', '', '', 'P', 0));

  const createId: string = bridge.lastRequestIdOf('createPrivateChat');
  expect(createId.length > 0).assertTrue();
  bridge.respondTo(createId, privateChatResponse(4242));
  await settle();

  const searchId: string = bridge.lastRequestIdOf('searchChatMessages');
  expect(searchId.length > 0).assertTrue();
  bridge.respondTo(searchId, foundMessages(messages, nextFromId));
  await settle();
  return coordinator;
}

function expectPlaceholder(item: SharedMediaItem, isPhoto: boolean): void {
  expect(item.fileId).assertEqual(0);
  expect(item.localPath === null).assertTrue();
  expect(item.isPhoto).assertEqual(isPhoto);
}

export default function sharedMediaPlaceholderTest(): void {
  describe('SharedMediaPlaceholderTest', () => {

    it('photoWithoutCachedSizes_keepsPlaceholderTile', 0, async (): Promise<void> => {
      const bridge: TestNativeBridge = new TestNativeBridge();
      const coordinator: ProfileCoordinator = await openWithPage(
        bridge, [photoMessage(101, [])], 0);

      // sizes 未缓存时也必须留下一座占位瓦片，不能静默丢消息。
      expect(coordinator.state.sharedMedia.length).assertEqual(1);
      expectPlaceholder(coordinator.state.sharedMedia[0], true);
      coordinator.destroy();
    });

    it('videoWithoutCoverOrThumbnail_keepsPlaceholderTile', 0, async (): Promise<void> => {
      const bridge: TestNativeBridge = new TestNativeBridge();
      const coordinator: ProfileCoordinator = await openWithPage(
        bridge, [videoMessageWithoutThumb(202)], 0);

      expect(coordinator.state.sharedMedia.length).assertEqual(1);
      expectPlaceholder(coordinator.state.sharedMedia[0], false);
      coordinator.destroy();
    });

    it('loadMorePageWithUnresolvedThumbs_appendsPlaceholders', 0, async (): Promise<void> => {
      const bridge: TestNativeBridge = new TestNativeBridge();
      const firstSize: Record<string, TdWireValue>[] = [photoSizeValue(9001, 640)];
      const coordinator: ProfileCoordinator = await openWithPage(
        bridge, [photoMessage(303, firstSize)], 58720256);

      expect(coordinator.state.sharedMedia.length).assertEqual(1);
      expect(coordinator.state.sharedMedia[0].fileId).assertEqual(9001);
      expect(coordinator.state.sharedHasMore).assertTrue();

      coordinator.dispatch(new LoadMoreSharedContent(0));
      const searchId: string = bridge.lastRequestIdOf('searchChatMessages');
      expect(searchId.length > 0).assertTrue();
      // 第二页：一条缩略图未缓存的照片 + 一条无封面的视频。
      bridge.respondTo(searchId, foundMessages([photoMessage(404, []), videoMessageWithoutThumb(505)], 0));
      await settle();

      expect(coordinator.state.sharedMedia.length).assertEqual(3);
      expectPlaceholder(coordinator.state.sharedMedia[1], true);
      expectPlaceholder(coordinator.state.sharedMedia[2], false);
      expect(coordinator.state.sharedHasMore).assertFalse();
      coordinator.destroy();
    });
  });
}
