/**
 * feature/chat — 导出入口（CHAT-001 + CHAT-003 + CHAT-004 + MSG-101 + MSG-102）。
 */

export { MessageItem, MessageSendState } from './model/MessageItem';
export { MediaAttachment, MediaKind } from './model/MediaAttachment';
export { MediaViewerItem } from './model/MediaViewerItem';

export { MessageTextSpan } from './model/MessageTextSpan';

export { parseFormattedText } from './model/FormattedTextParser';

export {
  ChatKind,
  SenderInfo,
  SenderInfoDeps,
  EMPTY_SENDER_INFO,
  NAME_PALETTE,
  chatKindOf,
  resolveSenderInfo,
  nameColorForIndex,
  avatarLettersForName
} from './model/SenderInfo';

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
  OnVisibleRangeChanged,
  TapFailedMessage,
  OpenMediaViewer,
  CloseMediaViewer,
  ChangeViewerIndex,
  RequestMediaDownload,
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
  ReportMessagesRead,
  ResendMessage,
  ChatEffect
} from './contract/ChatEffect';

export {
  isOutgoingMessageRead,
  incomingIdUpTo,
  ReadReportThrottle
} from './model/ReadReceipt';

export { chatReducer, messageSnippet } from './reducer/ChatReducer';

export {
  ChatUiStateListener,
  ChatCoordinator,
  messageContentText,
  messageSendStateOf,
  repliedMessageIdOf
} from './coordinator/ChatCoordinator';

export { MessageListDataSource, ChatPage } from './pages/ChatPage';
