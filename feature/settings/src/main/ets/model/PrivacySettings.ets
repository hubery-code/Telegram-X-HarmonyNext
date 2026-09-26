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
import { PrivacyMode, PrivacyRulesView, privacyModeLabel } from './PrivacyRules';

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

/**
 * 这一项有没有「Nobody」档位。Android `needNobodyOption()`（:302-318）里唯一被关掉的是
 * 「按手机号找到我」—— 它的档位只有「所有人 / 我的联系人」，因为「没有人能通过号码找到我」
 * 这条语义在那一项上不存在（不搜索就是找不到，不需要一档）。
 */
export function privacyNeedNobodyOption(key: PrivacySettingKey): boolean {
  return key !== 'allow_find_by_phone';
}

/**
 * 这一项有没有例外名单区块。Android `needExceptions()`（:321-331）：同样只有
 * 「按手机号找到我」没有 —— 那一档语义上不可再细分，加例外只会写出服务端不认的规则。
 */
export function privacyNeedExceptions(key: PrivacySettingKey): boolean {
  return key !== 'allow_find_by_phone';
}

/**
 * 两条例外行的标题。Android `buildCells()`（:494-517）按项分文案：
 * 「最后上线」用 Always Share With / Never Share With，其余用 Always Allow / Never Allow。
 */
export function privacyAlwaysAllowLabel(key: PrivacySettingKey): string {
  return key === 'show_last_seen' ? 'Always Share With' : 'Always Allow';
}

export function privacyNeverAllowLabel(key: PrivacySettingKey): string {
  return key === 'show_last_seen' ? 'Never Share With' : 'Never Allow';
}

/**
 * 附加开关区块：Android 的详情页在档位/例外之下还有一组**按项**出现的开关行
 * （`needExtraToggle` :631-655 + `newExtraToggleItems` :669-736），它们不属于档位、
 * 也不属于例外名单，所以单独一块卡。
 *
 * - Premium 放行**只有「群组与频道邀请」这一项有**。PRIVACY-101 一度把它做成所有项档位卡里
 *   的勾，结果是本端能在「简介」「生日」上写出 Android 根本写不出的 premium 规则。
 * - 「隐藏已读时间」只有「最后上线」有。
 * - Android 在「公开头像」「生日」两项下还有编辑器入口行（头像选择器 / 生日编辑器），
 *   本端没有那两个容器，**不为不存在的容器造 UI**（同 CHAN-SEND 的口径），故不出行。
 */
export function privacyNeedsPremiumRow(key: PrivacySettingKey): boolean {
  return key === 'allow_chat_invites';
}

export function privacyNeedsReadDateRow(key: PrivacySettingKey): boolean {
  return key === 'show_last_seen';
}

/**
 * 改主档位时 premium 该是什么（Android `onClick` 的 btn_everybody/contacts/nobody 分支：
 * `plusPremium = constructor == AllowChatInvites && desiredMode == CONTACTS`）。
 * 两条含义都在里面：只有 invites 项会**自动**放行 Premium，且其余项改档会把已有的
 * premium 规则一并摘掉（它算主档位类规则）。
 */
export function privacyPremiumForMode(key: PrivacySettingKey, mode: PrivacyMode): boolean {
  return key === 'allow_chat_invites' && mode === 'contacts';
}
