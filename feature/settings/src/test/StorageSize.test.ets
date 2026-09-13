/**
 * feature/settings — 存储占用格式化单测（SET-104 / FEAT-SET-004）。
 *
 * 覆盖：
 * 1. formatBytes 各单位边界（B/KB/MB/GB）、1024 进制进位、1 位小数；
 * 2. 非法输入（负数 / NaN / Infinity）统一回落到 "0 B"；
 * 3. formatStorageLabel 的空缓存不缀文件数、单复数。
 */

import { describe, it, expect } from '@ohos/hypium';
import { formatBytes, formatStorageLabel } from '../main/ets/model/StorageSize';

export default function storageSizeTest() {
  describe('StorageSizeTest', () => {
    it('formatBytes_bytesRangeHasNoDecimals', 0, () => {
      expect(formatBytes(0)).assertEqual('0 B');
      expect(formatBytes(1)).assertEqual('1 B');
      expect(formatBytes(512)).assertEqual('512 B');
      // 1023 仍是字节（不进位到 KB）
      expect(formatBytes(1023)).assertEqual('1023 B');
    });

    it('formatBytes_kilobytesAndAboveKeepOneDecimal', 0, () => {
      expect(formatBytes(1024)).assertEqual('1.0 KB');
      expect(formatBytes(1536)).assertEqual('1.5 KB');
      expect(formatBytes(1024 * 1024)).assertEqual('1.0 MB');
      expect(formatBytes(1024 * 1024 * 1.25)).assertEqual('1.3 MB');
      expect(formatBytes(1024 * 1024 * 1024)).assertEqual('1.0 GB');
      expect(formatBytes(1024 * 1024 * 1024 * 2.5)).assertEqual('2.5 GB');
    });

    it('formatBytes_boundariesRollOverToNextUnit', 0, () => {
      // 1 MB - 1 字节仍是 KB；1 MB 起才是 MB
      expect(formatBytes(1024 * 1024 - 1)).assertEqual('1024.0 KB');
      expect(formatBytes(1024 * 1024)).assertEqual('1.0 MB');
      expect(formatBytes(1024 * 1024 * 1024 - 1)).assertEqual('1024.0 MB');
      expect(formatBytes(1024 * 1024 * 1024)).assertEqual('1.0 GB');
    });

    it('formatBytes_invalidInputFallsBackToZero', 0, () => {
      expect(formatBytes(-1)).assertEqual('0 B');
      expect(formatBytes(-1024)).assertEqual('0 B');
      expect(formatBytes(Number.NaN)).assertEqual('0 B');
      expect(formatBytes(Number.POSITIVE_INFINITY)).assertEqual('0 B');
    });

    it('formatStorageLabel_omitsFileCountWhenEmpty', 0, () => {
      // 空缓存不缀 "0 files"，避免 "0 B · 0 files" 冗余
      expect(formatStorageLabel(0, 0)).assertEqual('0 B');
      expect(formatStorageLabel(-5, 0)).assertEqual('0 B');
    });

    it('formatStorageLabel_appendsFileCountWithPluralization', 0, () => {
      expect(formatStorageLabel(1536, 1)).assertEqual('1.5 KB · 1 file');
      expect(formatStorageLabel(1536, 2)).assertEqual('1.5 KB · 2 files');
      expect(formatStorageLabel(1024 * 1024 * 3.5, 128)).assertEqual('3.5 MB · 128 files');
    });

    it('formatStorageLabel_ignoresInvalidFileCount', 0, () => {
      expect(formatStorageLabel(1536, -3)).assertEqual('1.5 KB');
      expect(formatStorageLabel(1536, Number.NaN)).assertEqual('1.5 KB');
    });
  });
}
