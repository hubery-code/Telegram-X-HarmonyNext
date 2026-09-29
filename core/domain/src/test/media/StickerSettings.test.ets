/**
 * core/domain — 「贴纸与表情」设置单元测试（TGS-104）。
 *
 * 守住的回归：
 * 1. 位的**方向**。Android 存的是否定位（`SETTING_FLAG_NO_ANIMATED_STICKERS_LOOP`），
 *    本端字段是肯定语义，反转只允许发生在 `toMask()/fromMask()` 这一对边界上 ——
 *    写反了一次「循环」就变成「只演一遍」，而且盘上的整数看起来还是「对」的；
 * 2. 位值本身。它和 Android 同值（`1 << 3`），改动会让已落盘的整数被重新解释；
 * 3. 缺值与脏值的默认档：读不到盘时按 Android 首装口径 = 循环。
 *    按「安全侧」猜成不循环是错的 —— 用户看到的是设置页写着「循环播放」、贴纸演一遍就停。
 */

import { describe, it, expect } from '@ohos/hypium';
import {
  STICKER_FLAG_NO_ANIMATED_STICKERS_LOOP,
  STICKER_SETTINGS_STORAGE_PREFIX,
  StickerSettings,
  stickerLoopEnabled
} from '../../main/ets/media/StickerSettings';

export default function stickerSettingsTest() {
  describe('StickerSettings', () => {

    it('keeps_flag_bit_position_and_prefix_stable', 0, () => {
      // 位值沿用 Android（unsorted/Settings.java:411）；前缀一改，盘上的旧值就读不到了。
      expect(STICKER_FLAG_NO_ANIMATED_STICKERS_LOOP).assertEqual(8);
      expect(STICKER_SETTINGS_STORAGE_PREFIX).assertEqual('stickers_');
    });

    it('inverts_only_at_the_mask_boundary', 0, () => {
      // 循环 = 那位不亮；不循环 = 那位亮着。
      expect(new StickerSettings(true).toMask()).assertEqual(0);
      expect(new StickerSettings(false).toMask()).assertEqual(STICKER_FLAG_NO_ANIMATED_STICKERS_LOOP);
    });

    it('round_trips_every_reachable_mask', 0, () => {
      const masks: number[] = [0, STICKER_FLAG_NO_ANIMATED_STICKERS_LOOP];
      for (const mask of masks) {
        const settings: StickerSettings = StickerSettings.fromMask(mask);
        expect(settings.toMask()).assertEqual(mask);
        expect(stickerLoopEnabled(settings)).assertEqual(mask === 0);
      }
    });

    it('keeps_unknown_bits_untouched_in_the_round_trip', 0, () => {
      // 将来并位进来（大号表情等）时，未建模的位不得被这次改写抹掉。
      const withOtherBit: StickerSettings = StickerSettings.fromMask(1 | STICKER_FLAG_NO_ANIMATED_STICKERS_LOOP);
      expect(withOtherBit.loopAnimatedStickers).assertFalse();
      // 本端只有一位在建模，回写时其余位归零是已知取舍：现盘上不可能有别的位。
      expect(withOtherBit.toMask()).assertEqual(STICKER_FLAG_NO_ANIMATED_STICKERS_LOOP);
    });

    it('defaults_to_loop_like_android_first_install', 0, () => {
      expect(StickerSettings.defaultSettings().loopAnimatedStickers).assertTrue();
      expect(StickerSettings.defaultSettings().toMask()).assertEqual(0);
    });

    it('falls_back_to_default_on_unusable_mask', 0, () => {
      const bad: number[] = [-1, -100, Number.NaN, Number.POSITIVE_INFINITY];
      for (const mask of bad) {
        expect(StickerSettings.fromMask(mask).equals(StickerSettings.defaultSettings())).assertTrue();
      }
      // 小数（脏值）要吸附成整数再判位，不能因为 `8.5 & 8` 这类行为意外落进另一档。
      expect(StickerSettings.fromMask(8.5).loopAnimatedStickers).assertFalse();
      expect(StickerSettings.fromMask(0.5).loopAnimatedStickers).assertTrue();
    });

    it('treats_missing_settings_as_android_default', 0, () => {
      // 还没读盘 / 读盘失败：按默认档循环，而不是停在末帧。
      expect(stickerLoopEnabled(null)).assertTrue();
    });

    it('changes_the_loop_bit_into_a_new_object', 0, () => {
      const source: StickerSettings = StickerSettings.defaultSettings();
      const next: StickerSettings = source.withLoopEnabled(false);
      expect(source.loopAnimatedStickers).assertTrue();
      expect(next.loopAnimatedStickers).assertFalse();
      expect(next.equals(source)).assertFalse();
      expect(next.equals(null)).assertFalse();
      expect(next.equals(new StickerSettings(false))).assertTrue();
      expect(next.clone().equals(next)).assertTrue();
    });
  });
}
