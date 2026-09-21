import { describe, it, expect } from '@ohos/hypium';
import {
  CHAT_FONT_SIZE_STEPS,
  CHAT_FONT_SIZE_DEFAULT,
  CHAT_FONT_SIZE_MIN,
  CHAT_FONT_SIZE_MAX,
  MIN_READABLE_FONT_SIZE,
  clampChatFontSize,
  parseChatFontSize,
  chatFontSizeIndex,
  chatFontSizeAt,
  chatFontScaleOf,
  chatTextSizeOf
} from '../main/ets/FontScale';

export default function chatFontSizeTest() {
  describe('ChatFontSizeTest', () => {
    it('steps_matchTgxSettingsChatFontSizes', 0, () => {
      // 逐值对齐 TGX Settings.CHAT_FONT_SIZES，顺序不可改（Parity 契约）。
      expect(CHAT_FONT_SIZE_STEPS.length).assertEqual(10);
      const expected: number[] = [12, 13, 14, 15, 16, 18, 20, 22, 24, 26];
      for (let i = 0; i < expected.length; i++) {
        expect(CHAT_FONT_SIZE_STEPS[i]).assertEqual(expected[i]);
      }
      expect(CHAT_FONT_SIZE_DEFAULT).assertEqual(15);
      expect(CHAT_FONT_SIZE_MIN).assertEqual(12);
      expect(CHAT_FONT_SIZE_MAX).assertEqual(26);
    });

    it('clamp_snapsToNearestStep', 0, () => {
      expect(clampChatFontSize(15)).assertEqual(15);
      expect(clampChatFontSize(15.4)).assertEqual(15);
      expect(clampChatFontSize(15.6)).assertEqual(16);
      expect(clampChatFontSize(17)).assertEqual(16);
      expect(clampChatFontSize(25)).assertEqual(24);
    });

    it('clamp_equidistantPrefersLowerStep', 0, () => {
      // 19 距 18 与 20 等距（档位表在 16 之后是偶数档）。实现用严格 `<` 比较，
      // 先遍历到的较小档胜出——这里把这条语义固化下来，避免以后有人把 `<`
      // 改成 `<=` 造成静默行为漂移。
      expect(clampChatFontSize(19)).assertEqual(18);
      expect(clampChatFontSize(17)).assertEqual(16);
    });

    it('clamp_pinsOutOfRangeToEnds', 0, () => {
      expect(clampChatFontSize(0)).assertEqual(CHAT_FONT_SIZE_MIN);
      expect(clampChatFontSize(-5)).assertEqual(CHAT_FONT_SIZE_MIN);
      expect(clampChatFontSize(11.9)).assertEqual(CHAT_FONT_SIZE_MIN);
      expect(clampChatFontSize(100)).assertEqual(CHAT_FONT_SIZE_MAX);
    });

    it('clamp_rejectsNonNumericWithDefault', 0, () => {
      expect(clampChatFontSize(Number.NaN)).assertEqual(CHAT_FONT_SIZE_DEFAULT);
      expect(clampChatFontSize(Number.POSITIVE_INFINITY)).assertEqual(CHAT_FONT_SIZE_DEFAULT);
      expect(clampChatFontSize('abc')).assertEqual(CHAT_FONT_SIZE_DEFAULT);
      expect(clampChatFontSize('')).assertEqual(CHAT_FONT_SIZE_DEFAULT);
    });

    it('clamp_acceptsNumericStringFromAppStorage', 0, () => {
      // 回归防线：该值在 AppStorage 里按字符串约定存放（entry 回灌与 reducer
      // 两侧都写 `${size}`，跨存储层的文本表示）。此处若不做类型收敛，
      // Number.isFinite('26') 会返回 false，合法档位会被误判成脏值回落默认档。
      expect(clampChatFontSize('26')).assertEqual(26);
      expect(clampChatFontSize('12')).assertEqual(12);
      expect(clampChatFontSize('15')).assertEqual(15);
      expect(clampChatFontSize('15.6')).assertEqual(16);
      expect(clampChatFontSize('<none>')).assertEqual(CHAT_FONT_SIZE_DEFAULT);
    });

    it('parse_missingValueFallsBackToDefault', 0, () => {
      expect(parseChatFontSize(undefined)).assertEqual(CHAT_FONT_SIZE_DEFAULT);
      expect(parseChatFontSize(null)).assertEqual(CHAT_FONT_SIZE_DEFAULT);
    });

    it('parse_numberAndStringAgree', 0, () => {
      for (const step of CHAT_FONT_SIZE_STEPS) {
        expect(parseChatFontSize(step)).assertEqual(step);
        expect(parseChatFontSize(`${step}`)).assertEqual(step);
      }
    });

    it('indexAt_roundTripsEveryStep', 0, () => {
      for (let i = 0; i < CHAT_FONT_SIZE_STEPS.length; i++) {
        expect(chatFontSizeIndex(CHAT_FONT_SIZE_STEPS[i])).assertEqual(i);
        expect(chatFontSizeAt(i)).assertEqual(CHAT_FONT_SIZE_STEPS[i]);
      }
    });

    it('indexAt_outOfRangeIndexFallsBackToDefault', 0, () => {
      expect(chatFontSizeAt(-1)).assertEqual(CHAT_FONT_SIZE_DEFAULT);
      expect(chatFontSizeAt(CHAT_FONT_SIZE_STEPS.length)).assertEqual(CHAT_FONT_SIZE_DEFAULT);
    });

    it('scaleRatio_defaultStepIsIdentity', 0, () => {
      expect(chatFontScaleOf(CHAT_FONT_SIZE_DEFAULT)).assertEqual(1);
      expect(chatFontScaleOf(CHAT_FONT_SIZE_MIN)).assertEqual(0.8);
      expect(chatFontScaleOf(CHAT_FONT_SIZE_MAX)).assertEqual(1.7333333333333334);
    });

    it('textSize_defaultStep_keepsBaselineUntouched', 0, () => {
      // 默认档倍率 1.0 + 偏移 0 → 与改造前逐像素一致。
      expect(chatTextSizeOf(17, CHAT_FONT_SIZE_DEFAULT)).assertEqual(17);
      expect(chatTextSizeOf(13, CHAT_FONT_SIZE_DEFAULT)).assertEqual(13);
    });

    it('textSize_scalesBaseByRatio_thenAppliesDiff', 0, () => {
      expect(chatTextSizeOf(17, CHAT_FONT_SIZE_MAX)).assertEqual(29.5);
      expect(chatTextSizeOf(17, CHAT_FONT_SIZE_MAX, -1)).assertEqual(28.5);
      expect(chatTextSizeOf(12, CHAT_FONT_SIZE_MAX, -1)).assertEqual(19.8);
      expect(chatTextSizeOf(17, CHAT_FONT_SIZE_MIN, -1)).assertEqual(12.6);
    });

    it('textSize_neverDropsBelowReadableFloor', 0, () => {
      // 反应 chip 用的 caption(-4)：12 档算出来是 5.6vp，必须被托到下限。
      expect(chatTextSizeOf(12, CHAT_FONT_SIZE_MIN, -4)).assertEqual(MIN_READABLE_FONT_SIZE);
      expect(chatTextSizeOf(13, CHAT_FONT_SIZE_DEFAULT, -4)).assertEqual(MIN_READABLE_FONT_SIZE);
      expect(chatTextSizeOf(12, CHAT_FONT_SIZE_DEFAULT, -4)).assertEqual(MIN_READABLE_FONT_SIZE);
    });

    it('textSize_monotonicInFontSize', 0, () => {
      let previous: number = 0;
      for (const step of CHAT_FONT_SIZE_STEPS) {
        const current: number = chatTextSizeOf(17, step);
        expect(current >= previous).assertTrue();
        previous = current;
      }
    });
  });
}
