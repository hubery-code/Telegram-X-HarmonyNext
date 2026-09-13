/**
 * feature/chat_list — 会话列表协调器（CHATLIST-003 + MSG-108）。
 *
 * 桥接 core/domain 的 ChatListProjection 与本模块的 MVI：
 * - dispatch 经 chatListReducer 驱动 ChatListUiState，并执行 Effect
 *   （FetchChatList → projection.loadNextPage）；
 * - projection 状态变化时把 registry 中的 Chat 映射为 ChatListItem[]，
 *   经 OnChatsLoaded 回灌 reducer；
 * - TDLib 更新在登录初期成批到达，经 setTimeout(0) 合并为一个同步点，
 *   避免整表反复重绘。
 *
 * MSG-108 新增：映射时带上置顶态（ChatPosition.is_pinned）与手动未读标记；
 * 执行 SetChatPinned / SetChatReadState。"标记已读"要拆成两步——清手动未读
 * 标记 + 用 viewMessages(force_read) 把未读消息读掉，两者都是独立请求。
 */

import { hilog } from '@kit.PerformanceAnalysisKit';
import { ManualClock, SequentialIdGenerator, AppError, AppErrors } from '@tgx/core-common';
import { AccountScope } from '@tgx/core-account';
import {
  Chat,
  ChatListMain,
  File,
  Message,
  MessageSticker,
  MessageText,
  TdMessageContent
} from '@tgx/core-td-api-generated';
import {
  ChatListProjection,
  ChatListState,
  ChatRegistry,
  FileRegistry,
  isChatPinnedInList,
  Subscription
} from '@tgx/core-domain';
import { TdPendingRequest, TdWireObject } from '@tgx/td-gateway';
import { Result } from '@tgx/core-common';
import { ReducerEnv, ReducerResult } from '@tgx/feature-template';
import { ChatListItem, avatarColorForChatId, avatarLetterForTitle } from '../model/ChatListItem';
import { ChatListUiState } from '../contract/ChatListUiState';
import {
  ChatListIntent,
  LoadChats,
  OnChatsLoaded,
  OnChatsLoadFailed,
  OnChatActionFailed
} from '../contract/ChatListIntent';
import {
  ChatListEffect,
  FetchChatList,
  NavigateToChat,
  ShowToast,
  SetChatPinned,
  SetChatReadState
} from '../contract/ChatListEffect';
import { chatListReducer } from '../reducer/ChatListReducer';

const DOMAIN: number = 0x0000;
const TAG: string = 'ChatListCoordinator';

export type ChatListUiStateListener = (state: ChatListUiState) => void;

/** 最后一条消息的一行预览文案；多媒体消息用占位标签。 */
function messagePreview(message: Message | null): string {
  if (message === null || message.content === null) {
    return '';
  }
  const content: TdMessageContent = message.content;
  switch (content.type) {
    case 'messageText': {
      const text = (content as MessageText).text;
      return text !== null ? text.text.split('\n').join(' ') : '';
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
      const stickerContent: MessageSticker = message.content as MessageSticker;
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
    default:
      return '';
  }
}

export class ChatListCoordinator {
  private readonly registry: ChatRegistry;
  private readonly projection: ChatListProjection;
  private readonly fileRegistry: FileRegistry;
  private readonly scope: AccountScope;
  private readonly env: ReducerEnv;
  private readonly onNavigateToChat: (chatId: number, chatTitle: string) => void;
  private currentState: ChatListUiState;
  private readonly listeners: ChatListUiStateListener[] = [];
  private readonly requestedAvatarFileIds: Set<number> = new Set();
  private readonly avatarSubscriptions: Map<number, Subscription> = new Map();
  private syncScheduled: boolean = false;
  private destroyed: boolean = false;
  /** MSG-108：本页对应的 TDLib 会话列表（置顶态要按列表判定，不能只看 chat 自身）。 */
  private readonly chatList: ChatListMain;

  constructor(
    scope: AccountScope,
    env?: ReducerEnv,
    onNavigateToChat?: (chatId: number, chatTitle: string) => void
  ) {
    this.registry = new ChatRegistry();
    this.chatList = new ChatListMain();
    this.projection = new ChatListProjection(this.chatList, this.registry, scope);
    this.fileRegistry = new FileRegistry(scope);
    // MSG-108：置顶/标未读是"改现状"的操作，请求级失败要回灌到操作菜单调用方，
    // 所以这里保留 scope 引用（投影只暴露状态，不暴露请求能力）。
    this.scope = scope;
    this.env = env !== undefined ? env : {
      clock: new ManualClock(1000, 500),
      ids: new SequentialIdGenerator('chat-list-')
    };
    this.onNavigateToChat = onNavigateToChat !== undefined ? onNavigateToChat : (chatId: number, chatTitle: string): void => {};
    this.currentState = ChatListUiState.initial();
  }

  get state(): ChatListUiState {
    return this.currentState;
  }

  /**
   * FIX-001：按 chatId 查已注册会话的标题。
   *
   * 存在的意义是给**跨 feature** 的只读查询当桥：搜索结果（feature/search）
   * 只从 TDLib 拿到 chat_ids，自己没有会话元数据；而 feature/* 之间禁止互相
   * 依赖，所以由装配层把本方法包成回调注入 SearchCoordinator（见 entry）。
   * 命中 TDLib 通过 updateNewChat 推来的本地缓存，无网络往返。
   * 未注册（如按用户名搜到的、还不在会话列表里的公开会话）返回 null。
   *
   * 注：本版 TDLib 的 `Chat` 没有 `username` 字段（已移到 full-info 类），
   * 因此只提供标题；搜索结果的 @用户名此前显示的是伪值 `chat_<id>`，现留空。
   */
  getChatTitle(chatId: number): string | null {
    const chat: Chat | undefined = this.registry.getChat(chatId);
    return chat !== undefined ? chat.title : null;
  }

  start(): void {
    this.projection.setOnStateChanged(() => {
      this.scheduleSyncFromProjection();
    });
    this.projection.start();
    this.dispatch(new LoadChats());
  }

  destroy(): void {
    this.destroyed = true;
    this.projection.setOnStateChanged(null);
    this.projection.stop();
    this.fileRegistry.stop();
    const subs: Subscription[] = Array.from(this.avatarSubscriptions.values());
    for (let i = 0; i < subs.length; i++) {
      subs[i].unsubscribe();
    }
    this.avatarSubscriptions.clear();
    this.requestedAvatarFileIds.clear();
    this.listeners.length = 0;
  }

  subscribe(listener: ChatListUiStateListener): () => void {
    this.listeners.push(listener);
    listener(this.currentState);
    return () => {
      const idx: number = this.listeners.indexOf(listener);
      if (idx >= 0) {
        this.listeners.splice(idx, 1);
      }
    };
  }

  dispatch(intent: ChatListIntent): void {
    const result: ReducerResult<ChatListUiState, ChatListEffect> = chatListReducer(
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
    const projectionState: ChatListState = this.projection.state;
    const items: ChatListItem[] = this.mapChatsToItems(projectionState.chatIds);
    this.dispatch(new OnChatsLoaded(items));
  }

  private requestAvatarDownload(fileId: number): void {
    if (this.destroyed || fileId <= 0) {
      return;
    }
    if (this.fileRegistry.isDownloaded(fileId)) {
      return;
    }
    if (this.requestedAvatarFileIds.has(fileId)) {
      return;
    }
    this.requestedAvatarFileIds.add(fileId);

    if (!this.avatarSubscriptions.has(fileId)) {
      const sub: Subscription = this.fileRegistry.subscribeFile(fileId, (file: File) => {
        if (!this.destroyed && file.local !== null && file.local.is_downloading_completed) {
          this.scheduleSyncFromProjection();
        }
      });
      this.avatarSubscriptions.set(fileId, sub);
    }
    this.fileRegistry.downloadFile(fileId, 2);
  }

  private mapChatsToItems(chatIds: readonly number[]): ChatListItem[] {
    const items: ChatListItem[] = [];
    for (let i = 0; i < chatIds.length; i++) {
      const chat: Chat | undefined = this.registry.getChat(chatIds[i]);
      if (chat === undefined) {
        continue;
      }
      let avatarPath: string | null = null;
      if (chat.photo !== null && chat.photo.small !== null) {
        const smallFile: File = chat.photo.small;
        this.fileRegistry.putFile(smallFile);
        if (smallFile.local !== null && smallFile.local.is_downloading_completed && smallFile.local.path.length > 0) {
          avatarPath = smallFile.local.path;
        } else if (this.fileRegistry.isDownloaded(smallFile.id)) {
          avatarPath = this.fileRegistry.getLocalPath(smallFile.id);
        }
        if (avatarPath === null) {
          this.requestAvatarDownload(smallFile.id);
        }
      }
      items.push(new ChatListItem(
        chat.id,
        chat.title,
        messagePreview(chat.last_message),
        chat.last_message !== null ? chat.last_message.date * 1000 : 0,
        chat.unread_count,
        avatarColorForChatId(chat.id),
        avatarLetterForTitle(chat.title),
        // MSG-108：置顶态取 ChatPosition.is_pinned（按本页的 chatList 判定），
        // 手动未读标记独立于 unread_count。
        isChatPinnedInList(chat, this.chatList),
        chat.is_marked_as_unread,
        avatarPath
      ));
    }
    return items;
  }

  private executeEffect(effect: ChatListEffect): void {
    switch (effect.kind) {
      case 'fetchChatList': {
        const fetchEffect: FetchChatList = effect as FetchChatList;
        const result = this.projection.loadNextPage(fetchEffect.limit);
        // FIX-001：null = 投影正在加载或已到末尾，属正常跳过——不打日志、不报错、
        // 不弹 toast（此前把守卫当错误，冷启动必留一条假错误）。
        if (result === null) {
          break;
        }
        hilog.info(DOMAIN, TAG, 'executing loadChats limit=%{public}d', fetchEffect.limit);
        if (result.err) {
          hilog.error(DOMAIN, TAG, 'loadChats rejected: %{public}s', result.error.message);
          this.dispatch(new OnChatsLoadFailed(result.error));
        }
        if (result.ok) {
          // 请求级成功但响应级可能失败：回灌 OnChatsLoadFailed，避免静默卡在 loading。
          result.value.promise.then((res: Result<TdWireObject, AppError>) => {
            if (this.destroyed) {
              return;
            }
            if (res.err) {
              hilog.error(DOMAIN, TAG, 'loadChats failed: %{public}s', AppErrors.toLogString(res.error));
              this.dispatch(new OnChatsLoadFailed(res.error));
            }
          }).catch(() => {
          });
        }
        break;
      }

      case 'navigateToChat': {
        const navigateEffect: NavigateToChat = effect as NavigateToChat;
        hilog.info(DOMAIN, TAG, 'chat selected: %{public}s', `${navigateEffect.chatId}`);
        const chat: Chat | undefined = this.registry.getChat(navigateEffect.chatId);
        const chatTitle: string = chat !== undefined ? chat.title : '';
        this.onNavigateToChat(navigateEffect.chatId, chatTitle);
        break;
      }

      case 'showToast': {
        const toastEffect: ShowToast = effect as ShowToast;
        hilog.info(DOMAIN, TAG, 'toast: %{public}s', toastEffect.messageKey);
        break;
      }

      case 'setChatPinned': {
        const pin: SetChatPinned = effect as SetChatPinned;
        hilog.info(DOMAIN, TAG, 'toggleChatIsPinned chatId=%{public}s isPinned=%{public}s',
          `${pin.chatId}`, `${pin.isPinned}`);
        const result: Result<TdPendingRequest, AppError> =
          this.projection.toggleChatIsPinned(pin.chatId, pin.isPinned);
        this.settleChatAction(result, 'toggleChatIsPinned');
        break;
      }

      case 'setChatReadState': {
        const readState: SetChatReadState = effect as SetChatReadState;
        hilog.info(DOMAIN, TAG, 'setChatReadState chatId=%{public}s markAsUnread=%{public}s',
          `${readState.chatId}`, `${readState.markAsUnread}`);
        if (readState.markAsUnread) {
          // 标未读：只置手动标记。未读数是 TDLib 的事，本端不臆造。
          const markResult: Result<TdPendingRequest, AppError> =
            this.projection.toggleChatIsMarkedAsUnread(readState.chatId, true);
          this.settleChatAction(markResult, 'toggleChatIsMarkedAsUnread(true)');
        } else {
          // 标记已读 = 清手动标记 + 把未读消息读掉（对齐 Android Tdlib.markAllAsRead：
          // 有未读数先 readMessages，再看 isMarkedAsUnread 清标记）。两件事独立请求，
          // 各自失败各自回灌；清标记无条件发（幂等），读消息需要 lastMessageId。
          const clearResult: Result<TdPendingRequest, AppError> =
            this.projection.toggleChatIsMarkedAsUnread(readState.chatId, false);
          this.settleChatAction(clearResult, 'toggleChatIsMarkedAsUnread(false)');

          const chat: Chat | undefined = this.registry.getChat(readState.chatId);
          const lastMessageId: number = (chat !== undefined && chat.last_message !== null)
            ? chat.last_message.id
            : 0;
          if (chat !== undefined && chat.unread_count > 0 && lastMessageId > 0) {
            const readResult: Result<TdPendingRequest, AppError> =
              this.projection.markChatRead(readState.chatId, lastMessageId);
            this.settleChatAction(readResult, 'viewMessages(read)');
          }
        }
        break;
      }

      default:
        break;
    }
  }

  /**
   * MSG-108：置顶/标未读请求的失败统一回灌。
   * 请求级拒绝（result.err）与响应级失败（promise 里 res.err）走同一条
   * OnChatActionFailed → errorMessage 路径；成功无本地乐观改动——置顶靠
   * updateChatPosition 重排、已读靠 updateChatReadInbox、标未读靠
   * updateChatIsMarkedAsUnread，都由投影订阅推回来，避免与推送打架。
   */
  private settleChatAction(result: Result<TdPendingRequest, AppError>, label: string): void {
    if (result.err) {
      hilog.error(DOMAIN, TAG, '%{public}s rejected: %{public}s', label, AppErrors.toLogString(result.error));
      this.dispatch(new OnChatActionFailed(result.error));
      return;
    }
    if (result.ok) {
      result.value.promise.then((res: Result<TdWireObject, AppError>) => {
        if (this.destroyed) {
          return;
        }
        if (res.err) {
          hilog.error(DOMAIN, TAG, '%{public}s failed: %{public}s', label, AppErrors.toLogString(res.error));
          this.dispatch(new OnChatActionFailed(res.error));
        }
        if (res.ok) {
          hilog.info(DOMAIN, TAG, '%{public}s ok', label);
        }
      }).catch(() => {
      });
    }
  }
}
