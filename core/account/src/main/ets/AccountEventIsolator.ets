/**
 * core/account — AccountEventIsolator：跨账号事件隔离（CORE-003）。
 *
 * 计划 §5.5「不得使用承载所有账户的可变全局单例」+ 事件不互串的落实点：
 * - registry 为每个 AccountScope 的 TdGateway 包一层 ScopeIsolatingBridge，
 *   桥事件先按 clientId 过滤再进该账号的 gateway——其他账号的事件在桥边界
 *   就被丢弃，根本到不了本账号的 OrderedEventRouter/RequestRegistry；
 * - registry 自己持有一条 monitor 订阅（registry.start() 建立）负责未知
 *   clientId 记账：事件属于未注册 client → unknownClientIdEventCount++ 并
 *   经 onUnknownClientId 上报 AppError(internal/core_account.unknown_client_id)
 *   （计划 §7：不静默吞协议异常）。已知 client 的事件由对应 scope 的
 *   wrapper 处理，monitor 不计数、不拦截。
 *
 * 线程：全部在 ArkTS 线程同步执行（与 CORE-002 相同前提）。
 */

import { AppError, AppErrors } from '@tgx/core-common';
import {
  TdNativeBridgeLike,
  TdNativeBridgeMetrics,
  TdNativeEvent,
  TdNativeEventSink
} from '@tgx/td-gateway';

export const UNKNOWN_CLIENT_ID_ORIGIN: string = 'core_account.unknown_client_id';

/** 可变 clientId 引用：scope.open() 内 createClient 后回填，桥 wrapper 经它做过滤。 */
export interface AccountClientIdHolder {
  clientId: number;
}

export interface AccountIsolatorMetrics {
  /** 属于未注册 clientId 的事件数（已上报 AppError internal）。 */
  readonly unknownClientIdEventCount: number;
}

/** 只放行单个 client 事件的桥装饰器；其余方法原样委托内层桥。 */
class ScopeIsolatingBridge implements TdNativeBridgeLike {
  private readonly inner: TdNativeBridgeLike;
  private readonly holder: AccountClientIdHolder;

  constructor(inner: TdNativeBridgeLike, holder: AccountClientIdHolder) {
    this.inner = inner;
    this.holder = holder;
  }

  getVersion(): string {
    return this.inner.getVersion();
  }

  createClient(): number {
    return this.inner.createClient();
  }

  send(clientId: number, requestUtf8: string): void {
    this.inner.send(clientId, requestUtf8);
  }

  execute(requestUtf8: string): string | null {
    return this.inner.execute(requestUtf8);
  }

  subscribeUpdates(sink: TdNativeEventSink): number {
    const self: ScopeIsolatingBridge = this;
    return this.inner.subscribeUpdates((event: TdNativeEvent): void => {
      if (event.clientId === self.holder.clientId) {
        sink(event);
      }
      // 非本账号事件在此静默丢弃（另一账号的 wrapper 会放行它；未知 client 由 registry monitor 记账）。
    });
  }

  unsubscribe(subscriptionId: number): void {
    this.inner.unsubscribe(subscriptionId);
  }

  getMetrics(): TdNativeBridgeMetrics {
    return this.inner.getMetrics();
  }
}

export class AccountEventIsolator {
  private readonly onUnknownClientId: (error: AppError, clientId: number) => void;
  private readonly knownClientIds: Set<number> = new Set();
  private unknownClientIdEventCount: number = 0;

  constructor(onUnknownClientId?: (error: AppError, clientId: number) => void) {
    this.onUnknownClientId = onUnknownClientId !== undefined ? onUnknownClientId : (): void => {
    };
  }

  registerClient(clientId: number): void {
    this.knownClientIds.add(clientId);
  }

  unregisterClient(clientId: number): void {
    this.knownClientIds.delete(clientId);
  }

  isKnown(clientId: number): boolean {
    return this.knownClientIds.has(clientId);
  }

  /** 为某个 scope 包隔离桥：holder.clientId 在 createClient 后回填。 */
  wrapBridge(inner: TdNativeBridgeLike, holder: AccountClientIdHolder): TdNativeBridgeLike {
    return new ScopeIsolatingBridge(inner, holder);
  }

  /**
   * 生成 monitor 事件处理（registry 直接订阅内层桥时使用）。
   * 只对未知 clientId 记账并上报；已知 client 的事件原样忽略（由对应 scope 处理）。
   */
  createMonitorSink(): TdNativeEventSink {
    const self: AccountEventIsolator = this;
    return (event: TdNativeEvent): void => {
      if (self.knownClientIds.has(event.clientId)) {
        return;
      }
      self.unknownClientIdEventCount += 1;
      self.onUnknownClientId(
        AppErrors.internal(
          UNKNOWN_CLIENT_ID_ORIGIN,
          `event for unknown clientId: ${event.clientId}`,
          `sequence=${event.sequence}`
        ),
        event.clientId
      );
    };
  }

  getMetrics(): AccountIsolatorMetrics {
    return { unknownClientIdEventCount: this.unknownClientIdEventCount };
  }
}
