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
 * - TDLib 更新成批到达，经 setTimeout(0) 合并为一个同步点，避免反复重绘。
 * - 日志不记录消息正文，send 结果只记 ok/err 与稳定错误分类。
 *
 * 生命周期：start() 打开会话（openChat + 首屏加载），destroy() 关闭（closeChat）。
 */

import { Logger } from '@tgx/observability';
import { ClipboardPort, ToastPort, MediaPickerPort, PickedMedia, FakeClipboard, FakeToast, FakeMediaPicker } from '@tgx/platform-ports';
import { ManualClock, SequentialIdGenerator, AppError, AppErrors } from '@tgx/core-common';
import { AccountScope } from '@tgx/core-account';
import {
  Animation,
  Chat,
  decodeChat,
  decodeMessage,
  decodeMessageProperties,
  DraftMessage,
  DraftMessageContentText,
  encodeGetChat,
  encodeGetMessage,
  File,
  GetChat,
  GetMessage,
  InputMessageReplyToMessage,
  Message,
  MessageAnimation,
  MessagePhoto,
  MessageProperties,
  MessageReplyToMessage,
  MessageSticker,
  MessageText,
  MessageVideo,
  MessageVideoNote,
  Photo,
  PhotoSize,
  Sticker,
  TdJsonRaw,
  TdMessageContent,
  TdMessageReplyTo,
  TdMessageSendingState,
  User,
  Video,
  VideoNote
} from '@tgx/core-td-api-generated';
import { FileRegistry, MessageListState, MessageProjection, UserRegistry } from '@tgx/core-domain';
import { TdPendingRequest, TdWireObject, TdWireValue } from '@tgx/td-gateway';
import { Subscription } from '@tgx/platform-ports';
import { Result } from '@tgx/core-common';
import { ReducerEnv, ReducerResult } from '@tgx/feature-template';
import { MessageItem, MessageSendState } from '../model/MessageItem';
import { MessageTextSpan } from '../model/MessageTextSpan';
import { MediaAttachment } from '../model/MediaAttachment';
import { parseFormattedText } from '../model/FormattedTextParser';
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
  ComposerTextChanged,
  CancelComposerMode,
  RestoreDraft
} from '../contract/ChatIntent';
import {
  ChatEffect,
  SendTextMessage,
  FetchMessagePermissions,
  EditMessageText,
  DeleteMessages,
  OpenForwardPicker,
  ForwardMessages,
  ReportMessagesRead,
  ResendMessage,
  CopyTextToClipboard,
  PickAndSendPhotoEffect
} from '../contract/ChatEffect';
import { isOutgoingMessageRead, ReadReportThrottle } from '../model/ReadReceipt';
import { chatReducer } from '../reducer/ChatReducer';

const TAG: string = 'ChatCoordinator';
const INITIAL_PAGE_SIZE: number = 30;
const OLDER_PAGE_SIZE: number = 20;
/** 消息数低于该值且未到历史顶端时自动补拉。 */
const BACKFILL_THRESHOLD: number = 20;
/** 补拉延迟：给 TDLib 后台 preload 留时间窗（服务器往返 1-2s）。 */
const BACKFILL_DELAY_MS: number = 900;

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
  private readonly logger: Logger;
  private readonly onBack: () => void;
  /** MSG-106：请求装配层弹出转发目标会话选择器（缺省 no-op）。 */
  private readonly onOpenForwardPicker: (messageIds: number[]) => void;
  private currentState: ChatUiState;
  private readonly listeners: ChatUiStateListener[] = [];
  private syncScheduled: boolean = false;
  private throttledSyncScheduled: boolean = false;
  private backfillScheduled: boolean = false;
  private destroyed: boolean = false;
  /** MSG-102：会话种类（getChat 一次性解析，群聊才出署名）。 */
  private chatKind: ChatKind = 'unknown';
  private chatTypeRequested: boolean = false;
  /** MSG-102：已发起过 getUser 的 sender，防重复请求。 */
  private readonly requestedSenderIds: Set<number> = new Set();
  private readonly senderSubscriptions: Map<number, Subscription> = new Map();
  /** MEDIA-101/105：文件下载更新订阅。 */
  private readonly fileSubscriptions: Map<number, Subscription> = new Map();
  /** 已下发过 downloadFile 的文件 id 集合，防重复请求风暴。 */
  private readonly requestedFileIds: Set<number> = new Set();
  /** MSG-104：已读上报节流（lastReported 只增不减）。 */
  private readonly readThrottle: ReadReportThrottle = new ReadReportThrottle();
  /** 回复引用消息详情已发起过 getMessage 的 messageId 集合，防重复请求。 */
  private readonly requestedReplyIds: Set<number> = new Set();
  /** MSG-103：进入会话时的首条未读消息 id（锁定后会话内保持书签不消失，重进或无未读时为 null）。 */
  private firstUnreadMessageId: number | null = null;
  private initialUnreadResolved: boolean = false;

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
    this.dispatch(new LoadInitialMessages());
  }

  /** COMPOSER-101：立即保存当前输入栏中的草稿至 TDLib。 */
  public saveDraftNow(): void {
    const text: string = this.currentState.composerText;
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
      this.requestMediaDownload(reqIntent.fileId, 32);
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
    if (this.requestedFileIds.has(fileId)) {
      return;
    }
    this.requestedFileIds.add(fileId);

    if (!this.fileSubscriptions.has(fileId)) {
      const sub: Subscription = this.fileRegistry.subscribeFile(fileId, (file: File) => {
        if (!this.destroyed) {
          if (file.local !== null && file.local.is_downloading_completed) {
            this.scheduleSyncFromProjection();
          } else {
            this.scheduleThrottledSync();
          }
        }
      });
      this.fileSubscriptions.set(fileId, sub);
    }
    this.fileRegistry.downloadFile(fileId, priority);
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
      const localPath: string | null = this.fileRegistry.getLocalPath(fileId);
      const isDownloaded: boolean = this.fileRegistry.isDownloaded(fileId);
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
      const localPath: string | null = this.fileRegistry.getLocalPath(fileId);
      const isDownloaded: boolean = this.fileRegistry.isDownloaded(fileId);
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
      const localPath: string | null = this.fileRegistry.getLocalPath(fileId);
      const isDownloaded: boolean = this.fileRegistry.isDownloaded(fileId);
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

      // 视频较小（<= 10MB）自动下载，便于直接播放
      const videoSize: number = targetFile.size;
      if (!isDownloaded && !isDownloading && videoSize > 0 && videoSize <= 10 * 1024 * 1024) {
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
        videoContent.has_spoiler
      );
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
      const localPath: string | null = this.fileRegistry.getLocalPath(fileId);
      const isDownloaded: boolean = this.fileRegistry.isDownloaded(fileId);
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
        'video',
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
      const localPath: string | null = this.fileRegistry.getLocalPath(fileId);
      const isDownloaded: boolean = this.fileRegistry.isDownloaded(fileId);
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
        default: {
          summary = messageContentText(message.content);
          break;
        }
      }
    }

    return new ReplyInfo(summary, senderName, senderColorIndex, thumbnailPath, isSticker);
  }

  private mapMessageToItem(
    message: Message,
    replyInfoById: Map<number, ReplyInfo>,
    lastReadOutboxMessageId: number,
    showDateHeader: boolean = false,
    dateHeaderText: string = '',
    showUnreadSeparator: boolean = false
  ): MessageItem {
    const replyToId: number | null = repliedMessageIdOf(message.reply_to);
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
    const isTextMessage: boolean = message.content !== null && message.content.type === 'messageText';
    const media: MediaAttachment | null = this.resolveMediaAttachment(message);

    let spans: MessageTextSpan[] = [];
    let displayText: string = '';

    if (media !== null) {
      displayText = media.kind === 'sticker' ? '' : media.caption;
      spans = media.kind === 'sticker' ? [] : media.captionSpans;
    } else if (isTextMessage) {
      const textContent: MessageText = message.content as MessageText;
      displayText = textContent.text !== null ? textContent.text.text : '';
      spans = parseFormattedText(textContent.text);
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
      senderInfo.avatarPath
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
      albumMessageIds
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
            this.logger.info(TAG, 'chat_kind_resolved', `kind=${this.chatKind}`);
            this.scheduleSyncFromProjection();
          }
        }
      }).catch(() => {
      });
    }
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
              this.dispatch(new OnMessageActionMenuLoaded(
                fetch.messageId,
                props.can_be_edited,
                props.can_be_deleted_only_for_self,
                props.can_be_deleted_for_all_users,
                props.can_be_forwarded,
                props.can_be_saved
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

      default:
        break;
    }
  }

  /** MEDIA-102：调起相册选取图片并发送 */
  public pickAndSendPhoto(): void {
    this.dispatch(new PickAndSendPhoto());
  }

  /** MEDIA-102：取消正在上传或待发送的媒体消息 */
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
