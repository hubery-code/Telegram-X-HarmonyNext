/**
 * platform/storage — RdbSqlExecutor：relationalStore.RdbStore → SqlExecutor（PLAT-002）。
 *
 * Kit 与迁移框架之间的薄封装：executeSql/querySql 的 try/catch 转换为
 * Result<_, AppError>（BusinessError 数字码进入 platform/code，retryable=true）。
 */

import relationalStore from '@ohos.data.relationalStore';
import { BusinessError } from '@ohos.base';
import { Result, AppError, ok, err, AppErrors } from '@tgx/core-common';
import { SqlStatement } from '../core/RdbKvStatements';
import { SqlExecutor } from '../core/MigrationRunner';

function asPlatformError(origin: string, e: Object): AppError {
  const be: BusinessError = e as BusinessError;
  if (be !== null && be !== undefined && typeof be.code === 'number') {
    return AppErrors.platform(be.code, `${origin} failed (rdb kit)`, true);
  }
  return AppErrors.unknown(origin, `${origin} failed (non-business error)`);
}

function toKitArgs(args: Array<string | number | boolean | null>): Array<relationalStore.ValueType> {
  const out: Array<relationalStore.ValueType> = [];
  for (const arg of args) {
    out.push(arg);
  }
  return out;
}

export class RdbSqlExecutor implements SqlExecutor {
  private readonly store: relationalStore.RdbStore;

  constructor(store: relationalStore.RdbStore) {
    this.store = store;
  }

  async exec(statement: SqlStatement): Promise<Result<void, AppError>> {
    try {
      await this.store.executeSql(statement.sql, toKitArgs(statement.args));
      return ok(undefined);
    } catch (e) {
      return err(asPlatformError('rdb.executeSql', e));
    }
  }

  /** 查询单行单列整数；无结果行返回 ok(null)。 */
  async queryInteger(statement: SqlStatement): Promise<Result<number | null, AppError>> {
    let resultSet: relationalStore.ResultSet | undefined;
    try {
      resultSet = await this.store.querySql(statement.sql, toKitArgs(statement.args));
    } catch (e) {
      return err(asPlatformError('rdb.query', e));
    }
    if (resultSet === undefined) {
      return err(AppErrors.unknown('rdb.query', 'rdb query returned no result set'));
    }
    try {
      if (!resultSet.goToFirstRow()) {
        return ok(null);
      }
      return ok(resultSet.getLong(0));
    } catch (e) {
      return err(asPlatformError('rdb.query', e));
    } finally {
      try {
        resultSet.close();
      } catch (e) {
        // 关闭失败不影响读取结果；忽略。
      }
    }
  }
}
