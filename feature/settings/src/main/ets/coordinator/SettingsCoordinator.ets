/**
 * feature/settings — 设置页协调器（SET-101）。
 *
 * 桥接 AccountScope / UserRegistry / TDLib Gateway：
 * - start() 时派发 LoadUserProfile；
 * - 处理 LogoutEffect：调用 scope.request('logOut') 并导航回登录或通知上层；
 * - 提供状态订阅 subscribe(listener: (state: SettingsUiState) => void): () => void;
 * - 统一异常捕获与 error message 处理。
 */

import { Logger } from '@tgx/observability';
import { AppError, ManualClock, Result, SequentialIdGenerator } from '@tgx/core-common';
import { AccountScope } from '@tgx/core-account';
import { UserRegistry } from '@tgx/core-domain';
import {
  GetMe,
  GetStorageStatistics,
  GetUserFullInfo,
  LogOut,
  OptimizeStorage,
  StorageStatistics,
  TdJsonRaw,
  User,
  UserFullInfo,
  decodeStorageStatistics,
  decodeUser,
  decodeUserFullInfo,
  encodeGetMe,
  encodeGetStorageStatistics,
  encodeGetUserFullInfo,
  encodeLogOut,
  encodeOptimizeStorage
} from '@tgx/core-td-api-generated';
import { TdPendingRequest, TdWireObject } from '@tgx/td-gateway';
import { ReducerEnv, ReducerResult } from '@tgx/feature-template';
import { SettingsUiState } from '../contract/SettingsUiState';
import { formatStorageLabel } from '../model/StorageSize';
import {
  CacheCleared,
  LoadStorageStats,
  LoadUserProfile,
  ProfileLoaded,
  SetErrorMessage,
  SettingsIntent,
  StorageStatsLoaded,
  UserProfileData
} from '../contract/SettingsIntent';
import {
  ClearCacheEffect,
  LoadProfileEffect,
  LogoutEffect,
  NavigateToAuthEffect,
  SettingsEffect,
  ShowToastEffect
} from '../contract/SettingsEffect';
import { settingsReducer } from '../reducer/SettingsReducer';

const TAG: string = 'SettingsCoordinator';

export type SettingsUiStateListener = (state: SettingsUiState) => void;

export class SettingsCoordinator {
  private readonly scope: AccountScope;
  private readonly userRegistry: UserRegistry;
  private readonly env: ReducerEnv;
  private readonly onNavigateToAuth: () => void;
  private readonly logger: Logger;
  private currentState: SettingsUiState;
  private readonly listeners: SettingsUiStateListener[] = [];
  private unsubscribeUser: (() => void) | null = null;
  private subscribedUserId: number = 0;
  private destroyed: boolean = false;

  constructor(
    scope: AccountScope,
    userRegistry?: UserRegistry,
    env?: ReducerEnv,
    onNavigateToAuth?: () => void,
    logger?: Logger
  ) {
    this.scope = scope;
    this.userRegistry = userRegistry !== undefined ? userRegistry : new UserRegistry(scope);
    this.env = env !== undefined ? env : {
      clock: new ManualClock(1000, 500),
      ids: new SequentialIdGenerator('settings-')
    };
    this.onNavigateToAuth = onNavigateToAuth !== undefined ? onNavigateToAuth : (): void => {};
    this.logger = logger !== undefined ? logger : new Logger();
    this.currentState = SettingsUiState.initial();
  }

  get state(): SettingsUiState {
    return this.currentState;
  }

  start(): void {
    this.dispatch(new LoadUserProfile());
    // SET-104：进页即静默拉一次真实存储占用（此前 storageCacheSize 是硬编码占位）。
    this.dispatch(new LoadStorageStats());
  }

  destroy(): void {
    this.destroyed = true;
    if (this.unsubscribeUser !== null) {
      this.unsubscribeUser();
      this.unsubscribeUser = null;
    }
    this.listeners.length = 0;
  }

  subscribe(listener: SettingsUiStateListener): () => void {
    this.listeners.push(listener);
    listener(this.currentState);
    return (): void => {
      const idx: number = this.listeners.indexOf(listener);
      if (idx >= 0) {
        this.listeners.splice(idx, 1);
      }
    };
  }

  dispatch(intent: SettingsIntent): void {
    const result: ReducerResult<SettingsUiState, SettingsEffect> = settingsReducer(
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

  private executeEffect(effect: SettingsEffect): void {
    switch (effect.kind) {
      case 'loadProfile':
        this.handleLoadProfile();
        break;

      case 'logout':
        this.handleLogout();
        break;

      case 'clearCache':
        this.handleClearCache();
        break;

      case 'loadStorageStats':
        this.handleLoadStorageStats();
        break;

      case 'navigateToAuth':
        this.logger.info(TAG, 'navigating_to_auth');
        this.onNavigateToAuth();
        break;

      case 'showToast': {
        const toastEffect: ShowToastEffect = effect as ShowToastEffect;
        this.logger.info(TAG, 'toast', toastEffect.message);
        break;
      }

      default:
        break;
    }
  }

  private handleLoadProfile(): void {
    const meReq: GetMe = new GetMe();
    const result: Result<TdPendingRequest, AppError> = this.scope.request(
      'getMe',
      encodeGetMe(meReq) as TdWireObject
    );

    if (result.ok) {
      const self: SettingsCoordinator = this;
      result.value.promise.then((res: Result<TdWireObject, AppError>): void => {
        if (res.ok) {
          const user: User | null = decodeUser(res.value as TdJsonRaw);
          if (user !== null) {
            self.userRegistry.putUser(user);
            self.fetchFullInfoAndDispatch(user);
          } else {
            self.dispatch(new SetErrorMessage('Failed to decode user profile'));
          }
        }
        if (res.err) {
          self.dispatch(new SetErrorMessage(res.error.message));
        }
      }).catch((e: Error): void => {
        self.dispatch(new SetErrorMessage(e.message));
      });
    }
    if (result.err) {
      this.dispatch(new SetErrorMessage(result.error.message));
    }
  }

  private fetchFullInfoAndDispatch(user: User): void {
    const fullReq: GetUserFullInfo = new GetUserFullInfo();
    fullReq.user_id = user.id;
    const result: Result<TdPendingRequest, AppError> = this.scope.request(
      'getUserFullInfo',
      encodeGetUserFullInfo(fullReq) as TdWireObject
    );

    if (result.ok) {
      const self: SettingsCoordinator = this;
      result.value.promise.then((res: Result<TdWireObject, AppError>): void => {
        let bio: string = '';
        if (res.ok) {
          const fullInfo: UserFullInfo | null = decodeUserFullInfo(res.value as TdJsonRaw);
          if (fullInfo !== null && fullInfo.bio !== null) {
            bio = fullInfo.bio.text;
          }
        }
        if (res.err) {
          this.logger.logError(TAG, res.error);
        }
        self.dispatchProfile(user, bio);
      }).catch((): void => {
        self.dispatchProfile(user, '');
      });
    }
    if (result.err) {
      this.dispatchProfile(user, '');
    }
  }

  private dispatchProfile(user: User, bio: string): void {
    const displayName: string = this.userRegistry.formatFullName(user);
    let username: string = '';
    if (user.usernames !== null) {
      if (user.usernames.active_usernames.length > 0) {
        username = user.usernames.active_usernames[0];
      } else if (user.usernames.editable_username.length > 0) {
        username = user.usernames.editable_username;
      }
    }
    let avatarPath: string | null = null;
    if (
      user.profile_photo !== null &&
      user.profile_photo.small !== null &&
      user.profile_photo.small.local !== null &&
      user.profile_photo.small.local.path.length > 0
    ) {
      avatarPath = user.profile_photo.small.local.path;
    }

    const profile: UserProfileData = {
      userId: user.id,
      displayName: displayName.length > 0 ? displayName : (username.length > 0 ? username : `User ${user.id}`),
      username: username,
      phoneNumber: user.phone_number,
      avatarLocalPath: avatarPath,
      bio: bio
    };

    this.dispatch(new ProfileLoaded(profile));
    this.subscribeUserUpdates(user.id);
  }

  private subscribeUserUpdates(userId: number): void {
    if (this.subscribedUserId === userId && this.unsubscribeUser !== null) {
      return;
    }
    if (this.unsubscribeUser !== null) {
      this.unsubscribeUser();
      this.unsubscribeUser = null;
    }
    this.subscribedUserId = userId;
    const self: SettingsCoordinator = this;
    const sub = this.userRegistry.subscribeUser(userId, (updatedUser: User): void => {
      if (!self.destroyed) {
        self.dispatchProfile(updatedUser, self.currentState.bio);
      }
    });
    this.unsubscribeUser = (): void => {
      sub.unsubscribe();
    };
  }

  private handleLogout(): void {
    const req: LogOut = new LogOut();
    const result: Result<TdPendingRequest, AppError> = this.scope.request(
      'logOut',
      encodeLogOut(req) as TdWireObject
    );

    if (result.ok) {
      const self: SettingsCoordinator = this;
      result.value.promise.then((res: Result<TdWireObject, AppError>): void => {
        if (res.ok) {
          self.executeEffect(new NavigateToAuthEffect());
        }
        if (res.err) {
          self.dispatch(new SetErrorMessage(res.error.message));
        }
      }).catch((e: Error): void => {
        self.dispatch(new SetErrorMessage(e.message));
      });
    }
    if (result.err) {
      this.dispatch(new SetErrorMessage(result.error.message));
    }
  }

  /**
   * SET-104：拉取真实存储占用（getStorageStatistics）。
   * chat_limit=0 → 只算总量，不要按会话拆分的明细（设置页只需要总占用）；
   * 失败静默——设置页其它功能不受影响，保留上一次的显示值。
   */
  private handleLoadStorageStats(): void {
    const statsReq: GetStorageStatistics = new GetStorageStatistics();
    statsReq.chat_limit = 0;
    const result: Result<TdPendingRequest, AppError> = this.scope.request(
      'getStorageStatistics',
      encodeGetStorageStatistics(statsReq) as TdWireObject
    );

    if (result.ok) {
      const self: SettingsCoordinator = this;
      result.value.promise.then((res: Result<TdWireObject, AppError>): void => {
        if (self.destroyed) {
          return;
        }
        if (res.ok) {
          const stats: StorageStatistics | null = decodeStorageStatistics(res.value as TdJsonRaw);
          if (stats !== null) {
            self.dispatch(new StorageStatsLoaded(formatStorageLabel(stats.size, stats.count)));
          }
        }
        if (res.err) {
          this.logger.logError(TAG, res.error);
        }
      }).catch((): void => {
      });
    }
    if (result.err) {
      this.logger.logError(TAG, result.error);
    }
  }

  /**
   * SET-104：一键清理缓存（optimizeStorage）。
   *
   * size/ttl/count/immunity_delay 全传 0 = **删到剩 0 字节**（TDLib 里 -1 才是
   * "用默认上限"，0 是硬上限），file_types 留空即 TDLib 默认口径（缩略图/头像/
   * 贴纸/壁纸不删）。与 Android SettingsCacheController 的
   * `OptimizeStorage(0, 0, 0, 0, ...)` 完全一致。
   *
   * 清理后**用响应里返回的真实统计**刷新显示——响应就是清理后的整体
   * StorageStatistics（return_deleted_file_statistics=false），因此不必再发
   * 一次 getStorageStatistics；此前这里硬编码 '0 B' 是错的（数据库、语言包等
   * 非文件占用并不会被清掉，真实值通常不为 0）。
   */
  private handleClearCache(): void {
    const optReq: OptimizeStorage = new OptimizeStorage();
    optReq.size = 0;
    optReq.ttl = 0;
    optReq.count = 0;
    optReq.immunity_delay = 0;
    optReq.return_deleted_file_statistics = false;
    const result: Result<TdPendingRequest, AppError> = this.scope.request(
      'optimizeStorage',
      encodeOptimizeStorage(optReq) as TdWireObject
    );

    if (result.ok) {
      const self: SettingsCoordinator = this;
      result.value.promise.then((res: Result<TdWireObject, AppError>): void => {
        if (self.destroyed) {
          return;
        }
        if (res.ok) {
          const stats: StorageStatistics | null = decodeStorageStatistics(res.value as TdJsonRaw);
          const label: string = stats !== null
            ? formatStorageLabel(stats.size, stats.count)
            : '0 B';
          self.dispatch(new CacheCleared(label));
        }
        if (res.err) {
          self.dispatch(new SetErrorMessage(res.error.message));
        }
      }).catch((e: Error): void => {
        self.dispatch(new SetErrorMessage(e.message));
      });
    }
    if (result.err) {
      this.dispatch(new SetErrorMessage(result.error.message));
    }
  }
}
