/**
 * platform/files — AppFilesPort 的 HarmonyOS File Kit adapter（PLAT-005）。
 *
 * 对应计划 §5.6 目录约定（filesDir 下 accounts/<key>/…、cacheDir 下 thumbnails 等）。
 * 基于 @kit.CoreFileKit（fileIo + statfs）提供同步文件读写、原子写入、路径安全解析。
 *
 * 原子性约定（adapter 文档）：
 * - writeBytes/writeText 先写 .tmp 临时文件，成功后 rename 到目标路径；
 * - 若 rename 前发生异常，临时文件会被尽力清理；
 * - rename 是原子的（同分区下），保证读者不会看到部分写入。
 *
 * 路径安全：
 * - resolve 拒绝空路径、绝对路径、含 '..' 的路径段；
 * - sub 目录同样校验。
 *
 * 错误映射：
 * - Kit 抛出的 BusinessError 数字码 → storage/io（retryable=false）；
 * - ENOENT (13900002) 在 delete/exists 中特殊处理：delete→ok(false)，exists→ok(false)。
 */

import { fileIo as fs, statfs } from '@kit.CoreFileKit';
import { buffer } from '@kit.ArkTS';
import { BusinessError } from '@ohos.base';
import { Result, AppError, ok, err, AppErrors } from '@tgx/core-common';
import { AppFilesPort, AppDirectory, AppRoot, FileInfo } from '@tgx/platform-ports';

const ENOENT: number = 13900002;

function asStorageError(origin: string, e: Object): AppError {
  const be: BusinessError = e as BusinessError;
  if (be !== null && be !== undefined && typeof be.code === 'number') {
    return AppErrors.storage('io', `${origin} failed`, false, undefined, `${be.code}:${be.message}`);
  }
  return AppErrors.unknown(origin, `${origin} failed (non-business error)`);
}

function isEnoent(e: Object): boolean {
  const be: BusinessError = e as BusinessError;
  return be !== null && be !== undefined && be.code === ENOENT;
}

function isUnsafePath(path: string): boolean {
  if (path.length === 0) {
    return true;
  }
  if (path.startsWith('/')) {
    return true;
  }
  const segments: string[] = path.split('/');
  for (let i = 0; i < segments.length; i++) {
    if (segments[i] === '..') {
      return true;
    }
  }
  return false;
}

function joinPath(base: string, part1: string, part2: string): string {
  let result: string = base;
  if (result.endsWith('/')) {
    result = result + part1;
  } else {
    result = result + '/' + part1;
  }
  if (part2.length === 0) {
    return result;
  }
  if (result.endsWith('/')) {
    result = result + part2;
  } else {
    result = result + '/' + part2;
  }
  return result;
}

function joinPathSimple(base: string, part: string): string {
  if (part.length === 0) {
    return base;
  }
  if (base.endsWith('/')) {
    return base + part;
  }
  return base + '/' + part;
}

function ensureParentDir(path: string): void {
  const lastSlash: number = path.lastIndexOf('/');
  if (lastSlash <= 0) {
    return;
  }
  const parentDir: string = path.substring(0, lastSlash);
  try {
    fs.mkdirSync(parentDir, true);
  } catch (e) {
    // Ignore — directory likely already exists
  }
}

function toByteArray(data: Uint8Array): ArrayBuffer {
  const ab: ArrayBuffer = new ArrayBuffer(data.length);
  const dst: Uint8Array = new Uint8Array(ab);
  for (let i = 0; i < data.length; i++) {
    dst[i] = data[i];
  }
  return ab;
}

export class HarmonyAppFilesAdapter implements AppFilesPort {
  private readonly filesDir: string;
  private readonly cacheDir: string;

  constructor(filesDir: string, cacheDir: string) {
    this.filesDir = filesDir;
    this.cacheDir = cacheDir;
  }

  private rootPath(root: AppRoot): string {
    return root === 'files' ? this.filesDir : this.cacheDir;
  }

  resolve(dir: AppDirectory, relativePath: string): Result<string, AppError> {
    if (isUnsafePath(relativePath)) {
      return err(AppErrors.parameter('invalid', 'relativePath', 'empty, absolute, or contains ".." traversal'));
    }
    const root: string = this.rootPath(dir.root);
    if (dir.sub !== null) {
      if (isUnsafePath(dir.sub)) {
        return err(AppErrors.parameter('invalid', 'sub', 'sub directory is empty, absolute, or contains ".." traversal'));
      }
      return ok(joinPath(root, dir.sub, relativePath));
    }
    return ok(joinPathSimple(root, relativePath));
  }

  readBytes(path: string): Result<Uint8Array, AppError> {
    try {
      const file: fs.File = fs.openSync(path, fs.OpenMode.READ_ONLY);
      try {
        const stat: fs.Stat = fs.statSync(file.fd);
        const arrayBuffer: ArrayBuffer = new ArrayBuffer(stat.size);
        const bytesRead: number = fs.readSync(file.fd, arrayBuffer);
        const result: Uint8Array = new Uint8Array(arrayBuffer, 0, bytesRead);
        return ok(result);
      } finally {
        try {
          fs.closeSync(file);
        } catch (closeErr) {
          // suppress close errors
        }
      }
    } catch (e) {
      return err(asStorageError('readBytes', e));
    }
  }

  writeBytes(path: string, data: Uint8Array): Result<void, AppError> {
    ensureParentDir(path);
    const tempPath: string = path + '.tmp';
    try {
      const file: fs.File = fs.openSync(tempPath,
        fs.OpenMode.WRITE_ONLY | fs.OpenMode.CREATE | fs.OpenMode.TRUNC);
      try {
        const arrayBuffer: ArrayBuffer = toByteArray(data);
        fs.writeSync(file.fd, arrayBuffer);
      } finally {
        try {
          fs.closeSync(file);
        } catch (closeErr) {
          // suppress close errors
        }
      }
      fs.renameSync(tempPath, path);
      return ok(undefined);
    } catch (e) {
      try {
        fs.unlinkSync(tempPath);
      } catch (cleanupErr) {
        // best-effort cleanup
      }
      return err(asStorageError('writeBytes', e));
    }
  }

  readText(path: string): Result<string, AppError> {
    return this.readBytes(path).flatMap<string>((bytes: Uint8Array): Result<string, AppError> => {
      const decoded: string = buffer.from(bytes).toString('utf-8');
      return ok<string, AppError>(decoded);
    });
  }

  writeText(path: string, text: string): Result<void, AppError> {
    const encoded: buffer.Buffer = buffer.from(text, 'utf-8');
    const data: Uint8Array = new Uint8Array(encoded.length);
    for (let i = 0; i < encoded.length; i++) {
      data[i] = encoded[i];
    }
    return this.writeBytes(path, data);
  }

  delete(path: string): Result<boolean, AppError> {
    try {
      fs.unlinkSync(path);
      return ok(true);
    } catch (e) {
      if (isEnoent(e)) {
        return ok(false);
      }
      return err(asStorageError('delete', e));
    }
  }

  exists(path: string): Result<boolean, AppError> {
    try {
      const result: boolean = fs.accessSync(path);
      return ok(result);
    } catch (e) {
      if (isEnoent(e)) {
        return ok(false);
      }
      return err(asStorageError('exists', e));
    }
  }

  stat(path: string): Result<FileInfo, AppError> {
    try {
      const fileStat: fs.Stat = fs.statSync(path);
      const info: FileInfo = {
        sizeBytes: fileStat.size,
        lastModifiedMillis: fileStat.mtime * 1000
      };
      return ok(info);
    } catch (e) {
      return err(asStorageError('stat', e));
    }
  }

  freeSpaceBytes(dir: AppDirectory): Result<number, AppError> {
    try {
      const root: string = this.rootPath(dir.root);
      const path: string = dir.sub !== null
        ? joinPathSimple(root, dir.sub)
        : root;
      const freeBytes: number = statfs.getFreeSizeSync(path);
      return ok(freeBytes);
    } catch (e) {
      return err(asStorageError('freeSpaceBytes', e));
    }
  }

  totalSpaceBytes(dir: AppDirectory): Result<number, AppError> {
    try {
      const root: string = this.rootPath(dir.root);
      const path: string = dir.sub !== null
        ? joinPathSimple(root, dir.sub)
        : root;
      const totalBytes: number = statfs.getTotalSizeSync(path);
      return ok(totalBytes);
    } catch (e) {
      return err(asStorageError('totalSpaceBytes', e));
    }
  }
}
