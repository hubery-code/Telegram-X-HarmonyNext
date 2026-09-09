/**
 * core/account — 账号目录描述（CORE-003）。
 *
 * 计划 §5.6 目录模型：files/accounts/<account-key>/{tdlib/db, tdlib/files, exports}。
 * 本模块只产出 AppDirectory 描述（经 AppFilesPort 注入后由 port 解析/读写），
 * 绝不直接触碰文件系统。accountKey 校验在这里完成（持久化路径安全的第一道闸）：
 * 拒绝空、含路径分隔符或 '..' 的 key——这类 key 无法安全映射进沙盒子目录。
 */

import { AppError, AppErrors, Result, err, ok } from '@tgx/core-common';
import { AppDirectory, AppDirs } from '@tgx/platform-ports';

export interface AccountDirectoryLayout {
  readonly accountKey: string;
  /** files/accounts/<key> —— 账号数据目录根。 */
  readonly accountDir: AppDirectory;
  /** files/accounts/<key>/tdlib/db —— TDLib 数据库目录。 */
  readonly tdlibDbDir: AppDirectory;
  /** files/accounts/<key>/tdlib/files —— TDLib 文件目录。 */
  readonly tdlibFilesDir: AppDirectory;
  /** files/accounts/<key>/exports —— 导出产出目录。 */
  readonly exportsDir: AppDirectory;
}

/** accountKey → 目录布局。key 非法返回 err(parameter/invalid)，不产生任何部分结果。 */
export function buildAccountDirectories(accountKey: string): Result<AccountDirectoryLayout, AppError> {
  const keyError: AppError | null = validateAccountKey(accountKey);
  if (keyError !== null) {
    return err<AccountDirectoryLayout, AppError>(keyError);
  }
  const base: string = `accounts/${accountKey}`;
  const layout: AccountDirectoryLayout = {
    accountKey: accountKey,
    accountDir: AppDirs.filesSub(base),
    tdlibDbDir: AppDirs.filesSub(`${base}/tdlib/db`),
    tdlibFilesDir: AppDirs.filesSub(`${base}/tdlib/files`),
    exportsDir: AppDirs.filesSub(`${base}/exports`)
  };
  return ok<AccountDirectoryLayout, AppError>(layout);
}

/** key 规则：非空、不含 '/' '\\'、不含 '..' 段、不为 '.'。 */
export function validateAccountKey(accountKey: string): AppError | null {
  if (accountKey.length === 0) {
    return AppErrors.parameter('missing', 'accountKey', 'accountKey must not be empty');
  }
  if (accountKey.indexOf('/') >= 0 || accountKey.indexOf('\\') >= 0) {
    return AppErrors.parameter('invalid', 'accountKey', `accountKey must not contain path separators: ${accountKey}`);
  }
  if (accountKey === '.' || accountKey.indexOf('..') >= 0) {
    return AppErrors.parameter('invalid', 'accountKey', `accountKey must not contain dot segments: ${accountKey}`);
  }
  return null;
}
