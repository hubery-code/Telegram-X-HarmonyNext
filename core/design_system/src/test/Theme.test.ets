import { describe, it, expect } from '@ohos/hypium';
import {
  resolveToken,
  tokenNames,
  TOKEN_NAMESPACES,
  createTheme,
  LightTheme,
  DarkTheme
} from '../main/ets/Theme';
import { LightColors, DarkColors, COLOR_TOKEN_NAMES } from '../main/ets/Colors';

export default function themeTest() {
  describe('ThemeTest', () => {
    it('createTheme_picksPaletteByMode', 0, () => {
      const light = createTheme('light');
      const dark = createTheme('dark');
      expect(light.colors.background).assertEqual(LightColors.background);
      expect(dark.colors.background).assertEqual(DarkColors.background);
      expect(light.mode).assertEqual('light');
      expect(dark.mode).assertEqual('dark');
    });

    it('resolveToken_everyColorNameResolvesInBothThemes', 0, () => {
      for (const name of COLOR_TOKEN_NAMES) {
        const lightValue = resolveToken(LightTheme, `colors.${name}`);
        const darkValue = resolveToken(DarkTheme, `colors.${name}`);
        expect(lightValue).assertEqual(LightColors[name]);
        expect(darkValue).assertEqual(DarkColors[name]);
      }
    });

    it('resolveToken_spacingRadiusMotionResolveToValues', 0, () => {
      expect(resolveToken(LightTheme, 'spacing.md')).assertEqual(12);
      expect(resolveToken(LightTheme, 'spacing.screenInset')).assertEqual(16);
      expect(resolveToken(LightTheme, 'radius.lg')).assertEqual(12);
      expect(resolveToken(LightTheme, 'radius.full')).assertEqual(999);
      expect(resolveToken(LightTheme, 'motion.durationNormal')).assertEqual(200);
      const curve = resolveToken(LightTheme, 'motion.curveStandard');
      const c = curve as object;
      expect(c !== null && typeof c === 'object').assertTrue();
    });

    it('resolveToken_typographyIsScaledTriple', 0, () => {
      expect(resolveToken(LightTheme, 'typography.body')).assertEqual('17/22/400');
      const big = createTheme('light', 2.0);
      expect(resolveToken(big, 'typography.body')).assertEqual('34/44/400');
      const small = createTheme('light', 0.85);
      expect(resolveToken(small, 'typography.body')).assertEqual('14.5/18.7/400');
    });

    it('resolveToken_unknownNamesReturnUndefined', 0, () => {
      expect(resolveToken(LightTheme, 'colors.nonexistent')).assertUndefined();
      expect(resolveToken(LightTheme, 'typography.nonexistent')).assertUndefined();
      expect(resolveToken(LightTheme, 'spacing.nonexistent')).assertUndefined();
      expect(resolveToken(LightTheme, 'nope.md')).assertUndefined();
      expect(resolveToken(LightTheme, 'md')).assertUndefined();
    });

    it('tokenNames_coversAllNamespaces', 0, () => {
      expect(TOKEN_NAMESPACES.length).assertEqual(5);
      for (const ns of TOKEN_NAMESPACES) {
        expect(tokenNames(ns).length > 0).assertTrue();
      }
      expect(tokenNames('unknown').length).assertEqual(0);
    });
  });
}
