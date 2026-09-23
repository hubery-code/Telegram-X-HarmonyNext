/**
 * feature/chat_list — 会话列表抽屉状态（DRAWER-101）。
 *
 * 纯数据类：描述 TGX 抽屉导航（≡）的账号头与菜单静态内容。
 * 账号头数据由 ChatListCoordinator 经 getMe + FileRegistry 取回后由 reducer
 * 写入 ChatListUiState.drawer（结构与 Android DrawerController 对齐：
 * 头部账号区 + 菜单 + 底部夜间模式开关）；夜间模式偏好仍由装配层的
 * ThemeManager 持有，这里只带一份渲染用的快照。
 */

import { UiState } from '@tgx/feature-template';

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

/** 抽屉可跳转目标（纯导航意图，路由由装配层实现）。 */
export type DrawerNavTarget = 'contacts' | 'settings' | 'selfProfile';

/**
 * 账号头是否已拉到数据。
 * accountUserId 为 0 表示 getMe 还没回来（Saved Messages 需要先解析 my_id）。
 */
export function isDrawerAccountLoaded(state: DrawerState): boolean {
  return state.accountUserId > 0;
}

export interface DrawerStateOptions {
  readonly accountName?: string;
  readonly accountPhone?: string;
  readonly accountAvatarPath?: string | null;
  readonly accountAvatarLetters?: string;
  readonly nightMode?: boolean;
  readonly accountUserId?: number;
}

export class DrawerState implements UiState {
  readonly accountName: string;
  readonly accountPhone: string;
  readonly accountAvatarPath: string | null;
  readonly accountAvatarLetters: string;
  readonly nightMode: boolean;
  /** 当前账号的 user id（getMe.id）；0 = 尚未加载。 */
  readonly accountUserId: number;

  constructor(
    accountName: string = '',
    accountPhone: string = '',
    accountAvatarPath: string | null = null,
    accountAvatarLetters: string = '',
    nightMode: boolean = false,
    accountUserId: number = 0
  ) {
    this.accountName = accountName;
    this.accountPhone = accountPhone;
    this.accountAvatarPath = accountAvatarPath;
    this.accountAvatarLetters = accountAvatarLetters;
    this.nightMode = nightMode;
    this.accountUserId = accountUserId;
  }

  static empty(): DrawerState {
    return new DrawerState();
  }

  copyWith(options: DrawerStateOptions): DrawerState {
    return new DrawerState(
      options.accountName !== undefined ? options.accountName : this.accountName,
      options.accountPhone !== undefined ? options.accountPhone : this.accountPhone,
      options.accountAvatarPath !== undefined ? options.accountAvatarPath : this.accountAvatarPath,
      options.accountAvatarLetters !== undefined ? options.accountAvatarLetters : this.accountAvatarLetters,
      options.nightMode !== undefined ? options.nightMode : this.nightMode,
      options.accountUserId !== undefined ? options.accountUserId : this.accountUserId
    );
  }
}
