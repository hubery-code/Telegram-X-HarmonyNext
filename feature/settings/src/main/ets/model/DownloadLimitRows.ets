/**
 * feature/settings — 「按网络类型限制」三行的纯展示映射（AUTODL-103）。
 *
 * 与 `AutoDownloadRows` / `DataSaverRows` 同一口径：设置本体在 `@tgx/core-domain`，
 * 这里只把它翻成行文案，且**只返回 i18n 键**（尺寸档是单位串，不参与翻译）。
 *
 * 副标题的合成规则严格照 Android `TdlibFilesManager.getDownloadLimitString(limit, excludedTypes)`
 * （`:1427-1444`）：
 * 1. 七类全排除 → `Any media`（等于这一档什么都不自动下）；
 * 2. 否则有尺寸上限 → `Any media exceeding 50 MB`；
 * 3. 无上限且没排除 → `No restrictions`；
 * 4. 还被排除了一些类型 → 追一段裸类型名列表（Android 就是 `, Photos, Videos`）。
 * 一处措辞差异：Android 把「无上限」这一档显示成 `∞ GB`（`fileSize_GB` 塞了个 "∞"，`:1417-1418`），
 * 本端直接写 `No limit` —— 同一列里其它项都是「N MB」，出现「∞ GB」只会让人以为是容量单位。
 */

import {
  AutoDownloadMediaKind,
  DOWNLOAD_LIMIT_NONE,
  DownloadLimitsByNetwork,
  NetworkDownloadLimits,
  DataSaverNetworkType,
  downloadLimitSizeLabel
} from '@tgx/core-domain';
import { AUTO_DOWNLOAD_KIND_ORDER, autoDownloadKindLabelKey } from './AutoDownloadRows';

/** 三行的行序：对齐 Android `newAdvancedItems()` 的 mobile → Wi-Fi → roaming（`:594-604`）。 */
export const DOWNLOAD_LIMIT_NETWORK_ORDER: DataSaverNetworkType[] = ['mobile', 'wifi', 'roaming'];

/** 行标题（Android `RestrictOverMobile` / `RestrictOnWiFi` / `RestrictOnRoaming`）。 */
export function downloadLimitNetworkLabelKey(network: DataSaverNetworkType): string {
  if (network === 'wifi') {
    return 'Restrict on Wi-Fi';
  }
  if (network === 'roaming') {
    return 'Restrict on roaming';
  }
  return 'Restrict on mobile data';
}

/**
 * 面板里某一类媒体的行标题：勾选语义是「这一类不自动下」，所以带 No 前缀
 * （Android 的限制面板用的就是 `NoPhotos` / `NoVideos` / `NoGIFs`…，
 * 与分区面板那套「勾了才下」的裸类型名正好相反）。
 */
export function downloadLimitKindLabelKey(kind: AutoDownloadMediaKind): string {
  switch (kind) {
    case 'photo':
      return 'No Photos';
    case 'voice':
      return 'No Voice messages';
    case 'videoNote':
      return 'No Video messages';
    case 'video':
      return 'No Videos';
    case 'file':
      return 'No Files';
    case 'audio':
      return 'No Music';
    case 'gif':
      return 'No GIFs';
    default:
      return 'No Photos';
  }
}

/** 尺寸档的展示文案；`No limit` 是 i18n 键，其余是单位串。 */
export function downloadLimitSizeLabelKey(code: number): string {
  const label: string = downloadLimitSizeLabel(code);
  return label.length > 0 ? label : 'No limit';
}

/** 一行的副标题结构；页面按 `singleKey` / `exceedingKey` + `excludedKeys` 合成本地文案。 */
export class DownloadLimitSummary {
  /** 整句就是这一个键时非空（`Loading...` / `Any media` / `No restrictions`）。 */
  readonly singleKey: string;
  /** 有尺寸上限时的句子键（带 `{0}` 尺寸占位）；与 `singleKey` 互斥。 */
  readonly exceedingKey: string;
  readonly sizeLabel: string;
  /** 额外被排除的类型（裸名称键，沿用分区面板那套类型名）。 */
  readonly excludedKeys: string[];

  constructor(singleKey: string, exceedingKey: string, sizeLabel: string, excludedKeys: string[]) {
    this.singleKey = singleKey;
    this.exceedingKey = exceedingKey;
    this.sizeLabel = sizeLabel;
    this.excludedKeys = excludedKeys;
  }
}

/**
 * 一行的副标题。传的是 `NetworkDownloadLimits`（单档）而不是整套 —— 三行各显各的档，
 * 这才是 Android 那张表的读法。
 */
export function downloadLimitSummary(limits: NetworkDownloadLimits | null): DownloadLimitSummary {
  if (limits === null) {
    return new DownloadLimitSummary('Loading...', '', '', []);
  }
  const excludedKeys: string[] = [];
  for (const kind of AUTO_DOWNLOAD_KIND_ORDER) {
    if (limits.isExcluded(kind)) {
      excludedKeys.push(autoDownloadKindLabelKey(kind));
    }
  }
  if (excludedKeys.length === AUTO_DOWNLOAD_KIND_ORDER.length) {
    return new DownloadLimitSummary('Any media', '', '', []);
  }
  if (limits.sizeCode === DOWNLOAD_LIMIT_NONE && limits.excludedFlags.toMask() === 0) {
    return new DownloadLimitSummary('No restrictions', '', '', []);
  }
  if (limits.sizeCode === DOWNLOAD_LIMIT_NONE) {
    // 无上限但仍排除了若干类型：Android 这里也只列类型名，不写「No restrictions」。
    return new DownloadLimitSummary('', '', '', excludedKeys);
  }
  return new DownloadLimitSummary(
    '',
    'Any media exceeding {0}',
    downloadLimitSizeLabelKey(limits.sizeCode),
    excludedKeys
  );
}

/** 取某一档；整套还没读盘时返回 null（行显 Loading）。 */
export function downloadLimitOfNetwork(
  limits: DownloadLimitsByNetwork | null,
  network: DataSaverNetworkType
): NetworkDownloadLimits | null {
  return limits === null ? null : limits.of(network);
}
