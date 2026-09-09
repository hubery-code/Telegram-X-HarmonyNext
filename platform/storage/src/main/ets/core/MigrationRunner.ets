/**
 * platform/storage — schema migration 执行器（PLAT-002，纯 ArkTS）。
 *
 * 中断安全（验收「中断测试」的结构基础）：
 * - 每完成一个迁移步骤，先把版本标记推进到该步骤的目标版本，再进入下一步；
 * - 任一条语句失败 → 立即返回 err，版本标记停留在最后一个完成步骤的版本；
 * - 重新 open 时从存储的版本续跑剩余步骤（调用方负责保证步骤语句幂等或
 *   借助事务回滚，见 RdbPreferencesAdapter 的事务包装）。
 *
 * SqlExecutor 是唯一的底层抽象：生产实现包装 relationalStore.RdbStore，
 * 单测用可注入失败的 fake 模拟「写一半失败 / 版本跳跃」。
 */

import { Result, AppError, ok, err } from '@tgx/core-common';
import { SqlStatement } from './RdbKvStatements';
import { MigrationStep, PlannedMigrations, planMigrations } from './MigrationPlan';

export interface SqlExecutor {
  exec(statement: SqlStatement): Promise<Result<void, AppError>>;
}

/**
 * 从 fromVersion 迁移到 toVersion（可升可降）；返回最终版本（成功时恒等于 toVersion）。
 * fromVersion === toVersion 时为空操作，返回 ok(fromVersion)。
 */
export async function runMigrations(
  executor: SqlExecutor,
  available: MigrationStep[],
  fromVersion: number,
  toVersion: number,
  versionStatement: (version: number) => SqlStatement
): Promise<Result<number, AppError>> {
  const planned: Result<PlannedMigrations, AppError> =
    planMigrations(available, fromVersion, toVersion);
  let cursor: number = fromVersion;
  if (planned.ok) {
    for (const step of planned.value.steps) {
      const statements: SqlStatement[] = planned.value.direction === 'up' ? step.up : step.down;
      for (const statement of statements) {
        const executed: Result<void, AppError> = await executor.exec(statement);
        if (executed.err) {
          return err(executed.error);
        }
      }
      cursor = planned.value.direction === 'up' ? step.toVersion : step.fromVersion;
      const marked: Result<void, AppError> = await executor.exec(versionStatement(cursor));
      if (marked.err) {
        return err(marked.error);
      }
    }
    return ok(cursor);
  }
  if (planned.err) {
    return err(planned.error);
  }
  return ok(cursor);
}
