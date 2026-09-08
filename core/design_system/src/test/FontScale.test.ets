import { describe, it, expect } from '@ohos/hypium';
import {
  FONT_SCALE_MIN,
  FONT_SCALE_MAX,
  MIN_READABLE_FONT_SIZE,
  clampFontScale,
  scaleTextStyle,
  scaleTypography
} from '../main/ets/FontScale';
import { DefaultTypography, TextStyle } from '../main/ets/Typography';

const BOUNDARIES: number[] = [0.85, 1.0, 1.15, 1.3, 2.0];

export default function fontScaleTest() {
  describe('FontScaleTest', () => {
    it('boundaries_areAcceptedUnclamped', 0, () => {
      for (const s of BOUNDARIES) {
        expect(clampFontScale(s)).assertEqual(s);
      }
    });

    it('outOfRangeValues_areClamped', 0, () => {
      expect(clampFontScale(0.5)).assertEqual(FONT_SCALE_MIN);
      expect(clampFontScale(5.0)).assertEqual(FONT_SCALE_MAX);
      expect(clampFontScale(Number.NaN)).assertEqual(1.0);
    });

    it('scaleOne_isIdentity', 0, () => {
      const body: TextStyle = DefaultTypography.body;
      const scaled: TextStyle = scaleTextStyle(body, 1.0);
      expect(scaled.fontSize).assertEqual(body.fontSize);
      expect(scaled.lineHeight).assertEqual(body.lineHeight);
      expect(scaled.fontWeight).assertEqual(body.fontWeight);
    });

    it('monotonic_fontSizeGrowsWithScale', 0, () => {
      let prev = 0;
      for (const s of BOUNDARIES) {
        const size = scaleTextStyle(DefaultTypography.body, s).fontSize;
        expect(size > prev).assertTrue();
        prev = size;
      }
    });

    it('smallStyles_neverGoBelowReadableMinimum', 0, () => {
      const caption: TextStyle = DefaultTypography.caption;
      const smallest = scaleTextStyle(caption, FONT_SCALE_MIN);
      expect(smallest.fontSize >= MIN_READABLE_FONT_SIZE).assertTrue();
      // Even an absurd tiny style request respects the floor.
      const tiny: TextStyle = { fontSize: 1, lineHeight: 1, fontWeight: 400 };
      expect(scaleTextStyle(tiny, FONT_SCALE_MIN).fontSize).assertEqual(MIN_READABLE_FONT_SIZE);
    });

    it('lineHeight_neverSmallerThanFontSize', 0, () => {
      for (const s of BOUNDARIES) {
        const scaled = scaleTextStyle(DefaultTypography.body, s);
        expect(scaled.lineHeight >= scaled.fontSize).assertTrue();
      }
      // Degenerate input: lineHeight follows the floored fontSize.
      const tiny: TextStyle = { fontSize: 1, lineHeight: 1, fontWeight: 400 };
      const scaledTiny = scaleTextStyle(tiny, FONT_SCALE_MIN);
      expect(scaledTiny.lineHeight >= scaledTiny.fontSize).assertTrue();
    });

    it('scaleTypography_scalesEveryStyle_andKeepsWeights', 0, () => {
      for (const s of BOUNDARIES) {
        const scaled = scaleTypography(DefaultTypography, s);
        for (const name of ['display', 'largeTitle', 'title', 'headline', 'body',
          'callout', 'subheadline', 'footnote', 'caption']) {
          expect(scaled[name].fontWeight).assertEqual(DefaultTypography[name].fontWeight);
          expect(scaled[name].fontSize >= MIN_READABLE_FONT_SIZE).assertTrue();
          expect(scaled[name].lineHeight >= scaled[name].fontSize).assertTrue();
        }
      }
    });
  });
}
