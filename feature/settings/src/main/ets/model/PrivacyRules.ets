/**
 * feature/settings — 隐私例外名单模型（PRIVACY-101 / FEAT-SET-001 隐私分区）。
 *
 * 端口自 Android `telegram/PrivacySettings.java`：解析照 `valueOf`（975-1082），改档照
 * `toggleGlobal`（274-326），例外名单照 `allowExceptions` / `disallowExceptions`（790-925）。
 *
 * 为什么必须要整条规则列表：TDLib 的隐私项是**有序**规则表，首个命中的规则生效，所以
 * 「谁能看」的真值 =（主档位 + 前置例外名单）。旧版只看 `rules.length !== 1` 就把一项归成
 * `custom`，并且点击该行会写回**单条**简单规则 —— 那等于把用户维护的例外名单静默删掉。
 *
 * 两条有意偏离，各自带理由：
 * - bots 规则（allowBots / restrictBots）**原样保留、不参与改档**。Android 会按新档位重写它
 *   （`toggleGlobal:299-308`），但本端界面没有 bots 行，重写等于在一个用户看不见的维度上
 *   产生副作用。
 * - 例外名单改写的**插入位置**照 Android，但分类的是新列表：`allowExceptions` 的索引循环里
 *   读的是 `rules.get(index)`（字段，不是刚改完的 `newRules`），而循环边界却是
 *   `index < newRules.size()` —— 两条列表长度不同时那个 index 判定就是错的。本端统一按
 *   `newRules` 分类（PRIVACY-102），其余顺序规则一字不改。
 */

import {
  UserPrivacySettingRuleAllowAll,
  UserPrivacySettingRuleAllowChatMembers,
  UserPrivacySettingRuleAllowContacts,
  UserPrivacySettingRuleAllowPremiumUsers,
  UserPrivacySettingRuleAllowUsers,
  UserPrivacySettingRuleRestrictAll,
  UserPrivacySettingRuleRestrictChatMembers,
  UserPrivacySettingRuleRestrictUsers,
  TdUserPrivacySettingRule
} from '@tgx/core-td-api-generated';

/** 主档位。Android 同样是三档（`Mode.NOBODY/CONTACTS/EVERYBODY`）。 */
export type PrivacyMode = 'nobody' | 'contacts' | 'everybody';

export type PrivacyBotsException = 'default' | 'allow' | 'restrict';

/** 一条规则列表解析出来的视图（只含展示与判定需要的信息）。 */
export class PrivacyRulesView {
  readonly mode: PrivacyMode;
  readonly plusPremium: boolean;
  readonly plusUserIds: number[];
  readonly minusUserIds: number[];
  readonly plusChatIds: number[];
  readonly minusChatIds: number[];
  readonly botsException: PrivacyBotsException;

  constructor(
    mode: PrivacyMode,
    plusPremium: boolean,
    plusUserIds: number[],
    minusUserIds: number[],
    plusChatIds: number[],
    minusChatIds: number[],
    botsException: PrivacyBotsException
  ) {
    this.mode = mode;
    this.plusPremium = plusPremium;
    this.plusUserIds = plusUserIds;
    this.minusUserIds = minusUserIds;
    this.plusChatIds = plusChatIds;
    this.minusChatIds = minusChatIds;
    this.botsException = botsException;
  }
}

/**
 * 规则列表 → 视图。
 * 照 Android 的单遍前向扫描：`allowAll` / `restrictAll` 是**终结性**规则，扫到就停，
 * 它们后面的规则一律不参与判定（TDLib 也永不匹配到那里）。`allowContacts` 只认第一条
 * （`contactsHandled` 闩），`allowPremiumUsers` 同理，所以例外名单之后再来一条主规则
 * 也不会翻转视图 —— 这不是容错，是 TDLib 的匹配语义。
 */
export function parsePrivacyRules(rules: TdUserPrivacySettingRule[]): PrivacyRulesView {
  let allowAll: boolean = false;
  let allowContacts: boolean = false;
  let contactsHandled: boolean = false;
  let premiumHandled: boolean = false;
  let plusPremium: boolean = false;
  let botsException: PrivacyBotsException = 'default';
  const plusUserIds: number[] = [];
  const minusUserIds: number[] = [];
  const plusChatIds: number[] = [];
  const minusChatIds: number[] = [];

  for (let i = 0; i < rules.length; i++) {
    const rule: TdUserPrivacySettingRule = rules[i];
    if (rule.type === 'userPrivacySettingRuleAllowAll') {
      allowAll = true;
      if (!contactsHandled) {
        allowContacts = false;
      }
      break;
    }
    if (rule.type === 'userPrivacySettingRuleRestrictAll') {
      // `contactsHandled` / `premiumHandled` 两道闩是必需的：`[AllowContacts, RestrictAll]`
      // 是「我的联系人」的标准形状，若无条件把 allowContacts 归零就会读成「没有人」。
      allowAll = false;
      if (!premiumHandled) {
        plusPremium = false;
      }
      if (!contactsHandled) {
        allowContacts = false;
      }
      break;
    }
    if (rule.type === 'userPrivacySettingRuleAllowContacts') {
      if (!contactsHandled) {
        contactsHandled = true;
        allowContacts = true;
      }
      continue;
    }
    if (rule.type === 'userPrivacySettingRuleRestrictContacts') {
      if (!contactsHandled) {
        contactsHandled = true;
        allowContacts = false;
      }
      continue;
    }
    if (rule.type === 'userPrivacySettingRuleAllowPremiumUsers') {
      if (!premiumHandled) {
        premiumHandled = true;
        plusPremium = true;
      }
      continue;
    }
    if (rule.type === 'userPrivacySettingRuleAllowBots') {
      botsException = 'allow';
      continue;
    }
    if (rule.type === 'userPrivacySettingRuleRestrictBots') {
      botsException = 'restrict';
      continue;
    }
    if (rule.type === 'userPrivacySettingRuleAllowUsers') {
      appendIds(plusUserIds, (rule as UserPrivacySettingRuleAllowUsers).user_ids);
      continue;
    }
    if (rule.type === 'userPrivacySettingRuleRestrictUsers') {
      appendIds(minusUserIds, (rule as UserPrivacySettingRuleRestrictUsers).user_ids);
      continue;
    }
    if (rule.type === 'userPrivacySettingRuleAllowChatMembers') {
      appendIds(plusChatIds, (rule as UserPrivacySettingRuleAllowChatMembers).chat_ids);
      continue;
    }
    if (rule.type === 'userPrivacySettingRuleRestrictChatMembers') {
      appendIds(minusChatIds, (rule as UserPrivacySettingRuleRestrictChatMembers).chat_ids);
      continue;
    }
    // 未知规则类型：不猜语义，整条按「非终结」跳过 —— 改档时它会原样留在列表里。
  }

  const mode: PrivacyMode = allowAll ? 'everybody' : (allowContacts ? 'contacts' : 'nobody');
  return new PrivacyRulesView(
    mode,
    plusPremium,
    plusUserIds,
    minusUserIds,
    plusChatIds,
    minusChatIds,
    botsException
  );
}

/** 「总是允许」行是否存在。照 Android `needAlwaysAllow`（59-71）：看的是列表里的位置，不是视图。 */
export function privacyNeedAlwaysAllow(rules: TdUserPrivacySettingRule[]): boolean {
  for (let i = 0; i < rules.length; i++) {
    const type: string = rules[i].type;
    if (isGeneralRuleType(type)) {
      break;
    }
    if (type === 'userPrivacySettingRuleRestrictChatMembers') {
      return true;
    }
  }
  return parsePrivacyRules(rules).mode !== 'everybody';
}

/** 「从不允许」行是否存在：`nobody` 档下没有意义（Android `needNeverAllow`，69-71）。 */
export function privacyNeedNeverAllow(view: PrivacyRulesView): boolean {
  return view.mode !== 'nobody';
}

/**
 * 「总是允许」行的人数。照 Android `getPlusTotalCount`（935-969）：用户数 + **各会话成员数之和**，
 * 成员数读不到时按 0 计（不是按「会话条数」计）—— 一条 300 人的群在 Android 上就是 300。
 */
export function privacyAlwaysAllowCount(
  view: PrivacyRulesView,
  chatMemberCounts: Map<number, number>
): number {
  return view.plusUserIds.length + privacyMembersOf(view.plusChatIds, chatMemberCounts);
}

export function privacyNeverAllowCount(
  view: PrivacyRulesView,
  chatMemberCounts: Map<number, number>
): number {
  return view.minusUserIds.length + privacyMembersOf(view.minusChatIds, chatMemberCounts);
}

/** 成员数求和：未知（缺席或非正数）按 0，不猜。 */
export function privacyMembersOf(chatIds: number[], chatMemberCounts: Map<number, number>): number {
  let total: number = 0;
  for (let i = 0; i < chatIds.length; i++) {
    const count: number | undefined = chatMemberCounts.get(chatIds[i]);
    if (count !== undefined && count > 0) {
      total += count;
    }
  }
  return total;
}

/**
 * 改主档位，**例外名单原样保留**（Android `toggleGlobal`：279-293 只摘掉主档位类规则，
 * 用户/群例外显式 `break` 保位）。这是本包最关键的一条语义：从「所有人」切到「我的联系人」
 * 不能把「从不允许」名单清空 —— 旧版的单条规则写回就会犯这个错。
 *
 * `nobody` 档且列表为空时**不发** `restrictAll`：Android 311-324 同判，且设备实测过 TDLib
 * 对「没有人」读回的就是空列表（见 `PrivacySettings.ets` 里的取证记录）。
 */
export function privacyRulesForMode(
  rules: TdUserPrivacySettingRule[],
  mode: PrivacyMode,
  plusPremium: boolean
): TdUserPrivacySettingRule[] {
  const next: TdUserPrivacySettingRule[] = [];
  for (let i = 0; i < rules.length; i++) {
    if (isGeneralRuleType(rules[i].type)) {
      continue;
    }
    next.push(rules[i]);
  }
  // bots 例外保位（见文件头的偏离说明）：上面 isGeneralRuleType 不含 bots 两类，故它们已在 next 里。
  if (mode === 'everybody') {
    next.push(new UserPrivacySettingRuleAllowAll());
    return next;
  }
  if (mode === 'contacts') {
    if (plusPremium) {
      next.push(new UserPrivacySettingRuleAllowPremiumUsers());
    }
    next.push(new UserPrivacySettingRuleAllowContacts());
    next.push(new UserPrivacySettingRuleRestrictAll());
    return next;
  }
  if (next.length > 0) {
    next.push(new UserPrivacySettingRuleRestrictAll());
  }
  return next;
}

/**
 * 设「总是允许」名单（Android `allowExceptions`：790-867）。
 * 名单是**全量替换**（选择器回传的即最终集合）：`allowUsers` 与 `allowChatMembers` 两条整条摘掉，
 * 从对侧（`restrictUsers` / `restrictChatMembers`）里剔除本次勾选的 id（剔空就删规则），
 * 然后按各自的位置插回 —— 例外必须先于主档位规则才可能先命中。
 */
export function privacyRulesWithAllowExceptions(
  rules: TdUserPrivacySettingRule[],
  userIds: number[],
  chatIds: number[]
): TdUserPrivacySettingRule[] {
  return withExceptions(rules, userIds, chatIds, true);
}

/** 设「从不允许」名单，`privacyRulesWithAllowExceptions` 的镜像（Android 869-925）。 */
export function privacyRulesWithRestrictExceptions(
  rules: TdUserPrivacySettingRule[],
  userIds: number[],
  chatIds: number[]
): TdUserPrivacySettingRule[] {
  return withExceptions(rules, userIds, chatIds, false);
}

/** 档位文案（Lang key）。「我的联系人 + Premium」是 Android 的合并标签写法。 */
export function privacyModeLabel(mode: PrivacyMode, plusPremium: boolean): string {
  if (mode === 'everybody') {
    return 'Everybody';
  }
  if (mode === 'nobody') {
    return 'Nobody';
  }
  return plusPremium ? 'My Contacts & Premium' : 'My Contacts';
}

/** 主档位类规则：改档时被摘掉重建。bots 与例外名单都不在此列。 */
function isGeneralRuleType(type: string): boolean {
  return type === 'userPrivacySettingRuleAllowAll' ||
    type === 'userPrivacySettingRuleRestrictAll' ||
    type === 'userPrivacySettingRuleAllowContacts' ||
    type === 'userPrivacySettingRuleRestrictContacts' ||
    type === 'userPrivacySettingRuleAllowPremiumUsers';
}

/**
 * 两个方向的例外名单改写共用一套骨架（Android `allowExceptions` / `disallowExceptions`）。
 *
 * 位置规则是这一段的重点，两种方向**不一样**：
 * - 用户名单永远插在**列表最前**（`add(0, …)`）。
 * - 会话名单插在「用户/联系人例外之后、第一条主档位规则之前」：`allow` 侧（allowChatMembers）
 *   跳过 users/contacts/restrictChatMembers/premiumUsers 类规则，遇到 all、bots 或另一条
 *   allowChatMembers 即停；`restrict` 侧（restrictChatMembers）按 `isGeneral(…, premium 与 bots
 *   与 chatMembers 全算 general)` 判定，于是只跳过 users 类规则。两条都是 Android 原样。
 */
function withExceptions(
  rules: TdUserPrivacySettingRule[],
  userIds: number[],
  chatIds: number[],
  allow: boolean
): TdUserPrivacySettingRule[] {
  const pickedUsers: number[] = distinctIds(userIds);
  const pickedChats: number[] = distinctIds(chatIds);
  const sameUserKind: string = allow
    ? 'userPrivacySettingRuleAllowUsers'
    : 'userPrivacySettingRuleRestrictUsers';
  const sameChatKind: string = allow
    ? 'userPrivacySettingRuleAllowChatMembers'
    : 'userPrivacySettingRuleRestrictChatMembers';
  const next: TdUserPrivacySettingRule[] = [];
  for (let i = 0; i < rules.length; i++) {
    const rule: TdUserPrivacySettingRule = rules[i];
    if (rule.type === sameUserKind || rule.type === sameChatKind) {
      // 同侧整条替换：勾选集合是全量的，旧的那条没有保留价值。
      continue;
    }
    if (rule.type === 'userPrivacySettingRuleAllowUsers' ||
      rule.type === 'userPrivacySettingRuleRestrictUsers') {
      // 另一侧里被本次勾选命中的人要摘掉，摘空则整条删除。这里另起新对象而不是原地改
      // `user_ids`：旧列表还挂在 `savedRules` 上，就地改动会把「有没有未保存的编辑」抹平。
      const rest: number[] = withoutIds(privacyRuleUserIds(rule), pickedUsers);
      if (rest.length > 0) {
        // 重建时保持**原规则自己的方向**（这里是另一侧），不是本次的 allow。
        next.push(ruleWithUserIds(typeAllowsUsers(rule.type), rest));
      }
      continue;
    }
    if (rule.type === 'userPrivacySettingRuleAllowChatMembers' ||
      rule.type === 'userPrivacySettingRuleRestrictChatMembers') {
      const rest: number[] = withoutIds(privacyRuleChatIds(rule), pickedChats);
      if (rest.length > 0) {
        next.push(ruleWithChatIds(typeAllowsChatMembers(rule.type), rest));
      }
      continue;
    }
    next.push(rule);
  }
  if (pickedChats.length > 0) {
    insertAt(next, chatExceptionIndex(next, allow), ruleWithChatIds(allow, pickedChats));
  }
  if (pickedUsers.length > 0) {
    next.unshift(ruleWithUserIds(allow, pickedUsers));
  }
  return next;
}

/** 会话例外规则的插入位置：返回首个「该停下来」的下标，没有就 appended 到末尾。 */
function chatExceptionIndex(rules: TdUserPrivacySettingRule[], allow: boolean): number {
  for (let i = 0; i < rules.length; i++) {
    const type: string = rules[i].type;
    if (allow) {
      // Android 830-861：users / contacts / restrictChatMembers / premium 之后，
      // 遇 all、bots 或另一条 allowChatMembers 停。
      if (type === 'userPrivacySettingRuleAllowUsers' ||
        type === 'userPrivacySettingRuleRestrictUsers' ||
        type === 'userPrivacySettingRuleAllowContacts' ||
        type === 'userPrivacySettingRuleRestrictContacts' ||
        type === 'userPrivacySettingRuleRestrictChatMembers' ||
        type === 'userPrivacySettingRuleAllowPremiumUsers') {
        continue;
      }
      return i;
    }
    // Android 900-905：`isGeneral(rule, premium=true, bots=true, chatMembers=true)` 的否定，
    // 于是只有一条例外规则（users 两类）能让位。
    if (type === 'userPrivacySettingRuleAllowUsers' ||
      type === 'userPrivacySettingRuleRestrictUsers') {
      continue;
    }
    return i;
  }
  return rules.length;
}

function insertAt(rules: TdUserPrivacySettingRule[], index: number, rule: TdUserPrivacySettingRule): void {
  if (index < rules.length) {
    rules.splice(index, 0, rule);
    return;
  }
  rules.push(rule);
}

function ruleWithUserIds(allow: boolean, userIds: number[]): TdUserPrivacySettingRule {
  if (allow) {
    const allowed: UserPrivacySettingRuleAllowUsers = new UserPrivacySettingRuleAllowUsers();
    allowed.user_ids = userIds.slice();
    return allowed;
  }
  const restricted: UserPrivacySettingRuleRestrictUsers =
    new UserPrivacySettingRuleRestrictUsers();
  restricted.user_ids = userIds.slice();
  return restricted;
}

function ruleWithChatIds(allow: boolean, chatIds: number[]): TdUserPrivacySettingRule {
  if (allow) {
    const allowed: UserPrivacySettingRuleAllowChatMembers =
      new UserPrivacySettingRuleAllowChatMembers();
    allowed.chat_ids = chatIds.slice();
    return allowed;
  }
  const restricted: UserPrivacySettingRuleRestrictChatMembers =
    new UserPrivacySettingRuleRestrictChatMembers();
  restricted.chat_ids = chatIds.slice();
  return restricted;
}

/** users 两类规则携带的 userIds；其余规则回空。 */
function privacyRuleUserIds(rule: TdUserPrivacySettingRule): number[] {
  if (rule.type === 'userPrivacySettingRuleAllowUsers') {
    return (rule as UserPrivacySettingRuleAllowUsers).user_ids;
  }
  if (rule.type === 'userPrivacySettingRuleRestrictUsers') {
    return (rule as UserPrivacySettingRuleRestrictUsers).user_ids;
  }
  return [];
}

/** chatMembers 两类规则携带的 chatIds；其余规则回空。 */
function privacyRuleChatIds(rule: TdUserPrivacySettingRule): number[] {
  if (rule.type === 'userPrivacySettingRuleAllowChatMembers') {
    return (rule as UserPrivacySettingRuleAllowChatMembers).chat_ids;
  }
  if (rule.type === 'userPrivacySettingRuleRestrictChatMembers') {
    return (rule as UserPrivacySettingRuleRestrictChatMembers).chat_ids;
  }
  return [];
}

/** 这条规则类型是不是「允许」侧（users 两类）。 */
function typeAllowsUsers(type: string): boolean {
  return type === 'userPrivacySettingRuleAllowUsers';
}

/** 这条规则类型是不是「允许」侧（chatMembers 两类）。 */
function typeAllowsChatMembers(type: string): boolean {
  return type === 'userPrivacySettingRuleAllowChatMembers';
}

function appendIds(target: number[], source: number[]): void {
  for (let i = 0; i < source.length; i++) {
    target.push(source[i]);
  }
}

function distinctIds(ids: number[]): number[] {
  const seen: Set<number> = new Set();
  const out: number[] = [];
  for (let i = 0; i < ids.length; i++) {
    if (!seen.has(ids[i])) {
      seen.add(ids[i]);
      out.push(ids[i]);
    }
  }
  return out;
}

function withoutIds(ids: number[], excluded: number[]): number[] {
  const out: number[] = [];
  for (let i = 0; i < ids.length; i++) {
    if (excluded.indexOf(ids[i]) < 0) {
      out.push(ids[i]);
    }
  }
  return out;
}
