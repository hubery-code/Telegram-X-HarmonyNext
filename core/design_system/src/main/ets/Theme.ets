import { ColorTokens, LightColors, DarkColors, COLOR_TOKEN_NAMES } from './Colors';
import {
  TypographyTokens,
  TextStyle,
  DefaultTypography,
  TYPOGRAPHY_TOKEN_NAMES
} from './Typography';
import { SpacingTokens, DefaultSpacing, SPACING_TOKEN_NAMES } from './Spacing';
import { RadiusTokens, DefaultRadius, RADIUS_TOKEN_NAMES } from './Radius';
import { MotionTokens, DefaultMotion, MOTION_TOKEN_NAMES, BezierCurve } from './Motion';
import { clampFontScale, scaleTypography } from './FontScale';

export type ThemeMode = 'light' | 'dark';
export type ThemePreference = 'system' | 'light' | 'dark';

/**
 * A fully resolved theme: semantic colors for one mode, plus the base
 * (unscaled) type scale and the static spacing/radius/motion tokens.
 * Call `scaledTypography(fontScale)` to get the effective type scale.
 */
export interface Theme {
  mode: ThemeMode;
  colors: ColorTokens;
  typography: TypographyTokens;
  spacing: SpacingTokens;
  radius: RadiusTokens;
  motion: MotionTokens;
  fontScale: number;
}

/** Build a theme. `fontScale` is clamped to the supported range. */
export function createTheme(mode: ThemeMode, fontScale: number = 1.0): Theme {
  return {
    mode: mode,
    colors: mode === 'dark' ? DarkColors : LightColors,
    typography: DefaultTypography,
    spacing: DefaultSpacing,
    radius: DefaultRadius,
    motion: DefaultMotion,
    fontScale: clampFontScale(fontScale)
  };
}

export const LightTheme: Theme = createTheme('light');
export const DarkTheme: Theme = createTheme('dark');

/** Effective type scale for a theme's current font scale. */
export function scaledTypography(theme: Theme): TypographyTokens {
  return scaleTypography(theme.typography, theme.fontScale);
}

/** Effective single text style by name for a theme's current font scale. */
export function scaledTextStyle(theme: Theme, name: string): TextStyle | undefined {
  const scaled = scaledTypography(theme);
  return scaled[name];
}

export type TokenValue = string | number | BezierCurve;

/**
 * Token resolution entry: given a theme and a dotted token name, return its
 * value. Supported namespaces:
 *   colors.<name>      e.g. 'colors.background'   -> '#RRGGBBAA'
 *   typography.<name>  e.g. 'typography.body'     -> '17/22/400' (scaled)
 *   spacing.<name>     e.g. 'spacing.md'          -> vp number
 *   radius.<name>      e.g. 'radius.lg'           -> vp number
 *   motion.<name>      e.g. 'motion.durationNormal' -> ms number
 * Returns undefined for unknown names — callers decide on a fallback.
 */
export function resolveToken(theme: Theme, tokenName: string): TokenValue | undefined {
  const dot = tokenName.indexOf('.');
  if (dot <= 0) {
    return undefined;
  }
  const namespace = tokenName.substring(0, dot);
  const name = tokenName.substring(dot + 1);
  switch (namespace) {
    case 'colors':
      return colorToken(theme, name);
    case 'typography': {
      const style = scaledTextStyle(theme, name);
      if (!style) {
        return undefined;
      }
      return `${style.fontSize}/${style.lineHeight}/${style.fontWeight}`;
    }
    case 'spacing':
      return theme.spacing[name];
    case 'radius':
      return theme.radius[name];
    case 'motion':
      return theme.motion[name];
    default:
      return undefined;
  }
}

function colorToken(theme: Theme, name: string): string | undefined {
  if (COLOR_TOKEN_NAMES.indexOf(name) < 0) {
    return undefined;
  }
  return theme.colors[name];
}

/** Names of every token in a namespace, for exhaustive validation. */
export const TOKEN_NAMESPACES: string[] = ['colors', 'typography', 'spacing', 'radius', 'motion'];

export function tokenNames(namespace: string): string[] {
  switch (namespace) {
    case 'colors':
      return COLOR_TOKEN_NAMES;
    case 'typography':
      return TYPOGRAPHY_TOKEN_NAMES;
    case 'spacing':
      return SPACING_TOKEN_NAMES;
    case 'radius':
      return RADIUS_TOKEN_NAMES;
    case 'motion':
      return MOTION_TOKEN_NAMES;
    default:
      return [];
  }
}
