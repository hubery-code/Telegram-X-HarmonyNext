/**
 * feature/contact — 联系人页协调器（CONTACT-101）。
 *
 * 数据链路（对齐 Android ContactsController 的信息面，MVP 裁剪）：
 * - getContacts：拿 user_ids 全量联系人 id 列表；
 * - 逐用户经 core-domain UserRegistry（getUser 缓存命中即刻回灌，requestUser 未命中
 *   补拉；updateUser/updateUserStatus 订阅驱动全量重建），只收 userTypeRegular；
 * - 头像小图（profile_photo.small）：FileRegistry 本地路径命中即用，未命中
 *   downloadFile(priority 2) 并订阅 updateFile，落盘后随下次全量重建回灌路径；
 * - 排序：`compareContacts`（Android `ContactsController.sortUsers` 同规则：键为
 *   `Strings.clean(firstName + ' ' + lastName)`，按 UTF-16 码元序比较），
 *   与页面分组字母出自同一套规则，段不会被打断；
 * - 行点击：ContactTapped → reducer 出 OpenUserProfile 效应 → options.onOpenUserProfile
 *   交给装配层导航到用户资料页。
 *
 * 生命周期：构造即建 registries（其构造自带 start），start() 发 getContacts，
 * destroy() 停订阅与 registries。
 */

import { AccountScope } from '@tgx/core-account';
import { ManualClock, Result, AppError, AppErrors, SequentialIdGenerator } from '@tgx/core-common';
import {
  UserRegistry,
  FileRegistry,
  formatFullName,
  getAvatarLetters,
  getAvatarColorIndex
} from '@tgx/core-domain';
import {
  User,
  GetContacts,
  Users,
  encodeGetContacts,
  decodeUsers,
  TdJsonRaw
} from '@tgx/core-td-api-generated';
import { TdPendingRequest, TdWireObject } from '@tgx/td-gateway';
import { Logger } from '@tgx/observability';
import { Subscription } from '@tgx/platform-ports';
import { ReducerEnv, ReducerResult } from '@tgx/feature-template';
import { ContactsItem, ContactsUiState } from '../contract/ContactsUiState';
import {
  ContactsIntent,
  OnContactsLoaded,
  OnContactsFailed
} from '../contract/ContactsIntent';
import { ContactsEffect, FetchContacts, OpenUserProfile } from '../contract/ContactsEffect';
import { contactsReducer } from '../reducer/ContactsReducer';
import { compareContacts } from '../model/ContactsSections';

const TAG: string = 'ContactsCoordinator';

/** 头像下载优先级（对齐 ProfileCoordinator 拉取头像的 priority=2）。 */
const AVATAR_DOWNLOAD_PRIORITY: number = 2;

export interface ContactsCoordinatorOptions {
  /** 行点击后交给装配层打开用户资料页（缺省 no-op）。 */
  readonly onOpenUserProfile?: (userId: number) => void;
  readonly logger?: Logger;
}

export type ContactsUiStateListener = (uiState: ContactsUiState) => void;

/** 在线状态简文案（与 ProfileCoordinator 同款 MVP 口径）。 */
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

/** 取展示用户名：优先 editable，其次第一个 active（与 ProfileCoordinator 同规则）。 */
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

/** 小头像本地路径：命中即用；未命中触发下载并订阅 updateFile。 */
function avatarPathOf(user: User, fileRegistry: FileRegistry): string | null {
  const photo = user.profile_photo;
  if (photo === null || photo === undefined || photo.small === null || photo.small === undefined) {
    return null;
  }
  const localPath: string | null = fileRegistry.getLocalPath(photo.small.id);
  return localPath !== null && localPath.length > 0 ? localPath : null;
}

export class ContactsCoordinator {
  private readonly scope: AccountScope;
  private readonly userRegistry: UserRegistry;
  private readonly fileRegistry: FileRegistry;
  private readonly onOpenUserProfile: (userId: number) => void;
  private readonly logger: Logger;
  private readonly env: ReducerEnv;
  private currentState: ContactsUiState;
  private readonly listeners: ContactsUiStateListener[] = [];
  private readonly subscriptions: Subscription[] = [];
  /** 当前联系人 userId 全量（getContacts 回包），头像落盘后据此全量重建。 */
  private contactUserIds: number[] = [];
  /** 已订阅下载回调的小头像 fileId，防重复订阅。 */
  private readonly subscribedAvatarFileIds: Set<number> = new Set();
  private destroyed: boolean = false;

  constructor(scope: AccountScope, options?: ContactsCoordinatorOptions) {
    this.scope = scope;
    this.userRegistry = new UserRegistry(scope);
    this.fileRegistry = new FileRegistry(scope);
    this.onOpenUserProfile = options !== undefined && options.onOpenUserProfile !== undefined
      ? options.onOpenUserProfile
      : (userId: number): void => {};
    this.logger = options !== undefined && options.logger !== undefined
      ? options.logger
      : new Logger();
    this.env = {
      clock: new ManualClock(1000, 500),
      ids: new SequentialIdGenerator('contacts-')
    };
    this.currentState = ContactsUiState.initial();
  }

  get state(): ContactsUiState {
    return this.currentState;
  }

  start(): void {
    this.fetchContacts();
  }

  dispatch(intent: ContactsIntent): void {
    const result: ReducerResult<ContactsUiState, ContactsEffect> = contactsReducer(
      this.currentState,
      intent,
      this.env
    );
    if (result.state !== this.currentState) {
      this.currentState = result.state;
      for (let i: number = 0; i < this.listeners.length; i++) {
        this.listeners[i](this.currentState);
      }
    }
    for (let i: number = 0; i < result.effects.length; i++) {
      this.executeEffect(result.effects[i]);
    }
  }

  subscribe(listener: ContactsUiStateListener): () => void {
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
    for (let i: number = 0; i < this.subscriptions.length; i++) {
      this.subscriptions[i].unsubscribe();
    }
    this.subscriptions.length = 0;
    this.listeners.length = 0;
    this.subscribedAvatarFileIds.clear();
    this.fileRegistry.stop();
    this.userRegistry.stop();
  }

  /** getContacts：拿 user_ids，逐个补拉用户并汇总。 */
  private fetchContacts(): void {
    this.logger.info(TAG, 'fetch_contacts');
    const req: GetContacts = new GetContacts();
    const res: Result<TdPendingRequest, AppError> =
      this.scope.request('getContacts', encodeGetContacts(req) as TdWireObject);
    if (res.ok) {
      res.value.promise.then((out: Result<TdWireObject, AppError>): void => {
        if (this.destroyed) {
          return;
        }
        if (out.ok) {
          const users: Users | null = decodeUsers(out.value as TdJsonRaw);
          if (users === null) {
            this.dispatch(new OnContactsFailed(
              AppErrors.parameter('invalid', 'users', 'getContacts returned an unexpected payload')
            ));
            return;
          }
          this.loadContactUsers(users.user_ids);
        }
        if (out.err) {
          this.dispatch(new OnContactsFailed(out.error));
        }
      }).catch((): void => {
      });
    }
    if (res.err) {
      this.dispatch(new OnContactsFailed(res.error));
    }
  }

  /**
   * 逐用户：缓存命中即刻可汇总，未缓存 requestUser 补拉；
   * 每个用户订阅 updateUser/updateUserStatus，任一变化全量重建列表（联系人页量级下可接受）。
   */
  private loadContactUsers(userIds: number[]): void {
    this.contactUserIds = userIds.slice();
    for (let i: number = 0; i < userIds.length; i++) {
      const userId: number = userIds[i];
      this.subscriptions.push(this.userRegistry.subscribeUser(userId, (): void => {
        this.publishContacts();
      }));
    }
    // 缓存命中先回灌一帧（避免空态闪烁）。
    this.publishContacts();
    // 未缓存的发请求刷新（回包经 subscribeUser 推回后全量重建）。
    for (let i: number = 0; i < userIds.length; i++) {
      const userId: number = userIds[i];
      if (this.userRegistry.getUser(userId) !== null) {
        continue;
      }
      const res: Result<TdPendingRequest, AppError> = this.userRegistry.requestUser(userId);
      if (res.err) {
        this.logger.logError(TAG, res.error);
      }
    }
  }

  /** 按当前缓存全量重建联系人 items 并回灌（排序 + 头像解析都在这）。 */
  private publishContacts(): void {
    const items: ContactsItem[] = [];
    for (let i: number = 0; i < this.contactUserIds.length; i++) {
      const user: User | null = this.userRegistry.getUser(this.contactUserIds[i]);
      if (user === null) {
        continue;
      }
      // 只展示正常用户；删除/未知类型账号跳过。
      if (user.type_ === null || user.type_.type !== 'userTypeRegular') {
        continue;
      }
      items.push(this.buildItem(user));
    }
    items.sort(compareContacts);
    this.dispatch(new OnContactsLoaded(items));
  }

  private buildItem(user: User): ContactsItem {
    const avatarPath: string | null = avatarPathOf(user, this.fileRegistry);
    if (avatarPath === null) {
      this.ensureAvatarDownload(user);
    }
    return new ContactsItem(
      user.id,
      formatFullName(user),
      primaryUsernameOf(user),
      avatarPath,
      getAvatarLetters(user),
      getAvatarColorIndex(user.id),
      formatUserStatusText(user)
    );
  }

  /** 小头像未落盘：订阅 updateFile + downloadFile(priority 2)，落盘后全量重建回灌路径。 */
  private ensureAvatarDownload(user: User): void {
    const photo = user.profile_photo;
    if (photo === null || photo === undefined || photo.small === null || photo.small === undefined) {
      return;
    }
    const fileId: number = photo.small.id;
    if (this.subscribedAvatarFileIds.has(fileId)) {
      return;
    }
    this.subscribedAvatarFileIds.add(fileId);
    this.subscriptions.push(this.fileRegistry.subscribeFile(fileId, (): void => {
      if (this.destroyed) {
        return;
      }
      this.publishContacts();
    }));
    const res: Result<TdPendingRequest, AppError> =
      this.fileRegistry.downloadFile(fileId, AVATAR_DOWNLOAD_PRIORITY);
    if (res.err) {
      this.logger.logError(TAG, res.error);
    }
  }

  private executeEffect(effect: ContactsEffect): void {
    switch (effect.kind) {
      case 'fetchContacts': {
        this.logger.info(TAG, 'fetch_contacts_retry');
        this.fetchContacts();
        break;
      }
      case 'openUserProfile': {
        const open: OpenUserProfile = effect as OpenUserProfile;
        this.logger.info(TAG, 'open_user_profile', `userId=${open.userId}`);
        this.onOpenUserProfile(open.userId);
        break;
      }
      default:
        break;
    }
  }
}
