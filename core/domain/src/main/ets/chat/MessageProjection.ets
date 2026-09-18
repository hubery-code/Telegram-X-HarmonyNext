/**
 * core/domain — 单会话消息投影（CHAT-001）。
 *
 * 与 ChatListProjection 同构，维护单个会话内的消息集合：
 * - start()：订阅 Gateway 更新（仅处理本 chatId 的 updateNewMessage /
 *   updateMessageContent / updateMessageEdited / updateDeleteMessages），
 *   并向 TDLib 发 openChat 开始接收该会话的消息更新；
 * - stop()：退订并发 closeChat；
 * - loadInitialMessages(limit)：from_message_id=0、offset=0 取最新一页；
 * - loadOlderMessages(limit)：from_message_id=当前最旧消息 id、offset=0 向前翻页
 *   （回包含 from 消息本身，经 Map 去重吸收）；
 * - 消息按 message.id 升序维护（会话内 id 与时间序单调一致），渲染层最旧在前；
 *   Map 按 id 去重，回包边界重复天然被吸收；
 * - TDLib 按"最优性能"自选回包条数（首屏常只回内存里已有的 1 条，同时后台
 *   preload 更旧历史），因此空页或整页重复（无新增 id）才判定到达历史顶端。
 *
 * 注意：本模块不 import ArkUI / Kit（与 core 层约束一致）。
 *
 * CHAT-004 新增：sendTextMessage 支持 replyToMessageId；editMessageText /
 * deleteMessages / getMessageProperties（离线方法，供长按菜单权限过滤）。
 *
 * MSG-104 新增：markMessagesRead（viewMessages 已读上报）、resendMessages
 * （失败重发）；订阅 updateChatReadOutbox 维护对端已读水位
 * lastReadOutboxMessageId（放进 MessageListState）。
 *
 * MSG-104 修复：start() 里 openChat 后追加一次 getChat，把
 * chat.last_read_outbox_message_id 灌为水位初值——历史已读不会补推
 * updateChatReadOutbox，只靠增量推送会把"进入会话前已读"的消息错显为单勾。
 * openChat 后 chat 已命中 TDLib 本地缓存，这次请求无网络往返。
 *
 * MSG-106 新增：forwardMessages（多选消息转发到目标会话，含 send_copy
 * "以副本发送"隐藏原发送者选项）。
 */

import {
  decodeTdUpdate,
  decodeMessage,
  decodeChat,
  encodeGetChatHistory,
  encodeOpenChat,
  encodeCloseChat,
  encodeSendMessage,
  encodeEditMessageText,
  encodeDeleteMessages,
  encodeGetMessageProperties,
  encodeViewMessages,
  encodeResendMessages,
  encodeGetChat,
  encodeForwardMessages,
  encodeSetChatDraftMessage,
  encodeSearchChatMessages,
  encodeGetChatPinnedMessage,
  encodePinChatMessage,
  encodeUnpinChatMessage,
  encodeUnpinAllChatMessages,
  encodeJoinChat,
  encodeAddMessageReaction,
  encodeRemoveMessageReaction,
  GetChatHistory,
  OpenChat,
  CloseChat,
  SendMessage,
  EditMessageText,
  DeleteMessages,
  GetMessageProperties,
  ViewMessages,
  ResendMessages,
  GetChat,
  GetChatPinnedMessage,
  PinChatMessage,
  UnpinChatMessage,
  UnpinAllChatMessages,
  JoinChat,
  AddMessageReaction,
  RemoveMessageReaction,
  ReactionTypeEmoji,
  ForwardMessages,
  SetChatDraftMessage,
  SearchChatMessages,
  FoundChatMessages,
  decodeFoundChatMessages,
  DraftMessage,
  DraftMessageContentText,
  Chat,
  InputFileLocal,
  InputPhoto,
  InputMessagePhoto,
  InputDocument,
  InputMessageDocument,
  InputVoiceNote,
  InputMessageVoiceNote,
  InputMessageReplyToMessage,
  InputMessageText,
  LinkPreviewOptions,
  FormattedText,
  Message,
  TdJsonRaw,
  TdUpdate,
  UpdateNewMessage,
  UpdateMessageContent,
  UpdateMessageEdited,
  UpdateMessageSendSucceeded,
  UpdateDeleteMessages,
  UpdateChatReadOutbox,
  UpdateChatReadInbox,
  UpdateChatDraftMessage,
  UpdateMessageIsPinned
} from '@tgx/core-td-api-generated';
import { AccountScope } from '@tgx/core-account';
import { TdUpdateSubscription, TdPendingRequest, TdWireObject, TdWireValue } from '@tgx/td-gateway';
import { Result, AppError, AppErrors, err } from '@tgx/core-common';

export interface MessageListState {
  /** 按 message.id 升序（最旧在前）。 */
  readonly messages: Message[];
  readonly isLoading: boolean;
  readonly hasMoreOlder: boolean;
  /** MSG-104：对端已读到的最后一条己方消息 id（updateChatReadOutbox），0=未知/无。 */
  readonly lastReadOutboxMessageId: number;
  /** 本端收到的最后一条已读对端消息 id（updateChatReadInbox），0=未知/无。 */
  readonly lastReadInboxMessageId: number;
  /** 未读消息数（0 表示已全部读完）。 */
  readonly unreadCount: number;
}

/** getChatHistory 一页的吞入统计（received=成功 decode 条数，added=新增 id 数）。 */
class HistoryIngest {
  readonly received: number;
  readonly added: number;

  constructor(received: number, added: number) {
    this.received = received;
    this.added = added;
  }
}

/** 连续无新增页数达到该值才判定历史到顶（容忍 TDLib 后台 preload 在飞的空窗期）。 */
const MAX_EMPTY_PAGES: number = 3;

/** TDLib forwardMessages 单次可转发的消息条数上限（超出会被服务端拒绝）。 */
const MAX_FORWARD_IDS: number = 100;

export class MessageProjection {
  private readonly chatId: number;
  private readonly scope: AccountScope;

  private readonly messagesById: Map<number, Message> = new Map();
  private orderedIds: number[] = [];

  private isLoading: boolean = false;
  private hasMoreOlder: boolean = true;
  private emptyPageStreak: number = 0;
  /** MSG-104：对端已读回执水位（updateChatReadOutbox 推进，只增）。 */
  private lastReadOutboxMessageId: number = 0;
  /** 本端对收到的对端消息已读水位（updateChatReadInbox 推进，只增）。 */
  private lastReadInboxMessageId: number = 0;
  /** 未读消息计数。 */
  private unreadCount: number = 0;

  private subscription: TdUpdateSubscription | null = null;
  private stateListener: (() => void) | null = null;
  private initialDraft: DraftMessage | null = null;
  private draftListener: ((draft: DraftMessage | null) => void) | null = null;
  /** MSG-108：置顶消息动态变更监听器（updateMessageIsPinned）。 */
  private pinnedMessageListener: ((messageId: number, isPinned: boolean) => void) | null = null;

  constructor(chatId: number, scope: AccountScope) {
    this.chatId = chatId;
    this.scope = scope;
  }

  /** 列表内容或加载状态变化时回调（调用方负责合并高频通知）。 */
  setOnStateChanged(listener: (() => void) | null): void {
    this.stateListener = listener;
  }

  setOnDraftLoaded(listener: ((draft: DraftMessage | null) => void) | null): void {
    this.draftListener = listener;
  }

  /** MSG-108：设置置顶消息变化监听器。 */
  setOnPinnedMessageChanged(listener: ((messageId: number, isPinned: boolean) => void) | null): void {
    this.pinnedMessageListener = listener;
  }

  getInitialDraft(): DraftMessage | null {
    return this.initialDraft;
  }

  private notifyStateChanged(): void {
    if (this.stateListener !== null) {
      this.stateListener();
    }
  }

  start(): void {
    if (this.subscription !== null) {
      return;
    }
    this.subscription = this.scope.gatewayInstance.subscribeUpdates(
      { clientId: this.scope.clientId },
      (event) => {
        const update: TdUpdate | null = decodeTdUpdate(event.payload as TdJsonRaw);
        if (update === null) {
          return;
        }
        this.handleUpdate(update);
      }
    );
    this.openChat();
    this.fetchReadOutboxWatermark();
  }

  stop(): void {
    if (this.subscription !== null) {
      this.subscription.unsubscribe();
      this.subscription = null;
    }
    this.closeChat();
  }

  get state(): MessageListState {
    const messages: Message[] = [];
    for (let i = 0; i < this.orderedIds.length; i++) {
      const message: Message | undefined = this.messagesById.get(this.orderedIds[i]);
      if (message !== undefined) {
        messages.push(message);
      }
    }
    return {
      messages: messages,
      isLoading: this.isLoading,
      hasMoreOlder: this.hasMoreOlder,
      lastReadOutboxMessageId: this.lastReadOutboxMessageId,
      lastReadInboxMessageId: this.lastReadInboxMessageId,
      unreadCount: this.unreadCount
    };
  }

  /** 根据 messageId 从内存缓存中查询 Message 对象（用于回复摘要提取等）。 */
  getMessageById(messageId: number): Message | undefined {
    return this.messagesById.get(messageId);
  }

  /** 将单条消息放入内存查询缓存（不改变 orderedIds 列表展示顺序）。 */
  addCachedMessage(message: Message): void {
    if (!this.messagesById.has(message.id)) {
      this.messagesById.set(message.id, message);
    }
  }

  /**
   * 首屏：取最新一页消息。
   * 正在加载或已有数据时忽略并返回 null，避免重复请求。
   */
  loadInitialMessages(limit: number = 30): Result<TdPendingRequest, AppError> | null {
    if (this.isLoading || this.orderedIds.length > 0) {
      return null;
    }
    return this.requestHistory(0, 0, limit);
  }

  /**
   * 向前翻页：取比当前最旧消息更早的一页（offset=0 从 from_message_id
   * 本身开始，回包首条与已知最旧消息重复，经 Map 去重吸收）。
   * 正在加载 / 已到顶端 / 尚未首屏加载时忽略并返回 null。
   */
  loadOlderMessages(limit: number = 20): Result<TdPendingRequest, AppError> | null {
    if (this.isLoading || !this.hasMoreOlder || this.orderedIds.length === 0) {
      return null;
    }
    return this.requestHistory(this.orderedIds[0], 0, limit);
  }

  /**
   * SEARCH-102 聊天内搜索：组 SearchChatMessages 在**当前会话内**按关键词检索消息。
   * 返回 pendingRequest，调用方经 promise 解码 FoundChatMessages（含 messages 与
   * next_from_message_id 分页游标）。与全局搜索 SearchCoordinator 走 SearchMessages
   * 不同，这里 chatId 已固定在投影上，天然单会话检索对齐 FEAT-SEARCH-002。
   * 空关键词直接判 parameter/missing 不发起请求。
   */
  searchMessages(
    query: string,
    fromMessageId: number = 0,
    limit: number = 30
  ): Result<TdPendingRequest, AppError> {
    const trimmed: string = query.trim();
    if (trimmed.length === 0) {
      return err(AppErrors.parameter('invalid', 'query', 'search query is empty'));
    }
    const req: SearchChatMessages = new SearchChatMessages();
    req.chat_id = this.chatId;
    req.query = trimmed;
    req.from_message_id = fromMessageId;
    req.limit = limit;
    req.filter = null;
    req.sender_id = null;
    req.topic_id = null;
    return this.scope.request('searchChatMessages', encodeSearchChatMessages(req) as TdWireObject);
  }

  /**
   * SEARCH-102 结果跳转定位：围绕目标消息拉一段历史（GetChatHistory 从
   * from_message_id=target 出发，负 offset 使得返回包含该消息本身及其邻近消息），
   * 让目标消息进入本地缓存——ChatPage.scrollToMessageId 目前只对已加载的消息有效，
   * 跨页跳转需先围绕目标拉历史。正在加载时忽略返回 null（复用既有加载守卫）。
   */
  loadHistoryAround(
    messageId: number,
    radius: number = 30
  ): Result<TdPendingRequest, AppError> | null {
    if (this.isLoading) {
      return null;
    }
    // offset 为负：TDLib 返回指定消息及其更早的 radius 条，limit 取 2*radius 保证目标居中。
    return this.requestHistory(messageId, -radius, radius * 2);
  }

  /**
   * MSG-108 置顶消息：向 TDLib 请求当前会话的置顶消息（GetChatPinnedMessage）。
   * TDLib 返回最新的 Message，若无置顶消息则返回 404 错误。
   */
  getChatPinnedMessage(): Result<TdPendingRequest, AppError> {
    const req: GetChatPinnedMessage = new GetChatPinnedMessage();
    req.chat_id = this.chatId;
    return this.scope.request('getChatPinnedMessage', encodeGetChatPinnedMessage(req) as TdWireObject);
  }

  /**
   * MSG-108 置顶单条消息（PinChatMessage）。
   * A message can be pinned only if messageProperties.can_be_pinned.
   */
  pinChatMessage(
    messageId: number,
    disableNotification: boolean = false,
    onlyForSelf: boolean = false
  ): Result<TdPendingRequest, AppError> {
    const req: PinChatMessage = new PinChatMessage();
    req.chat_id = this.chatId;
    req.message_id = messageId;
    req.disable_notification = disableNotification;
    req.only_for_self = onlyForSelf;
    return this.scope.request('pinChatMessage', encodePinChatMessage(req) as TdWireObject);
  }

  /**
   * MSG-108 取消置顶单条消息（UnpinChatMessage）。
   */
  unpinChatMessage(messageId: number): Result<TdPendingRequest, AppError> {
    const req: UnpinChatMessage = new UnpinChatMessage();
    req.chat_id = this.chatId;
    req.message_id = messageId;
    return this.scope.request('unpinChatMessage', encodeUnpinChatMessage(req) as TdWireObject);
  }

  /**
   * MSG-108 取消会话内所有置顶消息（UnpinAllChatMessages）。
   */
  unpinAllChatMessages(): Result<TdPendingRequest, AppError> {
    const req: UnpinAllChatMessages = new UnpinAllChatMessages();
    req.chat_id = this.chatId;
    return this.scope.request('unpinAllChatMessages', encodeUnpinAllChatMessages(req) as TdWireObject);
  }

  /**
   * CHANNEL-101 频道模式：加入当前频道/会话（JoinChat）。
   */
  joinChat(): Result<TdPendingRequest, AppError> {
    const req: JoinChat = new JoinChat();
    req.chat_id = this.chatId;
    return this.scope.request('joinChat', encodeJoinChat(req) as TdWireObject);
  }

  /**
   * CHANNEL-101 消息反应：为消息添加反应（AddMessageReaction）。
   */
  addMessageReaction(messageId: number, emoji: string): Result<TdPendingRequest, AppError> {
    const req: AddMessageReaction = new AddMessageReaction();
    req.chat_id = this.chatId;
    req.message_id = messageId;
    const reactionType: ReactionTypeEmoji = new ReactionTypeEmoji();
    reactionType.emoji = emoji;
    req.reaction_type = reactionType;
    return this.scope.request('addMessageReaction', encodeAddMessageReaction(req) as TdWireObject);
  }

  /**
   * CHANNEL-101 消息反应：移除已添加的反应（RemoveMessageReaction）。
   */
  removeMessageReaction(messageId: number, emoji: string): Result<TdPendingRequest, AppError> {
    const req: RemoveMessageReaction = new RemoveMessageReaction();
    req.chat_id = this.chatId;
    req.message_id = messageId;
    const reactionType: ReactionTypeEmoji = new ReactionTypeEmoji();
    reactionType.emoji = emoji;
    req.reaction_type = reactionType;
    return this.scope.request('removeMessageReaction', encodeRemoveMessageReaction(req) as TdWireObject);
  }

  /**
   * 发送文本消息（CHAT-003 + CHAT-004）：组 inputMessageText 调 sendMessage。
   * trim 后为空直接判 parameter/missing，不发起请求；成功/失败经返回的
   * Result 与 pendingRequest.promise 透传给调用方。
   * replyToMessageId > 0 时组 inputMessageReplyToMessage 挂到 reply_to（CHAT-004 回复）。
   * 发出的消息经 updateNewMessage 进入列表、经 updateMessageSendSucceeded /
   * updateMessageSendFailed 结算发送态，均由现有更新订阅处理，这里不手动插入。
   */
  sendTextMessage(
    text: string,
    replyToMessageId: number = 0,
    linkPreviewOptions?: LinkPreviewOptions
  ): Result<TdPendingRequest, AppError> {
    const trimmed: string = text.trim();
    if (trimmed.length === 0) {
      return err<TdPendingRequest, AppError>(
        AppErrors.parameter('missing', 'text', 'message text is empty')
      );
    }
    const formatted: FormattedText = new FormattedText();
    formatted.text = trimmed;

    const content: InputMessageText = new InputMessageText();
    content.text = formatted;
    if (linkPreviewOptions !== undefined) {
      content.link_preview_options = linkPreviewOptions;
    }

    const req: SendMessage = new SendMessage();
    req.chat_id = this.chatId;
    if (replyToMessageId > 0) {
      const replyTo: InputMessageReplyToMessage = new InputMessageReplyToMessage();
      replyTo.message_id = replyToMessageId;
      req.reply_to = replyTo;
    }
    req.input_message_content = content;

    return this.scope.request('sendMessage', encodeSendMessage(req) as TdWireObject);
  }

  /**
   * 发送图片消息（MEDIA-102 / FEAT-MEDIA-001 发侧）：组 InputMessagePhoto 调 sendMessage。
   * localPath 为空直接判 parameter/missing；caption 可选。
   * replyToMessageId > 0 时挂 reply_to。
   */
  sendPhotoMessage(
    localPath: string,
    caption?: string,
    replyToMessageId: number = 0,
    width: number = 0,
    height: number = 0
  ): Result<TdPendingRequest, AppError> {
    const trimmedPath: string = localPath.trim();
    if (trimmedPath.length === 0) {
      return err<TdPendingRequest, AppError>(
        AppErrors.parameter('missing', 'localPath', 'photo local path is empty')
      );
    }
    const fileLocal: InputFileLocal = new InputFileLocal();
    fileLocal.path = trimmedPath;

    const photo: InputPhoto = new InputPhoto();
    photo.photo = fileLocal;
    if (width > 0) {
      photo.width = width;
    }
    if (height > 0) {
      photo.height = height;
    }

    const content: InputMessagePhoto = new InputMessagePhoto();
    content.photo = photo;
    if (caption !== undefined && caption.trim().length > 0) {
      const formatted: FormattedText = new FormattedText();
      formatted.text = caption.trim();
      content.caption = formatted;
    }

    const req: SendMessage = new SendMessage();
    req.chat_id = this.chatId;
    if (replyToMessageId > 0) {
      const replyTo: InputMessageReplyToMessage = new InputMessageReplyToMessage();
      replyTo.message_id = replyToMessageId;
      req.reply_to = replyTo;
    }
    req.input_message_content = content;

    return this.scope.request('sendMessage', encodeSendMessage(req) as TdWireObject);
  }

  /**
   * 发送文件消息（MEDIA-104 / FEAT-MEDIA-003 发侧）：组 InputMessageDocument 调 sendMessage。
   * localPath 为空直接判 parameter/missing；caption 可选。
   * replyToMessageId > 0 时挂 reply_to。
   */
  sendDocumentMessage(
    localPath: string,
    caption?: string,
    replyToMessageId: number = 0
  ): Result<TdPendingRequest, AppError> {
    const trimmedPath: string = localPath.trim();
    if (trimmedPath.length === 0) {
      return err<TdPendingRequest, AppError>(
        AppErrors.parameter('missing', 'localPath', 'document local path is empty')
      );
    }
    const fileLocal: InputFileLocal = new InputFileLocal();
    fileLocal.path = trimmedPath;

    const doc: InputDocument = new InputDocument();
    doc.document = fileLocal;

    const content: InputMessageDocument = new InputMessageDocument();
    content.document = doc;
    if (caption !== undefined && caption.trim().length > 0) {
      const formatted: FormattedText = new FormattedText();
      formatted.text = caption.trim();
      content.caption = formatted;
    }

    const req: SendMessage = new SendMessage();
    req.chat_id = this.chatId;
    if (replyToMessageId > 0) {
      const replyTo: InputMessageReplyToMessage = new InputMessageReplyToMessage();
      replyTo.message_id = replyToMessageId;
      req.reply_to = replyTo;
    }
    req.input_message_content = content;

    return this.scope.request('sendMessage', encodeSendMessage(req) as TdWireObject);
  }

  /**
   * 发送语音消息（VOICE-101 / FEAT-P2-006）：组 InputMessageVoiceNote 调 sendMessage。
   * localPath 为空直接判 parameter/missing；caption 可选。
   * replyToMessageId > 0 时挂 reply_to。
   */
  sendVoiceNoteMessage(
    localPath: string,
    durationSec: number = 0,
    waveform: string = '',
    caption?: string,
    replyToMessageId: number = 0
  ): Result<TdPendingRequest, AppError> {
    const trimmedPath: string = localPath.trim();
    if (trimmedPath.length === 0) {
      return err<TdPendingRequest, AppError>(
        AppErrors.parameter('missing', 'localPath', 'voice note local path is empty')
      );
    }
    const fileLocal: InputFileLocal = new InputFileLocal();
    fileLocal.path = trimmedPath;

    const voiceNote: InputVoiceNote = new InputVoiceNote();
    voiceNote.voice_note = fileLocal;
    voiceNote.duration = Math.max(0, Math.floor(durationSec));
    voiceNote.waveform = waveform;

    const content: InputMessageVoiceNote = new InputMessageVoiceNote();
    content.voice_note = voiceNote;
    if (caption !== undefined && caption.trim().length > 0) {
      const formatted: FormattedText = new FormattedText();
      formatted.text = caption.trim();
      content.caption = formatted;
    }

    const req: SendMessage = new SendMessage();
    req.chat_id = this.chatId;
    if (replyToMessageId > 0) {
      const replyTo: InputMessageReplyToMessage = new InputMessageReplyToMessage();
      replyTo.message_id = replyToMessageId;
      req.reply_to = replyTo;
    }
    req.input_message_content = content;

    return this.scope.request('sendMessage', encodeSendMessage(req) as TdWireObject);
  }

  /**
   * 保存或清除草稿（COMPOSER-101 / FEAT-CHAT-005）：setChatDraftMessage(chat_id, draft_message)。
   * text 为空且无 replyTo 时置 draft_message = null 清除草稿；
   * 否则组装 DraftMessage(DraftMessageContentText) 保存。
   */
  setChatDraftMessage(text: string, replyToMessageId: number = 0): Result<TdPendingRequest, AppError> {
    const trimmed: string = text.trim();
    const req: SetChatDraftMessage = new SetChatDraftMessage();
    req.chat_id = this.chatId;
    if (trimmed.length === 0 && replyToMessageId <= 0) {
      req.draft_message = null;
    } else {
      const draft: DraftMessage = new DraftMessage();
      const content: DraftMessageContentText = new DraftMessageContentText();
      const formatted: FormattedText = new FormattedText();
      formatted.text = text;
      content.text = formatted;
      draft.content = content;
      draft.date = Math.floor(Date.now() / 1000);
      if (replyToMessageId > 0) {
        const replyTo: InputMessageReplyToMessage = new InputMessageReplyToMessage();
        replyTo.message_id = replyToMessageId;
        draft.reply_to = replyTo;
      }
      req.draft_message = draft;
    }
    return this.scope.request('setChatDraftMessage', encodeSetChatDraftMessage(req) as TdWireObject);
  }

  /** 清除当前会话的草稿。 */
  clearChatDraftMessage(): Result<TdPendingRequest, AppError> {
    return this.setChatDraftMessage('', 0);
  }

  /**
   * 编辑文本消息（CHAT-004）：组 inputMessageText 调 editMessageText。
   * trim 后为空判 parameter/missing（editMessageText 不接受空文本）。
   * 成功后 TDLib 推 updateMessageContent / updateMessageEdited，由现有订阅
   * 更新列表；失败经 promise 透传给调用方回灌错误提示。
   */
  editMessageText(
    messageId: number,
    text: string,
    linkPreviewOptions?: LinkPreviewOptions
  ): Result<TdPendingRequest, AppError> {
    const trimmed: string = text.trim();
    if (trimmed.length === 0) {
      return err<TdPendingRequest, AppError>(
        AppErrors.parameter('missing', 'text', 'message text is empty')
      );
    }
    const formatted: FormattedText = new FormattedText();
    formatted.text = trimmed;

    const content: InputMessageText = new InputMessageText();
    content.text = formatted;
    if (linkPreviewOptions !== undefined) {
      content.link_preview_options = linkPreviewOptions;
    }

    const req: EditMessageText = new EditMessageText();
    req.chat_id = this.chatId;
    req.message_id = messageId;
    req.input_message_content = content;

    const result: Result<TdPendingRequest, AppError> =
      this.scope.request('editMessageText', encodeEditMessageText(req) as TdWireObject);
    if (result.ok) {
      const self: MessageProjection = this;
      // 响应本体即更新后的 message：确定性落本地，不依赖 updateMessageContent
      // 推送时序；随后到达的 update 经 upsert 幂等覆盖，无冲突。
      result.value.promise.then((res: Result<TdWireObject, AppError>) => {
        if (res.ok) {
          const message: Message | null = decodeMessage(res.value as TdJsonRaw);
          if (message !== null && message.chat_id === self.chatId) {
            self.upsertMessages([message]);
            self.notifyStateChanged();
          }
        }
      }).catch(() => {
      });
    }
    return result;
  }

  /**
   * 删除消息（CHAT-004）：deleteMessages(chat_id, message_ids, revoke)。
   * revoke=true 对所有人删除（需 can_be_deleted_for_all_users）。
   * 成功后 TDLib 推 updateDeleteMessages，由现有订阅把气泡移出列表。
   */
  deleteMessages(messageIds: number[], revoke: boolean): Result<TdPendingRequest, AppError> {
    if (messageIds.length === 0) {
      return err<TdPendingRequest, AppError>(
        AppErrors.parameter('missing', 'message_ids', 'no message ids to delete')
      );
    }
    const req: DeleteMessages = new DeleteMessages();
    req.chat_id = this.chatId;
    req.message_ids = messageIds;
    req.revoke = revoke;

    const result: Result<TdPendingRequest, AppError> =
      this.scope.request('deleteMessages', encodeDeleteMessages(req) as TdWireObject);
    if (result.ok) {
      const self: MessageProjection = this;
      // 响应 ok 即本地移除（乐观删除）：不依赖 updateDeleteMessages 推送时序；
      // 随后到达的 update 对已删除 id 幂等 no-op。
      result.value.promise.then((res: Result<TdWireObject, AppError>) => {
        if (res.ok) {
          let removed: boolean = false;
          for (let i = 0; i < messageIds.length; i++) {
            if (self.messagesById.delete(messageIds[i])) {
              const idx: number = self.orderedIds.indexOf(messageIds[i]);
              if (idx >= 0) {
                self.orderedIds.splice(idx, 1);
              }
              removed = true;
            }
          }
          if (removed) {
            self.notifyStateChanged();
          }
        }
      }).catch(() => {
      });
    }
    return result;
  }

  /**
   * 拉取单条消息的权限位（CHAT-004 长按菜单）：TDLib getMessageProperties
   * 为离线方法（本地计算、立即回包），返回 MessageProperties。
   */
  getMessageProperties(messageId: number): Result<TdPendingRequest, AppError> {
    const req: GetMessageProperties = new GetMessageProperties();
    req.chat_id = this.chatId;
    req.message_id = messageId;

    return this.scope.request('getMessageProperties', encodeGetMessageProperties(req) as TdWireObject);
  }

  /**
   * 已读上报（MSG-104）：viewMessages(chat_id, message_ids, source=null,
   * force_read=false)——source=null 让 TDLib 按 chat 开关状态判定，页面开着
   * 才入账。空数组直接判 parameter/missing，不发起请求。
   */
  markMessagesRead(messageIds: number[]): Result<TdPendingRequest, AppError> {
    if (messageIds.length === 0) {
      return err<TdPendingRequest, AppError>(
        AppErrors.parameter('missing', 'message_ids', 'no message ids to mark read')
      );
    }
    const req: ViewMessages = new ViewMessages();
    req.chat_id = this.chatId;
    req.message_ids = messageIds;
    req.source = null;
    req.force_read = false;

    return this.scope.request('viewMessages', encodeViewMessages(req) as TdWireObject);
  }

  /**
   * 重发失败消息（MSG-104）：resendMessages(chat_id, message_ids)。
   * 成功后 TDLib 推 updateMessageSendSucceeded/Failed 结算发送态，由现有订阅处理。
   */
  resendMessages(messageIds: number[]): Result<TdPendingRequest, AppError> {
    if (messageIds.length === 0) {
      return err<TdPendingRequest, AppError>(
        AppErrors.parameter('missing', 'message_ids', 'no message ids to resend')
      );
    }
    const req: ResendMessages = new ResendMessages();
    req.chat_id = this.chatId;
    req.message_ids = messageIds;

    return this.scope.request('resendMessages', encodeResendMessages(req) as TdWireObject);
  }

  /**
   * 转发消息（MSG-106 / FEAT-COMP-004）：forwardMessages(from_chat_id=this.chatId,
   * chat_id=toChatId, message_ids, send_copy, remove_caption)。
   *
   * - message_ids 必须严格递增，这里做升序去重（调用方传来的选择顺序不可信）；
   *   TDLib 上限 100 条，超出直接判 parameter/invalid 不发起请求；
   * - send_copy=true 即"以副本发送"（隐藏原发送者，Android 侧 R.string.SendAsCopy）；
   * - remove_caption 仅在 send_copy 为真时被 TDLib 采纳；
   * - 本端所有待转发消息同属 this.chatId，因此单次请求足够——Android 的
   *   TD.forwardMessages 按来源 chatId 分组多次调用，是为跨会话多选（分享流）准备的，
   *   单会话内多选无需分组；
   * - 成功无本地乐观插入：目标会话不在当前投影内，转出的气泡由目标会话自己的
   *   投影经 updateNewMessage 呈现（若用户随后进入该会话）。
   */
  forwardMessages(
    toChatId: number,
    messageIds: number[],
    sendCopy: boolean,
    removeCaption: boolean = false
  ): Result<TdPendingRequest, AppError> {
    if (messageIds.length === 0) {
      return err<TdPendingRequest, AppError>(
        AppErrors.parameter('missing', 'message_ids', 'no message ids to forward')
      );
    }
    if (messageIds.length > MAX_FORWARD_IDS) {
      return err<TdPendingRequest, AppError>(
        AppErrors.parameter('invalid', 'message_ids', `at most ${MAX_FORWARD_IDS} messages can be forwarded`)
      );
    }
    // 严格递增：升序 + 去重（TDLib 对乱序/重复的 message_ids 直接报错）。
    const sorted: number[] = [];
    const seen: Set<number> = new Set();
    const ascending: number[] = messageIds.slice().sort((a: number, b: number): number => a - b);
    for (let i = 0; i < ascending.length; i++) {
      if (!seen.has(ascending[i])) {
        seen.add(ascending[i]);
        sorted.push(ascending[i]);
      }
    }

    const req: ForwardMessages = new ForwardMessages();
    req.chat_id = toChatId;
    req.topic_id = null;
    req.from_chat_id = this.chatId;
    req.message_ids = sorted;
    req.options = null;
    req.send_copy = sendCopy;
    req.remove_caption = removeCaption;

    return this.scope.request('forwardMessages', encodeForwardMessages(req) as TdWireObject);
  }

  private requestHistory(fromMessageId: number, offset: number, limit: number): Result<TdPendingRequest, AppError> {
    const req: GetChatHistory = new GetChatHistory();
    req.chat_id = this.chatId;
    req.from_message_id = fromMessageId;
    req.offset = offset;
    req.limit = limit;
    req.only_local = false;

    const result: Result<TdPendingRequest, AppError> =
      this.scope.request('getChatHistory', encodeGetChatHistory(req) as TdWireObject);
    if (result.ok) {
      this.isLoading = true;
      this.notifyStateChanged();
      const self: MessageProjection = this;
      result.value.promise.then((res: Result<TdWireObject, AppError>) => {
        self.isLoading = false;
        if (res.ok) {
          const ingest: HistoryIngest = self.ingestHistoryPage(res.value, limit);
          console.info(`MessageProjection history chatId=${self.chatId} received=${ingest.received} added=${ingest.added}`);
          // TDLib 按"最优性能"自选回包条数：首屏常只回内存已有的末条消息，
          // 同时后台 preload 更旧历史（服务器往返 1-2s）。preload 在飞时空跑
          // 会拿到重复/空页，因此连续 MAX_EMPTY_PAGES 次无新增才判定到顶。
          if (ingest.added > 0) {
            self.emptyPageStreak = 0;
          } else {
            self.emptyPageStreak += 1;
            if (self.emptyPageStreak >= MAX_EMPTY_PAGES) {
              self.hasMoreOlder = false;
            }
          }
          self.notifyStateChanged();
        }
        // 失败路径不 notify：由调用方经返回的 promise 回灌 OnMessagesLoadFailed，
        // 避免随后的投影同步把 errorMessage 覆盖掉
      }).catch(() => {
        self.isLoading = false;
      });
    }
    return result;
  }

  /** 解包 messages 数组、逐条 decodeMessage（失败条目跳过），去重后按 id 升序重排。 */
  private ingestHistoryPage(wire: TdWireObject, limit: number): HistoryIngest {
    let received: number = 0;
    let added: number = 0;
    const rawMessages: TdWireValue | undefined = wire['messages'];
    if (rawMessages !== undefined && rawMessages !== null && Array.isArray(rawMessages)) {
      for (let i = 0; i < rawMessages.length; i++) {
        const message: Message | null = decodeMessage(rawMessages[i] as TdJsonRaw);
        if (message === null) {
          continue;
        }
        received += 1;
        if (!this.messagesById.has(message.id)) {
          added += 1;
          this.orderedIds.push(message.id);
        }
        this.messagesById.set(message.id, message);
      }
      if (added > 0) {
        this.orderedIds.sort((a: number, b: number): number => a - b);
      }
    }
    return new HistoryIngest(received, added);
  }

  private handleUpdate(update: TdUpdate): void {
    if (update.type === 'updateMessageContent' || update.type === 'updateMessageEdited' ||
      update.type === 'updateMessageSendSucceeded' || update.type === 'updateMessageSendFailed') {
      console.info(`MessageProjection update ${update.type} chatId=${this.chatId}`);
    }
    if (update.type === 'updateNewMessage') {
      const message: Message | null = (update as UpdateNewMessage).message;
      if (message !== null && message.chat_id === this.chatId) {
        this.upsertMessages([message]);
        this.notifyStateChanged();
      }
    } else if (update.type === 'updateMessageSendSucceeded' || update.type === 'updateMessageSendFailed') {
      // 发送结算（CHAT-003）：发出的消息先以临时 id + pending 态进列表，
      // 结算时把临时 id 换成正式消息（成功，sending_state=null）或失败态消息
      // （失败，sending_state=failed）。Succeeded/Failed 两个类的 message 与
      // old_message_id 字段同构，统一按 Succeeded 形状取。
      const sendUpdate: UpdateMessageSendSucceeded = update as UpdateMessageSendSucceeded;
      const message: Message | null = sendUpdate.message;
      if (message !== null && message.chat_id === this.chatId) {
        if (this.messagesById.delete(sendUpdate.old_message_id)) {
          const idx: number = this.orderedIds.indexOf(sendUpdate.old_message_id);
          if (idx >= 0) {
            this.orderedIds.splice(idx, 1);
          }
        }
        this.upsertMessages([message]);
        this.notifyStateChanged();
      }
    } else if (update.type === 'updateMessageContent') {
      const contentUpdate: UpdateMessageContent = update as UpdateMessageContent;
      if (contentUpdate.chat_id === this.chatId && contentUpdate.new_content !== null) {
        const existing: Message | undefined = this.messagesById.get(contentUpdate.message_id);
        if (existing !== undefined) {
          existing.content = contentUpdate.new_content;
          this.notifyStateChanged();
        }
      }
    } else if (update.type === 'updateMessageEdited') {
      const editedUpdate: UpdateMessageEdited = update as UpdateMessageEdited;
      if (editedUpdate.chat_id === this.chatId) {
        const existing: Message | undefined = this.messagesById.get(editedUpdate.message_id);
        if (existing !== undefined) {
          existing.edit_date = editedUpdate.edit_date;
          this.notifyStateChanged();
        }
      }
    } else if (update.type === 'updateDeleteMessages') {
      const deleteUpdate: UpdateDeleteMessages = update as UpdateDeleteMessages;
      if (deleteUpdate.chat_id === this.chatId) {
        let removed: boolean = false;
        for (let i = 0; i < deleteUpdate.message_ids.length; i++) {
          const messageId: number = deleteUpdate.message_ids[i];
          if (this.messagesById.delete(messageId)) {
            const idx: number = this.orderedIds.indexOf(messageId);
            if (idx >= 0) {
              this.orderedIds.splice(idx, 1);
            }
            removed = true;
          }
        }
        if (removed) {
          this.notifyStateChanged();
        }
      }
    } else if (update.type === 'updateChatReadOutbox') {
      // 已读回执（MSG-104）：对端已读水位只增不减，变化才通知。
      const readUpdate: UpdateChatReadOutbox = update as UpdateChatReadOutbox;
      if (readUpdate.chat_id === this.chatId) {
        console.info(`MessageProjection updateChatReadOutbox chatId=${this.chatId} lastReadOutbox=${readUpdate.last_read_outbox_message_id}`);
        this.advanceLastReadOutbox(readUpdate.last_read_outbox_message_id);
      }
    } else if (update.type === 'updateChatReadInbox') {
      // 本端对收到的消息已读水位推进（updateChatReadInbox）：只增不减。
      const readInboxUpdate: UpdateChatReadInbox = update as UpdateChatReadInbox;
      if (readInboxUpdate.chat_id === this.chatId) {
        this.advanceLastReadInbox(readInboxUpdate.last_read_inbox_message_id, readInboxUpdate.unread_count);
      }
    } else if (update.type === 'updateChatDraftMessage') {
      const draftUpdate: UpdateChatDraftMessage = update as UpdateChatDraftMessage;
      if (draftUpdate.chat_id === this.chatId) {
        this.initialDraft = draftUpdate.draft_message;
        if (this.draftListener !== null) {
          this.draftListener(draftUpdate.draft_message);
        }
      }
    } else if (update.type === 'updateMessageIsPinned') {
      const pinUpdate: UpdateMessageIsPinned = update as UpdateMessageIsPinned;
      if (pinUpdate.chat_id === this.chatId) {
        const existing: Message | undefined = this.messagesById.get(pinUpdate.message_id);
        if (existing !== undefined) {
          existing.is_pinned = pinUpdate.is_pinned;
          this.notifyStateChanged();
        }
        if (this.pinnedMessageListener !== null) {
          this.pinnedMessageListener(pinUpdate.message_id, pinUpdate.is_pinned);
        }
      }
    }
  }

  /** 已读水位只增不减，变化才通知（getChat 初始灌水位与增量推送共用）。 */
  private advanceLastReadOutbox(messageId: number): void {
    if (messageId > this.lastReadOutboxMessageId) {
      this.lastReadOutboxMessageId = messageId;
      this.notifyStateChanged();
    }
  }

  /** 本端已读水位只增不减，未读数同步更新，变化才通知。 */
  private advanceLastReadInbox(messageId: number, unreadCount?: number): void {
    let changed: boolean = false;
    if (messageId > this.lastReadInboxMessageId) {
      this.lastReadInboxMessageId = messageId;
      changed = true;
    }
    if (unreadCount !== undefined && unreadCount !== this.unreadCount) {
      this.unreadCount = unreadCount;
      changed = true;
    }
    if (changed) {
      this.notifyStateChanged();
    }
  }

  /**
   * 初始已读水位与草稿恢复（MSG-104 + COMPOSER-101）：getChat 取
   * chat.last_read_outbox_message_id、chat.last_read_inbox_message_id 与 chat.draft_message。
   * openChat 后 chat 已命中 TDLib 本地缓存，无网络往返；
   * 失败静默——水位退化为纯增量推送，与修复前行为一致。
   */
  private fetchReadOutboxWatermark(): void {
    const req: GetChat = new GetChat();
    req.chat_id = this.chatId;
    const result: Result<TdPendingRequest, AppError> =
      this.scope.request('getChat', encodeGetChat(req) as TdWireObject);
    if (result.ok) {
      const self: MessageProjection = this;
      result.value.promise.then((res: Result<TdWireObject, AppError>) => {
        if (res.ok) {
          const chat: Chat | null = decodeChat(res.value as TdJsonRaw);
          if (chat !== null && chat.id === self.chatId) {
            self.advanceLastReadOutbox(chat.last_read_outbox_message_id);
            self.advanceLastReadInbox(chat.last_read_inbox_message_id, chat.unread_count);
            self.initialDraft = chat.draft_message;
            if (self.draftListener !== null) {
              self.draftListener(chat.draft_message);
            }
          }
        }
      }).catch(() => {
      });
    }
  }

  private upsertMessages(messages: Message[]): void {
    let added: boolean = false;
    for (let i = 0; i < messages.length; i++) {
      const message: Message = messages[i];
      if (!this.messagesById.has(message.id)) {
        this.orderedIds.push(message.id);
        added = true;
      }
      this.messagesById.set(message.id, message);
    }
    if (added) {
      this.orderedIds.sort((a: number, b: number): number => a - b);
    }
  }

  private openChat(): void {
    const req: OpenChat = new OpenChat();
    req.chat_id = this.chatId;
    this.scope.request('openChat', encodeOpenChat(req) as TdWireObject);
  }

  private closeChat(): void {
    const req: CloseChat = new CloseChat();
    req.chat_id = this.chatId;
    this.scope.request('closeChat', encodeCloseChat(req) as TdWireObject);
  }
}
