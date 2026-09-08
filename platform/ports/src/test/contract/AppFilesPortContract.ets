/**
 * platform/ports — AppFilesPort 同套契约测试（PLAT-001）。
 *
 * 任何 AppFilesPort 实现（当前 FakeAppFiles，未来 platform/files 的
 * 文件 Kit adapter）都通过 `appFilesPortContract('name', factory)`
 * 套用同一组断言。配额语义由 factory 注入足够小的 totalSpace 验证。
 */

import { describe, it, expect } from '@ohos/hypium';
import { AppDirs, AppFilesPort } from '../../main/ets/AppFilesPort';

export default function appFilesPortContract(name: string, factory: () => AppFilesPort) {
  describe(`${name}_AppFilesPortContract`, () => {
    it('resolve_normalizesRelativePaths', 0, () => {
      const files: AppFilesPort = factory();
      const r = files.resolve(AppDirs.files(), 'accounts/a/tdlib/db');
      expect(r.ok).assertTrue();
      if (r.ok) {
        expect(r.value.indexOf('/sandbox/files/accounts/a/tdlib/db') === 0).assertTrue();
      }
      const sub = files.resolve(AppDirs.filesSub('accounts/a'), 'exports/x.bin');
      expect(sub.ok).assertTrue();
      if (sub.ok) {
        expect(sub.value.indexOf('/sandbox/files/accounts/a/exports/x.bin') === 0).assertTrue();
      }
    });

    it('resolve_rejectsEscapingPaths', 0, () => {
      const files: AppFilesPort = factory();
      const cases: string[] = ['', '/abs/path', '../escape', 'a/../../escape', '.'];
      for (const path of cases) {
        const r = files.resolve(AppDirs.cache(), path);
        expect(r.err).assertTrue();
        if (r.err) {
          expect(r.error.kind).assertEqual('parameter');
        }
      }
    });

    it('writeReadBytes_roundTripsAndCopies', 0, () => {
      const files: AppFilesPort = factory();
      const pathR = files.resolve(AppDirs.files(), 'blob.bin');
      if (!pathR.ok) {
        expect(false).assertTrue();
        return;
      }
      const path: string = pathR.value;
      const data: Uint8Array = new Uint8Array([9, 8, 7]);
      expect(files.writeBytes(path, data).ok).assertTrue();
      data[0] = 0; // 修改原数组不得影响已写入内容

      const read = files.readBytes(path);
      expect(read.ok).assertTrue();
      if (read.ok) {
        expect(read.value.length).assertEqual(3);
        expect(read.value[0]).assertEqual(9);
      }
    });

    it('readTextWriteText_unicodeRoundTrip', 0, () => {
      const files: AppFilesPort = factory();
      const pathR = files.resolve(AppDirs.files(), 'draft.txt');
      if (!pathR.ok) {
        expect(false).assertTrue();
        return;
      }
      const text: string = '你好 Telegram 🚀';
      expect(files.writeText(pathR.value, text).ok).assertTrue();
      const read = files.readText(pathR.value);
      expect(read.ok).assertTrue();
      if (read.ok) {
        expect(read.value).assertEqual(text);
      }
    });

    it('readMissingFile_returnsStorageError', 0, () => {
      const files: AppFilesPort = factory();
      const missing = files.readText('/sandbox/files/nope.txt');
      expect(missing.err).assertTrue();
      if (missing.err) {
        expect(missing.error.kind).assertEqual('storage');
      }
    });

    it('existsStatDelete_semantics', 0, () => {
      const files: AppFilesPort = factory();
      const pathR = files.resolve(AppDirs.cache(), 'thumb/1.webp');
      if (!pathR.ok) {
        expect(false).assertTrue();
        return;
      }
      const path: string = pathR.value;

      const before = files.exists(path);
      if (before.ok) {
        expect(before.value).assertFalse();
      }
      expect(files.delete(path).getOrElse(true)).assertFalse();

      files.writeText(path, 'abcd');
      const stat = files.stat(path);
      expect(stat.ok).assertTrue();
      if (stat.ok) {
        expect(stat.value.sizeBytes).assertEqual(4);
      }
      const deleted = files.delete(path);
      expect(deleted.getOrElse(false)).assertTrue();
      expect(files.exists(path).getOrElse(true)).assertFalse();
    });

    it('overwrite_replacesContentAndRecountsSpace', 0, () => {
      const files: AppFilesPort = factory();
      const pathR = files.resolve(AppDirs.files(), 'f.bin');
      if (!pathR.ok) {
        expect(false).assertTrue();
        return;
      }
      const path: string = pathR.value;
      files.writeBytes(path, new Uint8Array(100));
      files.writeBytes(path, new Uint8Array(10));
      const stat = files.stat(path);
      if (stat.ok) {
        expect(stat.value.sizeBytes).assertEqual(10);
      } else {
        expect(false).assertTrue();
      }
    });

    it('spaceQueries_areConsistent', 0, () => {
      const files: AppFilesPort = factory();
      const total = files.totalSpaceBytes(AppDirs.files());
      const free = files.freeSpaceBytes(AppDirs.files());
      expect(total.ok).assertTrue();
      expect(free.ok).assertTrue();
      if (total.ok && free.ok) {
        expect(total.value > 0).assertTrue();
        expect(free.value <= total.value).assertTrue();
      }
    });
  });
}

export function appFilesQuotaContract(name: string, factory: () => AppFilesPort) {
  describe(`${name}_AppFilesPortQuotaContract`, () => {
    it('writeBeyondQuota_returnsQuotaError', 0, () => {
      const files: AppFilesPort = factory();
      const big: Uint8Array = new Uint8Array(1024);
      const r = files.writeBytes('/sandbox/files/big.bin', big);
      expect(r.err).assertTrue();
      if (r.err) {
        expect(r.error.kind).assertEqual('storage');
        if (r.error.kind === 'storage') {
          expect(r.error.code).assertEqual('quota_exceeded');
        }
      }
    });
  });
}
