/**
 * core/account — AccountRegistry：账号 scope 生命周期的唯一管理点（CORE-003，计划 §5.5）。
 *
 * 「不得使用承载所有账户的可变全局单例」：本类就是全部可变状态的持有者，
 * 由调用方（entry 装配层）构造并持有——本模块不提供任何全局实例。
 *
 * 职责：
 * - create（幂等：同 accountKey 且未 closed → 返回既有 scope；closed → 重建新 scope）；
 * - activate/hibernate：状态转换 + 持久化 enabled 翻转（冷启动恢复语义，§6.1）；
 * - close（幂等：取消全部 pending、停 gateway、从清单移除、迟到事件由 scope 守卫丢弃）；
 * - restoreAll（冷启动：按持久化描述符批量恢复；单账号失败不拖垮其他账号，逐账号上报）；
 * - 事件隔离：每个 scope 的 gateway 经 AccountEventIsolator 包装，跨账号事件在桥边界丢弃；
 *   registry monitor 订阅负责未知 clientId 记账（AppError internal，不静默）。
 *
 * 持久化：files/accounts/registry.json 账号清单（AccountManifestStore，经 AppFilesPort）。
 * clientId 不持久化：TDLib clientId 是进程内标识，每次冷启动 createClient 重新分配（§6.1）。
 *
 * 线程契约：全部方法在 ArkTS 线程同步执行（与 CORE-002 相同前提）。
 */

import { AppError, AppErrors, Clock, Result, SystemClock, err, ok } from '@tgx/core-common';
import { TdGatewayOptions, TdNativeBridgeLike, TdNativeEventSink } from '@tgx/td-gateway';
import { AppFilesPort } from '@tgx/platform-ports';
import { AccountIdGenerator, RandomAccountIdGenerator } from './AccountIds';
import {
  AccountClientIdHolder,
  AccountEventIsolator,
  AccountIsolatorMetrics
} from './AccountEventIsolator';
import { AccountDescriptor, createDescriptor } from './AccountDescriptor';
import { AccountDirectoryLayout, buildAccountDirectories, validateAccountKey } from './AccountDirectories';
import { AccountManifestStore } from './AccountManifest';
import { AccountLifecycleState } from './AccountLifecycle';
import { AccountScope } from './AccountScope';

export interface AccountRestoreFailure {
  /** 恢复失败的账号 key；清单整体读取失败时为 '*'。 */
  readonly accountKey: string;
  readonly error: AppError;
}

export interface AccountRestoreReport {
  /** 成功恢复的 scope（enabled → active，disabled → hibernating）。 */
  readonly restored: AccountScope[];
  /** 逐账号上报的失败，绝不因单账号失败中断整体恢复。 */
  readonly failures: AccountRestoreFailure[];
}

export interface AccountRegistryOptions {
  readonly bridge: TdNativeBridgeLike;
  readonly files: AppFilesPort;
  readonly idGenerator?: AccountIdGenerator;
  /** createdAtMillis 时钟（缺省 SystemClock）。 */
  readonly clock?: Clock;
  /** 透传给每个 scope 的 TdGateway（超时/IdGenerator/协议错误出口等）。 */
  readonly gatewayOptions?: TdGatewayOptions;
  /** 未知 clientId 事件出口（缺省只计数）。 */
  readonly onUnknownClientId?: (error: AppError, clientId: number) => void;
}

export interface AccountRegistryMetrics {
  readonly scopeCount: number;
  readonly activeCount: number;
  readonly hibernatingCount: number;
  readonly closedCount: number;
  readonly unknownClientIdEventCount: number;
}

export class AccountRegistry {
  private readonly bridge: TdNativeBridgeLike;
  private readonly files: AppFilesPort;
  private readonly idGenerator: AccountIdGenerator;
  private readonly clock: Clock;
  private readonly gatewayOptions: TdGatewayOptions | undefined;
  private readonly isolator: AccountEventIsolator;
  private readonly manifest: AccountManifestStore;
  private readonly scopes: Map<string, AccountScope> = new Map();

  private monitorSubscriptionId: number = -1;

  constructor(options: AccountRegistryOptions) {
    this.bridge = options.bridge;
    this.files = options.files;
    this.idGenerator = options.idGenerator !== undefined ? options.idGenerator : new RandomAccountIdGenerator();
    this.clock = options.clock !== undefined ? options.clock : new SystemClock();
    this.gatewayOptions = options.gatewayOptions;
    this.isolator = new AccountEventIsolator(options.onUnknownClientId);
    this.manifest = new AccountManifestStore(options.files);
  }

  /**
   * 建立未知 clientId 监控订阅（幂等）。生产在 entry 装配层调用一次；
   * 未 start 时未知 clientId 事件不被记账（scope 隔离不受影响）。
   */
  start(): void {
    if (this.monitorSubscriptionId >= 0) {
      return;
    }
    const sink: TdNativeEventSink = this.isolator.createMonitorSink();
    this.monitorSubscriptionId = this.bridge.subscribeUpdates(sink);
  }

  /** 撤下监控订阅（幂等）。scope 的隔离桥订阅由各 scope 生命周期自管。 */
  stop(): void {
    if (this.monitorSubscriptionId >= 0) {
      this.bridge.unsubscribe(this.monitorSubscriptionId);
      this.monitorSubscriptionId = -1;
    }
  }

  get started(): boolean {
    return this.monitorSubscriptionId >= 0;
  }

  /**
   * 创建账号 scope（创建即 active：createClient → 订阅 → gateway.start）。
   * 幂等：同 accountKey 已有非 closed scope → 返回既有；已有 closed → 移除后重建。
   * 持久化失败（清单 upsert err）→ 关闭已开 scope 并返回 err，注册表不留半态。
   */
  create(accountKey: string): Result<AccountScope, AppError> {
    const existing: AccountScope | undefined = this.scopes.get(accountKey);
    if (existing !== undefined) {
      if (existing.lifecycle !== 'closed') {
        return ok<AccountScope, AppError>(existing);
      }
      this.scopes.delete(accountKey);
    }
    const keyError: AppError | null = validateAccountKey(accountKey);
    if (keyError !== null) {
      return err<AccountScope, AppError>(keyError);
    }
    const dirs: Result<AccountDirectoryLayout, AppError> = buildAccountDirectories(accountKey);
    if (dirs.ok === false) {
      return err<AccountScope, AppError>(dirs.error);
    }
    const descriptor: AccountDescriptor = createDescriptor(
      accountKey,
      this.idGenerator.nextAccountId(),
      this.clock.nowMillis(),
      true
    );
    const opened: Result<AccountScope, AppError> = this.openScope(descriptor, dirs.value, true);
    if (opened.ok === false) {
      return err<AccountScope, AppError>(opened.error);
    }
    const scope: AccountScope = opened.value;
    const persisted: Result<void, AppError> = this.manifest.upsert(descriptor);
    if (persisted.ok === false) {
      scope.close();
      return err<AccountScope, AppError>(persisted.error);
    }
    this.scopes.set(accountKey, scope);
    return ok<AccountScope, AppError>(scope);
  }

  /** 激活账号。休眠 → active 时把 enabled=true 持久化（冷启动恢复语义）。 */
  activate(accountKey: string): Result<AccountScope, AppError> {
    const scope: AccountScope | undefined = this.scopes.get(accountKey);
    if (scope === undefined) {
      return err<AccountScope, AppError>(notManaged(accountKey));
    }
    const wasHibernating: boolean = scope.lifecycle === 'hibernating';
    const transitioned: Result<AccountLifecycleState, AppError> = scope.activate();
    if (transitioned.ok === false) {
      return err<AccountScope, AppError>(transitioned.error);
    }
    if (wasHibernating) {
      const updated: AccountDescriptor = createDescriptor(
        accountKey,
        scope.accountId,
        scope.descriptor.createdAtMillis,
        true
      );
      const persisted: Result<void, AppError> = this.manifest.upsert(updated);
      if (persisted.ok === false) {
        // 运行时已激活，持久化失败不静默：透传 err 由调用方决定重试（README 语义）。
        return err<AccountScope, AppError>(persisted.error);
      }
      scope.replaceDescriptor(updated);
    }
    return ok<AccountScope, AppError>(scope);
  }

  /** 休眠账号：停 gateway 订阅、保留描述符与数据目录；enabled=false 持久化。 */
  hibernate(accountKey: string): Result<AccountScope, AppError> {
    const scope: AccountScope | undefined = this.scopes.get(accountKey);
    if (scope === undefined) {
      return err<AccountScope, AppError>(notManaged(accountKey));
    }
    const wasActive: boolean = scope.lifecycle === 'active';
    const transitioned: Result<AccountLifecycleState, AppError> = scope.hibernate();
    if (transitioned.ok === false) {
      return err<AccountScope, AppError>(transitioned.error);
    }
    if (wasActive) {
      const updated: AccountDescriptor = createDescriptor(
        accountKey,
        scope.accountId,
        scope.descriptor.createdAtMillis,
        false
      );
      const persisted: Result<void, AppError> = this.manifest.upsert(updated);
      if (persisted.ok === false) {
        return err<AccountScope, AppError>(persisted.error);
      }
      scope.replaceDescriptor(updated);
    }
    return ok<AccountScope, AppError>(scope);
  }

  /**
   * 关闭账号（终态，幂等）。取消全部 pending、停 gateway、从清单移除；
   * 清单移除失败时 scope 已关但保留在注册表中（可重试 close，不会丢号）。
   * closed scope 保留在 map 中直到被 create 替换——重复 close 返回既有 closed scope。
   */
  close(accountKey: string): Result<AccountScope, AppError> {
    const scope: AccountScope | undefined = this.scopes.get(accountKey);
    if (scope === undefined) {
      return err<AccountScope, AppError>(notManaged(accountKey));
    }
    const closed: Result<AccountLifecycleState, AppError> = scope.close();
    if (closed.ok === false) {
      return err<AccountScope, AppError>(closed.error);
    }
    if (scope.lifecycle !== 'closed') {
      return err<AccountScope, AppError>(
        AppErrors.internal('core_account.close_invariant', `scope not closed after close(): ${accountKey}`)
      );
    }
    const removed: Result<boolean, AppError> = this.manifest.remove(accountKey);
    if (removed.ok === false) {
      return err<AccountScope, AppError>(removed.error);
    }
    this.isolator.unregisterClient(scope.clientId);
    return ok<AccountScope, AppError>(scope);
  }

  get(accountKey: string): AccountScope | null {
    const scope: AccountScope | undefined = this.scopes.get(accountKey);
    return scope !== undefined ? scope : null;
  }

  /** 在管账号描述符清单（排除 closed，按插入序）。 */
  list(): AccountDescriptor[] {
    const out: AccountDescriptor[] = [];
    this.scopes.forEach((scope: AccountScope): void => {
      if (scope.lifecycle !== 'closed') {
        out.push(scope.descriptor);
      }
    });
    return out;
  }

  /**
   * 冷启动恢复（§6.1）：读持久化清单 → 逐账号恢复。
   * enabled → active scope；disabled → hibernating scope（恢复订阅前不启动 gateway）。
   * 单账号失败（清单项损坏/重复/建 client 失败）记入 failures，继续恢复其余账号；
   * 清单整体读取失败 → 单个 accountKey='*' 的失败项。
   */
  restoreAll(): AccountRestoreReport {
    const restored: AccountScope[] = [];
    const failures: AccountRestoreFailure[] = [];
    const loaded: Result<AccountDescriptor[], AppError> = this.manifest.load();
    if (loaded.ok === false) {
      const failure: AccountRestoreFailure = { accountKey: '*', error: loaded.error };
      failures.push(failure);
      return { restored: restored, failures: failures };
    }
    for (const descriptor of loaded.value) {
      const outcome: Result<AccountScope, AppError> = this.restoreOne(descriptor);
      if (outcome.ok === false) {
        const failure: AccountRestoreFailure = { accountKey: descriptor.accountKey, error: outcome.error };
        failures.push(failure);
      } else {
        restored.push(outcome.value);
      }
    }
    return { restored: restored, failures: failures };
  }

  getMetrics(): AccountRegistryMetrics {
    let active: number = 0;
    let hibernating: number = 0;
    let closed: number = 0;
    this.scopes.forEach((scope: AccountScope): void => {
      if (scope.lifecycle === 'active') {
        active += 1;
      } else if (scope.lifecycle === 'hibernating') {
        hibernating += 1;
      } else {
        closed += 1;
      }
    });
    const isolatorMetrics: AccountIsolatorMetrics = this.isolator.getMetrics();
    return {
      scopeCount: this.scopes.size,
      activeCount: active,
      hibernatingCount: hibernating,
      closedCount: closed,
      unknownClientIdEventCount: isolatorMetrics.unknownClientIdEventCount
    };
  }

  /** 恢复单账号：重复管理的非 closed key → err（隔离出账）；closed → 移除后重建。 */
  private restoreOne(descriptor: AccountDescriptor): Result<AccountScope, AppError> {
    const existing: AccountScope | undefined = this.scopes.get(descriptor.accountKey);
    if (existing !== undefined) {
      if (existing.lifecycle !== 'closed') {
        return err<AccountScope, AppError>(
          AppErrors.internal('core_account.already_managed', `account already managed: ${descriptor.accountKey}`)
        );
      }
      this.scopes.delete(descriptor.accountKey);
    }
    const dirs: Result<AccountDirectoryLayout, AppError> = buildAccountDirectories(descriptor.accountKey);
    if (dirs.ok === false) {
      return err<AccountScope, AppError>(dirs.error);
    }
    const opened: Result<AccountScope, AppError> = this.openScope(descriptor, dirs.value, descriptor.enabled);
    if (opened.ok === false) {
      return err<AccountScope, AppError>(opened.error);
    }
    const scope: AccountScope = opened.value;
    this.scopes.set(descriptor.accountKey, scope);
    return ok<AccountScope, AppError>(scope);
  }

  /** 打开 scope 的公共路径：隔离桥包装 + holder 共享 + 注册 clientId。 */
  private openScope(
    descriptor: AccountDescriptor,
    directories: AccountDirectoryLayout,
    startActive: boolean
  ): Result<AccountScope, AppError> {
    const holder: AccountClientIdHolder = { clientId: -1 };
    const isolatedBridge: TdNativeBridgeLike = this.isolator.wrapBridge(this.bridge, holder);
    const opened: Result<AccountScope, AppError> = AccountScope.open({
      bridge: isolatedBridge,
      files: this.files,
      descriptor: descriptor,
      directories: directories,
      gatewayOptions: this.gatewayOptions,
      startActive: startActive,
      clientIdHolder: holder
    });
    if (opened.ok === false) {
      return err<AccountScope, AppError>(opened.error);
    }
    this.isolator.registerClient(opened.value.clientId);
    return ok<AccountScope, AppError>(opened.value);
  }
}

function notManaged(accountKey: string): AppError {
  return AppErrors.parameter('missing', 'accountKey', `account not managed by this registry: ${accountKey}`);
}
