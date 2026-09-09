/**
 * platform/storage — schema migration 规划（PLAT-002，纯 ArkTS）。
 *
 * 版本模型：正整数线性版本链，每步 MigrationStep 只连接相邻版本
 * （fromVersion -> fromVersion+1），同时携带 up/down 两套语句：
 * - 升级路径：应用升级时按 up 语句逐版本前进；
 * - 回滚路径：应用降级（新装旧版）时按 down 语句逐版本后退；
 * - 某一步缺少目标方向的语句 → 规划失败，err(storage/migration)。
 *
 * planMigrations 只负责算出有序步骤列表，不执行；执行见 MigrationRunner。
 */

import { Result, AppError, ok, err, AppErrors } from '@tgx/core-common';
import { SqlStatement } from './RdbKvStatements';

export interface MigrationStep {
  readonly fromVersion: number;
  /** 恒等于 fromVersion + 1（线性版本链）。 */
  readonly toVersion: number;
  /** 升级语句（按序执行）。 */
  readonly up: SqlStatement[];
  /** 回滚语句（按序执行）；不支持回滚的步骤置空数组。 */
  readonly down: SqlStatement[];
}

export type MigrationDirection = 'up' | 'down';

export interface PlannedMigrations {
  readonly direction: MigrationDirection;
  readonly steps: MigrationStep[];
}

/** 防呆上限：版本链不可能超过该长度（阻断环/脏数据导致的死循环）。 */
const MAX_CHAIN_LENGTH: number = 1000;

function isValidVersion(version: number): boolean {
  return Number.isInteger(version) && version >= 1;
}

export function planMigrations(
  available: MigrationStep[],
  fromVersion: number,
  toVersion: number
): Result<PlannedMigrations, AppError> {
  if (!isValidVersion(fromVersion) || !isValidVersion(toVersion)) {
    return err(AppErrors.parameter('out_of_range', 'version',
      `versions must be positive integers, got ${fromVersion} -> ${toVersion}`));
  }
  if (fromVersion === toVersion) {
    const noOp: PlannedMigrations = { direction: 'up', steps: [] };
    return ok(noOp);
  }
  const direction: MigrationDirection = fromVersion < toVersion ? 'up' : 'down';
  const steps: MigrationStep[] = [];
  const visited: Set<number> = new Set();
  let cursor: number = fromVersion;
  while (cursor !== toVersion) {
    if (visited.has(cursor)) {
      return err(AppErrors.internal('migration-cycle',
        `migration chain revisits version ${cursor}`, undefined));
    }
    visited.add(cursor);
    const next: number = direction === 'up' ? cursor + 1 : cursor - 1;
    let found: MigrationStep | undefined;
    for (const step of available) {
      if (direction === 'up' && step.fromVersion === cursor && step.toVersion === next) {
        found = step;
        break;
      }
      if (direction === 'down' && step.toVersion === cursor && step.fromVersion === next) {
        found = step;
        break;
      }
    }
    if (found === undefined) {
      return err(AppErrors.storage('migration',
        `no ${direction} path between schema version ${cursor} and ${next}`, false));
    }
    if (direction === 'down' && found.down.length === 0 && found.up.length > 0) {
      return err(AppErrors.storage('migration',
        `schema step ${found.fromVersion} -> ${found.toVersion} does not support rollback`, false));
    }
    steps.push(found);
    cursor = next;
    if (steps.length > MAX_CHAIN_LENGTH) {
      return err(AppErrors.internal('migration-chain-too-long',
        `migration chain exceeded ${MAX_CHAIN_LENGTH} steps`, undefined));
    }
  }
  const result: PlannedMigrations = { direction: direction, steps: steps };
  return ok(result);
}
