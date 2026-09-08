/**
 * platform/ports — FakeAppFiles（PLAT-001）。
 *
 * AppFilesPort 的内存实现，模拟沙盒文件系统语义：
 * - resolve 做规范化并拒绝 '..' 越界 / 绝对路径 / 空路径；
 * - write 覆盖写、父目录自动创建；read/delete/exists/stat 按路径精确匹配；
 * - 配额模型：totalSpaceBytes 可注入（默认 64 MiB），
 *   freeSpaceBytes = total - 已用；write 超出配额返回 err(storage/quota_exceeded)；
 * - delete 返回是否实际删除；read 不存在路径返回 err(storage/io)。
 *
 * 注意：Fake 不做真实目录建模（目录只是路径前缀），
 * 生产 adapter 如暴露目录列举能力，需在契约变更中另行扩展。
 */

import { Result, AppError, ok, err, AppErrors } from '@tgx/core-common';
import { AppDirectory, FileInfo, AppFilesPort } from '../AppFilesPort';

const DEFAULT_TOTAL_SPACE: number = 64 * 1024 * 1024;

export class FakeAppFiles implements AppFilesPort {
  private readonly files: Map<string, Uint8Array> = new Map();
  private readonly modified: Map<string, number> = new Map();
  private readonly roots: Map<string, string> = new Map();
  private totalSpace: number = DEFAULT_TOTAL_SPACE;
  private clockMillis: number = 0;

  constructor(totalSpaceBytes?: number) {
    if (totalSpaceBytes !== undefined) {
      this.totalSpace = totalSpaceBytes;
    }
    this.roots.set('files', '/sandbox/files');
    this.roots.set('cache', '/sandbox/cache');
  }

  /** 测试驱动：推进 Fake 的文件修改时间。 */
  setClockMillis(millis: number): void {
    this.clockMillis = millis;
  }

  resolve(dir: AppDirectory, relativePath: string): Result<string, AppError> {
    const baseResult: Result<string, AppError> = this.dirBase(dir);
    if (baseResult.ok === false) {
      return err(baseResult.error);
    }
    const normalizedResult: Result<string, AppError> = this.normalize(relativePath);
    if (normalizedResult.ok === false) {
      return err(normalizedResult.error);
    }
    return ok(`${baseResult.value}/${normalizedResult.value}`);
  }

  readBytes(path: string): Result<Uint8Array, AppError> {
    const data: Uint8Array | undefined = this.files.get(path);
    if (data === undefined) {
      return err(AppErrors.storage('io', `file not found: ${path}`, false));
    }
    return ok(data.slice());
  }

  writeBytes(path: string, data: Uint8Array): Result<void, AppError> {
    const usage: number = this.usedBytes();
    const existingData: Uint8Array | undefined = this.files.get(path);
    const existing: number = existingData === undefined ? 0 : existingData.length;
    if (usage - existing + data.length > this.totalSpace) {
      return err(AppErrors.storage('quota_exceeded', `write of ${data.length} bytes exceeds quota`, true));
    }
    this.files.set(path, data.slice());
    this.modified.set(path, this.clockMillis);
    return ok(undefined);
  }

  readText(path: string): Result<string, AppError> {
    const bytes: Result<Uint8Array, AppError> = this.readBytes(path);
    if (bytes.ok === false) {
      return err(bytes.error);
    }
    return ok(this.decodeUtf8(bytes.value));
  }

  writeText(path: string, text: string): Result<void, AppError> {
    return this.writeBytes(path, this.encodeUtf8(text));
  }

  delete(path: string): Result<boolean, AppError> {
    if (!this.files.has(path)) {
      return ok(false);
    }
    this.files.delete(path);
    this.modified.delete(path);
    return ok(true);
  }

  exists(path: string): Result<boolean, AppError> {
    return ok(this.files.has(path));
  }

  stat(path: string): Result<FileInfo, AppError> {
    const data: Uint8Array | undefined = this.files.get(path);
    if (data === undefined) {
      return err(AppErrors.storage('io', `stat on missing file: ${path}`, false));
    }
    const modified: number | undefined = this.modified.get(path);
    return ok<FileInfo, AppError>({ sizeBytes: data.length, lastModifiedMillis: modified === undefined ? 0 : modified });
  }

  freeSpaceBytes(dir: AppDirectory): Result<number, AppError> {
    const baseResult: Result<string, AppError> = this.dirBase(dir);
    if (baseResult.ok === false) {
      return err(baseResult.error);
    }
    return ok(this.totalSpace - this.usedBytes());
  }

  totalSpaceBytes(dir: AppDirectory): Result<number, AppError> {
    const baseResult: Result<string, AppError> = this.dirBase(dir);
    if (baseResult.ok === false) {
      return err(baseResult.error);
    }
    return ok(this.totalSpace);
  }

  private usedBytes(): number {
    let total: number = 0;
    this.files.forEach((data: Uint8Array) => {
      total += data.length;
    });
    return total;
  }

  private dirBase(dir: AppDirectory): Result<string, AppError> {
    if (dir.sub === null) {
      return this.rootBase(dir.root);
    }
    return this.subBase(dir.root, dir.sub);
  }

  private rootBase(rootKind: string): Result<string, AppError> {
    const root: string | undefined = this.roots.get(rootKind);
    if (root === undefined) {
      return err(AppErrors.internal('AppFilesPort.rootBase', `missing root: ${rootKind}`));
    }
    return ok(root);
  }

  private subBase(rootKind: string, sub: string): Result<string, AppError> {
    const normalized: Result<string, AppError> = this.normalize(sub);
    if (normalized.ok === false) {
      return err(normalized.error);
    }
    const rootResult: Result<string, AppError> = this.rootBase(rootKind);
    if (rootResult.ok === false) {
      return err(rootResult.error);
    }
    return ok(`${rootResult.value}/${normalized.value}`);
  }

  /** 规范化相对路径：拒绝空、绝对、'.'、'..' 越界；返回不含首尾 '/' 的路径。 */
  private normalize(path: string): Result<string, AppError> {
    if (path.length === 0) {
      return err(AppErrors.parameter('missing', 'path', 'empty path'));
    }
    if (path.startsWith('/')) {
      return err(AppErrors.parameter('invalid', 'path', `absolute path not allowed: ${path}`));
    }
    const segments: string[] = path.split('/');
    const out: string[] = [];
    for (const segment of segments) {
      if (segment.length === 0 || segment === '.') {
        continue;
      }
      if (segment === '..') {
        return err(AppErrors.parameter('invalid', 'path', `path escapes sandbox root: ${path}`));
      }
      out.push(segment);
    }
    if (out.length === 0) {
      return err(AppErrors.parameter('invalid', 'path', `path resolves to root: ${path}`));
    }
    return ok(out.join('/'));
  }

  private encodeUtf8(text: string): Uint8Array {
    const bytes: number[] = [];
    for (let i = 0; i < text.length; i++) {
      let code: number = text.charCodeAt(i);
      if (code < 0x80) {
        bytes.push(code);
      } else if (code < 0x800) {
        bytes.push(0xc0 | (code >> 6), 0x80 | (code & 0x3f));
      } else if (code >= 0xd800 && code <= 0xdbff && i + 1 < text.length) {
        const next: number = text.charCodeAt(i + 1);
        if (next >= 0xdc00 && next <= 0xdfff) {
          code = 0x10000 + ((code - 0xd800) << 10) + (next - 0xdc00);
          bytes.push(
            0xf0 | (code >> 18),
            0x80 | ((code >> 12) & 0x3f),
            0x80 | ((code >> 6) & 0x3f),
            0x80 | (code & 0x3f)
          );
          i++;
          continue;
        }
        bytes.push(0xef, 0xbf, 0xbd);
      } else if (code >= 0xd800 && code <= 0xdfff) {
        bytes.push(0xef, 0xbf, 0xbd);
      } else {
        bytes.push(
          0xe0 | (code >> 12),
          0x80 | ((code >> 6) & 0x3f),
          0x80 | (code & 0x3f)
        );
      }
    }
    const out: Uint8Array = new Uint8Array(bytes.length);
    out.set(bytes);
    return out;
  }

  private decodeUtf8(data: Uint8Array): string {
    let out: string = '';
    let i: number = 0;
    while (i < data.length) {
      const b0: number = data[i];
      if (b0 < 0x80) {
        out += String.fromCharCode(b0);
        i += 1;
      } else if (b0 < 0xe0 && i + 1 < data.length) {
        out += String.fromCharCode(((b0 & 0x1f) << 6) | (data[i + 1] & 0x3f));
        i += 2;
      } else if (b0 < 0xf0 && i + 2 < data.length) {
        out += String.fromCharCode(((b0 & 0x0f) << 12) | ((data[i + 1] & 0x3f) << 6) | (data[i + 2] & 0x3f));
        i += 3;
      } else if (i + 3 < data.length) {
        let code: number = ((b0 & 0x07) << 18) | ((data[i + 1] & 0x3f) << 12)
          | ((data[i + 2] & 0x3f) << 6) | (data[i + 3] & 0x3f);
        code -= 0x10000;
        out += String.fromCharCode(0xd800 + (code >> 10), 0xdc00 + (code & 0x3ff));
        i += 4;
      } else {
        i += 1;
      }
    }
    return out;
  }
}
