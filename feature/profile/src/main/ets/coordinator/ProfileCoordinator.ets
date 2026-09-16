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
  TdJsonRaw
} from '@tgx/core-td-api-generated';
import { TdPendingRequest, TdWireObject } from '@tgx/td-gateway';
import { Logger } from '@tgx/observability';
import { Subscription } from '@tgx/platform-ports';
import { ReducerEnv, ReducerResult } from '@tgx/feature-template';
import { ProfileUiState } from '../contract/ProfileUiState';
import { ProfileIntent, OnProfileLoaded, OnBioLoaded, OnAvatarFileLoaded, OnProfileFailed } from '../contract/ProfileIntent';
import { ProfileEffect, CreatePrivateChatEffect } from '../contract/ProfileEffect';
import { profileReducer } from '../reducer/ProfileReducer';

const TAG: string = 'ProfileCoordinator';

/** 头像下载优先级（对齐 ChatCoordinator 拉取头像的 priority=2）。 */
const AVATAR_DOWNLOAD_PRIORITY: number = 2;

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

    // 完整资料（bio）：同样缓存优先 + 订阅 updateUserFullInfo。
    const cachedInfo = this.userRegistry.getUserFullInfo(this.userId);
    if (cachedInfo !== null) {
      this.dispatch(new OnBioLoaded(bioTextOf(cachedInfo)));
    }
    this.subscriptions.push(this.userRegistry.subscribeUserFullInfo(this.userId, (info: UserFullInfo): void => {
      if (!this.destroyed) {
        this.dispatch(new OnBioLoaded(bioTextOf(info)));
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
      default:
        break;
    }
  }
}
