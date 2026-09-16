/**
 * feature/chat_list — 会话列表抽屉状态（DRAWER-101）。
 *
 * 纯数据类：描述 TGX 抽屉导航（≡）的账号头与菜单静态内容。
 * 账号数据（头像/姓名/手机）与夜间模式真实切换逻辑由装配层注入，
 * 本模块只负责按状态渲染（结构与 Android DrawerController 对齐：
 * 头部账号区 + 菜单 + 底部夜间模式开关）。
 */

/** 抽屉菜单项 key（顺序即 TGX DrawerController 菜单顺序）。 */
export type DrawerItemKey = 'contacts' | 'calls' | 'saved' | 'settings' | 'invite' | 'help';

/** 抽屉菜单项全量列表，供 UI 遍历渲染。 */
export const DRAWER_ITEM_KEYS: DrawerItemKey[] = [
  'contacts',
  'calls',
  'saved',
  'settings',
  'invite',
  'help'
];

export class DrawerState {
  readonly accountName: string;
  readonly accountPhone: string;
  readonly accountAvatarPath: string | null;
  readonly accountAvatarLetters: string;
  readonly nightMode: boolean;

  constructor(
    accountName: string = '',
    accountPhone: string = '',
    accountAvatarPath: string | null = null,
    accountAvatarLetters: string = '',
    nightMode: boolean = false
  ) {
    this.accountName = accountName;
    this.accountPhone = accountPhone;
    this.accountAvatarPath = accountAvatarPath;
    this.accountAvatarLetters = accountAvatarLetters;
    this.nightMode = nightMode;
  }

  static empty(): DrawerState {
    return new DrawerState();
  }
}
