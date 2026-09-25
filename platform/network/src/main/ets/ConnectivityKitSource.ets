/**
 * platform/network — ConnectivityKitSource：基于 HarmonyOS Network Kit 的 ConnectivitySource（PLAT-004）。
 *
 * 事件源：connection.createNetConnection() 注册 netAvailable / netLost / netCapabilitiesChange；
 * current()：getDefaultNetSync() + getNetCapabilitiesSync() 同步取默认网络能力。
 * 需要权限 ohos.permission.GET_NETWORK_INFO（已在 module.json5 声明）。
 *
 * 漫游（AUTODL-102）：本 SDK 的 NetCap 枚举里没有 Android 那个 NOT_ROAMING 能力位，
 * 漫游只能由电话子系统 radio.getNetworkState().isRoaming 给出，而它是异步的，
 * 与同步的 current() 不同形 —— 因此本类把探针结果缓存在 roamingValue 上，
 * 注册后与每次网络事件里刷新，值变化时补发一次快照。
 * 不具备电话能力的形态（模拟器、平板、无 SIM）一律回落 false。
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
import radio from '@ohos.telephony.radio';
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

/** 电话子系统能力名：不具备（平板、模拟器、无 SIM 形态）时漫游按 false 处理。 */
const TELEPHONY_CORE_SYS_CAP: string = 'SystemCapability.Telephony.CoreService';

/**
 * 漫游探针：返回设备当前是否处于蜂窝漫游。
 * 抽成可注入函数是因为 `radio.getNetworkState` 是**异步**的，而
 * `ConnectivitySource.current()` 是同步契约 —— 异步读到的值只能缓存后盖到后续快照上，
 * 单测则直接注入确定值。
 */
export type RoamingProbe = () => Promise<boolean>;

/** 生产探针：读蜂窝网络注册状态里的 isRoaming；任何失败都回落 false（不漫游）。 */
async function readCellularRoaming(): Promise<boolean> {
  try {
    if (!canIUse(TELEPHONY_CORE_SYS_CAP)) {
      return false;
    }
    const state: radio.NetworkState = await radio.getNetworkState();
    return state !== undefined && state !== null && state.isRoaming === true;
  } catch (e) {
    // 无 SIM / 权限被拒 / 该形态不支持电话能力：都按「没在漫游」处理，不影响其余网络字段。
    return false;
  }
}

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
  private readonly roamingProbe: RoamingProbe;
  /**
   * 最近一次读到的漫游值。`radio.getNetworkState()` 只有异步形态，而 current() 是同步契约，
   * 所以这里缓存并在注册后与网络事件里刷新；漫游切换必然伴随 netAvailable /
   * netCapabilitiesChange，因此快照最多滞后一次事件，不会长期停在旧值上。
   */
  private roamingValue: boolean = false;
  private unregisterStarted: boolean = false;

  constructor(netConnection?: connection.NetConnection, roamingProbe?: RoamingProbe) {
    this.netConnection = netConnection !== undefined ? netConnection : connection.createNetConnection();
    this.roamingProbe = roamingProbe !== undefined ? roamingProbe : readCellularRoaming;
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
      }, this.roamingValue);
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
      // 漫游读的是电话子系统，回来时可能已经换了网络；只在仍活跃且值变了时补发一次快照。
      const refreshRoaming = (): void => {
        this.roamingProbe().then((next: boolean): void => {
          if (!state.active || next === this.roamingValue) {
            return;
          }
          this.roamingValue = next;
          dispatch(this.current());
        }).catch((): void => {
          // 探针自身失败不改变已缓存的漫游值，也不影响其余网络字段的上报。
        });
      };
      const onAvailable = (handle: connection.NetHandle): void => {
        refreshRoaming();
        dispatch(this.snapshotForHandle(handle));
      };
      const onLost = (): void => {
        dispatch(DISCONNECTED_SNAPSHOT);
      };
      const onCapsChange = (info: connection.NetCapabilityInfo): void => {
        refreshRoaming();
        const caps: connection.NetCapabilities = info.netCap;
        dispatch(mapCapabilities({
          bearerTypes: ConnectivityKitSource.toBearerNumbers(caps.bearerTypes),
          capabilities: ConnectivityKitSource.toCapabilityNumbers(caps.networkCap)
        }, this.roamingValue));
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
      refreshRoaming();
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
      }, this.roamingValue);
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
