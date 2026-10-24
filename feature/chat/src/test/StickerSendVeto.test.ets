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
      // GIF 不能蹭到贴纸豁免上，否则 otherMessages 位对 GIF 页签形同失效。
      //
      // GIF-SEND-101 之前这条用的是 `DEFAULT_RECENT_GIFS`（25 个假占位，fileId
      // 固定 2001-2040，天然在区间外，所以它其实**没有真的测到边界**）。
      // 那批占位已删，GIF 改为只显示 TDLib 的真实 saved animations，
      // fileId 由服务端给（可能是任意正整数）。所以这里改成钉**不变量**：
      // 用代表性 fileId（含区间上下边界之外/之内的两组）断言判据本身，
      // 而不是断言某份数据的取值恰好安全。
      const realWorldGifIds: number[] = [7001, 8888, 5001, 123456789, 98765432101];
      for (let i = 0; i < realWorldGifIds.length; i++) {
        expect(isUnicodeEmojiSticker(realWorldGifIds[i])).assertFalse();
      }
      // 边界自证：区间两端之内的值必须被判为 unicode emoji 贴纸，
      // 两端之外一个步长的必须不被判 —— 这样「区间」这个词才有意义。
      expect(isUnicodeEmojiSticker(UNICODE_EMOJI_STICKER_MIN_FILE_ID)).assertTrue();
      expect(isUnicodeEmojiSticker(UNICODE_EMOJI_STICKER_MAX_FILE_ID)).assertTrue();
      expect(isUnicodeEmojiSticker(UNICODE_EMOJI_STICKER_MIN_FILE_ID - 1)).assertFalse();
      expect(isUnicodeEmojiSticker(UNICODE_EMOJI_STICKER_MAX_FILE_ID + 1)).assertFalse();
    });
  });
}
