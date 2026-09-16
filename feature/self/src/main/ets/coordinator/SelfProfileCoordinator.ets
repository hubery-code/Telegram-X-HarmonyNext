/**
 * feature/self — 我的资料页协调器（SELF-101）。
 *
 * 数据链路（对齐 TGX 自身资料页 editMode 信息面）：
 * - getMe（scope.request）：回包 decodeUser → putUser 入 UserRegistry → 组帧回灌；
 * - getUserFullInfo（同一 registry）：bio（FormattedText.text 可空）+
 *   birthdate（`YYYY年M月D日 (N 岁)`，按当前日期算 N；year=0 退化为 `M月D日`）；
 * - 大头像（profile_photo.big）：FileRegistry 本地路径命中即用，未命中
 *   downloadFile(priority 2) 并订阅 updateFile，落盘后回灌路径；
 * - EditTapped / SettingsSectionTapped 仅占位 log（后续工作包接编辑页/设置页）。
 *
 * 生命周期：构造即建 registries（其构造自带 start），start() 发 getMe，
 * destroy() 停订阅并停两个 registry。
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
  GetMe,
  encodeGetMe,
  decodeUser,
  Birthdate,
  TdJsonRaw
} from '@tgx/core-td-api-generated';
import { TdPendingRequest, TdWireObject } from '@tgx/td-gateway';
import { Logger } from '@tgx/observability';
import { Subscription } from '@tgx/platform-ports';
import { ReducerEnv, ReducerResult } from '@tgx/feature-template';
import { SelfProfileUiState } from '../contract/SelfProfileUiState';
import {
  SelfProfileIntent,
  OnProfileLoaded,
  OnAvatarFileLoaded,
  OnProfileFailed,
  SettingsSectionTapped
} from '../contract/SelfProfileIntent';
import { SelfProfileEffect, FetchMeEffect } from '../contract/SelfProfileEffect';
import { selfProfileReducer } from '../reducer/SelfProfileReducer';

const TAG: string = 'SelfProfileCoordinator';

/** 头像下载优先级（对齐 ProfileCoordinator 拉取头像的 priority=2）。 */
const AVATAR_DOWNLOAD_PRIORITY: number = 2;

export interface SelfProfileCoordinatorOptions {
  readonly logger?: Logger;
}

export type SelfProfileUiStateListener = (uiState: SelfProfileUiState) => void;

/** SELF-101：在线状态简文案（MVP 中文短文案，不格式化 last seen 具体时间）。 */
function formatUserStatusText(user: User): string {
  const status = user.status;
  if (status === null || status === undefined) {
    return '';
  }
  switch (status.type) {
    case 'userStatusOnline':
      return '在线';
    case 'userStatusOffline':
      return '离线';
    case 'userStatusRecently':
      return '最近上线';
    case 'userStatusLastWeek':
      return '一周内上线';
    case 'userStatusLastMonth':
      return '一月内上线';
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

/**
 * 生日文案：`YYYY年M月D日 (N 岁)`（N 按当前日期周岁算，生日未到减一）；
 * year=0（未知年份）退化为 `M月D日`；无 birthdate 返回空串。
 */
function formatBirthdayText(birthdate: Birthdate | null): string {
  if (birthdate === null || birthdate === undefined) {
    return '';
  }
  const day: number = birthdate.day;
  const month: number = birthdate.month;
  const year: number = birthdate.year;
  if (day <= 0 || month <= 0) {
    return '';
  }
  if (year <= 0) {
    return `${month}月${day}日`;
  }
  const now: Date = new Date();
  let age: number = now.getFullYear() - year;
  const currentMonth: number = now.getMonth() + 1;
  const currentDay: number = now.getDate();
  if (currentMonth < month || (currentMonth === month && currentDay < day)) {
    age = age - 1;
  }
  if (age < 0) {
    age = 0;
  }
  return `${year}年${month}月${day}日 (${age} 岁)`;
}

export class SelfProfileCoordinator {
  private readonly scope: AccountScope;
  private readonly userRegistry: UserRegistry;
  private readonly fileRegistry: FileRegistry;
  private readonly logger: Logger;
  private readonly env: ReducerEnv;
  private currentState: SelfProfileUiState;
  private readonly listeners: SelfProfileUiStateListener[] = [];
  private readonly subscriptions: Subscription[] = [];
  /** 最近一次组帧用的 User / UserFullInfo，供 update 订阅重放整帧。 */
  private lastUser: User | null = null;
  private lastFullInfo: UserFullInfo | null = null;
  /** 已订阅下载回调的头像 fileId，防重复订阅。 */
  private subscribedAvatarFileId: number = -1;
  private destroyed: boolean = false;

  constructor(scope: AccountScope, options?: SelfProfileCoordinatorOptions) {
    this.scope = scope;
    this.userRegistry = new UserRegistry(scope);
    this.fileRegistry = new FileRegistry(scope);
    this.logger = options !== undefined && options.logger !== undefined
      ? options.logger
      : new Logger();
    this.env = {
      clock: new ManualClock(1000, 500),
      ids: new SequentialIdGenerator('self-')
    };
    this.currentState = SelfProfileUiState.initial();
  }

  get state(): SelfProfileUiState {
    return this.currentState;
  }

  start(): void {
    this.executeEffect(new FetchMeEffect());
  }

  dispatch(intent: SelfProfileIntent): void {
    const result: ReducerResult<SelfProfileUiState, SelfProfileEffect> = selfProfileReducer(
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
    // 占位动作：仅 log，后续工作包接编辑页/设置页导航。
    if (intent.kind === 'editTapped') {
      this.logger.info(TAG, 'edit_tapped');
    } else if (intent.kind === 'settingsSectionTapped') {
      const tapped: SettingsSectionTapped = intent as SettingsSectionTapped;
      this.logger.info(TAG, 'settings_section_tapped', `section=${tapped.section}`);
    }
    for (let i = 0; i < result.effects.length; i++) {
      this.executeEffect(result.effects[i]);
    }
  }

  subscribe(listener: SelfProfileUiStateListener): () => void {
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

  private executeEffect(effect: SelfProfileEffect): void {
    switch (effect.kind) {
      case 'fetchMe': {
        this.logger.info(TAG, 'fetch_me');
        const req: GetMe = new GetMe();
        const res: Result<TdPendingRequest, AppError> =
          this.scope.request('getMe', encodeGetMe(req) as TdWireObject);
        if (res.ok) {
          res.value.promise.then((out: Result<TdWireObject, AppError>): void => {
            if (this.destroyed) {
              return;
            }
            if (out.ok) {
              const user: User | null = decodeUser(out.value as TdJsonRaw);
              if (user !== null) {
                this.onSelfUserLoaded(user);
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

  /** getMe 回包：入库、订阅刷新、拉 full info（bio/生日）、解析头像。 */
  private onSelfUserLoaded(user: User): void {
    this.lastUser = user;
    this.userRegistry.putUser(user);
    this.resolveAvatarFile(user);

    const cachedInfo: UserFullInfo | null = this.userRegistry.getUserFullInfo(user.id);
    if (cachedInfo !== null) {
      this.lastFullInfo = cachedInfo;
    }
    this.subscriptions.push(this.userRegistry.subscribeUser(user.id, (updated: User): void => {
      if (this.destroyed) {
        return;
      }
      this.lastUser = updated;
      this.pushFrame();
    }));
    this.subscriptions.push(this.userRegistry.subscribeUserFullInfo(user.id, (info: UserFullInfo): void => {
      if (this.destroyed) {
        return;
      }
      this.lastFullInfo = info;
      this.pushFrame();
    }));
    const infoRes: Result<TdPendingRequest, AppError> = this.userRegistry.requestUserFullInfo(user.id);
    if (infoRes.err) {
      // full info 失败不阻塞页面（基础信息已在手），回灌基础帧并记日志。
      this.logger.logError(TAG, infoRes.error);
      this.pushFrame();
    }
  }

  /** 组整帧回灌：基础信息 + full info（生日/bio）+ 在线状态 + 头像占位。 */
  private pushFrame(): void {
    const user: User | null = this.lastUser;
    if (user === null) {
      return;
    }
    const info: UserFullInfo | null = this.lastFullInfo;
    this.dispatch(new OnProfileLoaded(
      formatFullName(user),
      primaryUsernameOf(user),
      user.phone_number !== null && user.phone_number !== undefined ? user.phone_number : '',
      info !== null ? formatBirthdayText(info.birthdate) : '',
      info !== null ? bioTextOf(info) : '',
      formatUserStatusText(user),
      getAvatarLetters(user),
      getAvatarColorIndex(user.id)
    ));
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
}
