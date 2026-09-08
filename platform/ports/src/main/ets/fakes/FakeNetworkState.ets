/**
 * platform/ports — FakeNetworkState（PLAT-001）。
 *
 * NetworkStatePort 的可驱动 Fake：
 * - observe() 注册后立即派发当前快照（初始值语义）；
 * - push() 模拟底层网络变化：与上一快照全字段相等时去重不派发；
 * - 派发串行、按注册顺序；unsubscribe 后不再收到事件；
 * - setObserveEnabled(false) 模拟注册失败路径（如权限缺失）。
 */

import { Result, AppError, ok, err, AppErrors } from '@tgx/core-common';
import { Subscription } from '../Common';
import { NetworkSnapshot, NetworkStatePort } from '../NetworkStatePort';

class FakeNetworkSubscription implements Subscription {
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

export class FakeNetworkState implements NetworkStatePort {
  private snapshot: NetworkSnapshot = { connected: false, transport: null, metered: false };
  private listeners: ((snapshot: NetworkSnapshot) => void)[] = [];
  private observeEnabled: boolean = true;

  constructor(initial?: NetworkSnapshot) {
    if (initial !== undefined) {
      this.snapshot = initial;
    }
  }

  /** 测试驱动：模拟网络变化（同值快照自动去重）。 */
  push(snapshot: NetworkSnapshot): void {
    if (this.sameSnapshot(snapshot, this.snapshot)) {
      return;
    }
    this.snapshot = snapshot;
    const targets: ((snapshot: NetworkSnapshot) => void)[] = this.listeners.slice();
    for (const listener of targets) {
      listener(snapshot);
    }
  }

  /** 测试驱动：模拟 observe 注册失败（权限缺失等）。 */
  setObserveEnabled(enabled: boolean): void {
    this.observeEnabled = enabled;
  }

  current(): NetworkSnapshot {
    return this.snapshot;
  }

  observe(listener: (snapshot: NetworkSnapshot) => void): Result<Subscription, AppError> {
    if (!this.observeEnabled) {
      return err(AppErrors.platform(48151624, 'network state observation not permitted', false));
    }
    this.listeners.push(listener);
    listener(this.snapshot);
    return ok(new FakeNetworkSubscription(() => {
      const index: number = this.listeners.indexOf(listener);
      if (index >= 0) {
        this.listeners.splice(index, 1);
      }
    }));
  }

  private sameSnapshot(a: NetworkSnapshot, b: NetworkSnapshot): boolean {
    return a.connected === b.connected && a.transport === b.transport && a.metered === b.metered;
  }
}
