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
 *
 * DRAWER-101 新增：抽屉账号头由本协调器负责（getMe + FileRegistry 头像下载），
 * 菜单项导航经 DrawerNavigate 回调交回装配层；"我的收藏"用
 * createPrivateChat(my_id) 解析成与自己的私聊后复用 ChatSelected 导航链路。
 */

import { Logger } from '@tgx/observability';
import { ManualClock, SequentialIdGenerator, AppError, AppErrors } from '@tgx/core-common';
import { AccountScope } from '@tgx/core-account';
import {
  Chat,
  ChatListMain,
  ChatListArchive,
  TdChatList,
  File,
  GetMe,
  encodeGetMe,
  CreatePrivateChat,
  encodeCreatePrivateChat,
  ProfilePhoto,
  User,
  decodeUser,
  decodeChat,
  Message,
  MessageSticker,
  MessageText,
  DraftMessageContentText,
  TdMessageContent,
  TdJsonRaw,
  ChatTypePrivate,
  ChatTypeSupergroup
} from '@tgx/core-td-api-generated';
import {
  ChatListProjection,
  ChatListState,
  ChatRegistry,
  FileRegistry,
  formatFullName,
  getAvatarLetters,
  isChatPinnedInList,
  Subscription
} from '@tgx/core-domain';
import { TdPendingRequest, TdWireObject } from '@tgx/td-gateway';
import { Result } from '@tgx/core-common';
import { ReducerEnv, ReducerResult } from '@tgx/feature-template';
import { ChatListItem, ChatCategory, avatarColorForChatId, avatarLetterForTitle } from '../model/ChatListItem';
import { ChatListUiState, ChatFolderTab } from '../contract/ChatListUiState';
import { DrawerNavTarget } from '../contract/DrawerState';
import {
  ChatListIntent,
  ChatSelected,
  LoadChats,
  DrawerAccountRequested,
  OnChatsLoaded,
  OnChatsLoadFailed,
  OnChatActionFailed,
  OnDrawerAccountLoaded,
  OnDrawerAvatarLoaded
} from '../contract/ChatListIntent';
import {
  ChatListEffect,
  FetchChatList,
  NavigateToChat,
  ShowToast,
  SetChatPinned,
  SetChatReadState,
  SetChatArchived,
  FetchDrawerAccount,
  DrawerNavigate,
  OpenSavedMessages
} from '../contract/ChatListEffect';
import { chatListReducer } from '../reducer/ChatListReducer';

const TAG: string = 'ChatListCoordinator';

/** DRAWER-101：账号头头像与列表行头像同优先级（小图，走同一条下载通道）。 */
const DRAWER_AVATAR_PRIORITY: number = 2;

/**
 * DRAWER-101："我的收藏"在 TDLib 里就是与自己的私聊，chat.title 是自己的名字。
 * TGX/官方客户端都在本地把这条会话改称 Saved Messages，这里对齐同一行为。
 */
export const SAVED_MESSAGES_TITLE: string = 'Saved Messages';

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
  private readonly mainProjection: ChatListProjection;
  private readonly archiveProjection: ChatListProjection;
  private readonly fileRegistry: FileRegistry;
  private readonly scope: AccountScope;
  private readonly env: ReducerEnv;
  private readonly onNavigateToChat: (chatId: number, chatTitle: string) => void;
  private readonly onDrawerNavigate: (target: DrawerNavTarget) => void;
  private currentState: ChatListUiState;
  private readonly listeners: ChatListUiStateListener[] = [];
  private readonly requestedAvatarFileIds: Set<number> = new Set();
  private readonly avatarSubscriptions: Map<number, Subscription> = new Map();
  private syncScheduled: boolean = false;
  private destroyed: boolean = false;

  /** DRAWER-101：getMe 在途标记（reducer 的幂等守卫看的是回灌后的状态，挡不住连点）。 */
  private drawerAccountFetching: boolean = false;
  private drawerAvatarSubscription: Subscription | null = null;
  /** DRAWER-101：Saved Messages = 与自己的私聊，chatId 解析一次即缓存。 */
  private savedMessagesChatId: number = 0;
  private savedMessagesResolving: boolean = false;
  /** CHAT-003：支持 Main 与 Archive 两个 TDLib 列表投影。 */
  private readonly mainList: ChatListMain;
  private readonly archiveList: ChatListArchive;
  private readonly logger: Logger;

  constructor(
    scope: AccountScope,
    env?: ReducerEnv,
    onNavigateToChat?: (chatId: number, chatTitle: string) => void,
    logger?: Logger,
    onDrawerNavigate?: (target: DrawerNavTarget) => void
  ) {
    this.registry = new ChatRegistry();
    this.mainList = new ChatListMain();
    this.archiveList = new ChatListArchive();
    this.mainProjection = new ChatListProjection(this.mainList, this.registry, scope);
    this.archiveProjection = new ChatListProjection(this.archiveList, this.registry, scope);
    this.fileRegistry = new FileRegistry(scope);
    // MSG-108：置顶/标未读是"改现状"的操作，请求级失败要回灌到操作菜单调用方，
    // 所以这里保留 scope 引用（投影只暴露状态，不暴露请求能力）。
    this.scope = scope;
    this.env = env !== undefined ? env : {
      clock: new ManualClock(1000, 500),
      ids: new SequentialIdGenerator('chat-list-')
    };
    this.onNavigateToChat = onNavigateToChat !== undefined ? onNavigateToChat : (chatId: number, chatTitle: string): void => {};
    this.onDrawerNavigate = onDrawerNavigate !== undefined
      ? onDrawerNavigate
      : (target: DrawerNavTarget): void => {};
    this.logger = logger !== undefined ? logger : new Logger();
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
    if (chat === undefined) {
      return null;
    }
    return this.isSavedMessagesChat(chat) ? SAVED_MESSAGES_TITLE : chat.title;
  }

  /**
   * DRAWER-101：是否"我的收藏"（与自己的私聊）。
   * 判据用 chatTypePrivate.user_id 与 my_id 相等，而不是"私聊 chatId == 用户 id"
   * 这条口头约定；createPrivateChat 已回过话时再按 chatId 兜一次。
   */
  private isSavedMessagesChat(chat: Chat): boolean {
    if (this.savedMessagesChatId > 0 && chat.id === this.savedMessagesChatId) {
      return true;
    }
    const myUserId: number = this.currentState.drawer.accountUserId;
    if (myUserId <= 0 || chat.type_ === null || chat.type_ === undefined) {
      return false;
    }
    return chat.type_.type === 'chatTypePrivate'
      && (chat.type_ as ChatTypePrivate).user_id === myUserId;
  }

  start(): void {
    this.mainProjection.setOnStateChanged(() => {
      this.scheduleSyncFromProjection();
    });
    this.archiveProjection.setOnStateChanged(() => {
      this.scheduleSyncFromProjection();
    });
    this.mainProjection.start();
    this.archiveProjection.start();
    this.archiveProjection.loadNextPage(20);
    this.dispatch(new LoadChats());
    // DRAWER-101：预热抽屉账号头（此前由装配层自己发 getMe，抽屉状态游离在 reducer 之外）。
    this.dispatch(new DrawerAccountRequested());
  }

  destroy(): void {
    this.destroyed = true;
    this.mainProjection.setOnStateChanged(null);
    this.mainProjection.stop();
    this.archiveProjection.setOnStateChanged(null);
    this.archiveProjection.stop();
    this.fileRegistry.stop();
    const subs: Subscription[] = Array.from(this.avatarSubscriptions.values());
    for (let i = 0; i < subs.length; i++) {
      subs[i].unsubscribe();
    }
    this.avatarSubscriptions.clear();
    this.requestedAvatarFileIds.clear();
    if (this.drawerAvatarSubscription !== null) {
      this.drawerAvatarSubscription.unsubscribe();
      this.drawerAvatarSubscription = null;
    }
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
    const isArchive: boolean = this.currentState.listKind === 'archive';
    const currentProjection: ChatListProjection = isArchive ? this.archiveProjection : this.mainProjection;
    const currentList: TdChatList = isArchive ? this.archiveList : this.mainList;
    const items: ChatListItem[] = this.mapChatsToItems(currentProjection.state.chatIds, currentList);

    let archiveUnreadCount: number = 0;
    const archiveChatIds: readonly number[] = this.archiveProjection.state.chatIds;
    for (let i = 0; i < archiveChatIds.length; i++) {
      const chat: Chat | undefined = this.registry.getChat(archiveChatIds[i]);
      if (chat !== undefined && chat.unread_count > 0) {
        archiveUnreadCount += chat.unread_count;
      }
    }
    const archiveChatCount: number = archiveChatIds.length;

    let allUnread: number = 0;
    let personalUnread: number = 0;
    let groupsUnread: number = 0;
    let channelsUnread: number = 0;
    let unreadTotal: number = 0;

    for (let i = 0; i < items.length; i++) {
      const item: ChatListItem = items[i];
      const isUnread: boolean = item.unreadCount > 0 || item.isMarkedAsUnread;
      if (isUnread) {
        allUnread++;
        unreadTotal++;
        if (item.category === 'private') {
          personalUnread++;
        } else if (item.category === 'group') {
          groupsUnread++;
        } else if (item.category === 'channel') {
          channelsUnread++;
        }
      }
    }

    const folders: readonly ChatFolderTab[] = [
      { id: 'all', title: 'All', unreadCount: allUnread },
      { id: 'personal', title: 'Personal', unreadCount: personalUnread },
      { id: 'groups', title: 'Groups', unreadCount: groupsUnread },
      { id: 'channels', title: 'Channels', unreadCount: channelsUnread },
      { id: 'unread', title: 'Unread', unreadCount: unreadTotal }
    ];

    this.dispatch(new OnChatsLoaded(items, archiveUnreadCount, archiveChatCount, folders));
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

  private mapChatsToItems(chatIds: readonly number[], currentList: TdChatList): ChatListItem[] {
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
      let draftText: string | null = null;
      if (chat.draft_message !== null && chat.draft_message !== undefined) {
        const draftContent = chat.draft_message.content;
        if (draftContent !== null && draftContent.type === 'draftMessageContentText') {
          const textObj = (draftContent as DraftMessageContentText).text;
          if (textObj !== null && textObj.text.trim().length > 0) {
            draftText = textObj.text.split('\n').join(' ');
          }
        }
      }
      let isMuted: boolean = false;
      if (chat.notification_settings !== null && chat.notification_settings !== undefined) {
        isMuted = chat.notification_settings.mute_for > 0;
      }
      let category: ChatCategory = 'private';
      if (chat.type_ !== null && chat.type_ !== undefined) {
        if (chat.type_.type === 'chatTypePrivate' || chat.type_.type === 'chatTypeSecret') {
          category = 'private';
        } else if (chat.type_.type === 'chatTypeBasicGroup') {
          category = 'group';
        } else if (chat.type_.type === 'chatTypeSupergroup') {
          const supergroup: ChatTypeSupergroup = chat.type_ as ChatTypeSupergroup;
          category = supergroup.is_channel ? 'channel' : 'group';
        }
      }
      items.push(new ChatListItem(
        chat.id,
        this.isSavedMessagesChat(chat) ? SAVED_MESSAGES_TITLE : chat.title,
        messagePreview(chat.last_message),
        chat.last_message !== null ? chat.last_message.date * 1000 : 0,
        chat.unread_count,
        avatarColorForChatId(chat.id),
        avatarLetterForTitle(chat.title),
        // MSG-108 / CHAT-003：置顶态按当前激活的 chatList 判定
        isChatPinnedInList(chat, currentList),
        chat.is_marked_as_unread,
        avatarPath,
        draftText,
        isMuted,
        category
      ));
    }
    return items;
  }

  private executeEffect(effect: ChatListEffect): void {
    switch (effect.kind) {
      case 'fetchChatList': {
        const fetchEffect: FetchChatList = effect as FetchChatList;
        const targetProjection: ChatListProjection =
          fetchEffect.listKind === 'archive' ? this.archiveProjection : this.mainProjection;
        const result = targetProjection.loadNextPage(fetchEffect.limit);
        // FIX-001：null = 投影正在加载或已到末尾，属正常跳过——不打日志、不报错、
        // 不弹 toast（此前把守卫当错误，冷启动必留一条假错误）。
        if (result === null) {
          break;
        }
        this.logger.info(TAG, 'executing_load_chats', `limit=${fetchEffect.limit},kind=${fetchEffect.listKind}`);
        if (result.err) {
          this.logger.logError(TAG, result.error);
          this.dispatch(new OnChatsLoadFailed(result.error));
        }
        if (result.ok) {
          // 请求级成功但响应级可能失败：回灌 OnChatsLoadFailed，避免静默卡在 loading。
          result.value.promise.then((res: Result<TdWireObject, AppError>) => {
            if (this.destroyed) {
              return;
            }
            if (res.err) {
              this.logger.logError(TAG, res.error);
              this.dispatch(new OnChatsLoadFailed(res.error));
            }
          }).catch(() => {
          });
        }
        break;
      }

      case 'navigateToChat': {
        const navigateEffect: NavigateToChat = effect as NavigateToChat;
        this.logger.info(TAG, 'chat_selected', `chatId=${navigateEffect.chatId}`);
        const registryTitle: string | null = this.getChatTitle(navigateEffect.chatId);
        this.onNavigateToChat(navigateEffect.chatId, registryTitle !== null ? registryTitle : '');
        break;
      }

      case 'showToast': {
        const toastEffect: ShowToast = effect as ShowToast;
        this.logger.info(TAG, 'toast', toastEffect.messageKey);
        break;
      }

      case 'setChatPinned': {
        const pin: SetChatPinned = effect as SetChatPinned;
        this.logger.info(TAG, 'toggle_chat_pinned', `chatId=${pin.chatId},isPinned=${pin.isPinned}`);
        const targetProjection: ChatListProjection =
          this.currentState.listKind === 'archive' ? this.archiveProjection : this.mainProjection;
        const result: Result<TdPendingRequest, AppError> =
          targetProjection.toggleChatIsPinned(pin.chatId, pin.isPinned);
        this.settleChatAction(result, 'toggleChatIsPinned');
        break;
      }

      case 'setChatReadState': {
        const readState: SetChatReadState = effect as SetChatReadState;
        this.logger.info(TAG, 'set_chat_read_state', `chatId=${readState.chatId},markAsUnread=${readState.markAsUnread}`);
        const targetProjection: ChatListProjection =
          this.currentState.listKind === 'archive' ? this.archiveProjection : this.mainProjection;
        if (readState.markAsUnread) {
          // 标未读：只置手动标记。未读数是 TDLib 的事，本端不臆造。
          const markResult: Result<TdPendingRequest, AppError> =
            targetProjection.toggleChatIsMarkedAsUnread(readState.chatId, true);
          this.settleChatAction(markResult, 'toggleChatIsMarkedAsUnread(true)');
        } else {
          // 标记已读 = 清手动标记 + 把未读消息读掉（对齐 Android Tdlib.markAllAsRead：
          // 有未读数先 readMessages，再看 isMarkedAsUnread 清标记）。两件事独立请求，
          // 各自失败各自回灌；清标记无条件发（幂等），读消息需要 lastMessageId。
          const clearResult: Result<TdPendingRequest, AppError> =
            targetProjection.toggleChatIsMarkedAsUnread(readState.chatId, false);
          this.settleChatAction(clearResult, 'toggleChatIsMarkedAsUnread(false)');

          const chat: Chat | undefined = this.registry.getChat(readState.chatId);
          const lastMessageId: number = (chat !== undefined && chat.last_message !== null)
            ? chat.last_message.id
            : 0;
          if (chat !== undefined && chat.unread_count > 0 && lastMessageId > 0) {
            const readResult: Result<TdPendingRequest, AppError> =
              targetProjection.markChatRead(readState.chatId, lastMessageId);
            this.settleChatAction(readResult, 'viewMessages(read)');
          }
        }
        break;
      }

      case 'setChatArchived': {
        const archiveEffect: SetChatArchived = effect as SetChatArchived;
        this.logger.info(TAG, 'toggle_chat_archived', `chatId=${archiveEffect.chatId},archived=${archiveEffect.archived}`);
        const targetList: TdChatList = archiveEffect.archived ? this.archiveList : this.mainList;
        const result: Result<TdPendingRequest, AppError> =
          this.mainProjection.moveChatToList(archiveEffect.chatId, targetList);
        this.settleChatAction(result, archiveEffect.archived ? 'addChatToList(archive)' : 'addChatToList(main)');
        break;
      }

      case 'fetchDrawerAccount': {
        this.fetchDrawerAccount();
        break;
      }

      case 'drawerNavigate': {
        const navigate: DrawerNavigate = effect as DrawerNavigate;
        this.logger.info(TAG, 'drawer_navigate', `target=${navigate.target}`);
        this.onDrawerNavigate(navigate.target);
        break;
      }

      case 'openSavedMessages': {
        this.openSavedMessages();
        break;
      }

      default:
        break;
    }
  }

  /**
   * DRAWER-101：拉当前账号（getMe）填抽屉账号头，并顺手发起头像下载。
   * drawerAccountFetching 是必须的：reducer 的幂等判断读的是"已回灌"的状态，
   * 请求在途时状态仍是空的，连点 ≡ 会重复发请求。
   */
  private fetchDrawerAccount(): void {
    if (this.destroyed || this.drawerAccountFetching) {
      return;
    }
    this.drawerAccountFetching = true;
    const req: GetMe = new GetMe();
    const res: Result<TdPendingRequest, AppError> =
      this.scope.request('getMe', encodeGetMe(req) as TdWireObject);
    // ArkTS 不会在提前 return 后收窄 Result，ok/err 两支各写一次（AGENTS.md §3.1）。
    if (res.err) {
      this.drawerAccountFetching = false;
      this.logger.logError(TAG, res.error);
      this.dispatch(new OnChatActionFailed(res.error));
    }
    if (res.ok) {
      res.value.promise.then((out: Result<TdWireObject, AppError>): void => {
        this.drawerAccountFetching = false;
        if (this.destroyed) {
          return;
        }
        if (out.err) {
          this.logger.logError(TAG, out.error);
          this.dispatch(new OnChatActionFailed(out.error));
        }
        if (out.ok) {
          const me: User | null = decodeUser(out.value as TdJsonRaw);
          if (me !== null) {
            this.dispatch(new OnDrawerAccountLoaded(
              me.id,
              formatFullName(me),
              me.phone_number !== null && me.phone_number !== undefined ? me.phone_number : '',
              getAvatarLetters(me)
            ));
            this.ensureDrawerAvatar(me);
          }
        }
      }).catch((): void => {
        this.drawerAccountFetching = false;
      });
    }
  }

  /** 账号头像：本地命中直接回灌路径；否则订阅 updateFile 后下载（与列表行头像同一套 FileRegistry）。 */
  private ensureDrawerAvatar(user: User): void {
    const photo: ProfilePhoto | null = user.profile_photo;
    if (photo === null || photo === undefined) {
      return;
    }
    const file: File | null = photo.small !== null && photo.small !== undefined
      ? photo.small
      : (photo.big !== null && photo.big !== undefined ? photo.big : null);
    if (file === null) {
      return;
    }
    this.fileRegistry.putFile(file);
    const localPath: string | null = this.fileRegistry.getLocalPath(file.id);
    if (localPath !== null) {
      this.dispatch(new OnDrawerAvatarLoaded(localPath));
      return;
    }
    if (this.drawerAvatarSubscription === null) {
      this.drawerAvatarSubscription = this.fileRegistry.subscribeFile(file.id, (updated: File): void => {
        if (this.destroyed) {
          return;
        }
        const path: string | null = this.fileRegistry.getLocalPath(updated.id);
        if (path !== null) {
          this.dispatch(new OnDrawerAvatarLoaded(path));
        }
      });
    }
    const res: Result<TdPendingRequest, AppError> =
      this.fileRegistry.downloadFile(file.id, DRAWER_AVATAR_PRIORITY);
    if (res.err) {
      this.logger.logError(TAG, res.error);
    }
  }

  /**
   * DRAWER-101：打开"我的收藏"。TDLib 里它就是与自己的私聊（Saved Messages），
   * 用 createPrivateChat(my_id) 解析——响应即完整 Chat，顺手写进 registry，
   * 这样导航到会话页时标题能同步命中本地缓存，不必等 updateNewChat。
   */
  private openSavedMessages(): void {
    if (this.destroyed || this.savedMessagesResolving) {
      return;
    }
    if (this.savedMessagesChatId > 0) {
      this.dispatch(new ChatSelected(this.savedMessagesChatId));
      return;
    }
    const knownUserId: number = this.currentState.drawer.accountUserId;
    if (knownUserId > 0) {
      this.requestSelfChat(knownUserId);
      return;
    }
    // 账号头还没回灌（冷启动 getMe 未回或失败）：先取 my_id 再解析自聊。
    this.savedMessagesResolving = true;
    const req: GetMe = new GetMe();
    const res: Result<TdPendingRequest, AppError> =
      this.scope.request('getMe', encodeGetMe(req) as TdWireObject);
    if (res.err) {
      this.savedMessagesResolving = false;
      this.logger.logError(TAG, res.error);
      this.dispatch(new OnChatActionFailed(res.error));
    }
    if (res.ok) {
      res.value.promise.then((out: Result<TdWireObject, AppError>): void => {
        this.savedMessagesResolving = false;
        if (this.destroyed) {
          return;
        }
        if (out.err) {
          this.logger.logError(TAG, out.error);
          this.dispatch(new OnChatActionFailed(out.error));
        }
        if (out.ok) {
          const me: User | null = decodeUser(out.value as TdJsonRaw);
          if (me !== null && me.id > 0) {
            this.requestSelfChat(me.id);
          }
        }
      }).catch((): void => {
        this.savedMessagesResolving = false;
      });
    }
  }

  private requestSelfChat(userId: number): void {
    this.savedMessagesResolving = true;
    const req: CreatePrivateChat = new CreatePrivateChat();
    req.user_id = userId;
    req.force = false;
    const res: Result<TdPendingRequest, AppError> =
      this.scope.request('createPrivateChat', encodeCreatePrivateChat(req) as TdWireObject);
    if (res.err) {
      this.savedMessagesResolving = false;
      this.logger.logError(TAG, res.error);
      this.dispatch(new OnChatActionFailed(res.error));
    }
    if (res.ok) {
      res.value.promise.then((out: Result<TdWireObject, AppError>): void => {
        this.savedMessagesResolving = false;
        if (this.destroyed) {
          return;
        }
        if (out.err) {
          this.logger.logError(TAG, out.error);
          this.dispatch(new OnChatActionFailed(out.error));
        }
        if (out.ok) {
          const chat: Chat | null = decodeChat(out.value as TdJsonRaw);
          if (chat !== null && chat.id > 0) {
            this.savedMessagesChatId = chat.id;
            this.logger.info(TAG, 'saved_messages_resolved', `chatId=${chat.id}`);
            this.registry.putChat(chat);
            this.dispatch(new ChatSelected(chat.id));
          }
        }
      }).catch((): void => {
        this.savedMessagesResolving = false;
      });
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
      this.logger.logError(TAG, result.error);
      this.dispatch(new OnChatActionFailed(result.error));
      return;
    }
    if (result.ok) {
      result.value.promise.then((res: Result<TdWireObject, AppError>) => {
        if (this.destroyed) {
          return;
        }
        if (res.err) {
          this.logger.logError(TAG, res.error);
          this.dispatch(new OnChatActionFailed(res.error));
        }
        if (res.ok) {
          this.logger.info(TAG, 'chat_action_ok', label);
        }
      }).catch(() => {
      });
    }
  }
}
