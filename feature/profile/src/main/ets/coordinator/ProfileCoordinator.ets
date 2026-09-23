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
  getAvatarColorIndex
} from '@tgx/core-domain';
import {
  User,
  UserFullInfo,
  Chat,
  CreatePrivateChat,
  encodeCreatePrivateChat,
  decodeChat,
  SearchChatMessages,
  encodeSearchChatMessages,
  SearchMessagesFilterPhotoAndVideo,
  SearchMessagesFilterDocument,
  SearchMessagesFilterUrl,
  TdSearchMessagesFilter,
  FoundChatMessages,
  decodeFoundChatMessages,
  GetGroupsInCommon,
  encodeGetGroupsInCommon,
  Chats,
  decodeChats,
  GetChat,
  encodeGetChat,
  Message,
  TdMessageContent,
  MessageText,
  MessagePhoto,
  MessageDocument,
  MessageVideo,
  PhotoSize,
  File,
  LinkPreview,
  TdChatType,
  ChatTypeSupergroup,
  TdJsonRaw
} from '@tgx/core-td-api-generated';
import { TdPendingRequest, TdWireObject } from '@tgx/td-gateway';
import { Logger } from '@tgx/observability';
import { Subscription } from '@tgx/platform-ports';
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
  OpenSharedChatRequested
} from '../contract/ProfileIntent';
import {
  ProfileEffect,
  CreatePrivateChatEffect,
  FetchSharedContent,
  FetchSharedGroups,
  FetchMoreSharedContent,
  OpenSharedChatEffect
} from '../contract/ProfileEffect';
import { SharedMediaItem, SharedFileItem, SharedLinkItem, SharedGroupItem } from '../contract/SharedContentItems';
import { profileReducer } from '../reducer/ProfileReducer';

const TAG: string = 'ProfileCoordinator';

/** 头像下载优先级（对齐 ChatCoordinator 拉取头像的 priority=2）。 */
const AVATAR_DOWNLOAD_PRIORITY: number = 2;

/** PROFILE-103：共享内容每页拉取条数（对齐 TGX shared media 默认页大小）。 */
const SHARED_PAGE_LIMIT: number = 20;

/** PROFILE-103：共享媒体缩略图下载优先级。 */
const SHARED_THUMB_DOWNLOAD_PRIORITY: number = 2;

/** 文件大小文案（与 feature/chat 的 formatFileSize 同规则，feature 间不可互引故本地实现）。 */
function formatFileSizeText(bytes: number): string {
  if (!Number.isFinite(bytes) || bytes <= 0) {
    return '0 B';
  }
  const KB: number = 1024;
  const MB: number = 1024 * 1024;
  const GB: number = 1024 * 1024 * 1024;
  if (bytes < KB) {
    return `${Math.round(bytes)} B`;
  }
  if (bytes < MB) {
    return `${(bytes / KB).toFixed(1)} KB`;
  }
  if (bytes < GB) {
    return `${(bytes / MB).toFixed(1)} MB`;
  }
  return `${(bytes / GB).toFixed(1)} GB`;
}

/** PROFILE-103：共享内容条目日期。当天 HH:mm，跨天 dd.MM（与 feature/chat 搜索结果一致）。 */
function formatSharedDate(unixSeconds: number): string {
  if (unixSeconds <= 0) {
    return '';
  }
  const date: Date = new Date(unixSeconds * 1000);
  const now: Date = new Date();
  const sameDay: boolean = date.getFullYear() === now.getFullYear() &&
    date.getMonth() === now.getMonth() &&
    date.getDate() === now.getDate();
  if (sameDay) {
    return `${pad2(date.getHours())}:${pad2(date.getMinutes())}`;
  }
  return `${pad2(date.getDate())}.${pad2(date.getMonth() + 1)}`;
}

function pad2(value: number): string {
  return value < 10 ? `0${value}` : `${value}`;
}

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

/** 从文本中提取首个 http(s) URL；无则空串。 */
function firstUrlInText(text: string): string {
  if (text.length === 0) {
    return '';
  }
  const match: RegExpMatchArray | null = text.match(/https?:\/\/[^\s"'<>()]+/i);
  if (match === null) {
    return '';
  }
  return match[0];
}

/** 宫格缩略图选尺寸：优先宽度 >=320 的最小档，否则最大档。 */
function pickThumbPhotoSize(sizes: PhotoSize[]): PhotoSize | null {
  if (sizes.length === 0) {
    return null;
  }
  let chosen: PhotoSize = sizes[sizes.length - 1];
  for (let i = 0; i < sizes.length; i++) {
    const size: PhotoSize = sizes[i];
    if (size.photo === null) {
      continue;
    }
    if (size.width >= 320) {
      chosen = size;
      break;
    }
  }
  return chosen.photo !== null ? chosen : null;
}

/** 会话类型文案（共同群组副标题兜底）。 */
function chatTypeLabel(type: TdChatType | null): string {
  if (type === null || type === undefined) {
    return '';
  }
  if (type.type === 'chatTypeSupergroup') {
    const supergroup: ChatTypeSupergroup = type as ChatTypeSupergroup;
    return supergroup.is_channel ? '频道' : '超级群组';
  }
  if (type.type === 'chatTypeBasicGroup') {
    return '群组';
  }
  if (type.type === 'chatTypePrivate') {
    return '私聊';
  }
  return '';
}

/** 消息内容摘要（共同群组副标题；与 feature/chat 的 messageContentText 同思路，本地实现）。 */
function messageContentSummary(content: TdMessageContent | null): string {
  if (content === null) {
    return '';
  }
  switch (content.type) {
    case 'messageText': {
      const text: MessageText = content as MessageText;
      return text.text !== null ? text.text.text : '';
    }
    case 'messagePhoto':
      return '[照片]';
    case 'messageVideo':
      return '[视频]';
    case 'messageDocument':
      return '[文件]';
    case 'messageAudio':
      return '[音频]';
    case 'messageVoiceNote':
      return '[语音]';
    case 'messageSticker':
      return '[贴纸]';
    case 'messageAnimation':
      return '[GIF]';
    default:
      return '';
  }
}

/** messageDocument → SharedFileItem（大小/日期文案 + 本地路径可空）。 */
function fileItemOf(msg: Message): SharedFileItem | null {
  const content: TdMessageContent | null = msg.content;
  if (content === null || content.type !== 'messageDocument') {
    return null;
  }
  const docMsg: MessageDocument = content as MessageDocument;
  if (docMsg.document === null) {
    return null;
  }
  const file: File | null = docMsg.document.document;
  const localPath: string | null =
    (file !== null && file.local !== null && file.local.path.length > 0) ? file.local.path : null;
  const sizeText: string = file !== null ? formatFileSizeText(file.size) : '';
  const name: string = docMsg.document.file_name.length > 0 ? docMsg.document.file_name : 'File';
  return new SharedFileItem(name, sizeText, formatSharedDate(msg.date), localPath);
}

/** messageText → SharedLinkItem：优先 link_preview 的 url/site_name/description，无则取文本中的 URL。 */
function linkItemOf(content: TdMessageContent | null): SharedLinkItem | null {
  if (content === null || content.type !== 'messageText') {
    return null;
  }
  const text: MessageText = content as MessageText;
  const body: string = text.text !== null ? text.text.text : '';
  const preview: LinkPreview | null = text.link_preview;
  if (preview !== null && preview !== undefined && preview.url.length > 0) {
    const desc: string = preview.description !== null && preview.description !== undefined
      ? preview.description.text
      : '';
    return new SharedLinkItem(preview.url, preview.site_name, desc);
  }
  const url: string = firstUrlInText(body);
  if (url.length === 0) {
    return null;
  }
  return new SharedLinkItem(url, '', '');
}

export interface ProfileCoordinatorOptions {
  /** 私聊创建成功后交给装配层导航（缺省 no-op）。 */
  readonly onOpenChat?: (chatId: number) => void;
  readonly logger?: Logger;
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

export class ProfileCoordinator {
  private readonly scope: AccountScope;
  private readonly userId: number;
  private readonly userRegistry: UserRegistry;
  private readonly fileRegistry: FileRegistry;
  private readonly onOpenChat: (chatId: number) => void;
  private readonly logger: Logger;
  private readonly env: ReducerEnv;
  private currentState: ProfileUiState;
  private readonly listeners: ProfileUiStateListener[] = [];
  private readonly subscriptions: Subscription[] = [];
  /** 已订阅下载回调的头像 fileId，防重复订阅。 */
  private subscribedAvatarFileId: number = -1;
  /** PROFILE-103：已订阅下载回调的共享媒体缩略图 fileId，防重复订阅。 */
  private readonly subscribedSharedFileIds: Set<number> = new Set();
  /** PROFILE-103：各 Tab 的分页 offset（Tab 0..2 为 next_from_message_id，Tab 3 为 offset_chat_id）。 */
  private readonly nextOffsets: Map<number, number> = new Map();
  /** 缓存目标用户的 private chatId，避免重复调用 createPrivateChat。 */
  private cachedPrivateChatId: number = 0;
  private destroyed: boolean = false;

  constructor(scope: AccountScope, userId: number, options?: ProfileCoordinatorOptions) {
    this.scope = scope;
    this.userId = userId;
    this.userRegistry = new UserRegistry(scope);
    this.fileRegistry = new FileRegistry(scope);
    this.onOpenChat = options !== undefined && options.onOpenChat !== undefined
      ? options.onOpenChat
      : (chatId: number): void => {};
    this.logger = options !== undefined && options.logger !== undefined
      ? options.logger
      : new Logger();
    this.env = {
      clock: new ManualClock(1000, 500),
      ids: new SequentialIdGenerator('profile-')
    };
    this.currentState = ProfileUiState.initial(userId);
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
    for (let i = 0; i < this.subscriptions.length; i++) {
      this.subscriptions[i].unsubscribe();
    }
    this.subscriptions.length = 0;
    this.listeners.length = 0;
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

      case 'openSharedChat': {
        const open: OpenSharedChatEffect = effect as OpenSharedChatEffect;
        this.logger.info(TAG, 'open_shared_chat', `chatId=${open.chatId}`);
        this.onOpenChat(open.chatId);
        break;
      }

      default:
        break;
    }
  }

  // ------------------------------------------------------------------
  // PROFILE-103：共享内容（媒体/文件/链接/群组）
  // ------------------------------------------------------------------

  private fetchMoreSharedContent(tab: number): void {
    if (tab === 3) {
      this.fetchSharedGroups(true);
      return;
    }
    this.fetchSharedContent(tab, true);
  }

  /**
   * Tab 0..2：先 createPrivateChat 拿 chatId，再 searchChatMessages 按
   * 照片视频/文件/链接过滤器检索。失败只 logError，并以当前数组回灌
   * OnSharedContentLoaded 仅用于复位 sharedLoading（不打扰 UI）。
   */
  private fetchSharedContent(tab: number, isLoadMore: boolean = false): void {
    this.logger.info(TAG, 'fetch_shared_content', `userId=${this.userId},tab=${tab},isLoadMore=${isLoadMore}`);
    if (this.cachedPrivateChatId > 0) {
      this.searchSharedContent(tab, this.cachedPrivateChatId, isLoadMore);
      return;
    }
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
          this.failSharedContent(tab);
          return;
        }
        if (out.ok) {
          const chat: Chat | null = decodeChat(out.value as TdJsonRaw);
          if (chat === null) {
            this.failSharedContent(tab);
            return;
          }
          this.cachedPrivateChatId = chat.id;
          this.logger.info(TAG, 'shared_private_chat_ready', `tab=${tab},chatId=${chat.id}`);
          this.searchSharedContent(tab, chat.id, isLoadMore);
        }
      }).catch((): void => {
      });
    }
    if (res.err) {
      this.logger.logError(TAG, res.error);
      this.failSharedContent(tab);
    }
  }

  private searchSharedContent(tab: number, chatId: number, isLoadMore: boolean = false): void {
    const req: SearchChatMessages = new SearchChatMessages();
    req.chat_id = chatId;
    req.query = '';
    req.from_message_id = isLoadMore ? (this.nextOffsets.get(tab) ?? 0) : 0;
    req.offset = 0;
    req.limit = SHARED_PAGE_LIMIT;
    req.sender_id = null;
    req.topic_id = null;
    if (tab === 0) {
      const filter: TdSearchMessagesFilter = new SearchMessagesFilterPhotoAndVideo();
      req.filter = filter;
    } else if (tab === 1) {
      const filter: TdSearchMessagesFilter = new SearchMessagesFilterDocument();
      req.filter = filter;
    } else {
      const filter: TdSearchMessagesFilter = new SearchMessagesFilterUrl();
      req.filter = filter;
    }
    const res: Result<TdPendingRequest, AppError> =
      this.scope.request('searchChatMessages', encodeSearchChatMessages(req) as TdWireObject);
    this.logger.info(TAG, 'search_shared_content',
      `tab=${tab},chatId=${chatId},fromMessageId=${req.from_message_id},accepted=${res.ok}`);
    if (res.ok) {
      res.value.promise.then((out: Result<TdWireObject, AppError>): void => {
        if (this.destroyed) {
          return;
        }
        if (out.err) {
          this.logger.logError(TAG, out.error);
          this.failSharedContent(tab);
          return;
        }
        if (out.ok) {
          const found: FoundChatMessages | null = decodeFoundChatMessages(out.value as TdJsonRaw);
          if (found === null) {
            this.failSharedContent(tab);
            return;
          }
          this.handleSharedMessages(tab, found, isLoadMore);
        }
      }).catch((): void => {
      });
    }
    if (res.err) {
      this.logger.logError(TAG, res.error);
      this.failSharedContent(tab);
    }
  }

  /** FoundChatMessages → 按 Tab 映射条目；只覆盖本次拉取的数组，其余透传当前状态。 */
  private handleSharedMessages(tab: number, found: FoundChatMessages, isLoadMore: boolean = false): void {
    const nextFromId: number = found.next_from_message_id;
    const hasMore: boolean = nextFromId > 0 && found.messages.length > 0;
    this.nextOffsets.set(tab, nextFromId);

    if (tab === 0) {
      const media: SharedMediaItem[] = [];
      for (let i = 0; i < found.messages.length; i++) {
        const msg: Message = found.messages[i];
        const item: SharedMediaItem | null = this.mediaItemOf(msg.content);
        if (item !== null) {
          media.push(item);
        }
      }
      const combined: SharedMediaItem[] = isLoadMore ? [...this.currentState.sharedMedia, ...media] : media;
      this.logger.info(TAG, 'shared_media_ok', `count=${combined.length},hasMore=${hasMore}`);
      this.dispatch(new OnSharedContentLoaded(0, combined, this.currentState.sharedFiles, this.currentState.sharedLinks, hasMore));
      return;
    }
    if (tab === 1) {
      const files: SharedFileItem[] = [];
      for (let i = 0; i < found.messages.length; i++) {
        const msg: Message = found.messages[i];
        const item: SharedFileItem | null = fileItemOf(msg);
        if (item !== null) {
          files.push(item);
        }
      }
      const combined: SharedFileItem[] = isLoadMore ? [...this.currentState.sharedFiles, ...files] : files;
      this.logger.info(TAG, 'shared_files_ok', `count=${combined.length},hasMore=${hasMore}`);
      this.dispatch(new OnSharedContentLoaded(1, this.currentState.sharedMedia, combined, this.currentState.sharedLinks, hasMore));
      return;
    }
    const links: SharedLinkItem[] = [];
    for (let i = 0; i < found.messages.length; i++) {
      const msg: Message = found.messages[i];
      const item: SharedLinkItem | null = linkItemOf(msg.content);
      if (item !== null) {
        links.push(item);
      }
    }
    const combined: SharedLinkItem[] = isLoadMore ? [...this.currentState.sharedLinks, ...links] : links;
    this.logger.info(TAG, 'shared_links_ok', `count=${combined.length},hasMore=${hasMore}`);
    this.dispatch(new OnSharedContentLoaded(2, this.currentState.sharedMedia, this.currentState.sharedFiles, combined, hasMore));
  }

  /** messagePhoto/messageVideo → SharedMediaItem；缩略图未就绪则触发下载订阅（局部回灌）。 */
  private mediaItemOf(content: TdMessageContent | null): SharedMediaItem | null {
    if (content === null) {
      return null;
    }
    if (content.type === 'messagePhoto') {
      const photo: MessagePhoto = content as MessagePhoto;
      if (photo.photo === null) {
        return null;
      }
      const size: PhotoSize | null = pickThumbPhotoSize(photo.photo.sizes);
      if (size === null || size.photo === null) {
        return null;
      }
      return this.sharedMediaItemOfFile(size.photo, true);
    }
    if (content.type === 'messageVideo') {
      const videoMsg: MessageVideo = content as MessageVideo;
      // 优先新版 cover（Photo），退回 video.thumbnail 的 JPEG 缩略图。
      if (videoMsg.cover !== null) {
        const coverSize: PhotoSize | null = pickThumbPhotoSize(videoMsg.cover.sizes);
        if (coverSize !== null && coverSize.photo !== null) {
          return this.sharedMediaItemOfFile(coverSize.photo, false);
        }
      }
      if (videoMsg.video !== null &&
        videoMsg.video.thumbnail !== null &&
        videoMsg.video.thumbnail.file !== null) {
        return this.sharedMediaItemOfFile(videoMsg.video.thumbnail.file, false);
      }
      return null;
    }
    return null;
  }

  private sharedMediaItemOfFile(file: File, isPhoto: boolean): SharedMediaItem {
    const fileId: number = file.id;
    let localPath: string | null = this.fileRegistry.getLocalPath(fileId);
    if (localPath === null) {
      localPath = this.resolveSharedMediaFile(fileId);
    }
    return new SharedMediaItem(fileId, localPath, isPhoto);
  }

  /** 缩略图本地路径未就绪：订阅 updateFile，落盘后局部重写 media 数组中该条目的 localPath。 */
  private resolveSharedMediaFile(fileId: number): string | null {
    if (!this.subscribedSharedFileIds.has(fileId)) {
      this.subscribedSharedFileIds.add(fileId);
      this.subscriptions.push(this.fileRegistry.subscribeFile(fileId, (file: File): void => {
        if (this.destroyed) {
          return;
        }
        const path: string | null = this.fileRegistry.getLocalPath(file.id);
        if (path === null || path.length === 0) {
          return;
        }
        const media: SharedMediaItem[] = this.currentState.sharedMedia;
        const updated: SharedMediaItem[] = [];
        let touched: boolean = false;
        for (let i = 0; i < media.length; i++) {
          const it: SharedMediaItem = media[i];
          if (it.fileId === file.id && (it.localPath === null || it.localPath.length === 0)) {
            updated.push(new SharedMediaItem(it.fileId, path, it.isPhoto));
            touched = true;
          } else {
            updated.push(it);
          }
        }
        if (touched) {
          this.dispatch(new OnSharedContentLoaded(0, updated, this.currentState.sharedFiles, this.currentState.sharedLinks, this.currentState.sharedHasMore));
        }
      }));
      const res: Result<TdPendingRequest, AppError> =
        this.fileRegistry.downloadFile(fileId, SHARED_THUMB_DOWNLOAD_PRIORITY);
      if (res.err) {
        this.logger.logError(TAG, res.error);
      }
    }
    return null;
  }

  /** Tab 3：getGroupsInCommon → 逐 id getChat 解析标题/副标题，全部回灌。 */
  private fetchSharedGroups(isLoadMore: boolean = false): void {
    this.logger.info(TAG, 'fetch_shared_groups', `userId=${this.userId},isLoadMore=${isLoadMore}`);
    const offsetChatId: number = isLoadMore ? (this.nextOffsets.get(3) ?? 0) : 0;
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
          this.nextOffsets.set(3, chats.chat_ids[chats.chat_ids.length - 1]);
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
    this.dispatch(new OnSharedContentFailed(3));
  }
}
