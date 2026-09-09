/**
 * platform/storage — RDB KV SQL 组装（PLAT-002，纯 ArkTS）。
 *
 * 所有 SQL 以字符串常量的方式在此集中组装（DDL / 读写 / 版本标记），
 * 单测直接断言语句文本与参数绑定；生产 adapter 只负责把 SqlStatement
 * 交给 relationalStore 执行。表结构即 schema v1 基线：
 *
 *   tgx_meta(key TEXT PRIMARY KEY NOT NULL, value INTEGER NOT NULL)   -- user_version
 *   tgx_kv(key TEXT PRIMARY KEY NOT NULL,
 *          type_tag INTEGER NOT NULL,
 *          value_text TEXT,
 *          value_real REAL,
 *          value_integer INTEGER)
 */

import { PreferenceValue } from '@tgx/platform-ports';
import { PreferenceWrite } from './PreferenceStoreCore';
import { encodePreferenceValue } from './RdbKvCodec';

/** SQL 参数绑定值（与 relationalStore.ValueType 的可用子集一致）。 */
export type SqlArg = string | number | boolean | null;

export interface SqlStatement {
  readonly sql: string;
  readonly args: SqlArg[];
}

export class RdbKvStatements {
  static readonly KV_TABLE: string = 'tgx_kv';
  static readonly META_TABLE: string = 'tgx_meta';
  static readonly USER_VERSION_KEY: string = 'user_version';
  /** 基线 schema 版本（v1 建表即基线，无需迁移步骤）。 */
  static readonly SCHEMA_BASELINE_VERSION: number = 1;

  static createMetaTable(): SqlStatement {
    return {
      sql: `CREATE TABLE IF NOT EXISTS ${RdbKvStatements.META_TABLE} ` +
        '(key TEXT PRIMARY KEY NOT NULL, value INTEGER NOT NULL)',
      args: []
    };
  }

  static createKvTable(): SqlStatement {
    return {
      sql: `CREATE TABLE IF NOT EXISTS ${RdbKvStatements.KV_TABLE} ` +
        '(key TEXT PRIMARY KEY NOT NULL, ' +
        'type_tag INTEGER NOT NULL, ' +
        'value_text TEXT, ' +
        'value_real REAL, ' +
        'value_integer INTEGER)',
      args: []
    };
  }

  /** 全量加载：open 时构建内存视图。 */
  static selectAllKv(): SqlStatement {
    return {
      sql: `SELECT key, type_tag, value_text, value_real, value_integer FROM ${RdbKvStatements.KV_TABLE}`,
      args: []
    };
  }

  static upsertKv(key: string, value: PreferenceValue): SqlStatement {
    const row = encodePreferenceValue(value);
    return {
      sql: `INSERT OR REPLACE INTO ${RdbKvStatements.KV_TABLE} ` +
        '(key, type_tag, value_text, value_real, value_integer) VALUES (?, ?, ?, ?, ?)',
      args: [key, row.typeTag, row.text, row.real, row.integer]
    };
  }

  static deleteKv(key: string): SqlStatement {
    return {
      sql: `DELETE FROM ${RdbKvStatements.KV_TABLE} WHERE key = ?`,
      args: [key]
    };
  }

  static selectUserVersion(): SqlStatement {
    return {
      sql: `SELECT value FROM ${RdbKvStatements.META_TABLE} WHERE key = ?`,
      args: [RdbKvStatements.USER_VERSION_KEY]
    };
  }

  /** 版本标记写入：迁移框架每完成一步调用一次（中断续跑的判断依据）。 */
  static upsertUserVersion(version: number): SqlStatement {
    return {
      sql: `INSERT OR REPLACE INTO ${RdbKvStatements.META_TABLE} (key, value) VALUES (?, ?)`,
      args: [RdbKvStatements.USER_VERSION_KEY, version]
    };
  }

  /** 把一次 flush 的写入操作序列转换为按序执行的语句（upsert/delete 均幂等，可安全重试）。 */
  static buildWrites(writes: PreferenceWrite[]): SqlStatement[] {
    const statements: SqlStatement[] = [];
    for (const write of writes) {
      if (write.kind === 'put') {
        statements.push(RdbKvStatements.upsertKv(write.key, write.value));
      } else {
        statements.push(RdbKvStatements.deleteKv(write.key));
      }
    }
    return statements;
  }
}
