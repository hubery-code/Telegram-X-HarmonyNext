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
  'Voice message': 'Voice message',
  'Audio': 'Audio',
  'Video message': 'Video message',
  'Unknown artist': 'Unknown artist',

  // Settings specific
  'NOTIFICATIONS': 'NOTIFICATIONS',
  'DEVICES': 'DEVICES',
  'DATA AND STORAGE': 'DATA AND STORAGE',
  'APPEARANCE': 'APPEARANCE',
  'LANGUAGE': 'LANGUAGE',
  'ABOUT': 'ABOUT',
  'Notifications': 'Notifications',
  'Devices': 'Devices',
  'Active Sessions': 'Active Sessions',
  'This Device': 'This Device',
  'Terminate All Other Sessions': 'Terminate All Other Sessions',
  'Terminate Session': 'Terminate Session',
  'Terminate': 'Terminate',
  'Online': 'Online',
  'Are you sure you want to terminate this session?': 'Are you sure you want to terminate this session?',
  'Are you sure you want to terminate all other sessions?': 'Are you sure you want to terminate all other sessions?',
  'No other active sessions': 'No other active sessions',
  'All Notifications': 'All Notifications',
  'Private Chats': 'Private Chats',
  'Group Chats': 'Group Chats',
  'Channels': 'Channels',
  'Storage & Cache': 'Storage & Cache',
  'Cache size: {0}': 'Cache size: {0}',
  'Clear': 'Clear',
  'Cache cleared': 'Cache cleared',
  'Notifications enabled': 'Notifications enabled',
  'Notifications disabled': 'Notifications disabled',
  'Theme Mode': 'Theme Mode',
  'Theme mode set to {0}': 'Theme mode set to {0}',
  'Chat Text Size': 'Chat Text Size',
  'Chat text size set to {0}': 'Chat text size set to {0}',
  'This is how your messages will look.': 'This is how your messages will look.',
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
  'Chinese': 'Simplified Chinese',

  // Privacy & Security (SELF-102)
  'PRIVACY': 'PRIVACY',
  'Privacy & Security': 'Privacy & Security',
  'Last Seen': 'Last Seen',
  'Phone Number': 'Phone Number',
  'Profile Photo': 'Profile Photo',
  'Bio': 'Bio',
  'Date of Birth': 'Date of Birth',
  'Calls': 'Calls',
  'Group and Channel Invites': 'Group and Channel Invites',
  'Discoverable by Phone Number': 'Discoverable by Phone Number',
  'Everybody': 'Everybody',
  'Premium Users': 'Premium Users',
  'My Contacts': 'My Contacts',
  'Nobody': 'Nobody',
  'Custom': 'Custom',
  'Unknown': 'Unknown',
  'Tap a row to change who can see it.': 'Tap a row to change who can see it.',

  // Network proxies (PROXY-101)
  'Proxies': 'Proxies',
  'Tap to set up': 'Tap to set up',
  'Proxy Disabled': 'Disabled',
  'Do Not Use Proxy': 'Do Not Use Proxy',
  'No proxies set up yet. Tap Add Proxy below.': 'No proxies set up yet. Tap Add Proxy below.',
  'Tap a proxy to route Telegram through it.': 'Tap a proxy to route Telegram through it.',
  'Add Proxy': 'Add Proxy',
  'Edit Proxy': 'Edit Proxy',
  'Proxy Type': 'Proxy Type',
  'Server Address': 'Server Address',
  'Port': 'Port',
  'Username': 'Username',
  'Password': 'Password',
  'Secret (hex)': 'Secret (hex)',
  'Comment': 'Comment (optional)',
  'Optional': 'Optional',
  'HTTP Only': 'HTTP Only',
  'Enable Proxy': 'Enable Proxy',
  'Route Telegram traffic through this proxy now.': 'Route Telegram traffic through this proxy now.',
  'Server address required': 'Enter the proxy server address',
  'Port must be 1-65535': 'Port must be a number from 1 to 65535',
  'Secret must be hexadecimal': 'Secret must be hexadecimal, e.g. ee1234…',
  'Remove proxy': 'Remove proxy',
  'Delete this proxy configuration?': 'Delete this proxy configuration?',

  // Proxy connectivity probe and connection state (PROXY-102)
  'Connected': 'Connected',
  'Available': 'Available',
  'Checking...': 'Checking...',
  'Connecting...': 'Connecting...',
  'Waiting for network...': 'Waiting for network...',
  'Updating...': 'Updating...',
  'Error': 'Error',
  'Problems detected': 'Problems detected',

  // Automatic media download (AUTODL-101)
  'Automatic Media Download': 'Automatic Media Download',
  'Automatic download': 'Automatic download',
  'Tap to choose what downloads on its own': 'Tap to choose what downloads on its own',
  'Media still downloads when you tap it.': 'Media still downloads when you tap it.',
  'Varies by chat type': 'Varies by chat type',
  'Download nothing automatically': 'Download nothing automatically',

  // Data saver (AUTODL-102)
  'Data Saver': 'Data Saver',
  'Turn on automatically': 'Turn on automatically',
  'Mobile data': 'Mobile data',
  'Roaming': 'Roaming',
  'Mobile and roaming': 'Mobile and roaming',
  'None': 'None',
  'Media never downloads automatically while Data Saver is on.':
    'Media never downloads automatically while Data Saver is on.',
  'Videos': 'Videos',
  'Music': 'Music',
  'GIFs': 'GIFs',

  // Per-network download limits (AUTODL-103)
  'Restrict on mobile data': 'Restrict on mobile data',
  'Restrict on Wi-Fi': 'Restrict on Wi-Fi',
  'Restrict on roaming': 'Restrict on roaming',
  'No Photos': 'No Photos',
  'No Voice messages': 'No Voice messages',
  'No Video messages': 'No Video messages',
  'No Videos': 'No Videos',
  'No Files': 'No Files',
  'No Music': 'No Music',
  'No GIFs': 'No GIFs',
  'Any media exceeding {0}': 'Any media exceeding {0}',
  'Any media': 'Any media',
  'No restrictions': 'No restrictions',
  'No limit': 'No limit',
  'Off': 'Off',

  // Internal links (DEEPLINK-101)
  'This link type is not supported yet': 'This link type is not supported yet',
  'Failed to open link': 'Failed to open link'
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
  'Voice message': '语音消息',
  'Audio': '音频',
  'Video message': '视频消息',
  'Unknown artist': '未知艺术家',

  // Settings specific
  'NOTIFICATIONS': '通知',
  'DEVICES': '设备',
  'DATA AND STORAGE': '数据与存储',
  'APPEARANCE': '外观',
  'LANGUAGE': '语言',
  'ABOUT': '关于',
  'Notifications': '通知',
  'Devices': '设备',
  'Active Sessions': '活跃设备与会话',
  'This Device': '当前设备',
  'Terminate All Other Sessions': '终止所有其他会话',
  'Terminate Session': '终止会话',
  'Terminate': '终止',
  'Online': '在线',
  'Are you sure you want to terminate this session?': '确定要终止该设备的会话吗？',
  'Are you sure you want to terminate all other sessions?': '确定要终止除当前设备外的所有其他会话吗？',
  'No other active sessions': '无其他活跃会话',
  'All Notifications': '全部通知',
  'Private Chats': '私聊',
  'Group Chats': '群组',
  'Channels': '频道',
  'Storage & Cache': '存储与缓存',
  'Cache size: {0}': '缓存大小：{0}',
  'Clear': '清理',
  'Cache cleared': '缓存已清理',
  'Notifications enabled': '通知已开启',
  'Notifications disabled': '通知已关闭',
  'Theme Mode': '主题模式',
  'Theme mode set to {0}': '主题模式已设置为 {0}',
  'Chat Text Size': '聊天字号',
  'Chat text size set to {0}': '聊天字号已设置为 {0}',
  'This is how your messages will look.': '消息将按这个字号显示。',
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
  'Chinese': '简体中文',

  // Network proxies (PROXY-101)
  'Proxies': '代理',
  'Tap to set up': '点按设置',
  'Proxy Disabled': '已停用',
  'Do Not Use Proxy': '不使用代理',
  'No proxies set up yet. Tap Add Proxy below.': '尚未添加代理，可点按下方「添加代理」。',
  'Tap a proxy to route Telegram through it.': '点按某个代理即可让 Telegram 走它。',
  'Add Proxy': '添加代理',
  'Edit Proxy': '编辑代理',
  'Proxy Type': '代理类型',
  'Server Address': '服务器地址',
  'Port': '端口',
  'Username': '用户名',
  'Password': '密码',
  'Secret (hex)': '密钥（十六进制）',
  'Comment': '备注（可选）',
  'Optional': '可选',
  'HTTP Only': '仅 HTTP',
  'Enable Proxy': '启用代理',
  'Route Telegram traffic through this proxy now.': '保存后立即让 Telegram 走这个代理。',
  'Server address required': '请填写代理服务器地址',
  'Port must be 1-65535': '端口需为 1 到 65535 之间的数字',
  'Secret must be hexadecimal': '密钥需为十六进制字符串，例如 ee1234…',
  'Remove proxy': '移除代理',
  'Delete this proxy configuration?': '确定删除这条代理配置吗？',

  // Proxy connectivity probe and connection state (PROXY-102)
  'Connected': '已连接',
  'Available': '可用',
  'Checking...': '检测中...',
  'Connecting...': '连接中...',
  'Waiting for network...': '等待网络...',
  'Updating...': '同步中...',
  'Error': '连接失败',
  'Problems detected': '直连异常',

  // Automatic media download (AUTODL-101)
  'Automatic Media Download': '自动媒体下载',
  'Automatic download': '自动下载',
  'Tap to choose what downloads on its own': '点按选择在哪些会话里自动下载哪些媒体',
  'Media still downloads when you tap it.': '关闭后点按媒体仍会下载，只是不再自动下载。',
  'Varies by chat type': '按会话类型分别设置',
  'Download nothing automatically': '不自动下载',

  // Data saver (AUTODL-102)
  'Data Saver': '省流量',
  'Turn on automatically': '自动开启',
  'Mobile data': '移动网络',
  'Roaming': '漫游',
  'Mobile and roaming': '移动网络与漫游',
  'None': '不开启',
  'Media never downloads automatically while Data Saver is on.':
    '省流量生效期间，任何媒体都不会自动下载；点按仍然可以下载。',
  'Videos': '视频',
  'Music': '音乐',
  'GIFs': '动图',

  // Per-network download limits (AUTODL-103)
  'Restrict on mobile data': '移动网络限制',
  'Restrict on Wi-Fi': 'Wi-Fi 限制',
  'Restrict on roaming': '漫游限制',
  'No Photos': '不下载照片',
  'No Voice messages': '不下载语音消息',
  'No Video messages': '不下载视频消息',
  'No Videos': '不下载视频',
  'No Files': '不下载文件',
  'No Music': '不下载音乐',
  'No GIFs': '不下载动图',
  'Any media exceeding {0}': '任意媒体超过 {0}',
  'Any media': '任意媒体',
  'No restrictions': '无限制',
  'No limit': '无上限',
  'Off': '关闭',

  // Internal links (DEEPLINK-101)
  'This link type is not supported yet': '暂不支持这种链接',
  'Failed to open link': '无法打开链接'
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
