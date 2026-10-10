import { describe, it, expect } from '@ohos/hypium';
import {
  Lang,
  LanguagePreference,
  SupportedLanguage,
  formatString,
  lang,
  languagePreferenceFromStored,
  resolveLanguage,
  systemLanguageFromLocale
} from '../main/ets/Lang';

function hasHan(text: string): boolean {
  return /[\u4e00-\u9fff]/.test(text);
}

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
        'Files': '文件',
        'All Notifications': '全部通知',
        'Private Chats': '私聊',
        'Group Chats': '群组',
        'Channels': '频道'
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

    it('viewLayerCopy_i18nLiteral101_translatesPinnedEntries', 0, () => {
      Lang.getInstance().reset();
      Lang.getInstance().setLanguage('zh');

      const requiredEntries: Record<string, string> = {
        'New Message': '新消息',
        'Clear History': '清空历史记录',
        'Clear Recent': '清空',
        'Delete this chat?': '删除聊天？',
        'Leave this channel?': '退出频道？',
        'Mute': '静音',
        'Unmute': '取消静音',
        'Join Channel': '加入频道',
        'Comments': '评论',
        'Original post': '原始帖子内容',
        'Send Sticker': '发送贴纸',
        'Add to Favorites': '添加至收藏',
        'View Sticker Set': '查看贴纸包',
        'Trending Sticker Sets': '热门贴纸包',
        'Installed': '已安装',
        'Sticker Set Details': '贴纸包详情',
        'Media': '媒体',
        'No Common Groups': '暂无共同群组',
        'Load More': '加载更多',
        'Send Message': '发送消息',
        'Block User': '屏蔽用户',
        'Data and Storage': '数据和存储',
        'Logs out all devices except for this one.': '退出除当前设备外的所有登录会话',
        'Switch Account': '切换账号',
        'Add Account': '添加账号'
      };

      const keys: string[] = Object.keys(requiredEntries);
      for (let i = 0; i < keys.length; i++) {
        const key: string = keys[i];
        expect(Lang.getInstance().t(key)).assertEqual(requiredEntries[key]);
      }
    });

    it('viewLayerCopy_i18nLiteral101_neverFallsBackToKeyUnderChinese', 0, () => {
      // Lang 缺译文时原样回吐 key，屏幕上就是一串英文标识 —— 和正常英文文案肉眼难以区分，
      // 所以这里按「中文界面里不能出现纯 ASCII 的整句」来断言（本仓视图层文案均含汉字）。
      const convertedKeys: string[] = [
        'New Message', 'Retry', 'Confirm', 'Leave', 'Report', 'Clear History', 'Clear Recent',
        'Delete Chat', 'Leave Channel', 'Leave Group', 'Linked Channel', 'Clear history?',
        'Delete this chat?', 'Report this chat?', 'Leave this group?', 'Mute', 'Unmute',
        'Enable Notifications', 'Join Channel', '{0} comments',
        'Voice messages are not allowed in this chat', 'Comments', 'Comments ({0})',
        'Original post', 'No comments yet. Leave the first one!', 'Send Sticker',
        'Add to Favorites', 'Remove from Favorites', 'Remove from Recent', 'View Sticker Set',
        'View {0} more', 'Trending Sticker Sets', '{0} stickers', 'Add', 'Added', 'Adding…',
        'Removing…', 'Loading sticker set…', 'Failed to load sticker set',
        'No installed sticker sets', 'Sticker Set Details',
        'Failed to load the sticker set. Please try again later.', 'Fetching info…', 'Installed',
        'Not installed', '{0} stickers · {1}', 'Add Sticker Set', 'Remove Sticker Set',
        'Add {0} stickers', 'Media', 'Links', 'Voice', 'Groups', 'Failed to load',
        'Tap the tab above to retry.', 'No Media Yet', 'No Files Yet', 'No Links Yet',
        'No Music Yet', 'No Voice Messages Yet', 'No Common Groups', 'Loading more…',
        'Load More', 'Send Message', 'Start Secret Chat', 'Block User', 'Block User (not loaded)',
        'Unblock User', 'Phone', 'Data and Storage',
        'Logs out all devices except for this one.', 'Switch Account', 'Close', 'Active',
        'Add Account'
      ];

      Lang.getInstance().reset();
      Lang.getInstance().setLanguage('zh');
      for (let i = 0; i < convertedKeys.length; i++) {
        const key: string = convertedKeys[i];
        const value: string = Lang.getInstance().t(key);
        expect(value !== key).assertTrue();
        expect(hasHan(value)).assertTrue();
      }

      Lang.getInstance().setLanguage('en');
      for (let i = 0; i < convertedKeys.length; i++) {
        expect(Lang.getInstance().t(convertedKeys[i])).assertEqual(convertedKeys[i]);
      }
    });

    it('viewLayerCopy_i18nLiteral101_substitutesPositionalArgsInBothLanguages', 0, () => {
      Lang.getInstance().reset();
      Lang.getInstance().setLanguage('en');
      expect(Lang.getInstance().t('{0} comments', 3)).assertEqual('3 comments');
      expect(Lang.getInstance().t('View {0} more', 12)).assertEqual('View 12 more');
      expect(Lang.getInstance().t('{0} stickers', 40)).assertEqual('40 stickers');
      expect(Lang.getInstance().t('Add {0} stickers', 40)).assertEqual('Add 40 stickers');
      expect(Lang.getInstance().t('{0} stickers · {1}', 40, 'Installed')).assertEqual('40 stickers · Installed');

      Lang.getInstance().setLanguage('zh');
      expect(Lang.getInstance().t('{0} comments', 3)).assertEqual('3 条评论');
      expect(Lang.getInstance().t('Comments ({0})', 7)).assertEqual('评论 (7)');
      expect(Lang.getInstance().t('View {0} more', 12)).assertEqual('查看其余 12 张');
      expect(Lang.getInstance().t('Add {0} stickers', 40)).assertEqual('添加 40 个贴纸');
      expect(Lang.getInstance().t('{0} stickers · {1}', 40, '已安装')).assertEqual('40 个贴纸 · 已安装');
    });

    it('viewLayerCopy_i18nLiteral102_drawerLoginAndComposer_neverFallBackToKey', 0, () => {
      // I18N-LITERAL-102 接回的这批：抽屉菜单行、登录流程按钮/状态、输入栏占位。
      // 守卫 R4 只认「词典已有的英文」，所以这批 key 一旦漏词条，R4 反而看不见 ——
      // 靠这里兜住：中文界面必须出汉字，英文界面必须原样出这句英文。
      const convertedKeys: string[] = [
        'Contacts', 'Saved Messages', 'Invite Friends', 'Help', 'Night Mode',
        'Continue', 'Signing in...', 'Message', 'Verifying...', 'Submit', 'All'
      ];
      // 'Message User' 不在这批：它的英文 value（Message）与 key 不同形，EN 侧的
      // `t(key) === key` 断言对它天然不成立，由下面那条名词/动词用例逐值钉。

      Lang.getInstance().reset();
      Lang.getInstance().setLanguage('zh');
      for (let i = 0; i < convertedKeys.length; i++) {
        const key: string = convertedKeys[i];
        const value: string = Lang.getInstance().t(key);
        expect(value !== key).assertTrue();
        expect(hasHan(value)).assertTrue();
      }

      Lang.getInstance().setLanguage('en');
      for (let i = 0; i < convertedKeys.length; i++) {
        expect(Lang.getInstance().t(convertedKeys[i])).assertEqual(convertedKeys[i]);
      }
    });

    it('viewLayerCopy_i18nLiteral102_messageNounAndVerbStayApart', 0, () => {
      // 'Message'（输入栏占位/回复摘要兜底，名词）与 'Message User'（资料页那颗按钮，
      // 动词）英文同形、中文不同形；共用一条 key 只会让其中一侧翻得别扭。
      Lang.getInstance().reset();
      Lang.getInstance().setLanguage('en');
      expect(Lang.getInstance().t('Message')).assertEqual('Message');
      expect(Lang.getInstance().t('Message User')).assertEqual('Message');

      Lang.getInstance().setLanguage('zh');
      expect(Lang.getInstance().t('Message')).assertEqual('消息');
      expect(Lang.getInstance().t('Message User')).assertEqual('发消息');
    });

    it('viewLayerCopy_i18nLiteral102_botToastSubstitutesPrintfArg', 0, () => {
      Lang.getInstance().reset();
      Lang.getInstance().setLanguage('en');
      expect(Lang.getInstance().t('Bot @%s selected', 'telegram')).assertEqual('Bot @telegram selected');
      Lang.getInstance().setLanguage('zh');
      expect(Lang.getInstance().t('Bot @%s selected', 'telegram')).assertEqual('已选择机器人 @telegram');
    });

    it('dataLayerCopy_i18nLiteral103_hasBothLanguages', 0, () => {
      // I18N-LITERAL-103 接回的这批：它们在 coordinator/model 里拼好再上屏，
      // 守卫 R5 只看「词典已知的英文」，漏词条时 R5 反而看不见（汉字那半边由 R5a 兜）。
      // 这批 key 的英文取值与 key 同形，所以这里能双向钉：中文出汉字、英文原样出这句。
      const convertedKeys: string[] = [
        'online', 'offline', 'last seen recently', 'last seen within a week',
        'last seen within a month', 'Service Notifications', 'Me', 'User',
        'Channel', 'Supergroup', 'Group', 'Private Chat',
        'Today', 'Yesterday', 'Last Week',
        'Sunday', 'Monday', 'Tuesday', 'Wednesday', 'Thursday', 'Friday', 'Saturday',
        '[Photo]', '[Video]', '[GIF]', '[Audio]', '[Voice message]', '[Voice]',
        '[Video message]', '[Document]', '[Sticker]', '[Location]', '[Venue]',
        '[Contact]', '[Poll]', '[Call]', '[Game]',
        'Recently Used', 'Favorites',
        'Mute failed', 'Unmute failed', 'Muted', 'Failed to clear history',
        'Chat history cleared', 'Failed to delete chat', 'Chat deleted',
        'Failed to report', 'Reported', 'Failed to leave', 'Left the chat',
        'Vote failed', 'Microphone permission required', 'Cannot start recording',
        'Recording failed, not sent', 'Downloading voice message…',
        'Voice file unavailable', 'Downloading audio…', 'Cannot start the secret chat',
        'Operation failed, please try again later', 'Voice file cannot be read',
        'Copied to clipboard', 'Link copied', 'No comment thread', 'Network error',
        'Channel post', 'Channel message',
        'This chat does not allow sending photos',
        'This chat does not allow sending videos',
        'This chat does not allow sending files',
        'This chat does not allow creating polls',
        'This chat does not allow sending stickers',
        'This chat does not allow sending GIFs',
        'This chat does not allow sending this content'
      ];

      Lang.getInstance().reset();
      Lang.getInstance().setLanguage('zh');
      for (let i = 0; i < convertedKeys.length; i++) {
        const key: string = convertedKeys[i];
        const value: string = Lang.getInstance().t(key);
        expect(value !== key).assertTrue();
        expect(hasHan(value)).assertTrue();
      }

      Lang.getInstance().setLanguage('en');
      for (let i = 0; i < convertedKeys.length; i++) {
        expect(Lang.getInstance().t(convertedKeys[i])).assertEqual(convertedKeys[i]);
      }
    });

    it('dataLayerCopy_i18nLiteral103_substitutesCountArgs', 0, () => {
      Lang.getInstance().reset();
      Lang.getInstance().setLanguage('en');
      expect(Lang.getInstance().t('{0} online', 3)).assertEqual('3 online');
      expect(Lang.getInstance().t('{0}, {1} online', 3, 12)).assertEqual('3, 12 online');
      expect(Lang.getInstance().t('{0} Sticker', '😀')).assertEqual('😀 Sticker');

      Lang.getInstance().setLanguage('zh');
      expect(Lang.getInstance().t('{0} online', 3)).assertEqual('3 在线');
      expect(Lang.getInstance().t('{0}, {1} online', 3, 12)).assertEqual('3, 12 在线');
      expect(Lang.getInstance().t('{0} Sticker', '😀')).assertEqual('😀 贴纸');
    });

    it('viewLayerCopy_i18nLiteral104_hasBothLanguages', 0, () => {
      // I18N-LITERAL-104 建词条并接线的这批：第五十三轮设备取证里它们在屏幕上就是英文原文，
      // 因为词典压根没有这一项（旧 R4 只认「词典已知的英文」，对「压根没建词条」完全放行）。
      // 这一条把 92 个 key 双向钉住：中文必须是汉字、英文必须原样出这句。
      // 带槽位的 key 在这里只查译文语言，槽位替换由下一条用例逐条钉。
      const convertedKeys: string[] = [
        'Authorization Failed', 'An unexpected error occurred.',
        'Try Again', 'Enter Code',
        'We sent an SMS with the code to {0}', 'Wrong number?',
        'Enter {0}-digit code', 'Resend code',
        'Resend code in {0}', 'Two-Step Verification',
        'Your account is protected with an additional password.', 'Enter your password',
        'Hint: {0}', 'Your Phone',
        'Please confirm your country code and enter your phone number.', 'Phone number',
        'Log in with QR code',
        'Open Telegram on another device, then go to Settings > Devices > Link Desktop Device and scan this code.',
        'Preparing a secure QR code...', 'The code refreshes automatically. Keep this screen open while scanning.',
        'Log in with QR code instead', 'Your Name',
        'Enter your name to complete registration.', 'First name (required)',
        'Last name (optional)', 'Registering...',
        'Complete', 'You',
        'edited', '{0} selected',
        'Failed · Tap to retry', 'Edit Message',
        'Reply to {0}', 'Resend',
        'Copy Link', 'Attach',
        'Create Poll', 'Question',
        'Option {0}', '＋ Add Option',
        'Anonymous Poll', 'Multiple Answers',
        'Create', 'Add a question and 2 options',
        'Download Video', 'Download GIF',
        'Loading messages...', 'No messages yet',
        'Failed to load messages', 'Search in chat...',
        '[Message]', 'Tap to load',
        'Recent', 'No Recent Emojis',
        'Emojis you send will appear here', 'Search GIFs',
        'Search results ({0})', 'Recent GIFs',
        '{0} GIFs', 'No Recent GIFs',
        'GIFs you send will appear here', 'Forward to…',
        'Send as copy', 'No chats found',
        'Archived Chats', '{0} chats',
        'Mark as read', 'Mark as unread',
        'Unarchive', 'Archive',
        'Draft: ', 'Loading chats...',
        'Failed to load chats', 'Search chats, messages...',
        'Searching...', 'Search Error',
        'No Results', 'No results found for "{0}"',
        'Recent Searches', 'Clear All',
        'Search Telegram', 'Search for chats, channels, and messages',
        'CHATS ({0})', 'MESSAGES ({0})',
        'Channel Info', 'Group Info',
        'User Info', 'Description',
        'Invite Link', 'Members ({0})',
        'No contacts', 'Bootstrap Error'
      ];

      Lang.getInstance().reset();
      Lang.getInstance().setLanguage('zh');
      for (let i = 0; i < convertedKeys.length; i++) {
        const key: string = convertedKeys[i];
        const value: string = Lang.getInstance().t(key);
        expect(value !== key).assertTrue();
        expect(hasHan(value)).assertTrue();
      }

      Lang.getInstance().setLanguage('en');
      for (let i = 0; i < convertedKeys.length; i++) {
        expect(Lang.getInstance().t(convertedKeys[i])).assertEqual(convertedKeys[i]);
      }
    });

    it('viewLayerCopy_i18nLiteral104_substitutesSlots', 0, () => {
      // 这批 key 里带 `{0}` 的是 14 条，槽位写在译文中间（不是尾部拼串），
      // 所以 {0} 换错位置在屏幕上一眼就能看出来 —— 逐条钉住两档语言。
      Lang.getInstance().reset();
      Lang.getInstance().setLanguage('en');
      expect(Lang.getInstance().t('We sent an SMS with the code to {0}', '+1 425')).assertEqual('We sent an SMS with the code to +1 425');
      expect(Lang.getInstance().t('Enter {0}-digit code', 5)).assertEqual('Enter 5-digit code');
      expect(Lang.getInstance().t('Resend code in {0}', '5s')).assertEqual('Resend code in 5s');
      expect(Lang.getInstance().t('Hint: {0}', 'abc')).assertEqual('Hint: abc');
      expect(Lang.getInstance().t('{0} selected', 2)).assertEqual('2 selected');
      expect(Lang.getInstance().t('Reply to {0}', 'Alice')).assertEqual('Reply to Alice');
      expect(Lang.getInstance().t('Option {0}', 3)).assertEqual('Option 3');
      expect(Lang.getInstance().t('Search results ({0})', 7)).assertEqual('Search results (7)');
      expect(Lang.getInstance().t('{0} GIFs', 4)).assertEqual('4 GIFs');
      expect(Lang.getInstance().t('{0} chats', 9)).assertEqual('9 chats');
      expect(Lang.getInstance().t('No results found for "{0}"', 'qw')).assertEqual('No results found for "qw"');
      expect(Lang.getInstance().t('CHATS ({0})', 1)).assertEqual('CHATS (1)');
      expect(Lang.getInstance().t('MESSAGES ({0})', 1)).assertEqual('MESSAGES (1)');
      expect(Lang.getInstance().t('Members ({0})', 33)).assertEqual('Members (33)');

      Lang.getInstance().setLanguage('zh');
      expect(Lang.getInstance().t('We sent an SMS with the code to {0}', '+1 425')).assertEqual('我们已通过短信把验证码发送到 +1 425');
      expect(Lang.getInstance().t('Enter {0}-digit code', 5)).assertEqual('输入 5 位验证码');
      expect(Lang.getInstance().t('Resend code in {0}', '5s')).assertEqual('5s 后可重新发送验证码');
      expect(Lang.getInstance().t('Hint: {0}', 'abc')).assertEqual('提示：abc');
      expect(Lang.getInstance().t('{0} selected', 2)).assertEqual('已选择 2 条');
      expect(Lang.getInstance().t('Reply to {0}', 'Alice')).assertEqual('回复 Alice');
      expect(Lang.getInstance().t('Option {0}', 3)).assertEqual('选项 3');
      expect(Lang.getInstance().t('Search results ({0})', 7)).assertEqual('搜索结果（7）');
      expect(Lang.getInstance().t('{0} GIFs', 4)).assertEqual('4 个 GIF');
      expect(Lang.getInstance().t('{0} chats', 9)).assertEqual('9 个聊天');
      expect(Lang.getInstance().t('No results found for "{0}"', 'qw')).assertEqual('未找到与“qw”相关的结果');
      expect(Lang.getInstance().t('CHATS ({0})', 1)).assertEqual('聊天（1）');
      expect(Lang.getInstance().t('MESSAGES ({0})', 1)).assertEqual('消息（1）');
      expect(Lang.getInstance().t('Members ({0})', 33)).assertEqual('成员（33）');
    });

    it('viewLayerCopy_i18nLiteral104_outgoingAuthorIsYou', 0, () => {
      // 104 撞到的措辞分裂就在这里：'You' 此前不在词典里，所以旧守卫一条都不报（R4 只认词典
      // 已知的英文），于是中文界面里自己发的消息回复条出 `Reply to You`。
      Lang.getInstance().reset();
      Lang.getInstance().setLanguage('zh');
      expect(Lang.getInstance().t('You')).assertEqual('你');
      expect(Lang.getInstance().t('Reply to {0}', Lang.getInstance().t('You')))
        .assertEqual('回复 你');
      Lang.getInstance().setLanguage('en');
      expect(Lang.getInstance().t('You')).assertEqual('You');
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

    it('systemLanguageFromLocale_matchesOnLanguageSubtagOnly', 0, () => {
      expect(systemLanguageFromLocale('zh')).assertEqual('zh');
      expect(systemLanguageFromLocale('zh-Hans')).assertEqual('zh');
      expect(systemLanguageFromLocale('zh-Hant-HK')).assertEqual('zh');
      expect(systemLanguageFromLocale('ZH-CN')).assertEqual('zh');
      expect(systemLanguageFromLocale('en-US')).assertEqual('en');
      expect(systemLanguageFromLocale('fr')).assertEqual('en');
      expect(systemLanguageFromLocale('')).assertEqual('en');
      expect(systemLanguageFromLocale(null)).assertEqual('en');
      expect(systemLanguageFromLocale(undefined)).assertEqual('en');
    });

    it('languagePreferenceFromStored_rejectsAnythingButTheThreeBuckets', 0, () => {
      expect(languagePreferenceFromStored('system')).assertEqual('system');
      expect(languagePreferenceFromStored('en')).assertEqual('en');
      expect(languagePreferenceFromStored('zh')).assertEqual('zh');
      // 脏值与缺值一律回落 'system'（Android 首装档）。刻意不回落成显式的 'en'：
      // 'en' 是一条**用户选过**的偏好，用它兜脏值会把「跟随系统」永久压掉。
      expect(languagePreferenceFromStored('zh-CN')).assertEqual('system');
      expect(languagePreferenceFromStored('EN')).assertEqual('system');
      expect(languagePreferenceFromStored('')).assertEqual('system');
      expect(languagePreferenceFromStored(null)).assertEqual('system');
      expect(languagePreferenceFromStored(undefined)).assertEqual('system');
    });

    it('hydrationFormula_resolvesStoredPreferenceAgainstSystemLocale', 0, () => {
      // EntryAbility 冷启动灌的就是这条公式（LANG-PERSIST-101）。
      expect(resolveLanguage(
        languagePreferenceFromStored(null), systemLanguageFromLocale('zh-Hans'))).assertEqual('zh');
      expect(resolveLanguage(
        languagePreferenceFromStored('system'), systemLanguageFromLocale('en-US'))).assertEqual('en');
      expect(resolveLanguage(
        languagePreferenceFromStored('en'), systemLanguageFromLocale('zh-Hans'))).assertEqual('en');
      expect(resolveLanguage(
        languagePreferenceFromStored('zh'), systemLanguageFromLocale('en-US'))).assertEqual('zh');
    });

    it('hydrate_appliesSystemLocaleThenStoredPreference', 0, () => {
      const instance: Lang = Lang.getInstance();
      const savedPreference: LanguagePreference = instance.getPreference();
      const savedSystemLanguage: SupportedLanguage = instance.getSystemLanguage();
      try {
        // 先钉住「跟随系统」，本用例断言的每一位都由这里显式决定，不依赖用例顺序。
        instance.setLanguage('system');
        instance.setSystemLanguage(systemLanguageFromLocale('zh-Hans'));
        expect(instance.getSystemLanguage()).assertEqual('zh');
        expect(instance.getLanguage()).assertEqual('zh');

        // 盘上是显式偏好时，系统档让位。
        instance.setLanguage(languagePreferenceFromStored('en'));
        expect(instance.getLanguage()).assertEqual('en');

        instance.setLanguage(languagePreferenceFromStored('system'));
        expect(instance.getLanguage()).assertEqual('zh');
      } finally {
        instance.setSystemLanguage(savedSystemLanguage);
        instance.setLanguage(savedPreference);
      }
    });
  });
}
