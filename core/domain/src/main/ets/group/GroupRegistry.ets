/**
 * core/domain — 群组与超级群注册表（PROFILE-102）。
 *
 * 管理单账号作用域下的群组（BasicGroup）与超级群/频道（Supergroup）实体及详情：
 * - 单账号事实源：维护 BasicGroup、BasicGroupFullInfo、Supergroup、SupergroupFullInfo、ChatMembers 缓存；
 * - 事件监听：订阅 Gateway 的 update 事件，处理：
 *   - UpdateBasicGroup / UpdateBasicGroupFullInfo
 *   - UpdateSupergroup / UpdateSupergroupFullInfo
 * - 监听器机制：支持按 groupId 订阅 FullInfo 变更；
 * - 查询与请求方法：
 *   - getBasicGroup, requestBasicGroup, getBasicGroupFullInfo, requestBasicGroupFullInfo
 *   - getSupergroup, requestSupergroup, getSupergroupFullInfo, requestSupergroupFullInfo
 *   - getSupergroupMembers, requestSupergroupMembers
 * - 展示辅助函数：formatMemberCount, getGroupAvatarLetters, formatMemberRole
 * - 纯 ArkTS / 100% Kit-free。
 */

import {
  BasicGroup,
  BasicGroupFullInfo,
  Supergroup,
  SupergroupFullInfo,
  GetBasicGroup,
  GetBasicGroupFullInfo,
  GetSupergroup,
  GetSupergroupFullInfo,
  GetSupergroupMembers,
  ChatMembers,
  ChatMember,
  UpdateBasicGroup,
  UpdateBasicGroupFullInfo,
  UpdateSupergroup,
  UpdateSupergroupFullInfo,
  decodeBasicGroup,
  decodeBasicGroupFullInfo,
  decodeSupergroup,
  decodeSupergroupFullInfo,
  decodeChatMembers,
  encodeGetBasicGroup,
  encodeGetBasicGroupFullInfo,
  encodeGetSupergroup,
  encodeGetSupergroupFullInfo,
  encodeGetSupergroupMembers,
  decodeTdUpdate,
  TdJsonRaw,
  TdUpdate
} from '@tgx/core-td-api-generated';
import { AccountScope } from '@tgx/core-account';
import { TdPendingRequest, TdRoutedEvent, TdUpdateFilter, TdUpdateSubscription, TdWireObject } from '@tgx/td-gateway';
import { Result, AppError } from '@tgx/core-common';
import { Subscription } from '@tgx/platform-ports';

class SimpleSubscription implements Subscription {
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
 * 提取群组/频道标题的 1-2 位首字母供圆形占位头像使用。
 */
export function getGroupAvatarLetters(title: string): string {
  if (title.length === 0) {
    return '';
  }
  const trimmed: string = title.trim();
  const parts: string[] = trimmed.split(/\s+/).filter((p: string): boolean => p.length > 0);
  if (parts.length >= 2) {
    const c1: string = extractFirstChar(parts[0]);
    const c2: string = extractFirstChar(parts[1]);
    return (c1 + c2).toUpperCase();
  }
  return extractFirstChar(trimmed).toUpperCase();
}

/**
 * 格式化群成员或频道订阅者数量。
 */
export function formatMemberCount(count: number, isChannel: boolean): string {
  if (isChannel) {
    if (count === 1) {
      return '1 subscriber';
    }
    return `${count} subscribers`;
  }
  if (count === 1) {
    return '1 member';
  }
  return `${count} members`;
}

/**
 * 格式化成员身份角标（Owner / Admin / 自定义 title）。
 */
export function formatMemberRole(member: ChatMember): string {
  if (member.tag && member.tag.length > 0) {
    return member.tag;
  }
  if (member.status !== null) {
    if (member.status.type === 'chatMemberStatusCreator') {
      return 'Owner';
    }
    if (member.status.type === 'chatMemberStatusAdministrator') {
      return 'Admin';
    }
  }
  return '';
}

export class GroupRegistry {
  private readonly scope: AccountScope;
  private readonly basicGroups: Map<number, BasicGroup> = new Map();
  private readonly basicGroupFullInfos: Map<number, BasicGroupFullInfo> = new Map();
  private readonly supergroups: Map<number, Supergroup> = new Map();
  private readonly supergroupFullInfos: Map<number, SupergroupFullInfo> = new Map();
  private readonly supergroupMembers: Map<number, ChatMember[]> = new Map();

  private readonly basicGroupListeners: Map<number, ((info: BasicGroupFullInfo) => void)[]> = new Map();
  private readonly supergroupListeners: Map<number, ((info: SupergroupFullInfo) => void)[]> = new Map();

  private updateSub: TdUpdateSubscription | null = null;

  constructor(scope: AccountScope) {
    this.scope = scope;
    this.start();
  }

  start(): void {
    if (this.updateSub !== null) {
      return;
    }
    const filter: TdUpdateFilter = {
      clientId: this.scope.clientId,
      types: [
        'updateBasicGroup',
        'updateBasicGroupFullInfo',
        'updateSupergroup',
        'updateSupergroupFullInfo'
      ]
    };
    this.updateSub = this.scope.gatewayInstance.subscribeUpdates(
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
    if (this.updateSub !== null) {
      this.updateSub.unsubscribe();
      this.updateSub = null;
    }
    this.basicGroupListeners.clear();
    this.supergroupListeners.clear();
  }

  clear(): void {
    this.basicGroups.clear();
    this.basicGroupFullInfos.clear();
    this.supergroups.clear();
    this.supergroupFullInfos.clear();
    this.supergroupMembers.clear();
    this.basicGroupListeners.clear();
    this.supergroupListeners.clear();
  }

  // --- BasicGroup ---

  getBasicGroup(basicGroupId: number): BasicGroup | null {
    const group: BasicGroup | undefined = this.basicGroups.get(basicGroupId);
    return group !== undefined ? group : null;
  }

  putBasicGroup(group: BasicGroup): void {
    this.basicGroups.set(group.id, group);
  }

  getBasicGroupFullInfo(basicGroupId: number): BasicGroupFullInfo | null {
    const info: BasicGroupFullInfo | undefined = this.basicGroupFullInfos.get(basicGroupId);
    return info !== undefined ? info : null;
  }

  putBasicGroupFullInfo(basicGroupId: number, info: BasicGroupFullInfo): void {
    this.basicGroupFullInfos.set(basicGroupId, info);
    this.notifyBasicGroupListeners(basicGroupId, info);
  }

  subscribeBasicGroupFullInfo(
    basicGroupId: number,
    listener: (info: BasicGroupFullInfo) => void
  ): Subscription {
    let list: ((info: BasicGroupFullInfo) => void)[] | undefined = this.basicGroupListeners.get(basicGroupId);
    if (list === undefined) {
      list = [];
      this.basicGroupListeners.set(basicGroupId, list);
    }
    list.push(listener);

    return new SimpleSubscription((): void => {
      const listeners: ((info: BasicGroupFullInfo) => void)[] | undefined =
        this.basicGroupListeners.get(basicGroupId);
      if (listeners !== undefined) {
        const idx: number = listeners.indexOf(listener);
        if (idx >= 0) {
          listeners.splice(idx, 1);
        }
        if (listeners.length === 0) {
          this.basicGroupListeners.delete(basicGroupId);
        }
      }
    });
  }

  requestBasicGroup(basicGroupId: number): Result<TdPendingRequest, AppError> {
    const req: GetBasicGroup = new GetBasicGroup();
    req.basic_group_id = basicGroupId;

    const result: Result<TdPendingRequest, AppError> =
      this.scope.request('getBasicGroup', encodeGetBasicGroup(req) as TdWireObject);
    if (result.ok) {
      const self: GroupRegistry = this;
      result.value.promise.then((res: Result<TdWireObject, AppError>): void => {
        if (res.ok) {
          const group: BasicGroup | null = decodeBasicGroup(res.value as TdJsonRaw);
          if (group !== null) {
            self.putBasicGroup(group);
          }
        }
      }).catch((): void => {});
    }
    return result;
  }

  requestBasicGroupFullInfo(basicGroupId: number): Result<TdPendingRequest, AppError> {
    const req: GetBasicGroupFullInfo = new GetBasicGroupFullInfo();
    req.basic_group_id = basicGroupId;

    const result: Result<TdPendingRequest, AppError> =
      this.scope.request('getBasicGroupFullInfo', encodeGetBasicGroupFullInfo(req) as TdWireObject);
    if (result.ok) {
      const self: GroupRegistry = this;
      result.value.promise.then((res: Result<TdWireObject, AppError>): void => {
        if (res.ok) {
          const info: BasicGroupFullInfo | null = decodeBasicGroupFullInfo(res.value as TdJsonRaw);
          if (info !== null) {
            self.putBasicGroupFullInfo(basicGroupId, info);
          }
        }
      }).catch((): void => {});
    }
    return result;
  }

  // --- Supergroup ---

  getSupergroup(supergroupId: number): Supergroup | null {
    const group: Supergroup | undefined = this.supergroups.get(supergroupId);
    return group !== undefined ? group : null;
  }

  putSupergroup(group: Supergroup): void {
    this.supergroups.set(group.id, group);
  }

  getSupergroupFullInfo(supergroupId: number): SupergroupFullInfo | null {
    const info: SupergroupFullInfo | undefined = this.supergroupFullInfos.get(supergroupId);
    return info !== undefined ? info : null;
  }

  putSupergroupFullInfo(supergroupId: number, info: SupergroupFullInfo): void {
    this.supergroupFullInfos.set(supergroupId, info);
    this.notifySupergroupListeners(supergroupId, info);
  }

  subscribeSupergroupFullInfo(
    supergroupId: number,
    listener: (info: SupergroupFullInfo) => void
  ): Subscription {
    let list: ((info: SupergroupFullInfo) => void)[] | undefined = this.supergroupListeners.get(supergroupId);
    if (list === undefined) {
      list = [];
      this.supergroupListeners.set(supergroupId, list);
    }
    list.push(listener);

    return new SimpleSubscription((): void => {
      const listeners: ((info: SupergroupFullInfo) => void)[] | undefined =
        this.supergroupListeners.get(supergroupId);
      if (listeners !== undefined) {
        const idx: number = listeners.indexOf(listener);
        if (idx >= 0) {
          listeners.splice(idx, 1);
        }
        if (listeners.length === 0) {
          this.supergroupListeners.delete(supergroupId);
        }
      }
    });
  }

  requestSupergroup(supergroupId: number): Result<TdPendingRequest, AppError> {
    const req: GetSupergroup = new GetSupergroup();
    req.supergroup_id = supergroupId;

    const result: Result<TdPendingRequest, AppError> =
      this.scope.request('getSupergroup', encodeGetSupergroup(req) as TdWireObject);
    if (result.ok) {
      const self: GroupRegistry = this;
      result.value.promise.then((res: Result<TdWireObject, AppError>): void => {
        if (res.ok) {
          const group: Supergroup | null = decodeSupergroup(res.value as TdJsonRaw);
          if (group !== null) {
            self.putSupergroup(group);
          }
        }
      }).catch((): void => {});
    }
    return result;
  }

  requestSupergroupFullInfo(supergroupId: number): Result<TdPendingRequest, AppError> {
    const req: GetSupergroupFullInfo = new GetSupergroupFullInfo();
    req.supergroup_id = supergroupId;

    const result: Result<TdPendingRequest, AppError> =
      this.scope.request('getSupergroupFullInfo', encodeGetSupergroupFullInfo(req) as TdWireObject);
    if (result.ok) {
      const self: GroupRegistry = this;
      result.value.promise.then((res: Result<TdWireObject, AppError>): void => {
        if (res.ok) {
          const info: SupergroupFullInfo | null = decodeSupergroupFullInfo(res.value as TdJsonRaw);
          if (info !== null) {
            self.putSupergroupFullInfo(supergroupId, info);
          }
        }
      }).catch((): void => {});
    }
    return result;
  }

  // --- Supergroup Members ---

  getSupergroupMembers(supergroupId: number): ChatMember[] | null {
    const members: ChatMember[] | undefined = this.supergroupMembers.get(supergroupId);
    return members !== undefined ? members : null;
  }

  putSupergroupMembers(supergroupId: number, members: ChatMember[]): void {
    this.supergroupMembers.set(supergroupId, members);
  }

  requestSupergroupMembers(
    supergroupId: number,
    offset: number = 0,
    limit: number = 50
  ): Result<TdPendingRequest, AppError> {
    const req: GetSupergroupMembers = new GetSupergroupMembers();
    req.supergroup_id = supergroupId;
    req.offset = offset;
    req.limit = limit;

    const result: Result<TdPendingRequest, AppError> =
      this.scope.request('getSupergroupMembers', encodeGetSupergroupMembers(req) as TdWireObject);
    if (result.ok) {
      const self: GroupRegistry = this;
      result.value.promise.then((res: Result<TdWireObject, AppError>): void => {
        if (res.ok) {
          const chatMembers: ChatMembers | null = decodeChatMembers(res.value as TdJsonRaw);
          if (chatMembers !== null && chatMembers.members.length > 0) {
            self.putSupergroupMembers(supergroupId, chatMembers.members);
          }
        }
      }).catch((): void => {});
    }
    return result;
  }

  // --- Event Handling ---

  handleUpdate(update: TdUpdate): void {
    if (update.type === 'updateBasicGroup') {
      const groupUpdate: UpdateBasicGroup = update as UpdateBasicGroup;
      if (groupUpdate.basic_group !== null) {
        this.putBasicGroup(groupUpdate.basic_group);
      }
    } else if (update.type === 'updateBasicGroupFullInfo') {
      const fullInfoUpdate: UpdateBasicGroupFullInfo = update as UpdateBasicGroupFullInfo;
      if (fullInfoUpdate.basic_group_full_info !== null) {
        this.putBasicGroupFullInfo(
          fullInfoUpdate.basic_group_id,
          fullInfoUpdate.basic_group_full_info
        );
      }
    } else if (update.type === 'updateSupergroup') {
      const groupUpdate: UpdateSupergroup = update as UpdateSupergroup;
      if (groupUpdate.supergroup !== null) {
        this.putSupergroup(groupUpdate.supergroup);
      }
    } else if (update.type === 'updateSupergroupFullInfo') {
      const fullInfoUpdate: UpdateSupergroupFullInfo = update as UpdateSupergroupFullInfo;
      if (fullInfoUpdate.supergroup_full_info !== null) {
        this.putSupergroupFullInfo(
          fullInfoUpdate.supergroup_id,
          fullInfoUpdate.supergroup_full_info
        );
      }
    }
  }

  private notifyBasicGroupListeners(basicGroupId: number, info: BasicGroupFullInfo): void {
    const listeners: ((info: BasicGroupFullInfo) => void)[] | undefined =
      this.basicGroupListeners.get(basicGroupId);
    if (listeners !== undefined && listeners.length > 0) {
      const copy: ((info: BasicGroupFullInfo) => void)[] = listeners.slice();
      for (let i = 0; i < copy.length; i++) {
        copy[i](info);
      }
    }
  }

  private notifySupergroupListeners(supergroupId: number, info: SupergroupFullInfo): void {
    const listeners: ((info: SupergroupFullInfo) => void)[] | undefined =
      this.supergroupListeners.get(supergroupId);
    if (listeners !== undefined && listeners.length > 0) {
      const copy: ((info: SupergroupFullInfo) => void)[] = listeners.slice();
      for (let i = 0; i < copy.length; i++) {
        copy[i](info);
      }
    }
  }
}
