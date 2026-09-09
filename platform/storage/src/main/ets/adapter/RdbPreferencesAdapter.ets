/**
 * platform/storage — PreferencesPort 的 RDB 键值 adapter（PLAT-002）。
 *
 * 同一端口的第二种实现：键值存进 @ohos.data.relationalStore（SQLite），
 * 带 schema version + migration 框架（升级/回滚路径，验收「中断/升级/回滚」
 * 的结构基础）。适用：需要跨版本演进的 app-owned 偏好/开关数据
 * （账号清单、功能开关、schema 版本等，见计划 §5.6）。
 *
 * 打开流程（open）：
 * 1. 建基线表（幂等 DDL）：tgx_meta（user_version）+ tgx_kv；
 * 2. 读版本标记：无记录 → 初始化为基线 v1；
 * 3. 版本 ≠ 当前版本 → runMigrations 逐版本迁移（升级走 up，应用降级走
 *    down = 回滚路径）；Kit 层用事务包裹，中断时整体回滚，重开续跑；
 * 4. 全量加载 tgx_kv 构建内存视图，交给 PreferenceStoreCore。
 *
 * 用法（entry 装配层）：
 *   const store = await RdbPreferencesAdapter.open(context, { dbName: 'tgx_app_prefs' });
 *   ... 使用 ...
 *   await store.close();
 *
 * 注意：RdbStore 的 SQL 接口全为异步，本 adapter 不提供同步打开；
 * 同进程同名库只允许一个打开实例（relationalStore 约束），重开前须先 close()。
 */

import relationalStore from '@ohos.data.relationalStore';
import common from '@ohos.app.ability.common';
import { BusinessError } from '@ohos.base';
import { Result, AppError, ok, err, AppErrors } from '@tgx/core-common';
import {
  PreferencesPort,
  PreferenceValue,
  PreferenceChange,
  Subscription
} from '@tgx/platform-ports';
import {
  PreferenceStoreCore,
  PreferencePersistence,
  PreferenceWrite
} from '../core/PreferenceStoreCore';
import { RdbKvStatements, SqlStatement } from '../core/RdbKvStatements';
import { decodePreferenceRow, RdbKvRow } from '../core/RdbKvCodec';
import { MigrationStep } from '../core/MigrationPlan';
import { runMigrations } from '../core/MigrationRunner';
import { RdbSqlExecutor } from './RdbSqlExecutor';

/** 当前 schema 版本。后续版本在 PREFERENCE_RDB_MIGRATIONS 追加步骤（from=N → to=N+1）。 */
export const PREFERENCE_RDB_CURRENT_SCHEMA_VERSION: number = 1;

/**
 * 迁移注册表：当前为空（v1 即基线）。新增 schema 版本时追加
 * { fromVersion, toVersion: from+1, up: [...], down: [...] }；
 * 不允许回滚的步骤可将 down 置空（应用降级到该步会报 storage/migration）。
 */
export const PREFERENCE_RDB_MIGRATIONS: MigrationStep[] = [];

export interface RdbPreferencesOpenOptions {
  /** 数据库文件名（自动补 .db 后缀）。同一进程内同名库只允许一个打开实例。 */
  readonly dbName: string;
  /** 安全级别，默认 S1（偏好为非敏感开关，见计划 §5.6）。 */
  readonly securityLevel?: relationalStore.SecurityLevel;
}

/** Kit 抛出的异常统一映射：BusinessError 数字码 → platform/code（retryable=true）。 */
function asPlatformError(origin: string, e: Object): AppError {
  const be: BusinessError = e as BusinessError;
  if (be !== null && be !== undefined && typeof be.code === 'number') {
    return AppErrors.platform(be.code, `${origin} failed (rdb kit)`, true);
  }
  return AppErrors.unknown(origin, `${origin} failed (non-business error)`);
}

class RdbPreferencePersistence implements PreferencePersistence {
  private readonly store: relationalStore.RdbStore;

  constructor(store: relationalStore.RdbStore) {
    this.store = store;
  }

  async persist(writes: PreferenceWrite[]): Promise<Result<void, AppError>> {
    const statements: SqlStatement[] = RdbKvStatements.buildWrites(writes);
    for (const statement of statements) {
      try {
        const args: Array<relationalStore.ValueType> = [];
        for (const arg of statement.args) {
          args.push(arg);
        }
        await this.store.executeSql(statement.sql, args);
      } catch (e) {
        return err(asPlatformError('rdb.persist', e));
      }
    }
    return ok(undefined);
  }
}

/** 事务包裹迁移：Kit 支持事务则整体提交/回滚（中断 → 整体回滚，重开续跑）。 */
async function migrateWithTransaction(
  store: relationalStore.RdbStore,
  executor: RdbSqlExecutor,
  fromVersion: number,
  toVersion: number
): Promise<Result<number, AppError>> {
  let transactional: boolean = false;
  try {
    store.beginTransaction();
    transactional = true;
  } catch (e) {
    transactional = false;
  }
  const migrated: Result<number, AppError> = await runMigrations(
    executor, PREFERENCE_RDB_MIGRATIONS, fromVersion, toVersion,
    (version: number) => RdbKvStatements.upsertUserVersion(version));
  if (transactional) {
    try {
      if (migrated.ok) {
        store.commit();
      } else {
        store.rollBack();
      }
    } catch (e) {
      return err(asPlatformError('rdb.migrate.transaction', e));
    }
  }
  return migrated;
}

async function loadAll(store: relationalStore.RdbStore): Promise<Result<Map<string, PreferenceValue>, AppError>> {
  const data: Map<string, PreferenceValue> = new Map();
  let resultSet: relationalStore.ResultSet | undefined;
  try {
    resultSet = await store.querySql(RdbKvStatements.selectAllKv().sql);
  } catch (e) {
    return err(asPlatformError('rdb.loadAll', e));
  }
  if (resultSet === undefined) {
    return err(AppErrors.unknown('rdb.loadAll', 'rdb query returned no result set'));
  }
  try {
    if (resultSet.goToFirstRow()) {
      const keyIndex: number = resultSet.getColumnIndex('key');
      const tagIndex: number = resultSet.getColumnIndex('type_tag');
      const textIndex: number = resultSet.getColumnIndex('value_text');
      const realIndex: number = resultSet.getColumnIndex('value_real');
      const integerIndex: number = resultSet.getColumnIndex('value_integer');
      do {
        const row: RdbKvRow = {
          typeTag: resultSet.getLong(tagIndex),
          text: resultSet.isColumnNull(textIndex) ? null : resultSet.getString(textIndex),
          real: resultSet.isColumnNull(realIndex) ? null : resultSet.getDouble(realIndex),
          integer: resultSet.isColumnNull(integerIndex) ? null : resultSet.getLong(integerIndex)
        };
        const decoded: Result<PreferenceValue, AppError> = decodePreferenceRow(row);
        if (decoded.err) {
          return err(decoded.error);
        }
        if (decoded.ok) {
          data.set(resultSet.getString(keyIndex), decoded.value);
        }
      } while (resultSet.goToNextRow());
    }
    return ok(data);
  } catch (e) {
    return err(asPlatformError('rdb.loadAll', e));
  } finally {
    try {
      resultSet.close();
    } catch (e) {
      // 忽略关闭失败。
    }
  }
}

async function openOnStore(store: relationalStore.RdbStore): Promise<Result<RdbPreferencesAdapter, AppError>> {
  const executor: RdbSqlExecutor = new RdbSqlExecutor(store);

  const ddls: SqlStatement[] = [
    RdbKvStatements.createMetaTable(),
    RdbKvStatements.createKvTable()
  ];
  for (const ddl of ddls) {
    const created: Result<void, AppError> = await executor.exec(ddl);
    if (created.err) {
      return err(created.error);
    }
  }

  const stored: Result<number | null, AppError> = await executor.queryInteger(RdbKvStatements.selectUserVersion());
  if (stored.err) {
    return err(stored.error);
  }
  const storedVersion: number | null = stored.getOrNull();
  if (storedVersion !== null && storedVersion < RdbKvStatements.SCHEMA_BASELINE_VERSION) {
    return err(AppErrors.storage('migration',
      `stored schema version ${storedVersion} is below baseline ${RdbKvStatements.SCHEMA_BASELINE_VERSION}`, false));
  }
  let version: number = storedVersion === null ? RdbKvStatements.SCHEMA_BASELINE_VERSION : storedVersion;
  if (storedVersion === null) {
    const marked: Result<void, AppError> =
      await executor.exec(RdbKvStatements.upsertUserVersion(RdbKvStatements.SCHEMA_BASELINE_VERSION));
    if (marked.err) {
      return err(marked.error);
    }
  }

  if (version !== PREFERENCE_RDB_CURRENT_SCHEMA_VERSION) {
    const migrated: Result<number, AppError> =
      await migrateWithTransaction(store, executor, version, PREFERENCE_RDB_CURRENT_SCHEMA_VERSION);
    if (migrated.err) {
      return err(migrated.error);
    }
    version = PREFERENCE_RDB_CURRENT_SCHEMA_VERSION;
  }

  const loaded: Result<Map<string, PreferenceValue>, AppError> = await loadAll(store);
  if (loaded.err) {
    return err(loaded.error);
  }
  const data: Map<string, PreferenceValue> = loaded.getOrElse(new Map());
  const core: PreferenceStoreCore =
    new PreferenceStoreCore(data, new RdbPreferencePersistence(store));
  return ok(new RdbPreferencesAdapter(core, store));
}

export class RdbPreferencesAdapter implements PreferencesPort {
  private readonly core: PreferenceStoreCore;
  private readonly store: relationalStore.RdbStore;
  private closed: boolean = false;

  /** 模块内构造；外部一律经 open()。 */
  constructor(core: PreferenceStoreCore, store: relationalStore.RdbStore) {
    this.core = core;
    this.store = store;
  }

  /** 打开（异步，唯一打开路径；SQL 接口全异步）。 */
  static async open(
    context: common.Context,
    options: RdbPreferencesOpenOptions
  ): Promise<Result<RdbPreferencesAdapter, AppError>> {
    const name: Result<string, AppError> = normalizeDbName(options.dbName);
    if (name.err) {
      return err(name.error);
    }
    try {
      const store: relationalStore.RdbStore = await relationalStore.getRdbStore(context, {
        name: name.getOrElse(''),
        securityLevel: options.securityLevel !== undefined
          ? options.securityLevel
          : relationalStore.SecurityLevel.S1
      });
      return await openOnStore(store);
    } catch (e) {
      return err(asPlatformError('rdb.open', e));
    }
  }

  /** 关闭底层 RdbStore（幂等）；关闭后本 adapter 不得再使用。 */
  async close(): Promise<Result<void, AppError>> {
    if (this.closed) {
      return ok(undefined);
    }
    this.closed = true;
    try {
      await this.store.close();
      return ok(undefined);
    } catch (e) {
      return err(asPlatformError('rdb.close', e));
    }
  }

  getString(key: string): Result<string | null, AppError> {
    return this.core.getString(key);
  }

  getNumber(key: string): Result<number | null, AppError> {
    return this.core.getNumber(key);
  }

  getBoolean(key: string): Result<boolean | null, AppError> {
    return this.core.getBoolean(key);
  }

  put(key: string, value: PreferenceValue): Result<void, AppError> {
    return this.core.put(key, value);
  }

  remove(key: string): Result<void, AppError> {
    return this.core.remove(key);
  }

  clear(): Result<void, AppError> {
    return this.core.clear();
  }

  flush(): Promise<Result<void, AppError>> {
    return this.core.flush();
  }

  observeChanges(listener: (change: PreferenceChange) => void): Subscription {
    return this.core.observeChanges(listener);
  }

  hasPendingChanges(): boolean {
    return this.core.hasPendingChanges();
  }
}

function normalizeDbName(dbName: string): Result<string, AppError> {
  if (dbName.length === 0) {
    return err(AppErrors.parameter('invalid', 'dbName', 'empty rdb name'));
  }
  if (dbName.endsWith('.db')) {
    return ok(dbName);
  }
  return ok(`${dbName}.db`);
}
