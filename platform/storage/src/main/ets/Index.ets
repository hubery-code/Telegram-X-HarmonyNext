/**
 * platform/storage — 对外导出（PLAT-002）。
 *
 * 纯逻辑（core/，无 Kit 依赖，本地单测覆盖）与 Kit adapter（adapter/）分开导出，
 * 本地 panda 单测只 import core/，避免加载 @ohos Kit 模块。
 */

export {
  PreferenceWrite,
  PreferencePersistence,
  PreferenceStoreCore
} from './core/PreferenceStoreCore';
export {
  RDB_TYPE_STRING,
  RDB_TYPE_NUMBER,
  RDB_TYPE_BOOLEAN,
  RdbKvRow,
  encodePreferenceValue,
  decodePreferenceRow
} from './core/RdbKvCodec';
export {
  SqlArg,
  SqlStatement,
  RdbKvStatements
} from './core/RdbKvStatements';
export {
  MigrationStep,
  MigrationDirection,
  PlannedMigrations,
  planMigrations
} from './core/MigrationPlan';
export {
  SqlExecutor,
  runMigrations
} from './core/MigrationRunner';
export { HarmonyPreferencesAdapter } from './adapter/HarmonyPreferencesAdapter';
export {
  RdbPreferencesAdapter,
  RdbPreferencesOpenOptions,
  PREFERENCE_RDB_CURRENT_SCHEMA_VERSION,
  PREFERENCE_RDB_MIGRATIONS
} from './adapter/RdbPreferencesAdapter';
export { RdbSqlExecutor } from './adapter/RdbSqlExecutor';
