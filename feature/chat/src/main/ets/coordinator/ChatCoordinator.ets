/**
 * feature/chat — 会话页协调器（CHAT-001 + CHAT-002 基础 + CHAT-003 发送 + CHAT-004 消息动作）。
 *
 * 桥接 core/domain 的 MessageProjection 与本模块的 MVI：
 * - dispatch 经 chatReducer 驱动 ChatUiState，并执行 Effect
 *   （FetchInitialMessages / FetchOlderMessages → projection 的 getChatHistory 分页；
 *   SendTextMessage → projection.sendTextMessage（带 replyToMessageId），
 *   请求级/响应级失败回灌 OnMessageSendFailed；NavigateBack → onBack 回调，
 *   由装配层销毁本 coordinator 并切回会话列表）；
 * - CHAT-004：FetchMessagePermissions → projection.getMessageProperties（TDLib
 *   离线方法），回包解码 MessageProperties 后经 OnMessageActionMenuLoaded 回灌；
 *   EditMessageText → projection.editMessageText，DeleteMessages →
 *   projection.deleteMessages；二者成功靠已订阅的 updateMessageContent /
 *   updateMessageEdited / updateDeleteMessages 刷新列表，失败统一回灌
 *   OnMessageActionFailed（errorMessage 细条提示）；
 * - projection 状态变化时把 Message 映射为 MessageItem[]（文本消息取原文，
 *   MSG-101 起同时解析 FormattedText entities 产出富文本 spans；
 *   多媒体按类型出占位标签），经 OnMessagesLoaded 回灌 reducer；
 * - MSG-102：持有 UserRegistry（构造即订阅 updateUser/updateUserStatus，
 *   destroy 时 stop）；start() 发一次 getChat 解析会话种类（群聊才署名）；
 *   群聊收到的用户消息经 resolveSenderInfo 出署名，缓存未命中时
 *   requestUser + subscribeUser（requestedSenderIds 防重），User 晚到后
 *   scheduleSyncFromProjection 重映射上屏；
 * - MSG-109：getChat 回包缓存 supergroupId/basicGroupId 并回灌 OnChatKindChanged；
 *   buildHeaderSubtitle() 计算头部副标题（私聊状态 / 群成员数+在线人数）经
 *   OnHeaderSubtitleChanged 回灌；私聊用户经 requestUser + subscribeUser 晚到重算，
 *   群/频道经 getSupergroupFullInfo + updateChatOnlineMemberCount 订阅刷新；
 *   openChatProfile 转 onOpenChatProfile 回调，chatMenuAction 只记日志。
 * - TDLib 更新成批到达，经 setTimeout(0) 合并为一个同步点，避免反复重绘。
 * - 日志不记录消息正文，send 结果只记 ok/err 与稳定错误分类。
 *
 * 生命周期：start() 打开会话（openChat + 首屏加载），destroy() 关闭（closeChat）。
 */

import { Logger } from '@tgx/observability';
import {
  ClipboardPort,
  ToastPort,
  MediaPickerPort,
  PickedMedia,
  FakeClipboard,
  FakeToast,
  FakeMediaPicker,
  AudioPlaybackMetadata,
  AudioPlayerPort,
  AudioRecorderPort,
  ERR_MIC_PERMISSION_DENIED,
  FakeAudioPlayer,
  FakeAudioRecorder
} from '@tgx/platform-ports';
import { ManualClock, SequentialIdGenerator, AppError, AppErrors } from '@tgx/core-common';
import { AccountScope } from '@tgx/core-account';
import {
  Animation,
  Audio,
  BasicGroup,
  Chat,
  ChatTypeBasicGroup,
  ChatTypePrivate,
  ChatTypeSecret,
  ChatTypeSupergroup,
  decodeBasicGroup,
  decodeChat,
  decodeMessage,
  decodeMessageProperties,
  decodeFoundChatMessages,
  decodeSupergroupFullInfo,
  decodeTdUpdate,
  FoundChatMessages,
  Document,
  DraftMessage,
  DraftMessageContentText,
  encodeGetBasicGroup,
  encodeGetChat,
  encodeGetMessage,
  encodeGetSupergroupFullInfo,
  File,
  GetBasicGroup,
  GetChat,
  GetMessage,
  GetSupergroupFullInfo,
  InputMessageReplyToMessage,
  LinkPreview,
  LinkPreviewTypeArticle,
  LinkPreviewTypePhoto,
  LinkPreviewTypeVideo,
  LinkPreviewTypeAnimation,
  LinkPreviewTypeDocument,
  LinkPreviewTypeApp,
  Message,
  MessageAnimation,
  MessageAudio,
  MessageDocument,
  MessagePhoto,
  MessageProperties,
  MessageReplyToMessage,
  MessageSenderUser,
  MessageSticker,
  MessageText,
  MessageVideo,
  MessageVideoNote,
  MessageVoiceNote,
  Photo,
  PhotoSize,
  Sticker,
  SupergroupFullInfo,
  Supergroup,
  decodeSupergroup,
  GetSupergroup,
  encodeGetSupergroup,
  ReactionTypeEmoji,
  TdJsonRaw,
  TdMessageContent,
  TdMessageReplyTo,
  TdMessageSendingState,
  TdUpdate,
  TdUserStatus,
  UpdateChatOnlineMemberCount,
  User,
  Video,
  VideoNote,
  VoiceNote,
  GetStickerSet,
  encodeGetStickerSet,
  decodeStickerSet,
  StickerSet,
  ChangeStickerSet,
  encodeChangeStickerSet,
  InputMessageSticker,
  InputSticker,
  InputFileId,
  SendMessage,
  encodeSendMessage,
  DeleteChat,
  encodeDeleteChat,
  DeleteChatHistory,
  encodeDeleteChatHistory,
  LeaveChat,
  encodeLeaveChat,
  ReportChat,
  encodeReportChat,
  SetChatNotificationSettings,
  encodeSetChatNotificationSettings,
  ChatNotificationSettings,
  UpdateChatNotificationSettings,
  ChatPermissions,
  UpdateChatPermissions,
  MessagePoll
} from '@tgx/core-td-api-generated';
import {
  FileRegistry,
  formatFullName,
  isChatMuted,
  canSendAnyMedia,
  ChatSendRights,
  sendRightsFromPermissions,
  MessageListState,
  MessageProjection,
  UserRegistry,
  withChatMuteFor
} from '@tgx/core-domain';
import { TdPendingRequest, TdRoutedEvent, TdUpdateFilter, TdUpdateSubscription, TdWireObject, TdWireValue } from '@tgx/td-gateway';
import { Subscription } from '@tgx/platform-ports';
import { Result } from '@tgx/core-common';
import { ReducerEnv, ReducerResult } from '@tgx/feature-template';
import { MessageItem, MessageSendState } from '../model/MessageItem';
import { ReactionChip } from '../model/ReactionChip';
import { MessageTextSpan } from '../model/MessageTextSpan';
import { MediaAttachment, decodeWaveform, encodeWaveform } from '../model/MediaAttachment';
import { LinkPreviewInfo } from '../model/LinkPreviewInfo';
import { ChatSearchResultItem } from '../model/ChatSearchResultItem';
import { PinnedMessageInfo } from '../model/PinnedMessageInfo';
import { parseFormattedText } from '../model/FormattedTextParser';
import { pollViewOf, PollView } from '../model/PollView';
import {
  ChatKind,
  chatKindOf,
  resolveSenderInfo,
  SenderInfo
} from '../model/SenderInfo';
import { ChatUiState, ComposerReplyMode } from '../contract/ChatUiState';
import {
  ChatIntent,
  LoadInitialMessages,
  LoadOlderMessages,
  OnMessagesLoaded,
  OnMessagesLoadFailed,
  OnMessageSendFailed,
  OnMessageActionMenuLoaded,
  OnMessageActionFailed,
  OnForwardCompleted,
  OnForwardFailed,
  OpenMediaViewer,
  RequestMediaDownload,
  PickAndSendPhoto,
  PickAndSendFile,
  PickAndSendVideo,
  ComposerTextChanged,
  CancelComposerMode,
  RestoreDraft,
  OnChatSearchLoaded,
  OnChatSearchFailed,
  OnJumpToMessageReady,
  OpenUserProfile,
  OnHeaderSubtitleChanged,
  OnChatKindChanged,
  OnChatMuteStateChanged,
  OpenChatProfile,
  ChatMenuAction,
  ConfirmMenuAction,
  OnPinnedMessageLoaded,
  OnChannelMemberStatusChanged,
  OnChatSendPermissionsChanged,
  OnStickerSetLoaded,
  OnStickerSetLoadFailed,
  OnStickerSetChanged,
  OnStickerSetActionFailed,
  OnStickerPreviewFileUpdated,
  StartVoiceRecord,
  StopAndSendVoiceRecord,
  CancelVoiceRecord,
  VoiceRecordTick,
  PlayVoiceNote,
  PauseVoiceNote,
  VoicePlaybackProgress,
  VoicePlaybackCompleted,
  VoicePlaybackFailed
} from '../contract/ChatIntent';
import {
  ChatEffect,
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
  SendPollEffect,
  SetPollAnswerEffect
} from '../contract/ChatEffect';
import { StickerSetPreviewState, StickerSetItem } from '../model/StickerSetPreviewState';
import { isOutgoingMessageRead, ReadReportThrottle } from '../model/ReadReceipt';
import { chatReducer } from '../reducer/ChatReducer';

const TAG: string = 'ChatCoordinator';
const INITIAL_PAGE_SIZE: number = 30;
const OLDER_PAGE_SIZE: number = 20;
/** 消息数低于该值且未到历史顶端时自动补拉。 */
const BACKFILL_THRESHOLD: number = 20;
/** 补拉延迟：给 TDLib 后台 preload 留时间窗（服务器往返 1-2s）。 */
const BACKFILL_DELAY_MS: number = 900;
/** SEARCH-102：单次聊天内搜索返回的最大命中条数（TDLib 上限 100）。 */
const CHAT_SEARCH_LIMIT: number = 30;
/** SEARCH-102：跳转定位时围绕目标消息拉取的上下半径。 */
const HISTORY_AROUND_RADIUS: number = 30;

export type ChatUiStateListener = (state: ChatUiState) => void;

/** 判定消息是否可作为相册聚合候选（同向、带有效 media_album_id 且为图片/视频/动图）。 */
export function isMediaAlbumCandidate(msg: Message): boolean {
  if (msg.media_album_id.length === 0 || msg.media_album_id === '0') {
    return false;
  }
  if (msg.content === null) {
    return false;
  }
  const t: string = msg.content.type;
  return t === 'messagePhoto' || t === 'messageVideo' || t === 'messageAnimation';
}

/** 气泡正文：文本消息取原文；多媒体/服务消息用占位标签（CHAT-002 后续替换为真实 renderer）。 */
export function messageContentText(content: TdMessageContent | null): string {
  if (content === null) {
    return '';
  }
  switch (content.type) {
    case 'messageText': {
      const text = (content as MessageText).text;
      return text !== null ? text.text : '';
    }
    case 'messagePhoto':
      return '[Photo]';
    case 'messageVideo':
      return '[Video]';
    case 'messageAnimation':
      return '[GIF]';
    case 'messageAudio':
      return '[Audio]';
    case 'messageVoiceNote':
      return '[Voice message]';
    case 'messageVideoNote':
      return '[Video message]';
    case 'messageDocument':
      return '[Document]';
    case 'messageSticker': {
      const stickerContent: MessageSticker = content as MessageSticker;
      if (stickerContent.sticker !== null && stickerContent.sticker.emoji.length > 0) {
        return `${stickerContent.sticker.emoji} Sticker`;
      }
      return 'Sticker';
    }
    case 'messageLocation':
    case 'messageLiveLocation':
      return '[Location]';
    case 'messageVenue':
      return '[Venue]';
    case 'messageContact':
      return '[Contact]';
    case 'messagePoll':
      return '[Poll]';
    case 'messageCall':
      return '[Call]';
    case 'messageGame':
      return '[Game]';
    case 'messageUnsupported':
      return '[Unsupported message]';
    default:
      return '';
  }
}

/** SEARCH-102：搜索结果日期。当天显示 HH:mm，跨天显示 dd.MM（对齐简化的会话内时间呈现）。 */
function formatSearchResultDate(unixSeconds: number): string {
  const date: Date = new Date(unixSeconds * 1000);
  const now: Date = new Date();
  const sameDay: boolean = date.getFullYear() === now.getFullYear() &&
    date.getMonth() === now.getMonth() &&
    date.getDate() === now.getDate();
  if (sameDay) {
    return `${pad2(date.getHours())}:${pad2(date.getMinutes())}`;
  }
  return `${pad2(date.getDate())}.${pad2(date.getMonth() + 1)}`;
}

function pad2(value: number): string {
  return value < 10 ? `0${value}` : `${value}`;
}

/** Message.sending_state → MessageItem.sendState（CHAT-003）。 */
export function messageSendStateOf(sendingState: TdMessageSendingState | null): MessageSendState {
  if (sendingState === null) {
    return 'none';
  }
  if (sendingState.type === 'messageSendingStatePending') {
    return 'pending';
  }
  if (sendingState.type === 'messageSendingStateFailed') {
    return 'failed';
  }
  return 'none';
}

/** Message.reply_to → 被回复消息 id（CHAT-004）；非回复/引用 story → null。 */
export function repliedMessageIdOf(replyTo: TdMessageReplyTo | null): number | null {
  if (replyTo === null || replyTo.type !== 'messageReplyToMessage') {
    return null;
  }
  const reply: MessageReplyToMessage = replyTo as MessageReplyToMessage;
  return reply.message_id > 0 ? reply.message_id : null;
}

/**
 * MSG-106：统计 forwardMessages 响应里真正转出的条数。
 * TDLib 按 message_ids 顺序逐条回 message 或 null（不可转发时为 null，
 * 例如受保护内容），所以只数非空项；不是数组/字段缺失按 0 处理。
 */
function countForwardedMessages(wire: TdWireObject): number {
  const raw: TdWireValue | undefined = wire['messages'];
  if (raw === undefined || raw === null || !Array.isArray(raw)) {
    return 0;
  }
  const items: TdWireValue[] = raw as TdWireValue[];
  let count: number = 0;
  for (let i = 0; i < items.length; i++) {
    if (items[i] !== null && items[i] !== undefined) {
      count += 1;
    }
  }
  return count;
}

export class ReplyInfo {
  readonly summary: string;
  readonly senderName: string;
  readonly senderColorIndex: number;
  readonly thumbnailPath: string | null;
  readonly isSticker: boolean;

  constructor(
    summary: string,
    senderName: string = '',
    senderColorIndex: number = -1,
    thumbnailPath: string | null = null,
    isSticker: boolean = false
  ) {
    this.summary = summary;
    this.senderName = senderName;
    this.senderColorIndex = senderColorIndex;
    this.thumbnailPath = thumbnailPath;
    this.isSticker = isSticker;
  }
}

export interface ChatCoordinatorOptions {
  readonly clipboardPort?: ClipboardPort;
  readonly toastPort?: ToastPort;
  readonly mediaPickerPort?: MediaPickerPort;
  readonly logger?: Logger;
  /** PROFILE-101：请求装配层打开指定用户的资料页（缺省 no-op）。 */
  readonly onOpenUserProfile?: (userId: number) => void;
  /** MSG-109：请求装配层打开会话资料页（缺省 no-op）。 */
  readonly onOpenChatProfile?: (chatId: number) => void;
  /** CHANNEL-101：请求装配层打开帖子评论列表页（缺省 no-op）。 */
  readonly onOpenComments?: (chatId: number, messageId: number) => void;
  /** VOICE-101：音频播放器抽象。 */
  readonly audioPlayerPort?: AudioPlayerPort;
  /** VOICE-101：音频录制器抽象。 */
  readonly audioRecorderPort?: AudioRecorderPort;
  /** VOICE-101：录音临时文件存放目录。 */
  readonly cacheDir?: string;
}

class ParsedDraft {
  readonly text: string;
  readonly replyToId: number;

  constructor(text: string, replyToId: number) {
    this.text = text;
    this.replyToId = replyToId;
  }
}

export class ChatCoordinator {
  private readonly projection: MessageProjection;
  private readonly scope: AccountScope;
  private readonly userRegistry: UserRegistry;
  private readonly fileRegistry: FileRegistry;
  private readonly env: ReducerEnv;
  private readonly clipboardPort: ClipboardPort;
  private readonly toastPort: ToastPort;
  private readonly mediaPickerPort: MediaPickerPort;
  private readonly audioPlayerPort: AudioPlayerPort;
  private readonly audioRecorderPort: AudioRecorderPort;
  private readonly cacheDir: string;
  private recordTimerId: number = -1;
  private recordingSeconds: number = 0;
  private readonly logger: Logger;
  private readonly onBack: () => void;
  /** MSG-106：请求装配层弹出转发目标会话选择器（缺省 no-op）。 */
  private readonly onOpenForwardPicker: (messageIds: number[]) => void;
  /** PROFILE-101：请求装配层打开用户资料页（缺省 no-op）。 */
  private readonly onOpenUserProfile: (userId: number) => void;
  /** MSG-109：请求装配层打开会话资料页（缺省 no-op）。 */
  private readonly onOpenChatProfile: (chatId: number) => void;
  /** CHANNEL-101：请求装配层打开帖子评论列表页（缺省 no-op）。 */
  private readonly onOpenComments: (chatId: number, messageId: number) => void;
  private currentState: ChatUiState;
  private readonly listeners: ChatUiStateListener[] = [];
  private syncScheduled: boolean = false;
  private throttledSyncScheduled: boolean = false;
  private backfillScheduled: boolean = false;
  private destroyed: boolean = false;
  /** MSG-102：会话种类（getChat 一次性解析，群聊才出署名）。 */
  private chatKind: ChatKind = 'unknown';
  private chatTypeRequested: boolean = false;
  /** MSG-109：超级群/频道 id（getChat 解析缓存，供头部成员数查询）。 */
  private supergroupId: number = 0;
  /** MSG-109：基本群 id（getChat 解析缓存，供头部成员数查询）。 */
  private basicGroupId: number = 0;
  /** PROF-ENTRY-001：私聊/密聊对方 user_id（getChat 解析，头部标题直达用户资料页）。 */
  private privatePeerUserId: number = 0;
  /**
   * SET-106：本会话当前通知设置（getChat 回读 + updateChatNotificationSettings 推送维护）。
   * 既是 ⋮ 菜单「静音/取消静音」的判定依据，也是写请求的底本——TDLib 的
   * chatNotificationSettings.sound_id 是 int64，缺省空串会被直接拒（bad_request）。
   */
  private chatNotificationSettings: ChatNotificationSettings | null = null;
  /** SET-106：updateChatNotificationSettings 订阅句柄（destroy 时退订）。 */
  private muteSubscription: TdUpdateSubscription | null = null;
  /** CHAN-SEND：updateChatPermissions 订阅句柄（destroy 时退订）。 */
  private permissionsSubscription: TdUpdateSubscription | null = null;
  /** MSG-109：getBasicGroup 是否已发起（防重；失败复位可重试）。 */
  private basicGroupInfoRequested: boolean = false;
  /** MSG-109：getSupergroupFullInfo 是否已发起（防重；失败复位可重试）。 */
  private supergroupInfoRequested: boolean = false;
  /** MSG-109：群/频道成员数缓存（0=未知）。 */
  private memberCount: number = 0;
  /** MSG-109：群在线人数缓存（updateChatOnlineMemberCount 推送；0=未知）。 */
  private onlineMemberCount: number = 0;
  /** MSG-109：updateChatOnlineMemberCount 订阅句柄（destroy 时退订）。 */
  private onlineCountSubscription: TdUpdateSubscription | null = null;
  /** MSG-109：私聊头部用户订阅句柄（destroy 时退订）。 */
  private headerUserSubscription: Subscription | null = null;
  /** MSG-109：私聊头部用户是否已发起 requestUser（防重）。 */
  private headerUserRequested: boolean = false;
  /** MSG-102：已发起过 getUser 的 sender，防重复请求。 */
  private readonly requestedSenderIds: Set<number> = new Set();
  private readonly senderSubscriptions: Map<number, Subscription> = new Map();
  /** MEDIA-101/105：文件下载更新订阅。 */
  private readonly fileSubscriptions: Map<number, Subscription> = new Map();
  /** 已下发过 downloadFile 的文件 id 集合，防重复请求风暴。 */
  private readonly requestedFileIds: Set<number> = new Set();
  /**
   * MEDIA-107：TDLib 明确回了错误的文件 id。下载失败原先只打日志，UI 静默退回
   * 下载按钮 —— 用户既不知道失败了，也没有区别于「首次下载」的重试入口。
   */
  private readonly failedFileIds: Set<number> = new Set();
  /**
   * MEDIA-105：待发送视频的**本地缩略图**缓存，key = 送进 TDLib 的视频沙箱物理路径。
   *
   * 为什么需要它：出站消息在服务端生成缩略图之前，回灌的 `messageVideo.video.thumbnail`
   * 一直是 null，气泡就会退化成「Video 组件首帧占位」而不是我们本地的缩略图。
   * 我们自己在适配器里抽了首帧，就顺手按视频路径记一份，让出站气泡**一上屏就有缩略图**。
   * TDLib 补上官方 thumbnail 后（`video.thumbnail` 非空）此缓存自动让位，不再参与渲染。
   */
  private readonly pendingVideoThumbnails: Map<string, string> = new Map();
  /** MSG-104：已读上报节流（lastReported 只增不减）。 */
  private readonly readThrottle: ReadReportThrottle = new ReadReportThrottle();
  /** 回复引用消息详情已发起过 getMessage 的 messageId 集合，防重复请求。 */
  private readonly requestedReplyIds: Set<number> = new Set();
  /** MSG-103：进入会话时的首条未读消息 id（锁定后会话内保持书签不消失，重进或无未读时为 null）。 */
  private firstUnreadMessageId: number | null = null;
  private initialUnreadResolved: boolean = false;
  /**
   * SEARCH-102：待定位的目标消息 id（0 = 无）。
   * 从全局搜索结果进会话时目标往往还没进缓存，而首屏加载在飞时投影会拒绝新的
   * 历史请求（loadHistoryAround 返回 null）——这里先把目标记下来，等投影空闲
   * （首屏/翻页完成）再拉围绕历史，避免"进会话后不定位"。
   */
  private pendingJumpMessageId: number = 0;
  /** 待定位目标的围绕历史是否已在飞，防止重复请求。 */
  private pendingJumpInFlight: boolean = false;

  constructor(
    scope: AccountScope,
    chatId: number,
    chatTitle: string,
    onBack?: () => void,
    onOpenForwardPicker?: (messageIds: number[]) => void,
    env?: ReducerEnv,
    options?: ChatCoordinatorOptions
  ) {
    this.projection = new MessageProjection(chatId, scope);
    this.scope = scope;
    // UserRegistry 构造即 start（订阅 updateUser/updateUserStatus），destroy 时 stop。
    this.userRegistry = new UserRegistry(scope);
    // FileRegistry 构造即 start（订阅 updateFile），destroy 时 stop。
    this.fileRegistry = new FileRegistry(scope);
    this.onBack = onBack !== undefined ? onBack : (): void => {};
    this.onOpenForwardPicker = onOpenForwardPicker !== undefined
      ? onOpenForwardPicker
      : (messageIds: number[]): void => {};
    this.onOpenUserProfile = (options !== undefined && options.onOpenUserProfile !== undefined)
      ? options.onOpenUserProfile
      : (userId: number): void => {};
    this.onOpenChatProfile = (options !== undefined && options.onOpenChatProfile !== undefined)
      ? options.onOpenChatProfile
      : (chatId: number): void => {};
    this.onOpenComments = (options !== undefined && options.onOpenComments !== undefined)
      ? options.onOpenComments
      : (chatId: number, messageId: number): void => {};
    this.env = env !== undefined ? env : {
      clock: new ManualClock(1000, 500),
      ids: new SequentialIdGenerator('chat-')
    };
    this.clipboardPort = (options !== undefined && options.clipboardPort !== undefined)
      ? options.clipboardPort
      : new FakeClipboard();
    this.toastPort = (options !== undefined && options.toastPort !== undefined)
      ? options.toastPort
      : new FakeToast();
    this.mediaPickerPort = (options !== undefined && options.mediaPickerPort !== undefined)
      ? options.mediaPickerPort
      : new FakeMediaPicker();
    this.audioPlayerPort = (options !== undefined && options.audioPlayerPort !== undefined)
      ? options.audioPlayerPort
      : new FakeAudioPlayer();
    this.audioRecorderPort = (options !== undefined && options.audioRecorderPort !== undefined)
      ? options.audioRecorderPort
      : new FakeAudioRecorder();
    this.cacheDir = (options !== undefined && options.cacheDir !== undefined && options.cacheDir.length > 0)
      ? options.cacheDir
      : '/data/storage/el2/base/cache';
    this.logger = (options !== undefined && options.logger !== undefined)
      ? options.logger
      : new Logger();
    this.currentState = new ChatUiState(chatId, chatTitle, [], false, true, null, '', null, null, -1, [], 0, 0, false, []);
  }

  get state(): ChatUiState {
    return this.currentState;
  }

  private extractDraft(draft: DraftMessage | null): ParsedDraft | null {
    if (draft === null) {
      return null;
    }
    let text: string = '';
    if (draft.content !== null && draft.content.type === 'draftMessageContentText') {
      const content = draft.content as DraftMessageContentText;
      if (content.text !== null && content.text.text.length > 0) {
        text = content.text.text;
      }
    }
    let replyToId: number = 0;
    if (draft.reply_to !== null && draft.reply_to !== undefined && draft.reply_to.type === 'inputMessageReplyToMessage') {
      replyToId = (draft.reply_to as InputMessageReplyToMessage).message_id;
    }
    if (text.length === 0 && replyToId === 0) {
      return null;
    }
    return new ParsedDraft(text, replyToId);
  }

  start(): void {
    this.projection.setOnDraftLoaded((draft: DraftMessage | null) => {
      if (!this.destroyed) {
        const parsed = this.extractDraft(draft);
        if (parsed !== null) {
          this.dispatch(new RestoreDraft(parsed.text, parsed.replyToId));
        }
      }
    });
    this.projection.setOnStateChanged(() => {
      this.scheduleSyncFromProjection();
    });
    this.projection.start();
    const parsed = this.extractDraft(this.projection.getInitialDraft());
    if (parsed !== null) {
      this.dispatch(new RestoreDraft(parsed.text, parsed.replyToId));
    }
    this.fetchChatKind();
    // SET-106：静音态实时同步（本端改、其它端改都会推 updateChatNotificationSettings）。
    this.subscribeChatNotificationSettings();
    // CHAN-SEND：发言权实时同步（管理员改权限会推 updateChatPermissions）。
    this.subscribeChatPermissions();
    // MSG-109：先按已知信息补一次副标题（chatKind 未回前为 no-op），
    // getChat 回包 / 用户状态订阅 / 在线人数订阅到达后各自重算。
    this.buildHeaderSubtitle();
    // MSG-108：加载会话置顶消息与监听动态变更
    this.projection.setOnPinnedMessageChanged((_messageId: number, _isPinned: boolean) => {
      this.fetchPinnedMessage();
    });
    this.fetchPinnedMessage();
    this.dispatch(new LoadInitialMessages());
  }

  /**
   * SEARCH-102：请求把视图定位到指定消息。两条入口共用：
   * - 装配层打开会话时传入路由里的目标（全局搜索结果 → 会话内定位）；
   * - 会话内搜索结果点击（经 JumpToSearchResult → JumpToMessage effect）。
   * 目标已缓存 → 直接回灌 OnJumpToMessageReady；未缓存 → 拉一段围绕它的历史，
   * 回包后目标进入投影再回灌；投影忙（首屏/翻页在飞）→ 记下目标，由
   * syncFromProjection 在空闲时推进。
   */
  public requestJumpToMessage(messageId: number): void {
    if (this.destroyed || messageId <= 0) {
      return;
    }
    this.pendingJumpMessageId = messageId;
    this.pendingJumpInFlight = false;
    this.tryResolvePendingJump();
  }

  /** 投影空闲时推进待跳转：已缓存直接 Ready；否则拉围绕历史（每次只拉一趟，避免死循环）。 */
  private tryResolvePendingJump(): void {
    const target: number = this.pendingJumpMessageId;
    if (this.destroyed || target <= 0) {
      return;
    }
    if (this.projection.getMessageById(target) !== undefined) {
      this.clearPendingJump();
      this.logger.info(TAG, 'jump_to_message_ok', `messageId=${target},cached=true`);
      this.dispatch(new OnJumpToMessageReady(target));
      return;
    }
    if (this.projection.state.isLoading || this.pendingJumpInFlight) {
      // 首屏/翻页/上一趟跳转在飞：等状态变更回调（syncFromProjection）再推进。
      return;
    }
    this.pendingJumpInFlight = true;
    this.logger.info(TAG, 'jump_to_message', `messageId=${target}`);
    const result: Result<TdPendingRequest, AppError> | null =
      this.projection.loadHistoryAround(target, HISTORY_AROUND_RADIUS);
    if (result === null) {
      this.pendingJumpInFlight = false;
      return;
    }
    if (result.err) {
      this.pendingJumpInFlight = false;
      this.clearPendingJump();
      this.logger.logError(TAG, result.error);
      return;
    }
    if (result.ok) {
      result.value.promise.then((res: Result<TdWireObject, AppError>) => {
        if (this.destroyed) {
          return;
        }
        this.pendingJumpInFlight = false;
        const reached: boolean = res.ok && this.projection.getMessageById(target) !== undefined;
        this.clearPendingJump();
        if (reached) {
          this.logger.info(TAG, 'jump_to_message_ok', `messageId=${target}`);
          this.dispatch(new OnJumpToMessageReady(target));
        } else {
          // 消息被删/不可达：放弃定位，不做无限重试。
          this.logger.info(TAG, 'jump_to_message_unreachable', `messageId=${target}`);
        }
      }).catch(() => {
        this.pendingJumpInFlight = false;
        this.clearPendingJump();
      });
    }
  }

  private clearPendingJump(): void {
    this.pendingJumpMessageId = 0;
    this.pendingJumpInFlight = false;
  }

  /** COMPOSER-101：立即保存当前输入栏中的草稿至 TDLib。 */
  public saveDraftNow(): void {    const text: string = this.currentState.composerText;
    let replyToMessageId: number = 0;
    if (this.currentState.composerMode !== null && this.currentState.composerMode.kind === 'reply') {
      replyToMessageId = (this.currentState.composerMode as ComposerReplyMode).targetMessageId;
    }
    if (text.trim().length > 0 || replyToMessageId > 0) {
      this.projection.setChatDraftMessage(text, replyToMessageId);
    } else {
      this.projection.clearChatDraftMessage();
    }
  }

  /**
   * SET-106 / MENU-101：静音/取消静音会话。
   * 以当前设置（getChat 回读或最近一次 updateChatNotificationSettings）为底本，
   * 只改 mute_for —— TDLib 的 sound_id/story_sound_id 是 int64，写空串会被
   * 直接判 bad_request（MENU-101 首版即因此静音从未能生效）。
   * 成功后的状态回灌走 updateChatNotificationSettings 订阅，不做乐观改写，
   * 避免本地标签与 TDLib 真值分叉。
   */
  private executeMuteChat(mute: boolean): void {
    const chatId: number = this.currentState.chatId;
    if (chatId === 0) {
      return;
    }
    const settings: ChatNotificationSettings = withChatMuteFor(this.chatNotificationSettings, mute);
    const req: SetChatNotificationSettings = new SetChatNotificationSettings();
    req.chat_id = chatId;
    req.notification_settings = settings;
    const result: Result<TdPendingRequest, AppError> =
      this.scope.request('setChatNotificationSettings', encodeSetChatNotificationSettings(req) as TdWireObject);
    if (result.err) {
      this.logger.logError(TAG, result.error);
      this.toastPort.showToast(mute ? '静音失败' : '取消静音失败');
      return;
    }
    if (result.ok) {
      result.value.promise.then((res: Result<TdWireObject, AppError>) => {
        if (!this.destroyed) {
          if (res.ok) {
            this.logger.info(TAG, 'chat_mute_applied', `chatId=${chatId},mute=${mute}`);
            this.toastPort.showToast(mute ? '已静音' : '已开启通知');
          }
          if (res.err) {
            this.logger.logError(TAG, res.error);
            this.toastPort.showToast(mute ? '静音失败' : '取消静音失败');
          }
        }
      }).catch(() => {});
    }
  }

  /** MENU-101：清空聊天历史（deleteChatHistory，remove_from_chat_list=true, revoke=true）。 */
  private executeClearHistory(): void {
    const chatId: number = this.currentState.chatId;
    if (chatId === 0) {
      return;
    }
    const req: DeleteChatHistory = new DeleteChatHistory();
    req.chat_id = chatId;
    req.remove_from_chat_list = true;
    req.revoke = true;
    const result: Result<TdPendingRequest, AppError> =
      this.scope.request('deleteChatHistory', encodeDeleteChatHistory(req) as TdWireObject);
    if (result.err) {
      this.logger.logError(TAG, result.error);
      this.toastPort.showToast('清空历史失败');
      return;
    }
    if (result.ok) {
      result.value.promise.then((res: Result<TdWireObject, AppError>) => {
        if (!this.destroyed) {
          if (res.ok) {
            this.toastPort.showToast('已清空聊天历史');
            this.onBack();
          }
          if (res.err) {
            this.logger.logError(TAG, res.error);
            this.toastPort.showToast('清空历史失败');
          }
        }
      });
    }
  }

  /** MENU-101：删除聊天（deleteChat，成功后返回会话列表）。 */
  private executeDeleteChat(): void {
    const chatId: number = this.currentState.chatId;
    if (chatId === 0) {
      return;
    }
    const req: DeleteChat = new DeleteChat();
    req.chat_id = chatId;
    const result: Result<TdPendingRequest, AppError> =
      this.scope.request('deleteChat', encodeDeleteChat(req) as TdWireObject);
    if (result.err) {
      this.logger.logError(TAG, result.error);
      this.toastPort.showToast('删除聊天失败');
      return;
    }
    if (result.ok) {
      result.value.promise.then((res: Result<TdWireObject, AppError>) => {
        if (!this.destroyed) {
          if (res.ok) {
            this.toastPort.showToast('已删除聊天');
            this.onBack();
          }
          if (res.err) {
            this.logger.logError(TAG, res.error);
            this.toastPort.showToast('删除聊天失败');
          }
        }
      });
    }
  }

  /** MENU-101：举报聊天（reportChat，option_id=spam 通用垃圾举报）。 */
  private executeReportChat(): void {
    const chatId: number = this.currentState.chatId;
    if (chatId === 0) {
      return;
    }
    const req: ReportChat = new ReportChat();
    req.chat_id = chatId;
    req.option_id = 'spam';
    req.message_ids = [];
    req.text = '';
    const result: Result<TdPendingRequest, AppError> =
      this.scope.request('reportChat', encodeReportChat(req) as TdWireObject);
    if (result.err) {
      this.logger.logError(TAG, result.error);
      this.toastPort.showToast('举报失败');
      return;
    }
    if (result.ok) {
      result.value.promise.then((res: Result<TdWireObject, AppError>) => {
        if (!this.destroyed) {
          if (res.ok) {
            this.toastPort.showToast('已举报');
          }
          if (res.err) {
            this.logger.logError(TAG, res.error);
            this.toastPort.showToast('举报失败');
          }
        }
      });
    }
  }

  /** MENU-101：退出群组/频道（leaveChat，成功后返回会话列表）。 */
  private executeLeaveChat(): void {
    const chatId: number = this.currentState.chatId;
    if (chatId === 0) {
      return;
    }
    const req: LeaveChat = new LeaveChat();
    req.chat_id = chatId;
    const result: Result<TdPendingRequest, AppError> =
      this.scope.request('leaveChat', encodeLeaveChat(req) as TdWireObject);
    if (result.err) {
      this.logger.logError(TAG, result.error);
      this.toastPort.showToast('退出失败');
      return;
    }
    if (result.ok) {
      result.value.promise.then((res: Result<TdWireObject, AppError>) => {
        if (!this.destroyed) {
          if (res.ok) {
            this.toastPort.showToast('已退出');
            this.onBack();
          }
          if (res.err) {
            this.logger.logError(TAG, res.error);
            this.toastPort.showToast('退出失败');
          }
        }
      });
    }
  }

  destroy(): void {
    this.destroyed = true;
    this.saveDraftNow();
    this.projection.setOnDraftLoaded(null);
    this.projection.setOnStateChanged(null);
    this.projection.stop();
    this.senderSubscriptions.forEach((sub: Subscription) => {
      sub.unsubscribe();
    });
    this.senderSubscriptions.clear();
    this.requestedSenderIds.clear();
    this.fileSubscriptions.forEach((sub: Subscription) => {
      sub.unsubscribe();
    });
    this.fileSubscriptions.clear();
    this.requestedFileIds.clear();
    this.failedFileIds.clear();
    // MSG-109：退订头部新增的在线人数/私聊用户订阅。
    if (this.onlineCountSubscription !== null) {
      this.onlineCountSubscription.unsubscribe();
      this.onlineCountSubscription = null;
    }
    if (this.headerUserSubscription !== null) {
      this.headerUserSubscription.unsubscribe();
      this.headerUserSubscription = null;
    }
    // SET-106：退订会话静音推送。
    if (this.muteSubscription !== null) {
      this.muteSubscription.unsubscribe();
      this.muteSubscription = null;
    }
    // CHAN-SEND：退订会话权限推送。
    if (this.permissionsSubscription !== null) {
      this.permissionsSubscription.unsubscribe();
      this.permissionsSubscription = null;
    }
    if (this.recordTimerId !== -1) {
      clearInterval(this.recordTimerId);
      this.recordTimerId = -1;
    }
    this.audioRecorderPort.cancelRecord().catch(() => {});
    this.audioPlayerPort.stop().catch(() => {});
    this.fileRegistry.stop();
    this.userRegistry.stop();
    this.listeners.length = 0;
  }

  subscribe(listener: ChatUiStateListener): () => void {
    this.listeners.push(listener);
    listener(this.currentState);
    return () => {
      const idx: number = this.listeners.indexOf(listener);
      if (idx >= 0) {
        this.listeners.splice(idx, 1);
      }
    };
  }

  dispatch(intent: ChatIntent): void {
    if (intent.kind === 'openMediaViewer') {
      const openIntent: OpenMediaViewer = intent as OpenMediaViewer;
      this.handleOpenMediaViewer(openIntent.messageId, openIntent.targetFileId);
    } else if (intent.kind === 'requestMediaDownload') {
      const reqIntent: RequestMediaDownload = intent as RequestMediaDownload;
      this.logger.info(TAG, 'request_media_download',
        `fileId=${reqIntent.fileId},downloaded=${this.fileRegistry.isDownloaded(reqIntent.fileId)}`);
      this.requestMediaDownload(reqIntent.fileId, 32);
    } else if (intent.kind === 'openUserProfile') {
      // PROFILE-101：纯导航意图——reducer 原样透传（default 分支），这里转给装配层路由。
      const profileIntent: OpenUserProfile = intent as OpenUserProfile;
      if (profileIntent.userId > 0) {
        this.logger.info(TAG, 'open_user_profile', `userId=${profileIntent.userId}`);
        this.onOpenUserProfile(profileIntent.userId);
      }
    } else if (intent.kind === 'openChatProfile') {
      // MSG-109：纯导航意图——reducer 原样透传（default 分支），这里转给装配层路由。
      // 修复（DSH 集成验收）：群/频道 chatId 为负数（超级群 -100xxx），>0 守卫会让
      // 群/频道标题点不动；合法条件是"非 0"。
      const chatProfileIntent: OpenChatProfile = intent as OpenChatProfile;
      if (chatProfileIntent.chatId !== 0) {
        // PROF-ENTRY-001：私聊没有「群资料页」可去，头部标题直达对方用户资料页。
        // 取 getChat 回包里的 type_.user_id 而不是拿 chatId 顶替——密聊 chatId ≠ user_id。
        if (this.privatePeerUserId > 0) {
          this.logger.info(TAG, 'open_user_profile_from_private_header',
            `chatId=${chatProfileIntent.chatId},userId=${this.privatePeerUserId}`);
          this.onOpenUserProfile(this.privatePeerUserId);
        } else {
          this.logger.info(TAG, 'open_chat_profile', `chatId=${chatProfileIntent.chatId}`);
          this.onOpenChatProfile(chatProfileIntent.chatId);
        }
      }
    } else if (intent.kind === 'chatMenuAction') {
      // MENU-101：⋮ 菜单动作实化——非破坏性动作直接调用 TDLib，
      // 破坏性动作由 reducer 弹出确认弹窗，用户确认后走 confirmMenuAction。
      const menuIntent: ChatMenuAction = intent as ChatMenuAction;
      this.logger.info(TAG, `chat_menu_${menuIntent.action}`);
      if (menuIntent.action === 'mute') {
        this.executeMuteChat(true);
      } else if (menuIntent.action === 'enable_notifications') {
        this.executeMuteChat(false);
      }
    } else if (intent.kind === 'confirmMenuAction') {
      // MENU-101：用户确认破坏性操作 → 执行 pendingMenuAction 对应的 TDLib 调用。
      const pendingAction: string = this.currentState.pendingMenuAction;
      this.logger.info(TAG, `confirm_menu_action_${pendingAction}`);
      if (pendingAction === 'clear_history') {
        this.executeClearHistory();
      } else if (pendingAction === 'delete_chat') {
        this.executeDeleteChat();
      } else if (pendingAction === 'report') {
        this.executeReportChat();
      } else if (pendingAction === 'leave') {
        this.executeLeaveChat();
      }
    }

    const result: ReducerResult<ChatUiState, ChatEffect> = chatReducer(
      this.currentState,
      intent,
      this.env
    );

    const stateChanged: boolean = result.state !== this.currentState;
    this.currentState = result.state;

    if (stateChanged) {
      for (let i = 0; i < this.listeners.length; i++) {
        this.listeners[i](this.currentState);
      }
    }

    if (result.effects.length > 0) {
      for (let i = 0; i < result.effects.length; i++) {
        this.executeEffect(result.effects[i]);
      }
    }
  }

  private handleOpenMediaViewer(messageId: number, targetFileId?: number): void {
    for (let i = 0; i < this.currentState.messages.length; i++) {
      const item: MessageItem = this.currentState.messages[i];
      if (item.messageId === messageId) {
        if (item.albumItems.length > 0) {
          for (let j = 0; j < item.albumItems.length; j++) {
            const m: MediaAttachment = item.albumItems[j];
            if (!m.isDownloaded && (targetFileId === undefined || m.fileId === targetFileId)) {
              this.requestMediaDownload(m.fileId, 32);
            }
          }
        } else if (item.media !== null && !item.media.isDownloaded) {
          this.requestMediaDownload(item.media.fileId, 32);
        }
        break;
      }
    }
  }

  private scheduleThrottledSync(): void {
    if (this.throttledSyncScheduled || this.destroyed) {
      return;
    }
    this.throttledSyncScheduled = true;
    setTimeout(() => {
      this.throttledSyncScheduled = false;
      if (!this.destroyed) {
        this.scheduleSyncFromProjection();
      }
    }, 200);
  }

  private scheduleSyncFromProjection(): void {
    if (this.syncScheduled || this.destroyed) {
      return;
    }
    this.syncScheduled = true;
    setTimeout(() => {
      this.syncScheduled = false;
      if (!this.destroyed) {
        this.syncFromProjection();
      }
    }, 0);
  }

  private syncFromProjection(): void {
    const projectionState: MessageListState = this.projection.state;
    // 回复引用查找表：解析被回复消息的 sender、正文摘要与缩略图
    const replyInfoById: Map<number, ReplyInfo> = new Map();
    for (let i = 0; i < projectionState.messages.length; i++) {
      const message: Message = projectionState.messages[i];
      replyInfoById.set(message.id, this.resolveReplyInfo(message));
    }
    // MSG-103：未读消息书签定位（对齐 Telegram X MessagesAdapter.java:528 与 canGoUnread 规则）
    if (!this.initialUnreadResolved) {
      if (projectionState.unreadCount > 0 && projectionState.lastReadInboxMessageId > 0) {
        for (let i = 0; i < projectionState.messages.length; i++) {
          const m: Message = projectionState.messages[i];
          if (!m.is_outgoing && m.id > projectionState.lastReadInboxMessageId) {
            this.firstUnreadMessageId = m.id;
            this.initialUnreadResolved = true;
            break;
          }
        }
      } else if (!projectionState.isLoading && projectionState.messages.length > 0) {
        // 首屏已加载完成且未读数为 0 或无已读水位，锁定本会话无未读分隔线
        this.initialUnreadResolved = true;
      }
    }

    const items: MessageItem[] = [];
    let i = 0;
    while (i < projectionState.messages.length) {
      const currentMsg: Message = projectionState.messages[i];
      const isCandidate: boolean = isMediaAlbumCandidate(currentMsg);

      let albumEnd: number = i + 1;
      if (isCandidate) {
        while (
          albumEnd < projectionState.messages.length &&
          isMediaAlbumCandidate(projectionState.messages[albumEnd]) &&
          projectionState.messages[albumEnd].media_album_id === currentMsg.media_album_id &&
          projectionState.messages[albumEnd].is_outgoing === currentMsg.is_outgoing
        ) {
          albumEnd++;
        }
      }

      const isAlbum: boolean = isCandidate && (albumEnd - i >= 2);

      let showDateHeader: boolean = false;
      let dateHeaderText: string = '';
      if (i === 0) {
        showDateHeader = true;
        dateHeaderText = formatDateHeader(currentMsg.date * 1000);
      } else {
        const prevMsg: Message = projectionState.messages[i - 1];
        if (!isSameDay(prevMsg.date * 1000, currentMsg.date * 1000)) {
          showDateHeader = true;
          dateHeaderText = formatDateHeader(currentMsg.date * 1000);
        }
      }

      let showUnreadSeparator: boolean = false;
      if (this.firstUnreadMessageId !== null) {
        if (isAlbum) {
          for (let k = i; k < albumEnd; k++) {
            if (projectionState.messages[k].id === this.firstUnreadMessageId) {
              showUnreadSeparator = true;
              break;
            }
          }
        } else {
          showUnreadSeparator = (currentMsg.id === this.firstUnreadMessageId);
        }
      }

      if (isAlbum) {
        const albumMessages: Message[] = [];
        for (let k = i; k < albumEnd; k++) {
          albumMessages.push(projectionState.messages[k]);
        }
        items.push(this.mapAlbumToItem(
          albumMessages,
          replyInfoById,
          projectionState.lastReadOutboxMessageId,
          showDateHeader,
          dateHeaderText,
          showUnreadSeparator
        ));
        i = albumEnd;
      } else {
        items.push(this.mapMessageToItem(
          currentMsg,
          replyInfoById,
          projectionState.lastReadOutboxMessageId,
          showDateHeader,
          dateHeaderText,
          showUnreadSeparator
        ));
        i++;
      }
    }
    this.dispatch(new OnMessagesLoaded(
      items,
      projectionState.hasMoreOlder,
      projectionState.lastReadInboxMessageId,
      projectionState.unreadCount
    ));
    this.maybeBackfillOlder(projectionState);
    // MSG-104：投影有新内容（含首屏完成、新消息到达）时直接上报最新 incoming
    // 已读。MVP 简化：聊天页开着即视为入屏（列表自动跟随到底时成立），
    // 精确可视范围由 onScrollIndex → OnVisibleRangeChanged 路径补充。
    this.reportReadUpTo(items, items.length - 1);
    // SEARCH-102：投影刚推进过（首屏完成/历史回填），此时才可能在空闲状态下
    // 推进"进会话定位"的待跳转目标。
    this.tryResolvePendingJump();
  }

  /** MSG-104：节流后向 TDLib 发 viewMessages；失败只记日志，不打扰 UI。 */
  private reportReadUpTo(items: readonly MessageItem[], lastVisibleIndex: number): void {
    const target: number = this.readThrottle.poll(items, lastVisibleIndex);
    if (target <= 0 || this.destroyed) {
      return;
    }
    const unreadIds: number[] = [];
    const limitIndex: number = Math.min(lastVisibleIndex, items.length - 1);
    for (let i = 0; i <= limitIndex; i++) {
      const it: MessageItem = items[i];
      if (!it.isOutgoing && it.messageId <= target) {
        if (it.albumMessageIds.length > 0) {
          for (let j = 0; j < it.albumMessageIds.length; j++) {
            unreadIds.push(it.albumMessageIds[j]);
          }
        } else {
          unreadIds.push(it.messageId);
        }
      }
    }
    if (unreadIds.length === 0) {
      unreadIds.push(target);
    }
    this.sendReadReport(unreadIds);
  }

  private sendReadReport(messageIds: number[]): void {
    const result: Result<TdPendingRequest, AppError> = this.projection.markMessagesRead(messageIds);
    if (result.err) {
      this.logger.logError(TAG, result.error);
      return;
    }
    if (result.ok) {
      result.value.promise.then((res: Result<TdWireObject, AppError>) => {
        if (res.err) {
          this.logger.logError(TAG, res.error);
        }
      }).catch(() => {
      });
    }
  }

  /**
   * 首屏/翻页后消息仍不足一屏 → 延迟补拉一页更早历史。
   * TDLib getChatHistory 首屏常只回内存中已有的末条消息（后台异步 preload
   * 更旧历史），需要再次请求才能拿到 preload 结果；投影侧以空页/全重复判顶，
   * 消息真实不足一屏的会话多拉一两页后自然终止。延迟给 preload 留时间窗。
   */
  private maybeBackfillOlder(state: MessageListState): void {
    if (this.destroyed || state.isLoading || !state.hasMoreOlder) {
      return;
    }
    if (state.messages.length === 0 || state.messages.length >= BACKFILL_THRESHOLD) {
      return;
    }
    if (this.backfillScheduled) {
      return;
    }
    this.backfillScheduled = true;
    setTimeout(() => {
      this.backfillScheduled = false;
      if (!this.destroyed && this.currentState.hasMoreOlder && !this.currentState.isLoading) {
        this.dispatch(new LoadOlderMessages());
      }
    }, BACKFILL_DELAY_MS);
  }

  public requestMediaDownload(fileId: number, priority: number = 1): void {
    if (this.destroyed || fileId <= 0) {
      return;
    }
    if (this.fileRegistry.isDownloaded(fileId)) {
      return;
    }
    // 用户再次点下载即视为重试：先撤掉失败标，失败态才能退出。
    this.failedFileIds.delete(fileId);
    if (this.requestedFileIds.has(fileId)) {
      this.logger.info(TAG, 'media_download_skip_requested', `fileId=${fileId}`);
      return;
    }
    this.requestedFileIds.add(fileId);

    if (!this.fileSubscriptions.has(fileId)) {
      const sub: Subscription = this.fileRegistry.subscribeFile(fileId, (file: File) => {
        if (!this.destroyed) {
          if (file.local !== null && file.local.is_downloading_completed) {
            this.logger.info(TAG, 'media_download_completed', `fileId=${fileId}`);
            this.requestedFileIds.delete(fileId);
            this.failedFileIds.delete(fileId);
            this.scheduleSyncFromProjection();
            if (file.local.path.length > 0) {
              this.dispatch(new OnStickerPreviewFileUpdated(fileId, file.local.path));
            }
          } else {
            // SET-104：TDLib 停止下载（清理缓存把文件重置 / 下载失败）时释放去重闩，
            // 否则同一次会话内该 fileId 永远无法再次发起下载。下载中保持闩住，避免
            // 投影每帧重复请求。
            if (file.local === null || !file.local.is_downloading_active) {
              this.requestedFileIds.delete(fileId);
            }
            this.scheduleThrottledSync();
          }
        }
      });
      this.fileSubscriptions.set(fileId, sub);
    }
    const result: Result<TdPendingRequest, AppError> = this.fileRegistry.downloadFile(fileId, priority);
    if (result.err) {
      this.markFileDownloadFailed(fileId, result.error);
      return;
    }
    if (result.ok) {
      result.value.promise.then((res: Result<TdWireObject, AppError>) => {
        if (this.destroyed) {
          return;
        }
        // TDLib 对 downloadFile 的错误回包（网络不可用 / 文件不可得）是唯一的失败信号，
        // updateFile 只会把 is_downloading_active 置回 false，不带原因。
        if (res.err) {
          this.markFileDownloadFailed(fileId, res.error);
        }
      }).catch(() => {});
    }
  }

  /** MEDIA-107：记下下载失败并放行去重闩，让重试按钮能立刻再发起。 */
  private markFileDownloadFailed(fileId: number, error: AppError): void {
    this.logger.logError(TAG, error);
    this.logger.info(TAG, 'media_download_failed', `fileId=${fileId},kind=${error.kind}`);
    this.failedFileIds.add(fileId);
    this.requestedFileIds.delete(fileId);
    this.scheduleThrottledSync();
  }

  private chooseDisplaySize(sizes: PhotoSize[]): PhotoSize {
    if (sizes.length === 0) {
      return new PhotoSize();
    }
    for (let i = 0; i < sizes.length; i++) {
      const s: PhotoSize = sizes[i];
      if (s.width >= 320 && s.width <= 960) {
        return s;
      }
    }
    if (sizes.length > 2) {
      return sizes[sizes.length - 2];
    }
    return sizes[sizes.length - 1];
  }

  private resolveMediaAttachment(message: Message): MediaAttachment | null {
    if (message.content === null) {
      return null;
    }

    if (message.content.type === 'messagePhoto') {
      const photoContent: MessagePhoto = message.content as MessagePhoto;
      if (photoContent.photo === null || photoContent.photo.sizes.length === 0) {
        return null;
      }
      const sizes: PhotoSize[] = photoContent.photo.sizes;
      const displaySize: PhotoSize = this.chooseDisplaySize(sizes);
      const thumbSize: PhotoSize = sizes[0];
      const targetFile: File | null = displaySize.photo;
      if (targetFile === null) {
        return null;
      }

      const fileId: number = targetFile.id;
      const localPath: string | null = this.fileRegistry.getLocalPath(fileId, targetFile);
      const isDownloaded: boolean = this.fileRegistry.isDownloaded(fileId, targetFile);
      const progress: number = this.fileRegistry.getDownloadProgress(fileId);
      const latestFile: File | null = this.fileRegistry.getFile(fileId);
      const isDownloading: boolean = latestFile !== null && latestFile.local !== null
        ? latestFile.local.is_downloading_active
        : (targetFile.local !== null ? targetFile.local.is_downloading_active : false);

      let thumbPath: string | null = null;
      if (thumbSize.photo !== null) {
        thumbPath = this.fileRegistry.getLocalPath(thumbSize.photo.id);
        if (thumbPath === null && thumbSize.photo.id !== fileId) {
          this.requestMediaDownload(thumbSize.photo.id, 2);
        }
      }

      const isUploading: boolean = this.fileRegistry.isUploading(fileId) ||
        (message.is_outgoing && message.sending_state !== null && message.sending_state.type === 'messageSendingStatePending');
      const uploadProgress: number = this.fileRegistry.getUploadProgress(fileId);

      if (isUploading && !this.fileSubscriptions.has(fileId)) {
        const sub: Subscription = this.fileRegistry.subscribeFile(fileId, (file: File) => {
          if (!this.destroyed) {
            if (file.remote !== null && file.remote.is_uploading_completed) {
              this.scheduleSyncFromProjection();
            } else {
              this.scheduleThrottledSync();
            }
          }
        });
        this.fileSubscriptions.set(fileId, sub);
      }

      if (!isDownloaded && !isDownloading && !isUploading) {
        this.requestMediaDownload(fileId, 1);
      }

      const captionText: string = photoContent.caption !== null ? photoContent.caption.text : '';
      const captionSpans: MessageTextSpan[] = photoContent.caption !== null ? parseFormattedText(photoContent.caption) : [];

      return new MediaAttachment(
        'photo',
        fileId,
        localPath,
        thumbPath,
        displaySize.width,
        displaySize.height,
        0,
        isDownloading,
        isDownloaded,
        progress,
        captionText,
        captionSpans,
        photoContent.has_spoiler,
        isUploading,
        uploadProgress
      );
    }

    if (message.content.type === 'messageAnimation') {
      const animContent: MessageAnimation = message.content as MessageAnimation;
      if (animContent.animation === null) {
        return null;
      }
      const anim: Animation = animContent.animation;
      const targetFile: File | null = anim.animation;
      if (targetFile === null) {
        return null;
      }

      const fileId: number = targetFile.id;
      const localPath: string | null = this.fileRegistry.getLocalPath(fileId, targetFile);
      const isDownloaded: boolean = this.fileRegistry.isDownloaded(fileId, targetFile);
      const progress: number = this.fileRegistry.getDownloadProgress(fileId);
      const latestFile: File | null = this.fileRegistry.getFile(fileId);
      const isDownloading: boolean = latestFile !== null && latestFile.local !== null
        ? latestFile.local.is_downloading_active
        : (targetFile.local !== null ? targetFile.local.is_downloading_active : false);

      let thumbPath: string | null = null;
      if (anim.thumbnail !== null && anim.thumbnail.file !== null) {
        thumbPath = this.fileRegistry.getLocalPath(anim.thumbnail.file.id);
        if (thumbPath === null) {
          this.requestMediaDownload(anim.thumbnail.file.id, 2);
        }
      }

      if (!isDownloaded && !isDownloading) {
        this.requestMediaDownload(fileId, 1);
      }

      const captionText: string = animContent.caption !== null ? animContent.caption.text : '';
      const captionSpans: MessageTextSpan[] = animContent.caption !== null ? parseFormattedText(animContent.caption) : [];

      return new MediaAttachment(
        'animation',
        fileId,
        localPath,
        thumbPath,
        anim.width,
        anim.height,
        anim.duration,
        isDownloading,
        isDownloaded,
        progress,
        captionText,
        captionSpans,
        animContent.has_spoiler
      );
    }

    if (message.content.type === 'messageVideo') {
      const videoContent: MessageVideo = message.content as MessageVideo;
      if (videoContent.video === null) {
        return null;
      }
      const video: Video = videoContent.video;
      const targetFile: File | null = video.video;
      if (targetFile === null) {
        return null;
      }

      const fileId: number = targetFile.id;
      let localPath: string | null = this.fileRegistry.getLocalPath(fileId, targetFile);
      // 出站视频：TDLib 回灌的本地路径即我们自己送进去的沙箱文件，
      // 注册表尚未收录时直接取 file.local.path，保证气泡立刻有本地源可渲染。
      if (localPath === null && targetFile.local !== null && targetFile.local.path.length > 0) {
        localPath = targetFile.local.path;
      }
      const isDownloaded: boolean = this.fileRegistry.isDownloaded(fileId, targetFile);
      const progress: number = this.fileRegistry.getDownloadProgress(fileId);
      const latestFile: File | null = this.fileRegistry.getFile(fileId);
      const isDownloading: boolean = latestFile !== null && latestFile.local !== null
        ? latestFile.local.is_downloading_active
        : (targetFile.local !== null ? targetFile.local.is_downloading_active : false);

      let thumbPath: string | null = null;
      if (video.thumbnail !== null && video.thumbnail.file !== null) {
        thumbPath = this.fileRegistry.getLocalPath(video.thumbnail.file.id);
        if (thumbPath === null) {
          this.requestMediaDownload(video.thumbnail.file.id, 2);
        }
      }
      // MEDIA-105 出站兜底：服务端缩略图尚未就绪时，用发送前本地抽的首帧顶上，
      // 让「视频缩略图先展示」在发送侧也成立。
      if (thumbPath === null && localPath !== null) {
        const localThumb: string | undefined = this.pendingVideoThumbnails.get(localPath);
        if (localThumb !== undefined) {
          thumbPath = localThumb;
        }
      }

      // MEDIA-105：上传态（此前视频分支漏了这一对，导致出站视频没有进度圈/取消钮）。
      const isUploading: boolean = this.fileRegistry.isUploading(fileId) ||
        (message.is_outgoing && message.sending_state !== null && message.sending_state.type === 'messageSendingStatePending');
      const uploadProgress: number = this.fileRegistry.getUploadProgress(fileId);
      if (isUploading && !this.fileSubscriptions.has(fileId)) {
        const sub: Subscription = this.fileRegistry.subscribeFile(fileId, (file: File) => {
          if (!this.destroyed) {
            if (file.remote !== null && file.remote.is_uploading_completed) {
              // 上传完成：服务端缩略图即将就绪，本地兜底图可以退场。
              if (localPath !== null) {
                this.pendingVideoThumbnails.delete(localPath);
              }
              this.scheduleSyncFromProjection();
            } else {
              this.scheduleThrottledSync();
            }
          }
        });
        this.fileSubscriptions.set(fileId, sub);
      }

      // 视频较小（<= 10MB）自动下载，便于直接播放
      const videoSize: number = targetFile.size;
      if (!isDownloaded && !isDownloading && !isUploading && videoSize > 0 && videoSize <= 10 * 1024 * 1024) {
        this.requestMediaDownload(fileId, 1);
      }

      const captionText: string = videoContent.caption !== null ? videoContent.caption.text : '';
      const captionSpans: MessageTextSpan[] = videoContent.caption !== null ? parseFormattedText(videoContent.caption) : [];

      return new MediaAttachment(
        'video',
        fileId,
        localPath,
        thumbPath,
        video.width,
        video.height,
        video.duration,
        isDownloading,
        isDownloaded,
        progress,
        captionText,
        captionSpans,
        videoContent.has_spoiler,
        isUploading,
        uploadProgress
      ).withDownloadFailed(this.failedFileIds.has(fileId));
    }

    if (message.content.type === 'messageVideoNote') {
      const noteContent: MessageVideoNote = message.content as MessageVideoNote;
      if (noteContent.video_note === null) {
        return null;
      }
      const note: VideoNote = noteContent.video_note;
      const targetFile: File | null = note.video;
      if (targetFile === null) {
        return null;
      }

      const fileId: number = targetFile.id;
      const localPath: string | null = this.fileRegistry.getLocalPath(fileId, targetFile);
      const isDownloaded: boolean = this.fileRegistry.isDownloaded(fileId, targetFile);
      const progress: number = this.fileRegistry.getDownloadProgress(fileId);
      const latestFile: File | null = this.fileRegistry.getFile(fileId);
      const isDownloading: boolean = latestFile !== null && latestFile.local !== null
        ? latestFile.local.is_downloading_active
        : (targetFile.local !== null ? targetFile.local.is_downloading_active : false);

      let thumbPath: string | null = null;
      if (note.thumbnail !== null && note.thumbnail.file !== null) {
        thumbPath = this.fileRegistry.getLocalPath(note.thumbnail.file.id);
        if (thumbPath === null) {
          this.requestMediaDownload(note.thumbnail.file.id, 2);
        }
      }

      if (!isDownloaded && !isDownloading) {
        this.requestMediaDownload(fileId, 1);
      }

      return new MediaAttachment(
        'videoNote',
        fileId,
        localPath,
        thumbPath,
        note.length > 0 ? note.length : 240,
        note.length > 0 ? note.length : 240,
        note.duration,
        isDownloading,
        isDownloaded,
        progress,
        '',
        [],
        false
      );
    }

    if (message.content.type === 'messageSticker') {
      const stickerContent: MessageSticker = message.content as MessageSticker;
      if (stickerContent.sticker === null) {
        return null;
      }
      const sticker: Sticker = stickerContent.sticker;
      const targetFile: File | null = sticker.sticker;
      if (targetFile === null) {
        return null;
      }

      const fileId: number = targetFile.id;
      const localPath: string | null = this.fileRegistry.getLocalPath(fileId, targetFile);
      const isDownloaded: boolean = this.fileRegistry.isDownloaded(fileId, targetFile);
      const progress: number = this.fileRegistry.getDownloadProgress(fileId);
      const latestFile: File | null = this.fileRegistry.getFile(fileId);
      const isDownloading: boolean = latestFile !== null && latestFile.local !== null
        ? latestFile.local.is_downloading_active
        : (targetFile.local !== null ? targetFile.local.is_downloading_active : false);

      let thumbPath: string | null = null;
      if (sticker.thumbnail !== null && sticker.thumbnail.file !== null) {
        thumbPath = this.fileRegistry.getLocalPath(sticker.thumbnail.file.id);
        if (thumbPath === null) {
          this.requestMediaDownload(sticker.thumbnail.file.id, 2);
        }
      }

      if (!isDownloaded && !isDownloading) {
        this.requestMediaDownload(fileId, 16);
      }

      return new MediaAttachment(
        'sticker',
        fileId,
        localPath,
        thumbPath,
        sticker.width,
        sticker.height,
        0,
        isDownloading,
        isDownloaded,
        progress,
        sticker.emoji,
        [],
        false,
        false,
        0,
        '',
        0,
        '',
        [],
        '',
        '',
        false,
        sticker.set_id
      );
    }

    if (message.content.type === 'messageDocument') {
      const docMsg: MessageDocument = message.content as MessageDocument;
      if (docMsg.document === null) {
        return null;
      }
      const doc: Document = docMsg.document;
      const targetFile: File | null = doc.document;
      if (targetFile === null) {
        return null;
      }

      const fileId: number = targetFile.id;
      const localPath: string | null = this.fileRegistry.getLocalPath(fileId, targetFile);
      const isDownloaded: boolean = this.fileRegistry.isDownloaded(fileId, targetFile);
      const progress: number = this.fileRegistry.getDownloadProgress(fileId);
      const latestFile: File | null = this.fileRegistry.getFile(fileId);
      const isDownloading: boolean = latestFile !== null && latestFile.local !== null
        ? latestFile.local.is_downloading_active
        : (targetFile.local !== null ? targetFile.local.is_downloading_active : false);

      const isUploading: boolean = this.fileRegistry.isUploading(fileId) ||
        (message.is_outgoing && message.sending_state !== null && message.sending_state.type === 'messageSendingStatePending');
      const uploadProgress: number = this.fileRegistry.getUploadProgress(fileId);

      if (isUploading && !this.fileSubscriptions.has(fileId)) {
        const sub: Subscription = this.fileRegistry.subscribeFile(fileId, (file: File) => {
          if (!this.destroyed) {
            if (file.remote !== null && file.remote.is_uploading_completed) {
              this.scheduleSyncFromProjection();
            } else {
              this.scheduleThrottledSync();
            }
          }
        });
        this.fileSubscriptions.set(fileId, sub);
      }

      let thumbPath: string | null = null;
      if (doc.thumbnail !== null && doc.thumbnail.file !== null) {
        thumbPath = this.fileRegistry.getLocalPath(doc.thumbnail.file.id);
        if (thumbPath === null) {
          this.requestMediaDownload(doc.thumbnail.file.id, 2);
        }
      }

      const captionText: string = docMsg.caption !== null ? docMsg.caption.text : '';
      const captionSpans: MessageTextSpan[] = docMsg.caption !== null ? parseFormattedText(docMsg.caption) : [];

      return new MediaAttachment(
        'document',
        fileId,
        localPath,
        thumbPath,
        doc.thumbnail !== null ? doc.thumbnail.width : 0,
        doc.thumbnail !== null ? doc.thumbnail.height : 0,
        0,
        isDownloading,
        isDownloaded,
        progress,
        captionText,
        captionSpans,
        false,
        isUploading,
        uploadProgress,
        doc.file_name,
        targetFile.size,
        doc.mime_type
      );
    }

    if (message.content.type === 'messageVoiceNote') {
      const voiceContent: MessageVoiceNote = message.content as MessageVoiceNote;
      if (voiceContent.voice_note === null) {
        return null;
      }
      const vn: VoiceNote = voiceContent.voice_note;
      const targetFile: File | null = vn.voice;
      if (targetFile === null) {
        return null;
      }

      const fileId: number = targetFile.id;
      const localPath: string | null = this.fileRegistry.getLocalPath(fileId, targetFile);
      const isDownloaded: boolean = this.fileRegistry.isDownloaded(fileId, targetFile);
      const progress: number = this.fileRegistry.getDownloadProgress(fileId);
      const latestFile: File | null = this.fileRegistry.getFile(fileId);
      const isDownloading: boolean = latestFile !== null && latestFile.local !== null
        ? latestFile.local.is_downloading_active
        : (targetFile.local !== null ? targetFile.local.is_downloading_active : false);

      const isUploading: boolean = this.fileRegistry.isUploading(fileId) ||
        (message.is_outgoing && message.sending_state !== null && message.sending_state.type === 'messageSendingStatePending');
      const uploadProgress: number = this.fileRegistry.getUploadProgress(fileId);

      if (isUploading && !this.fileSubscriptions.has(fileId)) {
        const sub: Subscription = this.fileRegistry.subscribeFile(fileId, (file: File) => {
          if (!this.destroyed) {
            if (file.remote !== null && file.remote.is_uploading_completed) {
              this.scheduleSyncFromProjection();
            } else {
              this.scheduleThrottledSync();
            }
          }
        });
        this.fileSubscriptions.set(fileId, sub);
      }

      const captionText: string = voiceContent.caption !== null ? voiceContent.caption.text : '';
      const captionSpans: MessageTextSpan[] = voiceContent.caption !== null ? parseFormattedText(voiceContent.caption) : [];
      const waveform: number[] = decodeWaveform(vn.waveform);

      return new MediaAttachment(
        'voiceNote',
        fileId,
        localPath,
        null,
        0,
        0,
        vn.duration,
        isDownloading,
        isDownloaded,
        progress,
        captionText,
        captionSpans,
        false,
        isUploading,
        uploadProgress,
        '',
        targetFile.size,
        vn.mime_type,
        waveform,
        '',
        '',
        voiceContent.is_listened
      );
    }

    if (message.content.type === 'messageAudio') {
      const audioContent: MessageAudio = message.content as MessageAudio;
      if (audioContent.audio === null) {
        return null;
      }
      const audio: Audio = audioContent.audio;
      const targetFile: File | null = audio.audio;
      if (targetFile === null) {
        return null;
      }

      const fileId: number = targetFile.id;
      const localPath: string | null = this.fileRegistry.getLocalPath(fileId, targetFile);
      const isDownloaded: boolean = this.fileRegistry.isDownloaded(fileId, targetFile);
      const progress: number = this.fileRegistry.getDownloadProgress(fileId);
      const latestFile: File | null = this.fileRegistry.getFile(fileId);
      const isDownloading: boolean = latestFile !== null && latestFile.local !== null
        ? latestFile.local.is_downloading_active
        : (targetFile.local !== null ? targetFile.local.is_downloading_active : false);

      const isUploading: boolean = this.fileRegistry.isUploading(fileId) ||
        (message.is_outgoing && message.sending_state !== null && message.sending_state.type === 'messageSendingStatePending');
      const uploadProgress: number = this.fileRegistry.getUploadProgress(fileId);

      if (isUploading && !this.fileSubscriptions.has(fileId)) {
        const sub: Subscription = this.fileRegistry.subscribeFile(fileId, (file: File) => {
          if (!this.destroyed) {
            if (file.remote !== null && file.remote.is_uploading_completed) {
              this.scheduleSyncFromProjection();
            } else {
              this.scheduleThrottledSync();
            }
          }
        });
        this.fileSubscriptions.set(fileId, sub);
      }

      let thumbPath: string | null = null;
      if (audio.album_cover_thumbnail !== null && audio.album_cover_thumbnail.file !== null) {
        thumbPath = this.fileRegistry.getLocalPath(audio.album_cover_thumbnail.file.id);
        if (thumbPath === null) {
          this.requestMediaDownload(audio.album_cover_thumbnail.file.id, 2);
        }
      }

      const captionText: string = audioContent.caption !== null ? audioContent.caption.text : '';
      const captionSpans: MessageTextSpan[] = audioContent.caption !== null ? parseFormattedText(audioContent.caption) : [];

      return new MediaAttachment(
        'audio',
        fileId,
        localPath,
        thumbPath,
        0,
        0,
        audio.duration,
        isDownloading,
        isDownloaded,
        progress,
        captionText,
        captionSpans,
        false,
        isUploading,
        uploadProgress,
        audio.file_name,
        targetFile.size,
        audio.mime_type,
        [],
        audio.title,
        audio.performer,
        false
      );
    }

    return null;
  }

  private resolveReplyInfo(message: Message): ReplyInfo {
    // 1. 发件人姓名与颜色
    let senderName: string = '';
    let senderColorIndex: number = -1;
    if (message.is_outgoing) {
      senderName = 'You';
      senderColorIndex = -1;
    } else {
      const senderInfo: SenderInfo = resolveSenderInfo(
        false,
        this.chatKind,
        message.sender_id,
        {
          lookupUser: (userId: number): User | null => this.userRegistry.getUser(userId),
          requestUser: (userId: number): void => this.requestSenderUser(userId)
        }
      );
      senderName = senderInfo.name;
      senderColorIndex = senderInfo.colorIndex;
    }

    // 2. 缩略图与多媒体判定
    let thumbnailPath: string | null = null;
    let isSticker: boolean = false;
    let summary: string = '';

    if (message.content !== null) {
      switch (message.content.type) {
        case 'messageText': {
          const textContent: MessageText = message.content as MessageText;
          summary = textContent.text !== null ? textContent.text.text : '';
          break;
        }
        case 'messagePhoto': {
          const photoContent: MessagePhoto = message.content as MessagePhoto;
          if (photoContent.caption !== null && photoContent.caption.text.length > 0) {
            summary = photoContent.caption.text;
          } else {
            summary = 'Photo';
          }
          if (photoContent.photo !== null && photoContent.photo.sizes.length > 0) {
            // 优先检查是否已有任何尺寸已在本地缓存
            for (let i = 0; i < photoContent.photo.sizes.length; i++) {
              const ps: PhotoSize = photoContent.photo.sizes[i];
              if (ps.photo !== null) {
                const lp: string | null = this.fileRegistry.getLocalPath(ps.photo.id);
                if (lp !== null) {
                  thumbnailPath = lp;
                  break;
                }
              }
            }
            // 若尚无任何本地缓存，选用最小缩略图发起下载
            if (thumbnailPath === null) {
              const smallestSize: PhotoSize = photoContent.photo.sizes[0];
              if (smallestSize.photo !== null) {
                const fileId: number = smallestSize.photo.id;
                thumbnailPath = this.fileRegistry.getLocalPath(fileId);
                if (thumbnailPath === null && !this.fileRegistry.isDownloaded(fileId)) {
                  this.requestMediaDownload(fileId, 2);
                }
              }
            }
          }
          break;
        }
        case 'messageSticker': {
          const stickerContent: MessageSticker = message.content as MessageSticker;
          isSticker = true;
          if (stickerContent.sticker !== null) {
            const sticker: Sticker = stickerContent.sticker;
            summary = sticker.emoji.length > 0 ? `${sticker.emoji} Sticker` : 'Sticker';
            if (sticker.thumbnail !== null && sticker.thumbnail.file !== null) {
              const fileId: number = sticker.thumbnail.file.id;
              thumbnailPath = this.fileRegistry.getLocalPath(fileId);
              if (thumbnailPath === null && !this.fileRegistry.isDownloaded(fileId)) {
                this.requestMediaDownload(fileId, 2);
              }
            }
            if (thumbnailPath === null && sticker.sticker !== null) {
              const fileId: number = sticker.sticker.id;
              thumbnailPath = this.fileRegistry.getLocalPath(fileId);
              if (thumbnailPath === null && !this.fileRegistry.isDownloaded(fileId)) {
                this.requestMediaDownload(fileId, 2);
              }
            }
          } else {
            summary = 'Sticker';
          }
          break;
        }
        case 'messageVideo': {
          const videoContent: MessageVideo = message.content as MessageVideo;
          if (videoContent.caption !== null && videoContent.caption.text.length > 0) {
            summary = videoContent.caption.text;
          } else {
            summary = 'Video';
          }
          if (videoContent.video !== null && videoContent.video.thumbnail !== null && videoContent.video.thumbnail.file !== null) {
            const fileId: number = videoContent.video.thumbnail.file.id;
            thumbnailPath = this.fileRegistry.getLocalPath(fileId);
            if (thumbnailPath === null && !this.fileRegistry.isDownloaded(fileId)) {
              this.requestMediaDownload(fileId, 2);
            }
          }
          break;
        }
        case 'messageAnimation': {
          const animContent: MessageAnimation = message.content as MessageAnimation;
          if (animContent.caption !== null && animContent.caption.text.length > 0) {
            summary = animContent.caption.text;
          } else {
            summary = 'GIF';
          }
          if (animContent.animation !== null && animContent.animation.thumbnail !== null && animContent.animation.thumbnail.file !== null) {
            const fileId: number = animContent.animation.thumbnail.file.id;
            thumbnailPath = this.fileRegistry.getLocalPath(fileId);
            if (thumbnailPath === null && !this.fileRegistry.isDownloaded(fileId)) {
              this.requestMediaDownload(fileId, 2);
            }
          }
          break;
        }
        case 'messageVideoNote': {
          summary = 'Video message';
          const noteContent: MessageVideoNote = message.content as MessageVideoNote;
          if (noteContent.video_note !== null && noteContent.video_note.thumbnail !== null && noteContent.video_note.thumbnail.file !== null) {
            const fileId: number = noteContent.video_note.thumbnail.file.id;
            thumbnailPath = this.fileRegistry.getLocalPath(fileId);
            if (thumbnailPath === null && !this.fileRegistry.isDownloaded(fileId)) {
              this.requestMediaDownload(fileId, 2);
            }
          }
          break;
        }
        case 'messageVoiceNote': {
          summary = 'Voice message';
          break;
        }
        case 'messageAudio': {
          const audioContent: MessageAudio = message.content as MessageAudio;
          if (audioContent.audio !== null && audioContent.audio.title.length > 0) {
            summary = audioContent.audio.title;
          } else {
            summary = 'Audio';
          }
          if (audioContent.audio !== null && audioContent.audio.album_cover_thumbnail !== null && audioContent.audio.album_cover_thumbnail.file !== null) {
            const fileId: number = audioContent.audio.album_cover_thumbnail.file.id;
            thumbnailPath = this.fileRegistry.getLocalPath(fileId);
            if (thumbnailPath === null && !this.fileRegistry.isDownloaded(fileId)) {
              this.requestMediaDownload(fileId, 2);
            }
          }
          break;
        }
        case 'messageDocument': {
          const docContent: MessageDocument = message.content as MessageDocument;
          if (docContent.document !== null && docContent.document.file_name.length > 0) {
            summary = docContent.document.file_name;
          } else {
            summary = 'Document';
          }
          if (docContent.document !== null && docContent.document.thumbnail !== null && docContent.document.thumbnail.file !== null) {
            const fileId: number = docContent.document.thumbnail.file.id;
            thumbnailPath = this.fileRegistry.getLocalPath(fileId);
            if (thumbnailPath === null && !this.fileRegistry.isDownloaded(fileId)) {
              this.requestMediaDownload(fileId, 2);
            }
          }
          break;
        }
        default: {
          summary = messageContentText(message.content);
          break;
        }
      }
    }

    return new ReplyInfo(summary, senderName, senderColorIndex, thumbnailPath, isSticker);
  }

  private resolveLinkPreviewInfo(linkPreview: LinkPreview | null): LinkPreviewInfo | null {
    if (linkPreview === null) {
      return null;
    }
    const url: string = linkPreview.url;
    const displayUrl: string = linkPreview.display_url.length > 0 ? linkPreview.display_url : url;
    const siteName: string = linkPreview.site_name;
    const title: string = linkPreview.title;
    const description: string = linkPreview.description !== null ? linkPreview.description.text : '';
    const author: string = linkPreview.author;
    const showAboveText: boolean = linkPreview.show_above_text;
    const showMediaAboveDescription: boolean = linkPreview.show_media_above_description;

    let thumbFileId: number = 0;
    let isPhoto: boolean = false;
    let isLargeMedia: boolean = linkPreview.show_large_media;
    let mediaWidth: number = 0;
    let mediaHeight: number = 0;

    if (linkPreview.type_ !== null) {
      const t = linkPreview.type_;
      if (t.type === 'linkPreviewTypePhoto') {
        isPhoto = true;
        isLargeMedia = true;
        const photo = (t as LinkPreviewTypePhoto).photo;
        if (photo !== null && photo.sizes.length > 0) {
          const size = this.chooseDisplaySize(photo.sizes);
          if (size.photo !== null) {
            thumbFileId = size.photo.id;
          }
          mediaWidth = size.width;
          mediaHeight = size.height;
        }
      } else if (t.type === 'linkPreviewTypeArticle') {
        const photo = (t as LinkPreviewTypeArticle).photo;
        if (photo !== null && photo.sizes.length > 0) {
          const size = isLargeMedia ? this.chooseDisplaySize(photo.sizes) : photo.sizes[0];
          if (size.photo !== null) {
            thumbFileId = size.photo.id;
          }
          mediaWidth = size.width;
          mediaHeight = size.height;
        }
      } else if (t.type === 'linkPreviewTypeApp') {
        const photo = (t as LinkPreviewTypeApp).photo;
        if (photo !== null && photo.sizes.length > 0) {
          const size = isLargeMedia ? this.chooseDisplaySize(photo.sizes) : photo.sizes[0];
          if (size.photo !== null) {
            thumbFileId = size.photo.id;
          }
          mediaWidth = size.width;
          mediaHeight = size.height;
        }
      } else if (t.type === 'linkPreviewTypeVideo') {
        const video = (t as LinkPreviewTypeVideo).video;
        if (video !== null) {
          mediaWidth = video.width;
          mediaHeight = video.height;
          if (video.thumbnail !== null && video.thumbnail.file !== null) {
            thumbFileId = video.thumbnail.file.id;
          }
        }
      } else if (t.type === 'linkPreviewTypeAnimation') {
        const anim = (t as LinkPreviewTypeAnimation).animation;
        if (anim !== null) {
          mediaWidth = anim.width;
          mediaHeight = anim.height;
          if (anim.thumbnail !== null && anim.thumbnail.file !== null) {
            thumbFileId = anim.thumbnail.file.id;
          }
        }
      } else if (t.type === 'linkPreviewTypeDocument') {
        const doc = (t as LinkPreviewTypeDocument).document;
        if (doc !== null && doc.thumbnail !== null && doc.thumbnail.file !== null) {
          thumbFileId = doc.thumbnail.file.id;
          mediaWidth = doc.thumbnail.width;
          mediaHeight = doc.thumbnail.height;
        }
      }
    }

    let thumbnailPath: string | null = null;
    if (thumbFileId > 0) {
      thumbnailPath = this.fileRegistry.getLocalPath(thumbFileId);
      if (thumbnailPath === null) {
        this.requestMediaDownload(thumbFileId, 2);
      }
    }

    const info: LinkPreviewInfo = new LinkPreviewInfo(
      url,
      displayUrl,
      siteName,
      title,
      description,
      author,
      showAboveText,
      thumbnailPath,
      thumbFileId,
      isPhoto,
      isLargeMedia,
      showMediaAboveDescription,
      mediaWidth,
      mediaHeight
    );

    return info.hasContent() ? info : null;
  }

  private mapMessageToItem(
    message: Message,
    replyInfoById: Map<number, ReplyInfo>,
    lastReadOutboxMessageId: number,
    showDateHeader: boolean = false,
    dateHeaderText: string = '',
    showUnreadSeparator: boolean = false
  ): MessageItem {
    let replyToId: number | null = null;
    let replyToSummary: string = '';
    let replySenderName: string = '';
    let replySenderColorIndex: number = -1;
    let replyThumbnailPath: string | null = null;
    let replyIsSticker: boolean = false;
    if (message.reply_to !== null && message.reply_to.type === 'messageReplyToMessage') {
      const rep = message.reply_to as MessageReplyToMessage;
      replyToId = rep.message_id;
    }
    if (replyToId !== null) {
      let replyInfo: ReplyInfo | undefined = replyInfoById.get(replyToId);
      if (replyInfo === undefined) {
        const cachedMsg: Message | undefined = this.projection.getMessageById(replyToId);
        if (cachedMsg !== undefined) {
          replyInfo = this.resolveReplyInfo(cachedMsg);
        } else {
          this.requestMissingReplyMessage(replyToId);
        }
      }
      if (replyInfo !== undefined) {
        replyToSummary = replyInfo.summary;
        replySenderName = replyInfo.senderName;
        replySenderColorIndex = replyInfo.senderColorIndex;
        replyThumbnailPath = replyInfo.thumbnailPath;
        replyIsSticker = replyInfo.isSticker;
      }
    }
    const isTextMessage: boolean = message.content !== null && message.content.type === 'messageText';
    const media: MediaAttachment | null = this.resolveMediaAttachment(message);
    // POLL-101：messagePoll 内容解析为 PollView（气泡渲染投票卡，正文行不再输出占位文本）。
    const poll: PollView | null = message.content !== null && message.content.type === 'messagePoll'
      ? pollViewOf((message.content as MessagePoll).poll)
      : null;

    let spans: MessageTextSpan[] = [];
    let displayText: string = '';
    let linkPreviewInfo: LinkPreviewInfo | null = null;

    if (poll !== null) {
      displayText = '';
    } else if (media !== null) {
      displayText = media.kind === 'sticker' ? '' : media.caption;
      spans = media.kind === 'sticker' ? [] : media.captionSpans;
    } else if (isTextMessage) {
      const textContent: MessageText = message.content as MessageText;
      displayText = textContent.text !== null ? textContent.text.text : '';
      spans = parseFormattedText(textContent.text);
      linkPreviewInfo = this.resolveLinkPreviewInfo(textContent.link_preview);
    } else {
      displayText = messageContentText(message.content);
    }

    // MSG-102 & MSG-102-AVATAR：群聊收到的用户消息出署名与真实头像；未命中缓存时拉取并订阅刷新。
    const senderInfo: SenderInfo = resolveSenderInfo(
      message.is_outgoing,
      this.chatKind,
      message.sender_id,
      {
        lookupUser: (userId: number): User | null => this.userRegistry.getUser(userId),
        requestUser: (userId: number): void => this.requestSenderUser(userId),
        lookupFilePath: (fileId: number): string | null => this.fileRegistry.getLocalPath(fileId),
        requestAvatarDownload: (fileId: number): void => {
          this.requestMediaDownload(fileId, 2);
        }
      }
    );

    // CHANNEL-101：频道帖子（非己方）、反应 chips 与评论数解析
    const isChannelPost: boolean = this.chatKind === 'channel' && !message.is_outgoing;
    const reactionChips: ReactionChip[] = [];
    if (message.interaction_info !== null && message.interaction_info.reactions !== null) {
      const rawReactions = message.interaction_info.reactions.reactions;
      for (let i = 0; i < rawReactions.length; i++) {
        const r = rawReactions[i];
        if (r.type_ !== null && r.type_.type === 'reactionTypeEmoji') {
          const emoji: string = (r.type_ as ReactionTypeEmoji).emoji;
          reactionChips.push(new ReactionChip(emoji, r.total_count, r.is_chosen));
        }
      }
    }
    let commentCount: number = 0;
    if (message.interaction_info !== null && message.interaction_info.reply_info !== null) {
      commentCount = message.interaction_info.reply_info.reply_count;
    }

    return new MessageItem(
      message.id,
      displayText,
      message.date * 1000,
      message.is_outgoing,
      senderInfo.name,
      messageSendStateOf(message.sending_state),
      isTextMessage,
      message.edit_date > 0,
      replyToId,
      replyToSummary,
      spans,
      senderInfo.colorIndex,
      isOutgoingMessageRead(message.is_outgoing, message.id, lastReadOutboxMessageId),
      media,
      replySenderName,
      replySenderColorIndex,
      replyThumbnailPath,
      replyIsSticker,
      showDateHeader,
      dateHeaderText,
      showUnreadSeparator,
      senderInfo.avatarPath,
      [],
      [],
      linkPreviewInfo,
      senderInfo.userId,
      isChannelPost,
      reactionChips,
      commentCount,
      message.is_pinned ?? false,
      poll
    );
  }

  private mapAlbumToItem(
    messages: Message[],
    replyInfoById: Map<number, ReplyInfo>,
    lastReadOutboxMessageId: number,
    showDateHeader: boolean = false,
    dateHeaderText: string = '',
    showUnreadSeparator: boolean = false
  ): MessageItem {
    const lastMsg: Message = messages[messages.length - 1];
    const albumMessageIds: number[] = [];
    const albumItems: MediaAttachment[] = [];
    let commonCaption: string = '';
    let commonSpans: MessageTextSpan[] = [];
    let isEdited: boolean = false;

    for (let i = 0; i < messages.length; i++) {
      const msg: Message = messages[i];
      albumMessageIds.push(msg.id);
      if (msg.edit_date > 0) {
        isEdited = true;
      }
      const media: MediaAttachment | null = this.resolveMediaAttachment(msg);
      if (media !== null) {
        albumItems.push(media);
        if (commonCaption.length === 0 && media.caption.length > 0) {
          commonCaption = media.caption;
          commonSpans = media.captionSpans;
        }
      }
    }

    let replyToId: number | null = null;
    for (let i = 0; i < messages.length; i++) {
      const rId: number | null = repliedMessageIdOf(messages[i].reply_to);
      if (rId !== null) {
        replyToId = rId;
        break;
      }
    }

    let replyToSummary: string = '';
    let replySenderName: string = '';
    let replySenderColorIndex: number = -1;
    let replyThumbnailPath: string | null = null;
    let replyIsSticker: boolean = false;

    if (replyToId !== null) {
      let replyInfo: ReplyInfo | undefined = replyInfoById.get(replyToId);
      if (replyInfo === undefined) {
        const cachedMsg: Message | undefined = this.projection.getMessageById(replyToId);
        if (cachedMsg !== undefined) {
          replyInfo = this.resolveReplyInfo(cachedMsg);
        } else {
          this.requestMissingReplyMessage(replyToId);
        }
      }
      if (replyInfo !== undefined) {
        replyToSummary = replyInfo.summary;
        replySenderName = replyInfo.senderName;
        replySenderColorIndex = replyInfo.senderColorIndex;
        replyThumbnailPath = replyInfo.thumbnailPath;
        replyIsSticker = replyInfo.isSticker;
      }
    }

    const senderInfo: SenderInfo = resolveSenderInfo(
      lastMsg.is_outgoing,
      this.chatKind,
      lastMsg.sender_id,
      {
        lookupUser: (userId: number): User | null => this.userRegistry.getUser(userId),
        requestUser: (userId: number): void => this.requestSenderUser(userId),
        lookupFilePath: (fileId: number): string | null => this.fileRegistry.getLocalPath(fileId),
        requestAvatarDownload: (fileId: number): void => {
          this.requestMediaDownload(fileId, 2);
        }
      }
    );

    const primaryMedia: MediaAttachment | null = albumItems.length > 0 ? albumItems[0] : null;

    // CHANNEL-101：相册所属频道帖子、反应 chips 与评论数解析
    const isChannelPost: boolean = this.chatKind === 'channel' && !lastMsg.is_outgoing;
    const albumReactionChips: ReactionChip[] = [];
    if (lastMsg.interaction_info !== null && lastMsg.interaction_info.reactions !== null) {
      const rawReactions = lastMsg.interaction_info.reactions.reactions;
      for (let i = 0; i < rawReactions.length; i++) {
        const r = rawReactions[i];
        if (r.type_ !== null && r.type_.type === 'reactionTypeEmoji') {
          const emoji: string = (r.type_ as ReactionTypeEmoji).emoji;
          albumReactionChips.push(new ReactionChip(emoji, r.total_count, r.is_chosen));
        }
      }
    }
    let albumCommentCount: number = 0;
    if (lastMsg.interaction_info !== null && lastMsg.interaction_info.reply_info !== null) {
      albumCommentCount = lastMsg.interaction_info.reply_info.reply_count;
    }

    return new MessageItem(
      lastMsg.id,
      commonCaption,
      lastMsg.date * 1000,
      lastMsg.is_outgoing,
      senderInfo.name,
      messageSendStateOf(lastMsg.sending_state),
      false,
      isEdited,
      replyToId,
      replyToSummary,
      commonSpans,
      senderInfo.colorIndex,
      isOutgoingMessageRead(lastMsg.is_outgoing, lastMsg.id, lastReadOutboxMessageId),
      primaryMedia,
      replySenderName,
      replySenderColorIndex,
      replyThumbnailPath,
      replyIsSticker,
      showDateHeader,
      dateHeaderText,
      showUnreadSeparator,
      senderInfo.avatarPath,
      albumItems,
      albumMessageIds,
      null,
      senderInfo.userId,
      isChannelPost,
      albumReactionChips,
      albumCommentCount,
      lastMsg.is_pinned ?? false
    );
  }

  /**
   * 被回复消息不在当前已加载历史中 → 异步向 TDLib 拉取该消息详情（getMessage），
   * 结果注入 projection.addCachedMessage 并触发 throttledSyncFromProjection 重新计算。
   */
  private requestMissingReplyMessage(messageId: number): void {
    if (this.destroyed || this.requestedReplyIds.has(messageId)) {
      return;
    }
    this.requestedReplyIds.add(messageId);
    const req: GetMessage = new GetMessage();
    req.chat_id = this.currentState.chatId;
    req.message_id = messageId;
    const result: Result<TdPendingRequest, AppError> =
      this.scope.request('getMessage', encodeGetMessage(req) as TdWireObject);
    if (result.ok) {
      result.value.promise.then((res: Result<TdWireObject, AppError>) => {
        if (!this.destroyed && res.ok) {
          const msg: Message | null = decodeMessage(res.value as TdJsonRaw);
          if (msg !== null) {
            this.projection.addCachedMessage(msg);
            this.scheduleThrottledSync();
          }
        }
      }).catch(() => {
      });
    }
  }

  /**
   * MSG-102：取一次会话类型（openChat 后 getChat 命中 TDLib 本地缓存）。
   * 会话种类稳定（基本群迁移超级群会换 chatId），一次请求足够；失败只记日志，
   * chatKind 保持 'unknown' 保守不出署名。
   */
  private fetchChatKind(): void {
    if (this.chatTypeRequested || this.destroyed) {
      return;
    }
    this.chatTypeRequested = true;
    const req: GetChat = new GetChat();
    req.chat_id = this.currentState.chatId;
    const result: Result<TdPendingRequest, AppError> =
      this.scope.request('getChat', encodeGetChat(req) as TdWireObject);
    if (result.err) {
      this.logger.logError(TAG, result.error);
      return;
    }
    if (result.ok) {
      result.value.promise.then((res: Result<TdWireObject, AppError>) => {
        if (this.destroyed) {
          return;
        }
        if (res.err) {
          this.logger.logError(TAG, res.error);
        }
        if (res.ok) {
          const chat: Chat | null = decodeChat(res.value as TdJsonRaw);
          if (chat !== null) {
            this.chatKind = chatKindOf(chat.type_);
            // MSG-109：缓存 supergroup/basicGroup id，供头部成员数副标题查询。
            if (chat.type_ !== null) {
              if (chat.type_.type === 'chatTypeSupergroup') {
                this.supergroupId = (chat.type_ as ChatTypeSupergroup).supergroup_id;
                this.fetchSupergroupMemberStatus();
              } else if (chat.type_.type === 'chatTypeBasicGroup') {
                this.basicGroupId = (chat.type_ as ChatTypeBasicGroup).basic_group_id;
              } else if (chat.type_.type === 'chatTypePrivate') {
                this.privatePeerUserId = (chat.type_ as ChatTypePrivate).user_id;
              } else if (chat.type_.type === 'chatTypeSecret') {
                this.privatePeerUserId = (chat.type_ as ChatTypeSecret).user_id;
              }
            }
            this.logger.info(TAG, 'chat_kind_resolved', `kind=${this.chatKind}`);
            // SET-106：同一次 getChat 响应即带 chat.notification_settings，
            // 直接回读静音态，⋮ 菜单首轮渲染就能出正确文案。
            this.applyChatNotificationSettings(chat.notification_settings);
            // CHAN-SEND：同一次响应即带 chat.permissions，先回读发言权再回灌 chatKind，
            // 保证底栏首轮渲染就知道是出输入栏还是静音条（同一同步块内，不存在闪烁）。
            this.applyChatSendPermissions(chat.permissions);
            // MSG-109：回灌 reducer 驱动头部通话按钮/菜单，并启动副标题计算。
            this.dispatch(new OnChatKindChanged(this.chatKind));
            this.buildHeaderSubtitle();
            this.scheduleSyncFromProjection();
          }
        }
      }).catch(() => {
      });
    }
  }

  /**
   * CHANNEL-101：拉取超级群/频道详情以确认当前用户的成员身份（GetSupergroup）。
   * 若 status 为 chatMemberStatusLeft，则表示未加入频道（回灌 isMember=false）。
   */
  private fetchSupergroupMemberStatus(): void {
    if (this.destroyed || this.supergroupId <= 0) {
      return;
    }
    const req: GetSupergroup = new GetSupergroup();
    req.supergroup_id = this.supergroupId;
    const result: Result<TdPendingRequest, AppError> =
      this.scope.request('getSupergroup', encodeGetSupergroup(req) as TdWireObject);
    if (result.err) {
      this.logger.logError(TAG, result.error);
      return;
    }
    if (result.ok) {
      result.value.promise.then((res: Result<TdWireObject, AppError>) => {
        if (this.destroyed) {
          return;
        }
        if (res.err) {
          this.logger.logError(TAG, res.error);
          return;
        }
        if (res.ok) {
          const sg: Supergroup | null = decodeSupergroup(res.value as TdJsonRaw);
          if (sg !== null && sg.status !== null) {
            const isLeft: boolean = sg.status.type === 'chatMemberStatusLeft';
            this.logger.info(TAG, 'supergroup_status_resolved', `isLeft=${isLeft}`);
            this.dispatch(new OnChannelMemberStatusChanged(!isLeft));
          }
        }
      }).catch(() => {
      });
    }
  }

  /**
   * MSG-108：拉取当前会话的置顶消息（GetChatPinnedMessage）。
   * 若无置顶消息，TDLib 返回 404，静默回灌 OnPinnedMessageLoaded(null)。
   * 若拉取成功，解析消息并在缓存中留存，回灌 OnPinnedMessageLoaded(PinnedMessageInfo)。
   */
  private fetchPinnedMessage(): void {
    if (this.destroyed) {
      return;
    }
    const result: Result<TdPendingRequest, AppError> = this.projection.getChatPinnedMessage();
    if (result.err) {
      this.dispatch(new OnPinnedMessageLoaded(null));
      return;
    }
    if (result.ok) {
      result.value.promise.then((res: Result<TdWireObject, AppError>) => {
        if (this.destroyed) {
          return;
        }
        if (res.err) {
          this.logger.info(TAG, 'pinned_message_none', `err=${res.error.message}`);
          this.dispatch(new OnPinnedMessageLoaded(null));
          return;
        }
        if (res.ok) {
          const msg: Message | null = decodeMessage(res.value as TdJsonRaw);
          if (msg === null || msg.id <= 0) {
            this.dispatch(new OnPinnedMessageLoaded(null));
            return;
          }
          this.projection.addCachedMessage(msg);
          const senderTitle: string = this.resolvePinnedSenderTitle(msg);
          const snippet: string = messageContentText(msg.content);
          const pinnedInfo: PinnedMessageInfo = new PinnedMessageInfo(
            msg.id,
            senderTitle,
            snippet.length > 0 ? snippet : 'Pinned message'
          );
          this.logger.info(TAG, 'pinned_message_loaded', `id=${msg.id} sender=${senderTitle}`);
          this.dispatch(new OnPinnedMessageLoaded(pinnedInfo));
        }
      }).catch(() => {
        if (!this.destroyed) {
          this.dispatch(new OnPinnedMessageLoaded(null));
        }
      });
    }
  }

  /** MSG-108：解析置顶消息展示标题（发送者名字/群名称/私聊用户名）。 */
  private resolvePinnedSenderTitle(msg: Message): string {
    if (msg.sender_id !== null && msg.sender_id !== undefined) {
      if (msg.sender_id.type === 'messageSenderUser') {
        const userId: number = (msg.sender_id as MessageSenderUser).user_id;
        const user: User | null = this.userRegistry.getUser(userId);
        if (user !== null) {
          const name: string = formatFullName(user);
          if (name.length > 0) {
            return name;
          }
        }
        this.requestSenderUser(userId);
        return 'Pinned Message';
      } else if (msg.sender_id.type === 'messageSenderChat') {
        return this.currentState.chatTitle.length > 0 ? this.currentState.chatTitle : 'Pinned Message';
      }
    }
    return 'Pinned Message';
  }

  /** MSG-102：缓存未命中的 sender 拉取一次并订阅，User 到达后重映射上屏。 */
  private requestSenderUser(userId: number): void {
    if (this.destroyed || this.requestedSenderIds.has(userId)) {
      return;
    }
    this.requestedSenderIds.add(userId);
    const subscription: Subscription = this.userRegistry.subscribeUser(userId, () => {
      if (!this.destroyed) {
        this.scheduleSyncFromProjection();
      }
    });
    this.senderSubscriptions.set(userId, subscription);
    const result: Result<TdPendingRequest, AppError> = this.userRegistry.requestUser(userId);
    if (result.err) {
      this.logger.logError(TAG, result.error);
    }
  }

  // ---- MSG-109 头部信息区：副标题计算 ----

  /**
   * 计算头部副标题并回灌（start()、chatKind 解析后及相关订阅回调里调用）：
   * - private：777000 → '服务通知'；否则取 User.status 格式化（缓存未命中先空串，
   *   requestUser + subscribeUser，User 到达后重算）；
   * - group/channel：已知 supergroupId 时拉 getSupergroupFullInfo 出成员数，
   *   并订阅 updateChatOnlineMemberCount 追加在线人数；基本群暂无副标题；
   * - unknown：不动（保持空串）。
   */
  private buildHeaderSubtitle(): void {
    if (this.destroyed) {
      return;
    }
    if (this.chatKind === 'private') {
      const chatId: number = this.currentState.chatId;
      if (chatId === 777000) {
        this.dispatch(new OnHeaderSubtitleChanged('服务通知'));
        return;
      }
      const user: User | null = this.userRegistry.getUser(chatId);
      if (user !== null && user.status !== null) {
        this.dispatch(new OnHeaderSubtitleChanged(this.formatUserStatus(user.status)));
        return;
      }
      // 缓存未命中：先空串，发起请求并订阅该用户，晚到后经回调重算。
      this.requestHeaderUser(chatId);
      this.dispatch(new OnHeaderSubtitleChanged(''));
      return;
    }
    if (this.chatKind === 'group' || this.chatKind === 'channel') {
      this.subscribeOnlineMemberCount();
      if (this.supergroupId > 0) {
        this.requestSupergroupMemberCount();
      } else if (this.basicGroupId > 0) {
        this.requestBasicGroupMemberCount();
      }
      this.updateGroupHeaderSubtitle();
    }
  }

  /** MSG-109：UserStatus → 头部副标题文案（对齐 TGX 中文截图）。 */
  private formatUserStatus(status: TdUserStatus): string {
    switch (status.type) {
      case 'userStatusOnline':
        return '在线';
      case 'userStatusOffline':
        return '最近在线';
      case 'userStatusRecently':
        return '最近上线';
      case 'userStatusLastWeek':
        return '最近一周内上线';
      case 'userStatusLastMonth':
        return '最近一个月内上线';
      default:
        return '';
    }
  }

  /** MSG-109：私聊头部用户信息未命中时请求一次并订阅，User 到达后重算副标题。 */
  private requestHeaderUser(userId: number): void {
    if (this.destroyed) {
      return;
    }
    if (this.headerUserSubscription === null) {
      this.headerUserSubscription = this.userRegistry.subscribeUser(userId, () => {
        if (!this.destroyed) {
          this.buildHeaderSubtitle();
        }
      });
    }
    if (this.headerUserRequested) {
      return;
    }
    this.headerUserRequested = true;
    const result: Result<TdPendingRequest, AppError> = this.userRegistry.requestUser(userId);
    if (result.err) {
      this.logger.logError(TAG, result.error);
    }
  }

  /** MSG-109：已知 supergroupId 时拉成员数；失败只记日志（复位后可重试）。 */
  private requestSupergroupMemberCount(): void {
    if (this.destroyed || this.supergroupId <= 0 || this.supergroupInfoRequested) {
      return;
    }
    this.supergroupInfoRequested = true;
    const req: GetSupergroupFullInfo = new GetSupergroupFullInfo();
    req.supergroup_id = this.supergroupId;
    const result: Result<TdPendingRequest, AppError> =
      this.scope.request('getSupergroupFullInfo', encodeGetSupergroupFullInfo(req) as TdWireObject);
    if (result.err) {
      this.supergroupInfoRequested = false;
      this.logger.logError(TAG, result.error);
      return;
    }
    if (result.ok) {
      result.value.promise.then((res: Result<TdWireObject, AppError>) => {
        if (this.destroyed) {
          return;
        }
        if (res.err) {
          this.supergroupInfoRequested = false;
          this.logger.logError(TAG, res.error);
        }
        if (res.ok) {
          const info: SupergroupFullInfo | null = decodeSupergroupFullInfo(res.value as TdJsonRaw);
          if (info !== null) {
            this.memberCount = info.member_count;
            this.updateGroupHeaderSubtitle();
          }
        }
      }).catch(() => {
      });
    }
  }

  /** MSG-109：已知 basicGroupId 时拉取成员数；失败只记日志（复位后可重试）。 */
  private requestBasicGroupMemberCount(): void {
    if (this.destroyed || this.basicGroupId <= 0 || this.basicGroupInfoRequested) {
      return;
    }
    this.basicGroupInfoRequested = true;
    const req: GetBasicGroup = new GetBasicGroup();
    req.basic_group_id = this.basicGroupId;
    const result: Result<TdPendingRequest, AppError> =
      this.scope.request('getBasicGroup', encodeGetBasicGroup(req) as TdWireObject);
    if (result.err) {
      this.basicGroupInfoRequested = false;
      this.logger.logError(TAG, result.error);
      return;
    }
    if (result.ok) {
      result.value.promise.then((res: Result<TdWireObject, AppError>) => {
        if (this.destroyed) {
          return;
        }
        if (res.err) {
          this.basicGroupInfoRequested = false;
          this.logger.logError(TAG, res.error);
        }
        if (res.ok) {
          const group: BasicGroup | null = decodeBasicGroup(res.value as TdJsonRaw);
          if (group !== null) {
            this.memberCount = group.member_count;
            this.updateGroupHeaderSubtitle();
          }
        }
      }).catch(() => {
      });
    }
  }

  /** MSG-109：按已缓存的成员数/在线人数回灌群副标题（'N 位成员' / 'N 位成员, M 在线'）。 */
  private updateGroupHeaderSubtitle(): void {
    if (this.chatKind !== 'group' && this.chatKind !== 'channel') {
      return;
    }
    let text: string = '';
    if (this.memberCount > 0) {
      text = this.chatKind === 'channel'
        ? `${this.memberCount} 位订阅者`
        : `${this.memberCount} 位成员`;
    }
    // 在线人数仅群聊展示（频道不显示在线数）。
    if (this.chatKind === 'group' && this.onlineMemberCount > 0) {
      text = text.length > 0 ? `${text}, ${this.onlineMemberCount} 在线` : `${this.onlineMemberCount} 在线`;
    }
    this.dispatch(new OnHeaderSubtitleChanged(text));
  }

  /** MSG-109：订阅 updateChatOnlineMemberCount（群在线人数推送），destroy 时退订。 */
  private subscribeOnlineMemberCount(): void {
    if (this.destroyed || this.onlineCountSubscription !== null) {
      return;
    }
    const filter: TdUpdateFilter = {
      clientId: this.scope.clientId,
      types: ['updateChatOnlineMemberCount']
    };
    this.onlineCountSubscription = this.scope.gatewayInstance.subscribeUpdates(
      filter,
      (event: TdRoutedEvent): void => {
        const update: TdUpdate | null = decodeTdUpdate(event.payload as TdJsonRaw);
        if (update === null || update.type !== 'updateChatOnlineMemberCount') {
          return;
        }
        const online: UpdateChatOnlineMemberCount = update as UpdateChatOnlineMemberCount;
        if (online.chat_id !== this.currentState.chatId) {
          return;
        }
        this.onlineMemberCount = online.online_member_count;
        this.updateGroupHeaderSubtitle();
      }
    );
  }

  /**
   * SET-106：把会话通知设置落到本地快照并回灌静音态。
   * null（TDLib 未给）时保持原快照不动，避免把「未知」渲染成「未静音」。
   */
  private applyChatNotificationSettings(settings: ChatNotificationSettings | null): void {
    if (settings === null) {
      return;
    }
    this.chatNotificationSettings = settings;
    const muted: boolean = isChatMuted(settings);
    if (muted !== this.currentState.isMuted) {
      this.logger.info(TAG, 'chat_mute_state', `muted=${muted},mute_for=${settings.mute_for}`);
    }
    this.dispatch(new OnChatMuteStateChanged(muted));
  }

  /** SET-106：订阅 updateChatNotificationSettings（本会话），destroy 时退订。 */
  private subscribeChatNotificationSettings(): void {
    if (this.destroyed || this.muteSubscription !== null) {
      return;
    }
    const filter: TdUpdateFilter = {
      clientId: this.scope.clientId,
      types: ['updateChatNotificationSettings']
    };
    this.muteSubscription = this.scope.gatewayInstance.subscribeUpdates(
      filter,
      (event: TdRoutedEvent): void => {
        const update: TdUpdate | null = decodeTdUpdate(event.payload as TdJsonRaw);
        if (update === null || update.type !== 'updateChatNotificationSettings') {
          return;
        }
        const muteUpdate: UpdateChatNotificationSettings = update as UpdateChatNotificationSettings;
        if (muteUpdate.chat_id !== this.currentState.chatId) {
          return;
        }
        this.applyChatNotificationSettings(muteUpdate.notification_settings);
      }
    );
  }

  /**
   * CHAN-SEND-2：把 chat.permissions 的九位发言权回灌状态（基础消息 / 图片 / 视频 / 文件 /
   * 音乐 / 语音便签 / 视频便签 / 投票 / 贴纸与 GIF）。
   * permissions 为 null（TDLib 没给）时按「全放开」处理 —— 读不到权限不等于没有权限，
   * 收成静音条会把用户彻底锁在输入栏外。
   */
  private applyChatSendPermissions(permissions: ChatPermissions | null): void {
    const rights: ChatSendRights = sendRightsFromPermissions(permissions);
    // 每次 getChat / updateChatPermissions 都打一条：真机取证要能直接看到 TDLib 给的值，
    // 而不是靠「没变化所以没日志」反推。
    this.logger.info(TAG, 'chat_send_permissions',
      `can_send=${rights.basic},media=${canSendAnyMedia(rights)},permissions=${permissions === null ? 'missing' : 'read'}`);
    this.dispatch(new OnChatSendPermissionsChanged(rights));
  }

  /** CHAN-SEND：订阅 updateChatPermissions（本会话），管理员中途改权限即时生效；destroy 时退订。 */
  private subscribeChatPermissions(): void {
    if (this.destroyed || this.permissionsSubscription !== null) {
      return;
    }
    const filter: TdUpdateFilter = {
      clientId: this.scope.clientId,
      types: ['updateChatPermissions']
    };
    this.permissionsSubscription = this.scope.gatewayInstance.subscribeUpdates(
      filter,
      (event: TdRoutedEvent): void => {
        const update: TdUpdate | null = decodeTdUpdate(event.payload as TdJsonRaw);
        if (update === null || update.type !== 'updateChatPermissions') {
          return;
        }
        const permUpdate: UpdateChatPermissions = update as UpdateChatPermissions;
        if (permUpdate.chat_id !== this.currentState.chatId) {
          return;
        }
        this.applyChatSendPermissions(permUpdate.permissions);
      }
    );
  }

  private executeEffect(effect: ChatEffect): void {
    switch (effect.kind) {
      case 'fetchInitialMessages': {
        this.logger.info(TAG, 'fetch_initial_messages', `chatId=${this.currentState.chatId}`);
        this.runFetch(this.projection.loadInitialMessages(INITIAL_PAGE_SIZE));
        break;
      }

      case 'fetchOlderMessages': {
        this.logger.info(TAG, 'fetch_older_messages', `chatId=${this.currentState.chatId}`);
        this.runFetch(this.projection.loadOlderMessages(OLDER_PAGE_SIZE));
        break;
      }

      case 'sendTextMessage': {
        const send: SendTextMessage = effect as SendTextMessage;
        this.logger.info(TAG, 'send_message', `chatId=${send.chatId}`);
        const result: Result<TdPendingRequest, AppError> =
          this.projection.sendTextMessage(send.text, send.replyToMessageId);
        this.projection.clearChatDraftMessage();
        if (result.err) {
          this.logger.logError(TAG, result.error);
          this.dispatch(new OnMessageSendFailed(result.error));
        }
        if (result.ok) {
          result.value.promise.then((res: Result<TdWireObject, AppError>) => {
            if (res.err) {
              this.logger.logError(TAG, res.error);
              if (!this.destroyed) {
                this.dispatch(new OnMessageSendFailed(res.error));
              }
            }
            if (res.ok) {
              this.logger.info(TAG, 'send_message_ok', `chatId=${send.chatId}`);
            }
          }).catch(() => {
          });
        }
        break;
      }

      case 'fetchMessagePermissions': {
        const fetch: FetchMessagePermissions = effect as FetchMessagePermissions;
        this.logger.info(TAG, 'fetch_message_permissions',
          `chatId=${fetch.chatId},messageId=${fetch.messageId}`);
        const result: Result<TdPendingRequest, AppError> = this.projection.getMessageProperties(fetch.messageId);
        if (result.err) {
          this.logger.logError(TAG, result.error);
          this.dispatch(new OnMessageActionFailed(result.error));
        }
        if (result.ok) {
          result.value.promise.then((res: Result<TdWireObject, AppError>) => {
            if (this.destroyed) {
              return;
            }
            if (res.err) {
              this.logger.logError(TAG, res.error);
              this.dispatch(new OnMessageActionFailed(res.error));
            }
            if (res.ok) {
              const props: MessageProperties | null = decodeMessageProperties(res.value as TdJsonRaw);
              if (props === null) {
                this.logger.error(TAG, 'undecodable_message_properties');
                this.dispatch(new OnMessageActionFailed(
                  AppErrors.internal('chat.message_properties_decode', 'failed to decode messageProperties')
                ));
                return;
              }
              const cachedMsg: Message | undefined = this.projection.getMessageById(fetch.messageId);
              const isPinned: boolean = cachedMsg !== undefined && (cachedMsg.is_pinned ?? false);
              this.dispatch(new OnMessageActionMenuLoaded(
                fetch.messageId,
                props.can_be_edited,
                props.can_be_deleted_only_for_self,
                props.can_be_deleted_for_all_users,
                props.can_be_forwarded,
                props.can_be_saved,
                props.can_be_pinned,
                isPinned
              ));
            }
          }).catch(() => {
          });
        }
        break;
      }

      case 'editMessageText': {
        const edit: EditMessageText = effect as EditMessageText;
        this.logger.info(TAG, 'edit_message_text',
          `chatId=${edit.chatId},messageId=${edit.messageId}`);
        const result: Result<TdPendingRequest, AppError> =
          this.projection.editMessageText(edit.messageId, edit.text);
        if (result.err) {
          this.logger.logError(TAG, result.error);
          this.dispatch(new OnMessageActionFailed(result.error));
        }
        if (result.ok) {
          result.value.promise.then((res: Result<TdWireObject, AppError>) => {
            if (res.err) {
              this.logger.logError(TAG, res.error);
              if (!this.destroyed) {
                this.dispatch(new OnMessageActionFailed(res.error));
              }
            }
            if (res.ok) {
              // 成功路径无动作：气泡由 updateMessageContent / updateMessageEdited 刷新。
              this.logger.info(TAG, 'edit_message_text_ok', `messageId=${edit.messageId}`);
            }
          }).catch(() => {
          });
        }
        break;
      }

      case 'deleteMessages': {
        const del: DeleteMessages = effect as DeleteMessages;
        this.logger.info(TAG, 'delete_messages',
          `chatId=${del.chatId},count=${del.messageIds.length},revoke=${del.revoke}`);
        const result: Result<TdPendingRequest, AppError> =
          this.projection.deleteMessages(del.messageIds, del.revoke);
        if (result.err) {
          this.logger.logError(TAG, result.error);
          this.dispatch(new OnMessageActionFailed(result.error));
        }
        if (result.ok) {
          result.value.promise.then((res: Result<TdWireObject, AppError>) => {
            if (res.err) {
              this.logger.logError(TAG, res.error);
              if (!this.destroyed) {
                this.dispatch(new OnMessageActionFailed(res.error));
              }
            }
            if (res.ok) {
              // 成功路径无动作：气泡由 updateDeleteMessages 移出列表。
              this.logger.info(TAG, 'delete_messages_ok', `chatId=${del.chatId}`);
            }
          }).catch(() => {
          });
        }
        break;
      }

      case 'pinMessageEffect': {
        const pin: PinMessageEffect = effect as PinMessageEffect;
        this.logger.info(TAG, 'pin_message',
          `chatId=${pin.chatId},messageId=${pin.messageId},disableNotification=${pin.disableNotification}`);
        const result: Result<TdPendingRequest, AppError> =
          this.projection.pinChatMessage(pin.messageId, pin.disableNotification, pin.onlyForSelf);
        if (result.err) {
          this.logger.logError(TAG, result.error);
          this.dispatch(new OnMessageActionFailed(result.error));
        }
        if (result.ok) {
          result.value.promise.then((res: Result<TdWireObject, AppError>) => {
            if (this.destroyed) {
              return;
            }
            if (res.err) {
              this.logger.logError(TAG, res.error);
              this.dispatch(new OnMessageActionFailed(res.error));
            }
            if (res.ok) {
              this.logger.info(TAG, 'pin_message_ok', `messageId=${pin.messageId}`);
              this.fetchPinnedMessage();
            }
          }).catch(() => {
          });
        }
        break;
      }

      case 'unpinMessageEffect': {
        const unpin: UnpinMessageEffect = effect as UnpinMessageEffect;
        this.logger.info(TAG, 'unpin_message', `chatId=${unpin.chatId},messageId=${unpin.messageId}`);
        const result: Result<TdPendingRequest, AppError> =
          this.projection.unpinChatMessage(unpin.messageId);
        if (result.err) {
          this.logger.logError(TAG, result.error);
          this.dispatch(new OnMessageActionFailed(result.error));
        }
        if (result.ok) {
          result.value.promise.then((res: Result<TdWireObject, AppError>) => {
            if (this.destroyed) {
              return;
            }
            if (res.err) {
              this.logger.logError(TAG, res.error);
              this.dispatch(new OnMessageActionFailed(res.error));
            }
            if (res.ok) {
              this.logger.info(TAG, 'unpin_message_ok', `messageId=${unpin.messageId}`);
              this.fetchPinnedMessage();
            }
          }).catch(() => {
          });
        }
        break;
      }

      case 'navigateBack': {
        this.logger.info(TAG, 'navigate_back', `chatId=${this.currentState.chatId}`);
        this.onBack();
        break;
      }

      case 'openForwardPicker': {
        // MSG-106：选择器 UI 归装配层（entry 同时持有会话列表数据与本次选择），
        // 这里只把选择集合透传出去。
        const picker: OpenForwardPicker = effect as OpenForwardPicker;
        this.logger.info(TAG, 'open_forward_picker',
          `fromChatId=${picker.fromChatId},count=${picker.messageIds.length}`);
        this.onOpenForwardPicker(picker.messageIds);
        break;
      }

      case 'forwardMessages': {
        const forward: ForwardMessages = effect as ForwardMessages;
        this.logger.info(TAG, 'forward_messages',
          `fromChatId=${forward.fromChatId},toChatId=${forward.toChatId},count=${forward.messageIds.length},copy=${forward.sendCopy}`);
        const result: Result<TdPendingRequest, AppError> =
          this.projection.forwardMessages(
            forward.toChatId,
            forward.messageIds,
            forward.sendCopy,
            forward.removeCaption
          );
        if (result.err) {
          this.logger.logError(TAG, result.error);
          this.dispatch(new OnForwardFailed(result.error));
        }
        if (result.ok) {
          result.value.promise.then((res: Result<TdWireObject, AppError>) => {
            if (this.destroyed) {
              return;
            }
            if (res.err) {
              this.logger.logError(TAG, res.error);
              this.dispatch(new OnForwardFailed(res.error));
            }
            // 正向 if(res.ok)：ArkTS 收窄只在块内有效，early-return 后取 res.value 不成立。
            if (res.ok) {
              // TDLib 返回 messageIds 对应的转发结果：不可转发的条目占位 null。
              const forwardedCount: number = countForwardedMessages(res.value);
              this.logger.info(TAG, 'forward_messages_ok',
                `forwarded=${forwardedCount},total=${forward.messageIds.length}`);
              if (forwardedCount === 0) {
                // 全部不可转发（如受保护内容）：按失败提示，别假装成功收起选择态。
                this.dispatch(new OnForwardFailed(
                  AppErrors.internal('chat.forward_none', 'none of the selected messages could be forwarded')
                ));
              } else {
                this.dispatch(new OnForwardCompleted(forwardedCount));
              }
            }
          }).catch(() => {
          });
        }
        break;
      }

      case 'reportMessagesRead': {
        // MSG-104：scroll intent 路径的已读上报；执行侧再经节流（只增不减）。
        const report: ReportMessagesRead = effect as ReportMessagesRead;
        if (!this.destroyed && this.readThrottle.shouldReport(report.messageId)) {
          this.sendReadReport([report.messageId]);
        }
        break;
      }

      case 'resendMessage': {
        // MSG-104：失败重发；响应失败回灌 OnMessageActionFailed（errorMessage 细条），
        // 成功无额外动作（updateMessageSendSucceeded/Failed 订阅结算）。
        const resend: ResendMessage = effect as ResendMessage;
        this.logger.info(TAG, 'resend_message',
          `chatId=${resend.chatId},messageId=${resend.messageId}`);
        const result: Result<TdPendingRequest, AppError> =
          this.projection.resendMessages([resend.messageId]);
        if (result.err) {
          this.logger.logError(TAG, result.error);
          this.dispatch(new OnMessageActionFailed(result.error));
        }
        if (result.ok) {
          result.value.promise.then((res: Result<TdWireObject, AppError>) => {
            if (res.err) {
              this.logger.logError(TAG, res.error);
              if (!this.destroyed) {
                this.dispatch(new OnMessageActionFailed(res.error));
              }
            }
          }).catch(() => {
          });
        }
        break;
      }

      case 'copyTextToClipboard': {
        // MSG-105：复制文本到系统剪贴板并弹出轻提示。
        const copy: CopyTextToClipboard = effect as CopyTextToClipboard;
        this.copyToClipboard(copy.text, copy.toastMessage);
        break;
      }

      case 'pickAndSendPhoto': {
        const pick: PickAndSendPhotoEffect = effect as PickAndSendPhotoEffect;
        this.handlePickAndSendPhoto(pick.replyToMessageId, pick.caption);
        break;
      }

      case 'pickAndSendFile': {
        const pick: PickAndSendFileEffect = effect as PickAndSendFileEffect;
        this.handlePickAndSendFile(pick.replyToMessageId, pick.caption);
        break;
      }

      case 'pickAndSendVideo': {
        // MEDIA-105：与选图同构，只是选择器换成视频并额外带上时长/宽高/缩略图。
        const pick: PickAndSendVideoEffect = effect as PickAndSendVideoEffect;
        this.handlePickAndSendVideo(pick.replyToMessageId, pick.caption);
        break;
      }

      case 'cancelMediaDownload': {
        const cancel: CancelMediaDownloadEffect = effect as CancelMediaDownloadEffect;
        this.cancelMediaDownload(cancel.fileId);
        break;
      }

      case 'fetchChatSearch': {
        const search: FetchChatSearch = effect as FetchChatSearch;
        this.logger.info(TAG, 'fetch_chat_search',
          `chatId=${search.chatId},from=${search.fromMessageId}`);
        const result: Result<TdPendingRequest, AppError> =
          this.projection.searchMessages(search.query, search.fromMessageId, CHAT_SEARCH_LIMIT);
        if (result.err) {
          this.logger.logError(TAG, result.error);
          this.dispatch(new OnChatSearchFailed(result.error));
        }
        if (result.ok) {
          result.value.promise.then((res: Result<TdWireObject, AppError>) => {
            if (this.destroyed) {
              return;
            }
            if (res.err) {
              this.logger.logError(TAG, res.error);
              this.dispatch(new OnChatSearchFailed(res.error));
            }
            if (res.ok) {
              const found: FoundChatMessages | null = decodeFoundChatMessages(res.value as TdJsonRaw);
              if (found === null) {
                this.dispatch(new OnChatSearchFailed(
                  AppErrors.internal('chat.search_decode', 'failed to decode foundChatMessages')
                ));
                return;
              }
              const items: ChatSearchResultItem[] = [];
              for (let i = 0; i < found.messages.length; i++) {
                const msg: Message = found.messages[i];
                const snippet: string = messageContentText(msg.content);
                const jumpable: boolean = this.projection.getMessageById(msg.id) !== undefined;
                items.push(new ChatSearchResultItem(
                  msg.id,
                  snippet,
                  formatSearchResultDate(msg.date),
                  jumpable
                ));
              }
              this.logger.info(TAG, 'chat_search_ok',
                `chatId=${search.chatId},hits=${items.length}`);
              this.dispatch(new OnChatSearchLoaded(items));
            }
          }).catch(() => {
          });
        }
        break;
      }

      case 'jumpToMessage': {
        const jump: JumpToMessage = effect as JumpToMessage;
        // SEARCH-102：与"进会话定位"共用同一条待跳转通道（投影忙时排队而非放弃）。
        this.requestJumpToMessage(jump.messageId);
        break;
      }

      case 'joinChannel': {
        this.logger.info(TAG, 'join_channel', `chatId=${this.currentState.chatId}`);
        const result: Result<TdPendingRequest, AppError> = this.projection.joinChat();
        if (result.err) {
          this.logger.logError(TAG, result.error);
        }
        if (result.ok) {
          result.value.promise.then((res: Result<TdWireObject, AppError>) => {
            if (this.destroyed) {
              return;
            }
            if (res.err) {
              this.logger.logError(TAG, res.error);
            }
            if (res.ok) {
              this.logger.info(TAG, 'join_channel_ok', `chatId=${this.currentState.chatId}`);
              this.dispatch(new OnChannelMemberStatusChanged(true));
            }
          }).catch(() => {
          });
        }
        break;
      }

      case 'toggleReaction': {
        const tr: ToggleReactionEffect = effect as ToggleReactionEffect;
        this.logger.info(TAG, 'toggle_reaction', `messageId=${tr.messageId},emoji=${tr.emoji},isChosen=${tr.isChosen}`);
        const result: Result<TdPendingRequest, AppError> = tr.isChosen
          ? this.projection.addMessageReaction(tr.messageId, tr.emoji)
          : this.projection.removeMessageReaction(tr.messageId, tr.emoji);
        if (result.err) {
          this.logger.logError(TAG, result.error);
        }
        break;
      }

      case 'openComments': {
        const oc: OpenCommentsEffect = effect as OpenCommentsEffect;
        this.logger.info(TAG, 'open_comments', `chatId=${oc.chatId},messageId=${oc.messageId}`);
        this.onOpenComments(oc.chatId, oc.messageId);
        break;
      }

      case 'fetchStickerSet': {
        const fetchSticker: FetchStickerSet = effect as FetchStickerSet;
        this.handleFetchStickerSet(fetchSticker.setId);
        break;
      }

      case 'changeStickerSetEffect': {
        const changeSticker: ChangeStickerSetEffect = effect as ChangeStickerSetEffect;
        this.handleChangeStickerSet(changeSticker.setId, changeSticker.isInstalled);
        break;
      }

      case 'sendStickerMessage': {
        const sendSticker: SendStickerMessage = effect as SendStickerMessage;
        this.handleSendSticker(sendSticker);
        break;
      }

      case 'sendAnimationMessage': {
        const sendAnimation: SendAnimationMessage = effect as SendAnimationMessage;
        this.handleSendAnimation(sendAnimation);
        break;
      }

      case 'startVoiceRecordEffect': {
        this.handleStartVoiceRecord();
        break;
      }

      case 'stopAndSendVoiceRecordEffect': {
        const stopEffect: StopAndSendVoiceRecordEffect = effect as StopAndSendVoiceRecordEffect;
        this.handleStopAndSendVoiceRecord(stopEffect.replyToMessageId);
        break;
      }

      case 'cancelVoiceRecordEffect': {
        this.handleCancelVoiceRecord();
        break;
      }

      case 'playVoiceNoteEffect': {
        const playEffect: PlayVoiceNoteEffect = effect as PlayVoiceNoteEffect;
        this.handlePlayVoiceNote(playEffect);
        break;
      }

      case 'pauseVoiceNoteEffect': {
        const pauseEffect: PauseVoiceNoteEffect = effect as PauseVoiceNoteEffect;
        this.handlePauseVoiceNote(pauseEffect);
        break;
      }

      case 'sendPoll': {
        const sendPoll: SendPollEffect = effect as SendPollEffect;
        this.handleSendPoll(sendPoll);
        break;
      }

      case 'setPollAnswer': {
        const voteEffect: SetPollAnswerEffect = effect as SetPollAnswerEffect;
        this.handleSetPollAnswer(voteEffect);
        break;
      }

      default:
        break;
    }
  }

  /** MEDIA-102：调起相册选取图片并发送 */
  public pickAndSendPhoto(): void {
    this.dispatch(new PickAndSendPhoto());
  }

  /** MEDIA-104：调起文件选择器选取通用文件并发送 */
  public pickAndSendFile(): void {
    this.dispatch(new PickAndSendFile());
  }

  /** MEDIA-105：调起相册选取视频并发送 */
  public pickAndSendVideo(): void {
    this.dispatch(new PickAndSendVideo());
  }

  /** FILE-103：取消正在下载的媒体文件 */
  public cancelMediaDownload(fileId: number): Result<TdPendingRequest, AppError> {
    this.requestedFileIds.delete(fileId);
    const result: Result<TdPendingRequest, AppError> = this.fileRegistry.cancelDownloadFile(fileId);
    this.scheduleSyncFromProjection();
    return result;
  }

  /** MEDIA-102 / MEDIA-104：取消正在上传或待发送的媒体消息 */
  public cancelMediaUpload(messageId: number): Result<TdPendingRequest, AppError> {
    return this.projection.deleteMessages([messageId], true);
  }

  private async handlePickAndSendPhoto(replyToMessageId: number = 0, caption: string = ''): Promise<void> {
    try {
      const pickedMedia: PickedMedia[] = await this.mediaPickerPort.pickPhoto(1);
      if (this.destroyed || pickedMedia.length === 0) {
        return;
      }
      const picked: PickedMedia = pickedMedia[0];
      const path: string = (picked.path !== undefined && picked.path.length > 0) ? picked.path : picked.uri;
      if (path.length === 0) {
        return;
      }
      this.dispatch(new ComposerTextChanged(''));
      if (this.currentState.composerMode !== null) {
        this.dispatch(new CancelComposerMode());
      }
      const result: Result<TdPendingRequest, AppError> = this.projection.sendPhotoMessage(
        path,
        caption.length > 0 ? caption : undefined,
        replyToMessageId
      );
      this.projection.clearChatDraftMessage();
      if (result.err) {
        this.logger.logError(TAG, result.error);
        this.dispatch(new OnMessageSendFailed(result.error));
      }
      if (result.ok) {
        result.value.promise.then((res: Result<TdWireObject, AppError>) => {
          if (res.err) {
            this.logger.logError(TAG, res.error);
            if (!this.destroyed) {
              this.dispatch(new OnMessageSendFailed(res.error));
            }
          } else {
            this.logger.info(TAG, 'send_photo_message_ok', `chatId=${this.currentState.chatId}`);
          }
        }).catch(() => {});
      }
    } catch (err) {
      this.logger.error(TAG, 'pick_photo_error', String(err));
    }
  }

  private async handlePickAndSendFile(replyToMessageId: number = 0, caption: string = ''): Promise<void> {
    try {
      const pickedMedia: PickedMedia[] = await this.mediaPickerPort.pickFile(1);
      if (this.destroyed || pickedMedia.length === 0) {
        return;
      }
      const picked: PickedMedia = pickedMedia[0];
      const path: string = (picked.path !== undefined && picked.path.length > 0) ? picked.path : picked.uri;
      if (path.length === 0) {
        return;
      }
      this.dispatch(new ComposerTextChanged(''));
      if (this.currentState.composerMode !== null) {
        this.dispatch(new CancelComposerMode());
      }
      const result: Result<TdPendingRequest, AppError> = this.projection.sendDocumentMessage(
        path,
        caption.length > 0 ? caption : undefined,
        replyToMessageId
      );
      this.projection.clearChatDraftMessage();
      if (result.err) {
        this.logger.logError(TAG, result.error);
        this.dispatch(new OnMessageSendFailed(result.error));
      }
      if (result.ok) {
        result.value.promise.then((res: Result<TdWireObject, AppError>) => {
          if (res.err) {
            this.logger.logError(TAG, res.error);
            if (!this.destroyed) {
              this.dispatch(new OnMessageSendFailed(res.error));
            }
          } else {
            this.logger.info(TAG, 'send_document_message_ok', `chatId=${this.currentState.chatId}`);
          }
        }).catch(() => {});
      }
    } catch (err) {
      this.logger.error(TAG, 'pick_file_error', String(err));
    }
  }

  /**
   * MEDIA-105（FEAT-MEDIA-002 发侧）：调起相册选视频 → sendVideoMessage。
   *
   * 与选图/选文件同构，差异在于：
   * - 选择器走 pickVideo，额外带回 duration / width / height / thumbnailPath
   *   （后三者由 entry 适配器用 AVMetadataExtractor + AVImageGenerator 取得）；
   * - 缩略图先登记进 pendingVideoThumbnails，让出站气泡立刻有图可显；
   * - 元数据缺失（模拟器抽帧失败等）不算错误，照常发送，
   *   TDLib 会自行探测，气泡退化为首帧占位。
   */
  private async handlePickAndSendVideo(replyToMessageId: number = 0, caption: string = ''): Promise<void> {
    try {
      const pickedMedia: PickedMedia[] = await this.mediaPickerPort.pickVideo(1);
      if (this.destroyed || pickedMedia.length === 0) {
        return;
      }
      const picked: PickedMedia = pickedMedia[0];
      const path: string = (picked.path !== undefined && picked.path.length > 0) ? picked.path : picked.uri;
      if (path.length === 0) {
        return;
      }
      const thumbnailPath: string | undefined =
        (picked.thumbnailPath !== undefined && picked.thumbnailPath.length > 0) ? picked.thumbnailPath : undefined;
      if (thumbnailPath !== undefined) {
        this.pendingVideoThumbnails.set(path, thumbnailPath);
      }

      this.dispatch(new ComposerTextChanged(''));
      if (this.currentState.composerMode !== null) {
        this.dispatch(new CancelComposerMode());
      }
      const result: Result<TdPendingRequest, AppError> = this.projection.sendVideoMessage(
        path,
        caption.length > 0 ? caption : undefined,
        replyToMessageId,
        picked.duration !== undefined ? picked.duration : 0,
        picked.width !== undefined ? picked.width : 0,
        picked.height !== undefined ? picked.height : 0,
        thumbnailPath,
        picked.thumbnailWidth !== undefined ? picked.thumbnailWidth : 0,
        picked.thumbnailHeight !== undefined ? picked.thumbnailHeight : 0
      );
      this.projection.clearChatDraftMessage();
      if (result.err) {
        this.logger.logError(TAG, result.error);
        this.dispatch(new OnMessageSendFailed(result.error));
      }
      if (result.ok) {
        result.value.promise.then((res: Result<TdWireObject, AppError>) => {
          if (res.err) {
            this.logger.logError(TAG, res.error);
            if (!this.destroyed) {
              this.dispatch(new OnMessageSendFailed(res.error));
            }
          } else {
            this.logger.info(TAG, 'send_video_message_ok', `chatId=${this.currentState.chatId}`);
          }
        }).catch(() => {});
      }
    } catch (err) {
      this.logger.error(TAG, 'pick_video_error', String(err));
    }
  }

  /** MSG-105：复制文本到系统剪贴板并弹出 Toast 提示。 */
  private copyToClipboard(text: string, toastMessage: string): void {
    this.clipboardPort.setPlainText(text).then(() => {
      this.logger.info(TAG, 'copy_to_clipboard_success', `len=${text.length}`);
      try {
        this.toastPort.showToast(toastMessage, 2000);
      } catch (toastErr) {
        this.logger.warn(TAG, 'toast_show_exception', String(toastErr));
      }
    }).catch((err: Object) => {
      this.logger.warn(TAG, 'clipboard_set_exception', String(err));
    });
  }

  private handleFetchStickerSet(setId: string): void {
    if (setId === '1' || setId === 'popular_hot_cherry') {
      const mockItems: StickerSetItem[] = [
        { id: 1001, fileId: 1001, emoji: '😎', width: 512, height: 512, localPath: null, thumbnailPath: null, isDownloaded: true, isDownloading: false },
        { id: 1002, fileId: 1002, emoji: '🎉', width: 512, height: 512, localPath: null, thumbnailPath: null, isDownloaded: true, isDownloading: false },
        { id: 1003, fileId: 1003, emoji: '🚀', width: 512, height: 512, localPath: null, thumbnailPath: null, isDownloaded: true, isDownloading: false },
        { id: 1004, fileId: 1004, emoji: '🔥', width: 512, height: 512, localPath: null, thumbnailPath: null, isDownloaded: true, isDownloading: false },
        { id: 1005, fileId: 1005, emoji: '👍', width: 512, height: 512, localPath: null, thumbnailPath: null, isDownloaded: true, isDownloading: false },
        { id: 1006, fileId: 1006, emoji: '❤️', width: 512, height: 512, localPath: null, thumbnailPath: null, isDownloaded: true, isDownloading: false },
        { id: 1007, fileId: 1007, emoji: '☕', width: 512, height: 512, localPath: null, thumbnailPath: null, isDownloaded: true, isDownloading: false },
        { id: 1008, fileId: 1008, emoji: '⭐', width: 512, height: 512, localPath: null, thumbnailPath: null, isDownloaded: true, isDownloading: false },
        { id: 1009, fileId: 1009, emoji: '👏', width: 512, height: 512, localPath: null, thumbnailPath: null, isDownloaded: true, isDownloading: false },
        { id: 1010, fileId: 1010, emoji: '🥳', width: 512, height: 512, localPath: null, thumbnailPath: null, isDownloaded: true, isDownloading: false },
        { id: 1011, fileId: 1011, emoji: '🌟', width: 512, height: 512, localPath: null, thumbnailPath: null, isDownloaded: true, isDownloading: false },
        { id: 1012, fileId: 1012, emoji: '🎯', width: 512, height: 512, localPath: null, thumbnailPath: null, isDownloaded: true, isDownloading: false },
        { id: 1013, fileId: 1013, emoji: '🏆', width: 512, height: 512, localPath: null, thumbnailPath: null, isDownloaded: true, isDownloading: false },
        { id: 1014, fileId: 1014, emoji: '💡', width: 512, height: 512, localPath: null, thumbnailPath: null, isDownloaded: true, isDownloading: false },
        { id: 1015, fileId: 1015, emoji: '✨', width: 512, height: 512, localPath: null, thumbnailPath: null, isDownloaded: true, isDownloading: false }
      ];
      const preview: StickerSetPreviewState = new StickerSetPreviewState(
        setId,
        'Hot Cherry',
        'HotCherry',
        false,
        false,
        true,
        mockItems,
        false,
        false,
        null
      );
      this.dispatch(new OnStickerSetLoaded(preview));
      return;
    }

    const req: GetStickerSet = new GetStickerSet();
    req.set_id = setId;
    const result: Result<TdPendingRequest, AppError> =
      this.scope.request('getStickerSet', encodeGetStickerSet(req) as TdWireObject);
    if (result.err) {
      this.logger.logError(TAG, result.error);
      this.dispatch(new OnStickerSetLoadFailed(setId, result.error.message));
    }
    if (result.ok) {
      result.value.promise.then((res: Result<TdWireObject, AppError>) => {
        if (res.err) {
          this.logger.logError(TAG, res.error);
          if (!this.destroyed) {
            this.dispatch(new OnStickerSetLoadFailed(setId, res.error.message));
          }
        }
        if (res.ok) {
          if (this.destroyed) {
            return;
          }
          const set: StickerSet | null = decodeStickerSet(res.value as TdJsonRaw);
          if (set === null) {
            this.dispatch(new OnStickerSetLoadFailed(setId, 'Failed to decode sticker set'));
            return;
          }
          const items: StickerSetItem[] = [];
          for (let i = 0; i < set.stickers.length; i++) {
            const s: Sticker = set.stickers[i];
            const targetFile: File | null = s.sticker;
            const thumbFile: File | null = (s.thumbnail !== null) ? s.thumbnail.file : null;
            const fileId: number = targetFile !== null ? targetFile.id : 0;
            const thumbId: number = thumbFile !== null ? thumbFile.id : 0;
            const localPath: string | null = fileId > 0 ? this.fileRegistry.getLocalPath(fileId) : null;
            const thumbPath: string | null = thumbId > 0 ? this.fileRegistry.getLocalPath(thumbId) : null;
            const isDownloaded: boolean = fileId > 0 ? this.fileRegistry.isDownloaded(fileId) : false;

            if (thumbId > 0 && thumbPath === null) {
              this.requestMediaDownload(thumbId, 2);
            }
            if (fileId > 0 && !isDownloaded) {
              this.requestMediaDownload(fileId, 1);
            }

            items.push({
              id: fileId,
              fileId: fileId,
              emoji: s.emoji,
              width: s.width,
              height: s.height,
              localPath: localPath,
              thumbnailPath: thumbPath,
              isDownloaded: isDownloaded,
              isDownloading: false
            });
          }
          const preview: StickerSetPreviewState = new StickerSetPreviewState(
            setId,
            set.title,
            set.name,
            set.is_installed,
            set.is_archived,
            set.is_official,
            items,
            false,
            false,
            null
          );
          this.dispatch(new OnStickerSetLoaded(preview));
        }
      }).catch(() => {
      });
    }
  }

  private handleChangeStickerSet(setId: string, isInstalled: boolean): void {
    if (setId === '1' || setId === 'popular_hot_cherry') {
      this.dispatch(new OnStickerSetChanged(setId, isInstalled));
      return;
    }

    const req: ChangeStickerSet = new ChangeStickerSet();
    req.set_id = setId;
    req.is_installed = isInstalled;
    req.is_archived = false;
    const result: Result<TdPendingRequest, AppError> =
      this.scope.request('changeStickerSet', encodeChangeStickerSet(req) as TdWireObject);
    if (result.err) {
      this.logger.logError(TAG, result.error);
      this.dispatch(new OnStickerSetActionFailed(setId, result.error.message));
    }
    if (result.ok) {
      result.value.promise.then((res: Result<TdWireObject, AppError>) => {
        if (res.err) {
          this.logger.logError(TAG, res.error);
          if (!this.destroyed) {
            this.dispatch(new OnStickerSetActionFailed(setId, res.error.message));
          }
        }
        if (res.ok) {
          if (!this.destroyed) {
            this.dispatch(new OnStickerSetChanged(setId, isInstalled));
          }
        }
      }).catch(() => {
      });
    }
  }

  /** POLL-101：发送投票消息（投影层组 InputMessagePoll 走 sendMessage）。 */
  private handleSendPoll(sendPoll: SendPollEffect): void {
    const result: Result<TdPendingRequest, AppError> = this.projection.sendPollMessage(
      sendPoll.question,
      sendPoll.options,
      sendPoll.isAnonymous,
      sendPoll.allowsMultiple
    );
    if (result.err) {
      this.logger.logError(TAG, result.error);
      this.dispatch(new OnMessageSendFailed(result.error));
    }
    if (result.ok) {
      result.value.promise.then((res: Result<TdWireObject, AppError>) => {
        if (res.err) {
          this.logger.logError(TAG, res.error);
          if (!this.destroyed) {
            this.dispatch(new OnMessageSendFailed(res.error));
          }
        }
        if (res.ok) {
          this.logger.info(TAG, 'send_poll_ok');
        }
      }).catch(() => {
      });
    }
  }

  /** POLL-101：投票（setPollAnswer）。失败只记日志 + toast，选中态以服务端回灌为准。 */
  private handleSetPollAnswer(vote: SetPollAnswerEffect): void {
    const result: Result<TdPendingRequest, AppError> =
      this.projection.setPollAnswer(vote.messageId, vote.optionIds);
    if (result.err) {
      this.logger.logError(TAG, result.error);
      this.toastPort.showToast('投票失败');
    }
    if (result.ok) {
      result.value.promise.then((res: Result<TdWireObject, AppError>) => {
        if (res.err) {
          this.logger.logError(TAG, res.error);
          if (!this.destroyed) {
            this.toastPort.showToast('投票失败');
          }
        }
        if (res.ok) {
          this.logger.info(TAG, 'set_poll_answer_ok', `messageId=${vote.messageId}`);
        }
      }).catch(() => {
      });
    }
  }

  private handleSendSticker(sendSticker: SendStickerMessage): void {
    if (sendSticker.fileId >= 1001 && sendSticker.fileId <= 1045) {
      this.projection.sendTextMessage(sendSticker.emoji, 0);
      return;
    }

    const req: SendMessage = new SendMessage();
    req.chat_id = sendSticker.chatId;
    const inputSticker: InputSticker = new InputSticker();
    const inputFileId: InputFileId = new InputFileId();
    inputFileId.id = sendSticker.fileId;
    inputSticker.sticker = inputFileId;
    inputSticker.width = sendSticker.width;
    inputSticker.height = sendSticker.height;
    const content: InputMessageSticker = new InputMessageSticker();
    content.sticker = inputSticker;
    content.emoji = sendSticker.emoji;
    req.input_message_content = content;
    const result: Result<TdPendingRequest, AppError> =
      this.scope.request('sendMessage', encodeSendMessage(req) as TdWireObject);
    if (result.err) {
      this.logger.logError(TAG, result.error);
      this.dispatch(new OnMessageSendFailed(result.error));
    }
    if (result.ok) {
      result.value.promise.then((res: Result<TdWireObject, AppError>) => {
        if (res.err) {
          this.logger.logError(TAG, res.error);
          if (!this.destroyed) {
            this.dispatch(new OnMessageSendFailed(res.error));
          }
        }
        if (res.ok) {
          this.logger.info(TAG, 'send_sticker_ok', `fileId=${sendSticker.fileId}`);
        }
      }).catch(() => {
      });
    }
  }

  private handleSendAnimation(sendAnimation: SendAnimationMessage): void {
    if (sendAnimation.fileId >= 2001 && sendAnimation.fileId <= 2040) {
      this.projection.sendTextMessage(`🎬 ${sendAnimation.caption || 'GIF'}`, 0);
      return;
    }

    this.logger.info(TAG, 'send_animation', `fileId=${sendAnimation.fileId}`);
  }

  /** null = 投影侧跳过（正在加载/已到顶端）；请求级与响应级失败都回灌 OnMessagesLoadFailed。 */
  private runFetch(result: Result<TdPendingRequest, AppError> | null): void {
    if (result === null) {
      return;
    }
    if (result.err) {
      this.logger.logError(TAG, result.error);
      this.dispatch(new OnMessagesLoadFailed(result.error));
    }
    if (result.ok) {
      result.value.promise.then((res: Result<TdWireObject, AppError>) => {
        if (res.err) {
          this.logger.logError(TAG, res.error);
          if (!this.destroyed) {
            this.dispatch(new OnMessagesLoadFailed(res.error));
          }
        }
        if (res.ok) {
          const raw: TdWireValue | undefined = res.value['messages'];
          const count: number = (raw !== undefined && Array.isArray(raw)) ? (raw as TdWireObject[]).length : -1;
          this.logger.info(TAG, 'get_chat_history_ok', `count=${count}`);
        }
      }).catch(() => {
      });
    }
  }

  /** VOICE-101：开始语音录制 */
  public startVoiceRecord(): void {
    this.dispatch(new StartVoiceRecord());
  }

  /** VOICE-101：停止语音录制并发送 */
  public stopAndSendVoiceRecord(): void {
    this.dispatch(new StopAndSendVoiceRecord());
  }

  /** VOICE-101：取消语音录制 */
  public cancelVoiceRecord(): void {
    this.dispatch(new CancelVoiceRecord());
  }

  /** VOICE-101：播放语音消息 */
  public playVoiceNote(messageId: number, fileId: number, localPath: string | null = null): void {
    this.dispatch(new PlayVoiceNote(messageId, fileId, localPath));
  }

  /** VOICE-101：暂停语音播放 */
  public pauseVoiceNote(messageId: number): void {
    this.dispatch(new PauseVoiceNote(messageId));
  }

  private async handleStartVoiceRecord(): Promise<void> {
    try {
      if (this.recordTimerId !== -1) {
        clearInterval(this.recordTimerId);
        this.recordTimerId = -1;
      }
      this.recordingSeconds = 0;
      const outputPath: string = `${this.cacheDir}/voice_${Date.now()}.m4a`;
      await this.audioRecorderPort.startRecord(outputPath);
      this.recordTimerId = setInterval(() => {
        if (this.destroyed || !this.currentState.isRecordingVoice) {
          if (this.recordTimerId !== -1) {
            clearInterval(this.recordTimerId);
            this.recordTimerId = -1;
          }
          return;
        }
        this.recordingSeconds++;
        this.dispatch(new VoiceRecordTick(this.recordingSeconds));
      }, 1000);
    } catch (e) {
      const reason: string = String(e);
      this.logger.error(TAG, 'start_voice_record_failed', reason);
      // 麦克风权限是最常见且唯一「用户可自救」的失败原因，单独给可操作提示。
      this.toastPort.showToast(
        reason.indexOf(ERR_MIC_PERMISSION_DENIED) >= 0 ? '需要麦克风权限才能录音' : '无法开始录音',
        2000
      );
      this.dispatch(new CancelVoiceRecord());
    }
  }

  private async handleStopAndSendVoiceRecord(replyToMessageId: number): Promise<void> {
    try {
      if (this.recordTimerId !== -1) {
        clearInterval(this.recordTimerId);
        this.recordTimerId = -1;
      }
      const result = await this.audioRecorderPort.stopRecord();
      if (!result.filePath || result.filePath.length === 0) {
        return;
      }
      if (result.playable === false) {
        // 产物不可解码：宁可少发一条，也不要落地一条永远打不开的语音消息。
        this.logger.error(TAG, 'voice_record_unplayable', 'recording output is not decodable; skip send');
        this.toastPort.showToast('录音失败，未发送', 2000);
        return;
      }
      const durationSec: number = Math.max(1, Math.round(result.durationMs / 1000));
      const waveformStr: string = encodeWaveform(result.waveform);
      const sendRes: Result<TdPendingRequest, AppError> = this.projection.sendVoiceNoteMessage(
        result.filePath,
        durationSec,
        waveformStr,
        undefined,
        replyToMessageId
      );
      if (sendRes.err) {
        this.logger.logError(TAG, sendRes.error);
        this.dispatch(new OnMessageSendFailed(sendRes.error));
      }
    } catch (e) {
      this.logger.error(TAG, 'stop_voice_record_failed', String(e));
    }
  }

  private async handleCancelVoiceRecord(): Promise<void> {
    try {
      if (this.recordTimerId !== -1) {
        clearInterval(this.recordTimerId);
        this.recordTimerId = -1;
      }
      await this.audioRecorderPort.cancelRecord();
    } catch (e) {
      this.logger.error(TAG, 'cancel_voice_record_failed', String(e));
    }
  }

  private async handlePlayVoiceNote(effect: PlayVoiceNoteEffect): Promise<void> {
    try {
      let localPath: string | null = effect.localPath;
      if (!localPath || localPath.length === 0) {
        if (effect.fileId > 0) {
          const cachedFile = this.fileRegistry.getFile(effect.fileId);
          if (cachedFile !== null && cachedFile.local !== null && cachedFile.local.is_downloading_completed && cachedFile.local.path.length > 0) {
            localPath = cachedFile.local.path;
          } else {
            // 触发下载并提示
            this.fileRegistry.downloadFile(effect.fileId, 32);
            this.toastPort.showToast('正在下载语音消息...', 1000);
            return;
          }
        }
      }
      if (!localPath || localPath.length === 0) {
        this.dispatch(new VoicePlaybackFailed(effect.messageId, '语音文件不可用'));
        return;
      }

      await this.audioPlayerPort.play(
        localPath,
        (currentMs: number, totalMs: number): void => {
          if (!this.destroyed && this.currentState.playingVoiceMessageId === effect.messageId) {
            this.dispatch(new VoicePlaybackProgress(effect.messageId, currentMs, totalMs));
          }
        },
        (): void => {
          if (!this.destroyed && this.currentState.playingVoiceMessageId === effect.messageId) {
            this.dispatch(new VoicePlaybackCompleted(effect.messageId));
          }
        },
        (errMsg: string): void => {
          if (!this.destroyed && this.currentState.playingVoiceMessageId === effect.messageId) {
            this.dispatch(new VoicePlaybackFailed(effect.messageId, errMsg));
          }
        },
        // AUDIO-BG-101：锁屏卡片显「语音消息 — 会话名」。时长留 0，由播放器 prepared 后回填。
        new AudioPlaybackMetadata(`${effect.messageId}`, '语音消息', this.currentState.chatTitle, 0)
      );
    } catch (e) {
      this.logger.error(TAG, 'play_voice_note_failed', String(e));
      this.dispatch(new VoicePlaybackFailed(effect.messageId, String(e)));
    }
  }

  private async handlePauseVoiceNote(effect: PauseVoiceNoteEffect): Promise<void> {
    try {
      await this.audioPlayerPort.pause();
    } catch (e) {
      this.logger.error(TAG, 'pause_voice_note_failed', String(e));
    }
  }
}

/** MSG-103：判断两个毫秒时间戳是否在同一自然日（本地时区同年月日）。 */
export function isSameDay(t1Ms: number, t2Ms: number): boolean {
  const d1: Date = new Date(t1Ms);
  const d2: Date = new Date(t2Ms);
  return d1.getFullYear() === d2.getFullYear() &&
    d1.getMonth() === d2.getMonth() &&
    d1.getDate() === d2.getDate();
}

/** MSG-103：对齐 Telegram X 规范（Lang.getDate），当年输出 "M月d日"，跨年输出 "yyyy年M月d日"。 */
export function formatDateHeader(timestampMs: number): string {
  const date: Date = new Date(timestampMs);
  const now: Date = new Date();
  const month: number = date.getMonth() + 1;
  const day: number = date.getDate();
  if (date.getFullYear() === now.getFullYear()) {
    return `${month}月${day}日`;
  }
  return `${date.getFullYear()}年${month}月${day}日`;
}
