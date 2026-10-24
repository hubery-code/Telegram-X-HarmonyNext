/**
 * feature/settings — 存储占用格式化单测（SET-104 / FEAT-SET-004）。
 *
 * 覆盖：
 * 1. formatBytes 各单位边界（B/KB/MB/GB）、1024 进制进位、1 位小数；
 * 2. 非法输入（负数 / NaN / Infinity）统一回落到 "0 B"；
 * 3. formatStorageLabel 的空缓存不缀文件数、单复数。
 */

import { describe, it, expect } from '@ohos/hypium';
import { Lang, LanguagePreference, SupportedLanguage } from '@tgx/core-common';
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
      // 这条用例原先直接断言英文串（`1.5 KB · 1 file`），**没有声明语言** ——
      // 它依赖「跑这条之前 Lang 恰好是 en」这个环境状态。2026-10-12 把默认语言
      // 改成中文之后它就必然失败（实测实际值是 `1.5 KB · 1 个文件`），
      // 只是从那以后没人在干净进程里单独跑过 feature_settings，一直没人发现。
      //
      // 修法不是「把期望的英文改成中文」，而是**显式声明语言、两个语档都断言**：
      //   ① 测试不再依赖执行顺序（这是缺陷的根因，不是表面现象）；
      //   ② 顺带把中英两侧的单复数都钉住 —— 本仓单测以中文为第一基准，
      //      但单复数这种 locale 相关行为必须两侧都验，否则「只在中文本地化对了」
      //      这类偏差永远看不见。
      const savedPref: LanguagePreference = Lang.getInstance().getPreference();
      try {
        Lang.getInstance().setLanguage('en');
        expect(formatStorageLabel(1536, 1)).assertEqual('1.5 KB · 1 file');
        expect(formatStorageLabel(1536, 2)).assertEqual('1.5 KB · 2 files');
        expect(formatStorageLabel(1024 * 1024 * 3.5, 128)).assertEqual('3.5 MB · 128 files');

        Lang.getInstance().setLanguage('zh');
        expect(formatStorageLabel(1536, 1)).assertEqual('1.5 KB · 1 个文件');
        expect(formatStorageLabel(1536, 2)).assertEqual('1.5 KB · 2 个文件');
        expect(formatStorageLabel(1024 * 1024 * 3.5, 128)).assertEqual('3.5 MB · 128 个文件');
      } finally {
        // 还原，别把语言状态泄给后面的用例（本文件排在 SettingsReducer 之后，
        // 它自己也会存还偏好，这里同样守规矩）。
        Lang.getInstance().setLanguage(savedPref);
      }
    });

    it('formatStorageLabel_ignoresInvalidFileCount', 0, () => {
      expect(formatStorageLabel(1536, -3)).assertEqual('1.5 KB');
      expect(formatStorageLabel(1536, Number.NaN)).assertEqual('1.5 KB');
    });

    it('formatStorageLabel_localizesUnitWord', 0, () => {
      // I18N-HOTSWITCH-101：单位词是文案不是单位符号，中文侧必须出「个文件」。
      const previous: SupportedLanguage = Lang.getInstance().getLanguage();
      let zhOne: string = '';
      let zhMany: string = '';
      try {
        Lang.getInstance().setSystemLanguage('zh');
        zhOne = formatStorageLabel(1536, 1);
        zhMany = formatStorageLabel(1024 * 1024 * 3.5, 128);
      } finally {
        Lang.getInstance().setSystemLanguage(previous);
      }
      expect(zhOne).assertEqual('1.5 KB · 1 个文件');
      expect(zhMany).assertEqual('3.5 MB · 128 个文件');
    });
  });
}
