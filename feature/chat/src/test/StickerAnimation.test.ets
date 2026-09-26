/**
 * feature/chat — 动效贴纸取数口径单测（TGS-101）。
 *
 * 钉住两件事：
 * - **哪些整档算动效**：只看路径结尾那一段扩展名，`.tgs` / `.json` 才是解码口的输入，
 *   位图与视频容器一律不算（算错了就是把 `Image` 能画的档换成一片空白）；
 * - **有解码口时档位怎么变**：只有「贴纸 + 整档已下盘 + 整档是动效格式」三条同时成立，
 *   `stickerBubbleRender` 才升 `'tgs'`；其余一切（未下完、位图、视频、只有缩略图）
 *   保持 STICKER-MSG-101 的原样，`canAnimate` 关掉时更是逐条等于旧行为。
 */

import { describe, it, expect } from '@ohos/hypium';
import { MediaAttachment, MediaKind } from '../main/ets/model/MediaAttachment';
import { stickerAnimationTgsPath, stickerPathIsLottie } from '../main/ets/model/StickerAnimation';
import { stickerBubbleRender } from '../main/ets/model/StickerMessage';

const FILE_DIR: string = '/data/app/el2/100/base/org.telegram.x.harmony/haps/entry/files/tdlib/db/stickers';
const THUMB_DIR: string = '/data/app/el2/100/base/org.telegram.x.harmony/haps/entry/files/tdlib/db/thumbnails';

function mediaOf(
  localPath: string | null,
  isDownloaded: boolean,
  thumbnailPath: string | null,
  kind: MediaKind = 'sticker'
): MediaAttachment {
  return new MediaAttachment(kind, 92, localPath, thumbnailPath, 128, 128, 0, false, isDownloaded, 1.0, '🦄');
}

export default function stickerAnimationTest() {
  describe('StickerAnimationTest', () => {

    it('only_tgs_and_json_suffixes_are_lottie', 0, () => {
      expect(stickerPathIsLottie(`${FILE_DIR}/1052321353216032834.tgs`)).assertTrue();
      expect(stickerPathIsLottie(`${FILE_DIR}/animation.JSON`)).assertTrue();
      expect(stickerPathIsLottie(`${FILE_DIR}/sticker.webp`)).assertFalse();
      expect(stickerPathIsLottie(`${FILE_DIR}/sticker.mp4`)).assertFalse();
      expect(stickerPathIsLottie(`${FILE_DIR}/4711`)).assertFalse();
      expect(stickerPathIsLottie(`${FILE_DIR}/sticker.tgs.`)).assertFalse();
      expect(stickerPathIsLottie(null)).assertFalse();
    });

    it('middle_of_the_name_does_not_count', 0, () => {
      // `.tgs` 必须在结尾：`x.tgs.webp` 是解好后的位图产物，不是解码口的输入
      expect(stickerPathIsLottie(`${FILE_DIR}/a.tgs.webp`)).assertFalse();
      expect(stickerPathIsLottie(`${FILE_DIR}/a.mp4.tgs`)).assertTrue();
    });

    it('animation_source_needs_downloaded_sticker_file', 0, () => {
      const tgs: string = `${FILE_DIR}/1052321353216032834.tgs`;
      expect(stickerAnimationTgsPath(mediaOf(tgs, true, `${THUMB_DIR}/1052321353216032834_109.webp`)) === tgs).assertTrue();
      // 整档没下完：画的是缩略图，没有可解码的文件
      expect(stickerAnimationTgsPath(mediaOf(tgs, false, `${THUMB_DIR}/x_109.webp`)) === null).assertTrue();
      // 位图贴纸即使能画也不进解码口
      expect(stickerAnimationTgsPath(mediaOf(`${FILE_DIR}/x.webp`, true, null)) === null).assertTrue();
      // 不是贴纸（照片的路径也可能带扩展名）
      expect(stickerAnimationTgsPath(mediaOf(tgs, true, null, 'photo')) === null).assertTrue();
    });

    it('tgs_tier_only_when_decoder_is_wired', 0, () => {
      const tgs: MediaAttachment = mediaOf(`${FILE_DIR}/1052321353216032834.tgs`, true, `${THUMB_DIR}/1052321353216032834_109.webp`);
      expect(stickerBubbleRender(tgs, true)).assertEqual('tgs');
      // 没解码口就是 STICKER-MSG-101 的老行为：退回静态缩略图
      expect(stickerBubbleRender(tgs)).assertEqual('thumbnail');
      expect(stickerBubbleRender(tgs, false)).assertEqual('thumbnail');
    });

    it('raster_and_video_tiers_ignore_the_decoder', 0, () => {
      expect(stickerBubbleRender(mediaOf(`${FILE_DIR}/6179161902497664507.webp`, true, null), true)).assertEqual('image');
      expect(stickerBubbleRender(mediaOf(`${FILE_DIR}/5135778821028215305.mp4`, true, null), true)).assertEqual('video');
      // 整档没下完 → 动效档无从谈起，仍是缩略图（下载中要能看到进度圈）
      expect(stickerBubbleRender(mediaOf(`${FILE_DIR}/x.tgs`, false, `${THUMB_DIR}/x_109.webp`), true)).assertEqual('thumbnail');
      // 只有 tgs 缩略图时没有可解码的整档，也没有能画的缩略图 → 退回 emoji（进度圈另外叠）
      expect(stickerBubbleRender(mediaOf(`${FILE_DIR}/y.tgs`, false, `${THUMB_DIR}/x_109.tgs`), true)).assertEqual('emoji');
    });

    it('no_local_path_never_animates', 0, () => {
      expect(stickerBubbleRender(mediaOf(null, false, null), true)).assertEqual('emoji');
      expect(stickerAnimationTgsPath(mediaOf(null, true, null)) === null).assertTrue();
    });
  });
}
