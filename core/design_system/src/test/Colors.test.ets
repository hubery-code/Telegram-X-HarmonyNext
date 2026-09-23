import { describe, it, expect } from '@ohos/hypium';
import {
  LightColors,
  DarkColors,
  COLOR_TOKEN_NAMES,
  isColorTokenValue
} from '../main/ets/Colors';

/** '#AARRGGBB' -> [r, g, b] in 0..1 (alpha ignored). */
function rgbOf(hex: string): number[] {
  const v = parseInt(hex.substring(1), 16);
  return [((v >> 16) & 0xFF) / 255, ((v >> 8) & 0xFF) / 255, (v & 0xFF) / 255];
}

function luminanceOf(hex: string): number {
  const lin = rgbOf(hex).map((c: number) => {
    return c <= 0.03928 ? c / 12.92 : Math.pow((c + 0.055) / 1.055, 2.4);
  });
  return 0.2126 * lin[0] + 0.7152 * lin[1] + 0.0722 * lin[2];
}

function contrastRatio(a: string, b: string): number {
  const la = luminanceOf(a);
  const lb = luminanceOf(b);
  const hi = Math.max(la, lb);
  const lo = Math.min(la, lb);
  return (hi + 0.05) / (lo + 0.05);
}

export default function colorsTest() {
  describe('ColorTokensTest', () => {
    it('every_semanticTokenExistsInBothPalettes', 0, () => {
      expect(COLOR_TOKEN_NAMES.length >= 15).assertTrue();
      for (const name of COLOR_TOKEN_NAMES) {
        expect(isColorTokenValue(LightColors[name])).assertTrue();
        expect(isColorTokenValue(DarkColors[name])).assertTrue();
      }
    });

    it('nameList_coversEveryTokenInTheMaps', 0, () => {
      for (const key of Object.keys(LightColors)) {
        expect(COLOR_TOKEN_NAMES.indexOf(key) >= 0).assertTrue();
      }
      for (const key of Object.keys(DarkColors)) {
        expect(COLOR_TOKEN_NAMES.indexOf(key) >= 0).assertTrue();
      }
    });

    it('lightAndDark_palettesAreDistinct', 0, () => {
      let differing = 0;
      for (const name of COLOR_TOKEN_NAMES) {
        if (LightColors[name] !== DarkColors[name]) {
          differing++;
        }
      }
      // Surfaces may legitimately share hex values across modes; require
      // nearly all tokens to differ so a swapped theme is visibly obvious.
      expect(differing >= COLOR_TOKEN_NAMES.length - 2).assertTrue();
    });

    it('primaryText_contrastMeetsWcagAa', 0, () => {
      expect(contrastRatio(LightColors.textPrimary, LightColors.background) >= 4.5).assertTrue();
      expect(contrastRatio(DarkColors.textPrimary, DarkColors.background) >= 4.5).assertTrue();
    });

    it('secondaryText_contrastMeetsWcagLargeText', 0, () => {
      expect(contrastRatio(LightColors.textSecondary, LightColors.background) >= 3.0).assertTrue();
      expect(contrastRatio(DarkColors.textSecondary, DarkColors.background) >= 3.0).assertTrue();
    });

    it('chatText_isReadableOnBothBubbleDirections', 0, () => {
      expect(contrastRatio(LightColors.chatText, LightColors.chatIncoming) >= 3.0).assertTrue();
      expect(contrastRatio(LightColors.chatText, LightColors.chatOutgoing) >= 3.0).assertTrue();
      expect(contrastRatio(DarkColors.chatText, DarkColors.chatIncoming) >= 3.0).assertTrue();
      expect(contrastRatio(DarkColors.chatText, DarkColors.chatOutgoing) >= 3.0).assertTrue();
    });

    it('textOnAccent_isReadableOnAccent', 0, () => {
      expect(contrastRatio(LightColors.textOnAccent, LightColors.accent) >= 3.0).assertTrue();
      expect(contrastRatio(DarkColors.textOnAccent, DarkColors.accent) >= 3.0).assertTrue();
    });

    // textOnScrim 存在的理由：深色主题下 textOnAccent 是黑色，压在照片封面上直接不可读。
    it('textOnScrim_staysWhiteOverScrim', 0, () => {
      expect(LightColors.textOnScrim).assertEqual('#FFFFFFFF');
      expect(DarkColors.textOnScrim).assertEqual('#FFFFFFFF');
      expect(DarkColors.textOnScrim !== DarkColors.textOnAccent).assertTrue();
      expect(contrastRatio(LightColors.textOnScrim, LightColors.scrim) >= 4.5).assertTrue();
      expect(contrastRatio(DarkColors.textOnScrim, DarkColors.scrim) >= 4.5).assertTrue();
    });
  });
}
