/**
 * core/domain — 按网络类型的自动下载限制（AUTODL-103，FEAT-P2-007 尺寸上限半边）。
 *
 * 对齐 Android Telegram-X `telegram/TdlibFilesManager.java`：除了「哪个会话分区自动下哪一类媒体」
 * （AUTODL-101）和「省流量一票否决」（AUTODL-102），Android 还有第三套设置 ——
 * **按当前网络类型给自动下载加限制**（`:960-962`）：
 * - `settings_limit_wifi`（默认 50MB，`:1199`）
 * - `settings_limit_mobile`（默认 15MB，`:1203`）
 * - `settings_limit_roaming`（默认 5MB，`:1207`）
 * 每档存的是**一个 int**：`(excludeFlags << 24) | (sizeLimit & 0xffffff)`（`:1133`），
 * 即「尺寸上限档位」+「这一档额外不自动下的媒体类型掩码」两件事挤在一个数字里。
 * 本端沿用 AUTODL-101 的口径不做字节打包（一个网络两个键，见 `MEDIA_LIMIT_STORAGE_PREFIX`），
 * 语义等价、调试时能直接看出是哪一项。
 *
 * 判定顺序严格照 Android `canAutomaticallyDownload()`（`:1352-1411`）：
 * 省流量否决 → **按网络类型取限制，尺寸超限或类型被排除就直接 false** → 会话分区勾选。
 * 也就是说这一层压在分区策略**之前**：Wi-Fi 上限调到 1MB 时，一张 3MB 的照片
 * 不会因为「私聊勾了照片」就放过去。
 *
 * 尺寸上限作用于**所有**媒体类型（Android `file.size > getDownloadLimit(limit)` 不分类型），
 * 所以 AUTODL-101 里那条「只有视频/文件/音乐看尺寸、写死 10MB」的临时规则由本档取代。
 *
 * 档位取值与顺序照 Android `:964-979`（`DOWNLOAD_LIMIT_NONE` 排在选项列表最后，
 * 表示「无上限」而不是某个具体字节数）。
 */

import { AutoDownloadFlags, AutoDownloadMediaKind } from './AutoDownloadPolicy';
import { DataSaverNetworkType } from './DataSaver';

/** 偏好存储键前缀；完整键 = 前缀 + accountKey + ':' + 网络档 + ':' + 字段。 */
export const MEDIA_LIMIT_STORAGE_PREFIX: string = 'medialimit_';

/** 三档网络；数组顺序即设置页行序（对齐 Android 的 mobile → Wi-Fi → roaming）。 */
export const MEDIA_LIMIT_NETWORKS: DataSaverNetworkType[] = ['mobile', 'wifi', 'roaming'];

/** 每档的两个字段；键名直接进偏好键尾部，改动等于换存储 schema。 */
export const MEDIA_LIMIT_FIELD_SIZE: string = 'size';
export const MEDIA_LIMIT_FIELD_EXCLUDE: string = 'exclude';

export const DOWNLOAD_LIMIT_NONE: number = 0x00;
export const DOWNLOAD_LIMIT_1MB: number = 0x01;
export const DOWNLOAD_LIMIT_5MB: number = 0x02;
export const DOWNLOAD_LIMIT_15MB: number = 0x03;
export const DOWNLOAD_LIMIT_50MB: number = 0x04;
export const DOWNLOAD_LIMIT_100MB: number = 0x05;
export const DOWNLOAD_LIMIT_500MB: number = 0x06;

/** 面板里的尺寸选项；顺序即界面顺序，`DOWNLOAD_LIMIT_NONE` 在末尾（照 Android `:971-979`）。 */
export const DOWNLOAD_LIMIT_OPTIONS: number[] = [
  DOWNLOAD_LIMIT_1MB,
  DOWNLOAD_LIMIT_5MB,
  DOWNLOAD_LIMIT_15MB,
  DOWNLOAD_LIMIT_50MB,
  DOWNLOAD_LIMIT_100MB,
  DOWNLOAD_LIMIT_500MB,
  DOWNLOAD_LIMIT_NONE
];

const MIB: number = 1024 * 1024;

/** 「无上限」用的哨兵字节数；比 TDLib 里可能出现的任何文件都大，且仍能安全参与比较。 */
export const DOWNLOAD_LIMIT_UNLIMITED_BYTES: number = Number.MAX_SAFE_INTEGER;

/** 档位 → 字节上限；未知档位按「无上限」处理（读盘脏值不该反过来拦下载）。 */
export function downloadLimitBytes(code: number): number {
  switch (code) {
    case DOWNLOAD_LIMIT_1MB:
      return 1 * MIB;
    case DOWNLOAD_LIMIT_5MB:
      return 5 * MIB;
    case DOWNLOAD_LIMIT_15MB:
      return 15 * MIB;
    case DOWNLOAD_LIMIT_50MB:
      return 50 * MIB;
    case DOWNLOAD_LIMIT_100MB:
      return 100 * MIB;
    case DOWNLOAD_LIMIT_500MB:
      return 500 * MIB;
    default:
      return DOWNLOAD_LIMIT_UNLIMITED_BYTES;
  }
}

/** 档位 → 尺寸文案（单位串，中英同形，无需翻译）。 */
export function downloadLimitSizeLabel(code: number): string {
  if (code === DOWNLOAD_LIMIT_NONE) {
    return '';
  }
  const bytes: number = downloadLimitBytes(code);
  if (bytes >= 1000 * MIB && bytes % (1000 * MIB) === 0) {
    return `${Math.floor(bytes / (1000 * MIB))} GB`;
  }
  return `${Math.floor(bytes / MIB)} MB`;
}

/** 全部七类媒体都被排除的掩码 —— Android 的 `DOWNLOAD_ALL_MEDIAS`（`:995`）。 */
export const DOWNLOAD_EXCLUDE_ALL_KINDS: number = 0x7f;

/** 某一档网络限制：尺寸上限档位 + 排除的媒体类型（勾选语义是「不自动下」）。 */
export class NetworkDownloadLimits {
  sizeCode: number;
  /** 复用分区的七位掩码结构，但这里是**排除**位（1 = 这一类不自动下）。 */
  excludedFlags: AutoDownloadFlags;

  constructor(sizeCode: number = DOWNLOAD_LIMIT_NONE, excludedFlags: AutoDownloadFlags | null = null) {
    this.sizeCode = sizeCode;
    this.excludedFlags = excludedFlags !== null ? excludedFlags : new AutoDownloadFlags();
  }

  isExcluded(kind: AutoDownloadMediaKind): boolean {
    return this.excludedFlags.of(kind);
  }

  /** 不可变改排除位。 */
  withExcluded(kind: AutoDownloadMediaKind, excluded: boolean): NetworkDownloadLimits {
    return new NetworkDownloadLimits(this.sizeCode, this.excludedFlags.with(kind, excluded));
  }

  /** 不可变改尺寸档；非法档位回落「无上限」。 */
  withSizeCode(code: number): NetworkDownloadLimits {
    const index: number = DOWNLOAD_LIMIT_OPTIONS.indexOf(code);
    return new NetworkDownloadLimits(index < 0 ? DOWNLOAD_LIMIT_NONE : code, this.excludedFlags.clone());
  }

  sizeBytes(): number {
    return downloadLimitBytes(this.sizeCode);
  }

  clone(): NetworkDownloadLimits {
    return new NetworkDownloadLimits(this.sizeCode, this.excludedFlags.clone());
  }

  equals(other: NetworkDownloadLimits | null): boolean {
    if (other === null) {
      return false;
    }
    return this.sizeCode === other.sizeCode && this.excludedFlags.equals(other.excludedFlags);
  }
}

/** 三档网络的限制集合。读不到盘就整套回落 Android 默认。 */
export class DownloadLimitsByNetwork {
  mobile: NetworkDownloadLimits;
  wifi: NetworkDownloadLimits;
  roaming: NetworkDownloadLimits;

  constructor(
    mobile: NetworkDownloadLimits | null = null,
    wifi: NetworkDownloadLimits | null = null,
    roaming: NetworkDownloadLimits | null = null
  ) {
    this.mobile = mobile !== null ? mobile : new NetworkDownloadLimits(DOWNLOAD_LIMIT_15MB);
    this.wifi = wifi !== null ? wifi : new NetworkDownloadLimits(DOWNLOAD_LIMIT_50MB);
    this.roaming = roaming !== null ? roaming : new NetworkDownloadLimits(DOWNLOAD_LIMIT_5MB);
  }

  /** Android `loadSettings()` 的兜底：Wi-Fi 50MB / 移动 15MB / 漫游 5MB，都不额外排除类型。 */
  static defaultLimits(): DownloadLimitsByNetwork {
    return new DownloadLimitsByNetwork();
  }

  /**
   * 当前网络类型该看哪一档。
   *
   * `other` / `none` 落**移动网络**这一档：Android 的 switch 里
   * `CONNECTION_TYPE_MOBILE` 与 `default` 共用一支（`:1374-1378`），
   * 未知网络从来不会走到宽松的 Wi-Fi 档 —— 回落方向保持一致才不会出现
   * 「断网重连的瞬间限制变松」。
   */
  of(network: DataSaverNetworkType): NetworkDownloadLimits {
    if (network === 'wifi') {
      return this.wifi;
    }
    if (network === 'roaming') {
      return this.roaming;
    }
    return this.mobile;
  }

  withNetwork(network: DataSaverNetworkType, limits: NetworkDownloadLimits): DownloadLimitsByNetwork {
    const next: DownloadLimitsByNetwork = this.clone();
    if (network === 'wifi') {
      next.wifi = limits;
    } else if (network === 'roaming') {
      next.roaming = limits;
    } else {
      next.mobile = limits;
    }
    return next;
  }

  clone(): DownloadLimitsByNetwork {
    return new DownloadLimitsByNetwork(this.mobile.clone(), this.wifi.clone(), this.roaming.clone());
  }

  equals(other: DownloadLimitsByNetwork | null): boolean {
    if (other === null) {
      return false;
    }
    return this.mobile.equals(other.mobile) && this.wifi.equals(other.wifi) && this.roaming.equals(other.roaming);
  }

  /**
   * 落盘值：每档两个数字，顺序 = `MEDIA_LIMIT_NETWORKS` × (size, exclude)。
   * 掩码取 `excludedFlags.toMask()`（位序 = `AUTO_DOWNLOAD_KINDS`，与分区策略同一张表）。
   */
  toStorageValues(): number[] {
    const values: number[] = [];
    for (const network of MEDIA_LIMIT_NETWORKS) {
      const limits: NetworkDownloadLimits = this.of(network);
      values.push(limits.sizeCode);
      values.push(limits.excludedFlags.toMask());
    }
    return values;
  }

  /**
   * 读盘值 → 设置；`null` 项表示「这一档从没设置过」，逐档回落默认，
   * 避免半套脏数据把 Wi-Fi 变成无上限。
   */
  static fromStorageValues(values: (number | null)[]): DownloadLimitsByNetwork {
    let mobile: NetworkDownloadLimits | null = null;
    let wifi: NetworkDownloadLimits | null = null;
    let roaming: NetworkDownloadLimits | null = null;
    for (let i = 0; i < MEDIA_LIMIT_NETWORKS.length; i++) {
      const size: number | null | undefined = values[i * 2];
      const exclude: number | null | undefined = values[i * 2 + 1];
      const network: DataSaverNetworkType | undefined = MEDIA_LIMIT_NETWORKS[i];
      if (size === null || size === undefined || !Number.isFinite(size) || size < 0) {
        continue;
      }
      const excludeMask: number =
        exclude !== null && exclude !== undefined && Number.isFinite(exclude) && exclude >= 0
          ? Math.floor(exclude) & DOWNLOAD_EXCLUDE_ALL_KINDS
          : 0;
      const limits: NetworkDownloadLimits =
        new NetworkDownloadLimits(Math.floor(size), AutoDownloadFlags.fromMask(excludeMask));
      if (network === 'wifi') {
        wifi = limits;
      } else if (network === 'roaming') {
        roaming = limits;
      } else {
        mobile = limits;
      }
    }
    return new DownloadLimitsByNetwork(mobile, wifi, roaming);
  }
}

/**
 * 尺寸与类型排除这一层是否放行。
 *
 * `sizeBytes <= 0` / 非有限值（服务端还没给尺寸）按放行处理 —— 与 AUTODL-101 同一口径：
 * 没有尺寸就不该拿尺寸当理由拦。上限本身是「小于等于」，与 Android 的
 * `file.size > getDownloadLimit(limit)` 严格互补。
 */
export function isMediaWithinDownloadLimits(
  limits: DownloadLimitsByNetwork | null,
  network: DataSaverNetworkType,
  kind: AutoDownloadMediaKind,
  sizeBytes: number
): boolean {
  const effective: DownloadLimitsByNetwork = limits !== null ? limits : DownloadLimitsByNetwork.defaultLimits();
  const of: NetworkDownloadLimits = effective.of(network);
  if (of.isExcluded(kind)) {
    return false;
  }
  if (!Number.isFinite(sizeBytes) || sizeBytes <= 0) {
    return true;
  }
  return sizeBytes <= of.sizeBytes();
}

/** 限制读写面；实现方负责按账号隔离与落盘（entry 装配层）。 */
export interface DownloadLimitsStore {
  /** 读取；读不到/失败返回 null，调用方回落默认且不回写。 */
  load(): DownloadLimitsByNetwork | null;

  /** 写入；返回是否成功（失败时 UI 保留原值）。 */
  save(limits: DownloadLimitsByNetwork): boolean;
}
