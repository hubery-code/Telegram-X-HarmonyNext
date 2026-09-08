/**
 * Typography tokens: type scale (font size / line height / weight).
 * Pure data — no ArkUI types — so the module stays Kit-free and unit-testable.
 * Weights use numeric values matching ArkUI FontWeight
 * (400=Regular, 500=Medium, 600=DemiBold/Bold in ArkUI mapping, 700=Bold).
 */

export interface TextStyle {
  /** Font size in vp. */
  fontSize: number;
  /** Line height in vp; must be >= fontSize for readability. */
  lineHeight: number;
  /** Numeric font weight (400/500/600/700). */
  fontWeight: number;
}

/** Canonical font weights, kept as numbers for ArkUI interop. */
export interface FontWeightValues {
  regular: number;
  medium: number;
  semibold: number;
  bold: number;
}

export const FontWeights: FontWeightValues = {
  regular: 400,
  medium: 500,
  semibold: 600,
  bold: 700
};

/**
 * Named type styles of the Telegram X type scale. Stored as Record so the
 * scale can be iterated; keep TYPOGRAPHY_TOKEN_NAMES in sync when adding one:
 *   display     rare marketing-scale headline
 *   largeTitle  page titles (chat title, settings section)
 *   title       navigation bar / sheet titles
 *   headline    list row primary text, section headers
 *   body        default message and body text
 *   callout     secondary list text, button labels
 *   subheadline metadata: member count, preview lines
 *   footnote    timestamps, small captions
 *   caption     badges, tiny annotations
 */
export interface TypographyTokens extends Record<string, TextStyle> {
  display: TextStyle;
  largeTitle: TextStyle;
  title: TextStyle;
  headline: TextStyle;
  body: TextStyle;
  callout: TextStyle;
  subheadline: TextStyle;
  footnote: TextStyle;
  caption: TextStyle;
}

export const DefaultTypography: TypographyTokens = {
  display: { fontSize: 34, lineHeight: 41, fontWeight: FontWeights.bold },
  largeTitle: { fontSize: 28, lineHeight: 34, fontWeight: FontWeights.bold },
  title: { fontSize: 20, lineHeight: 25, fontWeight: FontWeights.semibold },
  headline: { fontSize: 17, lineHeight: 22, fontWeight: FontWeights.semibold },
  body: { fontSize: 17, lineHeight: 22, fontWeight: FontWeights.regular },
  callout: { fontSize: 16, lineHeight: 21, fontWeight: FontWeights.regular },
  subheadline: { fontSize: 15, lineHeight: 20, fontWeight: FontWeights.regular },
  footnote: { fontSize: 13, lineHeight: 18, fontWeight: FontWeights.regular },
  caption: { fontSize: 12, lineHeight: 16, fontWeight: FontWeights.regular }
};

/** All type style names, for exhaustive iteration. */
export const TYPOGRAPHY_TOKEN_NAMES: string[] = [
  'display',
  'largeTitle',
  'title',
  'headline',
  'body',
  'callout',
  'subheadline',
  'footnote',
  'caption'
];
