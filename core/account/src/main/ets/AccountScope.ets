/**
 * core/account — AccountScope：单个账号的作用域（CORE-003，计划 §5.5）。
 *
 * 组成（与 §5.5 清单对齐）：
 * - accountId（稳定字符串，可注入生成器）/ accountKey（业务键）/ clientId（进程内）；
 * - 独占的 TdGateway 实例（经隔离桥创建，只接收本账号 clientId 的事件）；
 * - 生命周期状态（active/hibernating/closed，纯 reducer AccountLifecycle.ets）；
 * - AccountCancellation：该账号全部 pending request 的取消域；
 * - AccountDirectoryLayout：账号目录描述（只描述不触碰文件系统，读写全经 AppFilesPort）；
 * - AuthorizationStateHolder：授权状态机挂载点（转换 reducer 是 CORE-005）。
 *
 * 线程契约：与 CORE-002 相同——所有方法在 ArkTS 线程调用，事件全同步、无重入。
 *
 * 生命周期语义：
 * - open(startActive=true)（新建/恢复已启用账号）：createClient → 订阅内部事件 → gateway.start()；
 * - hibernate()：退订 bridge 事件流（gateway.stop()），描述符与数据目录保留，
 *   可 activate() 恢复；内部路由订阅保留，非 active 直达事件由守卫丢弃并计数；
 * - close()：取消域 cancelAll() + gateway.stop()，终态。closed 守卫把迟到事件
 *   丢弃并计数（响应侧由 CORE-002 tombstone 保证不二次 resolve）；close() 幂等。
 */

import { AppError, AppErrors, Result, err, ok } from '@tgx/core-common';
import {
  TdGateway,
  TdGatewayMetrics,
  TdGatewayOptions,
  TdNativeBridgeLike,
  TdPendingRequest,
  TdRequestOptions,
  TdRoutedEvent,
  TdUpdateSubscription,
  TdWireObject
} from '@tgx/td-gateway';
import { AppFilesPort } from '@tgx/platform-ports';
import {
  AccountLifecycleState,
  reduceAccountLifecycle
} from './AccountLifecycle';
import { AccountCancellation } from './AccountCancellation';
import { AccountDirectoryLayout } from './AccountDirectories';
import { AccountDescriptor } from './AccountDescriptor';
import { AccountClientIdHolder } from './AccountEventIsolator';
import { AuthorizationState, AuthorizationStateHolder } from './AuthorizationState';

export const SCOPE_CLOSED_ORIGIN: string = 'core_account.scope_closed';

export type AccountEventListener = (event: TdRoutedEvent) => void;

export interface AccountScopeOpenDeps {
  /** 已按本 scope 隔离的桥（AccountEventIsolator.wrapBridge 产物）或裸桥（单账号测试）。 */
  readonly bridge: TdNativeBridgeLike;
  readonly files: AppFilesPort;
  readonly descriptor: AccountDescriptor;
  readonly directories: AccountDirectoryLayout;
  readonly gatewayOptions?: TdGatewayOptions;
  /** true = 以 active 打开并启动 gateway；false = 以 hibernating 打开（恢复休眠账号）。 */
  readonly startActive: boolean;
  /** registry 共享的 clientId 回填位；缺省 scope 自建。 */
  readonly clientIdHolder?: AccountClientIdHolder;
}

export class AccountScope {
  private accountDescriptor: AccountDescriptor;
  private readonly directoryLayout: AccountDirectoryLayout;
  private readonly files: AppFilesPort;
  private readonly gateway: TdGateway;
  private readonly cancellation: AccountCancellation;
  private readonly authHolder: AuthorizationStateHolder;
  private readonly clientIdHolder: AccountClientIdHolder;

  private lifecycleState: AccountLifecycleState;
  private eventSubscription: TdUpdateSubscription | null = null;
  private eventListener: AccountEventListener | null = null;
  private droppedEventCountValue: number = 0;

  private constructor(deps: AccountScopeOpenDeps) {
    this.accountDescriptor = deps.descriptor;
    this.directoryLayout = deps.directories;
    this.files = deps.files;
    this.cancellation = new AccountCancellation();
    this.authHolder = new AuthorizationStateHolder();
    this.clientIdHolder = deps.clientIdHolder !== undefined ? deps.clientIdHolder : { clientId: -1 };
    this.gateway = new TdGateway(deps.bridge, deps.gatewayOptions);
    this.clientIdHolder.clientId = this.gateway.createClient();
    this.lifecycleState = deps.startActive ? 'active' : 'hibernating';
    if (deps.startActive) {
      this.startGatewayLocked();
    }
  }

  /**
   * 打开 scope。bridge.createClient 同步抛异常 → err(platform)（映射为可上报错误，
   * 不向调用方抛）；其余失败路径由调用方（AccountRegistry）编排回滚。
   */
  static open(deps: AccountScopeOpenDeps): Result<AccountScope, AppError> {
    let scope: AccountScope;
    try {
      scope = new AccountScope(deps);
    } catch (e) {
      const message: string = e instanceof Error ? e.message : String(e);
      return err<AccountScope, AppError>(
        AppErrors.platform(-1, 'failed to create TDLib client for account', true, undefined, message)
      );
    }
    return ok<AccountScope, AppError>(scope);
  }

  get accountKey(): string {
    return this.accountDescriptor.accountKey;
  }

  get accountId(): string {
    return this.accountDescriptor.accountId;
  }

  get clientId(): number {
    return this.clientIdHolder.clientId;
  }

  get descriptor(): AccountDescriptor {
    return this.accountDescriptor;
  }

  /** registry 专用：持久化描述符变更（enabled 翻转）成功后同步 scope 内副本。 */
  replaceDescriptor(next: AccountDescriptor): void {
    this.accountDescriptor = next;
  }

  get directories(): AccountDirectoryLayout {
    return this.directoryLayout;
  }

  get gatewayInstance(): TdGateway {
    return this.gateway;
  }

  get lifecycle(): AccountLifecycleState {
    return this.lifecycleState;
  }

  /** 授权状态（占位，转换 reducer 归 CORE-005）。UI 只读。 */
  get authorization(): AuthorizationState {
    return this.authHolder.current;
  }

  /** CORE-005 的 auth reducer 经此提交新状态。 */
  get authorizationHolder(): AuthorizationStateHolder {
    return this.authHolder;
  }

  get pendingRequestCount(): number {
    return this.cancellation.pendingCount;
  }

  /** 非 active 状态（closed 迟到 / hibernating 直达）被守卫丢弃的事件数。 */
  get droppedEventCount(): number {
    return this.droppedEventCountValue;
  }

  /** 激活：reducer 转换成立时重启 gateway 订阅并恢复事件派发。幂等。 */
  activate(): Result<AccountLifecycleState, AppError> {
    const reduced: Result<AccountLifecycleState, AppError> = reduceAccountLifecycle(this.lifecycleState, 'activate');
    if (reduced.ok === false) {
      return err<AccountLifecycleState, AppError>(reduced.error);
    }
    if (reduced.value !== this.lifecycleState) {
      this.lifecycleState = reduced.value;
      this.startGatewayLocked();
    }
    return ok<AccountLifecycleState, AppError>(this.lifecycleState);
  }

  /** 休眠：停 gateway 订阅、停事件派发；描述符与目录保留，可恢复。幂等。 */
  hibernate(): Result<AccountLifecycleState, AppError> {
    const reduced: Result<AccountLifecycleState, AppError> = reduceAccountLifecycle(this.lifecycleState, 'hibernate');
    if (reduced.ok === false) {
      return err<AccountLifecycleState, AppError>(reduced.error);
    }
    if (reduced.value !== this.lifecycleState) {
      this.lifecycleState = reduced.value;
      this.stopGatewayLocked();
    }
    return ok<AccountLifecycleState, AppError>(this.lifecycleState);
  }

  /**
   * 关闭（终态）：取消全部 pending request（迟到响应由 CORE-002 tombstone 安全丢弃）、
   * 停 gateway。事件订阅保留，closed 守卫丢弃并计数迟到事件。幂等。
   */
  close(): Result<AccountLifecycleState, AppError> {
    const reduced: Result<AccountLifecycleState, AppError> = reduceAccountLifecycle(this.lifecycleState, 'close');
    if (reduced.ok === false) {
      return err<AccountLifecycleState, AppError>(reduced.error);
    }
    if (this.lifecycleState !== 'closed') {
      this.lifecycleState = 'closed';
      this.cancellation.cancelAll();
      this.gateway.stop();
    }
    return ok<AccountLifecycleState, AppError>(this.lifecycleState);
  }

  /**
   * 账号内发请求：登记进取消域后透传 gateway（注入 @extra.requestId 等语义见 CORE-002）。
   * closed scope 返回 err(unknown/core_account.scope_closed)，绝不向已关闭账号发请求。
   */
  request(method: string, params?: TdWireObject, options?: TdRequestOptions): Result<TdPendingRequest, AppError> {
    if (this.lifecycleState === 'closed') {
      return err<TdPendingRequest, AppError>(
        AppErrors.unknown(SCOPE_CLOSED_ORIGIN, 'account scope is closed', `accountKey=${this.accountKey}`)
      );
    }
    const pending: TdPendingRequest = this.gateway.request(this.clientId, method, params, options);
    this.cancellation.track(pending);
    return ok<TdPendingRequest, AppError>(pending);
  }

  /** 订阅账号事件（CORE-005 的 auth reducer / AUTH-001 UI 接入点）。后注册替换先注册。 */
  subscribeEvents(listener: AccountEventListener): void {
    this.eventListener = listener;
  }

  unsubscribeEvents(): void {
    this.eventListener = null;
  }

  /** 解析账号目录内相对路径（经 AppFilesPort，不访问文件系统）。 */
  resolveAccountPath(relativePath: string): Result<string, AppError> {
    return this.files.resolve(this.directoryLayout.accountDir, relativePath);
  }

  getMetrics(): AccountScopeMetrics {
    return {
      lifecycle: this.lifecycleState,
      pendingRequests: this.cancellation.pendingCount,
      droppedEvents: this.droppedEventCount,
      gateway: this.gateway.getMetrics()
    };
  }

  private startGatewayLocked(): void {
    this.subscribeInternalEvents();
    this.gateway.start();
  }

  private stopGatewayLocked(): void {
    this.gateway.stop();
  }

  private subscribeInternalEvents(): void {
    if (this.eventSubscription !== null && this.eventSubscription.isActive) {
      return;
    }
    const self: AccountScope = this;
    this.eventSubscription = this.gateway.subscribeUpdates(
      { clientId: self.clientId },
      (event: TdRoutedEvent): void => {
        self.dispatchEvent(event);
      }
    );
  }

  /**
   * 事件守卫：非 active 状态（closed 迟到 / hibernating 直达）一律丢弃并计数，
   * 绝不向监听泄漏。内部路由订阅自建立后终身保留——bridge 订阅已随
   * hibernate/close 停止，能到达这里的事件只可能是已在途/直达的迟到事件。
   */
  private dispatchEvent(event: TdRoutedEvent): void {
    if (this.lifecycleState !== 'active') {
      this.droppedEventCountValue += 1;
      return;
    }
    if (this.eventListener !== null) {
      this.eventListener(event);
    }
  }
}

export interface AccountScopeMetrics {
  readonly lifecycle: AccountLifecycleState;
  readonly pendingRequests: number;
  readonly droppedEvents: number;
  readonly gateway: TdGatewayMetrics;
}
