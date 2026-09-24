/**
 * feature/chat — 查看器动态内容判定单测（MEDIA-VIEWER-102）。
 *
 * 覆盖三条只在真机上才会露出来的行为：
 * - 容器判定必须认 mime，扩展名只看**结尾**（旧实现 `indexOf('.mp4')` 会把
 *   `video.mp4.notes.txt` 判成视频、把 `.gif` 动图判成需要播放器）；
 * - 播放器只给当前页，相邻缓存页只画封面（否则好几条音轨同时响）；
 * - 缩放只开放给照片页。
 */

import { describe, it, expect } from '@ohos/hypium';
import { MediaAttachment, MediaKind } from '../main/ets/model/MediaAttachment';
import {
  animationContainer,
  motionContainerOf,
  viewerMotionRender,
  viewerNeedsPlayer,
  viewerRendersPlayer,
  viewerZoomable
} from '../main/ets/model/ViewerPlayback';

function mediaOf(
  kind: MediaKind,
  localPath: string | null,
  isDownloaded: boolean,
  fileName: string,
  mimeType: string,
  isUploading: boolean = false,
  isDownloading: boolean = false
): MediaAttachment {
  return new MediaAttachment(
    kind,
    77,
    localPath,
    '/path/poster.jpg',
    640,
    360,
    12,
    isDownloading,
    isDownloaded,
    isDownloaded ? 1.0 : 0.4,
    '',
    [],
    false,
    isUploading,
    isUploading ? 0.6 : 0,
    fileName,
    4096,
    mimeType
  );
}

const DOWNLOADED_MP4: MediaAttachment = mediaOf('animation', '/tdlib/files/animations/tmp.mp4', true, 'tmp.mp4', 'video/mp4');
const DOWNLOADED_GIF: MediaAttachment = mediaOf('animation', '/tdlib/files/animations/loop.gif', true, 'loop.gif', 'image/gif');
const DOWNLOADED_VIDEO: MediaAttachment = mediaOf('video', '/tdlib/files/videos/6167929330363015197.mp4', true, 'clip.mp4', 'video/mp4');

export default function viewerPlaybackTest() {
  describe('ViewerPlaybackTest', () => {

    // ---- 容器判定 ----

    it('container_mimeGifWinsOverPathExtension', 0, () => {
      expect(motionContainerOf('image/gif', 'x.mp4', '/a/b.mp4')).assertEqual('gif');
    });

    it('container_mimeIsCaseAndSpaceInsensitive', 0, () => {
      expect(motionContainerOf('  IMAGE/GIF ', '', null)).assertEqual('gif');
      expect(motionContainerOf('Video/MP4', '', null)).assertEqual('video');
    });

    it('container_transcodedGifStillEndsAsVideo', 0, () => {
      // 设备实测文件名：2176acbf..._hq.gif.mp4 —— 结尾是 mp4 就是播放器档。
      expect(motionContainerOf('', 'abc_hq.gif.mp4', null)).assertEqual('video');
    });

    it('container_fallsBackToLocalPathExtension', 0, () => {
      expect(motionContainerOf('', '', '/tdlib/files/animations/loop.gif')).assertEqual('gif');
      expect(motionContainerOf('', '', '/tdlib/files/videos/616.mp4')).assertEqual('video');
    });

    it('container_readsOnlyTrailingExtension', 0, () => {
      // 旧实现 localPath.indexOf('.mp4') >= 0 会把这条判成视频。
      expect(motionContainerOf('', 'video.mp4.notes.txt', null)).assertEqual('unknown');
    });

    it('container_unknownWhenNothingToRead', 0, () => {
      expect(motionContainerOf('', '', '/tdlib/files/animations/4965671180404723173_109')).assertEqual('unknown');
      expect(motionContainerOf('', '', null)).assertEqual('unknown');
    });

    it('animationContainer_unknownDefaultsToPlayer', 0, () => {
      const blind: MediaAttachment = mediaOf('animation', '/tdlib/files/animations/4965671180404723173_109', true, '', '');
      expect(animationContainer(blind)).assertEqual('video');
    });

    // ---- 是否需要播放器 ----

    it('needsPlayer_videoAndMp4Animation', 0, () => {
      expect(viewerNeedsPlayer(DOWNLOADED_VIDEO)).assertTrue();
      expect(viewerNeedsPlayer(DOWNLOADED_MP4)).assertTrue();
    });

    it('needsPlayer_gifAnimationUsesImage', 0, () => {
      expect(viewerNeedsPlayer(DOWNLOADED_GIF)).assertFalse();
    });

    it('needsPlayer_photoNeverNeedsPlayer', 0, () => {
      expect(viewerNeedsPlayer(mediaOf('photo', '/a/b.jpg', true, 'b.jpg', 'image/jpeg'))).assertFalse();
    });

    // ---- 当前页独占 ----

    it('rendersPlayer_onlyActiveIndex', 0, () => {
      expect(viewerRendersPlayer(3, 3)).assertTrue();
      expect(viewerRendersPlayer(2, 3)).assertFalse();
      expect(viewerRendersPlayer(4, 3)).assertFalse();
    });

    // ---- 档位判定 ----

    it('motionRender_activeVideoPagePlays', 0, () => {
      expect(viewerMotionRender(DOWNLOADED_VIDEO, true)).assertEqual('player');
    });

    it('motionRender_neighbouringVideoPageOnlyPosters', 0, () => {
      // Swiper 缓存页不起播放器：这条断言就是「不会同时有几条音轨」的证明。
      expect(viewerMotionRender(DOWNLOADED_VIDEO, false)).assertEqual('poster');
      expect(viewerMotionRender(DOWNLOADED_MP4, false)).assertEqual('poster');
    });

    it('motionRender_gifPlaysWhereverItIsDrawn', 0, () => {
      expect(viewerMotionRender(DOWNLOADED_GIF, true)).assertEqual('gif');
      expect(viewerMotionRender(DOWNLOADED_GIF, false)).assertEqual('gif');
    });

    it('motionRender_missingFileAsksForDownload', 0, () => {
      const pending: MediaAttachment = mediaOf('video', null, false, 'clip.mp4', 'video/mp4');
      const midair: MediaAttachment = mediaOf('video', null, false, 'clip.mp4', 'video/mp4', false, true);
      expect(viewerMotionRender(pending, true)).assertEqual('download');
      expect(viewerMotionRender(midair, true)).assertEqual('download');
    });

    it('motionRender_outgoingVideoPlaysBeforeDownloadFlag', 0, () => {
      // 出站视频没有 isDownloaded，但本地文件就是我们的输入源，当前页该能播。
      const outgoing: MediaAttachment = mediaOf('video', '/cache/outgoing.mp4', false, 'outgoing.mp4', 'video/mp4', true);
      expect(viewerMotionRender(outgoing, true)).assertEqual('player');
    });

    // ---- 缩放归属 ----

    it('zoomable_onlyPhotos', 0, () => {
      expect(viewerZoomable('photo')).assertTrue();
      expect(viewerZoomable('video')).assertFalse();
      expect(viewerZoomable('animation')).assertFalse();
    });
  });
}
