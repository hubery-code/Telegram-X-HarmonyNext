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
  /** 展示名：first + last 拼接（已按 localeCompare 排序）。 */
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

export interface ContactsUiStateOptions {
  isLoading?: boolean;
  errorMessage?: string | null;
  /** 搜索框文本（原始输入，不过滤首尾空白——由过滤函数归一）。 */
  query?: string;
  /** getContacts 全量结果（未经查询过滤）。 */
  allItems?: ContactsItem[];
  /** 按 query 过滤后的展示列表（page 直接渲染本字段）。 */
  items?: ContactsItem[];
}

export class ContactsUiState {
  readonly isLoading: boolean;
  readonly errorMessage: string | null;
  readonly query: string;
  readonly allItems: ContactsItem[];
  readonly items: ContactsItem[];

  constructor(
    isLoading: boolean = true,
    errorMessage: string | null = null,
    query: string = '',
    allItems: ContactsItem[] = [],
    items: ContactsItem[] = []
  ) {
    this.isLoading = isLoading;
    this.errorMessage = errorMessage;
    this.query = query;
    this.allItems = allItems;
    this.items = items;
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
      options.items !== undefined ? options.items : this.items
    );
  }
}
