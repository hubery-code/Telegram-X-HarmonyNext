/**
 * platform/network — ConnectivityAdapter：NetworkStatePort 生产 adapter（PLAT-004）。
 *
 * 结构：本类是 Kit-free 引擎（纯逻辑，可注入 ConnectivitySource 单测）；
 * Kit 事件源实现见 ConnectivityKitSource。
 *
 * 契约语义（platform/ports NetworkStatePort）落实：
 * - observe() 注册成功后立即派发一次当前快照（经去重器，防与紧随的底层事件重复）；
 * - 底层事件经 SnapshotDeduper 连续同值去重后派发；
 * - source.register 失败（权限缺失等）原样向上返回 err；
 * - current() 无失败路径：source 抛异常时返回断网语义快照；
 * - 注销句柄由 source 提供，幂等性由 source 保证（Kit 实现见 ConnectivityKitSource）。
 */

import { Result, AppError, ok } from '@tgx/core-common';
import { NetworkSnapshot, NetworkStatePort, Subscription } from '@tgx/platform-ports';
import { ConnectivitySource } from './ConnectivitySource';
import { SnapshotDeduper, DISCONNECTED_SNAPSHOT } from './ConnectivityMapping';
import { ConnectivityKitSource } from './ConnectivityKitSource';

export class ConnectivityAdapter implements NetworkStatePort {
  private readonly source: ConnectivitySource;

  /** 生产用法 new ConnectivityAdapter()；测试注入 Fake ConnectivitySource。 */
  constructor(source?: ConnectivitySource) {
    this.source = source !== undefined ? source : new ConnectivityKitSource();
  }

  current(): NetworkSnapshot {
    try {
      return this.source.current();
    } catch (e) {
      return DISCONNECTED_SNAPSHOT;
    }
  }

  observe(listener: (snapshot: NetworkSnapshot) => void): Result<Subscription, AppError> {
    const deduper: SnapshotDeduper = new SnapshotDeduper();
    const subscribed: Result<Subscription, AppError> = this.source.register(
      (snapshot: NetworkSnapshot) => {
        const emitted: NetworkSnapshot | null = deduper.next(snapshot);
        if (emitted !== null) {
          listener(emitted);
        }
      }
    );
    if (!subscribed.ok) {
      return subscribed;
    }
    const initial: NetworkSnapshot | null = deduper.next(this.current());
    if (initial !== null) {
      listener(initial);
    }
    return ok(subscribed.value);
  }
}
