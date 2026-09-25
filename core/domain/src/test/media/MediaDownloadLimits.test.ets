/**
 * core/domain — 按网络类型的自动下载限制单元测试（AUTODL-103）。
 *
 * 守住的回归：
 * 1. 档位 → 字节数是**跨版本可存**的约定（存的是档位码），码表一改，用户存的
 *    「Wi-Fi 50MB」会变成另一档；
 * 2. 默认三档必须等于 Android 的兜底（Wi-Fi 50MB / 移动 15MB / 漫游 5MB），
 *    否则首装看到的是自己造的默认；
 * 3. 未知网络类型必须落**移动**那一档 —— 落 Wi-Fi 等于断网重连的瞬间限制变松；
 * 4. 排除位优先于尺寸：一类媒体被排除时，多小都不下；
 * 5. 服务端没给尺寸时放行（与 AUTODL-101 同口径），不能把「还没报大小」读成「超限」。
 */

import { describe, it, expect } from '@ohos/hypium';
import {
  AutoDownloadFlags,
  AutoDownloadMediaKind
} from '../../main/ets/media/AutoDownloadPolicy';
import {
  DOWNLOAD_LIMIT_1MB,
  DOWNLOAD_LIMIT_100MB,
  DOWNLOAD_LIMIT_15MB,
  DOWNLOAD_LIMIT_500MB,
  DOWNLOAD_LIMIT_50MB,
  DOWNLOAD_LIMIT_5MB,
  DOWNLOAD_LIMIT_NONE,
  DOWNLOAD_LIMIT_OPTIONS,
  DOWNLOAD_LIMIT_UNLIMITED_BYTES,
  DownloadLimitsByNetwork,
  NetworkDownloadLimits,
  downloadLimitBytes,
  downloadLimitSizeLabel,
  isMediaWithinDownloadLimits
} from '../../main/ets/media/MediaDownloadLimits';
import { DataSaverNetworkType } from '../../main/ets/media/DataSaver';

const MIB: number = 1024 * 1024;

function limitsOf(sizeCode: number, excluded: AutoDownloadFlags | null = null): NetworkDownloadLimits {
  return new NetworkDownloadLimits(sizeCode, excluded);
}

export default function mediaDownloadLimitsTest() {
  describe('MediaDownloadLimits', () => {

    it('bytesTable_matchesAndroidCodesAndUnknownIsUnlimited', 0, () => {
      expect(downloadLimitBytes(DOWNLOAD_LIMIT_1MB)).assertEqual(1 * MIB);
      expect(downloadLimitBytes(DOWNLOAD_LIMIT_5MB)).assertEqual(5 * MIB);
      expect(downloadLimitBytes(DOWNLOAD_LIMIT_15MB)).assertEqual(15 * MIB);
      expect(downloadLimitBytes(DOWNLOAD_LIMIT_50MB)).assertEqual(50 * MIB);
      expect(downloadLimitBytes(DOWNLOAD_LIMIT_100MB)).assertEqual(100 * MIB);
      expect(downloadLimitBytes(DOWNLOAD_LIMIT_500MB)).assertEqual(500 * MIB);
      // 「无上限」没有字节值；未知档位也回落无上限，读盘脏值不该反过来拦下载
      expect(downloadLimitBytes(DOWNLOAD_LIMIT_NONE)).assertEqual(DOWNLOAD_LIMIT_UNLIMITED_BYTES);
      expect(downloadLimitBytes(99)).assertEqual(DOWNLOAD_LIMIT_UNLIMITED_BYTES);
    });

    it('optionOrder_isAndroidSheetOrderWithNoneLast', 0, () => {
      expect(DOWNLOAD_LIMIT_OPTIONS.length).assertEqual(7);
      expect(DOWNLOAD_LIMIT_OPTIONS[0]).assertEqual(DOWNLOAD_LIMIT_1MB);
      expect(DOWNLOAD_LIMIT_OPTIONS[6]).assertEqual(DOWNLOAD_LIMIT_NONE);
    });

    it('sizeLabel_isUnitStringAndNoneIsEmpty', 0, () => {
      expect(downloadLimitSizeLabel(DOWNLOAD_LIMIT_50MB)).assertEqual('50 MB');
      expect(downloadLimitSizeLabel(DOWNLOAD_LIMIT_500MB)).assertEqual('500 MB');
      expect(downloadLimitSizeLabel(DOWNLOAD_LIMIT_NONE)).assertEqual('');
    });

    it('defaults_matchAndroidFallback', 0, () => {
      const limits: DownloadLimitsByNetwork = DownloadLimitsByNetwork.defaultLimits();
      expect(limits.wifi.sizeCode).assertEqual(DOWNLOAD_LIMIT_50MB);
      expect(limits.mobile.sizeCode).assertEqual(DOWNLOAD_LIMIT_15MB);
      expect(limits.roaming.sizeCode).assertEqual(DOWNLOAD_LIMIT_5MB);
      expect(limits.wifi.excludedFlags.toMask()).assertEqual(0);
      expect(limits.roaming.excludedFlags.toMask()).assertEqual(0);
    });

    it('of_unknownNetworkFallsBackToMobileBucket', 0, () => {
      const limits: DownloadLimitsByNetwork = DownloadLimitsByNetwork.defaultLimits();
      expect(limits.of('wifi').sizeCode).assertEqual(DOWNLOAD_LIMIT_50MB);
      expect(limits.of('roaming').sizeCode).assertEqual(DOWNLOAD_LIMIT_5MB);
      expect(limits.of('mobile').sizeCode).assertEqual(DOWNLOAD_LIMIT_15MB);
      // 未知/无网络都落移动那一档（Android switch 里 mobile 与 default 共用一支）
      const networks: DataSaverNetworkType[] = ['other', 'none'];
      for (const network of networks) {
        expect(limits.of(network).sizeCode).assertEqual(DOWNLOAD_LIMIT_15MB);
      }
    });

    it('withNetwork_leavesOtherBucketsAlone', 0, () => {
      const source: DownloadLimitsByNetwork = DownloadLimitsByNetwork.defaultLimits();
      const before: number = source.mobile.sizeCode;
      const next: DownloadLimitsByNetwork =
        source.withNetwork('wifi', limitsOf(DOWNLOAD_LIMIT_1MB));
      expect(next.wifi.sizeCode).assertEqual(DOWNLOAD_LIMIT_1MB);
      expect(next.mobile.sizeCode).assertEqual(before);
      expect(next.roaming.sizeCode).assertEqual(DOWNLOAD_LIMIT_5MB);
      // 源对象没被改到：UiState 里的旧引用还要能安全比较
      expect(source.wifi.sizeCode).assertEqual(DOWNLOAD_LIMIT_50MB);
      expect(next.equals(source)).assertFalse();
      expect(next.equals(next.clone())).assertTrue();
      expect(next.equals(null)).assertFalse();
      // 'other' 走的是移动那一档，所以改它会动到 mobile
      const mobileNext: DownloadLimitsByNetwork = source.withNetwork('other', limitsOf(DOWNLOAD_LIMIT_5MB));
      expect(mobileNext.mobile.sizeCode).assertEqual(DOWNLOAD_LIMIT_5MB);
    });

    it('withSizeCode_rejectsUnknownCode', 0, () => {
      const limits: NetworkDownloadLimits = limitsOf(DOWNLOAD_LIMIT_50MB);
      expect(limits.withSizeCode(DOWNLOAD_LIMIT_100MB).sizeCode).assertEqual(DOWNLOAD_LIMIT_100MB);
      expect(limits.withSizeCode(77).sizeCode).assertEqual(DOWNLOAD_LIMIT_NONE);
      // 改尺寸不动排除位
      const excluded: NetworkDownloadLimits =
        limits.withExcluded('photo', true).withSizeCode(DOWNLOAD_LIMIT_1MB);
      expect(excluded.isExcluded('photo')).assertTrue();
      expect(limits.isExcluded('photo')).assertFalse();
    });

    it('excludedFlags_reusePartitionBitOrder', 0, () => {
      let limits: NetworkDownloadLimits = limitsOf(DOWNLOAD_LIMIT_50MB);
      const kinds: AutoDownloadMediaKind[] =
        ['photo', 'voice', 'videoNote', 'video', 'file', 'audio', 'gif'];
      for (let index = 0; index < kinds.length; index++) {
        const kind: AutoDownloadMediaKind = kinds[index];
        limits = limits.withExcluded(kind, true);
        expect(limits.isExcluded(kind)).assertTrue();
        expect(limits.excludedFlags.toMask()).assertEqual((1 << (index + 1)) - 1);
      }
      expect(limits.withExcluded('video', false).isExcluded('video')).assertFalse();
    });

    it('storage_roundTripsAllSixValues', 0, () => {
      const policy: DownloadLimitsByNetwork = DownloadLimitsByNetwork.defaultLimits()
        .withNetwork('mobile', limitsOf(DOWNLOAD_LIMIT_100MB, AutoDownloadFlags.fromMask(0x15)))
        .withNetwork('wifi', limitsOf(DOWNLOAD_LIMIT_NONE, AutoDownloadFlags.fromMask(0x7f)))
        .withNetwork('roaming', limitsOf(DOWNLOAD_LIMIT_1MB));
      const values: number[] = policy.toStorageValues();
      expect(values.length).assertEqual(6);
      const restored: DownloadLimitsByNetwork = DownloadLimitsByNetwork.fromStorageValues(values);
      expect(restored.equals(policy)).assertTrue();
      expect(restored.mobile.excludedFlags.toMask()).assertEqual(0x15);
      expect(restored.wifi.sizeCode).assertEqual(DOWNLOAD_LIMIT_NONE);
    });

    it('storage_partialOrBrokenValuesFallBackPerBucket', 0, () => {
      const expected: DownloadLimitsByNetwork = DownloadLimitsByNetwork.defaultLimits();
      const allEmpty: DownloadLimitsByNetwork =
        DownloadLimitsByNetwork.fromStorageValues([null, null, null, null, null, null]);
      expect(allEmpty.equals(expected)).assertTrue();
      // 只写了移动档：其余两档仍回落各自默认，不会被读成「无上限」
      const onlyMobile: DownloadLimitsByNetwork =
        DownloadLimitsByNetwork.fromStorageValues([DOWNLOAD_LIMIT_1MB, 0, null, null, null, null]);
      expect(onlyMobile.mobile.sizeCode).assertEqual(DOWNLOAD_LIMIT_1MB);
      expect(onlyMobile.wifi.sizeCode).assertEqual(DOWNLOAD_LIMIT_50MB);
      expect(onlyMobile.roaming.sizeCode).assertEqual(DOWNLOAD_LIMIT_5MB);
      // 负数 / NaN 是脏值；小数按 floor 收（与 AUTODL-101 同一口径）；排除掩码高位被截掉
      const broken: DownloadLimitsByNetwork = DownloadLimitsByNetwork.fromStorageValues(
        [-1, NaN, 1.9, 0x7f + 0x800, 2, null]
      );
      expect(broken.mobile.sizeCode).assertEqual(DOWNLOAD_LIMIT_15MB);
      expect(broken.wifi.sizeCode).assertEqual(DOWNLOAD_LIMIT_1MB);
      expect(broken.wifi.excludedFlags.toMask()).assertEqual(0x7f);
      expect(broken.roaming.sizeCode).assertEqual(DOWNLOAD_LIMIT_5MB);
      expect(broken.roaming.excludedFlags.toMask()).assertEqual(0);
    });

    it('gate_sizeIsLessOrEqualAndBoundaryInclusive', 0, () => {
      expect(isMediaWithinDownloadLimits(null, 'wifi', 'photo', 1024)).assertTrue();
      const limits: DownloadLimitsByNetwork = DownloadLimitsByNetwork.defaultLimits();
      expect(isMediaWithinDownloadLimits(limits, 'wifi', 'video', 50 * MIB)).assertTrue();
      expect(isMediaWithinDownloadLimits(limits, 'wifi', 'video', 50 * MIB + 1)).assertFalse();
      expect(isMediaWithinDownloadLimits(limits, 'roaming', 'file', 5 * MIB + 1)).assertFalse();
      // 无上限那档什么尺寸都放行
      const none: DownloadLimitsByNetwork =
        limits.withNetwork('wifi', limitsOf(DOWNLOAD_LIMIT_NONE));
      expect(isMediaWithinDownloadLimits(none, 'wifi', 'file', 10 * 1000 * MIB)).assertTrue();
    });

    it('gate_excludedKindDeniesRegardlessOfSize', 0, () => {
      const limits: DownloadLimitsByNetwork = DownloadLimitsByNetwork.defaultLimits()
        .withNetwork('wifi', limitsOf(DOWNLOAD_LIMIT_50MB, AutoDownloadFlags.fromMask(0).with('photo', true)));
      expect(isMediaWithinDownloadLimits(limits, 'wifi', 'photo', 1)).assertFalse();
      // 排除只作用于本档：移动档没勾「不下载照片」
      expect(isMediaWithinDownloadLimits(limits, 'mobile', 'photo', 1)).assertTrue();
    });

    it('gate_allowsWhenServerGivesNoSize', 0, () => {
      const limits: DownloadLimitsByNetwork = DownloadLimitsByNetwork.defaultLimits()
        .withNetwork('wifi', limitsOf(DOWNLOAD_LIMIT_1MB));
      expect(isMediaWithinDownloadLimits(limits, 'wifi', 'file', 0)).assertTrue();
      expect(isMediaWithinDownloadLimits(limits, 'wifi', 'file', -1)).assertTrue();
      expect(isMediaWithinDownloadLimits(limits, 'wifi', 'file', NaN)).assertTrue();
      expect(isMediaWithinDownloadLimits(limits, 'wifi', 'file', Infinity)).assertTrue();
      // 但排除位仍然生效：没有尺寸不等于可以下这一类
      const excluded: DownloadLimitsByNetwork = DownloadLimitsByNetwork.defaultLimits()
        .withNetwork('wifi', limitsOf(DOWNLOAD_LIMIT_1MB, AutoDownloadFlags.fromMask(0).with('file', true)));
      expect(isMediaWithinDownloadLimits(excluded, 'wifi', 'file', NaN)).assertFalse();
    });
  });
}
