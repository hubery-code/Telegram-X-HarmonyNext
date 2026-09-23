/**
 * feature/contact — 联系人页 UI 状态（CONTACT-101）。
 *
 * 不可变 + copyWith，对齐 feature/profile 的 ProfileUiState 约定。
 * 查询过滤走「双份缓冲」：allItems 保存 getContacts 全量结果，items 为
 * 按 query 过滤后的展示视图；OnContactsLoaded 同时填两份，QueryChanged
 * 基于 allItems 重算 items（纯 reducer 内完成，可单测）。
 */

/** 联系人列表行纯数据（纯数据类，跨 reducer/coordinator/page 传递）。 */
export class ContactsItem {
  readonly userId: number;
  /** 展示名：first + last 拼接（排序见 model/ContactsSections 的 contactSortKey）。 */
  readonly displayName: string;
  /** 用户名（不含 '@'）；无则空串。 */
  readonly username: string;
  /** 小头像本地路径（已下载）；否则 null 出彩色字母底。 */
  readonly avatarPath: string | null;
  /** 头像占位字母（1-2 个）。 */
  readonly avatarLetters: string;
  /** 头像/署名调色板索引（0..6），用于无头像时的彩色底。 */
  readonly colorIndex: number;
  /** 在线状态简文案：'online' / 'last seen ...' / ''。 */
  readonly statusText: string;

  constructor(
    userId: number = 0,
    displayName: string = '',
    username: string = '',
    avatarPath: string | null = null,
    avatarLetters: string = '',
    colorIndex: number = 0,
    statusText: string = ''
  ) {
    this.userId = userId;
    this.displayName = displayName;
    this.username = username;
    this.avatarPath = avatarPath;
    this.avatarLetters = avatarLetters;
    this.colorIndex = colorIndex;
    this.statusText = statusText;
  }
}

/**
 * 字母分组：由**已排序**的展示列表按相邻同字母归段（见 model/ContactsSections）。
 * 段数据进 state 而不是页面里现算：索引条的字母、跳转位移、`ForEach` 的唯一 key
 * 全都依赖同一份分段结果。
 */
export class ContactsSection {
  readonly letter: string;
  readonly items: ContactsItem[];
  /** 段首在扁平 items 里的下标（只作 ForEach key 的一部分，保证字母重复时 key 仍唯一）。 */
  readonly startIndex: number;

  constructor(letter: string = '', items: ContactsItem[] = [], startIndex: number = 0) {
    this.letter = letter;
    this.items = items;
    this.startIndex = startIndex;
  }
}

export interface ContactsUiStateOptions {
  isLoading?: boolean;
  errorMessage?: string | null;
  /** 搜索框文本（原始输入，不过滤首尾空白——由过滤函数归一）。 */
  query?: string;
  /** getContacts 全量结果（未经查询过滤）。 */
  allItems?: ContactsItem[];
  /** 按 query 过滤后的展示列表（page 直接渲染本字段）。 */
  items?: ContactsItem[];
  /** items 的字母分段（索引条与分组列表都渲染本字段）。 */
  sections?: ContactsSection[];
}

export class ContactsUiState {
  readonly isLoading: boolean;
  readonly errorMessage: string | null;
  readonly query: string;
  readonly allItems: ContactsItem[];
  readonly items: ContactsItem[];
  readonly sections: ContactsSection[];

  constructor(
    isLoading: boolean = true,
    errorMessage: string | null = null,
    query: string = '',
    allItems: ContactsItem[] = [],
    items: ContactsItem[] = [],
    sections: ContactsSection[] = []
  ) {
    this.isLoading = isLoading;
    this.errorMessage = errorMessage;
    this.query = query;
    this.allItems = allItems;
    this.items = items;
    this.sections = sections;
  }

  static initial(): ContactsUiState {
    return new ContactsUiState();
  }

  copyWith(options: ContactsUiStateOptions): ContactsUiState {
    return new ContactsUiState(
      options.isLoading !== undefined ? options.isLoading : this.isLoading,
      options.errorMessage !== undefined ? options.errorMessage : this.errorMessage,
      options.query !== undefined ? options.query : this.query,
      options.allItems !== undefined ? options.allItems : this.allItems,
      options.items !== undefined ? options.items : this.items,
      options.sections !== undefined ? options.sections : this.sections
    );
  }
}
