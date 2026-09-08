/**
 * Spacing tokens (vp). Base grid is 4vp; named steps cover all common
 * paddings, gaps and insets. Prefer these names over ad-hoc numbers.
 * Stored as Record; keep SPACING_TOKEN_NAMES in sync when adding one.
 *   none=0 hairline=2 xs=4 sm=8 md=12 lg=16 xl=20 xxl=24 huge=32
 *   screenInset — standard screen-edge padding
 *   listGap     — standard vertical gap between list rows
 */
export interface SpacingTokens extends Record<string, number> {
  none: number;
  hairline: number;
  xs: number;
  sm: number;
  md: number;
  lg: number;
  xl: number;
  xxl: number;
  huge: number;
  screenInset: number;
  listGap: number;
}

export const DefaultSpacing: SpacingTokens = {
  none: 0,
  hairline: 2,
  xs: 4,
  sm: 8,
  md: 12,
  lg: 16,
  xl: 20,
  xxl: 24,
  huge: 32,
  screenInset: 16,
  listGap: 8
};

export const SPACING_TOKEN_NAMES: string[] = [
  'none',
  'hairline',
  'xs',
  'sm',
  'md',
  'lg',
  'xl',
  'xxl',
  'huge',
  'screenInset',
  'listGap'
];
