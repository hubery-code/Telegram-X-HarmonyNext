# platform/storage（PLAT-002）

PreferencesPort 的**生产 adapter**（计划 §9.4 PLAT-002：产物「schema + migration」，验收「中断/升级/回滚测试」）。依赖 `@tgx/core-common`（Result/AppError）与 `@tgx/platform-ports`（PreferencesPort 契约），`file:` 本地引用 + oh_modules 符号链接（gitignored，照 `platform/ports` 做法）。

## Adapter 清单

| Adapter | 底层 Kit | 适用 | 打开方式 |
|---|---|---|---|
| `HarmonyPreferencesAdapter` | `@ohos.data.preferences` | 小型非敏感开关（主题、字号、UI 偏好，§5.6） | `open(context, name)` 异步；`openSync`（API 10+）供设备测试 |
| `RdbPreferencesAdapter` | `@ohos.data.relationalStore` | 需跨版本演进的 app-owned 键值（账号清单、功能开关、schema 版本，§5.6） | `open(context, { dbName })` 异步（RdbStore 全异步接口）；`close()` 幂等关闭 |

两个 adapter 共享 `PreferenceStoreCore`（纯 ArkTS）：内存视图、挂起变更合并、flush 后派发、clear 通配事件、失败保持挂起——与 `platform/ports` 契约语义严格对齐。

## RDB schema 与 migration 框架

- **表结构（schema v1 基线，`RdbKvStatements` 集中组装 SQL）**：
  - `tgx_meta(key TEXT PK, value INTEGER)` — 存 `user_version` 版本标记；
  - `tgx_kv(key TEXT PK, type_tag INTEGER, value_text TEXT, value_real REAL, value_integer INTEGER)` — 类型分列存储，读回无动态类型歧义（类型不匹配 → `err(storage/corrupted)`）。
- **版本模型**：正整数线性版本链；`PREFERENCE_RDB_CURRENT_SCHEMA_VERSION = 1`，`PREFERENCE_RDB_MIGRATIONS` 注册表当前为空。新增版本追加 `{fromVersion, toVersion: from+1, up[], down[]}`。
- **升级路径**：open 时读 `user_version`（无记录 → 初始化基线 v1），低于当前版本则 `runMigrations` 逐版本执行 `up`。
- **回滚路径**：存储版本高于当前版本（应用降级）时按 `down` 逐版本回退；`down` 置空的步骤显式声明不可回滚，降级到该步报 `err(storage/migration)`。
- **中断安全**：① 每完成一步先把 `user_version` 推进到该步目标版本再进下一步——任一条语句失败时版本停在最后完成步骤，重开从断点续跑；② Kit 层以 `beginTransaction/commit/rollBack` 包裹整段迁移，进程被杀时事务整体回滚。验收「中断/升级/回滚」的 fake 注入测试见 `src/test/MigrationRunner.test.ets`（写一半失败、版本标记失败、版本跳跃 1→3、回滚 3→1）。
- **flush 落盘**：upsert/delete 均幂等，flush 失败可整体重试；变更事件仅在落盘成功后派发。

## 验证矩阵

| 项 | 状态 | 证据 |
|---|---|---|
| 纯逻辑单测（core 全量语义/SQL 组装/编解码/migration 规划与执行含中断注入） | ✅ 本地已验 | `Tests run: 47, Failure: 0, Error: 0, Pass: 47`：`./hvigorw test --mode module -p module=platform_storage@default -p product=default --no-daemon` |
| adapter 本体严格编译（含 Kit 类型） | ✅ 本地已验 | `./hvigorw assembleHar --mode module -p module=platform_storage@default -p product=default --no-daemon` BUILD SUCCESSFUL（产出 `platform_storage.har`） |
| Kit 集成（真实建库/落盘/重开读回/事件派发） | ⏳ 待设备 | `src/ohosTest/ets/test/*.device.test.ets`（需接入测试宿主后真机执行） |
| PLAT-001 全量参数化 contract 复用到生产 adapter | ⏳ 待设备 + 待 test_support 包 | contract 函数在 `platform/ports/src/test`，ArkTS 编译器禁止跨模块相对 import（本地实测拒绝）；设备侧同样受限。建议 QA 将 contract 函数移入 `test/` 支撑包（计划 §4.3 `test_support`）后一行接入 |

## 工程要点（ArkTS 实测）

1. **Result 收窄**：`if (r.ok) { r.value }` / `if (r.err) { r.error }` 块内可收窄；取反（`!r.ok`）、early-return 之后、if/else 的 else 分支均**不**收窄——跨 har 模块时尤其如此。取值可用 `r.getOrNull()`（`T | null`，无需收窄）；`.code` 等分种类字段须先 `if (r.error.kind === 'storage')` 再收窄。
2. **AppErrors.storage/migration 等工厂方法 retryable 为必填**（3 参起）。
3. **内联对象字面量类型（`type X = { a: 1 } | { b: 2 }`）被禁**（arkts-no-obj-literals-as-types）——用 interface 组合 union；push/return 的对象字面量用显式类型常量承接。
4. Kit 异常映射：`catch (e)` 中 `e instanceof BusinessError` 不可用（BusinessError 仅类型）——用 `e as BusinessError` 转型后取 `.code`。
5. RdbStore 原始 SQL 用 `querySql`（`query` 只收 RdbPredicates）；`getRdbStoreSync` 为 API 24+；`Preferences.getPreferencesSync/getAllSync` 为 API 10+。
6. RdbStore 事务：`beginTransaction()/commit()/rollBack()`（@since 9）；异步 SQL 须在 Promise 完成后 commit。

## 已知限制 / 交接

1. **单实例约束**：同一偏好文件/数据库只由一个 adapter 实例持有（装配层保证）。跨实例同步不订阅 Kit change 事件；RDB 同进程同名库仅允许一个打开实例，重开前必须 `close()`。
2. flush 失败中途可能部分落盘：内存视图与磁盘短暂不一致，重试 flush 后以内存视图为准修复（写入幂等保证收敛）。
3. 新 schema 版本流程：在 `PREFERENCE_RDB_MIGRATIONS` 追加步骤（from=N → to=N+1，up/down 语句经 `RdbKvStatements` 风格组装）→ 升 `PREFERENCE_RDB_CURRENT_SCHEMA_VERSION` → 为 up/down 路径各补 fake 中断/回滚用例（仿 `MigrationRunner.test.ets`）。
4. `PreferencesPort` 的 `get*` 为同步读内存视图；RDB adapter 的 `open()` 为唯一异步点。
5. 设备测试 (`src/ohosTest`) 尚未接入测试宿主 har 依赖；接入时宿主 oh-package.json5 需加 `"@tgx/platform-storage": "file:../../platform/storage"` 及 `@tgx/platform-ports`、`@tgx/core-common`。
