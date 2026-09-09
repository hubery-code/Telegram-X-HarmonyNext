/**
 * platform/network — ConnectivityKitSource：基于 HarmonyOS Network Kit 的 ConnectivitySource（PLAT-004）。
 *
 * 事件源：connection.createNetConnection() 注册 netAvailable / netLost / netCapabilitiesChange；
 * current()：getDefaultNetSync() + getNetCapabilitiesSync() 同步取默认网络能力。
 * 需要权限 ohos.permission.GET_NETWORK_INFO（已在 module.json5 声明）。
 *
 * 解绑说明：本 SDK（API 24/26）的 connection.NetConnection 只有 on/register/unregister，
 * 没有 off——unregister 会移除该连接上的全部监听。因此本类按「一个 source 实例服务一个
 * observe 订阅」设计（ConnectivityAdapter 默认构造即一一对应）；迟到的 Kit 事件由
 * active 闭包标记丢弃，保证注销后不再派发。
 *
 * 错误语义：
 * - current() 无失败路径（契约）：任一 Kit 调用抛错/无默认网络 → 断网快照；
 * - register() 同步抛错 → err(AppError platform)；异步注册失败回调 → 派发断网快照并自动解绑；
 * - unsubscribe 幂等：重复调用只生效一次。
 *
 * 注意：本文件是模块内唯一 import Kit 的文件；本地单测不加载/不实例化本类，
 * 纯逻辑由注入 Fake ConnectivitySource 的 ConnectivityAdapter 单测覆盖。
 */

import connection from '@ohos.net.connection';
import { Result, AppError, ok, err, AppErrors } from '@tgx/core-common';
import { NetworkSnapshot, Subscription } from '@tgx/platform-ports';
import { ConnectivitySource } from './ConnectivitySource';
import {
  RawNetCapabilities,
  DISCONNECTED_SNAPSHOT,
  mapCapabilities,
  NET_BEARER_WIFI,
  NET_BEARER_CELLULAR,
  NET_BEARER_BLUETOOTH,
  NET_BEARER_ETHERNET,
  NET_BEARER_VPN
} from './ConnectivityMapping';

/** Kit BusinessError 码（SDK d.ts）：连接服务失败。 */
const ERR_SERVICE_UNAVAILABLE: number = 2100002;

/** 订阅状态：active=false 后 Kit 迟到事件全部丢弃。 */
class KitListenState {
  active: boolean = true;
}

class ConnectivityKitSubscription implements Subscription {
  private readonly state: KitListenState;
  private readonly doUnregister: () => void;
  private closed: boolean = false;

  constructor(state: KitListenState, doUnregister: () => void) {
    this.state = state;
    this.doUnregister = doUnregister;
  }

  get isActive(): boolean {
    return this.state.active && !this.closed;
  }

  unsubscribe(): void {
    if (!this.state.active || this.closed) {
      return;
    }
    this.closed = true;
    this.state.active = false;
    this.doUnregister();
  }
}

export class ConnectivityKitSource implements ConnectivitySource {
  private readonly netConnection: connection.NetConnection;
  private unregisterStarted: boolean = false;

  constructor(netConnection?: connection.NetConnection) {
    this.netConnection = netConnection !== undefined ? netConnection : connection.createNetConnection();
  }

  current(): NetworkSnapshot {
    try {
      const handle: connection.NetHandle = connection.getDefaultNetSync();
      if (handle === undefined || handle === null || handle.netId === 0) {
        return DISCONNECTED_SNAPSHOT;
      }
      const caps: connection.NetCapabilities = connection.getNetCapabilitiesSync(handle);
      return mapCapabilities({
        bearerTypes: ConnectivityKitSource.toBearerNumbers(caps.bearerTypes),
        capabilities: ConnectivityKitSource.toCapabilityNumbers(caps.networkCap)
      });
    } catch (e) {
      return DISCONNECTED_SNAPSHOT;
    }
  }

  register(listener: (snapshot: NetworkSnapshot) => void): Result<Subscription, AppError> {
    try {
      const nc: connection.NetConnection = this.netConnection;
      const state: KitListenState = new KitListenState();
      const dispatch = (snapshot: NetworkSnapshot): void => {
        if (state.active) {
          listener(snapshot);
        }
      };
      const onAvailable = (handle: connection.NetHandle): void => {
        dispatch(this.snapshotForHandle(handle));
      };
      const onLost = (): void => {
        dispatch(DISCONNECTED_SNAPSHOT);
      };
      const onCapsChange = (info: connection.NetCapabilityInfo): void => {
        const caps: connection.NetCapabilities = info.netCap;
        dispatch(mapCapabilities({
          bearerTypes: ConnectivityKitSource.toBearerNumbers(caps.bearerTypes),
          capabilities: ConnectivityKitSource.toCapabilityNumbers(caps.networkCap)
        }));
      };
      nc.on('netAvailable', onAvailable);
      nc.on('netLost', onLost);
      nc.on('netCapabilitiesChange', onCapsChange);
      nc.register((regError: Error) => {
        if (regError !== undefined && regError !== null) {
          // 异步注册失败：派发断网快照并解绑，避免悬挂监听
          dispatch(DISCONNECTED_SNAPSHOT);
          state.active = false;
          this.unregisterQuietly(nc);
        }
      });
      return ok(new ConnectivityKitSubscription(state, () => {
        this.unregisterQuietly(nc);
      }));
    } catch (e) {
      return err(AppErrors.platform(ERR_SERVICE_UNAVAILABLE, 'connectivity observation not permitted', false));
    }
  }

  private snapshotForHandle(handle: connection.NetHandle): NetworkSnapshot {
    try {
      if (handle === undefined || handle === null || handle.netId === 0) {
        return DISCONNECTED_SNAPSHOT;
      }
      const caps: connection.NetCapabilities = connection.getNetCapabilitiesSync(handle);
      return mapCapabilities({
        bearerTypes: ConnectivityKitSource.toBearerNumbers(caps.bearerTypes),
        capabilities: ConnectivityKitSource.toCapabilityNumbers(caps.networkCap)
      });
    } catch (e) {
      return DISCONNECTED_SNAPSHOT;
    }
  }

  /** unregister 幂等；本 SDK 无 off，unregister 移除该连接全部监听（单订阅设计见文件头）。 */
  private unregisterQuietly(nc: connection.NetConnection): void {
    if (this.unregisterStarted) {
      return;
    }
    this.unregisterStarted = true;
    try {
      nc.unregister(() => {
      });
    } catch (e) {
      // 解绑失败静默：迟到事件由 KitListenState.active=false 丢弃
    }
  }

  /** NetBearType 枚举 → 本模块映射表使用的数值（集中转换，映射表本身 Kit-free）。 */
  private static toBearerNumbers(bearerTypes: connection.NetBearType[]): number[] {
    const out: number[] = [];
    for (const b of bearerTypes) {
      if (b === connection.NetBearType.BEARER_WIFI) {
        out.push(NET_BEARER_WIFI);
      } else if (b === connection.NetBearType.BEARER_CELLULAR) {
        out.push(NET_BEARER_CELLULAR);
      } else if (b === connection.NetBearType.BEARER_BLUETOOTH) {
        out.push(NET_BEARER_BLUETOOTH);
      } else if (b === connection.NetBearType.BEARER_ETHERNET) {
        out.push(NET_BEARER_ETHERNET);
      } else if (b === connection.NetBearType.BEARER_VPN) {
        out.push(NET_BEARER_VPN);
      } else {
        out.push(-1);
      }
    }
    return out;
  }

  /** NetCap 枚举 → 数值数组。 */
  private static toCapabilityNumbers(caps: connection.NetCap[] | undefined): number[] {
    const out: number[] = [];
    if (caps === undefined || caps === null) {
      return out;
    }
    for (const c of caps) {
      out.push(c);
    }
    return out;
  }
}
