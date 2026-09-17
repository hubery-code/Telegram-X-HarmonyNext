import { describe, it, expect } from '@ohos/hypium';
import { MediaAttachment, MediaKind, formatFileSize, decodeWaveform, normalizeWaveform } from '../main/ets/model/MediaAttachment';
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

    it('creates sticker media attachment with emoji and dimensions', 0, () => {
      const sticker = new MediaAttachment(
        'sticker',
        4004,
        '/data/storage/el2/base/files/sticker.webp',
        '/data/storage/el2/base/files/sticker_thumb.jpg',
        512,
        512,
        0,
        false,
        true,
        1.0,
        '👍',
        [],
        false
      );

      expect(sticker.kind).assertEqual('sticker');
      expect(sticker.fileId).assertEqual(4004);
      expect(sticker.caption).assertEqual('👍');
      expect(sticker.width).assertEqual(512);
      expect(sticker.height).assertEqual(512);
      expect(sticker.isDownloaded).assertTrue();
    });

    it('creates photo media attachment with uploading state and progress', 0, () => {
      const photo = new MediaAttachment(
        'photo',
        6001,
        '/data/local/photo.jpg',
        null,
        1000,
        800,
        0,
        false,
        false,
        0.0,
        'Uploading...',
        [],
        false,
        true,
        0.65
      );

      expect(photo.kind).assertEqual('photo');
      expect(photo.isUploading).assertTrue();
      expect(photo.uploadProgress).assertEqual(0.65);
      expect(photo.isDownloaded).assertFalse();

      const uploaded = photo.copyWith(
        photo.localPath,
        photo.thumbnailPath,
        false,
        true,
        1.0,
        false,
        1.0
      );
      expect(uploaded.isUploading).assertFalse();
      expect(uploaded.isDownloaded).assertTrue();
      expect(uploaded.uploadProgress).assertEqual(1.0);
    });

    it('creates document media attachment with filename, size, and mime', 0, () => {
      const doc = new MediaAttachment(
        'document',
        4004,
        '/data/storage/el2/base/files/spec.pdf',
        null,
        0,
        0,
        0,
        false,
        true,
        1.0,
        'Project Specification',
        [],
        false,
        false,
        0,
        'spec.pdf',
        10485760,
        'application/pdf'
      );

      expect(doc.kind).assertEqual('document');
      expect(doc.fileId).assertEqual(4004);
      expect(doc.fileName).assertEqual('spec.pdf');
      expect(doc.fileSize).assertEqual(10485760);
      expect(doc.mimeType).assertEqual('application/pdf');
      expect(doc.isDownloaded).assertTrue();

      const updated = doc.copyWith(
        doc.localPath,
        doc.thumbnailPath,
        true,
        false,
        0.5,
        false,
        0,
        'spec_v2.pdf',
        20971520,
        'application/pdf'
      );
      expect(updated.fileName).assertEqual('spec_v2.pdf');
      expect(updated.fileSize).assertEqual(20971520);
      expect(updated.isDownloading).assertTrue();
      expect(updated.progress).assertEqual(0.5);
    });

    it('formatFileSize correctly formats various byte sizes', 0, () => {
      expect(formatFileSize(0)).assertEqual('0 B');
      expect(formatFileSize(-100)).assertEqual('0 B');
      expect(formatFileSize(500)).assertEqual('500 B');
      expect(formatFileSize(1024)).assertEqual('1.0 KB');
      expect(formatFileSize(1536)).assertEqual('1.5 KB');
      expect(formatFileSize(1048576)).assertEqual('1.0 MB');
      expect(formatFileSize(15728640)).assertEqual('15.0 MB');
      expect(formatFileSize(1073741824)).assertEqual('1.0 GB');
    });

    it('creates voiceNote media attachment with waveform and isListened', 0, () => {
      const voice = new MediaAttachment(
        'voiceNote',
        5001,
        '/data/storage/el2/base/files/voice.ogg',
        null,
        0,
        0,
        15,
        false,
        true,
        1.0,
        'Voice caption',
        [],
        false,
        false,
        0,
        '',
        12345,
        'audio/ogg',
        [5, 10, 20, 15],
        '',
        '',
        false
      );

      expect(voice.kind).assertEqual('voiceNote');
      expect(voice.fileId).assertEqual(5001);
      expect(voice.duration).assertEqual(15);
      expect(voice.isDownloaded).assertTrue();
      expect(voice.waveform.length).assertEqual(4);
      expect(voice.waveform[1]).assertEqual(10);
      expect(voice.isListened).assertFalse();
      expect(voice.caption).assertEqual('Voice caption');
    });

    it('creates audio media attachment with title, performer and thumbnail', 0, () => {
      const audio = new MediaAttachment(
        'audio',
        6001,
        '/data/storage/el2/base/files/song.mp3',
        '/data/storage/el2/base/files/cover.jpg',
        0,
        0,
        210,
        false,
        true,
        1.0,
        '',
        [],
        false,
        false,
        0,
        'song.mp3',
        5000000,
        'audio/mpeg',
        [],
        'Bohemian Rhapsody',
        'Queen',
        false
      );

      expect(audio.kind).assertEqual('audio');
      expect(audio.audioTitle).assertEqual('Bohemian Rhapsody');
      expect(audio.audioPerformer).assertEqual('Queen');
      expect(audio.duration).assertEqual(210);
      expect(audio.thumbnailPath).assertEqual('/data/storage/el2/base/files/cover.jpg');
    });

    it('creates videoNote media attachment with square dimensions', 0, () => {
      const videoNote = new MediaAttachment(
        'videoNote',
        7001,
        '/data/storage/el2/base/files/round.mp4',
        '/data/storage/el2/base/files/round_thumb.jpg',
        240,
        240,
        8,
        false,
        true,
        1.0
      );

      expect(videoNote.kind).assertEqual('videoNote');
      expect(videoNote.width).assertEqual(240);
      expect(videoNote.height).assertEqual(240);
      expect(videoNote.duration).assertEqual(8);
      expect(videoNote.isDownloaded).assertTrue();
    });

    it('decodeWaveform decodes base64 5-bit waveform properly', 0, () => {
      expect(decodeWaveform('').length).assertEqual(0);

      // 5 bytes = 40 bits = 8 samples (each 5 bits)
      // Base64 of 5 zero bytes: "AAAAAAA="
      const zeros = decodeWaveform('AAAAAAA=');
      expect(zeros.length).assertEqual(8);
      expect(zeros[0]).assertEqual(0);

      // Invalid base64 returns empty
      expect(decodeWaveform('not-valid!!').length).assertEqual(0);
    });

    it('normalizeWaveform resamples samples to targetCount', 0, () => {
      const emptyNorm = normalizeWaveform([], 32);
      expect(emptyNorm.length).assertEqual(32);
      // Default waveform has non-zero values
      expect(emptyNorm[0] > 0).assertTrue();

      const samples = [10, 20, 30, 40, 50, 60];
      const downsampled = normalizeWaveform(samples, 3);
      expect(downsampled.length).assertEqual(3);
      // Chunk 0 is [10, 20], max is 20
      expect(downsampled[0]).assertEqual(20);
      // Chunk 1 is [30, 40], max is 40
      expect(downsampled[1]).assertEqual(40);
      // Chunk 2 is [50, 60], max is 60
      expect(downsampled[2]).assertEqual(60);
    });

  });
}
