/**
 * feature/chat_list — 导出入口（CHATLIST-002 + MSG-108）。
 */

export {
  ChatListItem,
  AVATAR_PALETTE,
  avatarColorForChatId,
  avatarLetterForTitle
} from './model/ChatListItem';

export { generateMockChats } from './model/MockChatData';

export {
  ChatListKind,
  ChatListUiStateOptions,
  ChatListUiState,
  ChatActionMenuState
} from './contract/ChatListUiState';

export {
  LoadChats,
  RefreshChats,
  ChatSelected,
  OnChatsLoaded,
  OnChatsLoadFailed,
  OpenArchivedChats,
  CloseArchivedChats,
  ChatActionRequested,
  ToggleChatPinned,
  ToggleChatMarkedUnread,
  ToggleChatArchived,
  DismissChatActionMenu,
  OnChatActionFailed,
  ChatListIntent
} from './contract/ChatListIntent';

export {
  FetchChatList,
  NavigateToChat,
  ShowToast,
  SetChatPinned,
  SetChatReadState,
  SetChatArchived,
  ChatListEffect
} from './contract/ChatListEffect';

export { CHAT_LIST_PAGE_SIZE, chatListReducer, canMarkChatAsRead } from './reducer/ChatListReducer';

export { DrawerState, DrawerItemKey, DRAWER_ITEM_KEYS } from './contract/DrawerState';

export { ChatListUiStateListener, ChatListCoordinator } from './coordinator/ChatListCoordinator';

export { ChatListDataSource, ChatListPage } from './pages/ChatListPage';

export { DrawerMenu } from './pages/DrawerMenu';
