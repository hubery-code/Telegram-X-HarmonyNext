import { describe, it, expect } from '@ohos/hypium';
import { MediaAttachment, MediaKind } from '../main/ets/model/MediaAttachment';
import { MessageItem } from '../main/ets/model/MessageItem';
import { MessageTextSpan } from '../main/ets/model/MessageTextSpan';

export default function mediaAttachmentTest() {
  describe('MediaAttachmentTest', () => {

    it('creates photo media attachment with correct properties', 0, () => {
      const spans: MessageTextSpan[] = [new MessageTextSpan('Beautiful sunset', true)];
      const photo = new MediaAttachment(
        'photo',
        1001,
        '/data/storage/el2/base/files/photo.jpg',
        '/data/storage/el2/base/files/thumb.jpg',
        1280,
        720,
        0,
        false,
        true,
        1.0,
        'Beautiful sunset',
        spans,
        false
      );

      expect(photo.kind).assertEqual('photo');
      expect(photo.fileId).assertEqual(1001);
      expect(photo.localPath).assertEqual('/data/storage/el2/base/files/photo.jpg');
      expect(photo.thumbnailPath).assertEqual('/data/storage/el2/base/files/thumb.jpg');
      expect(photo.width).assertEqual(1280);
      expect(photo.height).assertEqual(720);
      expect(photo.isDownloaded).assertTrue();
      expect(photo.isDownloading).assertFalse();
      expect(photo.caption).assertEqual('Beautiful sunset');
      expect(photo.captionSpans.length).assertEqual(1);
    });

    it('creates animation media attachment with duration and gif tag', 0, () => {
      const anim = new MediaAttachment(
        'animation',
        2002,
        null,
        '/data/storage/el2/base/files/anim_thumb.jpg',
        400,
        400,
        5,
        true,
        false,
        0.45,
        'Funny reaction',
        [],
        false
      );

      expect(anim.kind).assertEqual('animation');
      expect(anim.duration).assertEqual(5);
      expect(anim.isDownloading).assertTrue();
      expect(anim.isDownloaded).assertFalse();
      expect(anim.progress).assertEqual(0.45);
    });

    it('creates video media attachment with thumbnail and duration', 0, () => {
      const video = new MediaAttachment(
        'video',
        3003,
        null,
        '/data/storage/el2/base/files/video_thumb.jpg',
        1920,
        1080,
        42,
        false,
        false,
        0.0,
        'Vacation video',
        [],
        false
      );

      expect(video.kind).assertEqual('video');
      expect(video.duration).assertEqual(42);
      expect(video.width).assertEqual(1920);
      expect(video.height).assertEqual(1080);
    });

    it('copyWith properly updates download state and progress', 0, () => {
      const initial = new MediaAttachment(
        'photo',
        5005,
        null,
        null,
        800,
        600,
        0,
        true,
        false,
        0.5
      );

      const downloaded = initial.copyWith(
        '/data/storage/el2/base/files/downloaded.jpg',
        '/data/storage/el2/base/files/thumb.jpg',
        false,
        true,
        1.0
      );

      expect(downloaded.fileId).assertEqual(5005);
      expect(downloaded.isDownloading).assertFalse();
      expect(downloaded.isDownloaded).assertTrue();
      expect(downloaded.localPath).assertEqual('/data/storage/el2/base/files/downloaded.jpg');
      expect(downloaded.thumbnailPath).assertEqual('/data/storage/el2/base/files/thumb.jpg');
      expect(downloaded.progress).assertEqual(1.0);
    });

    it('attaches MediaAttachment to MessageItem', 0, () => {
      const photo = new MediaAttachment('photo', 1234, '/path/to/img.jpg', null, 800, 600, 0, false, true, 1.0, 'Caption');
      const item = new MessageItem(
        100,
        'Caption',
        1700000000000,
        true,
        'Me',
        'none',
        false,
        false,
        null,
        '',
        [],
        -1,
        false,
        photo
      );

      expect(item.messageId).assertEqual(100);
      expect(item.media !== null).assertTrue();
      expect(item.media?.kind).assertEqual('photo');
      expect(item.media?.fileId).assertEqual(1234);
    });

  });
}
