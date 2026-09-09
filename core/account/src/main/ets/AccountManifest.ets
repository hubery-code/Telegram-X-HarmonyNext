/**
 * core/account — AccountManifestStore：账号清单的持久化（CORE-003）。
 *
 * 计划 §6.1：冷启动时 AccountRegistry 从持久化描述符批量恢复账号。
 * 清单落在 files/accounts/registry.json，经注入的 AppFilesPort 读写——
 * 本模块不 import 任何文件 Kit，文件系统语义全部归 port（PLAT-001 契约）。
 *
 * 语义约定：
 * - load()：清单不存在（exists=false）→ ok([])（空注册表是合法状态）；
 *   存在但读/解码失败 → err（storage/corrupted 或透传 IO 错误），绝不返回半解析清单；
 * - save() 覆盖写全量（调用方读-改-写）；写失败透传 err；
 * - upsert/remove 为 load+save 的组合便捷方法，remove 不存在 key → ok(false)。
 */

import { AppError, Result, err, ok } from '@tgx/core-common';
import { AppDirs, AppFilesPort } from '@tgx/platform-ports';
import {
  AccountDescriptor,
  decodeAccountManifest,
  encodeAccountManifest
} from './AccountDescriptor';

const MANIFEST_RELATIVE_PATH: string = 'accounts/registry.json';

export class AccountManifestStore {
  private readonly files: AppFilesPort;

  constructor(files: AppFilesPort) {
    this.files = files;
  }

  load(): Result<AccountDescriptor[], AppError> {
    const existsResult: Result<boolean, AppError> = this.files.exists(this.manifestPath());
    if (existsResult.ok === false) {
      return err<AccountDescriptor[], AppError>(existsResult.error);
    }
    if (!existsResult.value) {
      return ok<AccountDescriptor[], AppError>([]);
    }
    const readResult: Result<string, AppError> = this.files.readText(this.manifestPath());
    if (readResult.ok === false) {
      return err<AccountDescriptor[], AppError>(readResult.error);
    }
    return decodeAccountManifest(readResult.value);
  }

  save(descriptors: AccountDescriptor[]): Result<void, AppError> {
    const writeResult: Result<void, AppError> = this.files.writeText(this.manifestPath(), encodeAccountManifest(descriptors));
    if (writeResult.ok === false) {
      return err<void, AppError>(writeResult.error);
    }
    return ok<void, AppError>(undefined);
  }

  /** 插入或按 accountKey 替换；load/save 失败透传 err。 */
  upsert(descriptor: AccountDescriptor): Result<void, AppError> {
    const loaded: Result<AccountDescriptor[], AppError> = this.load();
    if (loaded.ok === false) {
      return err<void, AppError>(loaded.error);
    }
    const next: AccountDescriptor[] = [];
    let replaced: boolean = false;
    for (const existing of loaded.value) {
      if (existing.accountKey === descriptor.accountKey) {
        next.push(descriptor);
        replaced = true;
      } else {
        next.push(existing);
      }
    }
    if (!replaced) {
      next.push(descriptor);
    }
    return this.save(next);
  }

  /** 移除指定 key；不存在返回 ok(false)。 */
  remove(accountKey: string): Result<boolean, AppError> {
    const loaded: Result<AccountDescriptor[], AppError> = this.load();
    if (loaded.ok === false) {
      return err<boolean, AppError>(loaded.error);
    }
    const next: AccountDescriptor[] = [];
    let removed: boolean = false;
    for (const existing of loaded.value) {
      if (existing.accountKey === accountKey) {
        removed = true;
      } else {
        next.push(existing);
      }
    }
    if (!removed) {
      return ok<boolean, AppError>(false);
    }
    const saved: Result<void, AppError> = this.save(next);
    if (saved.ok === false) {
      return err<boolean, AppError>(saved.error);
    }
    return ok<boolean, AppError>(true);
  }

  /** 清单的沙盒内绝对路径（经 port 解析，越界会被 port 拒绝）。 */
  manifestPath(): string {
    const resolved: Result<string, AppError> = this.files.resolve(AppDirs.files(), MANIFEST_RELATIVE_PATH);
    if (resolved.ok === false) {
      return MANIFEST_RELATIVE_PATH;
    }
    return resolved.value;
  }
}
