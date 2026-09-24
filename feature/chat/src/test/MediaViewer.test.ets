import { describe, it, expect } from '@ohos/hypium';
import { ManualClock, SequentialIdGenerator } from '@tgx/core-common';
import { ReducerEnv, ReducerResult } from '@tgx/feature-template';
import {
  ChatUiState,
  ComposerReplyMode,
  MessageActionMenuState
} from '../main/ets/contract/ChatUiState';
import { MessageItem } from '../main/ets/model/MessageItem';
import { MediaAttachment, MediaFullSource } from '../main/ets/model/MediaAttachment';
import { MediaViewerItem, mediaViewerItemKey } from '../main/ets/model/MediaViewerItem';
import {
  OpenMediaViewer,
  CloseMediaViewer,
  ChangeViewerIndex,
  BackToChatList,
  OnMessagesLoaded
} from '../main/ets/contract/ChatIntent';
import {
  ChatEffect,
  NavigateBack
} from '../main/ets/contract/ChatEffect';
import { chatReducer, buildViewerItems } from '../main/ets/reducer/ChatReducer';

function makeEnv(): ReducerEnv {
  const env: ReducerEnv = {
    clock: new ManualClock(1000, 500),
    ids: new SequentialIdGenerator('req-test-')
  };
  return env;
}

function makePhotoMedia(fileId: number, path: string = '/path/photo.jpg'): MediaAttachment {
  return new MediaAttachment(
    'photo',
    fileId,
    path,
    '/path/thumb.jpg',
    800,
    600,
    0,
    false,
    true,
    1.0,
    'Photo caption',
    [],
    false
  );
}

function makeVideoMedia(fileId: number): MediaAttachment {
  return new MediaAttachment(
    'video',
    fileId,
    '/path/video.mp4',
    '/path/video_thumb.jpg',
    1920,
    1080,
    30,
    false,
    true,
    1.0,
    '',
    [],
    false
  );
}

function makeMediaMessage(messageId: number, isOutgoing: boolean, media: MediaAttachment, senderName: string = 'Alice'): MessageItem {
  return new MessageItem(
    messageId,
    '[Media]',
    1000 + messageId,
    isOutgoing,
    senderName,
    'none',
    false,
    false,
    null,
    '',
    [],
    0,
    false,
    media
  );
}

function makeTextMessage(messageId: number, text: string = 'hello'): MessageItem {
  return new MessageItem(
    messageId,
    text,
    1000 + messageId,
    false,
    'Bob',
    'none',
    true,
    false,
    null,
    ''
  );
}

export default function mediaViewerTest() {
  describe('MediaViewerTest', () => {

    it('buildViewerItems_extractsMediaItems_andSkipsPlainTextMessage', 0, () => {
      const p1 = makeMediaMessage(101, true, makePhotoMedia(1), '');
      const t1 = makeTextMessage(102, 'plain text');
      const v1 = makeMediaMessage(103, false, makeVideoMedia(2), 'Alice');

      const viewerItems = buildViewerItems([p1, t1, v1]);
      expect(viewerItems.length).assertEqual(2);
      expect(viewerItems[0].messageId).assertEqual(101);
      expect(viewerItems[0].senderName).assertEqual('You');
      expect(viewerItems[1].messageId).assertEqual(103);
      expect(viewerItems[1].senderName).assertEqual('Alice');
    });

    it('openMediaViewer_setsActiveViewerIndex_andPopulatesViewerItems', 0, () => {
      const p1 = makeMediaMessage(101, false, makePhotoMedia(1), 'Bob');
      const p2 = makeMediaMessage(102, true, makePhotoMedia(2), '');
      const state = new ChatUiState(1, 'Test Chat', [p1, p2], false, false, null, '', null, null);

      const result: ReducerResult<ChatUiState, ChatEffect> =
        chatReducer(state, new OpenMediaViewer(102), makeEnv());

      expect(result.state.activeViewerIndex).assertEqual(1);
      expect(result.state.viewerItems.length).assertEqual(2);
      expect(result.state.viewerItems[1].messageId).assertEqual(102);
      expect(result.effects.length).assertEqual(0);
    });

    it('openMediaViewer_unknownMessageId_isNoOp', 0, () => {
      const p1 = makeMediaMessage(101, false, makePhotoMedia(1));
      const state = new ChatUiState(1, 'Test Chat', [p1], false, false, null, '', null, null);

      const result: ReducerResult<ChatUiState, ChatEffect> =
        chatReducer(state, new OpenMediaViewer(999), makeEnv());

      expect(result.state.activeViewerIndex).assertEqual(-1);
    });

    it('closeMediaViewer_resetsActiveViewerIndexToMinusOne', 0, () => {
      const p1 = makeMediaMessage(101, false, makePhotoMedia(1));
      const viewerItem = new MediaViewerItem(101, 'Bob', 1000, p1.media!);
      const state = new ChatUiState(1, 'Test Chat', [p1], false, false, null, '', null, null, 0, [viewerItem]);

      const result: ReducerResult<ChatUiState, ChatEffect> =
        chatReducer(state, new CloseMediaViewer(), makeEnv());

      expect(result.state.activeViewerIndex).assertEqual(-1);
      expect(result.state.viewerItems.length).assertEqual(1);
    });

    it('changeViewerIndex_updatesValidIndex_andIgnoresInvalid', 0, () => {
      const p1 = makeMediaMessage(101, false, makePhotoMedia(1));
      const p2 = makeMediaMessage(102, false, makePhotoMedia(2));
      const viewerItems = buildViewerItems([p1, p2]);
      const state = new ChatUiState(1, 'Test Chat', [p1, p2], false, false, null, '', null, null, 0, viewerItems);

      const validResult: ReducerResult<ChatUiState, ChatEffect> =
        chatReducer(state, new ChangeViewerIndex(1), makeEnv());
      expect(validResult.state.activeViewerIndex).assertEqual(1);

      const invalidResult: ReducerResult<ChatUiState, ChatEffect> =
        chatReducer(state, new ChangeViewerIndex(5), makeEnv());
      expect(invalidResult.state.activeViewerIndex).assertEqual(0);
    });

    it('backToChatList_closesViewerFirst_withoutEmittingNavigateBack', 0, () => {
      const p1 = makeMediaMessage(101, false, makePhotoMedia(1));
      const viewerItems = buildViewerItems([p1]);
      const state = new ChatUiState(1, 'Test Chat', [p1], false, false, null, '', null, null, 0, viewerItems);

      const result: ReducerResult<ChatUiState, ChatEffect> =
        chatReducer(state, new BackToChatList(), makeEnv());

      expect(result.state.activeViewerIndex).assertEqual(-1);
      expect(result.effects.length).assertEqual(0);
    });

    it('backToChatList_closesActionMenuSecond_withoutEmittingNavigateBack', 0, () => {
      const menu = new MessageActionMenuState(101, true, true, true, false);
      const state = new ChatUiState(1, 'Test Chat', [], false, false, null, '', null, menu, -1, []);

      const result: ReducerResult<ChatUiState, ChatEffect> =
        chatReducer(state, new BackToChatList(), makeEnv());

      expect(result.state.actionMenu).assertNull();
      expect(result.effects.length).assertEqual(0);
    });

    it('backToChatList_cancelsComposerModeThird_withoutEmittingNavigateBack', 0, () => {
      const mode = new ComposerReplyMode(101, 'Alice', 'snippet');
      const state = new ChatUiState(1, 'Test Chat', [], false, false, null, '', mode, null, -1, []);

      const result: ReducerResult<ChatUiState, ChatEffect> =
        chatReducer(state, new BackToChatList(), makeEnv());

      expect(result.state.composerMode).assertNull();
      expect(result.effects.length).assertEqual(0);
    });

    it('backToChatList_whenNothingActive_emitsNavigateBack', 0, () => {
      const state = new ChatUiState(1, 'Test Chat', [], false, false, null, '', null, null, -1, []);

      const result: ReducerResult<ChatUiState, ChatEffect> =
        chatReducer(state, new BackToChatList(), makeEnv());

      expect(result.effects.length).assertEqual(1);
      expect(result.effects[0].kind).assertEqual('navigateBack');
    });

    it('onMessagesLoaded_updatesViewerItems_andClampsActiveIndex', 0, () => {
      const p1 = makeMediaMessage(101, false, makePhotoMedia(1));
      const p2 = makeMediaMessage(102, false, makePhotoMedia(2));
      const state = new ChatUiState(1, 'Test Chat', [p1, p2], false, false, null, '', null, null, 1, buildViewerItems([p1, p2]));

      // New messages only has p1 (p2 was deleted)
      const result: ReducerResult<ChatUiState, ChatEffect> =
        chatReducer(state, new OnMessagesLoaded([p1], false), makeEnv());

      expect(result.state.viewerItems.length).assertEqual(1);
      expect(result.state.activeViewerIndex).assertEqual(0); // clamped from 1 to 0
    });

    // ---- MEDIA-VIEWER-101：画廊项 key（大图档换源与相册同 id 兄弟项）----

    it('itemKey_separatesAlbumSiblingsSharingMessageId', 0, () => {
      const a: MediaViewerItem = new MediaViewerItem(101, 'Bob', 1000, makePhotoMedia(1));
      const b: MediaViewerItem = new MediaViewerItem(101, 'Bob', 1000, makePhotoMedia(2));
      expect(mediaViewerItemKey(a, false) === mediaViewerItemKey(b, false)).assertFalse();
    });

    it('itemKey_changesWhenFullTierLands', 0, () => {
      const pending: MediaAttachment = makePhotoMedia(1)
        .withFullSource(new MediaFullSource(9, 4000, 3000));
      const ready: MediaAttachment = makePhotoMedia(1)
        .withFullSource(new MediaFullSource(9, 4000, 3000, '/path/photo-full.jpg', true));
      const k1: string = mediaViewerItemKey(new MediaViewerItem(101, 'Bob', 1000, pending), false);
      const k2: string = mediaViewerItemKey(new MediaViewerItem(101, 'Bob', 1000, ready), false);
      expect(k1 === k2).assertFalse();
    });

    it('itemKey_isStableForIdenticalRenderedState', 0, () => {
      const k1: string = mediaViewerItemKey(new MediaViewerItem(101, 'Bob', 1000, makePhotoMedia(1)), false);
      const k2: string = mediaViewerItemKey(new MediaViewerItem(101, 'Bob', 1000, makePhotoMedia(1)), false);
      expect(k1).assertEqual(k2);
    });

    // ---- MEDIA-VIEWER-102：播放器归属位进键（翻页必须让上一页的 Video 节点重建消失）----

    it('itemKey_playerBitChangesOnActivation', 0, () => {
      const video: MediaViewerItem = new MediaViewerItem(201, 'Bob', 1000, makeVideoMedia(5));
      expect(mediaViewerItemKey(video, true) === mediaViewerItemKey(video, false)).assertFalse();
    });

    it('itemKey_photoIgnoresActivationBit', 0, () => {
      // 照片页不因为翻页白白重建（重建就是重新解码，会闪）。
      const photo: MediaViewerItem = new MediaViewerItem(202, 'Bob', 1000, makePhotoMedia(6));
      expect(mediaViewerItemKey(photo, true)).assertEqual(mediaViewerItemKey(photo, false));
    });
  });
}
