/**
 * feature/chat — 导出入口（CHAT-001 + CHAT-003 + CHAT-004）。
 */

export { MessageItem, MessageSendState } from './model/MessageItem';

export {
  ChatUiStateOptions,
  ChatUiState,
  ComposerMode,
  ComposerReplyMode,
  ComposerEditMode,
  MessageActionMenuState
} from './contract/ChatUiState';

export {
  LoadInitialMessages,
  LoadOlderMessages,
  OnMessagesLoaded,
  OnMessagesLoadFailed,
  ComposerTextChanged,
  SendCurrentMessage,
  OnMessageSendFailed,
  BackToChatList,
  MessageActionRequested,
  OnMessageActionMenuLoaded,
  ReplyToMessage,
  EditMessage,
  DeleteMessage,
  CancelComposerMode,
  DismissMessageActionMenu,
  OnMessageActionFailed,
  ChatIntent
} from './contract/ChatIntent';

export {
  FetchInitialMessages,
  FetchOlderMessages,
  SendTextMessage,
  FetchMessagePermissions,
  EditMessageText,
  DeleteMessages,
  NavigateBack,
  ChatEffect
} from './contract/ChatEffect';

export { chatReducer, messageSnippet } from './reducer/ChatReducer';

export {
  ChatUiStateListener,
  ChatCoordinator,
  messageContentText,
  messageSendStateOf,
  repliedMessageIdOf
} from './coordinator/ChatCoordinator';

export { MessageListDataSource, ChatPage } from './pages/ChatPage';
