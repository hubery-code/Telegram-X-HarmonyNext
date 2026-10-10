import { describe, it, expect } from '@ohos/hypium';
import { ThemeMode, ThemePreference, themeModeFromColorMode, themePreferenceFromStored } from '@tgx/core-design-system';
import { KEY_THEME_PREFERENCE, readSettingsString, writeSettingsString } from '../../main/ets/store/SettingsStore';

/**
 * APPSTORAGE-PAIR-101：装配层的主题落盘通道。
 *
 * 形状与 `SettingsStoreLanguageTest` 一致，钉的是「盘读不到时怎么办」这一半：
 * `preferences` Kit 在宿主单测里没有 context，`store` 恒为 undefined，这一层正好
 * 落在真机「打开存储失败」的那条分支上（读 null、写 false、不抛错）。
 *
 * 本包的缺陷恰好长在这个契约上：`SettingsReducer` 曾同时写 `'themeMode'` 与
 * `'themePreference'` 两个键，全仓零读主——改名不会编译报错，只表现为
 * 「选了深色，重启变回跟随系统」。下面的键名断言就是那道编译期没有的闸。
 */
export default function settingsStoreThemeTest(): void {
  describe('SettingsStoreThemeTest', () => {
    it('themePreferenceKey_matchesWhatTheReducerWrites', 0, () => {
      expect(KEY_THEME_PREFERENCE).assertEqual('themePreference');
    });

    it('coldStartWithNoDiskValue_fallsBackToFollowSystem', 0, () => {
      // EntryAbility.hydrateTheme 的读取链就是这两步：读盘（null）→ 校验回落（'system'）。
      expect(readSettingsString(KEY_THEME_PREFERENCE)).assertNull();
      expect(themePreferenceFromStored(readSettingsString(KEY_THEME_PREFERENCE))).assertEqual('system');
    });

    it('preferenceAndColorMode_composeIntoTheResolvedMode', 0, () => {
      // 「跟随系统 + 系统深色」必须是深色——这是 setSystemMode 拿到第一个调用者后
      // 才成立的一条；改动前系统告知什么都读不到，恒解析为浅色。
      const preference: ThemePreference = themePreferenceFromStored('system');
      const systemMode: ThemeMode = themeModeFromColorMode(0);
      expect(preference).assertEqual('system');
      expect(systemMode).assertEqual('dark');
      // 显式档位不受系统影响（同 resolveThemeMode 的口径，这里只钉住两位的输入形状）。
      expect(themePreferenceFromStored('light')).assertEqual('light');
      expect(themeModeFromColorMode(1)).assertEqual('light');
    });

    it('writeSettingsString_reportsFailureWithoutAnOpenedStore', 0, () => {
      expect(writeSettingsString(KEY_THEME_PREFERENCE, 'dark')).assertFalse();
      expect(readSettingsString(KEY_THEME_PREFERENCE)).assertNull();
    });
  });
}
