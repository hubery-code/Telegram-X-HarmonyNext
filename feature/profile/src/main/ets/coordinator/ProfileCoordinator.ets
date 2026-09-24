/**
 * feature/profile — 用户资料页协调器（PROFILE-101）。
 *
 * 数据链路（对齐 Android openPrivateProfile 的信息面）：
 * - getUser（经 core-domain UserRegistry，命中缓存即刻回灌，晚到经 updateUser/updateUserStatus
 *   订阅刷新）：展示名 / 用户名 / 手机号 / 在线状态 / 头像占位；
 * - getUserFullInfo（PROFILE-101 新增 registry 能力）：bio；
 * - 头像大图：FileRegistry 本地路径命中即用，未命中 downloadFile(priority 2) 并订阅
 *   updateFile，落盘后回灌路径。
 * - 「发消息」：createPrivateChat → 回包 Chat.id 交给装配层导航（effect 驱动）。
 *
 * 生命周期：构造即建 registries（其构造自带 start），start() 发请求，destroy() 停订阅。
 */

import { AccountScope } from '@tgx/core-account';
import { ManualClock, Result, AppError, SequentialIdGenerator } from '@tgx/core-common';
import {
  UserRegistry,
  FileRegistry,
  formatFullName,
  getAvatarLetters,
  getAvatarColorIndex,
  isChatMuted,
  withChatMuteFor
} from '@tgx/core-domain';
import {
  User,
  UserFullInfo,
  Chat,
  CreatePrivateChat,
  encodeCreatePrivateChat,
  decodeChat,
  GetGroupsInCommon,
  encodeGetGroupsInCommon,
  Chats,
  decodeChats,
  GetChat,
  encodeGetChat,
  Message,
  File,
  ChatNotificationSettings,
  SetChatNotificationSettings,
  encodeSetChatNotificationSettings,
  UpdateChatNotificationSettings,
  CreateNewSecretChat,
  encodeCreateNewSecretChat,
  SecretChat,
  decodeSecretChat,
  SetMessageSenderBlockList,
  encodeSetMessageSenderBlockList,
  MessageSenderUser,
  BlockListMain,
  TdBlockList,
  UpdateChatBlockList,
  TdUpdate,
  decodeTdUpdate,
  TdJsonRaw
} from '@tgx/core-td-api-generated';
import {
  TdPendingRequest,
  TdRoutedEvent,
  TdUpdateFilter,
  TdUpdateSubscription,
  TdWireObject
} from '@tgx/td-gateway';
import { Logger } from '@tgx/observability';
import { Subscription, ToastPort, FakeToast, AudioPlayerPort, FakeAudioPlayer } from '@tgx/platform-ports';
import { ReducerEnv, ReducerResult } from '@tgx/feature-template';
import { ProfileUiState } from '../contract/ProfileUiState';
import {
  ProfileIntent,
  OnProfileLoaded,
  OnBioLoaded,
  OnAvatarFileLoaded,
  OnProfileFailed,
  OnBirthdayLoaded,
  OnEmojiStatusLoaded,
  OnSharedContentLoaded,
  OnSharedGroupsLoaded,
  OnSharedContentFailed,
  OnSharedAudioPlaying,
  OpenSharedChatRequested,
  OnChatNotificationLoaded,
  OnChatNotificationFailed,
  OnPeerBlockLoaded,
  OnPeerBlockFailed
} from '../contract/ProfileIntent';
import {
  ProfileEffect,
  CreatePrivateChatEffect,
  FetchSharedContent,
  FetchSharedGroups,
  FetchMoreSharedContent,
  OpenSharedChatEffect,
  FetchChatNotification,
  SetChatNotification,
  CreateSecretChatEffect,
  SetPeerBlock,
  PlaySharedAudio,
  StopSharedAudio
} from '../contract/ProfileEffect';
import {
  SharedAudioItem,
  SharedContentRows,
  SharedGroupItem,
  SharedMediaItem
} from '../contract/SharedContentItems';
import {
  chatTypeLabel,
  messageContentSummary,
  withSharedAudioPath,
  withSharedMediaPath
} from '../model/SharedContentFormat';
import {
  mergeSharedRows,
  SHARED_PAGE_LIMIT,
  SHARED_TAB_GROUPS,
  SharedContentPage,
  SharedContentSearcher
} from '../model/SharedContentSearch';
import { profileReducer } from '../reducer/ProfileReducer';

const TAG: string = 'ProfileCoordinator';

/** 头像下载优先级（对齐 ChatCoordinator 拉取头像的 priority=2）。 */
const AVATAR_DOWNLOAD_PRIORITY: number = 2;

/** PROFILE-103：共享媒体缩略图下载优先级。 */
const SHARED_THUMB_DOWNLOAD_PRIORITY: number = 2;

/** 按当前日期计算周岁。 */
function ageOf(year: number, month: number, day: number, now: Date): number {
  let age: number = now.getFullYear() - year;
  const m: number = now.getMonth() + 1;
  const d: number = now.getDate();
  if (m < month || (m === month && d < day)) {
    age--;
  }
  return age < 0 ? 0 : age;
}

/**
 * PROFILE-103：UserFullInfo.birthdate → 'YYYY年M月D日 (N 岁)'（year=0 时仅 'M月D日'）。
 * 无生日返回空串。
 */
function formatBirthdayText(info: UserFullInfo, now: Date): string {
  const birth = info.birthdate;
  if (birth === null || birth === undefined) {
    return '';
  }
  if (birth.day <= 0 || birth.month <= 0 || birth.month > 12) {
    return '';
  }
  if (birth.year > 0) {
    const age: number = ageOf(birth.year, birth.month, birth.day, now);
    return `${birth.year}年${birth.month}月${birth.day}日 (${age} 岁)`;
  }
  return `${birth.month}月${birth.day}日`;
}

export interface ProfileCoordinatorOptions {
  /** 私聊创建成功后交给装配层导航（缺省 no-op）。 */
  readonly onOpenChat?: (chatId: number) => void;
  readonly logger?: Logger;
  /** ⋮ 菜单动作的结果提示（屏蔽写失败、对方不支持密聊等），缺省 FakeToast。 */
  readonly toastPort?: ToastPort;
  /** SHARED-AUDIO：音频播放器抽象；缺省 FakeAudioPlayer（无装配层注入时点按不外放）。 */
  readonly audioPlayerPort?: AudioPlayerPort;
}

export type ProfileUiStateListener = (uiState: ProfileUiState) => void;

/** PROFILE-101：在线状态文案（MVP 简化，不格式化 last seen 具体时间）。 */
function formatUserStatusText(user: User): string {
  const status = user.status;
  if (status === null || status === undefined) {
    return '';
  }
  switch (status.type) {
    case 'userStatusOnline':
      return 'online';
    case 'userStatusOffline':
    case 'userStatusRecently':
      return 'last seen recently';
    case 'userStatusLastWeek':
      return 'last seen within a week';
    case 'userStatusLastMonth':
      return 'last seen within a month';
    default:
      return '';
  }
}

/** 取展示用户名：优先 editable，其次第一个 active。 */
function primaryUsernameOf(user: User): string {
  const usernames = user.usernames;
  if (usernames === null || usernames === undefined) {
    return '';
  }
  if (usernames.editable_username.length > 0) {
    return usernames.editable_username;
  }
  if (usernames.active_usernames.length > 0) {
    return usernames.active_usernames[0];
  }
  return '';
}

/** UserFullInfo.bio 在本版 TDLib 生成类型里是 FormattedText（可空），取纯文本。 */
function bioTextOf(info: UserFullInfo): string {
  const bio = info.bio;
  if (bio === null || bio === undefined) {
    return '';
  }
  return bio.text;
}

/** PROFILE-103：有 emoji_status 时返回 '✨' 角标，否则空串。 */
function emojiStatusIndicator(user: User): string {
  if (user.emoji_status !== null && user.emoji_status !== undefined) {
    return '✨';
  }
  return '';
}

/** createPrivateChat 在途期间的一个等待方。 */
class PrivateChatWaiter {
  readonly onReady: (chatId: number) => void;
  readonly onFailed: () => void;

  constructor(onReady: (chatId: number) => void, onFailed: () => void) {
    this.onReady = onReady;
    this.onFailed = onFailed;
  }
}

export class ProfileCoordinator {
  private readonly scope: AccountScope;
  private readonly userId: number;
  private readonly userRegistry: UserRegistry;
  private readonly fileRegistry: FileRegistry;
  private readonly onOpenChat: (chatId: number) => void;
  private readonly toastPort: ToastPort;
  private readonly audioPlayerPort: AudioPlayerPort;
  private readonly logger: Logger;
  private readonly env: ReducerEnv;
  private currentState: ProfileUiState;
  private readonly listeners: ProfileUiStateListener[] = [];
  private readonly subscriptions: Subscription[] = [];
  /** 已订阅下载回调的头像 fileId，防重复订阅。 */
  private subscribedAvatarFileId: number = -1;
  /** PROFILE-103：已登记本地路径订阅的共享 fileId（缩略图与音频共用），防重复订阅。 */
  private readonly subscribedSharedFileIds: Set<number> = new Set();
  /** SHARED-AUDIO：音频还没落盘，落盘后自动续播的 fileId；0 = 无等待。 */
  private pendingPlayFileId: number = 0;
  /** PROFILE-103：共同群组 Tab 的分页游标（offset_chat_id）；内容 Tab 的游标在 searcher 内。 */
  private readonly nextOffsets: Map<number, number> = new Map();
  /** 共享内容媒体/文件/链接/音乐/语音的分页拉取（与群/频道资料页共用同一套规则，见 model/SharedContentSearch）。 */
  private readonly sharedSearcher: SharedContentSearcher;
  /** 缓存目标用户的 private chatId，避免重复调用 createPrivateChat。 */
  private cachedPrivateChatId: number = 0;
  /** createPrivateChat 在途时挂起的消费者，回包后统一放行。 */
  private privateChatWaiters: PrivateChatWaiter[] = [];
  private privateChatPending: boolean = false;
  /** PROFILE-103 收尾：会话通知设置快照（getChat 回读 / update 推送维护），写请求以它为底本。 */
  private chatNotificationSettings: ChatNotificationSettings | null = null;
  /** PROFILE-103 收尾：updateChatNotificationSettings 订阅句柄（destroy 时退订）。 */
  private notificationSubscription: TdUpdateSubscription | null = null;
  /** 已订阅通知推送的 chatId，避免每次回读都重订一份。 */
  private notificationChatId: number = 0;
  private destroyed: boolean = false;

  constructor(scope: AccountScope, userId: number, options?: ProfileCoordinatorOptions) {
    this.scope = scope;
    this.userId = userId;
    this.userRegistry = new UserRegistry(scope);
    this.fileRegistry = new FileRegistry(scope);
    this.onOpenChat = options !== undefined && options.onOpenChat !== undefined
      ? options.onOpenChat
      : (chatId: number): void => {};
    this.toastPort = options !== undefined && options.toastPort !== undefined
      ? options.toastPort
      : new FakeToast();
    this.audioPlayerPort = options !== undefined && options.audioPlayerPort !== undefined
      ? options.audioPlayerPort
      : new FakeAudioPlayer();
    this.logger = options !== undefined && options.logger !== undefined
      ? options.logger
      : new Logger();
    this.env = {
      clock: new ManualClock(1000, 500),
      ids: new SequentialIdGenerator('profile-')
    };
    const self: ProfileCoordinator = this;
    this.sharedSearcher = new SharedContentSearcher({
      request: (name: string, payload: TdWireObject): Result<TdPendingRequest, AppError> =>
        this.scope.request(name, payload),
      localPathOf: (fileId: number): string | null => self.sharedLocalPathOf(fileId),
      audioLocalPathOf: (fileId: number): string | null => self.fileRegistry.getLocalPath(fileId),
      senderNameOf: (userId: number): string => self.sharedSenderNameOf(userId),
      logger: this.logger,
      tag: TAG
    });
    this.currentState = ProfileUiState.initial(userId);
  }

  /**
   * SHARED-AUDIO：语音行的发送者昵称。私聊里发言人基本只有对方与自己，
   * 首屏 getUser 已经把两方拉进缓存；没命中时补一次请求，本行先回落到「语音消息」。
   */
  private sharedSenderNameOf(userId: number): string {
    if (userId === 0) {
      return '';
    }
    const user: User | null = this.userRegistry.getUser(userId);
    if (user === null) {
      this.userRegistry.requestUser(userId);
      return '';
    }
    return formatFullName(user);
  }

  get state(): ProfileUiState {
    return this.currentState;
  }

  start(): void {
    // 基础信息：缓存命中先回灌一帧（避免闪 loading），再请求刷新并订阅后续 update。
    const cached: User | null = this.userRegistry.getUser(this.userId);
    if (cached !== null) {
      this.pushUser(cached);
    }
    this.subscriptions.push(this.userRegistry.subscribeUser(this.userId, (user: User): void => {
      this.pushUser(user);
    }));
    const userRes: Result<TdPendingRequest, AppError> = this.userRegistry.requestUser(this.userId);
    if (userRes.err) {
      this.dispatch(new OnProfileFailed(userRes.error));
    }

    // 完整资料（bio + 生日）：同样缓存优先 + 订阅 updateUserFullInfo。
    const cachedInfo = this.userRegistry.getUserFullInfo(this.userId);
    if (cachedInfo !== null) {
      this.dispatch(new OnBioLoaded(bioTextOf(cachedInfo)));
      this.dispatch(new OnBirthdayLoaded(formatBirthdayText(cachedInfo, new Date())));
    }
    this.subscriptions.push(this.userRegistry.subscribeUserFullInfo(this.userId, (info: UserFullInfo): void => {
      if (!this.destroyed) {
        this.dispatch(new OnBioLoaded(bioTextOf(info)));
        this.dispatch(new OnBirthdayLoaded(formatBirthdayText(info, new Date())));
      }
    }));
    const infoRes: Result<TdPendingRequest, AppError> = this.userRegistry.requestUserFullInfo(this.userId);
    if (infoRes.err) {
      // bio 失败不阻塞页面（基础信息已在拉），只记日志。
      this.logger.logError(TAG, infoRes.error);
    }
  }

  dispatch(intent: ProfileIntent): void {
    const result: ReducerResult<ProfileUiState, ProfileEffect> = profileReducer(
      this.currentState,
      intent,
      this.env
    );
    if (result.state !== this.currentState) {
      this.currentState = result.state;
      for (let i = 0; i < this.listeners.length; i++) {
        this.listeners[i](this.currentState);
      }
    }
    for (let i = 0; i < result.effects.length; i++) {
      this.executeEffect(result.effects[i]);
    }
  }

  subscribe(listener: ProfileUiStateListener): () => void {
    this.listeners.push(listener);
    listener(this.currentState);
    return (): void => {
      const index: number = this.listeners.indexOf(listener);
      if (index >= 0) {
        this.listeners.splice(index, 1);
      }
    };
  }

  destroy(): void {
    if (this.destroyed) {
      return;
    }
    this.destroyed = true;
    this.sharedSearcher.destroy();
    this.pendingPlayFileId = 0;
    this.audioPlayerPort.stop().catch((): void => {});
    for (let i = 0; i < this.subscriptions.length; i++) {
      this.subscriptions[i].unsubscribe();
    }
    this.subscriptions.length = 0;
    this.listeners.length = 0;
    if (this.notificationSubscription !== null) {
      this.notificationSubscription.unsubscribe();
      this.notificationSubscription = null;
    }
    this.fileRegistry.stop();
    this.userRegistry.stop();
  }

  /** getUser 缓存/回包/update → 状态回灌 + 头像文件解析。 */
  private pushUser(user: User): void {
    this.dispatch(new OnProfileLoaded(
      formatFullName(user),
      primaryUsernameOf(user),
      user.phone_number !== null && user.phone_number !== undefined ? user.phone_number : '',
      formatUserStatusText(user),
      getAvatarLetters(user),
      getAvatarColorIndex(user.id)
    ));
    this.dispatch(new OnEmojiStatusLoaded(emojiStatusIndicator(user)));
    this.resolveAvatarFile(user);
  }

  /** 大头像（profile_photo.big）：本地命中即用；未命中下载并订阅 updateFile 回灌路径。 */
  private resolveAvatarFile(user: User): void {
    const photo = user.profile_photo;
    if (photo === null || photo === undefined || photo.big === null || photo.big === undefined) {
      return;
    }
    const fileId: number = photo.big.id;
    const localPath: string | null = this.fileRegistry.getLocalPath(fileId);
    if (localPath !== null) {
      this.dispatch(new OnAvatarFileLoaded(localPath));
      return;
    }
    if (this.subscribedAvatarFileId === fileId) {
      return; // 下载中，已订阅
    }
    this.subscribedAvatarFileId = fileId;
    this.subscriptions.push(this.fileRegistry.subscribeFile(fileId, (file): void => {
      if (this.destroyed) {
        return;
      }
      const path: string | null = this.fileRegistry.getLocalPath(file.id);
      if (path !== null) {
        this.dispatch(new OnAvatarFileLoaded(path));
      }
    }));
    const res: Result<TdPendingRequest, AppError> =
      this.fileRegistry.downloadFile(fileId, AVATAR_DOWNLOAD_PRIORITY);
    if (res.err) {
      this.logger.logError(TAG, res.error);
    }
  }

  private executeEffect(effect: ProfileEffect): void {
    switch (effect.kind) {
      case 'createPrivateChat': {
        const create: CreatePrivateChatEffect = effect as CreatePrivateChatEffect;
        this.logger.info(TAG, 'create_private_chat', `userId=${create.userId}`);
        const req: CreatePrivateChat = new CreatePrivateChat();
        req.user_id = create.userId;
        const res: Result<TdPendingRequest, AppError> =
          this.scope.request('createPrivateChat', encodeCreatePrivateChat(req) as TdWireObject);
        if (res.ok) {
          res.value.promise.then((out: Result<TdWireObject, AppError>): void => {
            if (this.destroyed) {
              return;
            }
            if (out.ok) {
              const chat: Chat | null = decodeChat(out.value as TdJsonRaw);
              if (chat !== null) {
                this.logger.info(TAG, 'create_private_chat_ok', `chatId=${chat.id}`);
                this.onOpenChat(chat.id);
              }
            }
            if (out.err) {
              this.dispatch(new OnProfileFailed(out.error));
            }
          }).catch((): void => {
          });
        }
        if (res.err) {
          this.dispatch(new OnProfileFailed(res.error));
        }
        break;
      }

      case 'fetchSharedContent': {
        const fetch: FetchSharedContent = effect as FetchSharedContent;
        this.fetchSharedContent(fetch.tab, false);
        break;
      }

      case 'fetchSharedGroups': {
        this.fetchSharedGroups(false);
        break;
      }

      case 'fetchMoreSharedContent': {
        const fetchMore: FetchMoreSharedContent = effect as FetchMoreSharedContent;
        this.fetchMoreSharedContent(fetchMore.tab);
        break;
      }

      case 'playSharedAudio': {
        const play: PlaySharedAudio = effect as PlaySharedAudio;
        this.playSharedAudio(play.fileId);
        break;
      }

      case 'stopSharedAudio': {
        this.stopSharedAudio();
        break;
      }

      case 'openSharedChat': {
        const open: OpenSharedChatEffect = effect as OpenSharedChatEffect;
        this.logger.info(TAG, 'open_shared_chat', `chatId=${open.chatId}`);
        this.onOpenChat(open.chatId);
        break;
      }

      case 'fetchChatNotification': {
        this.fetchChatNotification();
        break;
      }

      case 'setChatNotification': {
        const set: SetChatNotification = effect as SetChatNotification;
        this.executeSetChatNotification(set.muted);
        break;
      }

      case 'createSecretChat': {
        this.executeCreateSecretChat();
        break;
      }

      case 'setPeerBlock': {
        const block: SetPeerBlock = effect as SetPeerBlock;
        this.executeSetPeerBlock(block.blocked);
        break;
      }

      default:
        break;
    }
  }

  // ------------------------------------------------------------------
  // PROFILE-103：共享内容（媒体/文件/链接/音乐/语音/群组）
  // ------------------------------------------------------------------

  private fetchMoreSharedContent(tab: number): void {
    if (tab === SHARED_TAB_GROUPS) {
      this.fetchSharedGroups(true);
      return;
    }
    this.fetchSharedContent(tab, true);
  }

  /**
   * 内容 Tab（媒体/文件/链接/音乐/语音）：先 createPrivateChat 拿 chatId，再
   * searchChatMessages 按对应过滤器检索。失败只 logError，并退回 OnSharedContentFailed
   * 复位 sharedLoading（不打扰 UI）。
   */
  private fetchSharedContent(tab: number, isLoadMore: boolean = false): void {
    this.logger.info(TAG, 'fetch_shared_content', `userId=${this.userId},tab=${tab},isLoadMore=${isLoadMore}`);
    this.withPrivateChatId(
      `shared_tab=${tab}`,
      (chatId: number): void => {
        this.searchSharedContent(tab, chatId, isLoadMore);
      },
      (): void => {
        this.failSharedContent(tab);
      }
    );
  }

  /**
   * 私聊 chatId 是本页多项数据的公共前置（共享内容、会话通知设置）。
   * 命中缓存直接回调；在途则排队，只发一条 createPrivateChat —— 首屏两路数据
   * 同时开局，各发一份会白花一次往返。
   */
  private withPrivateChatId(
    source: string,
    onReady: (chatId: number) => void,
    onFailed: () => void
  ): void {
    if (this.cachedPrivateChatId > 0) {
      onReady(this.cachedPrivateChatId);
      return;
    }
    this.privateChatWaiters.push(new PrivateChatWaiter(onReady, onFailed));
    if (this.privateChatPending) {
      return;
    }
    this.privateChatPending = true;
    const req: CreatePrivateChat = new CreatePrivateChat();
    req.user_id = this.userId;
    const res: Result<TdPendingRequest, AppError> =
      this.scope.request('createPrivateChat', encodeCreatePrivateChat(req) as TdWireObject);
    if (res.ok) {
      res.value.promise.then((out: Result<TdWireObject, AppError>): void => {
        if (this.destroyed) {
          return;
        }
        if (out.err) {
          this.logger.logError(TAG, out.error);
          this.failPrivateChatWaiters();
          return;
        }
        if (out.ok) {
          const chat: Chat | null = decodeChat(out.value as TdJsonRaw);
          if (chat === null) {
            this.failPrivateChatWaiters();
            return;
          }
          this.cachedPrivateChatId = chat.id;
          this.logger.info(TAG, 'private_chat_ready', `source=${source},chatId=${chat.id}`);
          this.releasePrivateChatWaiters(chat.id);
        }
      }).catch((): void => {
      });
      return;
    }
    if (res.err) {
      this.logger.logError(TAG, res.error);
    }
    this.failPrivateChatWaiters();
  }

  private releasePrivateChatWaiters(chatId: number): void {
    const waiters: PrivateChatWaiter[] = this.privateChatWaiters;
    this.privateChatWaiters = [];
    this.privateChatPending = false;
    for (let i = 0; i < waiters.length; i++) {
      waiters[i].onReady(chatId);
    }
  }

  private failPrivateChatWaiters(): void {
    const waiters: PrivateChatWaiter[] = this.privateChatWaiters;
    this.privateChatWaiters = [];
    this.privateChatPending = false;
    for (let i = 0; i < waiters.length; i++) {
      waiters[i].onFailed();
    }
  }

  private searchSharedContent(tab: number, chatId: number, isLoadMore: boolean = false): void {
    this.sharedSearcher.search(tab, chatId, isLoadMore, (page: SharedContentPage): void => {
      this.applySharedPage(page, isLoadMore);
    });
  }

  /** 一页回包 + 当前状态 → 回灌；只覆盖本次拉取的 Tab 数组，其余透传。 */
  private applySharedPage(page: SharedContentPage, isLoadMore: boolean): void {
    if (this.destroyed) {
      return;
    }
    if (!page.loaded) {
      this.failSharedContent(page.tab);
      return;
    }
    const next: SharedContentRows =
      mergeSharedRows(this.currentSharedRows(), page.tab, page.rows, isLoadMore);
    this.dispatch(new OnSharedContentLoaded(page.tab, next, page.hasMore));
  }

  /** 当前状态里的五个内容 Tab 数组 → 一个集合（回灌时要按 Tab 局部替换）。 */
  private currentSharedRows(): SharedContentRows {
    const s: ProfileUiState = this.currentState;
    return new SharedContentRows({
      media: s.sharedMedia,
      files: s.sharedFiles,
      links: s.sharedLinks,
      audios: s.sharedAudios,
      voices: s.sharedVoices
    });
  }

  /** 本地路径未就绪时顺手登记 updateFile 订阅，落盘后原位回灌缩略图/音频路径。 */
  private sharedLocalPathOf(fileId: number): string | null {
    const cached: string | null = this.fileRegistry.getLocalPath(fileId);
    return cached !== null ? cached : this.subscribeSharedFile(fileId);
  }

  /** 订阅一次 fileId 的本地路径变化，并发起下载（缩略图与音频共用这条通道）。 */
  private subscribeSharedFile(fileId: number): string | null {
    if (!this.subscribedSharedFileIds.has(fileId)) {
      this.subscribedSharedFileIds.add(fileId);
      this.subscriptions.push(this.fileRegistry.subscribeFile(fileId, (file: File): void => {
        this.onSharedFileReady(file);
      }));
      const res: Result<TdPendingRequest, AppError> =
        this.fileRegistry.downloadFile(fileId, SHARED_THUMB_DOWNLOAD_PRIORITY);
      if (res.err) {
        this.logger.logError(TAG, res.error);
      }
    }
    return null;
  }

  /** 文件落盘：原位回灌网格缩略图与音频行的 localPath；有等待播放的顺带续播。 */
  private onSharedFileReady(file: File): void {
    if (this.destroyed) {
      return;
    }
    const path: string | null = this.fileRegistry.getLocalPath(file.id);
    if (path === null || path.length === 0) {
      return;
    }
    const rows: SharedContentRows = this.currentSharedRows();
    const media: SharedMediaItem[] | null = withSharedMediaPath(rows.media, file.id, path);
    const audios: SharedAudioItem[] | null = withSharedAudioPath(rows.audios, file.id, path);
    const voices: SharedAudioItem[] | null = withSharedAudioPath(rows.voices, file.id, path);
    if (media !== null || audios !== null || voices !== null) {
      this.dispatch(new OnSharedContentLoaded(
        this.currentState.activeSharedTab,
        new SharedContentRows({
          media: media !== null ? media : rows.media,
          files: rows.files,
          links: rows.links,
          audios: audios !== null ? audios : rows.audios,
          voices: voices !== null ? voices : rows.voices
        }),
        this.currentState.sharedHasMore
      ));
    }
    if (this.pendingPlayFileId === file.id) {
      this.pendingPlayFileId = 0;
      this.startSharedAudioPlayback(path);
    }
  }

  // ------------------------------------------------------------------
  // SHARED-AUDIO：点行播放（复用 VOICE-101 的 AudioPlayerPort 抽象）
  // ------------------------------------------------------------------

  private playSharedAudio(fileId: number): void {
    const item: SharedAudioItem | null = this.findSharedAudio(fileId);
    if (item === null) {
      this.dispatch(new OnSharedAudioPlaying(0));
      return;
    }
    if (item.localPath !== null && item.localPath.length > 0) {
      this.startSharedAudioPlayback(item.localPath);
      return;
    }
    // 音频没落盘：先触发下载，路径回来后由 onSharedFileReady 续播；
    // 播放态已由 reducer 乐观置位，这里不退回，避免图标闪一下。
    this.pendingPlayFileId = fileId;
    this.subscribeSharedFile(fileId);
    this.toastPort.showToast('正在下载音频...');
  }

  private startSharedAudioPlayback(path: string): void {
    const fileId: number = this.currentState.sharedPlayingFileId;
    this.audioPlayerPort.play(
      path,
      (_currentMs: number, _totalMs: number): void => {},
      (): void => {
        if (!this.destroyed) {
          this.dispatch(new OnSharedAudioPlaying(0));
        }
      },
      (errMsg: string): void => {
        this.logger.error(TAG, 'shared_audio_play_error', `fileId=${fileId},msg=${errMsg}`);
        if (!this.destroyed) {
          this.dispatch(new OnSharedAudioPlaying(0));
        }
      }
    ).catch((e: Error): void => {
      this.logger.error(TAG, 'shared_audio_play_failed', String(e));
      if (!this.destroyed) {
        this.dispatch(new OnSharedAudioPlaying(0));
      }
    });
  }

  private stopSharedAudio(): void {
    this.pendingPlayFileId = 0;
    this.audioPlayerPort.stop().catch((): void => {});
  }

  private findSharedAudio(fileId: number): SharedAudioItem | null {
    const rows: SharedContentRows = this.currentSharedRows();
    for (let i = 0; i < rows.audios.length; i++) {
      if (rows.audios[i].fileId === fileId) {
        return rows.audios[i];
      }
    }
    for (let i = 0; i < rows.voices.length; i++) {
      if (rows.voices[i].fileId === fileId) {
        return rows.voices[i];
      }
    }
    return null;
  }

  // ------------------------------------------------------------------
  // PROFILE-103 收尾：通知行真实态（读 getChat.notification_settings，写 setChatNotificationSettings）
  // ------------------------------------------------------------------

  private fetchChatNotification(): void {
    this.logger.info(TAG, 'fetch_chat_notification', `userId=${this.userId}`);
    this.withPrivateChatId(
      'notification',
      (chatId: number): void => {
        this.readChatState(chatId);
      },
      (): void => {
        this.dispatch(new OnChatNotificationFailed());
        this.dispatch(new OnPeerBlockFailed());
      }
    );
  }

  /**
   * 一次 getChat 同时喂两行真值（notification_settings / block_list），读不到就
   * 两路各自退回「未知」——菜单不能拿默认值冒充真值，也不留在「写请求在途」。
   */
  private readChatState(chatId: number): void {
    const req: GetChat = new GetChat();
    req.chat_id = chatId;
    const res: Result<TdPendingRequest, AppError> =
      this.scope.request('getChat', encodeGetChat(req) as TdWireObject);
    if (res.ok) {
      res.value.promise.then((out: Result<TdWireObject, AppError>): void => {
        if (this.destroyed) {
          return;
        }
        if (out.err) {
          this.logger.logError(TAG, out.error);
          this.failChatState();
          return;
        }
        if (out.ok) {
          const chat: Chat | null = decodeChat(out.value as TdJsonRaw);
          if (chat === null) {
            this.failChatState();
            return;
          }
          // 同一次回读顺手订上推送：本端/它端改静音、屏蔽都能实时翻回来。
          this.subscribeChatState(chatId);
          this.applyChatNotificationSettings(chat.notification_settings);
          this.applyPeerBlock(chat.block_list);
        }
      }).catch((): void => {
      });
      return;
    }
    if (res.err) {
      this.logger.logError(TAG, res.error);
    }
    this.failChatState();
  }

  private failChatState(): void {
    this.dispatch(new OnChatNotificationFailed());
    this.dispatch(new OnPeerBlockFailed());
  }

  /** null（TDLib 没给设置）时不猜「未静音」，退回「未知」态。 */
  private applyChatNotificationSettings(settings: ChatNotificationSettings | null): void {
    if (settings === null) {
      this.dispatch(new OnChatNotificationFailed());
      return;
    }
    this.chatNotificationSettings = settings;
    const muted: boolean = isChatMuted(settings);
    this.logger.info(TAG, 'chat_notification_state', `muted=${muted},mute_for=${settings.mute_for}`);
    this.dispatch(new OnChatNotificationLoaded(muted));
  }

  /**
   * 静音/取消静音。以回读快照为底本、只改 mute_for —— TDLib 的 sound_id/story_sound_id
   * 是 int64，写空串会被直接判 bad_request（见 core/domain ChatMute）。
   * 不做乐观改写：写成功后再 getChat 复核一遍真值。
   */
  private executeSetChatNotification(muted: boolean): void {
    const chatId: number = this.cachedPrivateChatId;
    if (chatId === 0) {
      this.dispatch(new OnChatNotificationFailed());
      return;
    }
    const req: SetChatNotificationSettings = new SetChatNotificationSettings();
    req.chat_id = chatId;
    req.notification_settings = withChatMuteFor(this.chatNotificationSettings, muted);
    const res: Result<TdPendingRequest, AppError> =
      this.scope.request('setChatNotificationSettings', encodeSetChatNotificationSettings(req) as TdWireObject);
    if (res.ok) {
      res.value.promise.then((out: Result<TdWireObject, AppError>): void => {
        if (this.destroyed) {
          return;
        }
        if (out.err) {
          this.logger.logError(TAG, out.error);
          this.dispatch(new OnChatNotificationFailed());
          return;
        }
        this.logger.info(TAG, 'chat_notification_written', `chatId=${chatId},mute=${muted}`);
        this.readChatState(chatId);
      }).catch((): void => {
      });
      return;
    }
    if (res.err) {
      this.logger.logError(TAG, res.error);
    }
    this.dispatch(new OnChatNotificationFailed());
  }

  private subscribeChatState(chatId: number): void {
    if (this.destroyed || this.notificationChatId === chatId) {
      return;
    }
    if (this.notificationSubscription !== null) {
      this.notificationSubscription.unsubscribe();
      this.notificationSubscription = null;
    }
    const filter: TdUpdateFilter = {
      clientId: this.scope.clientId,
      types: ['updateChatNotificationSettings', 'updateChatBlockList']
    };
    this.notificationSubscription = this.scope.gatewayInstance.subscribeUpdates(
      filter,
      (event: TdRoutedEvent): void => {
        const update: TdUpdate | null = decodeTdUpdate(event.payload as TdJsonRaw);
        if (update === null || this.destroyed) {
          return;
        }
        if (update.type === 'updateChatNotificationSettings') {
          const changed: UpdateChatNotificationSettings = update as UpdateChatNotificationSettings;
          if (changed.chat_id !== chatId) {
            return;
          }
          this.applyChatNotificationSettings(changed.notification_settings);
          return;
        }
        if (update.type === 'updateChatBlockList') {
          const changedBlock: UpdateChatBlockList = update as UpdateChatBlockList;
          if (changedBlock.chat_id !== chatId) {
            return;
          }
          this.applyPeerBlock(changedBlock.block_list);
        }
      }
    );
    this.notificationChatId = chatId;
  }

  // ------------------------------------------------------------------
  // PROFILE-103 收尾：⋮ 头部菜单真实动作（密聊 createNewSecretChat / 屏蔽 setMessageSenderBlockList）
  // ------------------------------------------------------------------

  /**
   * 屏蔽真值同样来自那一次 getChat：chat.block_list 为 null 表示该会话不在任何
   * 黑名单里。本 schema 没有 blockUser/unblockUser，只有按 messageSender 改黑名单。
   */
  private applyPeerBlock(blockList: TdBlockList | null): void {
    const blocked: boolean = blockList !== null;
    this.logger.info(TAG, 'peer_block_state', `userId=${this.userId},blocked=${blocked}`);
    this.dispatch(new OnPeerBlockLoaded(blocked));
  }

  /**
   * 密聊：createNewSecretChat 回执即 secretChat，其 id 同时是 chat.id（type 为
   * chatTypeSecret），所以直接复用装配层的 onOpenChat 导航，无需新路由。
   * 对方客户端不支持/已关闭密聊时 TDLib 报错，只提示不静默。
   */
  private executeCreateSecretChat(): void {
    const req: CreateNewSecretChat = new CreateNewSecretChat();
    req.user_id = this.userId;
    const res: Result<TdPendingRequest, AppError> =
      this.scope.request('createNewSecretChat', encodeCreateNewSecretChat(req) as TdWireObject);
    if (res.ok) {
      res.value.promise.then((out: Result<TdWireObject, AppError>): void => {
        if (this.destroyed) {
          return;
        }
        if (out.err) {
          this.logger.logError(TAG, out.error);
          this.toastPort.showToast('无法开启密聊');
          return;
        }
        if (out.ok) {
          const secretChat: SecretChat | null = decodeSecretChat(out.value as TdJsonRaw);
          if (secretChat === null || secretChat.id === 0) {
            this.toastPort.showToast('无法开启密聊');
            return;
          }
          this.logger.info(TAG, 'secret_chat_created',
            `userId=${this.userId},secretChatId=${secretChat.id},layer=${secretChat.layer}`);
          this.onOpenChat(secretChat.id);
        }
      }).catch((): void => {
      });
      return;
    }
    if (res.err) {
      this.logger.logError(TAG, res.error);
    }
    this.toastPort.showToast('无法开启密聊');
  }

  /**
   * 屏蔽/取消屏蔽：blocked=true 写入 blockListMain，false 传 null（TDLib 语义即解除）。
   * 不乐观改写，写成功后 getChat 复核真值。
   */
  private executeSetPeerBlock(blocked: boolean): void {
    this.withPrivateChatId(
      'peer_block',
      (chatId: number): void => {
        this.writePeerBlock(chatId, blocked);
      },
      (): void => {
        this.toastPort.showToast('操作失败，请稍后重试');
        this.dispatch(new OnPeerBlockFailed());
      }
    );
  }

  private writePeerBlock(chatId: number, blocked: boolean): void {
    const sender: MessageSenderUser = new MessageSenderUser();
    sender.user_id = this.userId;
    const req: SetMessageSenderBlockList = new SetMessageSenderBlockList();
    req.sender_id = sender;
    if (blocked) {
      const list: BlockListMain = new BlockListMain();
      req.block_list = list;
    } else {
      req.block_list = null;
    }
    const res: Result<TdPendingRequest, AppError> =
      this.scope.request('setMessageSenderBlockList', encodeSetMessageSenderBlockList(req) as TdWireObject);
    if (res.ok) {
      res.value.promise.then((out: Result<TdWireObject, AppError>): void => {
        if (this.destroyed) {
          return;
        }
        if (out.err) {
          this.logger.logError(TAG, out.error);
          this.toastPort.showToast('操作失败，请稍后重试');
          this.dispatch(new OnPeerBlockFailed());
          return;
        }
        this.logger.info(TAG, 'peer_block_written', `chatId=${chatId},blocked=${blocked}`);
        this.readChatState(chatId);
      }).catch((): void => {
      });
      return;
    }
    if (res.err) {
      this.logger.logError(TAG, res.error);
    }
    this.toastPort.showToast('操作失败，请稍后重试');
    this.dispatch(new OnPeerBlockFailed());
  }

  /** 共同群组 Tab：getGroupsInCommon → 逐 id getChat 解析标题/副标题，全部回灌。 */
  private fetchSharedGroups(isLoadMore: boolean = false): void {
    this.logger.info(TAG, 'fetch_shared_groups', `userId=${this.userId},isLoadMore=${isLoadMore}`);
    const offsetChatId: number = isLoadMore ? (this.nextOffsets.get(SHARED_TAB_GROUPS) ?? 0) : 0;
    const req: GetGroupsInCommon = new GetGroupsInCommon();
    req.user_id = this.userId;
    req.offset_chat_id = offsetChatId;
    req.limit = SHARED_PAGE_LIMIT;
    const res: Result<TdPendingRequest, AppError> =
      this.scope.request('getGroupsInCommon', encodeGetGroupsInCommon(req) as TdWireObject);
    if (res.ok) {
      res.value.promise.then((out: Result<TdWireObject, AppError>): void => {
        if (this.destroyed) {
          return;
        }
        if (out.err) {
          this.logger.logError(TAG, out.error);
          this.failSharedGroups();
          return;
        }
        if (out.ok) {
          const chats: Chats | null = decodeChats(out.value as TdJsonRaw);
          if (chats === null || chats.chat_ids.length === 0) {
            const current: SharedGroupItem[] = isLoadMore ? this.currentState.sharedGroups : [];
            this.dispatch(new OnSharedGroupsLoaded(current, false));
            return;
          }
          const hasMore: boolean = chats.chat_ids.length >= SHARED_PAGE_LIMIT;
          this.nextOffsets.set(SHARED_TAB_GROUPS, chats.chat_ids[chats.chat_ids.length - 1]);
          this.resolveSharedGroupChats(chats.chat_ids, isLoadMore, hasMore);
        }
      }).catch((): void => {
      });
    }
    if (res.err) {
      this.logger.logError(TAG, res.error);
      this.failSharedGroups();
    }
  }

  private resolveSharedGroupChats(chatIds: number[], isLoadMore: boolean = false, hasMore: boolean = false): void {
    const items: SharedGroupItem[] = [];
    for (let i = 0; i < chatIds.length; i++) {
      items.push(new SharedGroupItem(chatIds[i], '', ''));
    }
    const total: number = chatIds.length;
    let settled: number = 0;
    for (let i = 0; i < total; i++) {
      const index: number = i;
      const req: GetChat = new GetChat();
      req.chat_id = chatIds[i];
      const res: Result<TdPendingRequest, AppError> =
        this.scope.request('getChat', encodeGetChat(req) as TdWireObject);
      if (res.ok) {
        res.value.promise.then((out: Result<TdWireObject, AppError>): void => {
          settled++;
          if (!this.destroyed) {
            if (out.ok) {
              const chat: Chat | null = decodeChat(out.value as TdJsonRaw);
              if (chat !== null) {
                items[index] = this.groupItemOf(chat);
              }
            }
            if (out.err) {
              this.logger.logError(TAG, out.error);
            }
          }
          if (settled === total && !this.destroyed) {
            this.finishSharedGroups(items, isLoadMore, hasMore);
          }
        }).catch((): void => {
          settled++;
          if (settled === total && !this.destroyed) {
            this.finishSharedGroups(items, isLoadMore, hasMore);
          }
        });
      }
      if (res.err) {
        this.logger.logError(TAG, res.error);
        settled++;
        if (settled === total && !this.destroyed) {
          this.finishSharedGroups(items, isLoadMore, hasMore);
        }
      }
    }
  }

  private finishSharedGroups(items: SharedGroupItem[], isLoadMore: boolean = false, hasMore: boolean = false): void {
    const result: SharedGroupItem[] = [];
    for (let i = 0; i < items.length; i++) {
      const it: SharedGroupItem = items[i];
      if (it.title.length > 0) {
        result.push(it);
      }
    }
    const combined: SharedGroupItem[] = isLoadMore ? [...this.currentState.sharedGroups, ...result] : result;
    this.logger.info(TAG, 'shared_groups_ok', `count=${combined.length},hasMore=${hasMore}`);
    this.dispatch(new OnSharedGroupsLoaded(combined, hasMore));
  }

  /** 群组副标题：优先最后一条消息摘要，兜底会话类型文案。 */
  private groupItemOf(chat: Chat): SharedGroupItem {
    let subtitle: string = '';
    const last: Message | null = chat.last_message;
    if (last !== null && last !== undefined) {
      subtitle = messageContentSummary(last.content);
    }
    if (subtitle.length === 0) {
      subtitle = chatTypeLabel(chat.type_);
    }
    return new SharedGroupItem(chat.id, chat.title, subtitle);
  }

  /**
   * 拉取失败：出 `OnSharedContentFailed`，让页面把「没内容」和「没拉到」分开。
   * 旧实现用当前（空）数组回灌 loaded 意图，请求挂了页面照样显示「暂无媒体文件」。
   */
  private failSharedContent(tab: number): void {
    this.dispatch(new OnSharedContentFailed(tab));
  }

  private failSharedGroups(): void {
    this.dispatch(new OnSharedContentFailed(SHARED_TAB_GROUPS));
  }
}
