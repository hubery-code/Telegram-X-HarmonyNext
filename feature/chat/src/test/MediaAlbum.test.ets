import { describe, it, expect } from '@ohos/hypium';
import { ManualClock, SequentialIdGenerator } from '@tgx/core-common';
import { ReducerEnv } from '@tgx/feature-template';
import { Message, MessagePhoto, MessageText, MessageSticker } from '@tgx/core-td-api-generated';
import { isMediaAlbumCandidate } from '../main/ets/coordinator/ChatCoordinator';
import { MediaAttachment } from '../main/ets/model/MediaAttachment';
import { MessageItem } from '../main/ets/model/MessageItem';
import { MediaViewerItem } from '../main/ets/model/MediaViewerItem';
import { ChatUiState, MessageActionMenuState } from '../main/ets/contract/ChatUiState';
import { OpenMediaViewer, DeleteMessage, ForwardSelectedToChat } from '../main/ets/contract/ChatIntent';
import { DeleteMessages, ForwardMessages } from '../main/ets/contract/ChatEffect';
import { chatReducer, buildViewerItems } from '../main/ets/reducer/ChatReducer';

function makeEnv(nowMillis: number = 1000, monotonicMillis: number = 500): ReducerEnv {
  const env: ReducerEnv = {
    clock: new ManualClock(nowMillis, monotonicMillis),
    ids: new SequentialIdGenerator('req-test-')
  };
  return env;
}

function makePhotoMsg(id: number, albumId: string, outgoing: boolean = false): Message {
  const m = new Message();
  m.id = id;
  m.chat_id = 42;
  m.is_outgoing = outgoing;
  m.date = 1700000000 + id;
  m.media_album_id = albumId;
  const content = new MessagePhoto();
  content.type = 'messagePhoto';
  m.content = content;
  return m;
}

function makePhotoAttachment(fileId: number, caption: string = ''): MediaAttachment {
  return new MediaAttachment(
    'photo',
    fileId,
    null,
    null,
    800,
    600,
    0,
    false,
    false,
    0,
    caption,
    [],
    false
  );
}

export default function mediaAlbumTest() {
  describe('MediaAlbumTest', () => {

    it('isMediaAlbumCandidate detects valid photo/video/animation album messages', 0, () => {
      const photoMsg = makePhotoMsg(1, '123456789');
      expect(isMediaAlbumCandidate(photoMsg)).assertTrue();

      const zeroAlbumMsg = makePhotoMsg(2, '0');
      expect(isMediaAlbumCandidate(zeroAlbumMsg)).assertFalse();

      const emptyAlbumMsg = makePhotoMsg(3, '');
      expect(isMediaAlbumCandidate(emptyAlbumMsg)).assertFalse();

      const textMsg = new Message();
      textMsg.id = 4;
      textMsg.media_album_id = '123456789';
      textMsg.content = new MessageText();
      expect(isMediaAlbumCandidate(textMsg)).assertFalse();

      const stickerMsg = new Message();
      stickerMsg.id = 5;
      stickerMsg.media_album_id = '123456789';
      stickerMsg.content = new MessageSticker();
      expect(isMediaAlbumCandidate(stickerMsg)).assertFalse();
    });

    it('buildViewerItems expands albumItems into separate viewer items', 0, () => {
      const p1 = makePhotoAttachment(101, 'Photo 1');
      const p2 = makePhotoAttachment(102, 'Photo 2');
      const p3 = makePhotoAttachment(103, 'Photo 3');

      const albumMsg = new MessageItem(
        200,
        'Album Caption',
        1700000000000,
        false,
        'Alice',
        'none',
        false,
        false,
        null,
        '',
        [],
        -1,
        false,
        p1,
        '',
        -1,
        null,
        false,
        false,
        '',
        false,
        null,
        [p1, p2, p3],
        [198, 199, 200]
      );

      const singleMsg = new MessageItem(
        300,
        'Single',
        1700000001000,
        true,
        'You',
        'none',
        false,
        false,
        null,
        '',
        [],
        -1,
        false,
        makePhotoAttachment(301)
      );

      const viewerItems: MediaViewerItem[] = buildViewerItems([albumMsg, singleMsg]);
      expect(viewerItems.length).assertEqual(4);
      expect(viewerItems[0].messageId).assertEqual(200);
      expect(viewerItems[0].media.fileId).assertEqual(101);
      expect(viewerItems[1].messageId).assertEqual(200);
      expect(viewerItems[1].media.fileId).assertEqual(102);
      expect(viewerItems[2].messageId).assertEqual(200);
      expect(viewerItems[2].media.fileId).assertEqual(103);
      expect(viewerItems[3].messageId).assertEqual(300);
      expect(viewerItems[3].media.fileId).assertEqual(301);
    });

    it('openMediaViewer with targetFileId locates exact item index', 0, () => {
      const p1 = makePhotoAttachment(101);
      const p2 = makePhotoAttachment(102);
      const p3 = makePhotoAttachment(103);

      const albumMsg = new MessageItem(
        200,
        'Album Caption',
        1700000000000,
        false,
        'Alice',
        'none',
        false,
        false,
        null,
        '',
        [],
        -1,
        false,
        p1,
        '',
        -1,
        null,
        false,
        false,
        '',
        false,
        null,
        [p1, p2, p3],
        [198, 199, 200]
      );

      const state = new ChatUiState(1, 'Test Chat', [albumMsg], false, false, null, '', null, null);
      const res = chatReducer(state, new OpenMediaViewer(200, 102), makeEnv());
      expect(res.state.activeViewerIndex).assertEqual(1);
      expect(res.state.viewerItems[res.state.activeViewerIndex].media.fileId).assertEqual(102);
    });

    it('deleteMessage deletes all albumMessageIds if message is an album', 0, () => {
      const p1 = makePhotoAttachment(101);
      const p2 = makePhotoAttachment(102);

      const albumMsg = new MessageItem(
        200,
        'Album',
        1700000000000,
        false,
        'Alice',
        'none',
        false,
        false,
        null,
        '',
        [],
        -1,
        false,
        p1,
        '',
        -1,
        null,
        false,
        false,
        '',
        false,
        null,
        [p1, p2],
        [199, 200]
      );

      const menu = new MessageActionMenuState(200, true, false, true, true, true);
      const state = new ChatUiState(1, 'Test Chat', [albumMsg], false, false, null, '', null, menu);

      const res = chatReducer(state, new DeleteMessage(), makeEnv());
      expect(res.effects.length).assertEqual(1);
      const delEffect = res.effects[0] as DeleteMessages;
      expect(delEffect.kind).assertEqual('deleteMessages');
      expect(delEffect.messageIds.length).assertEqual(2);
      expect(delEffect.messageIds[0]).assertEqual(199);
      expect(delEffect.messageIds[1]).assertEqual(200);
    });

    it('forwardSelectedToChat expands albumMessageIds for forwarded albums', 0, () => {
      const p1 = makePhotoAttachment(101);
      const p2 = makePhotoAttachment(102);

      const albumMsg = new MessageItem(
        200,
        'Album',
        1700000000000,
        false,
        'Alice',
        'none',
        false,
        false,
        null,
        '',
        [],
        -1,
        false,
        p1,
        '',
        -1,
        null,
        false,
        false,
        '',
        false,
        null,
        [p1, p2],
        [199, 200]
      );

      let state = new ChatUiState(1, 'Test Chat', [albumMsg], false, false, null, '', null, null);
      state = state.copyWith({
        selectionMode: true,
        selectedMessageIds: [200]
      });

      const res = chatReducer(state, new ForwardSelectedToChat(999, false), makeEnv());
      expect(res.effects.length).assertEqual(1);
      const fwdEffect = res.effects[0] as ForwardMessages;
      expect(fwdEffect.kind).assertEqual('forwardMessages');
      expect(fwdEffect.toChatId).assertEqual(999);
      expect(fwdEffect.messageIds.length).assertEqual(2);
      expect(fwdEffect.messageIds[0]).assertEqual(199);
      expect(fwdEffect.messageIds[1]).assertEqual(200);
    });

  });
}
