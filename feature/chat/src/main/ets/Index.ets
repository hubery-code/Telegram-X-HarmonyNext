/**
 * feature/chat — 导出入口（CHAT-001）。
 */

export { MessageItem } from './model/MessageItem';

export { ChatUiStateOptions, ChatUiState } from './contract/ChatUiState';

export {
  LoadInitialMessages,
  LoadOlderMessages,
  OnMessagesLoaded,
  OnMessagesLoadFailed,
  BackToChatList,
  ChatIntent
} from './contract/ChatIntent';

export {
  FetchInitialMessages,
  FetchOlderMessages,
  NavigateBack,
  ChatEffect
} from './contract/ChatEffect';

export { chatReducer } from './reducer/ChatReducer';

export {
  ChatUiStateListener,
  ChatCoordinator,
  messageContentText
} from './coordinator/ChatCoordinator';

export { MessageListDataSource, ChatPage } from './pages/ChatPage';
