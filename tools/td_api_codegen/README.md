# td_api_codegen — TDLib schema IR 生成器（GEN-001）

把 TDLib 的 `td_api.tl` 解析成稳定的、机器可读的 **schema IR**，并计算
**schema hash**，为 GEN-002~004（ArkTS DTO/union、codec/validator、脱敏元数据
生成）提供唯一输入。

纯 Python 3（≥3.9）实现，无第三方依赖，不经过 hvigor，可独立运行。

## 输入（单一输入源）

```
native/tdcore/third_party/td/td/generate/scheme/td_api.tl
```

可用 `--input <path>` 覆盖（仅用于测试）。

## 用法

在**工程根目录**执行：

```bash
# CI 入口：解析 + hash + 与 checked-in 快照比对；不写任何文件。
# 干净检出下必须通过（退出码 0），这是「重新生成后工作树无差异」的基础。
python3 tools/td_api_codegen/td_api_ir.py verify

# 解析并写出 core/td_api_generated/schema.ir.json，然后与快照比对；
# 不一致时退出码 1 并提示 --update-snapshot。
python3 tools/td_api_codegen/td_api_ir.py generate

# 输入 .tl 有意升级后，刷新 golden 快照 + IR 导出（会改动工作树文件）。
python3 tools/td_api_codegen/td_api_ir.py generate --update-snapshot

# 只看 hash 与统计。
python3 tools/td_api_codegen/td_api_ir.py info
```

## 输出

| 文件 | 说明 |
|---|---|
| `core/td_api_generated/schema.ir.json` | IR 机器可读导出（GEN-002 的输入） |
| `tools/td_api_codegen/snapshot/td_api.ir.json` | checked-in golden 快照，`verify`/`generate` 比对的基准 |

## IR 结构（formatVersion 1）

顶层字段：

- `formatVersion` / `generator` — 生成器标识。
- `source` — 输入文件相对路径与其 SHA-256（原始字节）。
- `stats` — `types` / `constructors` / `objects` / `functions` / `fields` / `builtinAliases` 计数。
- `builtins` — 标量类型（`int32/int53/int64/double/string/bytes/bool/Bool`）与
  原始别名构造器（`boolFalse/boolTrue/int32/…/vector`）。
- `types` — 抽象类型表（按名字母序）：`name`、`kind`（`object` 抽象类 /
  `functionResult` 仅函数返回）、`constructors`（该类型的构造器，字母序）、`doc`。
- `constructors` — 全部构造器（对象 + 函数，按名字母序，字段保持声明顺序）：
  - `name` / `kind`（`object`|`function`）/ `type`（结果类型）/ `typeArgs`（如 `["t"]`）。
  - `typeVars` — 泛型形参（当前仅 `vector` 的 `["t"]`）。
  - `class` — 最近的 `//@class` 区段标注（文档分组用）。
  - `fields[]`：`name`、`type`（标量或类型名）、`isArray`、`vectorDepth`
    （支持 `vector<vector<T>>` 多层嵌套）、`signature`（如 `vector<vector<string>>`）。
  - `doc`：`description`（含 `//-` 续行，换行连接）与 `fields`（字段级文档）。

## schema hash 语义

`schemaHash` = SHA-256，输入为 `builtins + types + constructors` 三段的
**规范化 JSON**（键排序、无空白、UTF-8）。它**只随 schema 内容变化**：
注释措辞、行号、输入文件路径、统计数字的变化都不会改变 hash。
`source.sha256` 则精确锁定输入文件字节，两者互补。

解析输出全量确定：构造器按名字母序、字段按声明序、JSON 固定缩进，
重复运行字节级一致（已实测）。

## 解析覆盖

- `//@description` / `//@field` / `//@class` 注释、`//-` 续行、行内 `@field` 文档、
  行尾 `//` 注释、`/* */` 块注释。
- 抽象类型与构造器分开；`---functions---` 段识别函数。
- 泛型 `vector {t:Type} # [ t ] = Vector t;`。
- 字段类型：`int32/int53/int64/double/string/bytes/Bool`、任意类名、
  `vector<T>` 与任意层嵌套 `vector<vector<T>>`。

## 当前 schema hash（TDLib d1085f9ce / td_api.tl 16313 行）

```
7fbae70abe4def1a2576f9b89fe364b52501c68ac074a14ba67be87c729c5929
stats: types=743 constructors=3214 (objects=2192 functions=1022) fields=6997 builtinAliases=9
```

## GEN-002 交接说明

- 从 `core/td_api_generated/schema.ir.json` 读入即可，不要重新解析 .tl。
- 每个抽象 `type` 生成 discriminated union：`@type` 判别值 = 构造器 `name`。
- `functions` 的 `type` 即请求的返回类型；`Ok`/`Error` 为通用返回。
- 字段 ArkTS 映射建议：`int32/int53`→`number`，`int64`→`string`（精度），
  `double`→`number`，`string`→`string`，`bytes`→`string`（base64），
  `Bool`→`boolean`，`vectorDepth>0`→`T[]`。
- 生成代码必须整体提交、禁止手改；改动生成器后跑
  `generate --update-snapshot` 刷新快照，hash 变化会在 PROGRESS/CR 中显式可见。
