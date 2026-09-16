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

export type ContactsIntent =
  | QueryChanged
  | OnContactsLoaded
  | OnContactsFailed
  | ContactTapped;
