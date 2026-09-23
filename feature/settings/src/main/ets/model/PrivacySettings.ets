/**
 * feature/settings — 隐私设置读写模型（SELF-102 / FEAT-SET-001 隐私分区）。
 *
 * TDLib 的隐私项是 `userPrivacySettingRules`（有序规则列表，首个命中的规则生效），
 * 而设置页要展示的是 Telegram 那种「所有人 / 我的联系人 / 没有人」单选行。
 * 这里做两端都纯的映射：
 * - `choiceFromRules`：只有单条简单规则才认成一个明确选项，带例外名单（多条规则）
 *   一律归 `custom`，避免把「联系人但排除某几人」错显示成「联系人」；
 * - `rulesForChoice`：写回时只发一条简单规则，与 Telegram 改主可见范围即重置
 *   例外名单的行为一致。
 */

import {
  UserPrivacySettingAllowCalls,
  UserPrivacySettingAllowChatInvites,
  UserPrivacySettingAllowFindingByPhoneNumber,
  UserPrivacySettingRuleAllowAll,
  UserPrivacySettingRuleAllowContacts,
  UserPrivacySettingRuleAllowPremiumUsers,
  UserPrivacySettingRuleRestrictAll,
  UserPrivacySettingShowBio,
  UserPrivacySettingShowBirthdate,
  UserPrivacySettingShowPhoneNumber,
  UserPrivacySettingShowProfilePhoto,
  UserPrivacySettingShowStatus,
  TdUserPrivacySetting,
  TdUserPrivacySettingRule
} from '@tgx/core-td-api-generated';

export type PrivacySettingKey =
  | 'show_last_seen'
  | 'show_phone_number'
  | 'show_profile_photo'
  | 'show_bio'
  | 'show_birthdate'
  | 'allow_calls'
  | 'allow_chat_invites'
  | 'allow_find_by_phone';

export type PrivacyChoice = 'everybody' | 'premium' | 'contacts' | 'nobody' | 'custom' | 'unknown';

/** 页面上的一行：设置项 + 当前可见范围。 */
export class PrivacySettingItem {
  readonly key: PrivacySettingKey;
  readonly choice: PrivacyChoice;

  constructor(key: PrivacySettingKey, choice: PrivacyChoice) {
    this.key = key;
    this.choice = choice;
  }

  withChoice(choice: PrivacyChoice): PrivacySettingItem {
    if (this.choice === choice) {
      return this;
    }
    return new PrivacySettingItem(this.key, choice);
  }
}

/** 设置页展示顺序（对齐 TGX：在线状态与手机号在前）。 */
export const PRIVACY_SETTING_KEYS: PrivacySettingKey[] = [
  'show_last_seen',
  'show_phone_number',
  'show_profile_photo',
  'show_bio',
  'show_birthdate',
  'allow_calls',
  'allow_chat_invites',
  'allow_find_by_phone'
];

/**
 * 行标题与档位文案。
 * 返回的是 Lang 字典里的英文 key（不是成品文案），由页面 `t()` 翻译；
 * 模型层保持零 Kit / 零 Lang 依赖，单测可直接断言。
 */
export function privacySettingLabel(key: PrivacySettingKey): string {
  if (key === 'show_last_seen') {
    return 'Last Seen';
  }
  if (key === 'show_phone_number') {
    return 'Phone Number';
  }
  if (key === 'show_profile_photo') {
    return 'Profile Photo';
  }
  if (key === 'show_bio') {
    return 'Bio';
  }
  if (key === 'show_birthdate') {
    return 'Date of Birth';
  }
  if (key === 'allow_calls') {
    return 'Calls';
  }
  if (key === 'allow_chat_invites') {
    return 'Group and Channel Invites';
  }
  return 'Discoverable by Phone Number';
}

export function privacyChoiceLabel(choice: PrivacyChoice): string {
  if (choice === 'everybody') {
    return 'Everybody';
  }
  if (choice === 'premium') {
    return 'Premium Users';
  }
  if (choice === 'contacts') {
    return 'My Contacts';
  }
  if (choice === 'nobody') {
    return 'Nobody';
  }
  if (choice === 'custom') {
    return 'Custom';
  }
  return 'Unknown';
}

/** TDLib 设置对象（请求负载里的 `setting`）。 */
export function toUserPrivacySetting(key: PrivacySettingKey): TdUserPrivacySetting {
  if (key === 'show_last_seen') {
    return new UserPrivacySettingShowStatus();
  }
  if (key === 'show_phone_number') {
    return new UserPrivacySettingShowPhoneNumber();
  }
  if (key === 'show_profile_photo') {
    return new UserPrivacySettingShowProfilePhoto();
  }
  if (key === 'show_bio') {
    return new UserPrivacySettingShowBio();
  }
  if (key === 'show_birthdate') {
    return new UserPrivacySettingShowBirthdate();
  }
  if (key === 'allow_calls') {
    return new UserPrivacySettingAllowCalls();
  }
  if (key === 'allow_chat_invites') {
    return new UserPrivacySettingAllowChatInvites();
  }
  return new UserPrivacySettingAllowFindingByPhoneNumber();
}

/**
 * 规则 → 选项。
 * 列表里的规则全是 allow 语义（`restrictAll` 表示「到此为止，不再往下匹配」），
 * 因此空列表意味着没有任何人能看到 → `nobody`，不是读取失败。
 * 设备实测依据：给 `show_birthdate` 写入 `restrictAll` 后，TDLib 读回的就是
 * `rules=[]`（该设置的「没有人」不需要落库），所以这里必须认成 nobody，
 * 否则页面上会出现一个用户看不懂的 Unknown 行。
 * `unknown` 只保留给「该项读取失败」这一种情况，由 coordinator 直接构造。
 */
export function choiceFromRules(rules: TdUserPrivacySettingRule[]): PrivacyChoice {
  if (rules.length === 0) {
    return 'nobody';
  }
  if (rules.length !== 1) {
    return 'custom';
  }
  const type: string = rules[0].type;
  if (type === 'userPrivacySettingRuleAllowAll') {
    return 'everybody';
  }
  if (type === 'userPrivacySettingRuleAllowPremiumUsers') {
    return 'premium';
  }
  if (type === 'userPrivacySettingRuleAllowContacts') {
    return 'contacts';
  }
  if (type === 'userPrivacySettingRuleRestrictAll') {
    return 'nobody';
  }
  return 'custom';
}

/** 选项 → 规则；`custom`/`unknown` 没有对应的单条规则，写回路径必须挡掉。 */
export function rulesForChoice(choice: PrivacyChoice): TdUserPrivacySettingRule[] {
  const rules: TdUserPrivacySettingRule[] = [];
  if (choice === 'everybody') {
    rules.push(new UserPrivacySettingRuleAllowAll());
    return rules;
  }
  if (choice === 'premium') {
    rules.push(new UserPrivacySettingRuleAllowPremiumUsers());
    return rules;
  }
  if (choice === 'contacts') {
    rules.push(new UserPrivacySettingRuleAllowContacts());
    return rules;
  }
  rules.push(new UserPrivacySettingRuleRestrictAll());
  return rules;
}

/**
 * 点一行即在下拉的三档间循环（TGX 的例外名单编辑器尚未拆包，
 * 自定义/未知态从「我的联系人」重新开始，保证点一下就有确定结果）。
 */
export function nextPrivacyChoice(current: PrivacyChoice): PrivacyChoice {
  if (current === 'everybody') {
    return 'contacts';
  }
  if (current === 'premium') {
    return 'contacts';
  }
  if (current === 'contacts') {
    return 'nobody';
  }
  if (current === 'nobody') {
    return 'everybody';
  }
  return 'contacts';
}

/** 该选项能否直接写回 TDLib。 */
export function isPrivacyChoiceWritable(choice: PrivacyChoice): boolean {
  return choice === 'everybody' || choice === 'premium' || choice === 'contacts' || choice === 'nobody';
}
