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
 */

import {
  decodeTdUpdate,
  decodeMessage,
  encodeGetChatHistory,
  encodeOpenChat,
  encodeCloseChat,
  encodeSendMessage,
  encodeEditMessageText,
  encodeDeleteMessages,
  encodeGetMessageProperties,
  GetChatHistory,
  OpenChat,
  CloseChat,
  SendMessage,
  EditMessageText,
  DeleteMessages,
  GetMessageProperties,
  InputMessageReplyToMessage,
  InputMessageText,
  FormattedText,
  Message,
  TdJsonRaw,
  TdUpdate,
  UpdateNewMessage,
  UpdateMessageContent,
  UpdateMessageEdited,
  UpdateMessageSendSucceeded,
  UpdateDeleteMessages
} from '@tgx/core-td-api-generated';
import { AccountScope } from '@tgx/core-account';
import { TdUpdateSubscription, TdPendingRequest, TdWireObject, TdWireValue } from '@tgx/td-gateway';
import { Result, AppError, AppErrors, err } from '@tgx/core-common';

export interface MessageListState {
  /** 按 message.id 升序（最旧在前）。 */
  readonly messages: Message[];
  readonly isLoading: boolean;
  readonly hasMoreOlder: boolean;
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

export class MessageProjection {
  private readonly chatId: number;
  private readonly scope: AccountScope;

  private readonly messagesById: Map<number, Message> = new Map();
  private orderedIds: number[] = [];

  private isLoading: boolean = false;
  private hasMoreOlder: boolean = true;
  private emptyPageStreak: number = 0;

  private subscription: TdUpdateSubscription | null = null;
  private stateListener: (() => void) | null = null;

  constructor(chatId: number, scope: AccountScope) {
    this.chatId = chatId;
    this.scope = scope;
  }

  /** 列表内容或加载状态变化时回调（调用方负责合并高频通知）。 */
  setOnStateChanged(listener: (() => void) | null): void {
    this.stateListener = listener;
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
      hasMoreOlder: this.hasMoreOlder
    };
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
   * 发送文本消息（CHAT-003 + CHAT-004）：组 inputMessageText 调 sendMessage。
   * trim 后为空直接判 parameter/missing，不发起请求；成功/失败经返回的
   * Result 与 pendingRequest.promise 透传给调用方。
   * replyToMessageId > 0 时组 inputMessageReplyToMessage 挂到 reply_to（CHAT-004 回复）。
   * 发出的消息经 updateNewMessage 进入列表、经 updateMessageSendSucceeded /
   * updateMessageSendFailed 结算发送态，均由现有更新订阅处理，这里不手动插入。
   */
  sendTextMessage(text: string, replyToMessageId: number = 0): Result<TdPendingRequest, AppError> {
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
   * 编辑文本消息（CHAT-004）：组 inputMessageText 调 editMessageText。
   * trim 后为空判 parameter/missing（editMessageText 不接受空文本）。
   * 成功后 TDLib 推 updateMessageContent / updateMessageEdited，由现有订阅
   * 更新列表；失败经 promise 透传给调用方回灌错误提示。
   */
  editMessageText(messageId: number, text: string): Result<TdPendingRequest, AppError> {
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
