/**
 * platform/storage — RDB KV 值编解码（PLAT-002，纯 ArkTS）。
 *
 * PreferenceValue 与 tgx_kv 行模型的互转。行模型用三列分别承载三种类型，
 * 避免 SQLite 动态类型带来的读回歧义（类型不匹配 → err(storage/corrupted)）。
 */

import { Result, AppError, ok, err, AppErrors } from '@tgx/core-common';
import { PreferenceValue } from '@tgx/platform-ports';

export const RDB_TYPE_STRING: number = 0;
export const RDB_TYPE_NUMBER: number = 1;
export const RDB_TYPE_BOOLEAN: number = 2;

/** tgx_kv 一行的值列（key 列由语句层处理）。 */
export interface RdbKvRow {
  readonly typeTag: number;
  readonly text: string | null;
  readonly real: number | null;
  readonly integer: number | null;
}

export function encodePreferenceValue(value: PreferenceValue): RdbKvRow {
  if (typeof value === 'string') {
    return { typeTag: RDB_TYPE_STRING, text: value, real: null, integer: null };
  }
  if (typeof value === 'number') {
    return { typeTag: RDB_TYPE_NUMBER, text: null, real: value, integer: null };
  }
  return { typeTag: RDB_TYPE_BOOLEAN, text: null, real: null, integer: value ? 1 : 0 };
}

export function decodePreferenceRow(row: RdbKvRow): Result<PreferenceValue, AppError> {
  switch (row.typeTag) {
    case RDB_TYPE_STRING:
      if (row.text === null) {
        return err(AppErrors.storage('corrupted', 'kv row: string tag with null text', false));
      }
      return ok(row.text);
    case RDB_TYPE_NUMBER:
      if (row.real === null) {
        return err(AppErrors.storage('corrupted', 'kv row: number tag with null real', false));
      }
      return ok(row.real);
    case RDB_TYPE_BOOLEAN:
      if (row.integer === null || (row.integer !== 0 && row.integer !== 1)) {
        return err(AppErrors.storage('corrupted', 'kv row: boolean tag with invalid integer', false));
      }
      return ok(row.integer === 1);
    default:
      return err(AppErrors.storage('corrupted', `kv row: unknown type tag ${row.typeTag}`, false));
  }
}
