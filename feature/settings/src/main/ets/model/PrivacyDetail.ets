/**
 * feature/settings — 隐私设置详情页状态（PRIVACY-101 / FEAT-SET-001 隐私分区）。
 *
 * 为什么状态里直接揣着一条 TDLib 规则列表：隐私项的真值是**有序**规则表，例外名单的
 * 生效与否取决于它排在主档位规则之前还是之后（首个命中生效）。改成「主档 + 两个 id 数组」
 * 会丢掉先后信息 —— Android 正是用 `add(0, …)` 表达「最后改的那份例外优先」，所以这里
 * 保留原列表，界面上的每一次改动都由 `PrivacyRules.ets` 的纯函数改写它。
 *
 * 写回时机照 Android：页面内所有编辑只改本地 `rules` 并置 `dirty`，**离开页面那一次**才
 * `setUserPrivacySettingRules`（Android `onBlur → saveChanges`，`nothingChanged()` 时不发）。
 */

import {
  UserPrivacySettingRuleAllowChatMembers,
  UserPrivacySettingRuleAllowUsers,
  UserPrivacySettingRuleRestrictChatMembers,
  UserPrivacySettingRuleRestrictUsers,
  TdUserPrivacySettingRule,
  User
} from '@tgx/core-td-api-generated';
import { PrivacySettingKey } from './PrivacySettings';
import {
  parsePrivacyRules,
  PrivacyRulesView,
  privacyNeedAlwaysAllow,
  privacyNeedNeverAllow
} from './PrivacyRules';

export type PrivacyExceptionTarget = 'always' | 'never';

/** 例外名单行：userId + 已解析好的显示名（联系人没有名字时退回电话，不印裸 id）。 */
export class PrivacyExceptionRow {
  readonly userId: number;
  readonly title: string;

  constructor(userId: number, title: string) {
    this.userId = userId;
    this.title = title;
  }
}

/** 选择器里的一行联系人。 */
export class PrivacyContactRow {
  readonly userId: number;
  readonly title: string;
  readonly selected: boolean;

  constructor(userId: number, title: string, selected: boolean) {
    this.userId = userId;
    this.title = title;
    this.selected = selected;
  }

  withSelected(selected: boolean): PrivacyContactRow {
    if (this.selected === selected) {
      return this;
    }
    return new PrivacyContactRow(this.userId, this.title, selected);
  }
}

/** 「谁总是允许 / 谁从不允许」两行的呈现数据（含只计人数的群成员例外）。 */
export class PrivacyExceptionsView {
  readonly alwaysRows: PrivacyExceptionRow[];
  readonly neverRows: PrivacyExceptionRow[];
  readonly alwaysChatMemberCount: number;
  readonly neverChatMemberCount: number;
  readonly showAlwaysRow: boolean;
  readonly showNeverRow: boolean;

  constructor(
    alwaysRows: PrivacyExceptionRow[],
    neverRows: PrivacyExceptionRow[],
    alwaysChatMemberCount: number,
    neverChatMemberCount: number,
    showAlwaysRow: boolean,
    showNeverRow: boolean
  ) {
    this.alwaysRows = alwaysRows;
    this.neverRows = neverRows;
    this.alwaysChatMemberCount = alwaysChatMemberCount;
    this.neverChatMemberCount = neverChatMemberCount;
    this.showAlwaysRow = showAlwaysRow;
    this.showNeverRow = showNeverRow;
  }
}

/**
 * 详情页的一屏状态。`null` 表示没有打开任何一项（与「打开了但还在读」是两件事）。
 */
export class PrivacyDetailState {
  readonly key: PrivacySettingKey;
  readonly loading: boolean;
  readonly saving: boolean;
  /** 当前生效的规则列表（本地编辑后的结果）。 */
  readonly rules: TdUserPrivacySettingRule[];
  /** 服务端已生效的规则快照，用于判断有没有未保存的改动。 */
  readonly savedRules: TdUserPrivacySettingRule[];
  /** 全量联系人，选择器的数据源（`selected` 只反映当前例外名单）。 */
  readonly contacts: PrivacyContactRow[];
  /** 正在编辑哪一份名单；null 表示选择器没开。 */
  readonly pickerTarget: PrivacyExceptionTarget | null;
  /** 选择器里的勾选集合（点「完成」前不写回规则）。 */
  readonly pickedUserIds: number[];
  readonly errorMessage: string | null;

  constructor(
    key: PrivacySettingKey,
    loading: boolean,
    saving: boolean,
    rules: TdUserPrivacySettingRule[],
    savedRules: TdUserPrivacySettingRule[],
    contacts: PrivacyContactRow[],
    pickerTarget: PrivacyExceptionTarget | null,
    pickedUserIds: number[],
    errorMessage: string | null
  ) {
    this.key = key;
    this.loading = loading;
    this.saving = saving;
    this.rules = rules;
    this.savedRules = savedRules;
    this.contacts = contacts;
    this.pickerTarget = pickerTarget;
    this.pickedUserIds = pickedUserIds;
    this.errorMessage = errorMessage;
  }

  static forLoading(key: PrivacySettingKey): PrivacyDetailState {
    return new PrivacyDetailState(key, true, false, [], [], [], null, [], null);
  }

  static forLoaded(
    key: PrivacySettingKey,
    rules: TdUserPrivacySettingRule[],
    contacts: PrivacyContactRow[]
  ): PrivacyDetailState {
    return new PrivacyDetailState(key, false, false, rules, rules.slice(), contacts, null, [], null);
  }

  copyWith(
    options: PrivacyDetailStateOptions = {}
  ): PrivacyDetailState {
    return new PrivacyDetailState(
      options.key !== undefined ? options.key : this.key,
      options.loading !== undefined ? options.loading : this.loading,
      options.saving !== undefined ? options.saving : this.saving,
      options.rules !== undefined ? options.rules : this.rules,
      options.savedRules !== undefined ? options.savedRules : this.savedRules,
      options.contacts !== undefined ? options.contacts : this.contacts,
      options.pickerTarget !== undefined ? options.pickerTarget : this.pickerTarget,
      options.pickedUserIds !== undefined ? options.pickedUserIds : this.pickedUserIds,
      options.errorMessage !== undefined ? options.errorMessage : this.errorMessage
    );
  }

  /** 有没有未保存的改动（Android `nothingChanged()` 的反面）。 */
  isDirty(): boolean {
    return privacyRulesEqual(this.rules, this.savedRules) === false;
  }
}

interface PrivacyDetailStateOptions {
  key?: PrivacySettingKey;
  loading?: boolean;
  saving?: boolean;
  rules?: TdUserPrivacySettingRule[];
  savedRules?: TdUserPrivacySettingRule[];
  contacts?: PrivacyContactRow[];
  pickerTarget?: PrivacyExceptionTarget | null;
  pickedUserIds?: number[];
  errorMessage?: string | null;
}

/**
 * 规则列表是否等价 —— 按**序列化结果**比，不按对象引用。
 * 需要的是「这批规则写回服务端会不会产生任何变化」，所以两条同类型同 id 集合的规则算相等，
 * 而例外名单里 id 顺序变了同样算变化（TDLib 会保留顺序，界面回读也就跟着变）。
 */
export function privacyRulesEqual(
  left: TdUserPrivacySettingRule[],
  right: TdUserPrivacySettingRule[]
): boolean {
  if (left.length !== right.length) {
    return false;
  }
  for (let i = 0; i < left.length; i++) {
    if (left[i].type !== right[i].type) {
      return false;
    }
    if (privacyRuleIds(left[i]).length !== privacyRuleIds(right[i]).length) {
      return false;
    }
    const a: number[] = privacyRuleIds(left[i]);
    const b: number[] = privacyRuleIds(right[i]);
    for (let j = 0; j < a.length; j++) {
      if (a[j] !== b[j]) {
        return false;
      }
    }
  }
  return true;
}

/** 规则携带的 id 集合（用户或群成员）；主档位类规则回空数组。 */
export function privacyRuleIds(rule: TdUserPrivacySettingRule): number[] {
  if (rule.type === 'userPrivacySettingRuleAllowUsers') {
    return (rule as UserPrivacySettingRuleAllowUsers).user_ids.slice();
  }
  if (rule.type === 'userPrivacySettingRuleRestrictUsers') {
    return (rule as UserPrivacySettingRuleRestrictUsers).user_ids.slice();
  }
  if (rule.type === 'userPrivacySettingRuleAllowChatMembers') {
    return (rule as UserPrivacySettingRuleAllowChatMembers).chat_ids.slice();
  }
  if (rule.type === 'userPrivacySettingRuleRestrictChatMembers') {
    return (rule as UserPrivacySettingRuleRestrictChatMembers).chat_ids.slice();
  }
  return [];
}

/**
 * 用户 → 展示名。
 * 顺序照 Android 的取名规则：全名 → @用户名 → 电话号码；都没有时用固定占位，
 * 而不是把裸 userId 印给用户（列表里出现一串数字读不出意义）。
 */
export function privacyUserTitle(user: User | null): string {
  if (user === null) {
    return 'Unknown User';
  }
  const first: string = user.first_name.trim();
  const last: string = user.last_name.trim();
  const fullName: string = first.length > 0 ? (last.length > 0 ? `${first} ${last}` : first) : '';
  if (fullName.length > 0) {
    return fullName;
  }
  if (user.usernames !== null && user.usernames.active_usernames.length > 0) {
    return `@${user.usernames.active_usernames[0]}`;
  }
  if (user.phone_number.trim().length > 0) {
    return user.phone_number.trim();
  }
  return 'Unknown User';
}

/** 是否可进选择器列表：只列真人、且不含自己（Android picker 的 FLAG_NO_BOTS|FLAG_NO_SELF）。 */
export function privacyContactSelectable(user: User, selfUserId: number): boolean {
  if (user.id === selfUserId || user.id === 0) {
    return false;
  }
  return user.type_ !== null && user.type_.type === 'userTypeRegular';
}

/** 多选器数据源：TDLib `getContacts` 的返回顺序即联系人页顺序，这里不再二次排序。 */
export function privacyContactRows(
  users: User[],
  selfUserId: number,
  pickedUserIds: number[]
): PrivacyContactRow[] {
  const rows: PrivacyContactRow[] = [];
  for (let i = 0; i < users.length; i++) {
    const user: User = users[i];
    if (!privacyContactSelectable(user, selfUserId)) {
      continue;
    }
    rows.push(new PrivacyContactRow(
      user.id,
      privacyUserTitle(user),
      pickedUserIds.indexOf(user.id) >= 0
    ));
  }
  return rows;
}

/**
 * 例外名单行：按规则里的 id 顺序取名。
 * 解析不到名字的人**保留成占位行**而不是丢掉 —— 名单里确实有这个人，
 * 静默删行等于在界面上谎报服务端状态。
 * 名字来源是联系人视图：Android 的选择器只列联系人，所以例外名单里的人正常都有名字；
 * 只有「后来被删出通讯录」的人才会落到占位文案。
 */
export function privacyExceptionRows(
  userIds: number[],
  contacts: PrivacyContactRow[]
): PrivacyExceptionRow[] {
  const rows: PrivacyExceptionRow[] = [];
  for (let i = 0; i < userIds.length; i++) {
    let title: string = 'Unknown User';
    for (let j = 0; j < contacts.length; j++) {
      if (contacts[j].userId === userIds[i]) {
        title = contacts[j].title;
        break;
      }
    }
    rows.push(new PrivacyExceptionRow(userIds[i], title));
  }
  return rows;
}

/**
 * 选择器的勾选态：`contacts` 只存人和名字，勾了谁由 `pickedUserIds` 决定。
 * 每次勾选都重建一次行，UI 直接读 `row.selected`，不需要在页面里做二次判断。
 */
export function privacyContactsWithPicked(
  contacts: PrivacyContactRow[],
  pickedUserIds: number[]
): PrivacyContactRow[] {
  const rows: PrivacyContactRow[] = [];
  for (let i = 0; i < contacts.length; i++) {
    rows.push(contacts[i].withSelected(pickedUserIds.indexOf(contacts[i].userId) >= 0));
  }
  return rows;
}

/**
 * 「总是允许 / 从不允许」两行的呈现数据（Android `needAlwaysAllow` / `needNeverAllow`）。
 * 群成员例外在本端不可编辑，但要照 Android 计入人数，否则人数和名单对不上。
 */
export function privacyExceptionsView(
  rules: TdUserPrivacySettingRule[],
  contacts: PrivacyContactRow[]
): PrivacyExceptionsView {
  const view: PrivacyRulesView = parsePrivacyRules(rules);
  return new PrivacyExceptionsView(
    privacyExceptionRows(view.plusUserIds, contacts),
    privacyExceptionRows(view.minusUserIds, contacts),
    view.plusChatIds.length,
    view.minusChatIds.length,
    privacyNeedAlwaysAllow(rules),
    privacyNeedNeverAllow(view)
  );
}

