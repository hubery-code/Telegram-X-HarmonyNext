/**
 * feature/chat_list — 会话列表行视图模型（CHATLIST-002）。
 *
 * ChatListItem 是渲染一行所需的扁平不可变数据，由领域层 Chat 投影
 * （CHATLIST-001 的 ChatRegistry / ChatListProjection）或 Mock 生成器产出。
 * 头像占位色与首字母在这里派生：颜色按 chatId 稳定取色板，
 * 字母取标题首字符大写；色板是装饰性数据，不进 design token。
 *
 * MSG-108 新增：
 * - isPinned：该会话在当前列表中被置顶（TDLib ChatPosition.is_pinned），
 *   行内时间戳左侧出置顶标；
 * - isMarkedAsUnread：手动标未读标记。它与 unreadCount 独立——标未读不产生
 *   未读消息数，所以"标记置位 + 未读数 0"时用圆点徽标表达。
 * 两个字段都带默认值 false，保持既有调用点向后兼容。
 */

export type ChatCategory = 'private' | 'group' | 'channel';

export class ChatListItem {
  readonly chatId: number;
  readonly title: string;
  readonly lastMessagePreview: string;
  readonly timestampMs: number;
  readonly unreadCount: number;
  readonly avatarColor: string;
  readonly avatarLetter: string;
  readonly isPinned: boolean;
  readonly isMarkedAsUnread: boolean;
  readonly avatarPath: string | null;
  readonly draftText: string | null;
  readonly isMuted: boolean;
  readonly category: ChatCategory;

  constructor(
    chatId: number,
    title: string,
    lastMessagePreview: string,
    timestampMs: number,
    unreadCount: number,
    avatarColor: string,
    avatarLetter: string,
    isPinned: boolean = false,
    isMarkedAsUnread: boolean = false,
    avatarPath: string | null = null,
    draftText: string | null = null,
    isMuted: boolean = false,
    category: ChatCategory = 'private'
  ) {
    this.chatId = chatId;
    this.title = title;
    this.lastMessagePreview = lastMessagePreview;
    this.timestampMs = timestampMs;
    this.unreadCount = unreadCount;
    this.avatarColor = avatarColor;
    this.avatarLetter = avatarLetter;
    this.isPinned = isPinned;
    this.isMarkedAsUnread = isMarkedAsUnread;
    this.avatarPath = avatarPath;
    this.draftText = draftText;
    this.isMuted = isMuted;
    this.category = category;
  }
}

/** Telegram 经典头像占位色板（'#AARRGGBB'）。 */
export const AVATAR_PALETTE: string[] = [
  '#FFCC5049', // red
  '#FFD67722', // orange
  '#FF955CDB', // violet
  '#FF40A920', // green
  '#FF309EBA', // cyan
  '#FF368AD1', // blue
  '#FFC7508B'  // pink
];

/** 同一 chatId 恒得同一颜色。 */
export function avatarColorForChatId(chatId: number): string {
  const idx: number = Math.abs(chatId) % AVATAR_PALETTE.length;
  return AVATAR_PALETTE[idx];
}

/** 标题首字符大写作为占位字母；空标题回退 '?'。 */
export function avatarLetterForTitle(title: string): string {
  const trimmed: string = title.trim();
  if (trimmed.length === 0) {
    return '?';
  }
  return trimmed.charAt(0).toUpperCase();
}
