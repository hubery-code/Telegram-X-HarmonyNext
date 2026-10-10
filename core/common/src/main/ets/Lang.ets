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
/**
 * 时制档（I18N-DATE-102）。和 `SupportedLanguage` / `LanguagePreference` 放在一起，
 * 是因为它是**运行态档位**而不是日期形态：档位由装配层从系统取，形态只在 `DateFormat`。
 */
export type HourClock = '24h' | '12h';

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
 * Pure function: 系统 locale（`i18n.System.getSystemLanguage()` 的 `'zh-Hans'` /
 * `'en-US'` / `'fr-FR'` 这类 BCP-47 串）→ 本端支持的语言档。
 *
 * 只按**语言子标签**判定，不看地区：`zh` / `zh-Hans` / `zh-Hant-HK` / `ZH-CN` 都归 `zh`
 * （词典只有两本，地区差异本端还没建模）；其余与缺失值一律 `en`，与「读不到系统语言时
 * 不许让界面变成半中半英」的回落方向一致。
 */
export function systemLanguageFromLocale(locale: string | null | undefined): SupportedLanguage {
  if (locale === null || locale === undefined) {
    return 'en';
  }
  return locale.toLowerCase().startsWith('zh') ? 'zh' : 'en';
}

/**
 * Pure function: 盘上读回的**偏好**串 → 合法 `LanguagePreference`。
 *
 * 区分「没存过」与「存了脏值」两种情况都回落 `system` —— 那正是 Android 首装的默认档。
 * 绝不能把脏值当 `'en'` 处理：`'en'` 是一条**显式**偏好，会把「跟随系统」这条
 * 语义永久压掉，用户下次换系统语言就不再跟随了。
 */
export function languagePreferenceFromStored(stored: string | null | undefined): LanguagePreference {
  if (stored === 'system' || stored === 'en' || stored === 'zh') {
    return stored;
  }
  return 'system';
}

/**
 * Pure function: 系统的 24 小时制开关（`i18n.System.is24HourClock()` 的布尔）→ 本端时制档。
 *
 * **只有明确读到 `false` 才给 12 小时制**：`undefined` / `null`（Kit 调用抛错被上层收敛成
 * 缺失）一律回落 `'24h'` —— 那既是本仓此前的行为，也是 `zh-Hans` locale 的默认档，
 * 一次读取失败不该把界面切成 12 小时制。
 */
export function hourClockFromFlag(is24Hour: boolean | null | undefined): HourClock {
  return is24Hour === false ? '12h' : '24h';
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
  'Pinned message': 'Pinned message',
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
  'STICKERS AND EMOJI': 'STICKERS AND EMOJI',
  'APPEARANCE': 'APPEARANCE',
  'LANGUAGE': 'LANGUAGE',
  'ABOUT': 'ABOUT',
  'Notifications': 'Notifications',
  'Devices': 'Devices',
  'Active Sessions': 'Active Sessions',
  '{0} active sessions': '{0} active sessions',
  '{0} active session': '{0} active session',
  'This Device': 'This Device',
  'Terminate All Other Sessions': 'Terminate All Other Sessions',
  'Terminate Session': 'Terminate Session',
  'Terminate': 'Terminate',
  'Online': 'Online',
  'Just now': 'Just now',
  '{0} min ago': '{0} min ago',
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
  'My Contacts': 'My Contacts',
  'Nobody': 'Nobody',
  'Custom': 'Custom',
  'Unknown': 'Unknown',
  'Tap a row to change who can see it.': 'Tap a row to change who can see it.',

  // Privacy detail page (PRIVACY-101)
  'My Contacts & Premium': 'My Contacts & Premium',
  'Add Exceptions': 'Add Exceptions',
  'Always Allow': 'Always Allow',
  'Never Allow': 'Never Allow',
  'Always Share With': 'Always Share With',
  'Never Share With': 'Never Share With',
  'Add Users': 'Add Users',
  '{0} User': '{0} User',
  '{0} Users': '{0} Users',
  'No Contacts Yet': 'No Contacts Yet',
  'Custom Share Settings Help': 'People who are always allowed or never allowed win over the setting above.',

  // Extra toggle rows on the privacy detail page (PRIVACY-103)
  'Telegram Premium subscribers': 'Telegram Premium subscribers',
  'Allow Premium Invite Desc':
    'Always allow users with a Telegram Premium subscription to add you to groups and channels.',
  'Hide Read Time': 'Hide Read Time',
  'Hide Read Time Desc':
    'Hide the time when you read messages from people who can\'t see your last seen. If you turn this on, their read time will also be hidden from you. This setting does not affect group chats.',

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

  // Why a proxy probe failed (PROXY-103). These are our own sentences, classified
  // from the TDLib error — the raw text never reaches the screen.
  'Address not found': 'Address not found',
  'Connection refused': 'Connection refused',
  'Connection timed out': 'Connection timed out',
  'Network unavailable': 'Network unavailable',
  'Proxy handshake failed': 'Proxy handshake failed',
  'Proxy settings rejected': 'Proxy settings rejected',
  'Proxy error': 'Proxy error',

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

  // Stickers and emoji (TGS-104)
  'Loop Animated Stickers': 'Loop Animated Stickers',
  'Animated stickers keep playing.': 'Animated stickers keep playing.',
  'Animated stickers play once and stop.': 'Animated stickers play once and stop.',

  // Internal links (DEEPLINK-101)
  'This link type is not supported yet': 'This link type is not supported yet',
  'Failed to open link': 'Failed to open link',
  'Sticker set: %s': 'Sticker set: %s',

  // Link confirmations (DEEPLINK-102)
  'Join': 'Join',
  'Request to Join': 'Request to Join',
  '{0} members': '{0} members',
  '{0} subscribers': '{0} subscribers',
  '1 member': '1 member',
  '1 subscriber': '1 subscriber',
  'Owner': 'Owner',
  'Admin': 'Admin',
  '{0} file': '{0} file',
  '{0} files': '{0} files',
  'Connect to This Proxy?': 'Connect to This Proxy?',
  'Server': 'Server',
  'This will add a proxy server to your configuration.': 'This will add a proxy server to your configuration.',
  'This proxy uses a secret, make sure you trust the link source.': 'This proxy uses a secret, make sure you trust the link source.',
  'Enable': 'Enable',
  'Save for Later': 'Save for Later',
  'Join request sent': 'Join request sent',
  'Proxy enabled': 'Proxy enabled',
  'Proxy saved for later use': 'Proxy saved for later use',

  // Screen lock (APPLOCK-101)
  'Screen Lock': 'Screen Lock',
  'Passcode': 'Passcode',
  'Auto-Lock': 'Auto-Lock',
  'Show Typed Passcode': 'Show Typed Passcode',
  'Change Passcode': 'Change Passcode',
  'On': 'On',
  'Immediately': 'Immediately',
  'After 1 minute': 'After 1 minute',
  'After 5 minutes': 'After 5 minutes',
  'After 1 hour': 'After 1 hour',
  'After 5 hours': 'After 5 hours',
  'Never': 'Never',
  'Enter a new passcode': 'Enter a new passcode',
  'Repeat the passcode': 'Repeat the passcode',
  'Enter your current passcode': 'Enter your current passcode',
  'Enter your passcode': 'Enter your passcode',
  'Too many attempts. Try again in {0}s': 'Too many attempts. Try again in {0}s',
  'The passcode is stored in this device secure storage and never synced.': 'The passcode is stored in this device secure storage and never synced.',
  'PasscodeNoticeInvalid': 'Passcode must be 4 digits.',
  'PasscodeNoticeMismatch': 'The two passcodes did not match. Start again.',
  'PasscodeNoticeSaved': 'Passcode set.',
  'PasscodeNoticeRemoved': 'Passcode removed.',
  'PasscodeErrorWrong': 'Wrong passcode. Try again.',
  'PasscodeErrorStoreUnavailable': 'Secure storage is unavailable on this device.',
  'PasscodeErrorCorrupt': 'Stored passcode is unreadable. Reset it to continue.',

  // UI 层离散文案（I18N-LITERAL-101）：页面/组件里此前写死的中文。
  // 命名口径与上面一致 —— 英文原文当 key，守卫 `check_i18n_literals.py` 要求两本词典 key 全等。
  'New Message': 'New Message',
  'Retry': 'Retry',
  'Confirm': 'Confirm',
  'Leave': 'Leave',
  'Report': 'Report',
  'Clear History': 'Clear History',
  'Clear Recent': 'Clear Recent',
  'Delete Chat': 'Delete Chat',
  'Leave Channel': 'Leave Channel',
  'Leave Group': 'Leave Group',
  'Linked Channel': 'Linked Channel',
  'Clear history?': 'Clear history?',
  'Delete this chat?': 'Delete this chat?',
  'Report this chat?': 'Report this chat?',
  'Leave this channel?': 'Leave this channel?',
  'Leave this group?': 'Leave this group?',
  'Mute': 'Mute',
  'Unmute': 'Unmute',
  'Enable Notifications': 'Enable Notifications',
  'Join Channel': 'Join Channel',
  '{0} comments': '{0} comments',
  'Voice messages are not allowed in this chat': 'Voice messages are not allowed in this chat',
  'Comments': 'Comments',
  'Comments ({0})': 'Comments ({0})',
  'Original post': 'Original post',
  'No comments yet. Leave the first one!': 'No comments yet. Leave the first one!',
  'Leave a comment...': 'Leave a comment...',
  'Send Sticker': 'Send Sticker',
  'Add to Favorites': 'Add to Favorites',
  'Remove from Favorites': 'Remove from Favorites',
  'Remove from Recent': 'Remove from Recent',
  'View Sticker Set': 'View Sticker Set',
  'View {0} more': 'View {0} more',
  'Trending Sticker Sets': 'Trending Sticker Sets',
  '{0} stickers': '{0} stickers',
  'Add': 'Add',
  'Added': 'Added',
  'Adding…': 'Adding…',
  'Removing…': 'Removing…',
  'Loading sticker set…': 'Loading sticker set…',
  'Failed to load sticker set': 'Failed to load sticker set',
  'No installed sticker sets': 'No installed sticker sets',
  'Tap "Add" on a trending pack to install it. Installed packs show up here.':
    'Tap "Add" on a trending pack to install it. Installed packs show up here.',
  'Sticker Set Details': 'Sticker Set Details',
  'Failed to load the sticker set. Please try again later.':
    'Failed to load the sticker set. Please try again later.',
  'Fetching info…': 'Fetching info…',
  'Installed': 'Installed',
  'Not installed': 'Not installed',
  '{0} stickers · {1}': '{0} stickers · {1}',
  'Add Sticker Set': 'Add Sticker Set',
  'Remove Sticker Set': 'Remove Sticker Set',
  'Add {0} stickers': 'Add {0} stickers',
  'Media': 'Media',
  'Links': 'Links',
  'Voice': 'Voice',
  'Groups': 'Groups',
  'Failed to load': 'Failed to load',
  'Tap the tab above to retry.': 'Tap the tab above to retry.',
  'No Media Yet': 'No Media Yet',
  'Share photos and videos in this chat and access them on all your devices.':
    'Share photos and videos in this chat and access them on all your devices.',
  'No Files Yet': 'No Files Yet',
  'Share files in this chat and access them on all your devices.':
    'Share files in this chat and access them on all your devices.',
  'No Links Yet': 'No Links Yet',
  'Share links in this chat and access them on all your devices.':
    'Share links in this chat and access them on all your devices.',
  'No Music Yet': 'No Music Yet',
  'Share audio files in this chat and access them on all your devices.':
    'Share audio files in this chat and access them on all your devices.',
  'No Voice Messages Yet': 'No Voice Messages Yet',
  'Share voice messages in this chat and access them on all your devices.':
    'Share voice messages in this chat and access them on all your devices.',
  'No Common Groups': 'No Common Groups',
  'Groups you have in common with this user will appear here.':
    'Groups you have in common with this user will appear here.',
  'Loading more…': 'Loading more…',
  'Load More': 'Load More',
  'Send Message': 'Send Message',
  'Start Secret Chat': 'Start Secret Chat',
  'Block User': 'Block User',
  'Block User (not loaded)': 'Block User (not loaded)',
  'Unblock User': 'Unblock User',
  'Phone': 'Phone',
  'Data and Storage': 'Data and Storage',
  'EmptyValue': '<empty>',
  'Logs out all devices except for this one.': 'Logs out all devices except for this one.',
  // 账号切换器（DRAWER-101 写调用点时用了四个从没进词典的 key，R2 守卫当场抓到）
  'Switch Account': 'Switch Account',
  'Close': 'Close',
  'Active': 'Active',
  'Add Account': 'Add Account',

  // A11Y-101 BEGIN EN
  // Accessibility labels for icon-only controls (A11Y-101). Spoken by the screen reader, never shown, so they read as a phrase.
  'A11yBack': 'Back',
  'A11yClose': 'Close',
  'A11yMore': 'More options',
  'A11ySearch': 'Search',
  'A11yCall': 'Voice call',
  'A11yMenu': 'Menu',
  'A11ySettings': 'Settings',
  'A11ySwitchAccount': 'Switch account',
  'A11yOpenProfile': 'Open {0} profile',
  'A11yNewChat': 'New message',
  'A11yAttach': 'Attach',
  'A11yEmoji': 'Emoji',
  'A11yKeyboard': 'Switch to keyboard',
  'A11ySend': 'Send message',
  'A11yRecordVoice': 'Hold to record voice message',
  'A11yCancelRecording': 'Cancel recording',
  'A11ySendRecording': 'Send voice message',
  'A11yDeleteChar': 'Delete character',
  'A11yShowPassword': 'Show password',
  'A11yHidePassword': 'Hide password',
  'A11yForward': 'Forward',
  'A11yPlay': 'Play',
  'A11yPause': 'Pause',
  'A11yDownload': 'Download',
  'A11yCancelDownload': 'Cancel download',
  'A11yCancelUpload': 'Cancel upload',
  'A11yRetrySend': 'Retry sending',
  'A11yOpenMedia': 'Open photo',
  'A11yOpenFile': 'Open file',
  'A11yClosePinned': 'Hide pinned message',
  'A11ySelectMessage': 'Select message',
  'A11yDeselectMessage': 'Deselect message',
  'A11yMuteSound': 'Mute sound',
  'A11yUnmuteSound': 'Unmute sound',
  'A11yBoardTabEmoji': 'Emoji',
  'A11yBoardTabStickers': 'Stickers',
  'A11yBoardTabGif': 'GIFs',
  'A11yBoardCell': 'Sticker {0}',
  'A11yBoardPack': 'Sticker pack {0}',
  'A11yEdit': 'Edit',
  'A11yDelete': 'Delete',
  'A11yAddContact': 'Add contact',
  // A11Y-101 END EN
  // I18N-LITERAL-102：视图层写死英文接回词典（抽屉菜单行、登录流程、输入栏占位）。
  // 'Message' 与 'Message User' 英文同形、中文不同形：前者是名词（输入栏占位与回复摘要
  // 兜底），后者是资料页那颗「发消息」按钮的动词，共用一条 key 只会让其中一侧翻得别扭。
  'Contacts': 'Contacts',
  'Saved Messages': 'Saved Messages',
  'Invite Friends': 'Invite Friends',
  'Help': 'Help',
  'Night Mode': 'Night Mode',
  'Continue': 'Continue',
  'Signing in...': 'Signing in...',
  'Message': 'Message',
  'Message User': 'Message',
  // Index 的 toast 助手改名 tr -> t 后才进入 R2 射程，暴露出这条 key 从来没进词典。
  'Bot @%s selected': 'Bot @%s selected',
  'Verifying...': 'Verifying...',
  'Submit': 'Submit',
  'All': 'All',
  // I18N-LITERAL-102 END EN
  // I18N-LITERAL-103：coordinator/model 侧展示的文案（在线状态、群头部人数、会话列表预览占位、
  // 共享媒体分节与类型名、发言权否决句）。这些串此前直接在数据层拼好，中英各写死一处。
  'online': 'online',
  'offline': 'offline',
  'last seen recently': 'last seen recently',
  'last seen within a week': 'last seen within a week',
  'last seen within a month': 'last seen within a month',
  'Service Notifications': 'Service Notifications',
  '{0} online': '{0} online',
  '{0}, {1} online': '{0}, {1} online',
  'Me': 'Me',
  'User': 'User',
  'Channel': 'Channel',
  'Supergroup': 'Supergroup',
  'Group': 'Group',
  'Private Chat': 'Private Chat',
  'Today': 'Today',
  'Yesterday': 'Yesterday',
  'Last Week': 'Last Week',
  'Sunday': 'Sunday',
  'Monday': 'Monday',
  'Tuesday': 'Tuesday',
  'Wednesday': 'Wednesday',
  'Thursday': 'Thursday',
  'Friday': 'Friday',
  'Saturday': 'Saturday',
  '[Photo]': '[Photo]',
  '[Video]': '[Video]',
  '[GIF]': '[GIF]',
  '[Audio]': '[Audio]',
  '[Voice message]': '[Voice message]',
  '[Voice]': '[Voice]',
  '[Video message]': '[Video message]',
  '[Document]': '[Document]',
  '[Sticker]': '[Sticker]',
  '{0} Sticker': '{0} Sticker',
  '[Location]': '[Location]',
  '[Venue]': '[Venue]',
  '[Contact]': '[Contact]',
  '[Poll]': '[Poll]',
  '[Call]': '[Call]',
  '[Game]': '[Game]',
  'Recently Used': 'Recently Used',
  'Favorites': 'Favorites',
  'This chat does not allow sending photos': 'This chat does not allow sending photos',
  'This chat does not allow sending camera photos or videos': 'This chat does not allow sending camera photos or videos',
  'This chat does not allow sending videos': 'This chat does not allow sending videos',
  'This chat does not allow sending files': 'This chat does not allow sending files',
  'This chat does not allow creating polls': 'This chat does not allow creating polls',
  'This chat does not allow sending stickers': 'This chat does not allow sending stickers',
  'This chat does not allow sending GIFs': 'This chat does not allow sending GIFs',
  'This chat does not allow sending this content': 'This chat does not allow sending this content',
  // 动作结果提示（coordinator/reducer 里 `showToast(...)` 与 `CopyTextToClipboard` 的文案）。
  'Mute failed': 'Mute failed',
  'Unmute failed': 'Unmute failed',
  'Muted': 'Muted',
  'Failed to clear history': 'Failed to clear history',
  'Chat history cleared': 'Chat history cleared',
  'Failed to delete chat': 'Failed to delete chat',
  'Chat deleted': 'Chat deleted',
  'Failed to report': 'Failed to report',
  'Reported': 'Reported',
  'Failed to leave': 'Failed to leave',
  'Left the chat': 'Left the chat',
  'Vote failed': 'Vote failed',
  'Microphone permission required': 'Microphone permission required',
  'Cannot start recording': 'Cannot start recording',
  'Recording failed, not sent': 'Recording failed, not sent',
  'Downloading voice message…': 'Downloading voice message…',
  'Voice file unavailable': 'Voice file unavailable',
  'Downloading audio…': 'Downloading audio…',
  'Cannot start the secret chat': 'Cannot start the secret chat',
  'Operation failed, please try again later': 'Operation failed, please try again later',
  'Voice file cannot be read': 'Voice file cannot be read',
  'Copied to clipboard': 'Copied to clipboard',
  'Link copied': 'Link copied',
  'No comment thread': 'No comment thread',
  'Network error': 'Network error',
  'Channel post': 'Channel post',
  'Channel message': 'Channel message',
  'Sticker': 'Sticker',
  'Personal': 'Personal',
  'Unread': 'Unread',
  // 引用条（回复预览）与不支持消息的占位标签：数据层按内容类型给短标签，视图层直接渲染。
  'Photo': 'Photo',
  'Video': 'Video',
  'GIF': 'GIF',
  'Document': 'Document',
  '[Unsupported message]': '[Unsupported message]',
  // I18N-LITERAL-103 END EN
  // I18N-LITERAL-104 BEGIN EN —— 登录线七页
  'Authorization Failed': 'Authorization Failed',
  'An unexpected error occurred.': 'An unexpected error occurred.',
  'Try Again': 'Try Again',
  'Enter Code': 'Enter Code',
  'We sent an SMS with the code to {0}': 'We sent an SMS with the code to {0}',
  'Wrong number?': 'Wrong number?',
  'Enter {0}-digit code': 'Enter {0}-digit code',
  'Resend code': 'Resend code',
  'Resend code in {0}': 'Resend code in {0}',
  'Two-Step Verification': 'Two-Step Verification',
  'Your account is protected with an additional password.': 'Your account is protected with an additional password.',
  'Enter your password': 'Enter your password',
  'Hint: {0}': 'Hint: {0}',
  'Your Phone': 'Your Phone',
  'Please confirm your country code and enter your phone number.': 'Please confirm your country code and enter your phone number.',
  'Phone number': 'Phone number',
  'Log in with QR code': 'Log in with QR code',
  'Open Telegram on another device, then go to Settings > Devices > Link Desktop Device and scan this code.': 'Open Telegram on another device, then go to Settings > Devices > Link Desktop Device and scan this code.',
  'Preparing a secure QR code...': 'Preparing a secure QR code...',
  'The code refreshes automatically. Keep this screen open while scanning.': 'The code refreshes automatically. Keep this screen open while scanning.',
  'Log in with QR code instead': 'Log in with QR code instead',
  'Your Name': 'Your Name',
  'Enter your name to complete registration.': 'Enter your name to complete registration.',
  'First name (required)': 'First name (required)',
  'Last name (optional)': 'Last name (optional)',
  'Registering...': 'Registering...',
  'Complete': 'Complete',
  // I18N-LITERAL-104 —— 聊天页：气泡脚注、回复/编辑条、投票创建器、下载与空态
  // 自己发出的消息在预览条/大图廊里的主播昵称（TGX 用 "You"，中文界面该是「你」）。
  'You': 'You',
  'edited': 'edited',
  '{0} selected': '{0} selected',
  'Failed · Tap to retry': 'Failed · Tap to retry',
  'Edit Message': 'Edit Message',
  'Reply to {0}': 'Reply to {0}',
  'Resend': 'Resend',
  'Copy Link': 'Copy Link',
  'Attach': 'Attach',
  'Create Poll': 'Create Poll',
  'Question': 'Question',
  'Option {0}': 'Option {0}',
  '＋ Add Option': '＋ Add Option',
  'Anonymous Poll': 'Anonymous Poll',
  'Multiple Answers': 'Multiple Answers',
  'Create': 'Create',
  'Add a question and 2 options': 'Add a question and 2 options',
  'Download Video': 'Download Video',
  'Download GIF': 'Download GIF',
  'Loading messages...': 'Loading messages...',
  'No messages yet': 'No messages yet',
  'Failed to load messages': 'Failed to load messages',
  'Search in chat...': 'Search in chat...',
  '[Message]': '[Message]',
  'Tap to load': 'Tap to load',
  // I18N-LITERAL-104 —— 表情/GIF 板与转发选择器
  'Recent': 'Recent',
  'No Recent Emojis': 'No Recent Emojis',
  'Emojis you send will appear here': 'Emojis you send will appear here',
  'Search GIFs': 'Search GIFs',
  'Search results ({0})': 'Search results ({0})',
  'Recent GIFs': 'Recent GIFs',
  '{0} GIFs': '{0} GIFs',
  'No Recent GIFs': 'No Recent GIFs',
  'GIFs you send will appear here': 'GIFs you send will appear here',
  'Forward to…': 'Forward to…',
  'Send as copy': 'Send as copy',
  'No chats found': 'No chats found',
  // I18N-LITERAL-104 —— 会话列表：归档、菜单、草稿与前后台状态
  'Archived Chats': 'Archived Chats',
  '{0} chats': '{0} chats',
  'Mark as read': 'Mark as read',
  'Mark as unread': 'Mark as unread',
  'Unarchive': 'Unarchive',
  'Archive': 'Archive',
  'Draft: ': 'Draft: ',
  'Loading chats...': 'Loading chats...',
  'Failed to load chats': 'Failed to load chats',
  // I18N-LITERAL-104 —— 搜索页
  'Search chats, messages...': 'Search chats, messages...',
  'Searching...': 'Searching...',
  'Search Error': 'Search Error',
  // I18N-HOTSWITCH-102 —— 三条搜索失败兜底文案（以前硬编码在 SearchCoordinator，不在词典，
  // 守卫 R5b 看不见：现在状态里传 key，这里补双词典）
  'Too many searches. Please wait a moment and try again.': 'Too many searches. Please wait a moment and try again.',
  'Search is temporarily unavailable. Check your connection and try again.': 'Search is temporarily unavailable. Check your connection and try again.',
  'Search failed. Please try again.': 'Search failed. Please try again.',
  'No Results': 'No Results',
  'Search messages in this chat': 'Search messages in this chat',
  'No results found for "{0}"': 'No results found for "{0}"',
  'Recent Searches': 'Recent Searches',
  'Clear All': 'Clear All',
  'Search Telegram': 'Search Telegram',
  'Search for chats, channels, and messages': 'Search for chats, channels, and messages',
  'CHATS ({0})': 'CHATS ({0})',
  'MESSAGES ({0})': 'MESSAGES ({0})',
  // I18N-LITERAL-104 —— 资料页与联系人
  'Channel Info': 'Channel Info',
  'Group Info': 'Group Info',
  'User Info': 'User Info',
  'Description': 'Description',
  'Invite Link': 'Invite Link',
  'Members ({0})': 'Members ({0})',
  'No contacts': 'No contacts',
  // I18N-LITERAL-104 —— 装配层兜底面
  'Bootstrap Error': 'Bootstrap Error',
  // I18N-LITERAL-104 END EN
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
  'Pinned message': '置顶消息',
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
  'STICKERS AND EMOJI': '贴纸与表情',
  'APPEARANCE': '外观',
  'LANGUAGE': '语言',
  'ABOUT': '关于',
  'Notifications': '通知',
  'Devices': '设备',
  'Active Sessions': '活跃设备与会话',
  '{0} active sessions': '{0} 个活跃会话',
  '{0} active session': '{0} 个活跃会话',
  'This Device': '当前设备',
  'Terminate All Other Sessions': '终止所有其他会话',
  'Terminate Session': '终止会话',
  'Terminate': '终止',
  'Online': '在线',
  'Just now': '刚刚',
  '{0} min ago': '{0} 分钟前',
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

  // Privacy & Security (SELF-102 / PRIVACY-101)
  'PRIVACY': '隐私',
  'Privacy & Security': '隐私和安全',
  'Last Seen': '最后上线时间',
  'Phone Number': '手机号码',
  'Profile Photo': '个人头像',
  'Bio': '个人简介',
  'Date of Birth': '生日',
  'Calls': '通话',
  'Group and Channel Invites': '群组与频道邀请',
  'Discoverable by Phone Number': '可通过手机号找到我',
  'Everybody': '所有人',
  'My Contacts': '我的联系人',
  'Nobody': '没有人',
  'Custom': '自定义',
  'Unknown': '未知',
  'Tap a row to change who can see it.': '点按任意一行即可设置谁可以看到。',
  'My Contacts & Premium': '我的联系人与 Premium',
  'Add Exceptions': '添加例外',
  'Always Allow': '总是允许',
  'Never Allow': '从不允许',
  'Always Share With': '总是分享给',
  'Never Share With': '从不分享给',
  'Add Users': '添加用户',
  // 中文没有单复数变形，两档同文案。
  '{0} User': '{0} 位用户',
  '{0} Users': '{0} 位用户',
  'No Contacts Yet': '还没有联系人',
  'Custom Share Settings Help': '「总是允许」和「从不允许」里的人优先于上面的设置。',

  // Extra toggle rows on the privacy detail page (PRIVACY-103)
  'Telegram Premium subscribers': 'Telegram Premium 用户',
  'Allow Premium Invite Desc': '始终允许订阅了 Telegram Premium 的用户把你添加到群组与频道。',
  'Hide Read Time': '隐藏已读时间',
  'Hide Read Time Desc':
    '对看不到你最后上线时间的人隐藏你的已读时间。开启后，你也会看不到他们的已读时间。此项不影响群聊。',

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

  // 探测失败的原因（PROXY-103）：本端分类出来的句子，不是 TDLib 原文。
  'Address not found': '地址无法解析',
  'Connection refused': '连接被拒绝',
  'Connection timed out': '连接超时',
  'Network unavailable': '网络不可用',
  'Proxy handshake failed': '代理握手失败',
  'Proxy settings rejected': '代理配置被拒绝',
  'Proxy error': '代理异常',

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

  // 贴纸与表情（TGS-104）
  'Loop Animated Stickers': '循环播放动态贴纸',
  'Animated stickers keep playing.': '动态贴纸会一直循环播放。',
  'Animated stickers play once and stop.': '动态贴纸只播放一遍，停在最后一帧。',

  // Internal links (DEEPLINK-101)
  'This link type is not supported yet': '暂不支持这种链接',
  'Failed to open link': '无法打开链接',
  'Sticker set: %s': '贴纸包：%s',

  // Link confirmations (DEEPLINK-102)
  'Join': '加入',
  'Request to Join': '申请加入',
  '{0} members': '{0} 位成员',
  '{0} subscribers': '{0} 位订阅者',
  '1 member': '1 位成员',
  '1 subscriber': '1 位订阅者',
  'Owner': '群主',
  'Admin': '管理员',
  '{0} file': '{0} 个文件',
  '{0} files': '{0} 个文件',
  'Connect to This Proxy?': '连接到此代理？',
  'Server': '服务器',
  'This will add a proxy server to your configuration.': '这会将一个代理服务器添加到你的配置中。',
  'This proxy uses a secret, make sure you trust the link source.': '该代理带有密钥，请确认你信任链接来源。',
  'Enable': '启用',
  'Save for Later': '稍后使用',
  'Join request sent': '加入申请已发送',
  'Proxy enabled': '代理已启用',
  'Proxy saved for later use': '代理已保存，稍后可使用',

  // Screen lock (APPLOCK-101)
  'Screen Lock': '屏幕锁定',
  'Passcode': '密码',
  'Auto-Lock': '自动锁定',
  'Show Typed Passcode': '显示输入的密码',
  'Change Passcode': '更改密码',
  'On': '开启',
  'Immediately': '立即',
  'After 1 minute': '1 分钟后',
  'After 5 minutes': '5 分钟后',
  'After 1 hour': '1 小时后',
  'After 5 hours': '5 小时后',
  'Never': '从不',
  'Enter a new passcode': '输入新密码',
  'Repeat the passcode': '再次输入以确认',
  'Enter your current passcode': '输入当前密码',
  'Enter your passcode': '输入你的密码',
  'Too many attempts. Try again in {0}s': '尝试次数过多，请 {0} 秒后重试',
  'The passcode is stored in this device secure storage and never synced.': '密码保存在本机安全存储中，不会同步到任何地方。',
  'PasscodeNoticeInvalid': '密码必须是 4 位数字。',
  'PasscodeNoticeMismatch': '两次输入的密码不一致，请重新开始。',
  'PasscodeNoticeSaved': '密码已设置。',
  'PasscodeNoticeRemoved': '密码已移除。',
  'PasscodeErrorWrong': '密码错误，请重试。',
  'PasscodeErrorStoreUnavailable': '本机安全存储当前不可用。',
  'PasscodeErrorCorrupt': '已存储的密码无法读取，请重置后继续。',

  // UI 层离散文案（I18N-LITERAL-101）：与上方 EN 块同序、同 key。
  'New Message': '新消息',
  'Retry': '重试',
  'Confirm': '确认',
  'Leave': '退出',
  'Report': '举报',
  'Clear History': '清空历史记录',
  'Clear Recent': '清空',
  'Delete Chat': '删除聊天',
  'Leave Channel': '退出频道',
  'Leave Group': '退出群组',
  'Linked Channel': '已关联的频道',
  'Clear history?': '清空历史记录？',
  'Delete this chat?': '删除聊天？',
  'Report this chat?': '举报此聊天？',
  'Leave this channel?': '退出频道？',
  'Leave this group?': '退出群组？',
  'Mute': '静音',
  'Unmute': '取消静音',
  'Enable Notifications': '开启通知',
  'Join Channel': '加入频道',
  '{0} comments': '{0} 条评论',
  'Voice messages are not allowed in this chat': '此会话不允许发送语音消息',
  'Comments': '评论',
  'Comments ({0})': '评论 ({0})',
  'Original post': '原始帖子内容',
  'No comments yet. Leave the first one!': '还没有评论，留下第一条评论吧',
  'Leave a comment...': '发表评论...',
  'Send Sticker': '发送贴纸',
  'Add to Favorites': '添加至收藏',
  'Remove from Favorites': '移出收藏',
  'Remove from Recent': '从最近使用中移除',
  'View Sticker Set': '查看贴纸包',
  'View {0} more': '查看其余 {0} 张',
  'Trending Sticker Sets': '热门贴纸包',
  '{0} stickers': '{0} 个贴纸',
  'Add': '添加',
  'Added': '已添加',
  'Adding…': '添加中…',
  'Removing…': '移除中…',
  'Loading sticker set…': '正在读取贴纸包…',
  'Failed to load sticker set': '贴纸包读取失败',
  'No installed sticker sets': '还没有安装贴纸包',
  'Tap "Add" on a trending pack to install it. Installed packs show up here.':
    '点上方热门贴纸包的「添加」即可安装，安装后会出现在这里',
  'Sticker Set Details': '贴纸包详情',
  'Failed to load the sticker set. Please try again later.': '贴纸包加载失败，请稍后重试',
  'Fetching info…': '正在获取信息…',
  'Installed': '已安装',
  'Not installed': '未安装',
  '{0} stickers · {1}': '{0} 个贴纸 · {1}',
  'Add Sticker Set': '添加贴纸包',
  'Remove Sticker Set': '移除贴纸包',
  'Add {0} stickers': '添加 {0} 个贴纸',
  'Media': '媒体',
  'Links': '链接',
  'Voice': '语音',
  'Groups': '群组',
  'Failed to load': '加载失败',
  'Tap the tab above to retry.': '点击顶部对应页签重试。',
  'No Media Yet': '暂无媒体文件',
  'Share photos and videos in this chat and access them on all your devices.':
    '在此聊天中分享图片和视频，并在您所有的设备上访问。',
  'No Files Yet': '暂无文件',
  'Share files in this chat and access them on all your devices.':
    '在此聊天中分享文件，并在您所有的设备上访问。',
  'No Links Yet': '暂无链接',
  'Share links in this chat and access them on all your devices.':
    '在此聊天中分享链接，并在您所有的设备上访问。',
  'No Music Yet': '暂无音乐文件',
  'Share audio files in this chat and access them on all your devices.':
    '在此聊天中分享音频文件，并在您所有的设备上访问。',
  'No Voice Messages Yet': '暂无语音消息',
  'Share voice messages in this chat and access them on all your devices.':
    '在此聊天中分享语音消息，并在您所有的设备上访问。',
  'No Common Groups': '暂无共同群组',
  'Groups you have in common with this user will appear here.': '你们所在的共同群组会显示在这里。',
  'Loading more…': '正在加载更多…',
  'Load More': '加载更多',
  'Send Message': '发送消息',
  'Start Secret Chat': '开启密聊',
  'Block User': '屏蔽用户',
  'Block User (not loaded)': '屏蔽用户（未读取）',
  'Unblock User': '取消屏蔽',
  'Phone': '手机',
  'Data and Storage': '数据和存储',
  'EmptyValue': '<空>',
  'Logs out all devices except for this one.': '退出除当前设备外的所有登录会话',
  'Switch Account': '切换账号',
  'Close': '关闭',
  'Active': '正在使用',
  'Add Account': '添加账号',

  // A11Y-101 BEGIN ZH
  // 图标控件的无障碍标签（A11Y-101）：只被屏幕朗读播报，不显示在界面上。
  'A11yBack': '返回',
  'A11yClose': '关闭',
  'A11yMore': '更多选项',
  'A11ySearch': '搜索',
  'A11yCall': '语音通话',
  'A11yMenu': '菜单',
  'A11ySettings': '设置',
  'A11ySwitchAccount': '切换账号',
  'A11yOpenProfile': '打开 {0} 的资料页',
  'A11yNewChat': '新消息',
  'A11yAttach': '附件',
  'A11yEmoji': '表情',
  'A11yKeyboard': '切换到键盘',
  'A11ySend': '发送消息',
  'A11yRecordVoice': '按住录制语音消息',
  'A11yCancelRecording': '取消录音',
  'A11ySendRecording': '发送语音消息',
  'A11yDeleteChar': '删除一个字符',
  'A11yShowPassword': '显示密码',
  'A11yHidePassword': '隐藏密码',
  'A11yForward': '转发',
  'A11yPlay': '播放',
  'A11yPause': '暂停',
  'A11yDownload': '下载',
  'A11yCancelDownload': '取消下载',
  'A11yCancelUpload': '取消上传',
  'A11yRetrySend': '重试发送',
  'A11yOpenMedia': '打开图片',
  'A11yOpenFile': '打开文件',
  'A11yClosePinned': '隐藏置顶消息',
  'A11ySelectMessage': '选中这条消息',
  'A11yDeselectMessage': '取消选中这条消息',
  'A11yMuteSound': '关闭声音',
  'A11yUnmuteSound': '打开声音',
  'A11yBoardTabEmoji': '表情',
  'A11yBoardTabStickers': '贴纸',
  'A11yBoardTabGif': '动图',
  'A11yBoardCell': '贴纸 {0}',
  'A11yBoardPack': '贴纸包 {0}',
  'A11yEdit': '编辑',
  'A11yDelete': '删除',
  'A11yAddContact': '添加联系人',
  // A11Y-101 END ZH
  // I18N-LITERAL-102：与上方 EN 块同序、同 key。
  'Contacts': '联系人',
  'Saved Messages': '收藏夹',
  'Invite Friends': '邀请好友',
  'Help': '帮助',
  'Night Mode': '夜间模式',
  'Continue': '继续',
  'Signing in...': '正在登录...',
  'Message': '消息',
  'Message User': '发消息',
  'Bot @%s selected': '已选择机器人 @%s',
  'Verifying...': '校验中...',
  'Submit': '提交',
  'All': '全部',
  // I18N-LITERAL-102 END ZH
  // I18N-LITERAL-103：与上方 EN 块同序、同 key。
  'online': '在线',
  'offline': '离线',
  'last seen recently': '最近上线',
  'last seen within a week': '最近一周内上线',
  'last seen within a month': '最近一个月内上线',
  'Service Notifications': '服务通知',
  '{0} online': '{0} 在线',
  '{0}, {1} online': '{0}, {1} 在线',
  'Me': '我',
  'User': '用户',
  'Channel': '频道',
  'Supergroup': '超级群组',
  'Group': '群组',
  'Private Chat': '私聊',
  'Today': '今天',
  'Yesterday': '昨天',
  'Last Week': '上周',
  'Sunday': '星期日',
  'Monday': '星期一',
  'Tuesday': '星期二',
  'Wednesday': '星期三',
  'Thursday': '星期四',
  'Friday': '星期五',
  'Saturday': '星期六',
  '[Photo]': '[照片]',
  '[Video]': '[视频]',
  '[GIF]': '[动图]',
  '[Audio]': '[音频]',
  '[Voice message]': '[语音消息]',
  '[Voice]': '[语音]',
  '[Video message]': '[视频消息]',
  '[Document]': '[文件]',
  '[Sticker]': '[贴纸]',
  '{0} Sticker': '{0} 贴纸',
  '[Location]': '[位置]',
  '[Venue]': '[地点]',
  '[Contact]': '[联系人]',
  '[Poll]': '[投票]',
  '[Call]': '[通话]',
  '[Game]': '[游戏]',
  'Recently Used': '最近使用',
  'Favorites': '收藏',
  'This chat does not allow sending photos': '此会话不允许发送图片',
  'This chat does not allow sending camera photos or videos': '此会话不允许发送拍摄的照片或视频',
  'This chat does not allow sending videos': '此会话不允许发送视频',
  'This chat does not allow sending files': '此会话不允许发送文件',
  'This chat does not allow creating polls': '此会话不允许发起投票',
  'This chat does not allow sending stickers': '此会话不允许发送贴纸',
  'This chat does not allow sending GIFs': '此会话不允许发送 GIF',
  'This chat does not allow sending this content': '此会话不允许发送该内容',
  'Mute failed': '静音失败',
  'Unmute failed': '取消静音失败',
  'Muted': '已静音',
  'Failed to clear history': '清空历史失败',
  'Chat history cleared': '已清空聊天历史',
  'Failed to delete chat': '删除聊天失败',
  'Chat deleted': '已删除聊天',
  'Failed to report': '举报失败',
  'Reported': '已举报',
  'Failed to leave': '退出失败',
  'Left the chat': '已退出',
  'Vote failed': '投票失败',
  'Microphone permission required': '需要麦克风权限才能录音',
  'Cannot start recording': '无法开始录音',
  'Recording failed, not sent': '录音失败，未发送',
  'Downloading voice message…': '正在下载语音消息…',
  'Voice file unavailable': '语音文件不可用',
  'Downloading audio…': '正在下载音频…',
  'Cannot start the secret chat': '无法开启密聊',
  'Operation failed, please try again later': '操作失败，请稍后重试',
  'Voice file cannot be read': '语音文件无法读取',
  'Copied to clipboard': '已复制到剪贴板',
  'Link copied': '已复制链接',
  'No comment thread': '无法获取评论线程',
  'Network error': '网络异常',
  'Channel post': '频道帖子',
  'Channel message': '频道消息',
  'Sticker': '贴纸',
  'Personal': '个人',
  'Unread': '未读',
  'Photo': '照片',
  'Video': '视频',
  'GIF': 'GIF',
  'Document': '文档',
  '[Unsupported message]': '[不支持的消息]',
  // I18N-LITERAL-103 END ZH
  // I18N-LITERAL-104 BEGIN ZH —— 登录线七页
  'Authorization Failed': '授权失败',
  'An unexpected error occurred.': '出现未知错误。',
  'Try Again': '重试',
  'Enter Code': '输入验证码',
  'We sent an SMS with the code to {0}': '我们已通过短信把验证码发送到 {0}',
  'Wrong number?': '号码有误？',
  'Enter {0}-digit code': '输入 {0} 位验证码',
  'Resend code': '重新发送验证码',
  'Resend code in {0}': '{0} 后可重新发送验证码',
  'Two-Step Verification': '两步验证',
  'Your account is protected with an additional password.': '你的账号受额外密码保护。',
  'Enter your password': '输入你的密码',
  'Hint: {0}': '提示：{0}',
  'Your Phone': '你的手机号',
  'Please confirm your country code and enter your phone number.': '请确认国家/地区代码并输入手机号码。',
  'Phone number': '手机号码',
  'Log in with QR code': '使用二维码登录',
  'Open Telegram on another device, then go to Settings > Devices > Link Desktop Device and scan this code.': '请在另一台设备上打开 Telegram，进入「设置 > 设备 > 登录桌面设备」，然后扫描此二维码。',
  'Preparing a secure QR code...': '正在生成安全二维码…',
  'The code refreshes automatically. Keep this screen open while scanning.': '二维码会自动刷新，扫码时请保持此页面打开。',
  'Log in with QR code instead': '改用二维码登录',
  'Your Name': '你的名字',
  'Enter your name to complete registration.': '输入你的名字以完成注册。',
  'First name (required)': '名字（必填）',
  'Last name (optional)': '姓氏（选填）',
  'Registering...': '正在注册…',
  'Complete': '完成',
  // I18N-LITERAL-104 —— 聊天页
  'You': '你',
  'edited': '已编辑',
  '{0} selected': '已选择 {0} 条',
  'Failed · Tap to retry': '发送失败 · 点击重试',
  'Edit Message': '编辑消息',
  'Reply to {0}': '回复 {0}',
  'Resend': '重新发送',
  'Copy Link': '复制链接',
  'Attach': '附件',
  'Create Poll': '创建投票',
  'Question': '问题',
  'Option {0}': '选项 {0}',
  '＋ Add Option': '＋ 添加选项',
  'Anonymous Poll': '匿名投票',
  'Multiple Answers': '允许多选',
  'Create': '创建',
  'Add a question and 2 options': '请填写问题和 2 个选项',
  'Download Video': '下载视频',
  'Download GIF': '下载 GIF',
  'Loading messages...': '正在加载消息…',
  'No messages yet': '还没有消息',
  'Failed to load messages': '消息加载失败',
  'Search in chat...': '在聊天中搜索…',
  '[Message]': '[消息]',
  'Tap to load': '点击加载',
  // I18N-LITERAL-104 —— 表情/GIF 板与转发选择器
  'Recent': '最近',
  'No Recent Emojis': '暂无最近使用的表情',
  'Emojis you send will appear here': '你发送过的表情会出现在这里',
  'Search GIFs': '搜索 GIF',
  'Search results ({0})': '搜索结果（{0}）',
  'Recent GIFs': '最近使用的 GIF',
  '{0} GIFs': '{0} 个 GIF',
  'No Recent GIFs': '暂无最近使用的 GIF',
  'GIFs you send will appear here': '你发送过的 GIF 会出现在这里',
  'Forward to…': '转发给…',
  'Send as copy': '以副本发送',
  'No chats found': '未找到会话',
  // I18N-LITERAL-104 —— 会话列表
  'Archived Chats': '归档聊天',
  '{0} chats': '{0} 个聊天',
  'Mark as read': '标记为已读',
  'Mark as unread': '标记为未读',
  'Unarchive': '取消归档',
  'Archive': '归档',
  'Draft: ': '草稿：',
  'Loading chats...': '正在加载聊天…',
  'Failed to load chats': '聊天加载失败',
  // I18N-LITERAL-104 —— 搜索页
  'Search chats, messages...': '搜索聊天、消息…',
  'Searching...': '正在搜索…',
  'Search Error': '搜索出错',
  'Too many searches. Please wait a moment and try again.': '搜索太频繁了，请稍候再试。',
  'Search is temporarily unavailable. Check your connection and try again.': '搜索暂不可用，请检查网络后再试。',
  'Search failed. Please try again.': '搜索失败，请重试。',
  'No Results': '没有结果',
  'Search messages in this chat': '在此会话中搜索消息',
  'No results found for "{0}"': '未找到与“{0}”相关的结果',
  'Recent Searches': '最近搜索',
  'Clear All': '清除全部',
  'Search Telegram': '搜索 Telegram',
  'Search for chats, channels, and messages': '搜索聊天、频道与消息',
  'CHATS ({0})': '聊天（{0}）',
  'MESSAGES ({0})': '消息（{0}）',
  // I18N-LITERAL-104 —— 资料页与联系人
  'Channel Info': '频道信息',
  'Group Info': '群组信息',
  'User Info': '用户信息',
  'Description': '简介',
  'Invite Link': '邀请链接',
  'Members ({0})': '成员（{0}）',
  'No contacts': '暂无联系人',
  // I18N-LITERAL-104 —— 装配层兜底面
  'Bootstrap Error': '初始化失败',
  // I18N-LITERAL-104 END ZH
};

export class Lang {
  private static instance: Lang | null = null;

  private preference: LanguagePreference = 'system';
  private systemLanguage: SupportedLanguage = 'en';
  private hourClock: HourClock = '24h';
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

  /**
   * 时制档（I18N-DATE-102）：与 `systemLanguage` 同一条路子 —— 值由装配层从系统取
   * （`i18n.System.is24HourClock()` 是 Kit 调用，`core` 与各 coordinator 都碰不到），
   * 取到后灌进这里，coordinator 在投影时读，页面走 AppStorage 的响应式键。
   * 默认 `'24h'`：没灌值时（单测、更早的启动时序）保持本仓此前的行为。
   */
  getHourClock(): HourClock {
    return this.hourClock;
  }

  setHourClock(clock: HourClock): void {
    if (this.hourClock === clock) {
      return;
    }
    this.hourClock = clock;
    this.notifyListeners();
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
    this.hourClock = '24h';
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
