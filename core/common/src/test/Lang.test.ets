import { describe, it, expect } from '@ohos/hypium';
import {
  Lang,
  LanguagePreference,
  SupportedLanguage,
  formatString,
  lang,
  resolveLanguage
} from '../main/ets/Lang';

export default function langTest(): void {
  describe('LangTest', () => {
    it('resolveLanguage_resolvesSystemAndExplicitPreferences', 0, () => {
      expect(resolveLanguage('system', 'en')).assertEqual('en');
      expect(resolveLanguage('system', 'zh')).assertEqual('zh');
      expect(resolveLanguage('en', 'zh')).assertEqual('en');
      expect(resolveLanguage('zh', 'en')).assertEqual('zh');
    });

    it('formatString_replacesPositionalPlaceholders', 0, () => {
      expect(formatString('Hello', [])).assertEqual('Hello');
      expect(formatString('Hello {0}!', ['World'])).assertEqual('Hello World!');
      expect(formatString('{0} has {1} items and {0} files', ['Alice', 5])).assertEqual('Alice has 5 items and Alice files');
      expect(formatString('Cache: {0}', [1024])).assertEqual('Cache: 1024');
    });

    it('formatString_replacesPrintfPlaceholders', 0, () => {
      expect(formatString('User %s has %d points', ['Bob', 42])).assertEqual('User Bob has 42 points');
    });

    it('formatString_handlesMissingOrExtraArgsGracefully', 0, () => {
      expect(formatString('Hello {0} and {1}', ['Alice'])).assertEqual('Hello Alice and {1}');
      expect(formatString('Hello %s and %s', ['Alice'])).assertEqual('Hello Alice and %s');
      expect(formatString('Hello {0}', ['Alice', 'Bob', 'Charlie'])).assertEqual('Hello Alice');
    });

    it('singleton_getInstance_returnsSameInstance', 0, () => {
      const instance1 = Lang.getInstance();
      const instance2 = Lang.getInstance();
      expect(instance1 === instance2).assertTrue();
      expect(instance1 === lang).assertTrue();
    });

    it('initialState_defaultsToSystemPreferenceAndEnglish', 0, () => {
      Lang.getInstance().reset();
      expect(Lang.getInstance().getPreference()).assertEqual('system');
      expect(Lang.getInstance().getLanguage()).assertEqual('en');
    });

    it('setLanguage_updatesPreferenceAndEffectiveLanguage', 0, () => {
      Lang.getInstance().reset();
      Lang.getInstance().setLanguage('zh');
      expect(Lang.getInstance().getPreference()).assertEqual('zh');
      expect(Lang.getInstance().getLanguage()).assertEqual('zh');

      Lang.getInstance().setLanguage('en');
      expect(Lang.getInstance().getPreference()).assertEqual('en');
      expect(Lang.getInstance().getLanguage()).assertEqual('en');

      Lang.getInstance().setPreference('system');
      expect(Lang.getInstance().getPreference()).assertEqual('system');
      expect(Lang.getInstance().getLanguage()).assertEqual('en');
    });

    it('setSystemLanguage_affectsLanguageWhenPreferenceIsSystem', 0, () => {
      Lang.getInstance().reset();
      expect(Lang.getInstance().getLanguage()).assertEqual('en');

      Lang.getInstance().setSystemLanguage('zh');
      expect(Lang.getInstance().getSystemLanguage()).assertEqual('zh');
      expect(Lang.getInstance().getLanguage()).assertEqual('zh');

      Lang.getInstance().setLanguage('en');
      expect(Lang.getInstance().getLanguage()).assertEqual('en');

      Lang.getInstance().setLanguage('system');
      expect(Lang.getInstance().getLanguage()).assertEqual('zh');
    });

    it('getString_and_t_translateEnglishAndChinese', 0, () => {
      Lang.getInstance().reset();
      Lang.getInstance().setLanguage('en');
      expect(Lang.getInstance().getString('Settings')).assertEqual('Settings');
      expect(Lang.getInstance().t('Appearance')).assertEqual('Appearance');
      expect(Lang.getInstance().t('Cancel')).assertEqual('Cancel');

      Lang.getInstance().setLanguage('zh');
      expect(Lang.getInstance().getString('Settings')).assertEqual('设置');
      expect(Lang.getInstance().t('Appearance')).assertEqual('外观');
      expect(Lang.getInstance().t('Cancel')).assertEqual('取消');
    });

    it('presetDictionary_containsRequiredVocabulary', 0, () => {
      Lang.getInstance().reset();
      Lang.getInstance().setLanguage('zh');

      const requiredEntries: Record<string, string> = {
        'Settings': '设置',
        'General': '通用',
        'Language': '语言',
        'Appearance': '外观',
        'Theme': '主题',
        'Light': '浅色',
        'Dark': '深色',
        'System': '跟随系统',
        'Storage': '存储',
        'Clear Cache': '清理缓存',
        'Chats': '聊天',
        'Messages': '消息',
        'Cancel': '取消',
        'Done': '完成',
        'Delete': '删除',
        'Edit': '编辑',
        'Reply': '回复',
        'Copy': '复制',
        'Forward': '转发',
        'Pin': '置顶',
        'Unpin': '取消置顶',
        'Save': '保存',
        'Search': '搜索',
        'Send': '发送',
        'Photos': '照片',
        'Files': '文件'
      };

      const keys: string[] = Object.keys(requiredEntries);
      for (let i = 0; i < keys.length; i++) {
        const key: string = keys[i];
        const expected: string = requiredEntries[key];
        expect(Lang.getInstance().t(key)).assertEqual(expected);
      }
    });

    it('getString_supportsPlaceholderFormatting', 0, () => {
      Lang.getInstance().reset();
      Lang.getInstance().setLanguage('en');
      expect(Lang.getInstance().t('Cache size: {0}', '24.5 MB')).assertEqual('Cache size: 24.5 MB');
      expect(Lang.getInstance().t('Theme mode set to {0}', 'dark')).assertEqual('Theme mode set to dark');

      Lang.getInstance().setLanguage('zh');
      expect(Lang.getInstance().t('Cache size: {0}', '24.5 MB')).assertEqual('缓存大小：24.5 MB');
      expect(Lang.getInstance().t('Theme mode set to {0}', 'dark')).assertEqual('主题模式已设置为 dark');
      expect(Lang.getInstance().t('Language set to {0}', 'zh')).assertEqual('语言已设置为 zh');
    });

    it('getString_fallsBackToKeyWhenUntranslated', 0, () => {
      Lang.getInstance().reset();
      Lang.getInstance().setLanguage('zh');
      expect(Lang.getInstance().t('Custom Unregistered Key')).assertEqual('Custom Unregistered Key');
      expect(Lang.getInstance().t('Item count: {0}', 10)).assertEqual('Item count: 10');
    });

    it('registerTranslations_allowsCustomExtensions', 0, () => {
      Lang.getInstance().reset();
      Lang.getInstance().setLanguage('zh');
      const customZh: Record<string, string> = {
        'Beta Feature': '测试功能'
      };
      Lang.getInstance().registerTranslations('zh', customZh);
      expect(Lang.getInstance().t('Beta Feature')).assertEqual('测试功能');
    });

    it('subscribe_notifiesListenersOnLanguageChange', 0, () => {
      Lang.getInstance().reset();
      let notifiedLang: SupportedLanguage = 'en';
      let notifiedPref: LanguagePreference = 'system';
      let callCount: number = 0;

      const unsubscribe = Lang.getInstance().subscribe((lang: SupportedLanguage, pref: LanguagePreference): void => {
        notifiedLang = lang;
        notifiedPref = pref;
        callCount++;
      });

      Lang.getInstance().setLanguage('zh');
      expect(callCount).assertEqual(1);
      expect(notifiedLang).assertEqual('zh');
      expect(notifiedPref).assertEqual('zh');

      // No-op when setting identical language
      Lang.getInstance().setLanguage('zh');
      expect(callCount).assertEqual(1);

      Lang.getInstance().setLanguage('en');
      expect(callCount).assertEqual(2);
      expect(notifiedLang).assertEqual('en');
      expect(notifiedPref).assertEqual('en');

      unsubscribe();
      Lang.getInstance().setLanguage('zh');
      expect(callCount).assertEqual(2);
    });

    it('subscribe_supportsNotifyImmediately', 0, () => {
      Lang.getInstance().reset();
      Lang.getInstance().setLanguage('zh');

      let called: boolean = false;
      let initialLang: string = '';
      const unsubscribe = Lang.getInstance().subscribe((lang: SupportedLanguage): void => {
        called = true;
        initialLang = lang;
      }, true);

      expect(called).assertTrue();
      expect(initialLang).assertEqual('zh');
      unsubscribe();
    });

    it('unsubscribe_viaMethodWorks', 0, () => {
      Lang.getInstance().reset();
      let callCount: number = 0;
      const listener = (_lang: SupportedLanguage, _pref: LanguagePreference): void => {
        callCount++;
      };

      Lang.getInstance().subscribe(listener);
      Lang.getInstance().setLanguage('zh');
      expect(callCount).assertEqual(1);

      Lang.getInstance().unsubscribe(listener);
      Lang.getInstance().setLanguage('en');
      expect(callCount).assertEqual(1);
    });

    it('reset_restoresDefaultsAndClearsListeners', 0, () => {
      Lang.getInstance().reset();
      let called: boolean = false;
      Lang.getInstance().subscribe((): void => {
        called = true;
      });

      Lang.getInstance().setLanguage('zh');
      expect(called).assertTrue();

      called = false;
      Lang.getInstance().reset();
      expect(Lang.getInstance().getPreference()).assertEqual('system');
      expect(Lang.getInstance().getLanguage()).assertEqual('en');

      // Previous listeners cleared
      Lang.getInstance().setLanguage('zh');
      expect(called).assertFalse();
    });
  });
}
