/**
 * feature/chat — 导出入口（CHAT-001 + CHAT-003 + CHAT-004 + MSG-101 + MSG-102 + MSG-106）。
 */

export { MessageItem, MessageSendState } from './model/MessageItem';
export { ReactionChip } from './model/ReactionChip';
export { MediaAttachment, MediaKind, formatFileSize, decodeWaveform, encodeWaveform, normalizeWaveform } from './model/MediaAttachment';
export { MediaViewerItem } from './model/MediaViewerItem';
export { LinkPreviewInfo } from './model/LinkPreviewInfo';
export { ChatSearchResultItem } from './model/ChatSearchResultItem';
export { PinnedMessageInfo } from './model/PinnedMessageInfo';

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
  DEFAULT_RECENT_EMOJIS,
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
  PickAndSendVideo,
  CancelMediaUpload,
  RestoreDraft,
  OpenAttachmentMenu,
  CloseAttachmentMenu,
  ToggleAttachmentMenu,
  OpenEmojiBoard,
  CloseEmojiBoard,
  ToggleEmojiBoard,
  InsertEmoji,
  DeleteLastEmojiChar,
  ClearRecentEmojis,
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
  OnPinnedMessageLoaded,
  DismissPinnedBar,
  JumpToPinnedMessage,
  PinMessage,
  UnpinMessage,
  JoinChannel,
  OnChannelMemberStatusChanged,
  OpenMessageComments,
  ToggleMessageReaction,
  OpenStickerSet,
  OnStickerSetLoaded,
  OnStickerSetLoadFailed,
  CloseStickerSetPreview,
  InstallStickerSet,
  UninstallStickerSet,
  OnStickerSetChanged,
  OnStickerSetActionFailed,
  SendStickerFromPreview,
  SendSticker,
  ClearRecentStickers,
  SendGif,
  ClearRecentGifs,
  SearchGifs,
  OnStickerPreviewFileUpdated,
  StartVoiceRecord,
  StopAndSendVoiceRecord,
  CancelVoiceRecord,
  VoiceRecordTick,
  PlayVoiceNote,
  PauseVoiceNote,
  VoicePlaybackProgress,
  VoicePlaybackCompleted,
  VoicePlaybackFailed,
  ChatIntent
} from './contract/ChatIntent';

export {
  StickerSetPreviewState,
  StickerSetItem,
  StickerPack,
  DEFAULT_STICKER_PACKS,
  DEFAULT_RECENT_STICKERS
} from './model/StickerSetPreviewState';

export {
  GifItem,
  GIF_CATEGORIES,
  DEFAULT_RECENT_GIFS,
  DEFAULT_GIF_PACKS
} from './model/GifItem';

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
  PickAndSendVideoEffect,
  CancelMediaDownloadEffect,
  FetchChatSearch,
  JumpToMessage,
  PinMessageEffect,
  UnpinMessageEffect,
  JoinChannelEffect,
  ToggleReactionEffect,
  OpenCommentsEffect,
  FetchStickerSet,
  ChangeStickerSetEffect,
  SendStickerMessage,
  SendAnimationMessage,
  StartVoiceRecordEffect,
  StopAndSendVoiceRecordEffect,
  CancelVoiceRecordEffect,
  PlayVoiceNoteEffect,
  PauseVoiceNoteEffect,
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
export { StickerSetPreviewSheet } from './pages/StickerSetPreviewSheet';
export { CommentsPage } from './pages/CommentsPage';
export {
  CommentsCoordinator,
  CommentsUiState,
  CommentItem,
  CommentsUiStateListener
} from './coordinator/CommentsCoordinator';
