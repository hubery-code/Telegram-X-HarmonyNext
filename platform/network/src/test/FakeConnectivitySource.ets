/**
 * platform/network 测试 — FakeConnectivitySource：可驱动假事件源（PLAT-004）。
 *
 * - pushRaw 不做去重（故意模拟 Kit 天然重复上报），去重是 ConnectivityAdapter 的责任；
 * - setRegisterEnabled(false) 模拟注册失败（权限缺失等）；
 * - unsubscribe 幂等，注销后不再派发。
 */

import { Result, AppError, ok, err, AppErrors } from '@tgx/core-common';
import { NetworkSnapshot, Subscription } from '@tgx/platform-ports';
import { ConnectivitySource } from '../main/ets/ConnectivitySource';
import { DISCONNECTED_SNAPSHOT } from '../main/ets/ConnectivityMapping';

class FakeSubscription implements Subscription {
  private active: boolean = true;
  private readonly off: () => void;

  constructor(off: () => void) {
    this.off = off;
  }

  get isActive(): boolean {
    return this.active;
  }

  unsubscribe(): void {
    if (!this.active) {
      return;
    }
    this.active = false;
    this.off();
  }
}

export class FakeConnectivitySource implements ConnectivitySource {
  private snapshot: NetworkSnapshot = DISCONNECTED_SNAPSHOT;
  private listeners: ((snapshot: NetworkSnapshot) => void)[] = [];
  private registerEnabled: boolean = true;

  setSnapshot(snapshot: NetworkSnapshot): void {
    this.snapshot = snapshot;
  }

  /** 驱动：模拟底层网络变化（原始派发，故意不去重）。 */
  pushRaw(snapshot: NetworkSnapshot): void {
    this.snapshot = snapshot;
    const targets: ((snapshot: NetworkSnapshot) => void)[] = this.listeners.slice();
    for (const listener of targets) {
      listener(snapshot);
    }
  }

  setRegisterEnabled(enabled: boolean): void {
    this.registerEnabled = enabled;
  }

  current(): NetworkSnapshot {
    return this.snapshot;
  }

  register(listener: (snapshot: NetworkSnapshot) => void): Result<Subscription, AppError> {
    if (!this.registerEnabled) {
      return err(AppErrors.platform(2100002, 'connectivity observation not permitted', false));
    }
    this.listeners.push(listener);
    return ok(new FakeSubscription(() => {
      const index: number = this.listeners.indexOf(listener);
      if (index >= 0) {
        this.listeners.splice(index, 1);
      }
    }));
  }
}
