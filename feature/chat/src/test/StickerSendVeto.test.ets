/**
 * feature/chat — 贴纸 / GIF 发送否决的判定单元测试（CHAN-SEND-3）。
 *
 * 守住的回归：ChatPage 只对「真贴纸」按 otherMessages 否决，unicode 表情当文本发不受这条管；
 * 而这条豁免的边界是硬编码 fileId 区间 —— 内置包一旦加到区间外，点了就会在只禁贴纸的群里
 * 被本地扣下（用户看到「不允许发送贴纸」，其实要发的是一行 emoji）。
 * 同理 GIF 的占位 fileId 必须**落在区间外**，否则禁贴纸的群会连 GIF 入口一起放行。
 */

import { describe, it, expect } from '@ohos/hypium';
import {
  DEFAULT_STICKER_PACKS,
  isUnicodeEmojiSticker,
  StickerSetItem,
  UNICODE_EMOJI_STICKER_MAX_FILE_ID,
  UNICODE_EMOJI_STICKER_MIN_FILE_ID
} from '../main/ets/model/StickerSetPreviewState';
import { DEFAULT_RECENT_GIFS, GifItem } from '../main/ets/model/GifItem';

export default function stickerSendVetoTest(): void {
  describe('StickerSendVetoTest', () => {

    it('unicodeRange_acceptsItsOwnBoundsAndRejectsNeighbours', 0, () => {
      expect(isUnicodeEmojiSticker(UNICODE_EMOJI_STICKER_MIN_FILE_ID)).assertTrue();
      expect(isUnicodeEmojiSticker(UNICODE_EMOJI_STICKER_MAX_FILE_ID)).assertTrue();
      expect(isUnicodeEmojiSticker(UNICODE_EMOJI_STICKER_MIN_FILE_ID - 1)).assertFalse();
      expect(isUnicodeEmojiSticker(UNICODE_EMOJI_STICKER_MAX_FILE_ID + 1)).assertFalse();
      expect(isUnicodeEmojiSticker(0)).assertFalse();
    });

    it('builtinStickerData_staysInsideTheUnicodeExemption', 0, () => {
      // 内置包全部是 emoji 占位，越界的应当走真贴纸发送路径。
      // （STICKER-RECENT-101 之后「最近使用」不再是内置数据，它来自 TDLib `getRecentStickers`，
      // 真实 fileId 本来就该落在豁免区间外。）
      for (let p = 0; p < DEFAULT_STICKER_PACKS.length; p++) {
        const stickers: StickerSetItem[] = DEFAULT_STICKER_PACKS[p].stickers;
        expect(stickers.length > 0).assertTrue();
        for (let i = 0; i < stickers.length; i++) {
          expect(isUnicodeEmojiSticker(stickers[i].fileId)).assertTrue();
        }
      }
    });

    it('gifData_staysOutsideTheUnicodeExemption', 0, () => {
      // GIF 占位档不能蹭到贴纸豁免上，否则 otherMessages 位对 GIF 页签形同失效。
      const gifs: GifItem[] = DEFAULT_RECENT_GIFS;
      expect(gifs.length > 0).assertTrue();
      for (let i = 0; i < gifs.length; i++) {
        expect(isUnicodeEmojiSticker(gifs[i].fileId)).assertFalse();
      }
    });
  });
}
