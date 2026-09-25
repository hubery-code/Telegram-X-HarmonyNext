/**
 * core/domain — 省流量（Data Saver）开关与判定（AUTODL-102）。
 *
 * 对齐 Android Telegram-X `telegram/TdlibFilesManager.java`：省流量**不是**「自动媒体下载」
 * 勾选策略的一部分，而是压在它上面的另一套设置，存在另一个偏好键里
 * （`:1007` `settings_datasaver`，一个整数位标记，按账号隔离 `:1015-1017`）。
 * 位取值照 `:1000-1005`：
 * - `DATA_SAVER_FLAG_ENABLED = 1` —— 主开关，不分网络类型一律生效；
 * - `DATA_SAVER_FLAG_WHEN_MOBILE = 1 << 1` —— 切到蜂窝数据时自动生效；
 * - `DATA_SAVER_FLAG_WHEN_ROAMING = 1 << 2` —— 切到漫游时自动生效。
 * Android 另有三位只作用于 VoIP（`DATASAVER_FLAG_CALLS_*`），本端没有通话，不建空位。
 *
 * 判定是**硬否决**：Android `canAutomaticallyDownload()` 的第一行就是
 * `if (isDataSaverActive()) return false;`（`:1353-1355`），在会话类型、媒体类型、尺寸
 * 之前直接结束。省流量生效时不再自动下载任何媒体，用户手动点下载不受影响 ——
 * 那是请求，不是自动下载（同 AUTODL-101 那道门的边界）。
 *
 * 与 Android 的一处有意差异：Android 还会读系统的「数据节省」状态
 * （`core/WatchDog.java:282-302`，`ConnectivityManager.getRestrictBackgroundStatus`）。
 * 本端 `@ohos.net.connection` 的 NetCap 枚举里既没有 Android 的 `NOT_ROAMING` 位，
 * 也没有暴露给普通应用的系统省流量状态，所以这一维不实现（不留一个永远不生效的开关）；
 * 漫游状态改由 `@ohos.telephony.radio.getNetworkState().isRoaming` 提供。
 */

import { NetworkSnapshot } from '@tgx/platform-ports';

/** 偏好存储键前缀；完整键 = 前缀 + accountKey（按账号隔离，同 AUTODL-101）。 */
export const DATA_SAVER_STORAGE_PREFIX: string = 'datasaver_';

export const DATA_SAVER_FLAG_ENABLED: number = 1;
export const DATA_SAVER_FLAG_WHEN_MOBILE: number = 1 << 1;
export const DATA_SAVER_FLAG_WHEN_ROAMING: number = 1 << 2;

/** 「自动开启」的两档；数组顺序即设置页行序，改动必须同步用例矩阵。 */
export const DATA_SAVER_AUTO_ON_FLAGS: number[] = [DATA_SAVER_FLAG_WHEN_MOBILE, DATA_SAVER_FLAG_WHEN_ROAMING];

/**
 * 网络类型档位。与 platform/ports 的 `NetworkTransport` 不是一套词表：
 * Android 的判定分支是「Wi-Fi / 蜂窝 / 漫游 / 其他 / 断网」，其中**漫游是蜂窝的子状态**
 * 而不是另一种承载类型，所以这里单列一档，由装配层从快照的 `transport + roaming` 推导。
 */
export type DataSaverNetworkType = 'none' | 'wifi' | 'mobile' | 'roaming' | 'other';

/**
 * 网络快照 → 网络类型档位（快照来自 `platform/ports`，装配层只负责把它原样递过来）。
 *
 * 蜂窝 + 漫游才是 `roaming`；读不到漫游信息（无 SIM、电话能力不可用、Kit 抛错）时
 * `roaming` 为 false，落回 `mobile` —— 回落方向选「更保守」而不是「更宽松」：
 * 用户只勾了「移动网络时自动开启」时照样拦得住，不会因为读不到漫游而漏放。
 */
export function dataSaverNetworkOfSnapshot(snapshot: NetworkSnapshot | null): DataSaverNetworkType {
  if (snapshot === null || !snapshot.connected) {
    return 'none';
  }
  if (snapshot.transport === 'cellular') {
    return snapshot.roaming ? 'roaming' : 'mobile';
  }
  if (snapshot.transport === 'wifi' || snapshot.transport === 'ethernet') {
    return 'wifi';
  }
  return 'other';
}

/** 省流量设置。三位布尔显式列举，便于 ArkUI 直接观察与开关绑定。 */
export class DataSaverSettings {
  /** 主开关：不分网络类型一律拦。 */
  enabled: boolean;
  /** 切到蜂窝数据时自动生效。 */
  whenMobile: boolean;
  /** 切到漫游时自动生效。 */
  whenRoaming: boolean;

  constructor(enabled: boolean = false, whenMobile: boolean = false, whenRoaming: boolean = true) {
    this.enabled = enabled;
    this.whenMobile = whenMobile;
    this.whenRoaming = whenRoaming;
  }

  /** Android 的兜底默认（`:1192` 只置 `DATASAVER_FLAG_WHEN_ROAMING`）。 */
  static defaultSettings(): DataSaverSettings {
    return new DataSaverSettings();
  }

  static fromMask(mask: number): DataSaverSettings {
    if (!Number.isFinite(mask) || mask < 0) {
      return DataSaverSettings.defaultSettings();
    }
    const value: number = Math.floor(mask);
    return new DataSaverSettings(
      (value & DATA_SAVER_FLAG_ENABLED) !== 0,
      (value & DATA_SAVER_FLAG_WHEN_MOBILE) !== 0,
      (value & DATA_SAVER_FLAG_WHEN_ROAMING) !== 0
    );
  }

  toMask(): number {
    let mask: number = 0;
    if (this.enabled) {
      mask |= DATA_SAVER_FLAG_ENABLED;
    }
    if (this.whenMobile) {
      mask |= DATA_SAVER_FLAG_WHEN_MOBILE;
    }
    if (this.whenRoaming) {
      mask |= DATA_SAVER_FLAG_WHEN_ROAMING;
    }
    return mask;
  }

  ofFlag(flag: number): boolean {
    if (flag === DATA_SAVER_FLAG_ENABLED) {
      return this.enabled;
    }
    if (flag === DATA_SAVER_FLAG_WHEN_MOBILE) {
      return this.whenMobile;
    }
    if (flag === DATA_SAVER_FLAG_WHEN_ROAMING) {
      return this.whenRoaming;
    }
    return false;
  }

  /** 不可变改位；未知位原样返回，避免把 VoIP 的空位当成主开关。 */
  withFlag(flag: number, value: boolean): DataSaverSettings {
    if (flag === DATA_SAVER_FLAG_ENABLED) {
      return new DataSaverSettings(value, this.whenMobile, this.whenRoaming);
    }
    if (flag === DATA_SAVER_FLAG_WHEN_MOBILE) {
      return new DataSaverSettings(this.enabled, value, this.whenRoaming);
    }
    if (flag === DATA_SAVER_FLAG_WHEN_ROAMING) {
      return new DataSaverSettings(this.enabled, this.whenMobile, value);
    }
    return new DataSaverSettings(this.enabled, this.whenMobile, this.whenRoaming);
  }

  /** 「自动开启」行的摘要键（对齐 Android 的 Mobile / Roaming / both / None 四态）。 */
  autoOnSummaryKey(): string {
    if (this.whenMobile && this.whenRoaming) {
      return 'Mobile and roaming';
    }
    if (this.whenMobile) {
      return 'Mobile data';
    }
    if (this.whenRoaming) {
      return 'Roaming';
    }
    return 'None';
  }

  clone(): DataSaverSettings {
    return new DataSaverSettings(this.enabled, this.whenMobile, this.whenRoaming);
  }

  equals(other: DataSaverSettings | null): boolean {
    if (other === null) {
      return false;
    }
    return this.toMask() === other.toMask();
  }
}

/**
 * 省流量此刻是否生效 —— 下载门上那一票否决。
 *
 * `null`（还没读盘）按 Android 的默认设置走，**不能**按「三位都没勾」走：默认勾着
 * 「漫游时自动开启」，读盘失败却在漫游里放行下载，是这台设备上最难复现也最贵的一类错。
 */
export function isDataSaverActive(
  settings: DataSaverSettings | null,
  network: DataSaverNetworkType
): boolean {
  const effective: DataSaverSettings = settings !== null ? settings : DataSaverSettings.defaultSettings();
  if (effective.enabled) {
    return true;
  }
  if (network === 'mobile') {
    return effective.whenMobile;
  }
  if (network === 'roaming') {
    return effective.whenRoaming;
  }
  // Wi-Fi / 其他网络 / 断网：两档自动开启都不成立；主开关已在上面判过。
  return false;
}

/** 设置读写面；实现方负责按账号隔离与落盘（entry 装配层）。 */
export interface DataSaverStore {
  /** 读取；读不到/失败返回 null，调用方回落默认且不回写。 */
  load(): DataSaverSettings | null;

  /** 写入；返回是否成功（失败时 UI 保留原值）。 */
  save(settings: DataSaverSettings): boolean;
}
