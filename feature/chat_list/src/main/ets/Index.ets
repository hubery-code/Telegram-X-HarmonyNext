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
  ChatActionMenuState,
  ChatFolderTab,
  DEFAULT_CHAT_FOLDERS,
  filterChatsByFolder
} from './contract/ChatListUiState';

export {
  LoadChats,
  RefreshChats,
  ChatSelected,
  OnChatsLoaded,
  OnChatsLoadFailed,
  OpenArchivedChats,
  CloseArchivedChats,
  SelectChatFolder,
  ChatActionRequested,
  ToggleChatPinned,
  ToggleChatMarkedUnread,
  ToggleChatArchived,
  DismissChatActionMenu,
  OnChatActionFailed,
  DrawerAccountRequested,
  DrawerItemClicked,
  DrawerAccountClicked,
  OnDrawerAccountLoaded,
  OnDrawerAvatarLoaded,
  DrawerNightModeSet,
  ChatListIntent
} from './contract/ChatListIntent';

export {
  FetchChatList,
  NavigateToChat,
  ShowToast,
  SetChatPinned,
  SetChatReadState,
  SetChatArchived,
  FetchDrawerAccount,
  DrawerNavigate,
  OpenSavedMessages,
  ChatListEffect
} from './contract/ChatListEffect';

export { CHAT_LIST_PAGE_SIZE, chatListReducer, canMarkChatAsRead } from './reducer/ChatListReducer';

export {
  DrawerState,
  DrawerStateOptions,
  DrawerItemKey,
  DrawerNavTarget,
  DRAWER_ITEM_KEYS,
  isDrawerAccountLoaded
} from './contract/DrawerState';

export { ChatListUiStateListener, ChatListCoordinator } from './coordinator/ChatListCoordinator';

export { ChatListDataSource, ChatListPage } from './pages/ChatListPage';

export { DrawerMenu } from './pages/DrawerMenu';
