/**
 * feature/chat — 会话页纯 Reducer（CHAT-001 + CHAT-003 + CHAT-004）。
 *
 * 遵循计划 §5.11 / UI-003：
 * - 纯函数：(state, intent, env) -> ReducerResult<ChatUiState, ChatEffect>
 * - 禁止直接修改 state；无变化返回原引用 reduced(state)
 * - 禁止在 reducer 内做 I/O 或异步，加载请求只产出 Fetch* 描述
 *
 * CHAT-004 新增消息动作流：
 * - messageActionRequested → 只产出 FetchMessagePermissions（权限位由 TDLib
 *   getMessageProperties 离线计算）；
 * - onMessageActionMenuLoaded → 权限过滤（回复恒可；编辑仅己方文本消息且
 *   canBeEdited；删除需 canBeDeletedOnlyForSelf || canBeDeletedForAllUsers）
 *   生成 MessageActionMenuState；
 * - replyToMessage / editMessage 进入输入栏回复/编辑模式；编辑模式进入时把
 *   当前草稿存进 draftBackup，cancelComposerMode / backToChatList（返回键优先
 *   退出模式）取消时恢复；
 * - sendCurrentMessage 按模式分流：edit → EditMessageText（发出后恢复草稿），
 *   reply → SendTextMessage 带 replyToMessageId；
 * - deleteMessage → DeleteMessages(chatId, [id], revoke=canBeDeletedForAllUsers)；
 * - onMessageActionFailed → errorMessage 细条提示。
 *
 * MSG-106 新增转发多选流：
 * - forwardMessagesRequested → 进入选择态并预选中 actionMenu 的消息（需
 *   showForward，即 can_be_forwarded）；
 * - toggleMessageSelection → 增删选中；取消掉最后一条即自动退出选择态
 *   （Telegram X 行为）；
 * - forwardSelectedToChat → OpenForwardPicker 之前先产出选择器请求，选定后
 *   由 ForwardMessages effect 执行；成功 OnForwardCompleted 退出选择态，
 *   失败 OnForwardFailed 只提示、保留选择便于换目标重试；
 * - onMessagesLoaded 收敛选择集合（选中期间消息被删/撤回时剔除）；
 * - backToChatList 优先退出选择态（在操作菜单之后、输入栏模式之前）。
 *
 * MSG-109 头部信息区：
 * - onHeaderSubtitleChanged / onChatKindChanged：coordinator 计算结果回灌，
 *   值相同返回原引用；
 * - openChatProfile / chatMenuAction：纯导航/占位意图不改状态、无 effect
 *   （switch 无匹配分支，落到末尾 reduced(state) 透传）。
 */

import { Reducer, ReducerEnv, ReducerResult, reduced } from '@tgx/feature-template';
import {
  ChatUiState,
  ComposerEditMode,
  ComposerMode,
  ComposerReplyMode,
  MessageActionMenuState
} from '../contract/ChatUiState';
import { MessageItem } from '../model/MessageItem';
import { ReactionChip } from '../model/ReactionChip';
import { MediaViewerItem } from '../model/MediaViewerItem';
import { MediaAttachment } from '../model/MediaAttachment';
import {
  ChatIntent,
  OnMessagesLoaded,
  OnMessagesLoadFailed,
  ComposerTextChanged,
  OnMessageSendFailed,
  MessageActionRequested,
  OnMessageActionMenuLoaded,
  OnMessageActionFailed,
  CopyMessageText,
  CopyMessageLink,
  ForwardMessagesRequested,
  ToggleMessageSelection,
  ForwardSelectedToChat,
  OnForwardCompleted,
  OnForwardFailed,
  OnVisibleRangeChanged,
  TapFailedMessage,
  OpenMediaViewer,
  CloseMediaViewer,
  ChangeViewerIndex,
  CancelMediaUpload,
  RestoreDraft,
  CancelMediaDownload,
  ResendFailedMessage,
  ChatSearchQueryChanged,
  OnChatSearchLoaded,
  OnChatSearchFailed,
  JumpToSearchResult,
  OnJumpToMessageReady,
  OnHeaderSubtitleChanged,
  OnChatKindChanged,
  OnPinnedMessageLoaded,
  DismissPinnedBar,
  JumpToPinnedMessage,
  PinMessage,
  UnpinMessage,
  JoinChannel,
  OnChannelMemberStatusChanged,
  OpenMessageComments,
  ToggleMessageReaction,
  InsertEmoji,
  DeleteLastEmojiChar,
  ClearRecentEmojis,
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
  ChatMenuAction,
  OpenPollComposer,
  ClosePollComposer,
  PollQuestionChanged,
  PollOptionTextChanged,
  AddPollComposerOption,
  RemovePollComposerOption,
  TogglePollComposerAnonymous,
  TogglePollComposerMultiple,
  SubmitPollComposer,
  VotePollOption
} from '../contract/ChatIntent';
import {
  ChatEffect,
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
  PickAndSendVideoEffect,
  PickAndSendFileEffect,
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
  SendPollEffect,
  SetPollAnswerEffect
} from '../contract/ChatEffect';
import { StickerSetPreviewState, StickerSetItem } from '../model/StickerSetPreviewState';
import { GifItem } from '../model/GifItem';
import {
  PollComposerState,
  PollOptionView,
  PollView,
  POLL_MAX_OPTIONS,
  POLL_MIN_OPTIONS,
  POLL_QUESTION_MAX_LENGTH,
  POLL_OPTION_MAX_LENGTH
} from '../model/PollView';
import { incomingIdUpTo } from '../model/ReadReceipt';
import {
  clearSelection,
  isMessageSelected,
  retainExistingSelection,
  toggleMessageSelection
} from '../model/ForwardSelection';

/** 收集列表中所有可在大图画廊中展示的多媒体项。 */
export function buildViewerItems(messages: readonly MessageItem[]): MediaViewerItem[] {
  const list: MediaViewerItem[] = [];
  for (let i = 0; i < messages.length; i++) {
    const item: MessageItem = messages[i];
    const sender: string = item.isOutgoing ? 'You' : (item.senderName.length > 0 ? item.senderName : '');
    if (item.albumItems.length > 0) {
      for (let j = 0; j < item.albumItems.length; j++) {
        const media: MediaAttachment = item.albumItems[j];
        if (media.kind === 'photo' || media.kind === 'animation' || media.kind === 'video') {
          list.push(new MediaViewerItem(item.messageId, sender, item.timestampMs, media));
        }
      }
    } else if (item.media !== null && (item.media.kind === 'photo' || item.media.kind === 'animation' || item.media.kind === 'video')) {
      list.push(new MediaViewerItem(item.messageId, sender, item.timestampMs, item.media));
    }
  }
  return list;
}

/** 提取消息中第一个可复制的链接 URL（MSG-105）。 */
export function extractFirstLink(item: MessageItem): string | null {
  if (item.spans.length > 0) {
    for (let i = 0; i < item.spans.length; i++) {
      const span = item.spans[i];
      if (span.linkUrl !== null && span.linkUrl.length > 0) {
        return span.linkUrl;
      }
    }
  }
  // 兜底扫描文本中的 http:// 或 https:// 或 www.
  const text: string = item.text;
  const match: RegExpMatchArray | null = text.match(/https?:\/\/[^\s]+|www\.[^\s]+/);
  if (match !== null && match[0] !== undefined) {
    return match[0];
  }
  return null;
}

/** 菜单/预览条用的正文摘要：压成单行并截断。 */
export function messageSnippet(text: string, maxLength: number = 80): string {
  const oneLine: string = text.replace(/\n/g, ' ');
  if (oneLine.length <= maxLength) {
    return oneLine;
  }
  return `${oneLine.substring(0, maxLength)}…`;
}

function findMessage(state: ChatUiState, messageId: number): MessageItem | null {
  for (let i = 0; i < state.messages.length; i++) {
    if (state.messages[i].messageId === messageId) {
      return state.messages[i];
    }
  }
  return null;
}

/** 取消输入栏模式（若有）：编辑模式恢复草稿，回复模式不动草稿。无模式时返回原引用。 */
function cancelMode(state: ChatUiState): ChatUiState {
  const mode: ComposerMode | null = state.composerMode;
  if (mode === null) {
    return state;
  }
  if (mode.kind === 'edit') {
    const editMode: ComposerEditMode = mode as ComposerEditMode;
    return state.copyWith({
      composerMode: null,
      composerText: editMode.draftBackup
    });
  }
  return state.copyWith({ composerMode: null });
}

/** 回复预览条标题：己方消息 "You"，否则 senderName，缺省退化为会话名。 */
function replyAuthorLabel(state: ChatUiState, item: MessageItem): string {
  if (item.isOutgoing) {
    return 'You';
  }
  if (item.senderName.length > 0) {
    return item.senderName;
  }
  return state.chatTitle;
}

/**
 * EMOJI-101: 安全移除末尾 Unicode 字符/Emoji（兼容代理对与变音符/选择符）。
 */
export function removeLastEmojiChar(text: string): string {
  if (text.length === 0) {
    return '';
  }
  let end: number = text.length;
  if (end > 0 && text.charCodeAt(end - 1) === 0xFE0F) {
    end--;
  }
  if (end >= 2) {
    const lastCode: number = text.charCodeAt(end - 1);
    const secondLastCode: number = text.charCodeAt(end - 2);
    if (lastCode >= 0xDC00 && lastCode <= 0xDFFF &&
        secondLastCode >= 0xD800 && secondLastCode <= 0xDBFF) {
      return text.substring(0, end - 2);
    }
  }
  if (end > 0) {
    return text.substring(0, end - 1);
  }
  return '';
}

export const chatReducer: Reducer<ChatUiState, ChatIntent, ChatEffect> = (
  state: ChatUiState,
  intent: ChatIntent,
  env: ReducerEnv
): ReducerResult<ChatUiState, ChatEffect> => {
  switch (intent.kind) {
    case 'loadInitialMessages': {
      if (state.isLoading || state.messages.length > 0) {
        return reduced(state);
      }
      const nextState: ChatUiState = state.copyWith({
        isLoading: true,
        errorMessage: null
      });
      const effects: ChatEffect[] = [new FetchInitialMessages(state.chatId)];
      return reduced(nextState, effects);
    }

    case 'loadOlderMessages': {
      if (state.isLoading || !state.hasMoreOlder) {
        return reduced(state);
      }
      const nextState: ChatUiState = state.copyWith({
        isLoading: true,
        errorMessage: null
      });
      const effects: ChatEffect[] = [new FetchOlderMessages(state.chatId)];
      return reduced(nextState, effects);
    }

    case 'onMessagesLoaded': {
      const loadedIntent: OnMessagesLoaded = intent as OnMessagesLoaded;
      const viewerItems: MediaViewerItem[] = buildViewerItems(loadedIntent.messages);
      let activeIndex: number = state.activeViewerIndex;
      if (activeIndex >= viewerItems.length) {
        activeIndex = viewerItems.length > 0 ? viewerItems.length - 1 : -1;
      }
      // MSG-106：选择集合收敛——选中期间消息被删除/撤回时剔除失效 id；
      // 全部失效则连选择态一起退出（没有可转发的目标）。
      const pruned: readonly number[] = retainExistingSelection(
        state.selectedMessageIds,
        (messageId: number): boolean => {
          for (let i = 0; i < loadedIntent.messages.length; i++) {
            if (loadedIntent.messages[i].messageId === messageId) {
              return true;
            }
          }
          return false;
        }
      );
      const keepSelectionMode: boolean = state.selectionMode && pruned.length > 0;
      let composerMode: ComposerMode | null = state.composerMode;
      if (composerMode !== null && composerMode.kind === 'reply') {
        const replyMode: ComposerReplyMode = composerMode as ComposerReplyMode;
        if (replyMode.previewTitle === 'Reply' || replyMode.previewText.length === 0) {
          for (let i = 0; i < loadedIntent.messages.length; i++) {
            const msg: MessageItem = loadedIntent.messages[i];
            if (msg.messageId === replyMode.targetMessageId) {
              composerMode = new ComposerReplyMode(
                replyMode.targetMessageId,
                replyAuthorLabel(state, msg),
                messageSnippet(msg.text)
              );
              break;
            }
          }
        }
      }
      const nextState: ChatUiState = state.copyWith({
        messages: loadedIntent.messages,
        hasMoreOlder: loadedIntent.hasMoreOlder,
        isLoading: false,
        errorMessage: null,
        viewerItems: viewerItems,
        activeViewerIndex: activeIndex,
        lastReadInboxMessageId: loadedIntent.lastReadInboxMessageId > 0
          ? loadedIntent.lastReadInboxMessageId
          : state.lastReadInboxMessageId,
        unreadCount: loadedIntent.unreadCount,
        selectionMode: keepSelectionMode,
        selectedMessageIds: keepSelectionMode ? pruned : [],
        composerMode: composerMode
      });
      return reduced(nextState);
    }

    case 'onMessagesLoadFailed': {
      const failedIntent: OnMessagesLoadFailed = intent as OnMessagesLoadFailed;
      const nextState: ChatUiState = state.copyWith({
        isLoading: false,
        errorMessage: failedIntent.error.message
      });
      return reduced(nextState);
    }

    case 'composerTextChanged': {
      const changedIntent: ComposerTextChanged = intent as ComposerTextChanged;
      // 输入即清掉陈旧错误（发送失败/加载失败），不打断正在打的字。
      const nextState: ChatUiState = state.copyWith({
        composerText: changedIntent.text,
        errorMessage: null
      });
      return reduced(nextState);
    }

    case 'restoreDraft': {
      const draftIntent: RestoreDraft = intent as RestoreDraft;
      // 若草稿全为空则无需恢复
      if (draftIntent.draftText.length === 0 && draftIntent.replyToMessageId === 0) {
        return reduced(state);
      }
      // 只有在当前输入栏为空时才恢复，避免覆盖用户已输入的内容
      if (state.composerText.length > 0) {
        return reduced(state);
      }
      let mode: ComposerMode | null = state.composerMode;
      if (draftIntent.replyToMessageId > 0 && mode === null) {
        const item: MessageItem | null = findMessage(state, draftIntent.replyToMessageId);
        const author: string = item !== null ? replyAuthorLabel(state, item) : 'Reply';
        const snippet: string = item !== null ? messageSnippet(item.text) : '';
        mode = new ComposerReplyMode(draftIntent.replyToMessageId, author, snippet);
      }
      const nextState: ChatUiState = state.copyWith({
        composerText: draftIntent.draftText,
        composerMode: mode
      });
      return reduced(nextState);
    }

    case 'sendCurrentMessage': {
      // 空文本（trim 后）不发送。
      const text: string = state.composerText.trim();
      if (text.length === 0) {
        return reduced(state);
      }
      const mode: ComposerMode | null = state.composerMode;
      if (mode !== null && mode.kind === 'edit') {
        // 编辑模式：改调 editMessageText；发出后退出编辑并恢复进入前的草稿。
        const editMode: ComposerEditMode = mode as ComposerEditMode;
        const nextState: ChatUiState = state.copyWith({
          composerMode: null,
          composerText: editMode.draftBackup,
          errorMessage: null,
          showEmojiBoard: false
        });
        const effects: ChatEffect[] = [new EditMessageText(state.chatId, editMode.targetMessageId, text)];
        return reduced(nextState, effects);
      }
      if (mode !== null && mode.kind === 'reply') {
        // 回复模式：sendMessage 带 reply_to；发出后清除回复态。
        const replyMode: ComposerReplyMode = mode as ComposerReplyMode;
        const nextState: ChatUiState = state.copyWith({
          composerMode: null,
          composerText: '',
          errorMessage: null,
          showEmojiBoard: false
        });
        const effects: ChatEffect[] = [new SendTextMessage(state.chatId, text, replyMode.targetMessageId)];
        return reduced(nextState, effects);
      }
      // 普通发送：发送后立即清空输入栏（乐观清空，
      // 失败由 OnMessageSendFailed 回灌 errorMessage 提示，不回填文本）。
      const nextState: ChatUiState = state.copyWith({
        composerText: '',
        errorMessage: null,
        showEmojiBoard: false
      });
      const effects: ChatEffect[] = [new SendTextMessage(state.chatId, text)];
      return reduced(nextState, effects);
    }

    case 'onMessageSendFailed': {
      const sendFailedIntent: OnMessageSendFailed = intent as OnMessageSendFailed;
      const nextState: ChatUiState = state.copyWith({
        errorMessage: sendFailedIntent.error.message
      });
      return reduced(nextState);
    }

    case 'pickAndSendPhoto': {
      let replyToMessageId: number = 0;
      if (state.composerMode !== null && state.composerMode.kind === 'reply') {
        replyToMessageId = (state.composerMode as ComposerReplyMode).targetMessageId;
      }
      const caption: string = state.composerText.trim();
      const effects: ChatEffect[] = [
        new PickAndSendPhotoEffect(state.chatId, replyToMessageId, caption)
      ];
      const nextState: ChatUiState = state.showAttachmentMenu ? state.copyWith({ showAttachmentMenu: false }) : state;
      return reduced(nextState, effects);
    }

    case 'pickAndSendFile': {
      let replyToMessageId: number = 0;
      if (state.composerMode !== null && state.composerMode.kind === 'reply') {
        replyToMessageId = (state.composerMode as ComposerReplyMode).targetMessageId;
      }
      const caption: string = state.composerText.trim();
      const effects: ChatEffect[] = [
        new PickAndSendFileEffect(state.chatId, replyToMessageId, caption)
      ];
      const nextState: ChatUiState = state.showAttachmentMenu ? state.copyWith({ showAttachmentMenu: false }) : state;
      return reduced(nextState, effects);
    }

    // MEDIA-105：与选图/选文件同构——带出回复目标与当前草稿作为 caption，
    // 并收起附件面板。真正的选取与发送交给 coordinator（需要系统选择器副作用）。
    case 'pickAndSendVideo': {
      let replyToMessageId: number = 0;
      if (state.composerMode !== null && state.composerMode.kind === 'reply') {
        replyToMessageId = (state.composerMode as ComposerReplyMode).targetMessageId;
      }
      const caption: string = state.composerText.trim();
      const effects: ChatEffect[] = [
        new PickAndSendVideoEffect(state.chatId, replyToMessageId, caption)
      ];
      const nextState: ChatUiState = state.showAttachmentMenu ? state.copyWith({ showAttachmentMenu: false }) : state;
      return reduced(nextState, effects);
    }

    case 'openAttachmentMenu': {
      return reduced(state.copyWith({ showAttachmentMenu: true, showEmojiBoard: false }));
    }

    case 'closeAttachmentMenu': {
      return reduced(state.copyWith({ showAttachmentMenu: false }));
    }

    case 'toggleAttachmentMenu': {
      const nextAttachment: boolean = !state.showAttachmentMenu;
      return reduced(state.copyWith({
        showAttachmentMenu: nextAttachment,
        showEmojiBoard: nextAttachment ? false : state.showEmojiBoard
      }));
    }

    case 'openEmojiBoard': {
      return reduced(state.copyWith({ showEmojiBoard: true, showAttachmentMenu: false }));
    }

    case 'closeEmojiBoard': {
      return reduced(state.copyWith({ showEmojiBoard: false }));
    }

    case 'toggleEmojiBoard': {
      const nextEmoji: boolean = !state.showEmojiBoard;
      return reduced(state.copyWith({
        showEmojiBoard: nextEmoji,
        showAttachmentMenu: nextEmoji ? false : state.showAttachmentMenu
      }));
    }

    case 'insertEmoji': {
      const insertIntent: InsertEmoji = intent as InsertEmoji;
      const emoji: string = insertIntent.emoji;
      const filtered: string[] = state.recentEmojis.filter((e: string): boolean => e !== emoji);
      const nextRecents: string[] = [emoji, ...filtered].slice(0, 32);
      return reduced(state.copyWith({
        composerText: state.composerText + emoji,
        recentEmojis: nextRecents
      }));
    }

    case 'deleteLastEmojiChar': {
      return reduced(state.copyWith({
        composerText: removeLastEmojiChar(state.composerText)
      }));
    }

    case 'clearRecentEmojis': {
      return reduced(state.copyWith({
        recentEmojis: []
      }));
    }

    case 'cancelMediaUpload': {
      const cancelIntent: CancelMediaUpload = intent as CancelMediaUpload;
      return reduced(state, [
        new DeleteMessages(state.chatId, [cancelIntent.messageId], true)
      ]);
    }

    case 'cancelMediaDownload': {
      // FILE-103：取消媒体/文件下载
      const cancelIntent: CancelMediaDownload = intent as CancelMediaDownload;
      return reduced(state, [new CancelMediaDownloadEffect(cancelIntent.fileId)]);
    }

    case 'backToChatList': {
      // EMOJI-101：表情面板打开时，返回先关闭面板不离开页面。
      if (state.showEmojiBoard) {
        return reduced(state.copyWith({ showEmojiBoard: false }));
      }
      // VOICE-101：录音态激活时，返回先取消录音。
      if (state.isRecordingVoice) {
        return reduced(
          state.copyWith({ isRecordingVoice: false, recordingDurationSec: 0 }),
          [new CancelVoiceRecordEffect(state.chatId)]
        );
      }
      // COMPOSER-102：附件面板打开时，返回先关闭面板不离开页面。
      if (state.showAttachmentMenu) {
        return reduced(state.copyWith({ showAttachmentMenu: false }));
      }
      // 撤销路径：若全屏查看器打开，先关闭查看器不离开页面。
      if (state.activeViewerIndex >= 0) {
        return reduced(state.copyWith({ activeViewerIndex: -1 }));
      }
      // 气泡长按动作菜单打开时，返回先关闭菜单。
      if (state.actionMenu !== null) {
        return reduced(state.copyWith({ actionMenu: null }));
      }
      // MSG-106：多选转发态激活时，返回只退出选择态，不离开页面。
      if (state.selectionMode) {
        return reduced(state.copyWith({ selectionMode: false, selectedMessageIds: clearSelection() }));
      }
      // 回复/编辑模式激活时，返回先退出模式（编辑恢复草稿），不离开页面。
      if (state.composerMode !== null) {
        return reduced(cancelMode(state));
      }
      const effects: ChatEffect[] = [new NavigateBack()];
      return reduced(state, effects);
    }

    case 'messageActionRequested': {
      const requested: MessageActionRequested = intent as MessageActionRequested;
      // 消息已不在列表（刚被删除）→ 不拉权限。
      if (findMessage(state, requested.messageId) === null) {
        return reduced(state);
      }
      const effects: ChatEffect[] = [new FetchMessagePermissions(state.chatId, requested.messageId)];
      return reduced(state, effects);
    }

    case 'onMessageActionMenuLoaded': {
      const loaded: OnMessageActionMenuLoaded = intent as OnMessageActionMenuLoaded;
      const item: MessageItem | null = findMessage(state, loaded.messageId);
      if (item === null) {
        return reduced(state);
      }
      // 权限过滤：回复恒可（发送失败消息不可回复）；编辑仅己方文本消息且 canBeEdited；
      // 删除需 canBeDeletedOnlyForSelf || canBeDeletedForAllUsers（发送失败消息恒可删除撤销）；
      // revoke 取 canBeDeletedForAllUsers（可对所有人删则对所有人删，失败消息为本地撤销）；
      // MSG-106：转发需 canBeForwarded（发送失败消息不可转发）；
      // MSG-105：复制文本需 canBeSaved 且非空文本；复制链接需 canBeSaved 且存在链接；
      // FILE-103：失败消息展示 Resend 重发选项。
      const isFailed: boolean = item.sendState === 'failed';
      const showResend: boolean = isFailed;
      const showReply: boolean = !isFailed;
      const showEdit: boolean = !isFailed && item.isOutgoing && item.isTextMessage && loaded.canBeEdited;
      const showDelete: boolean = isFailed || loaded.canBeDeletedOnlyForSelf || loaded.canBeDeletedForAllUsers;
      const showCopy: boolean = !isFailed && loaded.canBeSaved && item.text.trim().length > 0;
      const firstLink: string | null = extractFirstLink(item);
      const showCopyLink: boolean = !isFailed && loaded.canBeSaved && firstLink !== null;
      const showForward: boolean = !isFailed && loaded.canBeForwarded;
      const showPin: boolean = !isFailed && loaded.canBePinned;
      const isPinned: boolean = loaded.isPinned || item.isPinned;
      const chosenReactions: string[] = item.reactionChips
        .filter((chip: ReactionChip): boolean => chip.isChosen)
        .map((chip: ReactionChip): string => chip.emoji);
      const availableReactions: string[] = ['👍', '❤️', '🔥', '🎉', '👏', '😂'];
      const menu: MessageActionMenuState = new MessageActionMenuState(
        loaded.messageId,
        showReply,
        showEdit,
        showDelete,
        isFailed ? true : loaded.canBeDeletedForAllUsers,
        showForward,
        showCopy,
        showCopyLink,
        firstLink,
        showResend,
        showPin,
        isPinned,
        availableReactions,
        chosenReactions
      );
      const nextState: ChatUiState = state.copyWith({ actionMenu: menu });
      return reduced(nextState);
    }

    case 'dismissMessageActionMenu': {
      if (state.actionMenu === null) {
        return reduced(state);
      }
      return reduced(state.copyWith({ actionMenu: null }));
    }

    case 'copyMessageText': {
      const menu: MessageActionMenuState | null = state.actionMenu;
      if (menu === null || !menu.showCopy) {
        return reduced(state);
      }
      const item: MessageItem | null = findMessage(state, menu.messageId);
      if (item === null || item.text.trim().length === 0) {
        return reduced(state.copyWith({ actionMenu: null }));
      }
      const nextState: ChatUiState = state.copyWith({ actionMenu: null });
      const effects: ChatEffect[] = [new CopyTextToClipboard(item.text, '已复制到剪贴板')];
      return reduced(nextState, effects);
    }

    case 'copyMessageLink': {
      const menu: MessageActionMenuState | null = state.actionMenu;
      if (menu === null || !menu.showCopyLink || menu.linkUrlToCopy === null) {
        return reduced(state);
      }
      const nextState: ChatUiState = state.copyWith({ actionMenu: null });
      const effects: ChatEffect[] = [new CopyTextToClipboard(menu.linkUrlToCopy, '已复制链接')];
      return reduced(nextState, effects);
    }

    case 'replyToMessage': {
      const menu: MessageActionMenuState | null = state.actionMenu;
      if (menu === null) {
        return reduced(state);
      }
      const item: MessageItem | null = findMessage(state, menu.messageId);
      if (item === null) {
        return reduced(state.copyWith({ actionMenu: null }));
      }
      const mode: ComposerReplyMode = new ComposerReplyMode(
        menu.messageId,
        replyAuthorLabel(state, item),
        messageSnippet(item.text)
      );
      const nextState: ChatUiState = state.copyWith({
        actionMenu: null,
        composerMode: mode
      });
      return reduced(nextState);
    }

    case 'editMessage': {
      const menu: MessageActionMenuState | null = state.actionMenu;
      if (menu === null || !menu.showEdit) {
        return reduced(state);
      }
      const item: MessageItem | null = findMessage(state, menu.messageId);
      if (item === null || !item.isOutgoing || !item.isTextMessage) {
        return reduced(state.copyWith({ actionMenu: null }));
      }
      // 进入编辑：暂存当前草稿，输入栏填入被编辑消息原文。
      const mode: ComposerEditMode = new ComposerEditMode(
        menu.messageId,
        messageSnippet(item.text),
        state.composerText
      );
      const nextState: ChatUiState = state.copyWith({
        actionMenu: null,
        composerMode: mode,
        composerText: item.text
      });
      return reduced(nextState);
    }

    case 'deleteMessage': {
      const menu: MessageActionMenuState | null = state.actionMenu;
      if (menu === null || !menu.showDelete) {
        return reduced(state);
      }
      let nextState: ChatUiState = state.copyWith({ actionMenu: null });
      // 删的正是回复/编辑目标 → 一并退出输入栏模式。
      const mode: ComposerMode | null = state.composerMode;
      if (mode !== null && mode.targetMessageId === menu.messageId) {
        nextState = cancelMode(nextState);
      }
      const targetItem: MessageItem | null = findMessage(state, menu.messageId);
      const idsToDelete: number[] = (targetItem !== null && targetItem.albumMessageIds.length > 0)
        ? targetItem.albumMessageIds
        : [menu.messageId];
      const effects: ChatEffect[] = [new DeleteMessages(state.chatId, idsToDelete, menu.deleteRevoke)];
      return reduced(nextState, effects);
    }

    case 'pinMessage': {
      const menu: MessageActionMenuState | null = state.actionMenu;
      if (menu === null || !menu.showPin) {
        return reduced(state);
      }
      const pinIntent: PinMessage = intent as PinMessage;
      const nextState: ChatUiState = state.copyWith({ actionMenu: null });
      return reduced(nextState, [
        new PinMessageEffect(
          state.chatId,
          menu.messageId,
          pinIntent.disableNotification,
          pinIntent.onlyForSelf
        )
      ]);
    }

    case 'unpinMessage': {
      const menu: MessageActionMenuState | null = state.actionMenu;
      if (menu === null || !menu.showPin) {
        return reduced(state);
      }
      const nextState: ChatUiState = state.copyWith({ actionMenu: null });
      return reduced(nextState, [
        new UnpinMessageEffect(state.chatId, menu.messageId)
      ]);
    }

    case 'cancelComposerMode': {
      return reduced(cancelMode(state));
    }

    case 'onMessageActionFailed': {
      const failed: OnMessageActionFailed = intent as OnMessageActionFailed;
      const nextState: ChatUiState = state.copyWith({
        errorMessage: failed.error.message
      });
      return reduced(nextState);
    }

    // ---- MSG-106 转发多选流 ----

    case 'forwardMessagesRequested': {
      // 菜单点选 Forward：关闭菜单、进入选择态并预选中该条。
      // showForward 已在 onMessageActionMenuLoaded 内按 can_be_forwarded 过滤。
      const menu: MessageActionMenuState | null = state.actionMenu;
      if (menu === null || !menu.showForward) {
        return reduced(state);
      }
      const item: MessageItem | null = findMessage(state, menu.messageId);
      if (item === null) {
        return reduced(state.copyWith({ actionMenu: null }));
      }
      const nextState: ChatUiState = state.copyWith({
        actionMenu: null,
        selectionMode: true,
        selectedMessageIds: toggleMessageSelection([], menu.messageId),
        errorMessage: null
      });
      return reduced(nextState);
    }

    case 'toggleMessageSelection': {
      const toggle: ToggleMessageSelection = intent as ToggleMessageSelection;
      if (!state.selectionMode) {
        return reduced(state);
      }
      // 消息已不在列表（刚被删除）→ 忽略，选择集合不动。
      if (findMessage(state, toggle.messageId) === null) {
        return reduced(state);
      }
      const next: number[] = toggleMessageSelection(state.selectedMessageIds, toggle.messageId);
      // 取消掉最后一条 → 自动退出选择态（Telegram X 行为）。
      if (next.length === 0) {
        return reduced(state.copyWith({ selectionMode: false, selectedMessageIds: clearSelection() }));
      }
      return reduced(state.copyWith({ selectedMessageIds: next }));
    }

    case 'exitMessageSelection': {
      if (!state.selectionMode) {
        return reduced(state);
      }
      return reduced(state.copyWith({ selectionMode: false, selectedMessageIds: clearSelection() }));
    }

    case 'confirmForwardSelection': {
      // 顶栏 Forward：把"给这些消息挑目标"交给装配层（entry 持有会话列表数据）。
      if (!state.selectionMode || state.selectedMessageIds.length === 0) {
        return reduced(state);
      }
      const expandedIds: number[] = [];
      for (let i = 0; i < state.selectedMessageIds.length; i++) {
        const selId: number = state.selectedMessageIds[i];
        const msgItem: MessageItem | null = findMessage(state, selId);
        if (msgItem !== null && msgItem.albumMessageIds.length > 0) {
          for (let j = 0; j < msgItem.albumMessageIds.length; j++) {
            expandedIds.push(msgItem.albumMessageIds[j]);
          }
        } else {
          expandedIds.push(selId);
        }
      }
      const effects: ChatEffect[] = [
        new OpenForwardPicker(state.chatId, expandedIds)
      ];
      return reduced(state, effects);
    }

    case 'forwardSelectedToChat': {
      const pick: ForwardSelectedToChat = intent as ForwardSelectedToChat;
      if (!state.selectionMode || state.selectedMessageIds.length === 0) {
        return reduced(state);
      }
      if (pick.toChatId === 0) {
        return reduced(state);
      }
      const expandedIds: number[] = [];
      for (let i = 0; i < state.selectedMessageIds.length; i++) {
        const selId: number = state.selectedMessageIds[i];
        const msgItem: MessageItem | null = findMessage(state, selId);
        if (msgItem !== null && msgItem.albumMessageIds.length > 0) {
          for (let j = 0; j < msgItem.albumMessageIds.length; j++) {
            expandedIds.push(msgItem.albumMessageIds[j]);
          }
        } else {
          expandedIds.push(selId);
        }
      }
      // 选择态保留到 OnForwardCompleted：失败时用户可直接换目标重试。
      const effects: ChatEffect[] = [
        new ForwardMessages(state.chatId, pick.toChatId, expandedIds, pick.sendCopy)
      ];
      return reduced(state, effects);
    }

    case 'onForwardCompleted': {
      // 成功：收起选择态并清空选择（幂等——已退出时返回原引用）。
      if (!state.selectionMode && state.selectedMessageIds.length === 0) {
        return reduced(state);
      }
      const nextState: ChatUiState = state.copyWith({
        selectionMode: false,
        selectedMessageIds: clearSelection(),
        errorMessage: null
      });
      return reduced(nextState);
    }

    case 'onForwardFailed': {
      const failure: OnForwardFailed = intent as OnForwardFailed;
      // 保留选择态：换一个目标会话即可重试。
      const nextState: ChatUiState = state.copyWith({
        errorMessage: failure.error.message
      });
      return reduced(nextState);
    }

    case 'onVisibleRangeChanged': {
      // MSG-104：入屏即读。index → 该范围内最大 incoming 消息 id，出
      // ReportMessagesRead；无 incoming 不出 effect。节流（只增不减）在
      // coordinator 执行侧（ReadReportThrottle），reducer 保持无状态。
      const visible: OnVisibleRangeChanged = intent as OnVisibleRangeChanged;
      const targetId: number = incomingIdUpTo(state.messages, visible.lastVisibleIndex);
      if (targetId <= 0) {
        return reduced(state);
      }
      const effects: ChatEffect[] = [new ReportMessagesRead(state.chatId, targetId)];
      return reduced(state, effects);
    }

    case 'tapFailedMessage': {
      // MSG-104：点击失败气泡重发；非失败态/未知消息忽略。状态不变：
      // 结算由 updateMessageSendSucceeded/Failed 订阅驱动。
      const tapped: TapFailedMessage = intent as TapFailedMessage;
      const item: MessageItem | null = findMessage(state, tapped.messageId);
      if (item === null || item.sendState !== 'failed') {
        return reduced(state);
      }
      const effects: ChatEffect[] = [new ResendMessage(state.chatId, tapped.messageId)];
      return reduced(state, effects);
    }

    case 'resendFailedMessage': {
      // FILE-103：长按菜单或重试图标触发失败消息重发，收起菜单并派发 ResendMessage。
      const resendIntent: ResendFailedMessage = intent as ResendFailedMessage;
      const item: MessageItem | null = findMessage(state, resendIntent.messageId);
      if (item === null || item.sendState !== 'failed') {
        return reduced(state.copyWith({ actionMenu: null }));
      }
      const nextState: ChatUiState = state.copyWith({ actionMenu: null });
      const effects: ChatEffect[] = [new ResendMessage(state.chatId, resendIntent.messageId)];
      return reduced(nextState, effects);
    }

    case 'openMediaViewer': {
      const openIntent: OpenMediaViewer = intent as OpenMediaViewer;
      const viewerItems: MediaViewerItem[] = buildViewerItems(state.messages);
      let targetIndex: number = -1;
      for (let i = 0; i < viewerItems.length; i++) {
        if (viewerItems[i].messageId === openIntent.messageId) {
          if (openIntent.targetFileId !== undefined && openIntent.targetFileId > 0) {
            if (viewerItems[i].media.fileId === openIntent.targetFileId) {
              targetIndex = i;
              break;
            }
          } else {
            targetIndex = i;
            break;
          }
        }
      }
      if (targetIndex < 0) {
        return reduced(state);
      }
      const nextState: ChatUiState = state.copyWith({
        viewerItems: viewerItems,
        activeViewerIndex: targetIndex
      });
      return reduced(nextState);
    }

    case 'closeMediaViewer': {
      if (state.activeViewerIndex < 0) {
        return reduced(state);
      }
      return reduced(state.copyWith({ activeViewerIndex: -1 }));
    }

    case 'changeViewerIndex': {
      const changeIntent: ChangeViewerIndex = intent as ChangeViewerIndex;
      if (changeIntent.newIndex < 0 || changeIntent.newIndex >= state.viewerItems.length) {
        return reduced(state);
      }
      return reduced(state.copyWith({ activeViewerIndex: changeIntent.newIndex }));
    }

    // ---- SEARCH-102 聊天内搜索 ----
    case 'openChatSearch': {
      if (state.showSearch) {
        return reduced(state);
      }
      // 清空在途标记，展开搜索面板。
      return reduced(state.copyWith({
        showSearch: true,
        searchQuery: '',
        searchResults: [],
        isSearching: false,
        jumpToMessageId: 0
      }));
    }

    case 'closeChatSearch': {
      if (!state.showSearch) {
        return reduced(state);
      }
      return reduced(state.copyWith({
        showSearch: false,
        searchQuery: '',
        searchResults: [],
        isSearching: false,
        jumpToMessageId: 0
      }));
    }

    case 'chatSearchQueryChanged': {
      const queryIntent: ChatSearchQueryChanged = intent as ChatSearchQueryChanged;
      return reduced(state.copyWith({
        searchQuery: queryIntent.query,
        jumpToMessageId: 0
      }));
    }

    case 'performChatSearch': {
      const query: string = state.searchQuery.trim();
      if (query.length === 0 || state.isSearching) {
        return reduced(state);
      }
      const effects: ChatEffect[] = [new FetchChatSearch(state.chatId, query, 0)];
      return reduced(state.copyWith({ isSearching: true }), effects);
    }

    case 'onChatSearchLoaded': {
      const loadedIntent: OnChatSearchLoaded = intent as OnChatSearchLoaded;
      return reduced(state.copyWith({
        isSearching: false,
        searchResults: loadedIntent.results
      }));
    }

    case 'onChatSearchFailed': {
      const failedIntent: OnChatSearchFailed = intent as OnChatSearchFailed;
      return reduced(state.copyWith({
        isSearching: false,
        errorMessage: failedIntent.error.message
      }));
    }

    case 'jumpToSearchResult': {
      const jumpIntent: JumpToSearchResult = intent as JumpToSearchResult;
      if (jumpIntent.messageId <= 0 || state.jumpToMessageId !== 0) {
        return reduced(state);
      }
      const effects: ChatEffect[] = [new JumpToMessage(jumpIntent.messageId)];
      // 关闭搜索面板，发起历史围绕拉取。
      return reduced(state.copyWith({
        showSearch: false,
        jumpToMessageId: jumpIntent.messageId,
        searchResults: []
      }), effects);
    }

    case 'onJumpToMessageReady': {
      const readyIntent: OnJumpToMessageReady = intent as OnJumpToMessageReady;
      return reduced(state.copyWith({ jumpToMessageId: readyIntent.messageId }));
    }

    case 'clearJumpToMessage': {
      if (state.jumpToMessageId === 0) {
        return reduced(state);
      }
      return reduced(state.copyWith({ jumpToMessageId: 0 }));
    }

    // ---- MSG-109 头部信息区 ----

    case 'onHeaderSubtitleChanged': {
      // 副标题回灌：值相同不动状态，避免无关重渲。
      const subtitleIntent: OnHeaderSubtitleChanged = intent as OnHeaderSubtitleChanged;
      if (state.headerSubtitle === subtitleIntent.subtitle) {
        return reduced(state);
      }
      return reduced(state.copyWith({ headerSubtitle: subtitleIntent.subtitle }));
    }

    case 'onChatKindChanged': {
      // 会话种类回灌（驱动头部通话按钮与 ⋮ 菜单项）；值相同不动状态。
      const kindIntent: OnChatKindChanged = intent as OnChatKindChanged;
      if (state.chatKind === kindIntent.chatKind) {
        return reduced(state);
      }
      return reduced(state.copyWith({ chatKind: kindIntent.chatKind }));
    }

    // ---- MSG-108 置顶消息横条 ----

    case 'onPinnedMessageLoaded': {
      const pIntent: OnPinnedMessageLoaded = intent as OnPinnedMessageLoaded;
      return reduced(state.copyWith({
        pinnedMessage: pIntent.pinnedMessage,
        showPinnedBar: pIntent.pinnedMessage !== null
      }));
    }

    case 'dismissPinnedBar': {
      return reduced(state.copyWith({ showPinnedBar: false }));
    }

    case 'jumpToPinnedMessage': {
      if (state.pinnedMessage === null || state.pinnedMessage.messageId <= 0) {
        return reduced(state);
      }
      return reduced(
        state.copyWith({ jumpToMessageId: state.pinnedMessage.messageId }),
        [new JumpToMessage(state.pinnedMessage.messageId)]
      );
    }

    // ---- CHANNEL-101 频道模式 ----

    case 'joinChannel': {
      return reduced(state, [new JoinChannelEffect(state.chatId)]);
    }

    case 'onChannelMemberStatusChanged': {
      const memberIntent: OnChannelMemberStatusChanged = intent as OnChannelMemberStatusChanged;
      if (state.isChannelMember === memberIntent.isMember) {
        return reduced(state);
      }
      return reduced(state.copyWith({ isChannelMember: memberIntent.isMember }));
    }

    case 'openMessageComments': {
      const commentsIntent: OpenMessageComments = intent as OpenMessageComments;
      return reduced(state, [new OpenCommentsEffect(state.chatId, commentsIntent.messageId)]);
    }

    case 'toggleMessageReaction': {
      const reactionIntent: ToggleMessageReaction = intent as ToggleMessageReaction;
      let targetChosen: boolean = false;
      let targetFound: boolean = false;
      const newMessages: MessageItem[] = state.messages.map((item: MessageItem): MessageItem => {
        if (item.messageId !== reactionIntent.messageId) {
          return item;
        }
        let chipUpdated: boolean = false;
        let newChips: ReactionChip[] = item.reactionChips.map((chip: ReactionChip): ReactionChip => {
          if (chip.emoji !== reactionIntent.emoji) {
            return chip;
          }
          chipUpdated = true;
          targetFound = true;
          targetChosen = !chip.isChosen;
          const newCount: number = Math.max(0, chip.count + (targetChosen ? 1 : -1));
          return new ReactionChip(chip.emoji, newCount, targetChosen);
        }).filter((chip: ReactionChip): boolean => chip.count > 0);
        if (!chipUpdated) {
          targetFound = true;
          targetChosen = true;
          newChips = [...newChips, new ReactionChip(reactionIntent.emoji, 1, true)];
        }
        return new MessageItem(
          item.messageId,
          item.text,
          item.timestampMs,
          item.isOutgoing,
          item.senderName,
          item.sendState,
          item.isTextMessage,
          item.isEdited,
          item.replyToMessageId,
          item.replyToSummary,
          item.spans,
          item.senderColorIndex,
          item.isRead,
          item.media,
          item.replySenderName,
          item.replySenderColorIndex,
          item.replyThumbnailPath,
          item.replyIsSticker,
          item.showDateHeader,
          item.dateHeaderText,
          item.showUnreadSeparator,
          item.senderAvatarPath,
          item.albumItems,
          item.albumMessageIds,
          item.linkPreview,
          item.senderUserId,
          item.isChannelPost,
          newChips,
          item.commentCount,
          item.isPinned,
          item.poll
        );
      });
      if (!targetFound) {
        return reduced(state);
      }
      let nextActionMenu: MessageActionMenuState | null = state.actionMenu;
      if (nextActionMenu !== null && nextActionMenu.messageId === reactionIntent.messageId) {
        const nextChosen: string[] = targetChosen
          ? (nextActionMenu.chosenReactions.indexOf(reactionIntent.emoji) === -1
            ? [...nextActionMenu.chosenReactions, reactionIntent.emoji]
            : [...nextActionMenu.chosenReactions])
          : nextActionMenu.chosenReactions.filter((e: string): boolean => e !== reactionIntent.emoji);
        nextActionMenu = new MessageActionMenuState(
          nextActionMenu.messageId,
          nextActionMenu.showReply,
          nextActionMenu.showEdit,
          nextActionMenu.showDelete,
          nextActionMenu.deleteRevoke,
          nextActionMenu.showForward,
          nextActionMenu.showCopy,
          nextActionMenu.showCopyLink,
          nextActionMenu.linkUrlToCopy,
          nextActionMenu.showResend,
          nextActionMenu.showPin,
          nextActionMenu.isPinned,
          nextActionMenu.availableReactions,
          nextChosen
        );
      }
      return reduced(
        state.copyWith({ messages: newMessages, actionMenu: nextActionMenu }),
        [new ToggleReactionEffect(state.chatId, reactionIntent.messageId, reactionIntent.emoji, targetChosen)]
      );
    }

    case 'openStickerSet': {
      const openIntent: OpenStickerSet = intent as OpenStickerSet;
      const initialPreview: StickerSetPreviewState = new StickerSetPreviewState(
        openIntent.setId,
        '',
        '',
        false,
        false,
        false,
        [],
        true,
        false,
        null
      );
      return reduced(
        state.copyWith({
          stickerSetPreview: initialPreview,
          showEmojiBoard: false,
          showAttachmentMenu: false
        }),
        [new FetchStickerSet(openIntent.setId)]
      );
    }

    case 'onStickerSetLoaded': {
      const loadedIntent: OnStickerSetLoaded = intent as OnStickerSetLoaded;
      return reduced(state.copyWith({ stickerSetPreview: loadedIntent.preview }));
    }

    case 'onStickerSetLoadFailed': {
      const failedIntent: OnStickerSetLoadFailed = intent as OnStickerSetLoadFailed;
      if (state.stickerSetPreview !== null && state.stickerSetPreview.setId === failedIntent.setId) {
        return reduced(
          state.copyWith({
            stickerSetPreview: state.stickerSetPreview.copyWith(
              undefined,
              undefined,
              undefined,
              undefined,
              undefined,
              undefined,
              false,
              false,
              failedIntent.error
            )
          })
        );
      }
      return reduced(state);
    }

    case 'closeStickerSetPreview': {
      return reduced(state.copyWith({ stickerSetPreview: null }));
    }

    case 'installStickerSet': {
      const installIntent: InstallStickerSet = intent as InstallStickerSet;
      if (state.stickerSetPreview !== null && state.stickerSetPreview.setId === installIntent.setId) {
        const nextPreview: StickerSetPreviewState = state.stickerSetPreview.copyWith(
          undefined,
          undefined,
          undefined,
          undefined,
          undefined,
          undefined,
          undefined,
          true,
          null
        );
        return reduced(
          state.copyWith({ stickerSetPreview: nextPreview }),
          [new ChangeStickerSetEffect(installIntent.setId, true)]
        );
      }
      return reduced(state, [new ChangeStickerSetEffect(installIntent.setId, true)]);
    }

    case 'uninstallStickerSet': {
      const uninstallIntent: UninstallStickerSet = intent as UninstallStickerSet;
      if (state.stickerSetPreview !== null && state.stickerSetPreview.setId === uninstallIntent.setId) {
        const nextPreview: StickerSetPreviewState = state.stickerSetPreview.copyWith(
          undefined,
          undefined,
          undefined,
          undefined,
          undefined,
          undefined,
          undefined,
          true,
          null
        );
        return reduced(
          state.copyWith({ stickerSetPreview: nextPreview }),
          [new ChangeStickerSetEffect(uninstallIntent.setId, false)]
        );
      }
      return reduced(state, [new ChangeStickerSetEffect(uninstallIntent.setId, false)]);
    }

    case 'onStickerSetChanged': {
      const changedIntent: OnStickerSetChanged = intent as OnStickerSetChanged;
      if (state.stickerSetPreview !== null && state.stickerSetPreview.setId === changedIntent.setId) {
        const nextPreview: StickerSetPreviewState = state.stickerSetPreview.copyWith(
          undefined,
          undefined,
          changedIntent.isInstalled,
          undefined,
          undefined,
          undefined,
          false,
          false,
          null
        );
        return reduced(state.copyWith({ stickerSetPreview: nextPreview }));
      }
      return reduced(state);
    }

    case 'onStickerSetActionFailed': {
      const failedAction: OnStickerSetActionFailed = intent as OnStickerSetActionFailed;
      if (state.stickerSetPreview !== null && state.stickerSetPreview.setId === failedAction.setId) {
        const nextPreview: StickerSetPreviewState = state.stickerSetPreview.copyWith(
          undefined,
          undefined,
          undefined,
          undefined,
          undefined,
          undefined,
          false,
          false,
          failedAction.error
        );
        return reduced(state.copyWith({ stickerSetPreview: nextPreview }));
      }
      return reduced(state);
    }

    case 'sendStickerFromPreview': {
      const sendStickerIntent: SendStickerFromPreview = intent as SendStickerFromPreview;
      const stickerItem: StickerSetItem = sendStickerIntent.item;
      const filtered: StickerSetItem[] = state.recentStickers.filter(
        (s: StickerSetItem): boolean => s.id !== stickerItem.id && s.fileId !== stickerItem.fileId
      );
      const nextRecents: StickerSetItem[] = [stickerItem, ...filtered].slice(0, 32);
      return reduced(
        state.copyWith({
          stickerSetPreview: null,
          recentStickers: nextRecents
        }),
        [new SendStickerMessage(state.chatId, stickerItem.fileId, stickerItem.width, stickerItem.height, stickerItem.emoji)]
      );
    }

    case 'sendSticker': {
      const sendStickerIntent: SendSticker = intent as SendSticker;
      const stickerItem: StickerSetItem = sendStickerIntent.item;
      const filtered: StickerSetItem[] = state.recentStickers.filter(
        (s: StickerSetItem): boolean => s.id !== stickerItem.id && s.fileId !== stickerItem.fileId
      );
      const nextRecents: StickerSetItem[] = [stickerItem, ...filtered].slice(0, 32);
      return reduced(
        state.copyWith({ recentStickers: nextRecents }),
        [new SendStickerMessage(state.chatId, stickerItem.fileId, stickerItem.width, stickerItem.height, stickerItem.emoji)]
      );
    }

    case 'clearRecentStickers': {
      return reduced(state.copyWith({
        recentStickers: []
      }));
    }

    case 'sendGif': {
      const sendGifIntent: SendGif = intent as SendGif;
      const gifItem: GifItem = sendGifIntent.item;
      const filtered: GifItem[] = state.recentGifs.filter(
        (g: GifItem): boolean => g.id !== gifItem.id && g.fileId !== gifItem.fileId
      );
      const nextRecents: GifItem[] = [gifItem, ...filtered].slice(0, 32);
      return reduced(
        state.copyWith({ recentGifs: nextRecents }),
        [new SendAnimationMessage(state.chatId, gifItem.fileId, gifItem.width, gifItem.height, gifItem.title)]
      );
    }

    case 'clearRecentGifs': {
      return reduced(state.copyWith({
        recentGifs: []
      }));
    }

    case 'searchGifs': {
      const searchGifsIntent: SearchGifs = intent as SearchGifs;
      return reduced(state.copyWith({
        gifSearchQuery: searchGifsIntent.query
      }));
    }

    case 'onStickerPreviewFileUpdated': {
      const updateIntent: OnStickerPreviewFileUpdated = intent as OnStickerPreviewFileUpdated;
      if (state.stickerSetPreview === null) {
        return reduced(state);
      }
      let changed: boolean = false;
      const nextStickers: StickerSetItem[] = state.stickerSetPreview.stickers.map((s: StickerSetItem): StickerSetItem => {
        if (s.fileId === updateIntent.fileId || s.id === updateIntent.fileId) {
          changed = true;
          return {
            id: s.id,
            fileId: s.fileId,
            emoji: s.emoji,
            width: s.width,
            height: s.height,
            localPath: updateIntent.localPath,
            thumbnailPath: s.thumbnailPath,
            isDownloaded: true,
            isDownloading: false
          };
        }
        return s;
      });
      if (!changed) {
        return reduced(state);
      }
      const nextPreview: StickerSetPreviewState = state.stickerSetPreview.copyWith(
        undefined,
        undefined,
        undefined,
        undefined,
        undefined,
        nextStickers
      );
      return reduced(state.copyWith({ stickerSetPreview: nextPreview }));
    }

    case 'startVoiceRecord': {
      return reduced(
        state.copyWith({
          isRecordingVoice: true,
          recordingDurationSec: 0
        }),
        [new StartVoiceRecordEffect(state.chatId)]
      );
    }

    case 'stopAndSendVoiceRecord': {
      const replyToId: number = state.composerMode?.kind === 'reply' ? (state.composerMode as ComposerReplyMode).targetMessageId : 0;
      return reduced(
        state.copyWith({
          isRecordingVoice: false,
          recordingDurationSec: 0
        }),
        [new StopAndSendVoiceRecordEffect(state.chatId, replyToId)]
      );
    }

    case 'cancelVoiceRecord': {
      return reduced(
        state.copyWith({
          isRecordingVoice: false,
          recordingDurationSec: 0
        }),
        [new CancelVoiceRecordEffect(state.chatId)]
      );
    }

    case 'voiceRecordTick': {
      const tickIntent: VoiceRecordTick = intent as VoiceRecordTick;
      if (!state.isRecordingVoice) {
        return reduced(state);
      }
      return reduced(
        state.copyWith({
          recordingDurationSec: tickIntent.durationSec
        })
      );
    }

    case 'playVoiceNote': {
      const playIntent: PlayVoiceNote = intent as PlayVoiceNote;
      return reduced(
        state.copyWith({
          playingVoiceMessageId: playIntent.messageId,
          voicePlaybackProgress: 0,
          voicePlaybackTimeSec: 0
        }),
        [new PlayVoiceNoteEffect(state.chatId, playIntent.messageId, playIntent.fileId, playIntent.localPath)]
      );
    }

    case 'pauseVoiceNote': {
      const pauseIntent: PauseVoiceNote = intent as PauseVoiceNote;
      if (state.playingVoiceMessageId === pauseIntent.messageId) {
        return reduced(
          state.copyWith({
            playingVoiceMessageId: null
          }),
          [new PauseVoiceNoteEffect(state.chatId, pauseIntent.messageId)]
        );
      }
      return reduced(state);
    }

    case 'voicePlaybackProgress': {
      const progIntent: VoicePlaybackProgress = intent as VoicePlaybackProgress;
      if (state.playingVoiceMessageId !== progIntent.messageId) {
        return reduced(state);
      }
      const progress: number = progIntent.totalMs > 0 ? Math.min(1, Math.max(0, progIntent.currentMs / progIntent.totalMs)) : 0;
      const timeSec: number = Math.floor(progIntent.currentMs / 1000);
      return reduced(
        state.copyWith({
          voicePlaybackProgress: progress,
          voicePlaybackTimeSec: timeSec
        })
      );
    }

    case 'voicePlaybackCompleted': {
      const compIntent: VoicePlaybackCompleted = intent as VoicePlaybackCompleted;
      if (state.playingVoiceMessageId === compIntent.messageId) {
        return reduced(
          state.copyWith({
            playingVoiceMessageId: null,
            voicePlaybackProgress: 0,
            voicePlaybackTimeSec: 0
          })
        );
      }
      return reduced(state);
    }

    case 'voicePlaybackFailed': {
      const failIntent: VoicePlaybackFailed = intent as VoicePlaybackFailed;
      if (state.playingVoiceMessageId === failIntent.messageId) {
        return reduced(
          state.copyWith({
            playingVoiceMessageId: null,
            voicePlaybackProgress: 0,
            voicePlaybackTimeSec: 0,
            errorMessage: failIntent.error
          })
        );
      }
      return reduced(state);
    }

    // openChatProfile：纯导航意图，reducer 原样透传。

    case 'chatMenuAction': {
      const menuIntent: ChatMenuAction = intent as ChatMenuAction;
      const destructiveActions: string[] = ['clear_history', 'delete_chat', 'report', 'leave'];
      if (destructiveActions.indexOf(menuIntent.action) >= 0) {
        return reduced(
          state.copyWith({
            showMenuConfirmDialog: true,
            pendingMenuAction: menuIntent.action
          })
        );
      }
      return reduced(state);
    }

    case 'confirmMenuAction': {
      return reduced(
        state.copyWith({
          showMenuConfirmDialog: false,
          pendingMenuAction: ''
        })
      );
    }

    case 'dismissMenuConfirmDialog': {
      return reduced(
        state.copyWith({
          showMenuConfirmDialog: false,
          pendingMenuAction: ''
        })
      );
    }

    // ===== POLL-101：发起投票面板（受控编辑态）+ 投票乐观更新 =====

    case 'openPollComposer': {
      return reduced(state.copyWith({
        pollComposer: PollComposerState.draft(),
        showAttachmentMenu: false,
        showEmojiBoard: false
      }));
    }

    case 'closePollComposer': {
      if (state.pollComposer === null) {
        return reduced(state);
      }
      return reduced(state.copyWith({ pollComposer: null }));
    }

    case 'pollQuestionChanged': {
      const composer: PollComposerState | null = state.pollComposer;
      if (composer === null) {
        return reduced(state);
      }
      const questionIntent: PollQuestionChanged = intent as PollQuestionChanged;
      return reduced(state.copyWith({
        pollComposer: composer.copyWith({
          question: questionIntent.text.slice(0, POLL_QUESTION_MAX_LENGTH)
        })
      }));
    }

    case 'pollOptionTextChanged': {
      const composer: PollComposerState | null = state.pollComposer;
      if (composer === null) {
        return reduced(state);
      }
      const optionIntent: PollOptionTextChanged = intent as PollOptionTextChanged;
      if (optionIntent.index < 0 || optionIntent.index >= composer.options.length) {
        return reduced(state);
      }
      const nextOptions: string[] = composer.options.slice();
      nextOptions[optionIntent.index] = optionIntent.text.slice(0, POLL_OPTION_MAX_LENGTH);
      return reduced(state.copyWith({ pollComposer: composer.copyWith({ options: nextOptions }) }));
    }

    case 'addPollComposerOption': {
      const composer: PollComposerState | null = state.pollComposer;
      if (composer === null || composer.options.length >= POLL_MAX_OPTIONS) {
        return reduced(state);
      }
      const nextOptions: string[] = composer.options.slice();
      nextOptions.push('');
      return reduced(state.copyWith({ pollComposer: composer.copyWith({ options: nextOptions }) }));
    }

    case 'removePollComposerOption': {
      const composer: PollComposerState | null = state.pollComposer;
      if (composer === null || composer.options.length <= POLL_MIN_OPTIONS) {
        return reduced(state);
      }
      const removeIntent: RemovePollComposerOption = intent as RemovePollComposerOption;
      if (removeIntent.index < 0 || removeIntent.index >= composer.options.length) {
        return reduced(state);
      }
      const nextOptions: string[] = composer.options.slice();
      nextOptions.splice(removeIntent.index, 1);
      return reduced(state.copyWith({ pollComposer: composer.copyWith({ options: nextOptions }) }));
    }

    case 'togglePollComposerAnonymous': {
      const composer: PollComposerState | null = state.pollComposer;
      if (composer === null) {
        return reduced(state);
      }
      return reduced(state.copyWith({
        pollComposer: composer.copyWith({ isAnonymous: !composer.isAnonymous })
      }));
    }

    case 'togglePollComposerMultiple': {
      const composer: PollComposerState | null = state.pollComposer;
      if (composer === null) {
        return reduced(state);
      }
      return reduced(state.copyWith({
        pollComposer: composer.copyWith({ allowsMultiple: !composer.allowsMultiple })
      }));
    }

    case 'submitPollComposer': {
      const composer: PollComposerState | null = state.pollComposer;
      if (composer === null) {
        return reduced(state);
      }
      const question: string = composer.question.trim();
      const options: string[] = composer.nonEmptyOptions();
      if (question.length === 0 || options.length < POLL_MIN_OPTIONS) {
        return reduced(state);
      }
      return reduced(
        state.copyWith({ pollComposer: null }),
        [new SendPollEffect(state.chatId, question, options, composer.isAnonymous, composer.allowsMultiple)]
      );
    }

    case 'votePollOption': {
      const voteIntent: VotePollOption = intent as VotePollOption;
      if (voteIntent.optionIndex < 0) {
        return reduced(state);
      }
      let targetFound: boolean = false;
      let nextOptionIds: number[] = [];
      const newMessages: MessageItem[] = state.messages.map((item: MessageItem): MessageItem => {
        if (item.messageId !== voteIntent.messageId || item.poll === null) {
          return item;
        }
        const poll: PollView = item.poll;
        // 已结束投票不可再投。
        if (poll.isClosed) {
          return item;
        }
        targetFound = true;
        const tappedChosen: boolean = poll.options.length > voteIntent.optionIndex &&
          poll.options[voteIntent.optionIndex].isChosen;
        const nextOptions: PollOptionView[] = [];
        for (let i: number = 0; i < poll.options.length; i++) {
          const option: PollOptionView = poll.options[i];
          let chosen: boolean = option.isChosen;
          if (i === voteIntent.optionIndex) {
            chosen = poll.allowsMultipleAnswers ? !tappedChosen : true;
          } else if (!poll.allowsMultipleAnswers) {
            chosen = false;
          }
          if (chosen) {
            nextOptionIds.push(i);
          }
          nextOptions.push(new PollOptionView(
            option.index, option.text, option.voterCount, option.votePercentage, chosen
          ));
        }
        const anyChosen: boolean = nextOptionIds.length > 0;
        return item.withPoll(new PollView(
          poll.question,
          nextOptions,
          poll.totalVoterCount,
          poll.isAnonymous,
          poll.allowsMultipleAnswers,
          poll.isClosed,
          poll.showResults || anyChosen,
          anyChosen
        ));
      });
      if (!targetFound) {
        return reduced(state);
      }
      return reduced(
        state.copyWith({ messages: newMessages }),
        [new SetPollAnswerEffect(state.chatId, voteIntent.messageId, nextOptionIds)]
      );
    }
  }

  return reduced(state);
};
