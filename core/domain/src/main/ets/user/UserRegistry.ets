/**
 * core/domain — 用户状态注册表（MSG-102）。
 *
 * 管理单账号作用域下的用户实体与在线状态：
 * - 单账号事实源：内存维护 Map<number, User>，由 AccountScope 构造；
 * - 事件监听：订阅 Gateway 的 update 事件，处理：
 *   - UpdateUser（type === 'updateUser'）：更新缓存中的用户对象，触发监听回调；
 *   - UpdateUserStatus（type === 'updateUserStatus'）：更新指定用户的 status 字段，触发监听回调；
 * - 监听器机制：支持按 userId 订阅状态变更，返回符合 @tgx/platform-ports 契约的标准 Subscription；
 * - 查询与请求方法：getUser, putUser, requestUser；
 * - 格式化与展示辅助函数：formatFullName, getAvatarLetters, getAvatarColorIndex, isOnline；
 * - 生命周期：stop() 取消 Gateway 订阅并清理监听器。
 */

import {
  User,
  UserFullInfo,
  GetUser,
  GetUserFullInfo,
  UpdateUser,
  UpdateUserStatus,
  UpdateUserFullInfo,
  encodeGetUser,
  encodeGetUserFullInfo,
  decodeUser,
  decodeUserFullInfo,
  decodeTdUpdate,
  TdJsonRaw,
  TdUpdate
} from '@tgx/core-td-api-generated';
import { AccountScope } from '@tgx/core-account';
import { TdPendingRequest, TdRoutedEvent, TdUpdateFilter, TdUpdateSubscription, TdWireObject } from '@tgx/td-gateway';
import { Result, AppError } from '@tgx/core-common';
import { Subscription } from '@tgx/platform-ports';

class UserSubscription implements Subscription {
  private active: boolean = true;
  private readonly onUnsubscribe: () => void;

  constructor(onUnsubscribe: () => void) {
    this.onUnsubscribe = onUnsubscribe;
  }

  get isActive(): boolean {
    return this.active;
  }

  unsubscribe(): void {
    if (!this.active) {
      return;
    }
    this.active = false;
    this.onUnsubscribe();
  }
}

/** 提取字符串首字符（正确处理 Unicode 代理对）。 */
function extractFirstChar(str: string): string {
  if (str.length === 0) {
    return '';
  }
  const codePoint: number | undefined = str.codePointAt(0);
  if (codePoint === undefined) {
    return '';
  }
  return String.fromCodePoint(codePoint);
}

/**
 * 格式化用户全名：拼接 first_name 与 last_name，空时安全降级返回空字符串。
 */
export function formatFullName(user: User | null): string {
  if (user === null) {
    return '';
  }
  const first: string = user.first_name ? user.first_name.trim() : '';
  const last: string = user.last_name ? user.last_name.trim() : '';
  if (first.length > 0 && last.length > 0) {
    return `${first} ${last}`;
  }
  if (first.length > 0) {
    return first;
  }
  if (last.length > 0) {
    return last;
  }
  return '';
}

/**
 * 提取 1-2 位大写首字母供彩色圆形头像使用。
 */
export function getAvatarLetters(user: User | null): string {
  if (user === null) {
    return '';
  }
  const first: string = user.first_name ? user.first_name.trim() : '';
  const last: string = user.last_name ? user.last_name.trim() : '';

  if (first.length > 0 && last.length > 0) {
    const c1: string = extractFirstChar(first);
    const c2: string = extractFirstChar(last);
    return (c1 + c2).toUpperCase();
  }

  if (first.length > 0) {
    const parts: string[] = first.split(/\s+/).filter((p: string): boolean => p.length > 0);
    if (parts.length >= 2) {
      const c1: string = extractFirstChar(parts[0]);
      const c2: string = extractFirstChar(parts[1]);
      return (c1 + c2).toUpperCase();
    }
    return extractFirstChar(first).toUpperCase();
  }

  if (last.length > 0) {
    const parts: string[] = last.split(/\s+/).filter((p: string): boolean => p.length > 0);
    if (parts.length >= 2) {
      const c1: string = extractFirstChar(parts[0]);
      const c2: string = extractFirstChar(parts[1]);
      return (c1 + c2).toUpperCase();
    }
    return extractFirstChar(last).toUpperCase();
  }

  return '';
}

/**
 * 计算用户头像的颜色索引：确定性哈希，取模 0..6 对应色盘。
 */
export function getAvatarColorIndex(userId: number): number {
  if (!Number.isFinite(userId)) {
    return 0;
  }
  const absId: number = Math.abs(Math.floor(userId));
  return absId % 7;
}

/**
 * 判断用户当前是否在线（user?.status?.type === 'userStatusOnline'）。
 */
export function isOnline(user: User | null): boolean {
  if (user === null || user.status === null || user.status === undefined) {
    return false;
  }
  return user.status.type === 'userStatusOnline';
}

export class UserRegistry {
  private readonly scope: AccountScope;
  private readonly users: Map<number, User> = new Map();
  private readonly fullInfos: Map<number, UserFullInfo> = new Map();
  private readonly listenersByUserId: Map<number, ((user: User) => void)[]> = new Map();
  private readonly fullInfoListenersByUserId: Map<number, ((info: UserFullInfo) => void)[]> = new Map();
  private subscription: TdUpdateSubscription | null = null;

  constructor(scope: AccountScope) {
    this.scope = scope;
    this.start();
  }

  start(): void {
    if (this.subscription !== null) {
      return;
    }
    const filter: TdUpdateFilter = {
      clientId: this.scope.clientId,
      // PROFILE-101：updateUserFullInfo 在 getUserFullInfo 回包后由 TDLib 推送，用于资料页 bio 刷新。
      types: ['updateUser', 'updateUserStatus', 'updateUserFullInfo']
    };
    this.subscription = this.scope.gatewayInstance.subscribeUpdates(
      filter,
      (event: TdRoutedEvent): void => {
        const update: TdUpdate | null = decodeTdUpdate(event.payload as TdJsonRaw);
        if (update === null) {
          return;
        }
        this.handleUpdate(update);
      }
    );
  }

  stop(): void {
    if (this.subscription !== null) {
      this.subscription.unsubscribe();
      this.subscription = null;
    }
    this.listenersByUserId.clear();
    this.fullInfoListenersByUserId.clear();
  }

  clear(): void {
    this.users.clear();
    this.fullInfos.clear();
    this.listenersByUserId.clear();
    this.fullInfoListenersByUserId.clear();
  }

  getUser(userId: number): User | null {
    const user: User | undefined = this.users.get(userId);
    return user !== undefined ? user : null;
  }

  putUser(user: User): void {
    const existing: User | undefined = this.users.get(user.id);
    let targetUser: User;
    if (existing !== undefined && existing !== user) {
      this.updateInPlace(existing, user);
      targetUser = existing;
    } else {
      this.users.set(user.id, user);
      targetUser = user;
    }
    this.notifyListeners(user.id, targetUser);
  }

  subscribeUser(userId: number, listener: (user: User) => void): Subscription {
    let listeners: ((user: User) => void)[] | undefined = this.listenersByUserId.get(userId);
    if (listeners === undefined) {
      listeners = [];
      this.listenersByUserId.set(userId, listeners);
    }
    listeners.push(listener);

    return new UserSubscription((): void => {
      const list: ((user: User) => void)[] | undefined = this.listenersByUserId.get(userId);
      if (list !== undefined) {
        const index: number = list.indexOf(listener);
        if (index >= 0) {
          list.splice(index, 1);
        }
        if (list.length === 0) {
          this.listenersByUserId.delete(userId);
        }
      }
    });
  }

  requestUser(userId: number): Result<TdPendingRequest, AppError> {
    const req: GetUser = new GetUser();
    req.user_id = userId;

    const result: Result<TdPendingRequest, AppError> =
      this.scope.request('getUser', encodeGetUser(req) as TdWireObject);
    if (result.ok) {
      const self: UserRegistry = this;
      result.value.promise.then((res: Result<TdWireObject, AppError>): void => {
        if (res.ok) {
          const user: User | null = decodeUser(res.value as TdJsonRaw);
          if (user !== null) {
            self.putUser(user);
          }
        }
      }).catch((): void => {
      });
    }
    return result;
  }

  /**
   * PROFILE-101：请求用户完整资料（bio 等）。回包经 TDLib 以 updateUserFullInfo
   * 推送回来后入缓存并通知监听；调用方也可直接消费返回的 promise。
   */
  requestUserFullInfo(userId: number): Result<TdPendingRequest, AppError> {
    const req: GetUserFullInfo = new GetUserFullInfo();
    req.user_id = userId;

    const result: Result<TdPendingRequest, AppError> =
      this.scope.request('getUserFullInfo', encodeGetUserFullInfo(req) as TdWireObject);
    if (result.ok) {
      const self: UserRegistry = this;
      result.value.promise.then((res: Result<TdWireObject, AppError>): void => {
        if (res.ok) {
          const info: UserFullInfo | null = decodeUserFullInfo(res.value as TdJsonRaw);
          if (info !== null) {
            self.putUserFullInfo(userId, info);
          }
        }
      }).catch((): void => {
      });
    }
    return result;
  }

  getUserFullInfo(userId: number): UserFullInfo | null {
    const info: UserFullInfo | undefined = this.fullInfos.get(userId);
    return info !== undefined ? info : null;
  }

  putUserFullInfo(userId: number, info: UserFullInfo): void {
    this.fullInfos.set(userId, info);
    this.notifyFullInfoListeners(userId, info);
  }

  subscribeUserFullInfo(userId: number, listener: (info: UserFullInfo) => void): Subscription {
    let listeners: ((info: UserFullInfo) => void)[] | undefined =
      this.fullInfoListenersByUserId.get(userId);
    if (listeners === undefined) {
      listeners = [];
      this.fullInfoListenersByUserId.set(userId, listeners);
    }
    listeners.push(listener);
    return new UserSubscription((): void => {
      const list: ((info: UserFullInfo) => void)[] | undefined =
        this.fullInfoListenersByUserId.get(userId);
      if (list !== undefined) {
        const index: number = list.indexOf(listener);
        if (index >= 0) {
          list.splice(index, 1);
        }
        if (list.length === 0) {
          this.fullInfoListenersByUserId.delete(userId);
        }
      }
    });
  }

  formatFullName(user: User | null): string {
    return formatFullName(user);
  }

  static formatFullName(user: User | null): string {
    return formatFullName(user);
  }

  getAvatarLetters(user: User | null): string {
    return getAvatarLetters(user);
  }

  static getAvatarLetters(user: User | null): string {
    return getAvatarLetters(user);
  }

  getAvatarColorIndex(userId: number): number {
    return getAvatarColorIndex(userId);
  }

  static getAvatarColorIndex(userId: number): number {
    return getAvatarColorIndex(userId);
  }

  isOnline(user: User | null): boolean {
    return isOnline(user);
  }

  static isOnline(user: User | null): boolean {
    return isOnline(user);
  }

  private handleUpdate(update: TdUpdate): void {
    if (update.type === 'updateUser') {
      const userUpdate: UpdateUser = update as UpdateUser;
      if (userUpdate.user !== null) {
        this.putUser(userUpdate.user);
      }
    } else if (update.type === 'updateUserStatus') {
      const statusUpdate: UpdateUserStatus = update as UpdateUserStatus;
      const existing: User | undefined = this.users.get(statusUpdate.user_id);
      if (existing !== undefined) {
        existing.status = statusUpdate.status;
        this.notifyListeners(existing.id, existing);
      }
    } else if (update.type === 'updateUserFullInfo') {
      const fullInfoUpdate: UpdateUserFullInfo = update as UpdateUserFullInfo;
      if (fullInfoUpdate.user_full_info !== null) {
        this.putUserFullInfo(fullInfoUpdate.user_id, fullInfoUpdate.user_full_info);
      }
    }
  }

  private updateInPlace(target: User, source: User): void {
    target.first_name = source.first_name;
    target.last_name = source.last_name;
    target.usernames = source.usernames;
    target.phone_number = source.phone_number;
    target.status = source.status;
    target.profile_photo = source.profile_photo;
    target.accent_color_id = source.accent_color_id;
    target.background_custom_emoji_id = source.background_custom_emoji_id;
    target.upgraded_gift_colors = source.upgraded_gift_colors;
    target.profile_accent_color_id = source.profile_accent_color_id;
    target.profile_background_custom_emoji_id = source.profile_background_custom_emoji_id;
    target.emoji_status = source.emoji_status;
    target.is_contact = source.is_contact;
    target.is_mutual_contact = source.is_mutual_contact;
    target.is_close_friend = source.is_close_friend;
    target.verification_status = source.verification_status;
    target.is_premium = source.is_premium;
    target.is_support = source.is_support;
    target.restriction_info = source.restriction_info;
    target.active_story_state = source.active_story_state;
    target.restricts_new_chats = source.restricts_new_chats;
    target.paid_message_star_count = source.paid_message_star_count;
    target.have_access = source.have_access;
    target.type_ = source.type_;
    target.language_code = source.language_code;
    target.added_to_attachment_menu = source.added_to_attachment_menu;
  }

  private notifyListeners(userId: number, user: User): void {
    const listeners: ((user: User) => void)[] | undefined = this.listenersByUserId.get(userId);
    if (listeners !== undefined && listeners.length > 0) {
      const copy: ((user: User) => void)[] = [...listeners];
      for (let i = 0; i < copy.length; i++) {
        copy[i](user);
      }
    }
  }

  private notifyFullInfoListeners(userId: number, info: UserFullInfo): void {
    const listeners: ((info: UserFullInfo) => void)[] | undefined =
      this.fullInfoListenersByUserId.get(userId);
    if (listeners !== undefined && listeners.length > 0) {
      const copy: ((info: UserFullInfo) => void)[] = [...listeners];
      for (let i = 0; i < copy.length; i++) {
        copy[i](info);
      }
    }
  }
}
