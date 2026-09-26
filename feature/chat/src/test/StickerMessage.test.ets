/**
 * feature/chat — 贴纸消息气泡档位单测（STICKER-MSG-101）。
 *
 * 钉住设备实测出来的那条分支（Saved Messages 里动效贴纸气泡整块空白）：
 * - `.tgs` 整档已下完也**不能**进 `Image`，必须退回缩略图；
 * - 缩略图本身是 `.tgs` 时不能当兜底（等于再画一次空白），继续退到 emoji；
 * - 视频容器走 `Video`，且扩展名只看结尾；
 * - 位图（webp/png/gif）与无扩展名的整档正常直接画。
 */

import { describe, it, expect } from '@ohos/hypium';
import { MediaAttachment } from '../main/ets/model/MediaAttachment';
import { stickerBubbleRender } from '../main/ets/model/StickerMessage';

function stickerOf(
  localPath: string | null,
  isDownloaded: boolean,
  thumbnailPath: string | null,
  emoji: string = '🦄',
  isDownloading: boolean = false
): MediaAttachment {
  return new MediaAttachment(
    'sticker',
    92,
    localPath,
    thumbnailPath,
    128,
    128,
    0,
    isDownloading,
    isDownloaded,
    isDownloaded ? 1.0 : 0.3,
    emoji
  );
}

const TGS_DIR: string = '/data/app/el2/100/base/org.telegram.x.harmony/haps/entry/files/tdlib/db/stickers';
const THUMB_DIR: string = '/data/app/el2/100/base/org.telegram.x.harmony/haps/entry/files/tdlib/db/thumbnails';

export default function stickerMessageTest() {
  describe('StickerMessageTest', () => {

    it('tgs_sticker_downloaded_falls_back_to_webp_thumbnail', 0, () => {
      const media: MediaAttachment = stickerOf(`${TGS_DIR}/1052321353216032834.tgs`, true, `${THUMB_DIR}/1052321353216032834_109.webp`);
      expect(stickerBubbleRender(media)).assertEqual('thumbnail');
    });

    it('tgs_sticker_without_thumbnail_falls_back_to_emoji', 0, () => {
      const media: MediaAttachment = stickerOf(`${TGS_DIR}/1052321353216032834.tgs`, true, null, '🦄', true);
      expect(stickerBubbleRender(media)).assertEqual('emoji');
    });

    it('tgs_thumbnail_is_not_a_fallback', 0, () => {
      const media: MediaAttachment = stickerOf(`${TGS_DIR}/9.tgs`, true, `${THUMB_DIR}/328260442013040644_1680977305.tgs`);
      expect(stickerBubbleRender(media)).assertEqual('emoji');
    });

    it('raster_sticker_draws_full_file', 0, () => {
      expect(stickerBubbleRender(stickerOf(`${TGS_DIR}/6179161902497664507.webp`, true, null))).assertEqual('image');
      expect(stickerBubbleRender(stickerOf(`${TGS_DIR}/sticker.png`, true, null))).assertEqual('image');
      expect(stickerBubbleRender(stickerOf(`${TGS_DIR}/sticker.gif`, true, null))).assertEqual('image');
    });

    it('path_without_extension_is_not_rejected', 0, () => {
      expect(stickerBubbleRender(stickerOf(`${TGS_DIR}/4711`, true, null))).assertEqual('image');
    });

    it('video_sticker_uses_player', 0, () => {
      expect(stickerBubbleRender(stickerOf(`${TGS_DIR}/5135778821028215305.mp4`, true, null))).assertEqual('video');
      expect(stickerBubbleRender(stickerOf(`${TGS_DIR}/clip.webm`, true, null))).assertEqual('video');
      // 扩展名只认结尾：中间出现 .mp4 的不是视频容器，而是画不开的 tgs
      expect(stickerBubbleRender(stickerOf(`${TGS_DIR}/a.mp4.tgs`, true, `${THUMB_DIR}/a_109.webp`))).assertEqual('thumbnail');
    });

    it('undownloaded_sticker_prefers_thumbnail', 0, () => {
      expect(stickerBubbleRender(stickerOf(`${TGS_DIR}/x.tgs`, false, `${THUMB_DIR}/x_109.webp`, '🦄', true))).assertEqual('thumbnail');
      expect(stickerBubbleRender(stickerOf(`${TGS_DIR}/x.webp`, false, `${THUMB_DIR}/x_109.webp`))).assertEqual('thumbnail');
      expect(stickerBubbleRender(stickerOf(null, false, null, ''))).assertEqual('emoji');
    });

    it('blank_emoji_returns_emoji_tier_for_placeholder_glyph', 0, () => {
      const media: MediaAttachment = stickerOf(null, false, null, '   ');
      expect(stickerBubbleRender(media)).assertEqual('emoji');
    });
  });
}
