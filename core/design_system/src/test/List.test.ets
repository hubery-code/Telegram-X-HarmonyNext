import { describe, it, expect } from '@ohos/hypium';
import colorsTest from './Colors.test';
import fontScaleTest from './FontScale.test';
import staticTokensTest from './Tokens.test';
import themeTest from './Theme.test';
import themeManagerTest from './ThemeManager.test';

export default function testsuite() {
  colorsTest();
  fontScaleTest();
  staticTokensTest();
  themeTest();
  themeManagerTest();
}
