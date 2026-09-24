/**
 * feature/settings — 设置分区直达的纯映射（SELF-101）。
 *
 * 「我的资料」页的入口行（通知 / 设备和存储）经 `settingsSection/{section}` 路由
 * 落到本页，但路由参数是外部字符串，必须先收敛成受限键再驱动渲染：
 * 未知值一律退回 `all`（完整设置页），避免用一个错拼的 section 打出半截页面。
 *
 * `devices` 不占用分区渲染：设置页内已有整屏的活跃会话子页（DevicesSubPage），
 * 直达它才是 TGX「设备」行的落点，故由 reducer 转成 showDevicesPage=true。
 * `privacy`（SELF-102）同理，落点是 PrivacySubPage；两者都只作为卡片行出现在
 * 完整设置页里，不单独成一个分区。
 */

export type SettingsSectionKey = 'all' | 'notifications' | 'data_and_storage';

/** 分区页内渲染的卡片块。 */
export type SettingsCardKey =
  | 'profile' | 'notifications' | 'devices' | 'privacy' | 'storage' | 'auto_download' | 'proxy'
  | 'appearance' | 'language' | 'about' | 'logout';

const ALL_CARDS: SettingsCardKey[] = [
  'profile', 'notifications', 'devices', 'privacy', 'storage', 'auto_download', 'proxy',
  'appearance', 'language', 'about', 'logout'
];

const NOTIFICATIONS_CARDS: SettingsCardKey[] = ['notifications'];
// TGX 把「自动下载」和「代理」都放在 Data and Storage 里（前者在存储用量下面，
// 后者在 Connection 组），故与存储同分区。
const DATA_STORAGE_CARDS: SettingsCardKey[] = ['storage', 'auto_download', 'proxy'];

/** 外部 section 字符串 → 受限键；未知值退回 'all'。 */
export function parseSettingsSection(raw: string): SettingsSectionKey {
  if (raw === 'notifications') {
    return 'notifications';
  }
  if (raw === 'data_and_storage') {
    return 'data_and_storage';
  }
  return 'all';
}

/** 分区页标题的 i18n key（'all' 用页面原标题）。 */
export function settingsSectionTitleKey(section: SettingsSectionKey): string {
  if (section === 'notifications') {
    return 'NOTIFICATIONS';
  }
  if (section === 'data_and_storage') {
    return 'DATA AND STORAGE';
  }
  return 'Settings';
}

/** 分区页可见的卡片块集合。 */
export function settingsCardsForSection(section: SettingsSectionKey): SettingsCardKey[] {
  if (section === 'notifications') {
    return NOTIFICATIONS_CARDS;
  }
  if (section === 'data_and_storage') {
    return DATA_STORAGE_CARDS;
  }
  return ALL_CARDS;
}

export function sectionShowsCard(section: SettingsSectionKey, card: SettingsCardKey): boolean {
  return settingsCardsForSection(section).indexOf(card) >= 0;
}
