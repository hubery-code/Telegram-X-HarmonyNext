/**
 * platform/network — Kit 能力 → NetworkSnapshot 映射 + 快照去重（PLAT-004，纯 ArkTS 无 Kit 依赖）。
 *
 * 映射表（对照 HarmonyOS Network Kit，见 @ohos.net.connection d.ts）：
 * - NetBearType：BEARER_CELLULAR=0 → cellular，BEARER_WIFI=1 → wifi，
 *   BEARER_ETHERNET=3 → ethernet，其余（BLUETOOTH=2 / VPN=4 / 未知）→ other；
 * - 多 bearer 并存（如 VPN over Wi-Fi）取优先级最高者，与系统默认网络优先级一致：
 *   ethernet > wifi > cellular > other；
 * - metered：NetCapabilities.networkCap 不含 NET_CAPABILITY_NOT_METERED（=11）即为计费网络
 *   （蜂窝通常无 NOT_METERED → metered=true；Wi-Fi 通常带 NOT_METERED → metered=false）。
 *
 * 以上常量值以 SDK d.ts 为准（API 24/26 已核对）；若 Kit 枚举值演进，
 * 只需改本文件常量，调用方无感。
 */

import { NetworkSnapshot, NetworkTransport } from '@tgx/platform-ports';

/** HarmonyOS connection.NetBearType 数值（SDK d.ts 核对）。 */
export const NET_BEARER_CELLULAR: number = 0;
export const NET_BEARER_WIFI: number = 1;
export const NET_BEARER_BLUETOOTH: number = 2;
export const NET_BEARER_ETHERNET: number = 3;
export const NET_BEARER_VPN: number = 4;

/** HarmonyOS connection.NetCap.NET_CAPABILITY_NOT_METERED 数值（SDK d.ts 核对）。 */
export const NET_CAPABILITY_NOT_METERED: number = 11;

/** 断网快照（契约语义：transport 为 null、metered 为 false）。 */
export const DISCONNECTED_SNAPSHOT: NetworkSnapshot = {
  connected: false,
  transport: null,
  metered: false
};

/** 单个 bearer → 契约 transport。 */
export function transportForBearer(bearer: number): NetworkTransport {
  if (bearer === NET_BEARER_WIFI) {
    return 'wifi';
  }
  if (bearer === NET_BEARER_CELLULAR) {
    return 'cellular';
  }
  if (bearer === NET_BEARER_ETHERNET) {
    return 'ethernet';
  }
  return 'other';
}

/** 多 bearer 并存时的选择优先级（与系统默认网络优先级一致，索引小者优先）。 */
const TRANSPORT_PRIORITY: NetworkTransport[] = ['ethernet', 'wifi', 'cellular', 'other'];

/**
 * Kit NetCapabilities 的 Kit-free 投影：adapter 只依赖这两个数组，
 * Kit 层负责把 connection.NetCapabilities 抽成该结构（也是单测的注入面）。
 */
export interface RawNetCapabilities {
  readonly bearerTypes: number[];
  readonly capabilities: number[];
}

/** RawNetCapabilities → 已连接快照（断网语义不在此函数内，见 DISCONNECTED_SNAPSHOT）。 */
export function mapCapabilities(raw: RawNetCapabilities): NetworkSnapshot {
  let best: NetworkTransport = 'other';
  let bestRank: number = TRANSPORT_PRIORITY.length;
  for (const bearer of raw.bearerTypes) {
    const transport: NetworkTransport = transportForBearer(bearer);
    const rank: number = TRANSPORT_PRIORITY.indexOf(transport);
    if (rank >= 0 && rank < bestRank) {
      bestRank = rank;
      best = transport;
    }
  }
  const metered: boolean = raw.capabilities.indexOf(NET_CAPABILITY_NOT_METERED) < 0;
  return { connected: true, transport: best, metered: metered };
}

/** 两快照全字段相等判定（契约去重口径）。 */
export function sameSnapshot(a: NetworkSnapshot, b: NetworkSnapshot): boolean {
  return a.connected === b.connected && a.transport === b.transport && a.metered === b.metered;
}

/**
 * 连续快照去重器：底层（Kit 或 Fake）可能天然重复上报，
 * next() 返回 null 表示与上一快照相同（丢弃），否则返回该快照。
 */
export class SnapshotDeduper {
  private last: NetworkSnapshot | null = null;

  next(snapshot: NetworkSnapshot): NetworkSnapshot | null {
    if (this.last !== null && sameSnapshot(this.last, snapshot)) {
      return null;
    }
    this.last = snapshot;
    return snapshot;
  }
}
