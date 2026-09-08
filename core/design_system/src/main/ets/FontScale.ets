import { TextStyle, TypographyTokens, TYPOGRAPHY_TOKEN_NAMES } from './Typography';

/**
 * Font-scale adaptation. HarmonyOS exposes the system font size via
 * `display.getDefaultDisplaySync()` / configuration update callbacks;
 * the platform layer will feed the raw scale into this module. Pure math here.
 */

/** Supported range, matching HarmonyOS font-size settings behavior. */
export const FONT_SCALE_MIN: number = 0.85;
export const FONT_SCALE_MAX: number = 2.0;

/**
 * Absolute floor for scaled text. Below ~11vp body text becomes hard to
 * read even when the user asked for smaller text, so never go under this.
 */
export const MIN_READABLE_FONT_SIZE: number = 11;

/** Clamp an arbitrary (possibly untrusted platform) scale into the supported range. */
export function clampFontScale(scale: number): number {
  if (Number.isNaN(scale)) {
    return 1.0;
  }
  if (scale < FONT_SCALE_MIN) {
    return FONT_SCALE_MIN;
  }
  if (scale > FONT_SCALE_MAX) {
    return FONT_SCALE_MAX;
  }
  return scale;
}

/** Round to 1 decimal place to keep generated values stable in snapshots. */
function round1(value: number): number {
  return Math.round(value * 10) / 10;
}

/**
 * Scale one text style. Line height scales by the same factor but never
 * drops below the (also scaled, then floored) font size.
 */
export function scaleTextStyle(style: TextStyle, fontScale: number): TextStyle {
  const scale = clampFontScale(fontScale);
  const fontSize = Math.max(round1(style.fontSize * scale), MIN_READABLE_FONT_SIZE);
  const lineHeight = Math.max(round1(style.lineHeight * scale), fontSize);
  return {
    fontSize: fontSize,
    lineHeight: lineHeight,
    fontWeight: style.fontWeight
  };
}

/** Scale every style in the type scale, preserving names and weights. */
export function scaleTypography(tokens: TypographyTokens, fontScale: number): TypographyTokens {
  const scaled = {} as TypographyTokens;
  for (const name of TYPOGRAPHY_TOKEN_NAMES) {
    scaled[name] = scaleTextStyle(tokens[name], fontScale);
  }
  return scaled;
}
