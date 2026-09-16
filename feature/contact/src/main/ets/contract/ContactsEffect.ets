/**
 * feature/contact — 联系人页效应（CONTACT-101）。
 */

import { Effect } from '@tgx/feature-template';

/**
 * 拉取通讯录：getContacts → user_ids → 逐用户 getUser 汇总。
 * 由协调器 start() 触发，也预留「失败重试 / 下拉刷新」复用同一条效应路径。
 */
export class FetchContacts implements Effect {
  readonly kind: 'fetchContacts' = 'fetchContacts';
}

/** ContactTapped 的导航效应：交给装配层打开对应用户资料页。 */
export class OpenUserProfile implements Effect {
  readonly kind: 'openUserProfile' = 'openUserProfile';
  readonly userId: number;

  constructor(userId: number) {
    this.userId = userId;
  }
}

export type ContactsEffect = FetchContacts | OpenUserProfile;
