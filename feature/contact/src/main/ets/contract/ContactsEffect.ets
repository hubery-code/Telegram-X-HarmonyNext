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

/**
 * GROUP-CREATE-101：多选确认效应——把已选成员名单（点选顺序）交给装配层，
 * 由它接力进入命名段（GroupCreateStarted）。模式本身不动，装配层决定去留。
 */
export class ConfirmMemberSelection implements Effect {
  readonly kind: 'confirmMemberSelection' = 'confirmMemberSelection';
  readonly userIds: number[];

  constructor(userIds: number[]) {
    this.userIds = userIds;
  }
}

export type ContactsEffect = FetchContacts | OpenUserProfile | ConfirmMemberSelection;
