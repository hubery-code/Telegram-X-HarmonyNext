/**
 * feature/chat_list — 覆盖层的物理返回键收口（CHATLIST-BACK-101）。
 *
 * 会话列表页的覆盖层包括：
 * 1. actionMenu !== null：长按会话行弹出的单会话操作菜单（底部动作面板 + 遮罩）
 * 2. listKind === 'archive'：进入了归档会话列表视图
 *
 * 抽屉 DrawerMenu 由 ChatListPage 的 showDrawer 驱动，在视觉上位于最顶层。
 * 外部装配层（entry）在拦截 onBackPress 时，优先关闭抽屉，随后再执行本函数的覆盖层意图。
 */

import {
  ChatListIntent,
  DismissChatActionMenu,
  CloseArchivedChats
} from '../contract/ChatListIntent';
import { ChatListUiState } from '../contract/ChatListUiState';

/**
 * 返回这一次物理返回键应当派发的关闭意图；`null` 表示当前没有任何覆盖层，
 * 调用方（entry）才放行路由 pop 或交由系统默认处理。
 */
export function chatListOverlayCloseIntent(state: ChatListUiState): ChatListIntent | null {
  if (state.actionMenu !== null) {
    return new DismissChatActionMenu();
  }
  if (state.listKind === 'archive') {
    return new CloseArchivedChats();
  }
  return null;
}
