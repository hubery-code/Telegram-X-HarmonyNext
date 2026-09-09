import { encodeLoadChats, decodeTdUpdate,

 ChatListFolder,

  Chat,
  ChatPosition,
  TdChatList,
  TdUpdate,
  UpdateNewChat,
  UpdateChatPosition,
  LoadChats,
} from '@tgx/core-td-api-generated';
import { ChatRegistry } from './ChatRegistry';
import { AccountScope } from '@tgx/core-account';
import { TdPendingRequest } from '@tgx/td-gateway';
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
  
  constructor(chatList: TdChatList | null, registry: ChatRegistry, scope: AccountScope) {
    this.chatList = chatList;
    this.registry = registry;
    this.scope = scope;
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
  
  /** 分页请求 */
  loadNextPage(limit: number = 20): Result<TdPendingRequest, AppError> {
    if (this.isLoading || !this.hasMore) {
      return err(AppErrors.internal('domain', 'Cannot load next page'));
    }
    
    this.isLoading = true;
    const req = new LoadChats();
    req.chat_list = this.chatList;
    req.limit = limit;
    
    const result = this.scope.request('loadChats', encodeLoadChats(req) as import('@tgx/td-gateway').TdWireObject);
    if (result.ok) {
      result.value.promise.then((res) => {
        this.isLoading = false;
        // 如果 TDLib 返回 404，表示到达列表末尾
        if (res.ok === false) {
          // In a real app we might check the actual TDLib error code or kind
          this.hasMore = false;
        }
          this.hasMore = false;
        }
      }).catch(() => {
        this.isLoading = false;
      });
    } else {
      this.isLoading = false;
    }
    return result; // Type workaround for now
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
      if (posUpdate.position && chatListEquals(posUpdate.position.list, this.chatList)) {
        this.setChatPosition(posUpdate.chat_id, posUpdate.position);
      } else {
        // 检查这个 updateChatPosition 是否把该 chat 移出了当前的 chatList
        const chat = this.registry.getChat(posUpdate.chat_id);
        if (chat) {
          // TDLib 机制：UpdateChatPosition 包含了 list。
          // 如果 list 与当前不同，说明在那个 list 里的位置改变。但这不代表移出了当前 list。
          // 实际上如果移除，TDLib 会发 UpdateChatPosition，其中 list=当前list，order="0"。
          if (posUpdate.position && chatListEquals(posUpdate.position.list, this.chatList)) {
             // 上面已经处理
          }
        }
      }
    }
  }
  
  private updateChatPositionFromChat(chat: Chat): void {
    const position = chat.positions.find(p => chatListEquals(p.list, this.chatList));
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
      
      const otherPos = otherChat.positions.find(p => chatListEquals(p.list, this.chatList));
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
      const posIdx = chat.positions.findIndex(p => chatListEquals(p.list, this.chatList));
      if (posIdx >= 0) {
        chat.positions[posIdx] = position;
      } else {
        chat.positions.push(position);
      }
    }
  }
}
