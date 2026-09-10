/**
 * feature/chat_list — 导出入口（CHATLIST-002）。
 */

export {
  ChatListItem,
  AVATAR_PALETTE,
  avatarColorForChatId,
  avatarLetterForTitle
} from './model/ChatListItem';

export { generateMockChats } from './model/MockChatData';

export { ChatListUiStateOptions, ChatListUiState } from './contract/ChatListUiState';

export {
  LoadChats,
  RefreshChats,
  ChatSelected,
  OnChatsLoaded,
  OnChatsLoadFailed,
  ChatListIntent
} from './contract/ChatListIntent';

export {
  FetchChatList,
  NavigateToChat,
  ShowToast,
  ChatListEffect
} from './contract/ChatListEffect';

export { CHAT_LIST_PAGE_SIZE, chatListReducer } from './reducer/ChatListReducer';

export { ChatListUiStateListener, ChatListCoordinator } from './coordinator/ChatListCoordinator';

export { ChatListDataSource, ChatListPage } from './pages/ChatListPage';
