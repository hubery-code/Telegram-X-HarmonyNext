/**
 * feature/chat — 转发目标会话的视图模型（MSG-106 / FEAT-COMP-004）。
 *
 * 会话选择器（转发目标列表）渲染一行所需的扁平不可变数据。
 * 由装配层（entry）从会话列表数据映射而来：feature/* 之间禁止互相依赖
 * （ARCHITECTURE §2 规则 1），所以本模块不 import @tgx/feature-chat-list，
 * 只定义自己的窄视图模型，映射由 entry 完成。
 */

export class ForwardTarget {
  readonly chatId: number;
  readonly title: string;
  /** 头像占位色（'#AARRGGBB'）。 */
  readonly avatarColor: string;
  /** 头像占位首字母。 */
  readonly avatarLetter: string;
  /** true = 就是当前正在浏览的会话（可转发给自己所在的会话，Telegram X 允许）。 */
  readonly isSourceChat: boolean;
  readonly avatarPath: string | null;

  constructor(
    chatId: number,
    title: string,
    avatarColor: string,
    avatarLetter: string,
    isSourceChat: boolean = false,
    avatarPath: string | null = null
  ) {
    this.chatId = chatId;
    this.title = title;
    this.avatarColor = avatarColor;
    this.avatarLetter = avatarLetter;
    this.isSourceChat = isSourceChat;
    this.avatarPath = avatarPath;
  }
}

/**
 * 标题的本地大小写不敏感匹配（选择器的"搜索/过滤"预留纯函数）。
 * 空查询恒匹配，便于直接接入输入框。
 */
export function matchesForwardQuery(title: string, query: string): boolean {
  const trimmed: string = query.trim();
  if (trimmed.length === 0) {
    return true;
  }
  return title.toLowerCase().indexOf(trimmed.toLowerCase()) >= 0;
}
