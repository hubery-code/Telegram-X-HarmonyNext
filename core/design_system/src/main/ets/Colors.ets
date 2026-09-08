/**
 * Semantic color tokens. Components must reference these semantic names,
 * never raw hex values. Light and dark palettes expose the SAME token set;
 * tests assert the two sets are complete and distinct.
 *
 * Token set (keep COLOR_TOKEN_NAMES in sync when adding one):
 *   background            page / screen background
 *   backgroundSecondary grouped lists, inset areas
 *   surface               elevated cards, sheets, popups
 *   surfaceVariant        hover/pressed fills, input fields
 *   textPrimary           primary text on background/surface
 *   textSecondary         metadata, timestamps
 *   textTertiary          disabled / least-important text
 *   textOnAccent          text on accent-colored fills
 *   accent                links, primary buttons, toggles
 *   accentPressed         accent pressed/highlighted state
 *   destructive           delete, leave, report
 *   link                  URLs and inline message links
 *   chatIncoming          incoming chat bubble fill
 *   chatOutgoing          outgoing chat bubble fill
 *   chatText              bubble text (same for both directions)
 *   divider               hairline separators
 *   border                input/control outlines
 *   scrim                 modal scrim (alpha included)
 *   disabled              disabled icons/controls
 *
 * Hex format matches ArkUI '#AARRGGBB'.
 * Stored as Record (not a fixed interface) so token tables can be iterated
 * and validated exhaustively; use COLOR_TOKEN_NAMES for name completion.
 */
export interface ColorTokens extends Record<string, string> {
  background: string;
  backgroundSecondary: string;
  surface: string;
  surfaceVariant: string;
  textPrimary: string;
  textSecondary: string;
  textTertiary: string;
  textOnAccent: string;
  accent: string;
  accentPressed: string;
  destructive: string;
  link: string;
  chatIncoming: string;
  chatOutgoing: string;
  chatText: string;
  divider: string;
  border: string;
  scrim: string;
  disabled: string;
}

export const LightColors: ColorTokens = {
  background: '#FFFFFFFF',
  backgroundSecondary: '#FFF4F4F4',
  surface: '#FFFFFFFF',
  surfaceVariant: '#FFF0F0F0',
  textPrimary: '#FF000000',
  textSecondary: '#FF8E8E93',
  textTertiary: '#FFC4C4C6',
  textOnAccent: '#FFFFFFFF',
  accent: '#FF2481CC',
  accentPressed: '#FF1B6BAF',
  destructive: '#FFFF3B30',
  link: '#FF2481CC',
  chatIncoming: '#FFF1F1F4',
  chatOutgoing: '#FFD9F1FF',
  chatText: '#FF000000',
  divider: '#1F000000',
  border: '#33000000',
  scrim: '#66000000',
  disabled: '#FFBDBDC2'
};

export const DarkColors: ColorTokens = {
  background: '#FF000000',
  backgroundSecondary: '#FF1C1C1E',
  surface: '#FF1C1C1E',
  surfaceVariant: '#FF2C2C2E',
  textPrimary: '#FFFFFFFF',
  textSecondary: '#FF98989F',
  textTertiary: '#FF636366',
  textOnAccent: '#FF000000',
  accent: '#FF30A3F0',
  accentPressed: '#FF58B7F4',
  destructive: '#FFFF453A',
  link: '#FF30A3F0',
  chatIncoming: '#FF2C2C2E',
  chatOutgoing: '#FF1D3D52',
  chatText: '#FFFFFFFF',
  divider: '#33FFFFFF',
  border: '#4DFFFFFF',
  scrim: '#99000000',
  disabled: '#FF48484A'
};

/** All semantic color token names, for iteration / exhaustive checks. */
export const COLOR_TOKEN_NAMES: string[] = [
  'background',
  'backgroundSecondary',
  'surface',
  'surfaceVariant',
  'textPrimary',
  'textSecondary',
  'textTertiary',
  'textOnAccent',
  'accent',
  'accentPressed',
  'destructive',
  'link',
  'chatIncoming',
  'chatOutgoing',
  'chatText',
  'divider',
  'border',
  'scrim',
  'disabled'
];

/** '#' + 8-hex-digit string, e.g. '#FF2481CC'. */
export function isColorTokenValue(value: string): boolean {
  return /^#[0-9A-Fa-f]{8}$/.test(value);
}
