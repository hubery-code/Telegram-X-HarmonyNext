/**
 * feature/settings — 「省流量」卡的纯展示映射（AUTODL-102）。
 *
 * 与 `AutoDownloadRows` 同一口径：设置本体在 `@tgx/core-domain`，这里只把位与设置
 * 翻成行文案，且**只返回 i18n 键**，翻译交给页面。
 */

import { DATA_SAVER_FLAG_WHEN_MOBILE, DATA_SAVER_FLAG_WHEN_ROAMING, DataSaverSettings } from '@tgx/core-domain';

/** 「自动开启」面板里某一档的行标题。 */
export function dataSaverAutoOnLabelKey(flag: number): string {
  if (flag === DATA_SAVER_FLAG_WHEN_MOBILE) {
    return 'Mobile data';
  }
  if (flag === DATA_SAVER_FLAG_WHEN_ROAMING) {
    return 'Roaming';
  }
  return '';
}

/**
 * 「自动开启」行的副标题：Mobile data / Roaming / Mobile and roaming / None 四态
 * （对齐 Android `SettingsDataController.java:156-158`）。还没读盘显 Loading。
 */
export function dataSaverAutoOnSummaryKey(settings: DataSaverSettings | null): string {
  return settings === null ? 'Loading...' : settings.autoOnSummaryKey();
}
