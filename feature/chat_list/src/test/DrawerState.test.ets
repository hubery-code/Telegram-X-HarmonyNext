/**
 * feature/chat_list — 抽屉状态纯数据类单测（DRAWER-101）。
 *
 * 覆盖：
 * 1. DrawerState.empty()：空账号 + 夜间模式关；
 * 2. 构造器全字段存取；
 * 3. DRAWER_ITEM_KEYS：六项 key 与 TGX DrawerController 菜单顺序一致。
 */

import { describe, it, expect } from '@ohos/hypium';
import { DrawerState, DrawerItemKey, DRAWER_ITEM_KEYS } from '../main/ets/contract/DrawerState';

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
  });
}
