/**
 * feature/chat — 导出入口（CHAT-001 + CHAT-003 + CHAT-004 + MSG-101 + MSG-102 + MSG-106）。
 */

export { MessageItem, MessageSendState } from './model/MessageItem';
export { MediaAttachment, MediaKind, formatFileSize } from './model/MediaAttachment';
export { MediaViewerItem } from './model/MediaViewerItem';
export { LinkPreviewInfo } from './model/LinkPreviewInfo';
export { ChatSearchResultItem } from './model/ChatSearchResultItem';

export { MessageTextSpan } from './model/MessageTextSpan';

export { parseFormattedText } from './model/FormattedTextParser';

export { ForwardTarget, matchesForwardQuery } from './model/ForwardTarget';

export {
  isMessageSelected,
  toggleMessageSelection,
  clearSelection,
  retainExistingSelection
} from './model/ForwardSelection';

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
  CopyMessageText,
  CopyMessageLink,
  EditMessage,
  DeleteMessage,
  CancelComposerMode,
  DismissMessageActionMenu,
  OnMessageActionFailed,
  ForwardMessagesRequested,
  ToggleMessageSelection,
  ExitMessageSelection,
  ConfirmForwardSelection,
  ForwardSelectedToChat,
  OnForwardCompleted,
  OnForwardFailed,
  OnVisibleRangeChanged,
  TapFailedMessage,
  OpenMediaViewer,
  CloseMediaViewer,
  ChangeViewerIndex,
  RequestMediaDownload,
  PickAndSendPhoto,
  PickAndSendFile,
  CancelMediaUpload,
  RestoreDraft,
  OpenAttachmentMenu,
  CloseAttachmentMenu,
  ToggleAttachmentMenu,
  CancelMediaDownload,
  ResendFailedMessage,
  OpenChatSearch,
  CloseChatSearch,
  ChatSearchQueryChanged,
  PerformChatSearch,
  OnChatSearchLoaded,
  OnChatSearchFailed,
  JumpToSearchResult,
  OnJumpToMessageReady,
  ClearJumpToMessage,
  OpenUserProfile,
  OnHeaderSubtitleChanged,
  OnChatKindChanged,
  OpenChatProfile,
  ChatMenuAction,
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
  OpenForwardPicker,
  ForwardMessages,
  ReportMessagesRead,
  ResendMessage,
  CopyTextToClipboard,
  PickAndSendPhotoEffect,
  PickAndSendFileEffect,
  CancelMediaDownloadEffect,
  FetchChatSearch,
  JumpToMessage,
  ChatEffect
} from './contract/ChatEffect';

export {
  isOutgoingMessageRead,
  incomingIdUpTo,
  ReadReportThrottle
} from './model/ReadReceipt';

export { chatReducer, messageSnippet, extractFirstLink } from './reducer/ChatReducer';

export {
  ChatUiStateListener,
  ChatCoordinator,
  ChatCoordinatorOptions,
  messageContentText,
  messageSendStateOf,
  repliedMessageIdOf,
  isSameDay,
  formatDateHeader
} from './coordinator/ChatCoordinator';

export { MessageListDataSource, ChatPage } from './pages/ChatPage';
export { ForwardPickerPage } from './pages/ForwardPickerPage';
