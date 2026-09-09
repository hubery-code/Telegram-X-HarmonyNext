/**
 * feature/chat_list — Mock 会话数据生成器（CHATLIST-002）。
 *
 * 生成确定性的示例会话（默认 50 条）：姓名/群名/频道名取自固定词表，
 * 文案与时间戳按索引推导，同一输入恒得同一输出，便于调试与测试。
 * 时间游标从 baseTimeMs（默认当前时刻）向过去递减，列表天然按新到旧排序。
 * 本文件不是 reducer，允许 Date.now()；UI 联调接真实投影后整体替换。
 */

import { ChatListItem, avatarColorForChatId, avatarLetterForTitle } from './ChatListItem';

const MINUTE_MS: number = 60 * 1000;

const PERSON_FIRST_NAMES: string[] = [
  'Alice', 'Bruno', 'Chen', 'Dana', 'Eli', 'Fatima', 'Gustav', 'Hana',
  'Ivan', 'Jia', 'Kenji', 'Lena', 'Marco', 'Nadia', 'Omar', 'Priya',
  'Quentin', 'Rosa', 'Sam', 'Tara', 'Umar', 'Vera', 'Wei', 'Xenia',
  'Yusuf', 'Zoe'
];

const PERSON_LAST_NAMES: string[] = [
  'Freeman', 'Anderson', 'Wei', 'Scully', 'Cohen', 'Khan', 'Müller', 'Tanaka',
  'Petrov', 'Li', 'Sato', 'Horvat', 'Rossi', 'Haddad', 'Ali', 'Sharma',
  'Lefevre', 'Garcia', 'Fischer', 'Novak', 'Demir', 'Ivanova', 'Larsen', 'Papadopoulos',
  'Ahmad', 'Kovacs'
];

const GROUP_NAMES: string[] = [
  'Telegram X Dev',
  'Weekend Hikers',
  'Family',
  'Apartment 4B Neighbors',
  'Book Club',
  'Football Sunday',
  'Product Design',
  'Road Trip 2026'
];

const CHANNEL_NAMES: string[] = [
  'Tech Daily',
  'HarmonyOS News',
  'Indie Makers',
  'Market Watch'
];

const MESSAGE_SNIPPETS: string[] = [
  'Hey, are we still on for tonight?',
  'Just sent you the files, let me know if anything is missing',
  'Haha that is exactly what I said!',
  'Can you review the PR when you have a minute?',
  'The build finally passed 🎉',
  'See you at the usual place at 7',
  'I will be offline this afternoon, ping me tomorrow',
  'Did you catch the game last night?',
  'New mockups are in the shared folder',
  'Sounds good, shipping it',
  'Reminder: standup moved to 9:30',
  'Thanks for the quick turnaround!',
  'Let’s sync after lunch',
  'The ticket is closed, root cause was a race in the cache layer',
  'Check out this article on ArkTS strict mode',
  'On my way, 10 minutes',
  'Can we move the meeting to Friday?',
  'Dinner is on me next time',
  'I pushed a fix, please re-test',
  'No worries, take your time',
  'The photos from the trip are amazing',
  'Who is bringing the projector?',
  'CI is red again, looking into it',
  'Happy birthday! 🎂',
  'Let’s continue this thread tomorrow',
  'Got it, thanks!',
  'The server migration is scheduled for Sunday night',
  'Draft is ready for your comments',
  'Ping me when you land',
  'That workaround actually holds up pretty well'
];

/** 生成 count 条 Mock 会话，按时间新到旧排序。 */
export function generateMockChats(count: number = 50, baseTimeMs: number = Date.now()): ChatListItem[] {
  const items: ChatListItem[] = [];
  let cursor: number = baseTimeMs;
  for (let i = 0; i < count; i++) {
    const chatId: number = 100000 + i;
    const snippet: string = MESSAGE_SNIPPETS[(i * 11 + 5) % MESSAGE_SNIPPETS.length];

    let title: string;
    let preview: string;
    if (i % 10 === 4) {
      title = CHANNEL_NAMES[Math.floor(i / 10) % CHANNEL_NAMES.length];
      preview = snippet;
    } else if (i % 10 === 9) {
      title = GROUP_NAMES[Math.floor(i / 10) % GROUP_NAMES.length];
      const speaker: string = PERSON_FIRST_NAMES[(i * 3 + 1) % PERSON_FIRST_NAMES.length];
      preview = `${speaker}: ${snippet}`;
    } else {
      const firstName: string = PERSON_FIRST_NAMES[i % PERSON_FIRST_NAMES.length];
      const lastName: string = PERSON_LAST_NAMES[(i * 7 + 3) % PERSON_LAST_NAMES.length];
      title = `${firstName} ${lastName}`;
      preview = snippet;
    }

    let unreadCount: number = 0;
    if (i % 7 === 3) {
      unreadCount = 128; // 触发 99+ 徽标样式
    } else if (i % 3 === 0) {
      unreadCount = ((i * 7) % 9) + 1;
    }

    items.push(new ChatListItem(
      chatId,
      title,
      preview,
      cursor,
      unreadCount,
      avatarColorForChatId(chatId),
      avatarLetterForTitle(title)
    ));

    // 相邻会话间隔 3..139 分钟，50 条约覆盖 3 天
    cursor -= (3 + ((i * 17) % 137)) * MINUTE_MS;
  }
  return items;
}
