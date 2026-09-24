/**
 * feature/profile — 群组/频道资料页协调器（PROFILE-102）。
 *
 * 遵循 100% Kit-free 架构规范：
 * - 纯端口注入（ClipboardPort, ToastPort, Logger）；
 * - 协调 ChatRegistry, GroupRegistry, UserRegistry, FileRegistry；
 * - 聚合群详情与首屏成员列表（对标 Telegram-X ProfileController.Args(chat)）。
 */

import { AccountScope } from '@tgx/core-account';
import { AppError, Result, ManualClock, SequentialIdGenerator } from '@tgx/core-common';
import {
  ChatRegistry,
  GroupRegistry,
  UserRegistry,
  FileRegistry,
  formatFullName,
  getAvatarLetters,
  getAvatarColorIndex,
  isOnline,
  formatMemberRole
} from '@tgx/core-domain';
import {
  File,
  Chat,
  BasicGroupFullInfo,
  SupergroupFullInfo,
  ChatMember,
  ChatMembers,
  User,
  GetChat,
  encodeGetChat,
  decodeChat,
  TdJsonRaw,
  ChatTypeBasicGroup,
  ChatTypeSupergroup,
  MessageSenderUser
} from '@tgx/core-td-api-generated';
import { TdWireObject, TdPendingRequest } from '@tgx/td-gateway';
import {
  AudioPlaybackMetadata,
  AudioPlayerPort,
  ClipboardPort,
  FakeAudioPlayer,
  ToastPort,
  Subscription
} from '@tgx/platform-ports';
import { Logger } from '@tgx/observability';
import { ReducerResult, ReducerEnv } from '@tgx/feature-template';
import { ChatProfileUiState, ChatMemberUiItem } from '../contract/ChatProfileUiState';
import {
  SharedAudioItem,
  SharedContentRows,
  SharedMediaItem
} from '../contract/SharedContentItems';
import {
  audioSessionMetadata,
  withSharedAudioPath,
  withSharedMediaPath
} from '../model/SharedContentFormat';
import {
  mergeSharedRows,
  SHARED_TAB_VOICE,
  SharedContentPage,
  SharedContentSearcher
} from '../model/SharedContentSearch';
import {
  ChatProfileIntent,
  OpenChatProfile,
  OnChatLoaded,
  OnBasicGroupFullInfoLoaded,
  OnSupergroupFullInfoLoaded,
  OnChatMembersLoaded,
  OnChatAvatarLoaded,
  OnChatProfileError,
  OnSharedContentLoaded,
  OnSharedContentFailed,
  OnSharedAudioPlaying
} from '../contract/ChatProfileIntent';
import {
  ChatProfileEffect,
  FetchChatDetailsEffect,
  FetchSharedContentEffect,
  FetchMoreSharedContentEffect,
  PlaySharedAudioEffect,
  StopSharedAudioEffect,
  NavigateToUserProfileEffect,
  CopyInviteLinkEffect,
  NavigateBackEffect
} from '../contract/ChatProfileEffect';
import { chatProfileReducer } from '../reducer/ChatProfileReducer';

const TAG: string = 'ChatProfileCoordinator';

/** 共享媒体缩略图/音频下载优先级（与用户资料页一致：预览级，不抢播放器带宽）。 */
const SHARED_THUMB_DOWNLOAD_PRIORITY: number = 2;

export interface ChatProfileCoordinatorOptions {
  readonly onNavigateToUserProfile?: (userId: number) => void;
  readonly onNavigateBack?: () => void;
  /** SHARED-AUDIO：音频播放器抽象；缺省 FakeAudioPlayer（无装配层注入时点按不外放）。 */
  readonly audioPlayerPort?: AudioPlayerPort;
}

export class ChatProfileCoordinator {
  private readonly scope: AccountScope;
  private readonly chatRegistry: ChatRegistry;
  private readonly groupRegistry: GroupRegistry;
  private readonly userRegistry: UserRegistry;
  private readonly fileRegistry: FileRegistry;
  private readonly clipboardPort: ClipboardPort;
  private readonly toastPort: ToastPort;
  private readonly audioPlayerPort: AudioPlayerPort;
  private readonly logger: Logger;
  private readonly options: ChatProfileCoordinatorOptions;
  private readonly env: ReducerEnv;

  private state: ChatProfileUiState = ChatProfileUiState.initial();
  private onStateChangedListener: ((state: ChatProfileUiState) => void) | null = null;
  private activeChatId: number = 0;
  private subscriptions: Subscription[] = [];
  /** 共享内容五个内容 Tab 的分页拉取（与用户资料页共用 model/SharedContentSearch）。 */
  private readonly sharedSearcher: SharedContentSearcher;
  /** 已登记本地路径订阅的 fileId，防重复订阅。 */
  private readonly subscribedSharedFileIds: Set<number> = new Set();
  /** SHARED-AUDIO：文件还没下载完，落盘后自动续播的 fileId；0 = 无等待。 */
  private pendingPlayFileId: number = 0;
  private destroyed: boolean = false;

  constructor(
    scope: AccountScope,
    chatRegistry: ChatRegistry,
    clipboardPort: ClipboardPort,
    toastPort: ToastPort,
    logger: Logger,
    options?: ChatProfileCoordinatorOptions,
    groupRegistry?: GroupRegistry,
    userRegistry?: UserRegistry,
    fileRegistry?: FileRegistry
  ) {
    this.scope = scope;
    this.chatRegistry = chatRegistry;
    this.clipboardPort = clipboardPort;
    this.toastPort = toastPort;
    this.logger = logger;
    this.options = options !== undefined ? options : {};
    this.audioPlayerPort = this.options.audioPlayerPort !== undefined
      ? this.options.audioPlayerPort
      : new FakeAudioPlayer();
    this.groupRegistry = groupRegistry !== undefined ? groupRegistry : new GroupRegistry(scope);
    this.userRegistry = userRegistry !== undefined ? userRegistry : new UserRegistry(scope);
    this.fileRegistry = fileRegistry !== undefined ? fileRegistry : new FileRegistry(scope);
    this.env = {
      clock: new ManualClock(1000, 500),
      ids: new SequentialIdGenerator('chat-profile-')
    };
    const self: ChatProfileCoordinator = this;
    this.sharedSearcher = new SharedContentSearcher({
      request: (name: string, payload: TdWireObject): Result<TdPendingRequest, AppError> =>
        this.scope.request(name, payload),
      localPathOf: (fileId: number): string | null => self.sharedLocalPathOf(fileId),
      audioLocalPathOf: (fileId: number): string | null => self.fileRegistry.getLocalPath(fileId),
      senderNameOf: (userId: number): string => self.sharedSenderNameOf(userId),
      logger: this.logger,
      tag: TAG
    });
  }

  /**
   * 语音行的发送者昵称。
   * 本页成员列表已经把所有发言人 getUser 过，正常都在缓存里；没命中时补一次请求，
   * 本行先显示「语音消息」，下一页起就有名字。
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

  getState(): ChatProfileUiState {
    return this.state;
  }

  setOnStateChanged(listener: (state: ChatProfileUiState) => void): void {
    this.onStateChangedListener = listener;
  }

  start(chatId: number): void {
    this.activeChatId = chatId;
    // 每个页面有自己的 coordinator，但游标防御性清一次：换 chatId 复用实例时
    // 旧会话的 next_from_message_id 对新会话毫无意义。
    this.sharedSearcher.resetOffsets();
    this.dispatch(new OpenChatProfile(chatId));
  }

  destroy(): void {
    this.destroyed = true;
    this.sharedSearcher.destroy();
    this.pendingPlayFileId = 0;
    this.audioPlayerPort.stop().catch((): void => {});
    for (let i = 0; i < this.subscriptions.length; i++) {
      this.subscriptions[i].unsubscribe();
    }
    this.subscriptions = [];
    this.onStateChangedListener = null;
  }

  dispatch(intent: ChatProfileIntent): void {
    const res: ReducerResult<ChatProfileUiState, ChatProfileEffect> =
      chatProfileReducer(this.state, intent, this.env);
    this.state = res.state;
    if (this.onStateChangedListener !== null) {
      this.onStateChangedListener(this.state);
    }
    for (let i = 0; i < res.effects.length; i++) {
      this.executeEffect(res.effects[i]);
    }
  }

  private executeEffect(effect: ChatProfileEffect): void {
    switch (effect.type) {
      case 'fetchChatDetailsEffect': {
        const fetchEffect: FetchChatDetailsEffect = effect as FetchChatDetailsEffect;
        this.loadChatDetails(fetchEffect.chatId);
        break;
      }
      case 'fetchSharedContentEffect': {
        const fetch: FetchSharedContentEffect = effect as FetchSharedContentEffect;
        this.fetchSharedContent(fetch.tab, false);
        break;
      }
      case 'fetchMoreSharedContentEffect': {
        const fetchMore: FetchMoreSharedContentEffect = effect as FetchMoreSharedContentEffect;
        this.fetchSharedContent(fetchMore.tab, true);
        break;
      }
      case 'playSharedAudioEffect': {
        const play: PlaySharedAudioEffect = effect as PlaySharedAudioEffect;
        this.playSharedAudio(play.fileId);
        break;
      }
      case 'stopSharedAudioEffect': {
        this.stopSharedAudio();
        break;
      }
      case 'navigateToUserProfileEffect': {
        const navEffect: NavigateToUserProfileEffect = effect as NavigateToUserProfileEffect;
        if (this.options.onNavigateToUserProfile) {
          this.options.onNavigateToUserProfile(navEffect.userId);
        }
        break;
      }
      case 'copyInviteLinkEffect': {
        const copyEffect: CopyInviteLinkEffect = effect as CopyInviteLinkEffect;
        this.clipboardPort.setPlainText(copyEffect.link);
        this.toastPort.showToast('Invite link copied');
        break;
      }
      case 'navigateBackEffect': {
        if (this.options.onNavigateBack) {
          this.options.onNavigateBack();
        }
        break;
      }
    }
  }

  private loadChatDetails(chatId: number): void {
    // 1. 获取 Chat 基础对象
    const cachedChat: Chat | undefined = this.chatRegistry.getChat(chatId);
    if (cachedChat !== undefined) {
      this.processChat(cachedChat);
      return;
    }

    const req: GetChat = new GetChat();
    req.chat_id = chatId;
    const res: Result<TdPendingRequest, AppError> = this.scope.request(
      'getChat',
      encodeGetChat(req) as TdWireObject
    );

    if (res.ok) {
      const self: ChatProfileCoordinator = this;
      res.value.promise.then((chatRes: Result<TdWireObject, AppError>): void => {
        if (chatRes.ok) {
          const chat: Chat | null = decodeChat(chatRes.value as TdJsonRaw);
          if (chat !== null) {
            self.chatRegistry.putChat(chat);
            self.processChat(chat);
          }
        }
        if (chatRes.err) {
          self.dispatch(new OnChatProfileError(chatRes.error));
        }
      }).catch((): void => {});
    }
  }

  private processChat(chat: Chat): void {
    this.dispatch(new OnChatLoaded(chat));

    // 处理群头像下载与展示
    if (chat.photo !== null && chat.photo.small !== null) {
      const fileId: number = chat.photo.small.id;
      const cachedPath: string | null = this.fileRegistry.getLocalPath(fileId);
      if (cachedPath !== null) {
        this.dispatch(new OnChatAvatarLoaded(cachedPath));
      } else {
        const self: ChatProfileCoordinator = this;
        const sub: Subscription = this.fileRegistry.subscribeFile(fileId, (f: File): void => {
          if (f.local !== null && f.local.is_downloading_completed && f.local.path.length > 0) {
            self.dispatch(new OnChatAvatarLoaded(f.local.path));
          }
        });
        this.subscriptions.push(sub);
        this.fileRegistry.downloadFile(fileId, 2);
      }
    }

    // 分流 BasicGroup 与 Supergroup
    if (chat.type_ !== null) {
      if (chat.type_.type === 'chatTypeBasicGroup') {
        const bgType: ChatTypeBasicGroup = chat.type_ as ChatTypeBasicGroup;
        this.loadBasicGroupDetails(bgType.basic_group_id);
      } else if (chat.type_.type === 'chatTypeSupergroup') {
        const sgType: ChatTypeSupergroup = chat.type_ as ChatTypeSupergroup;
        this.loadSupergroupDetails(sgType.supergroup_id, sgType.is_channel);
      }
    }
  }

  private loadBasicGroupDetails(basicGroupId: number): void {
    const cachedInfo: BasicGroupFullInfo | null =
      this.groupRegistry.getBasicGroupFullInfo(basicGroupId);
    if (cachedInfo !== null) {
      this.dispatch(new OnBasicGroupFullInfoLoaded(cachedInfo));
    }

    // 订阅详情变更
    const sub: Subscription = this.groupRegistry.subscribeBasicGroupFullInfo(
      basicGroupId,
      (info: BasicGroupFullInfo): void => {
        this.dispatch(new OnBasicGroupFullInfoLoaded(info));
      }
    );
    this.subscriptions.push(sub);

    // 请求最新详情
    this.groupRegistry.requestBasicGroupFullInfo(basicGroupId);
  }

  private loadSupergroupDetails(supergroupId: number, isChannel: boolean): void {
    const cachedInfo: SupergroupFullInfo | null =
      this.groupRegistry.getSupergroupFullInfo(supergroupId);
    if (cachedInfo !== null) {
      this.dispatch(new OnSupergroupFullInfoLoaded(cachedInfo));
    }

    // 订阅详情变更
    const sub: Subscription = this.groupRegistry.subscribeSupergroupFullInfo(
      supergroupId,
      (info: SupergroupFullInfo): void => {
        this.dispatch(new OnSupergroupFullInfoLoaded(info));
      }
    );
    this.subscriptions.push(sub);

    // 请求最新详情
    this.groupRegistry.requestSupergroupFullInfo(supergroupId);

    // 非频道群组请求首屏成员（频道成员不可见）
    if (!isChannel) {
      this.loadSupergroupMembers(supergroupId);
    }
  }

  private loadSupergroupMembers(supergroupId: number): void {
    const cachedMembers: ChatMember[] | null =
      this.groupRegistry.getSupergroupMembers(supergroupId);
    if (cachedMembers !== null && cachedMembers.length > 0) {
      this.processMembers(cachedMembers);
    }

    const self: ChatProfileCoordinator = this;
    const res: Result<TdPendingRequest, AppError> =
      this.groupRegistry.requestSupergroupMembers(supergroupId, 0, 50);
    if (res.ok) {
      res.value.promise.then((memRes: Result<TdWireObject, AppError>): void => {
        if (memRes.ok) {
          const freshMembers: ChatMember[] | null =
            self.groupRegistry.getSupergroupMembers(supergroupId);
          if (freshMembers !== null) {
            self.processMembers(freshMembers);
          }
        }
      }).catch((): void => {});
    }
  }

  private processMembers(members: ChatMember[]): void {
    const items: ChatMemberUiItem[] = [];

    for (let i = 0; i < members.length; i++) {
      const m: ChatMember = members[i];
      if (m.member_id && m.member_id.type === 'messageSenderUser') {
        const senderUser: MessageSenderUser = m.member_id as MessageSenderUser;
        const userId: number = senderUser.user_id;
        const user: User | null = this.userRegistry.getUser(userId);

        let fullName: string = '';
        let username: string = '';
        let letters: string = '';
        let colorIndex: number = getAvatarColorIndex(userId);
        let online: boolean = false;
        let statusText: string = '';
        let avatarPath: string | null = null;

        if (user !== null) {
          fullName = formatFullName(user);
          username = user.usernames ? user.usernames.active_usernames[0] || '' : '';
          letters = getAvatarLetters(user);
          online = isOnline(user);
          statusText = online ? 'online' : 'last seen recently';
          if (user.profile_photo && user.profile_photo.small) {
            avatarPath = this.fileRegistry.getLocalPath(user.profile_photo.small.id);
          }
        } else {
          fullName = `User #${userId}`;
          letters = 'U';
          this.userRegistry.requestUser(userId);
        }

        const role: string = formatMemberRole(m);
        items.push({
          userId: userId,
          fullName: fullName,
          username: username,
          avatarLetters: letters,
          avatarColorIndex: colorIndex,
          avatarPath: avatarPath,
          role: role,
          isOnline: online,
          statusText: statusText
        });
      }
    }

    this.dispatch(new OnChatMembersLoaded(items));
  }

  // ------------------------------------------------------------------
  // CHATPROF-SHARED：共享内容（媒体/文件/链接/音乐/语音），与用户资料页共用 model/SharedContentSearch
  // ------------------------------------------------------------------

  /** 本页的 chatId 由入口给出，不像私聊页还要先 createPrivateChat 解析。 */
  private fetchSharedContent(tab: number, isLoadMore: boolean): void {
    // 0 = 还没回读到 chat；超级群组/频道的 chatId 是负数，不能按「>0 才有效」判。
    const chatId: number = this.state.chatId;
    if (chatId === 0) {
      this.dispatch(new OnSharedContentFailed(tab));
      return;
    }
    this.logger.info(TAG, 'fetch_shared_content', `chatId=${chatId},tab=${tab},isLoadMore=${isLoadMore}`);
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
      this.dispatch(new OnSharedContentFailed(page.tab));
      return;
    }
    const next: SharedContentRows =
      mergeSharedRows(this.currentSharedRows(), page.tab, page.rows, isLoadMore);
    this.dispatch(new OnSharedContentLoaded(page.tab, next, page.hasMore));
  }

  /** 当前状态里的五个内容 Tab 数组 → 一个集合（回灌时要按 Tab 局部替换）。 */
  private currentSharedRows(): SharedContentRows {
    const s: ChatProfileUiState = this.state;
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
        this.state.activeSharedTab,
        new SharedContentRows({
          media: media !== null ? media : rows.media,
          files: rows.files,
          links: rows.links,
          audios: audios !== null ? audios : rows.audios,
          voices: voices !== null ? voices : rows.voices
        }),
        this.state.sharedHasMore
      ));
    }
    if (this.pendingPlayFileId === file.id) {
      this.pendingPlayFileId = 0;
      this.startSharedAudioPlayback(path, this.findSharedAudio(file.id));
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
      this.startSharedAudioPlayback(item.localPath, item);
      return;
    }
    // 音频没落盘：先触发下载，路径回来后由 onSharedFileReady 续播；
    // 播放态已由 reducer 乐观置位，这里不退回，避免图标闪一下。
    this.pendingPlayFileId = fileId;
    this.subscribeSharedFile(fileId);
    this.toastPort.showToast('正在下载音频...');
  }

  private startSharedAudioPlayback(path: string, item: SharedAudioItem | null): void {
    const fileId: number = this.state.sharedPlayingFileId;
    const metadata: AudioPlaybackMetadata | undefined = item === null
      ? undefined
      : audioSessionMetadata(item, this.state.activeSharedTab === SHARED_TAB_VOICE, this.state.title);
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
      },
      metadata
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
}
