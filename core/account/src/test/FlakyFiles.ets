/**
 * 测试用注入失败 Fake：在 FakeAppFiles 基础上支持单点写/读失败，
 * 覆盖 manifest 持久化失败（create 回滚、close 保留）与清单读取失败路径。
 */

import { AppError, AppErrors, Result, err } from '@tgx/core-common';
import { FakeAppFiles } from '@tgx/platform-ports';

export class FlakyFiles extends FakeAppFiles {
  failNextWriteFlag: boolean = false;
  failNextReadFlag: boolean = false;
  writtenTextCount: number = 0;

  override writeText(path: string, text: string): Result<void, AppError> {
    if (this.failNextWriteFlag) {
      this.failNextWriteFlag = false;
      return err<void, AppError>(AppErrors.storage('io', 'flaky write failure', true));
    }
    this.writtenTextCount += 1;
    return super.writeText(path, text);
  }

  override readText(path: string): Result<string, AppError> {
    if (this.failNextReadFlag) {
      this.failNextReadFlag = false;
      return err<string, AppError>(AppErrors.storage('io', 'flaky read failure', true));
    }
    return super.readText(path);
  }
}
