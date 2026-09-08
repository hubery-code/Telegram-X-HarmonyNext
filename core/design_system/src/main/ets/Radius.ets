/**
 * Corner-radius tokens (vp). Use `full` for pills/avatars.
 * Stored as Record; keep RADIUS_TOKEN_NAMES in sync when adding one.
 *   none=0 sm=4 md=8 lg=12 xl=16 full=999
 */
export interface RadiusTokens extends Record<string, number> {
  none: number;
  sm: number;
  md: number;
  lg: number;
  xl: number;
  full: number;
}

export const DefaultRadius: RadiusTokens = {
  none: 0,
  sm: 4,
  md: 8,
  lg: 12,
  xl: 16,
  full: 999
};

export const RADIUS_TOKEN_NAMES: string[] = [
  'none',
  'sm',
  'md',
  'lg',
  'xl',
  'full'
];
