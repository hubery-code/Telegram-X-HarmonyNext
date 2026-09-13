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
  ChatActionRequested,
  ToggleChatPinned,
  ToggleChatMarkedUnread,
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
  ChatListEffect
} from './contract/ChatListEffect';

export { CHAT_LIST_PAGE_SIZE, chatListReducer, canMarkChatAsRead } from './reducer/ChatListReducer';

export { ChatListUiStateListener, ChatListCoordinator } from './coordinator/ChatListCoordinator';

export { ChatListDataSource, ChatListPage } from './pages/ChatListPage';
