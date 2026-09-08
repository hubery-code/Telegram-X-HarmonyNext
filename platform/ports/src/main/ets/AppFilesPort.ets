/**
 * platform/ports — AppFilesPort 应用文件/目录契约（PLAT-001）。
 *
 * 对应计划 §5.6 目录约定（filesDir 下 accounts/<key>/…、cacheDir 下 thumbnails 等）。
 * 生产实现由 platform/files 适配层基于 HarmonyOS 文件 Kit / context 目录提供。
 *
 * 语义约定：
 * - 路径安全：所有传入的相对路径不得逃逸对应目录根（拒绝 '..' 越界与绝对路径），
 *   违规返回 err(parameter/invalid)，绝不静默落到沙盒外；
 * - 路径分隔统一 '/'；resolve 返回规范化的沙盒内路径字符串；
 * - write 原子性约定：生产实现应先写临时文件再 rename（adapter 文档须声明），
 *   Fake 直接落内存但对外语义一致；
 * - read/delete 对不存在路径：read 返回 err(storage/io)，delete 返回 ok(false)；
 * - 空间查询为目录所属文件系统语义，Fake 用可注入的配额模型模拟；
 * - 错误统一 Result<_, AppError>。
 */

import { Result, AppError } from '@tgx/core-common';

/** 应用标准目录根（计划 §5.6 的两级目录模型）。 */
export type AppRoot = 'files' | 'cache';

/**
 * 应用标准目录：files/cache 根 + 可选子目录。
 * 构造请用 AppDirs 工厂（ArkTS 不允许对象字面量类型联合）。
 */
export interface AppDirectory {
  readonly root: AppRoot;
  /** 子目录相对路径；null 表示根本身。不得含越界段。 */
  readonly sub: string | null;
}

export class AppDirs {
  static files(): AppDirectory {
    return { root: 'files', sub: null };
  }

  static cache(): AppDirectory {
    return { root: 'cache', sub: null };
  }

  static filesSub(sub: string): AppDirectory {
    return { root: 'files', sub: sub };
  }

  static cacheSub(sub: string): AppDirectory {
    return { root: 'cache', sub: sub };
  }
}

/** 文件元信息。 */
export interface FileInfo {
  readonly sizeBytes: number;
  readonly lastModifiedMillis: number;
}

export interface AppFilesPort {
  /**
   * 解析目录 + 相对路径为规范化沙盒内路径。
   * 拒绝：空路径、绝对路径、含 '..' 越界段。
   */
  resolve(dir: AppDirectory, relativePath: string): Result<string, AppError>;

  /** 读字节；不存在或读取失败返回 err。 */
  readBytes(path: string): Result<Uint8Array, AppError>;

  /** 写字节（父目录自动创建）；配额不足返回 err(storage/quota_exceeded)。 */
  writeBytes(path: string, data: Uint8Array): Result<void, AppError>;

  /** 读文本（UTF-8）。 */
  readText(path: string): Result<string, AppError>;

  /** 写文本（UTF-8）。 */
  writeText(path: string, text: string): Result<void, AppError>;

  /** 删除文件；返回是否实际删除了已存在的文件。 */
  delete(path: string): Result<boolean, AppError>;

  /** 是否存在。 */
  exists(path: string): Result<boolean, AppError>;

  /** 元信息；不存在返回 err。 */
  stat(path: string): Result<FileInfo, AppError>;

  /** 目录内（或文件系统）剩余可写字节数。 */
  freeSpaceBytes(dir: AppDirectory): Result<number, AppError>;

  /** 目录所属文件系统总字节数。 */
  totalSpaceBytes(dir: AppDirectory): Result<number, AppError>;
}
