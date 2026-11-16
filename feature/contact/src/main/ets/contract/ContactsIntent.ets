/**
 * feature/contact — 联系人页意图（CONTACT-101）。
 */

import { Intent } from '@tgx/feature-template';
import { AppError } from '@tgx/core-common';
import { ContactsItem } from './ContactsUiState';

/** 搜索框输入变化；reducer 存 query 并基于 allItems 重算过滤视图 items。 */
export class QueryChanged implements Intent {
  readonly kind: 'queryChanged' = 'queryChanged';
  readonly query: string;

  constructor(query: string) {
    this.query = query;
  }
}

/** getContacts → getUser 汇总回灌：全量列表 + 过滤视图一次填好。 */
export class OnContactsLoaded implements Intent {
  readonly kind: 'onContactsLoaded' = 'onContactsLoaded';
  readonly items: ContactsItem[];

  constructor(items: ContactsItem[]) {
    this.items = items;
  }
}

/** 加载失败（getContacts 请求级错误）。 */
export class OnContactsFailed implements Intent {
  readonly kind: 'onContactsFailed' = 'onContactsFailed';
  readonly error: AppError;

  constructor(error: AppError) {
    this.error = error;
  }
}

/** 点击联系人行 → 出 OpenUserProfile 效应（reducer 不直接导航）。 */
export class ContactTapped implements Intent {
  readonly kind: 'contactTapped' = 'contactTapped';
  readonly userId: number;

  constructor(userId: number) {
    this.userId = userId;
  }
}

// ---- GROUP-CREATE-101 建群选成员（多选模式）----

/**
 * 装配层进入「选成员」场景时派发：打开多选模式并清空旧选中集。
 * 模式是导航上下文，所以由装配层在挂载页面前派发，而不是页面自持。
 */
export class MultiSelectEnabled implements Intent {
  readonly kind: 'multiSelectEnabled' = 'multiSelectEnabled';
}

/** 点选/取消一个成员：选中集尾部追加、重复点击移除（保持点选顺序）。 */
export class MemberSelectionToggled implements Intent {
  readonly kind: 'memberSelectionToggled' = 'memberSelectionToggled';
  readonly userId: number;

  constructor(userId: number) {
    this.userId = userId;
  }
}

/** 点「下一步 (N)」：出 ConfirmMemberSelection 效应，成员名单交给装配层。 */
export class MemberSelectionConfirmed implements Intent {
  readonly kind: 'memberSelectionConfirmed' = 'memberSelectionConfirmed';
}

/** 放弃选择（返回/取消）：退出多选模式并清空选中集。 */
export class MultiSelectReset implements Intent {
  readonly kind: 'multiSelectReset' = 'multiSelectReset';
}

export type ContactsIntent =
  | QueryChanged
  | OnContactsLoaded
  | OnContactsFailed
  | ContactTapped
  | MultiSelectEnabled
  | MemberSelectionToggled
  | MemberSelectionConfirmed
  | MultiSelectReset;
