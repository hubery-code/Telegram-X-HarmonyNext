import { describe, it, expect } from '@ohos/hypium';
import { languagePreferenceFromStored, resolveLanguage, systemLanguageFromLocale } from '@tgx/core-common';
import { KEY_APP_LANGUAGE, readSettingsString, writeSettingsString } from '../../main/ets/store/SettingsStore';

/**
 * LANG-PERSIST-101：装配层的语言落盘通道。
 *
 * 这些用例钉的是**「盘读不到时怎么办」**这一半——`preferences` Kit 在宿主单测里
 * 没有 context，`initSettingsStore()` 永远不会被调用，`store` 恒为 undefined，
 * 于是这一层正好落在真机上「打开存储失败」的那条分支上：读回 null、写回 false，
 * 且绝不抛错。真机上存储打开失败时走的就是同一段代码，所以这条分支不是摆设。
 *
 * 落盘/回灌的正向往返只能靠设备取证（改完语言 → 杀进程 → 冷启动仍为该语言）。
 */
export default function settingsStoreLanguageTest(): void {
  describe('SettingsStoreLanguageTest', () => {
    it('appLanguageKey_matchesWhatTheReducerWrites', 0, () => {
      // 这个字符串是与 feature_settings 的 `SettingsReducer` 之间的契约：
      // reducer 写 `AppStorage.setOrCreate('appLanguage', pref)`，entry 观察同名键落盘。
      // 任一侧改名都不会编译报错，只会让设置静默不持久化。
      expect(KEY_APP_LANGUAGE).assertEqual('appLanguage');
    });

    it('readSettingsString_returnsNullWithoutAnOpenedStore', 0, () => {
      expect(readSettingsString(KEY_APP_LANGUAGE)).assertNull();
    });

    it('coldStartWithNoDiskValue_fallsBackToFollowSystem', 0, () => {
      // EntryAbility 的读取链就是这两步：读盘（null）→ 校验回落（'system'）。
      expect(languagePreferenceFromStored(readSettingsString(KEY_APP_LANGUAGE))).assertEqual('system');
      // 最坏情况连系统语言都读不到（locale null → 'en'）：跟随系统 = 英文，
      // 与本包改动前的表现一致，不会把界面静默变成中文。
      expect(resolveLanguage(
        languagePreferenceFromStored(readSettingsString(KEY_APP_LANGUAGE)),
        systemLanguageFromLocale(null))).assertEqual('en');
    });

    it('writeSettingsString_reportsFailureWithoutAnOpenedStore', 0, () => {
      expect(writeSettingsString(KEY_APP_LANGUAGE, 'zh')).assertFalse();
      // 写失败不许把值留在内存里：下一次读仍然是「没存过」。
      expect(readSettingsString(KEY_APP_LANGUAGE)).assertNull();
    });
  });
}
