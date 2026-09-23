/**
 * feature/chat_list — 抽屉状态纯数据类单测（DRAWER-101）。
 *
 * 覆盖：
 * 1. DrawerState.empty()：空账号 + 夜间模式关 + 未回灌的 accountUserId；
 * 2. 构造器全字段存取；
 * 3. DRAWER_ITEM_KEYS：六项 key 与 TGX DrawerController 菜单顺序一致；
 * 4. copyWith：只改指定字段、显式 null 生效、原对象不被改动。
 */

import { describe, it, expect } from '@ohos/hypium';
import {
  DrawerState,
  DrawerItemKey,
  DRAWER_ITEM_KEYS,
  isDrawerAccountLoaded
} from '../main/ets/contract/DrawerState';

export default function drawerStateTest(): void {
  describe('DrawerState', () => {
    it('empty_returnsBlankAccountAndNightModeOff', 0, () => {
      const state: DrawerState = DrawerState.empty();
      expect(state.accountName).assertEqual('');
      expect(state.accountPhone).assertEqual('');
      expect(state.accountAvatarPath).assertEqual(null);
      expect(state.accountAvatarLetters).assertEqual('');
      expect(state.nightMode).assertFalse();
    });

    it('constructor_storesAllFields', 0, () => {
      const state: DrawerState = new DrawerState('Alice', '+1 234 567', '/data/a.png', 'AL', true);
      expect(state.accountName).assertEqual('Alice');
      expect(state.accountPhone).assertEqual('+1 234 567');
      expect(state.accountAvatarPath).assertEqual('/data/a.png');
      expect(state.accountAvatarLetters).assertEqual('AL');
      expect(state.nightMode).assertTrue();
    });

    it('drawerItemKeys_listsSixEntriesInTgxOrder', 0, () => {
      expect(DRAWER_ITEM_KEYS.length).assertEqual(6);
      expect(DRAWER_ITEM_KEYS[0]).assertEqual('contacts');
      expect(DRAWER_ITEM_KEYS[1]).assertEqual('calls');
      expect(DRAWER_ITEM_KEYS[2]).assertEqual('saved');
      expect(DRAWER_ITEM_KEYS[3]).assertEqual('settings');
      expect(DRAWER_ITEM_KEYS[4]).assertEqual('invite');
      expect(DRAWER_ITEM_KEYS[5]).assertEqual('help');
      const first: DrawerItemKey = DRAWER_ITEM_KEYS[0];
      expect(first).assertEqual('contacts');
    });

    it('empty_hasNoUserId_soAccountIsTreatedAsUnloaded', 0, () => {
      // accountUserId 是"账号头是否已回灌"的判据，也是 Saved Messages 解析的前提。
      expect(DrawerState.empty().accountUserId).assertEqual(0);
      expect(isDrawerAccountLoaded(DrawerState.empty())).assertFalse();
      expect(isDrawerAccountLoaded(new DrawerState('A', '', null, 'A', false, 42))).assertTrue();
    });

    it('copyWith_overridesOnlyGivenFields', 0, () => {
      const base: DrawerState = new DrawerState('Alice', '+1 234 567', null, 'AL', false, 42);

      const avatarOnly: DrawerState = base.copyWith({ accountAvatarPath: '/data/a.png' });
      expect(avatarOnly.accountAvatarPath).assertEqual('/data/a.png');
      expect(avatarOnly.accountName).assertEqual('Alice');
      expect(avatarOnly.accountUserId).assertEqual(42);
      expect(avatarOnly.nightMode).assertFalse();

      const nightOnly: DrawerState = base.copyWith({ nightMode: true });
      expect(nightOnly.nightMode).assertTrue();
      expect(nightOnly.accountAvatarPath).assertEqual(null);

      // 显式传 null 才是清空头像；未传（undefined）保持原值。
      const cleared: DrawerState = avatarOnly.copyWith({ accountAvatarPath: null });
      expect(cleared.accountAvatarPath).assertEqual(null);
      expect(cleared.accountName).assertEqual('Alice');

      // 原对象不被改动（不可变约定）。
      expect(base.accountAvatarPath).assertEqual(null);
    });
  });
}
