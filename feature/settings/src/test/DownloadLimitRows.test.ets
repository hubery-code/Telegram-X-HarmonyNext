/**
 * feature/settings — 「按网络类型限制」三行文案映射单元测试（AUTODL-103）。
 *
 * 守住的是副标题与面板勾选必须同源：Android 那一档把「尺寸上限」和「排除的类型」
 * 挤在一个 int 里，副标题有四种合成结果，写错任何一种都会让用户以为限制没生效。
 * 这里只产 i18n 键（尺寸档是单位串），翻译在页面层。
 */

import { describe, it, expect } from '@ohos/hypium';
import {
  AutoDownloadFlags,
  DOWNLOAD_LIMIT_15MB,
  DOWNLOAD_LIMIT_1MB,
  DOWNLOAD_LIMIT_50MB,
  DOWNLOAD_LIMIT_5MB,
  DOWNLOAD_LIMIT_NONE,
  DownloadLimitsByNetwork,
  NetworkDownloadLimits
} from '@tgx/core-domain';
import {
  DOWNLOAD_LIMIT_NETWORK_ORDER,
  DownloadLimitSummary,
  downloadLimitKindLabelKey,
  downloadLimitNetworkLabelKey,
  downloadLimitOfNetwork,
  downloadLimitSizeLabelKey,
  downloadLimitSummary
} from '../main/ets/model/DownloadLimitRows';

function limits(sizeCode: number, mask: number): NetworkDownloadLimits {
  return new NetworkDownloadLimits(sizeCode, AutoDownloadFlags.fromMask(mask));
}

export default function downloadLimitRowsTest(): void {
  describe('DownloadLimitRows', () => {

    it('networkOrder_isAndroidAdvancedItemsOrder', 0, () => {
      expect(DOWNLOAD_LIMIT_NETWORK_ORDER.length).assertEqual(3);
      expect(DOWNLOAD_LIMIT_NETWORK_ORDER[0]).assertEqual('mobile');
      expect(DOWNLOAD_LIMIT_NETWORK_ORDER[1]).assertEqual('wifi');
      expect(DOWNLOAD_LIMIT_NETWORK_ORDER[2]).assertEqual('roaming');

      expect(downloadLimitNetworkLabelKey('mobile')).assertEqual('Restrict on mobile data');
      expect(downloadLimitNetworkLabelKey('wifi')).assertEqual('Restrict on Wi-Fi');
      expect(downloadLimitNetworkLabelKey('roaming')).assertEqual('Restrict on roaming');
      // 未知网络与断网都读移动那一档，行标题也跟着落移动 —— 别出现「标题 Wi-Fi、数值移动」
      expect(downloadLimitNetworkLabelKey('other')).assertEqual('Restrict on mobile data');
      expect(downloadLimitNetworkLabelKey('none')).assertEqual('Restrict on mobile data');
    });

    it('kindLabels_useTheNoPrefixBecauseCheckedMeansExcluded', 0, () => {
      expect(downloadLimitKindLabelKey('photo')).assertEqual('No Photos');
      expect(downloadLimitKindLabelKey('voice')).assertEqual('No Voice messages');
      expect(downloadLimitKindLabelKey('videoNote')).assertEqual('No Video messages');
      expect(downloadLimitKindLabelKey('video')).assertEqual('No Videos');
      expect(downloadLimitKindLabelKey('file')).assertEqual('No Files');
      expect(downloadLimitKindLabelKey('audio')).assertEqual('No Music');
      expect(downloadLimitKindLabelKey('gif')).assertEqual('No GIFs');
    });

    it('sizeLabel_isUnitStringAndNoneReadsNoLimit', 0, () => {
      expect(downloadLimitSizeLabelKey(DOWNLOAD_LIMIT_1MB)).assertEqual('1 MB');
      expect(downloadLimitSizeLabelKey(DOWNLOAD_LIMIT_5MB)).assertEqual('5 MB');
      expect(downloadLimitSizeLabelKey(DOWNLOAD_LIMIT_15MB)).assertEqual('15 MB');
      expect(downloadLimitSizeLabelKey(DOWNLOAD_LIMIT_50MB)).assertEqual('50 MB');
      expect(downloadLimitSizeLabelKey(DOWNLOAD_LIMIT_NONE)).assertEqual('No limit');
    });

    it('summary_notLoadedYetShowsLoading', 0, () => {
      const summary: DownloadLimitSummary = downloadLimitSummary(null);
      expect(summary.singleKey).assertEqual('Loading...');
      expect(summary.excludedKeys.length).assertEqual(0);
    });

    it('summary_allKindsExcludedSaysAnyMedia', 0, () => {
      // 七类全排除 = 这一档什么都不自动下，Android 直接显 AnyMedia，不再提尺寸
      const summary: DownloadLimitSummary = downloadLimitSummary(limits(DOWNLOAD_LIMIT_1MB, 0x7f));
      expect(summary.singleKey).assertEqual('Any media');
      expect(summary.exceedingKey).assertEqual('');
      expect(summary.excludedKeys.length).assertEqual(0);
    });

    it('summary_noCapNoExclusionSaysNoRestrictions', 0, () => {
      const summary: DownloadLimitSummary = downloadLimitSummary(limits(DOWNLOAD_LIMIT_NONE, 0));
      expect(summary.singleKey).assertEqual('No restrictions');
    });

    it('summary_noCapWithExclusionsListsBareKindNames', 0, () => {
      // 0x05 = photo + videoNote（位序沿用 AUTO_DOWNLOAD_KINDS，不是 Android 的 DOWNLOAD_FLAG_*）
      const summary: DownloadLimitSummary = downloadLimitSummary(limits(DOWNLOAD_LIMIT_NONE, 0x05));
      expect(summary.singleKey).assertEqual('');
      expect(summary.exceedingKey).assertEqual('');
      expect(summary.excludedKeys.length).assertEqual(2);
      expect(summary.excludedKeys[0]).assertEqual('Photos');
      expect(summary.excludedKeys[1]).assertEqual('Video message');
    });

    it('summary_capBuildsExceedingSentenceAndKeepsExclusions', 0, () => {
      const summary: DownloadLimitSummary = downloadLimitSummary(limits(DOWNLOAD_LIMIT_50MB, 0x08));
      expect(summary.singleKey).assertEqual('');
      expect(summary.exceedingKey).assertEqual('Any media exceeding {0}');
      expect(summary.sizeLabel).assertEqual('50 MB');
      expect(summary.excludedKeys.length).assertEqual(1);
      expect(summary.excludedKeys[0]).assertEqual('Videos');
    });

    it('summary_followsEachNetworkBucket', 0, () => {
      const all: DownloadLimitsByNetwork = DownloadLimitsByNetwork.defaultLimits();
      expect(downloadLimitSummary(downloadLimitOfNetwork(all, 'wifi')).sizeLabel).assertEqual('50 MB');
      expect(downloadLimitSummary(downloadLimitOfNetwork(all, 'mobile')).sizeLabel).assertEqual('15 MB');
      expect(downloadLimitSummary(downloadLimitOfNetwork(all, 'roaming')).sizeLabel).assertEqual('5 MB');
      // 整套没读盘时三行都显 Loading，不是各自回落默认
      expect(downloadLimitOfNetwork(null, 'wifi') === null).assertTrue();
      expect(downloadLimitSummary(downloadLimitOfNetwork(null, 'wifi')).singleKey).assertEqual('Loading...');
    });
  });
}
