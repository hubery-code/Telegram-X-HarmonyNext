# td_api_generated — TDLib 类型生成产物

本目录全部内容由生成器产出，**禁止手改**。

- 生成器：`tools/td_api_codegen/`（`td_api_ir.py` = GEN-001 schema IR；`td_api_arkts.py` = GEN-002 ArkTS，用法见其 README）
- 输入：`native/tdcore/third_party/td/td/generate/scheme/td_api.tl`（单一输入源，经 GEN-001 IR）
- 校验（CI）：
  - `python3 tools/td_api_codegen/td_api_ir.py verify`（IR 与 golden 快照一致）
  - `python3 tools/td_api_codegen/td_api_arkts.py verify`（ArkTS 与重新生成逐字节一致）

| 文件 | 说明 |
|---|---|
| `schema.ir.json` | GEN-001 产出的 schema IR（GEN-002 ArkTS DTO/union 生成的直接输入） |
| `src/main/ets/Index.ets` | 全量显式 re-export（har 入口） |
| `src/main/ets/runtime/TdJson.ets` | `TdJsonRaw`/`TdJsonObject` JSON 值类型、`TdUnknownObject`（未知 `@type` 前向兼容载体）、标量/vector 编解码助手、`TD_SCHEMA_HASH` 等常量 |
| `src/main/ets/types/TdTypes_<A-Z>.ets` | 每个构造器一个类（判别属性 `type`、wire 名 `type_`/`extra_` 避让）+ 每类 `decode/encode` 函数，按类名字母分块 |
| `src/main/ets/types/TdUnions.ets` | 每个抽象类型一个判别联合（恒含 `TdUnknownObject` 成员）+ `decodeTd<T>/encodeTd<T>` + `TdObject`/`TdFunction`/`TdResponseMap` + `decodeTdObject`/`encodeTdObject` |
| `src/test/*.test.ets` | hypium 单测：codec round-trip、未知 `@type`/未知字段 fallback、int64 精度、请求 wire shape/`@extra`/返回类型映射 |

## 关键语义

- **模块**：`core_td_api_generated`（har），包名 `@tgx/td-api-generated`；
  `oh_modules/@ohos/hypium` 为本地符号链接（gitignored，照抄 entry/core_common 做法）。
- **命名**：抽象类型 `T` → `TdT`（联合）；构造器 → PascalCase 类（`date`/`error`/`proxy`
  等撞 JS 全局名的构造器确定性回退为 `DateValue`/`ErrorValue`/`ProxyValue`）。
- **精度**：`int64` → `string`；`int32/int53/double` → `number`。
- **前向兼容**：decode 永不抛错——未知 `@type` → `TdUnknownObject`（保留 raw，
  可无损 re-encode）；未知字段忽略；缺字段取默认值；`null` 输入 → `null`。
- **消费注意**：ArkTS 不按判别属性收窄联合，用 `instanceof` 分支。
- **统计**：classes=3205（objects=2183 + functions=1022）、unions=743、chunk 文件 23 个；
  schemaHash `7fbae70a…c5929`。

GEN-003/004 将在本目录追加 codec fixtures 与脱敏元数据，同样生成、同样禁止手改。
