/**
 * entry/lifecycle — LifecycleCoordinator：应用生命周期协调器（LIFE-001，计划 §9.5）。
 *
 * 职责：
 * 1. 冷启动与杀进程恢复：优先调用 AccountRegistry.restoreAll() 从持久化清单恢复账号；
 *    若无账号则创建默认账号 'default'；确定 primaryScope。
 * 2. 前后台协调：
 *    - onForeground：标记前台，确保活跃账号激活，查询网络快照并向 TDLib 发送 setNetworkType；
 *    - onBackground：标记后台，记录时间戳，刷盘/持久化；
 * 3. 动态网络状态协调：订阅 NetworkStatePort.observe，网络切换（WiFi/蜂窝/断网）时广播 setNetworkType；
 * 4. 销毁生命周期：onDestroy 退订网络、幂等关闭 scope、停止 registry 监控。
 */

import { Clock, SystemClock } from '@tgx/core-common';
import {
  AccountRegistry,
  AccountRestoreFailure,
  AccountRestoreReport,
  AccountScope,
  AccountDescriptor
} from '@tgx/core-account';
import { NetworkStatePort, NetworkSnapshot, Subscription } from '@tgx/platform-ports';
import { TdWireObject } from '@tgx/td-gateway';
import {
  NetworkTypeMobile,
  NetworkTypeNone,
  NetworkTypeOther,
  NetworkTypeWiFi,
  SetNetworkType,
  TdNetworkType,
  encodeSetNetworkType
} from '@tgx/core-td-api-generated';

export interface LifecycleBootstrapReport {
  readonly primaryScope: AccountScope;
  readonly scopes: AccountScope[];
  readonly failures: AccountRestoreFailure[];
  readonly isForeground: boolean;
  readonly currentNetwork: NetworkSnapshot;
}

export interface LifecycleCoordinatorOptions {
  readonly registry: AccountRegistry;
  readonly network: NetworkStatePort;
  readonly clock?: Clock;
  readonly onForegroundChanged?: (isForeground: boolean) => void;
  readonly onNetworkChanged?: (snapshot: NetworkSnapshot) => void;
  readonly logger?: (message: string) => void;
}

export function mapSnapshotToNetworkType(snapshot: NetworkSnapshot): TdNetworkType {
  if (!snapshot.connected) {
    return new NetworkTypeNone();
  }
  if (snapshot.transport === 'wifi') {
    return new NetworkTypeWiFi();
  }
  if (snapshot.transport === 'cellular') {
    return new NetworkTypeMobile();
  }
  return new NetworkTypeOther();
}

export class LifecycleCoordinator {
  private readonly registry: AccountRegistry;
  private readonly network: NetworkStatePort;
  private readonly clock: Clock;
  private readonly options: LifecycleCoordinatorOptions;

  private isForegroundValue: boolean = false;
  private isDestroyedValue: boolean = false;
  private isStartedValue: boolean = false;
  private lastForegroundTimestamp: number = 0;
  private lastBackgroundTimestamp: number = 0;

  private networkSubscription: Subscription | null = null;
  private primaryScope: AccountScope | null = null;

  constructor(options: LifecycleCoordinatorOptions) {
    this.options = options;
    this.registry = options.registry;
    this.network = options.network;
    this.clock = options.clock !== undefined ? options.clock : new SystemClock();
  }

  get isForeground(): boolean {
    return this.isForegroundValue;
  }

  get isDestroyed(): boolean {
    return this.isDestroyedValue;
  }

  get isStarted(): boolean {
    return this.isStartedValue;
  }

  get lastForegroundTime(): number {
    return this.lastForegroundTimestamp;
  }

  get lastBackgroundTime(): number {
    return this.lastBackgroundTimestamp;
  }

  get primaryAccountScope(): AccountScope | null {
    return this.primaryScope;
  }

  /**
   * 启动协调器（冷启动装配入口）。
   * 优先执行 restoreAll() 恢复历史账号，若为空则创建 default 账号；
   * 建立网络监听并派发初始网络类型。
   */
  start(): LifecycleBootstrapReport {
    if (this.isStartedValue) {
      throw new Error('LifecycleCoordinator: already started');
    }
    this.isStartedValue = true;
    this.isForegroundValue = true;
    this.lastForegroundTimestamp = this.clock.nowMillis();

    this.log('start: restoring accounts...');
    const report: AccountRestoreReport = this.registry.restoreAll();
    let primary: AccountScope | null = null;

    for (let i: number = 0; i < report.restored.length; i++) {
      const s: AccountScope = report.restored[i];
      if (s.lifecycle === 'active') {
        primary = s;
        break;
      }
    }

    if (primary === null && report.restored.length > 0) {
      const first: AccountScope = report.restored[0];
      const activated = this.registry.activate(first.accountKey);
      if (activated.ok) {
        primary = activated.value;
      } else {
        primary = first;
      }
    }

    if (primary === null) {
      this.log('start: no restored accounts, creating default account');
      const created = this.registry.create('default');
      if (created.ok) {
        primary = created.value;
      }
      if (created.err) {
        throw new Error(`LifecycleCoordinator: failed to create default scope: ${created.error.kind}`);
      }
    }
    if (primary === null) {
      throw new Error('LifecycleCoordinator: primaryScope could not be resolved');
    }
    this.primaryScope = primary;

    const currentNetwork: NetworkSnapshot = this.network.current();
    this.log(`start: primary scope accountKey=${primary.accountKey}, initial network connected=${currentNetwork.connected}`);

    const self: LifecycleCoordinator = this;
    const observeResult = this.network.observe((snapshot: NetworkSnapshot): void => {
      self.handleNetworkChanged(snapshot);
    });
    if (observeResult.err) {
      this.log(`start: failed to observe network state: ${observeResult.error.kind}`);
    }
    if (observeResult.ok) {
      this.networkSubscription = observeResult.value;
    }

    const netType: TdNetworkType = mapSnapshotToNetworkType(currentNetwork);
    this.broadcastNetworkType(netType);

    const activeScopes: AccountScope[] = [];
    const descriptors: AccountDescriptor[] = this.registry.list();
    for (let i: number = 0; i < descriptors.length; i++) {
      const s: AccountScope | null = this.registry.get(descriptors[i].accountKey);
      if (s !== null) {
        activeScopes.push(s);
      }
    }

    const resultReport: LifecycleBootstrapReport = {
      primaryScope: primary,
      scopes: activeScopes,
      failures: report.failures,
      isForeground: this.isForegroundValue,
      currentNetwork: currentNetwork
    };
    return resultReport;
  }

  /**
   * 应用回到前台：
   * 1. 状态翻转 isForeground = true；
   * 2. 确保所有 active 账号处于激活态；
   * 3. 广播当前网络快照到 TDLib（调用 setNetworkType 促使 socket 快速恢复）。
   */
  onForeground(): void {
    if (this.isDestroyedValue) {
      return;
    }
    if (this.isForegroundValue) {
      return;
    }
    this.isForegroundValue = true;
    this.lastForegroundTimestamp = this.clock.nowMillis();
    this.log('onForeground: app entered foreground');

    if (this.options.onForegroundChanged !== undefined) {
      this.options.onForegroundChanged(true);
    }

    const descriptors: AccountDescriptor[] = this.registry.list();
    for (let i: number = 0; i < descriptors.length; i++) {
      const scope: AccountScope | null = this.registry.get(descriptors[i].accountKey);
      if (scope !== null && scope.lifecycle === 'active') {
        scope.activate();
      }
    }

    const currentNetwork: NetworkSnapshot = this.network.current();
    const netType: TdNetworkType = mapSnapshotToNetworkType(currentNetwork);
    this.broadcastNetworkType(netType);
  }

  /**
   * 应用切入后台：
   * 1. 状态翻转 isForeground = false；
   * 2. 记录进入后台时间戳；
   * 3. 通知后台回调。
   */
  onBackground(): void {
    if (this.isDestroyedValue) {
      return;
    }
    if (!this.isForegroundValue) {
      return;
    }
    this.isForegroundValue = false;
    this.lastBackgroundTimestamp = this.clock.nowMillis();
    this.log('onBackground: app entered background');

    if (this.options.onForegroundChanged !== undefined) {
      this.options.onForegroundChanged(false);
    }
  }

  /**
   * 应用销毁：
   * 1. 退订网络状态变化；
   * 2. 关闭所有在管 scope 连接；
   * 3. 停止 registry 监控。
   */
  onDestroy(): void {
    if (this.isDestroyedValue) {
      return;
    }
    this.isDestroyedValue = true;
    this.isForegroundValue = false;
    this.log('onDestroy: tearing down lifecycle coordinator');

    if (this.networkSubscription !== null) {
      this.networkSubscription.unsubscribe();
      this.networkSubscription = null;
    }

    const descriptors: AccountDescriptor[] = this.registry.list();
    for (let i: number = 0; i < descriptors.length; i++) {
      this.registry.close(descriptors[i].accountKey);
    }
    this.registry.stop();
  }

  /**
   * 响应网络变化：向所有处于 active 状态的账号发送 setNetworkType。
   */
  private handleNetworkChanged(snapshot: NetworkSnapshot): void {
    if (this.isDestroyedValue) {
      return;
    }
    this.log(`handleNetworkChanged: connected=${snapshot.connected}, transport=${snapshot.transport}`);
    if (this.options.onNetworkChanged !== undefined) {
      this.options.onNetworkChanged(snapshot);
    }
    const netType: TdNetworkType = mapSnapshotToNetworkType(snapshot);
    this.broadcastNetworkType(netType);
  }

  /**
   * 广播 setNetworkType 给所有 active 的 AccountScope。
   */
  private broadcastNetworkType(netType: TdNetworkType): void {
    const req: SetNetworkType = new SetNetworkType();
    req.type_ = netType;
    const wireObject: TdWireObject = encodeSetNetworkType(req) as TdWireObject;

    const descriptors: AccountDescriptor[] = this.registry.list();
    for (let i: number = 0; i < descriptors.length; i++) {
      const scope: AccountScope | null = this.registry.get(descriptors[i].accountKey);
      if (scope !== null && scope.lifecycle === 'active') {
        scope.request('setNetworkType', wireObject);
      }
    }
  }

  private log(message: string): void {
    if (this.options.logger !== undefined) {
      this.options.logger(message);
    }
  }
}
