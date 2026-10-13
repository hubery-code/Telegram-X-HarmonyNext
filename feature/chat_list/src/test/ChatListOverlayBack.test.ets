/**
 * feature/chat_list — 覆盖层物理返回键收口的单测（CHATLIST-BACK-101）。
 *
 * 断言视觉层叠顺序的关闭优先级：
 * 1. 会话操作菜单（actionMenu）高于归档列表视图；
 * 2. 归档列表视图（listKind === 'archive'）高于主会话列表；
 * 3. 当覆盖层均未激活时，交回 null 让外部装配层（entry）放行路由 pop 或退出应用。
 */

import { describe, it, expect } from '@ohos/hypium';
import { ChatListUiState, ChatActionMenuState } from '../main/ets/contract/ChatListUiState';
import { chatListOverlayCloseIntent } from '../main/ets/model/ChatListOverlayBack';

export default function chatListOverlayBackTest(): void {
  describe('ChatListOverlayBack', () => {
    it('idle_returnsNullSoRouterPops', 0, () => {
      expect(chatListOverlayCloseIntent(ChatListUiState.initial())).assertNull();
    });

    it('actionMenu_dismissesChatActionMenu', 0, () => {
      const state: ChatListUiState = ChatListUiState.initial().copyWith({
        actionMenu: new ChatActionMenuState(1001, 'Test Chat', false, true, false)
      });
      expect(chatListOverlayCloseIntent(state)?.kind).assertEqual('dismissChatActionMenu');
    });

    it('archiveList_closesArchivedChats', 0, () => {
      const state: ChatListUiState = ChatListUiState.initial().copyWith({
        listKind: 'archive'
      });
      expect(chatListOverlayCloseIntent(state)?.kind).assertEqual('closeArchivedChats');
    });

    it('hierarchy_actionMenuTakesPrecedenceOverArchive', 0, () => {
      // 在归档列表中长按某条会话弹出操作菜单：优先关闭长按菜单，其次才关闭归档列表
      const state: ChatListUiState = ChatListUiState.initial().copyWith({
        listKind: 'archive',
        actionMenu: new ChatActionMenuState(1002, 'Archived Chat', true, false, true)
      });
      expect(chatListOverlayCloseIntent(state)?.kind).assertEqual('dismissChatActionMenu');
    });
  });
}
