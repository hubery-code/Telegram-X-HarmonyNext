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
 * - chatMembers 例外（allowChatMembers / restrictChatMembers）**只读不改**：本端选择器只列
 *   联系人，不列群成员；人数照 Android 计入总数（`getPlusTotalCount`，935-969），所以读得到、
 *   改不坏。
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

/** 「总是允许」行的总人数：用户 + 群成员两个来源（Android `getPlusTotalCount`）。 */
export function privacyAlwaysAllowCount(view: PrivacyRulesView): number {
  return view.plusUserIds.length + view.plusChatIds.length;
}

export function privacyNeverAllowCount(view: PrivacyRulesView): number {
  return view.minusUserIds.length + view.minusChatIds.length;
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
 * 名单是**全量替换**（选择器回传的即最终集合）：先摘掉旧的 `allowUsers`，再从
 * `restrictUsers` 里剔除这些 id（剔空就删规则），最后把 `allowUsers` 插在**列表最前**
 * —— 例外必须先于主档位规则才可能先命中。
 */
export function privacyRulesWithAllowUsers(
  rules: TdUserPrivacySettingRule[],
  userIds: number[]
): TdUserPrivacySettingRule[] {
  return withUserException(rules, userIds, true);
}

/** 设「从不允许」名单，`privacyRulesWithAllowUsers` 的镜像（Android 869-925）。 */
export function privacyRulesWithRestrictUsers(
  rules: TdUserPrivacySettingRule[],
  userIds: number[]
): TdUserPrivacySettingRule[] {
  return withUserException(rules, userIds, false);
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
 * 两个方向的例外名单改写共用一套骨架：`allow` 为真时替换 `allowUsers`、从 `restrictUsers`
 * 里剔除；为假时反过来。 picked 为空就不插入规则（Android 同：空名单等于「这一侧没有例外」）。
 */
function withUserException(
  rules: TdUserPrivacySettingRule[],
  userIds: number[],
  allow: boolean
): TdUserPrivacySettingRule[] {
  const picked: number[] = distinctIds(userIds);
  const sameKind: string = allow
    ? 'userPrivacySettingRuleAllowUsers'
    : 'userPrivacySettingRuleRestrictUsers';
  const oppositeKind: string = allow
    ? 'userPrivacySettingRuleRestrictUsers'
    : 'userPrivacySettingRuleAllowUsers';
  const next: TdUserPrivacySettingRule[] = [];
  for (let i = 0; i < rules.length; i++) {
    const rule: TdUserPrivacySettingRule = rules[i];
    if (rule.type === sameKind) {
      continue;
    }
    if (rule.type === oppositeKind) {
      // 另一侧里被本次勾选命中的人要摘掉，摘空则整条删除。这里另起新对象而不是原地改
      // `user_ids`：旧列表还挂在 `savedRules` 上，就地改动会把「有没有未保存的编辑」抹平。
      const rest: number[] = withoutIds(userIdsOf(rule), picked);
      if (rest.length > 0) {
        next.push(ruleWithUserIds(!allow, rest));
      }
      continue;
    }
    next.push(rule);
  }
  if (picked.length > 0) {
    next.unshift(ruleWithUserIds(allow, picked));
  }
  return next;
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

function userIdsOf(rule: TdUserPrivacySettingRule): number[] {
  if (rule.type === 'userPrivacySettingRuleAllowUsers') {
    return (rule as UserPrivacySettingRuleAllowUsers).user_ids;
  }
  if (rule.type === 'userPrivacySettingRuleRestrictUsers') {
    return (rule as UserPrivacySettingRuleRestrictUsers).user_ids;
  }
  return [];
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
