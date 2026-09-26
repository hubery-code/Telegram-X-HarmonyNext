/**
 * feature/settings — 隐私设置项与页面投影（SELF-102 / FEAT-SET-001 隐私分区）。
 *
 * TDLib 的隐私项是 `userPrivacySettingRules`（有序规则列表，首个命中的规则生效）。
 * 列表 → 行文案的解析、改档、例外名单改写全部在 `PrivacyRules.ets`（纯函数、Kit-free）；
 * 本文件只留「有哪几项、叫什么、对应哪个 TDLib 设置对象」与页面上的一行。
 *
 * PRIVACY-101 起列表行不再自己持有规则：一行要显示的是主档位 + 例外人数，而详情页要的是
 * 整条列表，所以列表页与详情页共用 `PrivacyRulesView`，写回一律经详情页。
 */

import {
  UserPrivacySettingAllowCalls,
  UserPrivacySettingAllowChatInvites,
  UserPrivacySettingAllowFindingByPhoneNumber,
  UserPrivacySettingShowBio,
  UserPrivacySettingShowBirthdate,
  UserPrivacySettingShowPhoneNumber,
  UserPrivacySettingShowProfilePhoto,
  UserPrivacySettingShowStatus,
  TdUserPrivacySetting
} from '@tgx/core-td-api-generated';
import { PrivacyRulesView, privacyModeLabel } from './PrivacyRules';

export type PrivacySettingKey =
  | 'show_last_seen'
  | 'show_phone_number'
  | 'show_profile_photo'
  | 'show_bio'
  | 'show_birthdate'
  | 'allow_calls'
  | 'allow_chat_invites'
  | 'allow_find_by_phone';

/**
 * 列表里的一行。
 * `view === null` 只表示「这一项 TDLib 没读到」，绝不退成一个猜出来的默认档。
 */
export class PrivacySettingItem {
  readonly key: PrivacySettingKey;
  readonly view: PrivacyRulesView | null;

  constructor(key: PrivacySettingKey, view: PrivacyRulesView | null) {
    this.key = key;
    this.view = view;
  }

  withView(view: PrivacyRulesView): PrivacySettingItem {
    return new PrivacySettingItem(this.key, view);
  }
}

/**
 * 行的副标题（当前可见范围）。返回 Lang key，由页面 `t()` 翻译。
 * 入参可为 null：列表页在项未加载到时会先渲染占位，这里统一回「Unknown」而不是猜一个档位。
 */
export function privacyRowLabel(item: PrivacySettingItem | null): string {
  if (item === null || item.view === null) {
    return 'Unknown';
  }
  return privacyModeLabel(item.view.mode, item.view.plusPremium);
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
 * 行标题。返回的是 Lang 字典里的英文 key（不是成品文案），由页面 `t()` 翻译；
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
