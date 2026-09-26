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
  Chat,
  ChatTypeSupergroup,
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
  privacyAlwaysAllowCount,
  privacyNeedAlwaysAllow,
  privacyNeedNeverAllow,
  privacyNeverAllowCount
} from './PrivacyRules';

export type PrivacyExceptionTarget = 'always' | 'never';

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

/**
 * 选择器里的一行会话（只有群与超大群，频道不可选 —— 见 `privacyChatSelectable`）。
 * `memberCount` 是 TDLib 报的人员数，0 表示「不知道」（`supergroup.member_count` 允许未知），
 * 未知就不编造文案。
 */
export class PrivacyChatRow {
  readonly chatId: number;
  readonly title: string;
  readonly memberCount: number;
  readonly selected: boolean;

  constructor(chatId: number, title: string, memberCount: number, selected: boolean) {
    this.chatId = chatId;
    this.title = title;
    this.memberCount = memberCount;
    this.selected = selected;
  }

  withSelected(selected: boolean): PrivacyChatRow {
    if (this.selected === selected) {
      return this;
    }
    return new PrivacyChatRow(this.chatId, this.title, this.memberCount, selected);
  }
}

/**
 * 「总是允许 / 从不允许」两行的呈现数据。
 * 只有人数没有名单：Android 的那两行 value 就是 `xUsers` 复数文案（`getPlusTotalCount`），
 * 名字只在点开后于选择器里以勾选态出现，所以这里不携带行数组。
 */
export class PrivacyExceptionsView {
  /** 人数口径照 Android：用户数 + 各会话成员数之和（不是会话条数）。 */
  readonly alwaysCount: number;
  readonly neverCount: number;
  readonly showAlwaysRow: boolean;
  readonly showNeverRow: boolean;

  constructor(
    alwaysCount: number,
    neverCount: number,
    showAlwaysRow: boolean,
    showNeverRow: boolean
  ) {
    this.alwaysCount = alwaysCount;
    this.neverCount = neverCount;
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
  /** 全量联系人，选择器的一组数据源（`selected` 只反映当前例外名单）。 */
  readonly contacts: PrivacyContactRow[];
  /**
   * 会话候选：最近会话里的群与超大群，**外加**例外名单已经引用到的会话（否则名单里的群在界
   * 面上会退成一个没有名字的占位行）。选择器的另一组数据源。
   */
  readonly chats: PrivacyChatRow[];
  /** 正在编辑哪一份名单；null 表示选择器没开。 */
  readonly pickerTarget: PrivacyExceptionTarget | null;
  /** 选择器里的勾选集合（点「完成」前不写回规则）。 */
  readonly pickedUserIds: number[];
  readonly pickedChatIds: number[];
  readonly errorMessage: string | null;

  constructor(
    key: PrivacySettingKey,
    loading: boolean,
    saving: boolean,
    rules: TdUserPrivacySettingRule[],
    savedRules: TdUserPrivacySettingRule[],
    contacts: PrivacyContactRow[],
    chats: PrivacyChatRow[],
    pickerTarget: PrivacyExceptionTarget | null,
    pickedUserIds: number[],
    pickedChatIds: number[],
    errorMessage: string | null
  ) {
    this.key = key;
    this.loading = loading;
    this.saving = saving;
    this.rules = rules;
    this.savedRules = savedRules;
    this.contacts = contacts;
    this.chats = chats;
    this.pickerTarget = pickerTarget;
    this.pickedUserIds = pickedUserIds;
    this.pickedChatIds = pickedChatIds;
    this.errorMessage = errorMessage;
  }

  static forLoading(key: PrivacySettingKey): PrivacyDetailState {
    return new PrivacyDetailState(key, true, false, [], [], [], [], null, [], [], null);
  }

  static forLoaded(
    key: PrivacySettingKey,
    rules: TdUserPrivacySettingRule[],
    contacts: PrivacyContactRow[],
    chats: PrivacyChatRow[]
  ): PrivacyDetailState {
    return new PrivacyDetailState(
      key, false, false, rules, rules.slice(), contacts, chats, null, [], [], null
    );
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
      options.chats !== undefined ? options.chats : this.chats,
      options.pickerTarget !== undefined ? options.pickerTarget : this.pickerTarget,
      options.pickedUserIds !== undefined ? options.pickedUserIds : this.pickedUserIds,
      options.pickedChatIds !== undefined ? options.pickedChatIds : this.pickedChatIds,
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
  chats?: PrivacyChatRow[];
  pickerTarget?: PrivacyExceptionTarget | null;
  pickedUserIds?: number[];
  pickedChatIds?: number[];
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
 * 会话是否可进选择器：群与超大群可以，**频道不行**，私聊 / 密聊 / Saved Messages 也不进。
 * Android 的选择器是 `ContactsController` 带 `FLAG_NO_CHANNELS`，且「会话成员」这条例外
 * 语义上只对群成立（频道没有「成员能把设置传给谁」这回事）。
 */
export function privacyChatSelectable(chat: Chat): boolean {
  if (chat.id === 0 || chat.type_ === null) {
    return false;
  }
  if (chat.type_.type === 'chatTypeBasicGroup') {
    return true;
  }
  if (chat.type_.type === 'chatTypeSupergroup') {
    return (chat.type_ as ChatTypeSupergroup).is_channel === false;
  }
  return false;
}

/** 会话标题：TDLib 允许 title 为空（名字还没同步下来），此时回占位而不是留一行空白。 */
export function privacyChatTitle(chat: Chat): string {
  const title: string = chat.title.trim();
  return title.length > 0 ? title : 'Unknown Chat';
}

/**
 * 会话候选 → 选择器的「会话」分区。
 * 顺序即候选顺序（最近会话在前、名单引用项补在后），不按标题重排 —— 与联系人分区同一条规矩：
 * 不发明 Android 没有的排序。`memberCounts` 缺项或非正数按「未知」记 0，页面据此不编人数文案。
 */
export function privacyChatRows(
  chats: Chat[],
  memberCounts: Map<number, number>,
  pickedChatIds: number[]
): PrivacyChatRow[] {
  const rows: PrivacyChatRow[] = [];
  for (let i = 0; i < chats.length; i++) {
    const chat: Chat = chats[i];
    if (!privacyChatSelectable(chat)) {
      continue;
    }
    const count: number | undefined = memberCounts.get(chat.id);
    rows.push(new PrivacyChatRow(
      chat.id,
      privacyChatTitle(chat),
      count !== undefined && count > 0 ? count : 0,
      pickedChatIds.indexOf(chat.id) >= 0
    ));
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

/** 会话分区的勾选态，与 `privacyContactsWithPicked` 同理。 */
export function privacyChatsWithPicked(
  chats: PrivacyChatRow[],
  pickedChatIds: number[]
): PrivacyChatRow[] {
  const rows: PrivacyChatRow[] = [];
  for (let i = 0; i < chats.length; i++) {
    rows.push(chats[i].withSelected(pickedChatIds.indexOf(chats[i].chatId) >= 0));
  }
  return rows;
}

/** chatId → 成员数的查表；成员数只存在 `chats` 行里，不留第二份真值。 */
export function privacyChatMemberCounts(chats: PrivacyChatRow[]): Map<number, number> {
  const counts: Map<number, number> = new Map<number, number>();
  for (let i = 0; i < chats.length; i++) {
    counts.set(chats[i].chatId, chats[i].memberCount);
  }
  return counts;
}

/**
 * 「总是允许 / 从不允许」两行的呈现数据（Android `needAlwaysAllow` / `needNeverAllow`）。
 * 存在与否由规则列表的**位置**决定；人数里会话按 Android 口径算**成员数**而不是条数，
 * 所以 `chats` 要覆盖名单引用到的会话，读不到成员数时记 0（宁可少报也不猜）。
 */
export function privacyExceptionsView(
  rules: TdUserPrivacySettingRule[],
  chats: PrivacyChatRow[]
): PrivacyExceptionsView {
  const view: PrivacyRulesView = parsePrivacyRules(rules);
  const counts: Map<number, number> = privacyChatMemberCounts(chats);
  return new PrivacyExceptionsView(
    privacyAlwaysAllowCount(view, counts),
    privacyNeverAllowCount(view, counts),
    privacyNeedAlwaysAllow(rules),
    privacyNeedNeverAllow(view)
  );
}


