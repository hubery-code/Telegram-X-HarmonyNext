/**
 * Global internationalization (i18n) & language management contract (SET-103 / FEAT-SET-002 / FEAT-UI-003).
 *
 * Provides:
 * - LanguagePreference: 'system' | 'en' | 'zh'
 * - SupportedLanguage: 'en' | 'zh'
 * - Lang: runtime language manager supporting preference switching,
 *   reactive listener subscriptions, and placeholder substitution.
 * - 100% Kit-free pure ArkTS domain logic.
 */

export type LanguagePreference = 'system' | 'en' | 'zh';
export type SupportedLanguage = 'en' | 'zh';

export type LanguageListener = (language: SupportedLanguage, preference: LanguagePreference) => void;

/**
 * Pure function: resolve effective SupportedLanguage ('en' | 'zh') from preference and system language.
 */
export function resolveLanguage(
  preference: LanguagePreference,
  systemLanguage: SupportedLanguage = 'en'
): SupportedLanguage {
  if (preference === 'en' || preference === 'zh') {
    return preference;
  }
  return systemLanguage === 'zh' ? 'zh' : 'en';
}

/**
 * Pure function: replace placeholders in template string with args.
 * Supports positional tokens like {0}, {1} as well as printf tokens like %s and %d.
 */
export function formatString(template: string, args: (string | number)[]): string {
  if (args.length === 0) {
    return template;
  }
  let result: string = template;
  // 1. Replace positional placeholders {0}, {1}, etc.
  for (let i = 0; i < args.length; i++) {
    const token: string = '{' + i + '}';
    if (result.indexOf(token) !== -1) {
      result = result.split(token).join(String(args[i]));
    }
  }
  // 2. Replace %s and %d sequentially if present
  let argIdx: number = 0;
  let formatted: string = '';
  for (let i = 0; i < result.length; i++) {
    if (result[i] === '%' && i + 1 < result.length && (result[i + 1] === 's' || result[i + 1] === 'd')) {
      if (argIdx < args.length) {
        formatted += String(args[argIdx++]);
      } else {
        formatted += result.substring(i, i + 2);
      }
      i++;
    } else {
      formatted += result[i];
    }
  }
  return formatted;
}

const EN_DICTIONARY: Record<string, string> = {
  // Navigation & General
  'Settings': 'Settings',
  'General': 'General',
  'Language': 'Language',
  'Appearance': 'Appearance',
  'Theme': 'Theme',
  'Light': 'Light',
  'Dark': 'Dark',
  'System': 'System',
  'Follow System': 'Follow System',
  'Storage': 'Storage',
  'Clear Cache': 'Clear Cache',
  'Chats': 'Chats',
  'Messages': 'Messages',
  'Cancel': 'Cancel',
  'Done': 'Done',
  'Delete': 'Delete',
  'Edit': 'Edit',
  'Reply': 'Reply',
  'Copy': 'Copy',
  'Forward': 'Forward',
  'Pin': 'Pin',
  'Unpin': 'Unpin',
  'Save': 'Save',
  'Search': 'Search',
  'Send': 'Send',
  'Photos': 'Photos',
  'Files': 'Files',

  // Settings specific
  'NOTIFICATIONS': 'NOTIFICATIONS',
  'DATA AND STORAGE': 'DATA AND STORAGE',
  'APPEARANCE': 'APPEARANCE',
  'LANGUAGE': 'LANGUAGE',
  'ABOUT': 'ABOUT',
  'Notifications': 'Notifications',
  'Storage & Cache': 'Storage & Cache',
  'Cache size: {0}': 'Cache size: {0}',
  'Clear': 'Clear',
  'Cache cleared': 'Cache cleared',
  'Notifications enabled': 'Notifications enabled',
  'Notifications disabled': 'Notifications disabled',
  'Theme Mode': 'Theme Mode',
  'Theme mode set to {0}': 'Theme mode set to {0}',
  'Language set to {0}': 'Language set to {0}',
  'App Version': 'App Version',
  'Log Out': 'Log Out',
  'Are you sure you want to log out from this account?': 'Are you sure you want to log out from this account?',
  'Dismiss': 'Dismiss',
  'Telegram User': 'Telegram User',
  'Loading...': 'Loading...',
  'Logging out...': 'Logging out...',
  'English': 'English',
  'Simplified Chinese': 'Simplified Chinese',
  'Chinese': 'Simplified Chinese'
};

const ZH_DICTIONARY: Record<string, string> = {
  // Navigation & General
  'Settings': '设置',
  'General': '通用',
  'Language': '语言',
  'Appearance': '外观',
  'Theme': '主题',
  'Light': '浅色',
  'Dark': '深色',
  'System': '跟随系统',
  'Follow System': '跟随系统',
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
  'Files': '文件',

  // Settings specific
  'NOTIFICATIONS': '通知',
  'DATA AND STORAGE': '数据与存储',
  'APPEARANCE': '外观',
  'LANGUAGE': '语言',
  'ABOUT': '关于',
  'Notifications': '通知',
  'Storage & Cache': '存储与缓存',
  'Cache size: {0}': '缓存大小：{0}',
  'Clear': '清理',
  'Cache cleared': '缓存已清理',
  'Notifications enabled': '通知已开启',
  'Notifications disabled': '通知已关闭',
  'Theme Mode': '主题模式',
  'Theme mode set to {0}': '主题模式已设置为 {0}',
  'Language set to {0}': '语言已设置为 {0}',
  'App Version': '应用版本',
  'Log Out': '退出登录',
  'Are you sure you want to log out from this account?': '确定要退出当前账号吗？',
  'Dismiss': '忽略',
  'Telegram User': 'Telegram 用户',
  'Loading...': '加载中...',
  'Logging out...': '正在退出登录...',
  'English': 'English',
  'Simplified Chinese': '简体中文',
  'Chinese': '简体中文'
};

export class Lang {
  private static instance: Lang | null = null;

  private preference: LanguagePreference = 'system';
  private systemLanguage: SupportedLanguage = 'en';
  private readonly listeners: LanguageListener[] = [];
  private dictionaries: Record<SupportedLanguage, Record<string, string>>;

  constructor(
    initialPreference: LanguagePreference = 'system',
    initialSystemLanguage: SupportedLanguage = 'en'
  ) {
    this.preference = initialPreference;
    this.systemLanguage = initialSystemLanguage;
    this.dictionaries = this.createDefaultDictionaries();
  }

  static getInstance(): Lang {
    if (Lang.instance === null) {
      Lang.instance = new Lang();
    }
    return Lang.instance;
  }

  static resetInstance(): void {
    if (Lang.instance !== null) {
      Lang.instance.reset();
    }
  }

  private createDefaultDictionaries(): Record<SupportedLanguage, Record<string, string>> {
    const enCopy: Record<string, string> = {};
    const enKeys: string[] = Object.keys(EN_DICTIONARY);
    for (let i = 0; i < enKeys.length; i++) {
      enCopy[enKeys[i]] = EN_DICTIONARY[enKeys[i]];
    }

    const zhCopy: Record<string, string> = {};
    const zhKeys: string[] = Object.keys(ZH_DICTIONARY);
    for (let i = 0; i < zhKeys.length; i++) {
      zhCopy[zhKeys[i]] = ZH_DICTIONARY[zhKeys[i]];
    }

    const dicts: Record<SupportedLanguage, Record<string, string>> = {
      'en': enCopy,
      'zh': zhCopy
    };
    return dicts;
  }

  getPreference(): LanguagePreference {
    return this.preference;
  }

  setLanguage(preference: LanguagePreference): void {
    if (this.preference === preference) {
      return;
    }
    this.preference = preference;
    this.notifyListeners();
  }

  setPreference(preference: LanguagePreference): void {
    this.setLanguage(preference);
  }

  getLanguage(): SupportedLanguage {
    return resolveLanguage(this.preference, this.systemLanguage);
  }

  getSystemLanguage(): SupportedLanguage {
    return this.systemLanguage;
  }

  setSystemLanguage(language: SupportedLanguage): void {
    if (this.systemLanguage === language) {
      return;
    }
    this.systemLanguage = language;
    if (this.preference === 'system') {
      this.notifyListeners();
    }
  }

  formatByKey(key: string, lang: SupportedLanguage, args: (string | number)[]): string {
    const dict = this.dictionaries[lang];
    let template: string | undefined = dict !== undefined ? dict[key] : undefined;
    if (template === undefined) {
      // Fallback to English dictionary
      template = this.dictionaries['en'][key];
    }
    if (template === undefined) {
      // Fallback to raw key
      template = key;
    }
    return formatString(template, args);
  }

  getString(key: string, ...args: (string | number)[]): string {
    const currentLang: SupportedLanguage = this.getLanguage();
    return this.formatByKey(key, currentLang, args);
  }

  t(key: string, ...args: (string | number)[]): string {
    return this.getString(key, ...args);
  }

  registerTranslations(lang: SupportedLanguage, dict: Record<string, string>): void {
    const target: Record<string, string> = this.dictionaries[lang];
    if (target === undefined) {
      return;
    }
    const keys: string[] = Object.keys(dict);
    for (let i = 0; i < keys.length; i++) {
      target[keys[i]] = dict[keys[i]];
    }
  }

  subscribe(listener: LanguageListener, notifyImmediately: boolean = false): () => void {
    this.listeners.push(listener);
    if (notifyImmediately) {
      listener(this.getLanguage(), this.preference);
    }
    return (): void => {
      this.unsubscribe(listener);
    };
  }

  unsubscribe(listener: LanguageListener): void {
    const idx: number = this.listeners.indexOf(listener);
    if (idx >= 0) {
      this.listeners.splice(idx, 1);
    }
  }

  reset(): void {
    this.preference = 'system';
    this.systemLanguage = 'en';
    this.listeners.length = 0;
    this.dictionaries = this.createDefaultDictionaries();
  }

  private notifyListeners(): void {
    const effectiveLang: SupportedLanguage = this.getLanguage();
    const pref: LanguagePreference = this.preference;
    const snapshot: LanguageListener[] = this.listeners.slice();
    for (let i = 0; i < snapshot.length; i++) {
      snapshot[i](effectiveLang, pref);
    }
  }
}

export const lang: Lang = Lang.getInstance();
