/**
 * feature/chat — 导出入口（CHAT-001 + CHAT-003）。
 */

export { MessageItem, MessageSendState } from './model/MessageItem';

export { ChatUiStateOptions, ChatUiState } from './contract/ChatUiState';

export {
  LoadInitialMessages,
  LoadOlderMessages,
  OnMessagesLoaded,
  OnMessagesLoadFailed,
  ComposerTextChanged,
  SendCurrentMessage,
  OnMessageSendFailed,
  BackToChatList,
  ChatIntent
} from './contract/ChatIntent';

export {
  FetchInitialMessages,
  FetchOlderMessages,
  SendTextMessage,
  NavigateBack,
  ChatEffect
} from './contract/ChatEffect';

export { chatReducer } from './reducer/ChatReducer';

export {
  ChatUiStateListener,
  ChatCoordinator,
  messageContentText,
  messageSendStateOf
} from './coordinator/ChatCoordinator';

export { MessageListDataSource, ChatPage } from './pages/ChatPage';
