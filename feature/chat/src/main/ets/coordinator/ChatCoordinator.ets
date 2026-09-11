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

import { hilog } from '@kit.PerformanceAnalysisKit';
import { ManualClock, SequentialIdGenerator, AppError, AppErrors } from '@tgx/core-common';
import { AccountScope } from '@tgx/core-account';
import {
  Animation,
  Chat,
  decodeChat,
  decodeMessageProperties,
  encodeGetChat,
  File,
  GetChat,
  Message,
  MessageAnimation,
  MessagePhoto,
  MessageProperties,
  MessageReplyToMessage,
  MessageText,
  MessageVideo,
  Photo,
  PhotoSize,
  TdJsonRaw,
  TdMessageContent,
  TdMessageReplyTo,
  TdMessageSendingState,
  User,
  Video
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
import { ChatUiState } from '../contract/ChatUiState';
import {
  ChatIntent,
  LoadInitialMessages,
  LoadOlderMessages,
  OnMessagesLoaded,
  OnMessagesLoadFailed,
  OnMessageSendFailed,
  OnMessageActionMenuLoaded,
  OnMessageActionFailed
} from '../contract/ChatIntent';
import {
  ChatEffect,
  SendTextMessage,
  FetchMessagePermissions,
  EditMessageText,
  DeleteMessages,
  ReportMessagesRead,
  ResendMessage
} from '../contract/ChatEffect';
import { isOutgoingMessageRead, ReadReportThrottle } from '../model/ReadReceipt';
import { chatReducer } from '../reducer/ChatReducer';

const DOMAIN: number = 0x0000;
const TAG: string = 'ChatCoordinator';
const INITIAL_PAGE_SIZE: number = 30;
const OLDER_PAGE_SIZE: number = 20;
/** 消息数低于该值且未到历史顶端时自动补拉。 */
const BACKFILL_THRESHOLD: number = 20;
/** 补拉延迟：给 TDLib 后台 preload 留时间窗（服务器往返 1-2s）。 */
const BACKFILL_DELAY_MS: number = 900;

export type ChatUiStateListener = (state: ChatUiState) => void;

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
    case 'messageSticker':
      return '[Sticker]';
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

export class ChatCoordinator {
  private readonly projection: MessageProjection;
  private readonly scope: AccountScope;
  private readonly userRegistry: UserRegistry;
  private readonly fileRegistry: FileRegistry;
  private readonly env: ReducerEnv;
  private readonly onBack: () => void;
  private currentState: ChatUiState;
  private readonly listeners: ChatUiStateListener[] = [];
  private syncScheduled: boolean = false;
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
  /** MSG-104：已读上报节流（lastReported 只增不减）。 */
  private readonly readThrottle: ReadReportThrottle = new ReadReportThrottle();

  constructor(
    scope: AccountScope,
    chatId: number,
    chatTitle: string,
    onBack?: () => void,
    env?: ReducerEnv
  ) {
    this.projection = new MessageProjection(chatId, scope);
    this.scope = scope;
    // UserRegistry 构造即 start（订阅 updateUser/updateUserStatus），destroy 时 stop。
    this.userRegistry = new UserRegistry(scope);
    // FileRegistry 构造即 start（订阅 updateFile），destroy 时 stop。
    this.fileRegistry = new FileRegistry(scope);
    this.onBack = onBack !== undefined ? onBack : (): void => {};
    this.env = env !== undefined ? env : {
      clock: new ManualClock(1000, 500),
      ids: new SequentialIdGenerator('chat-')
    };
    this.currentState = new ChatUiState(chatId, chatTitle, [], false, true, null, '', null, null);
  }

  get state(): ChatUiState {
    return this.currentState;
  }

  start(): void {
    this.projection.setOnStateChanged(() => {
      this.scheduleSyncFromProjection();
    });
    this.projection.start();
    this.fetchChatKind();
    this.dispatch(new LoadInitialMessages());
  }

  destroy(): void {
    this.destroyed = true;
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
    // 回复引用摘要：先建 id → 正文文本的查找表，原消息不在当前列表时摘要为空。
    const textById: Map<number, string> = new Map();
    for (let i = 0; i < projectionState.messages.length; i++) {
      const message: Message = projectionState.messages[i];
      textById.set(message.id, messageContentText(message.content));
    }
    const items: MessageItem[] = [];
    for (let i = 0; i < projectionState.messages.length; i++) {
      items.push(this.mapMessageToItem(projectionState.messages[i], textById,
        projectionState.lastReadOutboxMessageId));
    }
    this.dispatch(new OnMessagesLoaded(items, projectionState.hasMoreOlder));
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
    this.sendReadReport(target);
  }

  private sendReadReport(messageId: number): void {
    const result: Result<TdPendingRequest, AppError> = this.projection.markMessagesRead([messageId]);
    if (result.err) {
      hilog.error(DOMAIN, TAG, 'viewMessages rejected: %{public}s', AppErrors.toLogString(result.error));
      return;
    }
    if (result.ok) {
      result.value.promise.then((res: Result<TdWireObject, AppError>) => {
        if (res.err) {
          hilog.error(DOMAIN, TAG, 'viewMessages failed: %{public}s', AppErrors.toLogString(res.error));
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

  private requestMediaDownload(fileId: number): void {
    if (this.destroyed || fileId <= 0) {
      return;
    }
    if (this.fileRegistry.isDownloaded(fileId)) {
      return;
    }
    if (!this.fileSubscriptions.has(fileId)) {
      const sub: Subscription = this.fileRegistry.subscribeFile(fileId, (_file: File) => {
        if (!this.destroyed) {
          this.scheduleSyncFromProjection();
        }
      });
      this.fileSubscriptions.set(fileId, sub);
    }
    this.fileRegistry.downloadFile(fileId, 1);
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
      const displaySize: PhotoSize = sizes[sizes.length - 1];
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
          this.requestMediaDownload(thumbSize.photo.id);
        }
      }

      if (!isDownloaded && !isDownloading) {
        this.requestMediaDownload(fileId);
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
        photoContent.has_spoiler
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
          this.requestMediaDownload(anim.thumbnail.file.id);
        }
      }

      if (!isDownloaded && !isDownloading) {
        this.requestMediaDownload(fileId);
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
          this.requestMediaDownload(video.thumbnail.file.id);
        }
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

    return null;
  }

  private mapMessageToItem(message: Message, textById: Map<number, string>,
    lastReadOutboxMessageId: number): MessageItem {
    const replyToId: number | null = repliedMessageIdOf(message.reply_to);
    let replyToSummary: string = '';
    if (replyToId !== null) {
      const targetText: string | undefined = textById.get(replyToId);
      if (targetText !== undefined) {
        replyToSummary = targetText;
      }
    }
    const isTextMessage: boolean = message.content !== null && message.content.type === 'messageText';
    const media: MediaAttachment | null = this.resolveMediaAttachment(message);

    let spans: MessageTextSpan[] = [];
    let displayText: string = '';

    if (media !== null) {
      displayText = media.caption;
      spans = media.captionSpans;
    } else if (isTextMessage) {
      const textContent: MessageText = message.content as MessageText;
      displayText = textContent.text !== null ? textContent.text.text : '';
      spans = parseFormattedText(textContent.text);
    } else {
      displayText = messageContentText(message.content);
    }

    // MSG-102：群聊收到的用户消息出署名；未命中缓存时 requestSenderUser 拉取并订阅刷新。
    const senderInfo: SenderInfo = resolveSenderInfo(
      message.is_outgoing,
      this.chatKind,
      message.sender_id,
      {
        lookupUser: (userId: number): User | null => this.userRegistry.getUser(userId),
        requestUser: (userId: number): void => this.requestSenderUser(userId)
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
      media
    );
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
      hilog.error(DOMAIN, TAG, 'getChat rejected: %{public}s', AppErrors.toLogString(result.error));
      return;
    }
    if (result.ok) {
      result.value.promise.then((res: Result<TdWireObject, AppError>) => {
        if (this.destroyed) {
          return;
        }
        if (res.err) {
          hilog.error(DOMAIN, TAG, 'getChat failed: %{public}s', AppErrors.toLogString(res.error));
        }
        if (res.ok) {
          const chat: Chat | null = decodeChat(res.value as TdJsonRaw);
          if (chat !== null) {
            this.chatKind = chatKindOf(chat.type_);
            hilog.info(DOMAIN, TAG, 'chat kind resolved: %{public}s', this.chatKind);
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
      hilog.error(DOMAIN, TAG, 'requestUser rejected userId=%{public}s: %{public}s',
        `${userId}`, AppErrors.toLogString(result.error));
    }
  }

  private executeEffect(effect: ChatEffect): void {
    switch (effect.kind) {
      case 'fetchInitialMessages': {
        hilog.info(DOMAIN, TAG, 'fetch initial messages chatId=%{public}s', `${this.currentState.chatId}`);
        this.runFetch(this.projection.loadInitialMessages(INITIAL_PAGE_SIZE));
        break;
      }

      case 'fetchOlderMessages': {
        hilog.info(DOMAIN, TAG, 'fetch older messages chatId=%{public}s', `${this.currentState.chatId}`);
        this.runFetch(this.projection.loadOlderMessages(OLDER_PAGE_SIZE));
        break;
      }

      case 'sendTextMessage': {
        const send: SendTextMessage = effect as SendTextMessage;
        hilog.info(DOMAIN, TAG, 'send message chatId=%{public}s', `${send.chatId}`);
        const result: Result<TdPendingRequest, AppError> =
          this.projection.sendTextMessage(send.text, send.replyToMessageId);
        if (result.err) {
          hilog.error(DOMAIN, TAG, 'sendMessage rejected: %{public}s', AppErrors.toLogString(result.error));
          this.dispatch(new OnMessageSendFailed(result.error));
        }
        if (result.ok) {
          result.value.promise.then((res: Result<TdWireObject, AppError>) => {
            if (res.err) {
              hilog.error(DOMAIN, TAG, 'sendMessage failed: %{public}s', AppErrors.toLogString(res.error));
              if (!this.destroyed) {
                this.dispatch(new OnMessageSendFailed(res.error));
              }
            }
            if (res.ok) {
              hilog.info(DOMAIN, TAG, 'sendMessage ok chatId=%{public}s', `${send.chatId}`);
            }
          }).catch(() => {
          });
        }
        break;
      }

      case 'fetchMessagePermissions': {
        const fetch: FetchMessagePermissions = effect as FetchMessagePermissions;
        hilog.info(DOMAIN, TAG, 'fetch message permissions chatId=%{public}s messageId=%{public}s',
          `${fetch.chatId}`, `${fetch.messageId}`);
        const result: Result<TdPendingRequest, AppError> = this.projection.getMessageProperties(fetch.messageId);
        if (result.err) {
          hilog.error(DOMAIN, TAG, 'getMessageProperties rejected: %{public}s', AppErrors.toLogString(result.error));
          this.dispatch(new OnMessageActionFailed(result.error));
        }
        if (result.ok) {
          result.value.promise.then((res: Result<TdWireObject, AppError>) => {
            if (this.destroyed) {
              return;
            }
            if (res.err) {
              hilog.error(DOMAIN, TAG, 'getMessageProperties failed: %{public}s', AppErrors.toLogString(res.error));
              this.dispatch(new OnMessageActionFailed(res.error));
            }
            if (res.ok) {
              const props: MessageProperties | null = decodeMessageProperties(res.value as TdJsonRaw);
              if (props === null) {
                hilog.error(DOMAIN, TAG, 'getMessageProperties: undecodable response');
                this.dispatch(new OnMessageActionFailed(
                  AppErrors.internal('chat.message_properties_decode', 'failed to decode messageProperties')
                ));
                return;
              }
              this.dispatch(new OnMessageActionMenuLoaded(
                fetch.messageId,
                props.can_be_edited,
                props.can_be_deleted_only_for_self,
                props.can_be_deleted_for_all_users
              ));
            }
          }).catch(() => {
          });
        }
        break;
      }

      case 'editMessageText': {
        const edit: EditMessageText = effect as EditMessageText;
        hilog.info(DOMAIN, TAG, 'edit message chatId=%{public}s messageId=%{public}s',
          `${edit.chatId}`, `${edit.messageId}`);
        const result: Result<TdPendingRequest, AppError> =
          this.projection.editMessageText(edit.messageId, edit.text);
        if (result.err) {
          hilog.error(DOMAIN, TAG, 'editMessageText rejected: %{public}s', AppErrors.toLogString(result.error));
          this.dispatch(new OnMessageActionFailed(result.error));
        }
        if (result.ok) {
          result.value.promise.then((res: Result<TdWireObject, AppError>) => {
            if (res.err) {
              hilog.error(DOMAIN, TAG, 'editMessageText failed: %{public}s', AppErrors.toLogString(res.error));
              if (!this.destroyed) {
                this.dispatch(new OnMessageActionFailed(res.error));
              }
            }
            if (res.ok) {
              // 成功路径无动作：气泡由 updateMessageContent / updateMessageEdited 刷新。
              hilog.info(DOMAIN, TAG, 'editMessageText ok messageId=%{public}s', `${edit.messageId}`);
            }
          }).catch(() => {
          });
        }
        break;
      }

      case 'deleteMessages': {
        const del: DeleteMessages = effect as DeleteMessages;
        hilog.info(DOMAIN, TAG, 'delete messages chatId=%{public}s count=%{public}d revoke=%{public}s',
          `${del.chatId}`, del.messageIds.length, `${del.revoke}`);
        const result: Result<TdPendingRequest, AppError> =
          this.projection.deleteMessages(del.messageIds, del.revoke);
        if (result.err) {
          hilog.error(DOMAIN, TAG, 'deleteMessages rejected: %{public}s', AppErrors.toLogString(result.error));
          this.dispatch(new OnMessageActionFailed(result.error));
        }
        if (result.ok) {
          result.value.promise.then((res: Result<TdWireObject, AppError>) => {
            if (res.err) {
              hilog.error(DOMAIN, TAG, 'deleteMessages failed: %{public}s', AppErrors.toLogString(res.error));
              if (!this.destroyed) {
                this.dispatch(new OnMessageActionFailed(res.error));
              }
            }
            if (res.ok) {
              // 成功路径无动作：气泡由 updateDeleteMessages 移出列表。
              hilog.info(DOMAIN, TAG, 'deleteMessages ok chatId=%{public}s', `${del.chatId}`);
            }
          }).catch(() => {
          });
        }
        break;
      }

      case 'navigateBack': {
        hilog.info(DOMAIN, TAG, 'back to chat list from chatId=%{public}s', `${this.currentState.chatId}`);
        this.onBack();
        break;
      }

      case 'reportMessagesRead': {
        // MSG-104：scroll intent 路径的已读上报；执行侧再经节流（只增不减）。
        const report: ReportMessagesRead = effect as ReportMessagesRead;
        if (!this.destroyed && this.readThrottle.shouldReport(report.messageId)) {
          this.sendReadReport(report.messageId);
        }
        break;
      }

      case 'resendMessage': {
        // MSG-104：失败重发；响应失败回灌 OnMessageActionFailed（errorMessage 细条），
        // 成功无额外动作（updateMessageSendSucceeded/Failed 订阅结算）。
        const resend: ResendMessage = effect as ResendMessage;
        hilog.info(DOMAIN, TAG, 'resend message chatId=%{public}s messageId=%{public}s',
          `${resend.chatId}`, `${resend.messageId}`);
        const result: Result<TdPendingRequest, AppError> =
          this.projection.resendMessages([resend.messageId]);
        if (result.err) {
          hilog.error(DOMAIN, TAG, 'resendMessages rejected: %{public}s', AppErrors.toLogString(result.error));
          this.dispatch(new OnMessageActionFailed(result.error));
        }
        if (result.ok) {
          result.value.promise.then((res: Result<TdWireObject, AppError>) => {
            if (res.err) {
              hilog.error(DOMAIN, TAG, 'resendMessages failed: %{public}s', AppErrors.toLogString(res.error));
              if (!this.destroyed) {
                this.dispatch(new OnMessageActionFailed(res.error));
              }
            }
          }).catch(() => {
          });
        }
        break;
      }

      default:
        break;
    }
  }

  /** null = 投影侧跳过（正在加载/已到顶端）；请求级与响应级失败都回灌 OnMessagesLoadFailed。 */
  private runFetch(result: Result<TdPendingRequest, AppError> | null): void {
    if (result === null) {
      return;
    }
    if (result.err) {
      hilog.error(DOMAIN, TAG, 'getChatHistory rejected: %{public}s', result.error.message);
      this.dispatch(new OnMessagesLoadFailed(result.error));
    }
    if (result.ok) {
      result.value.promise.then((res: Result<TdWireObject, AppError>) => {
        if (res.err) {
          hilog.error(DOMAIN, TAG, 'getChatHistory failed: %{public}s', res.error.message);
          if (!this.destroyed) {
            this.dispatch(new OnMessagesLoadFailed(res.error));
          }
        }
        if (res.ok) {
          const raw: TdWireValue | undefined = res.value['messages'];
          const count: number = (raw !== undefined && Array.isArray(raw)) ? (raw as TdWireObject[]).length : -1;
          hilog.info(DOMAIN, TAG, 'getChatHistory ok: %{public}d messages', count);
        }
      }).catch(() => {
      });
    }
  }
}
