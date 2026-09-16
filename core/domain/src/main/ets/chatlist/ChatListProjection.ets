import { encodeAddChatToList,
 encodeLoadChats, decodeTdUpdate,
 encodeToggleChatIsPinned,
 encodeToggleChatIsMarkedAsUnread,
 encodeViewMessages,

 ChatListFolder,

  AddChatToList,
  Chat,
  ChatPosition,
  MessageSourceChatList,
  TdChatList,
  TdUpdate,
  ToggleChatIsPinned,
  ToggleChatIsMarkedAsUnread,
  UpdateNewChat,
  UpdateChatPosition,
  UpdateChatLastMessage,
  UpdateChatReadInbox,
  UpdateChatIsMarkedAsUnread,
  UpdateChatPhoto,
  UpdateChatTitle,
  UpdateChatDraftMessage,
  ViewMessages,
  LoadChats,
} from '@tgx/core-td-api-generated';
import { ChatRegistry } from './ChatRegistry';
import { AccountScope } from '@tgx/core-account';
import { TdPendingRequest, TdWireObject } from '@tgx/td-gateway';
import { Result, AppError, AppErrors, err } from '@tgx/core-common';
import { TdUpdateSubscription } from '@tgx/td-gateway';

export interface ChatListState {
  chatIds: number[];
  isLoading: boolean;
  hasMore: boolean;
}

/** 比较两个 TdChatList 是否代表同一个列表 */
export function chatListEquals(a: TdChatList | null, b: TdChatList | null): boolean {
  if (a === b) return true;
  if (!a || !b) return false;
  if (a.type !== b.type) return false;
  if (a.type === 'chatListFolder' && b.type === 'chatListFolder') {
    return (a as ChatListFolder).chat_folder_id === (b as ChatListFolder).chat_folder_id;
  }
  return true;
}

/**
 * 比较两个 ChatPosition 的 order。
 * 返回负数表示 A 应该排在 B 前面（即 A 的 order 更大，降序）。
 */
export function compareChatOrder(orderA: string, idA: number, orderB: string, idB: number): number {
  const oA = BigInt(orderA);
  const oB = BigInt(orderB);
  if (oA > oB) return -1;
  if (oA < oB) return 1;
  const iA = BigInt(idA);
  const iB = BigInt(idB);
  if (iA > iB) return -1;
  if (iA < iB) return 1;
  return 0;
}

/**
 * 会话在指定列表中的置顶态（MSG-108 / FEAT-CHAT-002）。
 * 权威来源是 TDLib `ChatPosition.is_pinned`——不靠客户端自行推断"排在最前即置顶"，
 * 因为置顶区与普通区之间还有 order 断层，归档区也不在同一列表。
 * 该会话在此列表中没有 position（未入列/已移出）时视为未置顶。
 */
export function isChatPinnedInList(chat: Chat, chatList: TdChatList | null): boolean {
  const position: ChatPosition | undefined =
    chat.positions.find((p: ChatPosition) => chatListEquals(p.list, chatList));
  return position !== undefined ? position.is_pinned : false;
}

/**
 * 会话列表视图投影。
 * 订阅 AccountScope 的 Gateway 更新，维护指定 ChatList 的有序列表。
 */
export class ChatListProjection {
  private readonly chatList: TdChatList | null;
  private readonly registry: ChatRegistry;
  private readonly scope: AccountScope;
  
  // 维护在该 list 下有 position 的所有 chatId
  // 我们只存带有位置信息的，排序在 getState 时进行或增量维护
  // 为了简单，我们维护一个内部的数组，并保证它是有序的
  private orderedChatIds: number[] = [];
  
  private isLoading: boolean = false;
  private hasMore: boolean = true;
  
  private subscription: TdUpdateSubscription | null = null;
  private stateListener: (() => void) | null = null;
  
  constructor(chatList: TdChatList | null, registry: ChatRegistry, scope: AccountScope) {
    this.chatList = chatList;
    this.registry = registry;
    this.scope = scope;
  }
  
  /** 列表内容或加载状态变化时回调（每次变更一次，调用方负责合并高频通知）。 */
  setOnStateChanged(listener: (() => void) | null): void {
    this.stateListener = listener;
  }
  
  private notifyStateChanged(): void {
    if (this.stateListener !== null) {
      this.stateListener();
    }
  }
  
  start(): void {
    if (this.subscription) return;
    this.subscription = this.scope.gatewayInstance.subscribeUpdates(
      { clientId: this.scope.clientId },
      (event) => {
        const update = decodeTdUpdate(event.payload as import('@tgx/core-td-api-generated').TdJsonRaw);
        if (!update) return;
        this.handleUpdate(update);
      }
    );
  }
  
  stop(): void {
    if (this.subscription) {
      this.subscription.unsubscribe();
      this.subscription = null;
    }
  }
  
  get state(): ChatListState {
    return {
      chatIds: [...this.orderedChatIds],
      isLoading: this.isLoading,
      hasMore: this.hasMore
    };
  }
  
  /**
   * 分页请求（FIX-001：良性跳过返回 null，不再当错误）。
   *
   * 「正在加载」与「已到末尾」都是**正常状态**，不是失败。此前这里返回
   * `err(AppErrors.internal('domain','Cannot load next page'))`，导致
   * ChatListCoordinator 把它当请求失败 → 打 error 日志 + 弹 "Cannot load
   * next page" toast。触发路径很常见：`start()` 派发 LoadChats 后，
   * ChatListPage 首次挂载时也可能再派发一次（它的守卫看的是 UI 状态
   * isLoading，而该值在投影 notify → sync 后就立刻回落 false，投影自己的
   * 请求其实还在飞），第二次必然撞上这里的守卫 → 每次冷启动都留一条假错误。
   *
   * 现对齐 MessageProjection.loadInitialMessages/loadOlderMessages 的既有约定：
   * `null` = 本次跳过、无需任何提示；调用方直接 return。
   */
  loadNextPage(limit: number = 20): Result<TdPendingRequest, AppError> | null {
    if (this.isLoading || !this.hasMore) {
      return null;
    }
    
    this.isLoading = true;
    this.notifyStateChanged();
    const req = new LoadChats();
    req.chat_list = this.chatList;
    req.limit = limit;
    
    const result = this.scope.request('loadChats', encodeLoadChats(req) as import('@tgx/td-gateway').TdWireObject);
    if (result.ok) {
      result.value.promise.then((res) => {
        this.isLoading = false;
        // 如果 TDLib 返回 404，表示到达列表末尾
        if (res.ok === false) {
          this.hasMore = false;
        }
        this.notifyStateChanged();
      }).catch(() => {
        this.isLoading = false;
        this.notifyStateChanged();
      });
    } else {
      this.isLoading = false;
      this.notifyStateChanged();
    }
    return result; // Type workaround for now
  }
  
  /**
   * 置顶/取消置顶会话（MSG-108 / FEAT-CHAT-002）：
   * toggleChatIsPinned(chat_list=本投影的列表, chat_id, is_pinned)。
   * 成功后 TDLib 推 updateChatPosition（新 order + is_pinned），本投影的
   * setChatPosition 会按 (order, id) 降序重排——置顶区自然浮到最前，
   * 因此这里不做乐观本地重排，避免与推送竞争产生二次跳动。
   */
  toggleChatIsPinned(chatId: number, isPinned: boolean): Result<TdPendingRequest, AppError> {
    const req: ToggleChatIsPinned = new ToggleChatIsPinned();
    req.chat_list = this.chatList;
    req.chat_id = chatId;
    req.is_pinned = isPinned;
    return this.scope.request('toggleChatIsPinned', encodeToggleChatIsPinned(req) as TdWireObject);
  }

  /** Move a chat between Main and Archive. TDLib emits position updates for both lists. */
  moveChatToList(chatId: number, targetList: TdChatList): Result<TdPendingRequest, AppError> {
    const req: AddChatToList = new AddChatToList();
    req.chat_id = chatId;
    req.chat_list = targetList;
    return this.scope.request('addChatToList', encodeAddChatToList(req) as TdWireObject);
  }

  /**
   * 手动标未读/取消标未读（MSG-108 / FEAT-CHAT-004 部分）：
   * toggleChatIsMarkedAsUnread(chat_id, is_marked_as_unread)。
   * 它只改"手动未读"标记，不产生未读消息数——未读徽标的数字仍由
   * unread_count 决定；标记置位且无未读消息时由 UI 出圆点徽标。
   * 成功后 TDLib 推 updateChatIsMarkedAsUnread，由 handleUpdate 就地刷新。
   */
  toggleChatIsMarkedAsUnread(chatId: number, isMarkedAsUnread: boolean): Result<TdPendingRequest, AppError> {
    const req: ToggleChatIsMarkedAsUnread = new ToggleChatIsMarkedAsUnread();
    req.chat_id = chatId;
    req.is_marked_as_unread = isMarkedAsUnread;
    return this.scope.request(
      'toggleChatIsMarkedAsUnread',
      encodeToggleChatIsMarkedAsUnread(req) as TdWireObject
    );
  }

  /**
   * 从会话列表把会话标记为已读（MSG-108）：
   * viewMessages(chat_id, [last_message_id], source=MessageSourceChatList, force_read=true)。
   *
   * force_read=true 是必需的——此刻会话是关闭的（用户在列表页），
   * 传 false 时 TDLib 会按"会话是否打开"判定而不入账。source 显式给
   * MessageSourceChatList 对齐 Android Tdlib.markAllAsRead 的读来源语义。
   * 成功后 TDLib 推 updateChatReadInbox（unread_count → 0），现有分支已处理。
   */
  markChatRead(chatId: number, lastMessageId: number): Result<TdPendingRequest, AppError> {
    if (lastMessageId <= 0) {
      return err<TdPendingRequest, AppError>(
        AppErrors.parameter('missing', 'last_message_id', 'chat has no last message to read')
      );
    }
    const req: ViewMessages = new ViewMessages();
    req.chat_id = chatId;
    req.message_ids = [lastMessageId];
    req.source = new MessageSourceChatList();
    req.force_read = true;
    return this.scope.request('viewMessages', encodeViewMessages(req) as TdWireObject);
  }

  private handleUpdate(update: TdUpdate): void {
    if (update.type === 'updateNewChat') {
      const chat = (update as UpdateNewChat).chat;
      if (chat) {
        this.registry.putChat(chat);
        this.updateChatPositionFromChat(chat);
      }
    } else if (update.type === 'updateChatPosition') {
      const posUpdate = update as UpdateChatPosition;
      const pos = posUpdate.position;
      if (pos && chatListEquals(pos.list, this.chatList)) {
        this.setChatPosition(posUpdate.chat_id, pos);
      } else {
        // 检查这个 updateChatPosition 是否把该 chat 移出了当前的 chatList
        const chat = this.registry.getChat(posUpdate.chat_id);
        if (chat) {
          // TDLib 机制：UpdateChatPosition 包含了 list。
          // 如果 list 与当前不同，说明在那个 list 里的位置改变。但这不代表移出了当前 list。
          // 实际上如果移除，TDLib 会发 UpdateChatPosition，其中 list=当前list，order="0"。
          const pos = posUpdate.position;
      if (pos && chatListEquals(pos.list, this.chatList)) {
             // 上面已经处理
          }
        }
      }
    } else if (update.type === 'updateChatLastMessage') {
      // 刷新 registry 里的 last_message，并按 update 携带的 positions 重排
      const lmUpdate = update as UpdateChatLastMessage;
      const chat = this.registry.getChat(lmUpdate.chat_id);
      if (chat) {
        chat.last_message = lmUpdate.last_message;
        const position = lmUpdate.positions.find((p: ChatPosition) => chatListEquals(p.list, this.chatList));
        if (position) {
          this.setChatPosition(lmUpdate.chat_id, position);
        } else {
          this.notifyStateChanged();
        }
      }
    } else if (update.type === 'updateChatReadInbox') {
      const readUpdate = update as UpdateChatReadInbox;
      const chat = this.registry.getChat(readUpdate.chat_id);
      if (chat) {
        chat.unread_count = readUpdate.unread_count;
        this.notifyStateChanged();
      }
    } else if (update.type === 'updateChatIsMarkedAsUnread') {
      // MSG-108：手动标未读标记变更（本端操作回执或他端同步）。就地刷新聊天
      // 列表行；列表顺序不受影响（标未读不改 order），因此无需重排。
      const markedUpdate = update as UpdateChatIsMarkedAsUnread;
      const chat = this.registry.getChat(markedUpdate.chat_id);
      if (chat) {
        chat.is_marked_as_unread = markedUpdate.is_marked_as_unread;
        this.notifyStateChanged();
      }
    } else if (update.type === 'updateChatPhoto') {
      const photoUpdate = update as UpdateChatPhoto;
      const chat = this.registry.getChat(photoUpdate.chat_id);
      if (chat) {
        chat.photo = photoUpdate.photo;
        this.notifyStateChanged();
      }
    } else if (update.type === 'updateChatTitle') {
      const titleUpdate = update as UpdateChatTitle;
      const chat = this.registry.getChat(titleUpdate.chat_id);
      if (chat) {
        chat.title = titleUpdate.title;
        this.notifyStateChanged();
      }
    } else if (update.type === 'updateChatDraftMessage') {
      const draftUpdate = update as UpdateChatDraftMessage;
      const chat = this.registry.getChat(draftUpdate.chat_id);
      if (chat) {
        chat.draft_message = draftUpdate.draft_message;
        const position = draftUpdate.positions.find((p: ChatPosition) => chatListEquals(p.list, this.chatList));
        if (position) {
          this.setChatPosition(draftUpdate.chat_id, position);
        } else {
          this.notifyStateChanged();
        }
      }
    }
  }
  
  private updateChatPositionFromChat(chat: Chat): void {
    const position = chat.positions.find((p: ChatPosition) => chatListEquals(p.list, this.chatList));
    if (position) {
      this.setChatPosition(chat.id, position);
    }
  }
  
  private setChatPosition(chatId: number, position: ChatPosition): void {
    // order 为 0 或 "0" 表示从列表中移除
    if (position.order === '0' || !position.order) {
      const idx = this.orderedChatIds.indexOf(chatId);
      if (idx >= 0) {
        this.orderedChatIds.splice(idx, 1);
        this.notifyStateChanged();
      }
      return;
    }
    
    // 如果已经在列表中，先移除
    const oldIdx = this.orderedChatIds.indexOf(chatId);
    if (oldIdx >= 0) {
      this.orderedChatIds.splice(oldIdx, 1);
    }
    
    // 找到合适的插入位置（按 order, id 降序）
    // 简单二分或线性查找插入点
    let insertIdx = 0;
    for (let i = 0; i < this.orderedChatIds.length; i++) {
      const otherId = this.orderedChatIds[i];
      const otherChat = this.registry.getChat(otherId);
      if (!otherChat) continue; // 不该发生
      
      const otherPos = otherChat.positions.find((p: ChatPosition) => chatListEquals(p.list, this.chatList));
      if (!otherPos) continue;
      
      if (compareChatOrder(position.order, chatId, otherPos.order, otherId) < 0) {
        // 当前 chat 应该排在 otherChat 之前
        break;
      }
      insertIdx++;
    }
    
    this.orderedChatIds.splice(insertIdx, 0, chatId);
    
    // 同步更新 Registry 中的 position 状态（UpdateChatPosition 不携带整个 Chat，需要手动 patch Registry 中的 Chat）
    const chat = this.registry.getChat(chatId);
    if (chat) {
      const posIdx = chat.positions.findIndex((p: ChatPosition) => chatListEquals(p.list, this.chatList));
      if (posIdx >= 0) {
        chat.positions[posIdx] = position;
      } else {
        chat.positions.push(position);
      }
    }
    this.notifyStateChanged();
  }
}
