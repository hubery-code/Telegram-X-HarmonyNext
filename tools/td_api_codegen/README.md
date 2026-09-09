# td_api_codegen — TDLib schema IR + ArkTS 代码生成（GEN-001 / GEN-002）

把 TDLib 的 `td_api.tl` 解析成稳定的、机器可读的 **schema IR**，并计算
**schema hash**（GEN-001，`td_api_ir.py`）；再从 IR 生成 ArkTS DTO、
判别联合、JSON codec 与请求返回类型映射（GEN-002，`td_api_arkts.py`）。

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

## GEN-002：ArkTS 生成器（td_api_arkts.py）

从 `core/td_api_generated/schema.ir.json`（GEN-001 产物）生成 ArkTS，输出到
`core/td_api_generated/src/main/ets/`。**不要重新解析 .tl，不要改动
`td_api_ir.py`。** 生成完全确定：重复运行字节级一致。

```bash
# 重新生成全部 ArkTS 文件（生成物禁止手改，改这里）
python3 tools/td_api_codegen/td_api_arkts.py generate

# CI 入口：内存中重新生成并与 checked-in 文件逐字节比对（不写文件）
python3 tools/td_api_codegen/td_api_arkts.py verify

# 统计
python3 tools/td_api_codegen/td_api_arkts.py info
```

### 命名规则

| TDLib | ArkTS |
|---|---|
| 抽象类型 `T`（判别联合） | `Td`+`T`（如 `TdMessageContent`、`TdUpdate`） |
| 构造器 `camelCase`（类） | `Pascal(camelCase)`；冲突时确定性回退 `Td<Pascal>` → `<Pascal>Value`（如 `date`→`DateValue`、`error`→`ErrorValue`） |
| 字段名 `type`/`extra` | 属性名 `type_`/`extra_`（与判别属性 `type`、`@extra` 载体 `extra` 避让；wire 名不变） |
| union decode/encode | `decodeTd<T>` / `encodeTd<T>` |
| 类 decode/encode | `decode<Pascal>` / `encode<Pascal>` |
| 任意对象入口 | `decodeTdObject` / `encodeTdObject` |

已知避让：TDLib 有抽象类型 `JsonValue`，故运行时 JSON 值类型命名为
`TdJsonRaw`（+ `TdJsonObject`）；ArkTS 禁止递归 type alias 与条件/索引类型，
故 `TdJsonObject` 用 `interface extends Record`、返回类型映射只有
`TdResponseMap` 接口（无 `TdResponseFor` 条件类型）。

### 类型/codec 语义

- 判别属性：`type: '<ctor>'`；`extra?: string` 承载 TDLib `@extra`
  （decode 保留、encode 回传，供请求/响应关联）。
- 标量：`int32/int53/double`→`number`，`int64`→`string`（精度；
  decode 兼容 number 输入），`string/bytes`→`string`，`bool/Bool`→`boolean`。
- 对象引用（抽象类型或构造器名）→ `X | null`；`vector<n>`→数组（元素非空）。
- decode 永不抛错：未知 `@type` → `TdUnknownObject`（保留 raw，可无损
  re-encode）；未知字段忽略；缺字段取 schema 默认值；`null` 输入 → `null`。
- encode 输出 TDLib wire shape（`@type`/字段名蛇形原样）。
- ArkTS 不按判别属性收窄联合，消费侧用 `instanceof`。

## GEN-002 交接给 GEN-003/004

- GEN-003（codec fixture round-trip）：decode/encode 函数已全部生成，
  只需补官方/脱敏 JSON fixtures 与差分测试。
- GEN-004（脱敏元数据）：已实现，见下节。

## GEN-004：敏感字段元数据 + 日志脱敏 helper（td_api_sensitive.py）

从 `core/td_api_generated/schema.ir.json` 生成敏感字段元数据与脱敏运行时，
输出到 `core/td_api_generated/src/main/ets/redaction/`。**不要重新解析 .tl，
不要改动 `td_api_ir.py`/`td_api_arkts.py`。** 生成完全确定：重复运行字节级一致。

```bash
# 重新生成（生成物禁止手改，改生成器里的规则表）
python3 tools/td_api_codegen/td_api_sensitive.py generate

# CI 入口：内存中重新生成并与 checked-in 文件逐字节比对（不写文件）
python3 tools/td_api_codegen/td_api_sensitive.py verify

# 规则统计（规则按策略分布、覆盖构造器/字段/类型数）
python3 tools/td_api_codegen/td_api_sensitive.py info
```

### 规则表（单一决策点）

规则全部集中在 `td_api_sensitive.py` 顶部的三张表里，每条规则带决策注释：

1. **`SCOPED_RULES`** — 构造器级覆盖（最高优先级）。用于同名异义字段：
   `username` 在 Telegram 用户上是公开标识，但在 `proxyTypeHttp/proxyTypeSocks5`
   上是代理凭据；`setTdlibParameters` 的 `api_id/api_hash/database_encryption_key`；
   `error.code` 是 TDLib 错误码而非验证码（反向覆盖为 keep）。
2. **`EXACT_RULES`** — 精确字段名规则（不做子串匹配，避免 `next_code_type`
   这类"类型标签"被误伤）。含密码/验证码/令牌/密钥/手机号/邮箱/IP/姓名等，
   并显式记录 keep 决策（`country_code`、`language_code`、`key`、`is_secret`、
   `has_password`、`username` 等）以防后续 suffix 规则误伤。
3. **`SUFFIX_RULES`** — 后缀规则（`_password`/`_secret` redact，
   `_token`/`_hash` mask）。刻意**没有** `_code`（`country_code` 等非敏感）。

策略语义（在生成物 `TdSensitiveFields.ets` 头部也有说明）：

| policy | 语义 |
|---|---|
| `redact` | 完全遮蔽：字符串→`«redacted»`，数字→0，布尔→false，子树整体替换 |
| `mask` | 部分遮蔽：字符串留头尾若干字符；数字/布尔置 0/false；子树递归细粒度处理 |
| `keep` | 保留（未列入元数据的字段默认 keep） |

首个匹配生效（scoped > exact > suffix > 默认 keep）。

### 输出文件

| 文件 | 说明 |
|---|---|
| `redaction/TdSensitiveFields.ets` | 结构化元数据：构造器→字段→策略+决策理由、`TD_SENSITIVE_TYPES` 类型级清单（仅 object 构造器，函数请求的敏感入参不会污染其返回类型）、未知 `@type` 兜底子串表；头部带 schema hash 与生成器版本 |
| `redaction/TdRedact.ets` | `redactTdJson(json)`：按元数据脱敏 TDLib JSON 字符串，未知 `@type` 按字段名子串保守遮蔽，非法输入永不抛错（返回占位符，不允许不可审计内容放行）；`redactFields(obj: TdObject)`：encode→redact→decode 的 DTO 深拷贝脱敏 |

### 当前统计（TDLib d1085f9ce / schemaHash 7fbae70a…c5929）

`ctorsWithRules=124 flaggedFields=154 sensitiveTypes=44`（info 子命令实时输出；
redact 75 / mask 79）。与 GEN-002 的关系：GEN-002 文件一律不改动，本阶段只新增
`redaction/` 目录两个文件（`TD_KNOWN_CONSTRUCTORS` 全量构造器表也在
TdSensitiveFields.ets 内，用于区分「已知但无规则→keep」与「未知 @type→保守兜底」）。

### 与 core/observability 的关系（§14.4 两道防线）

计划要求「日志按字段白名单输出，禁止先完整记录再正则脱敏」。`core/observability`
的 Logger 是第一道防线（白名单制，只有显式标记可日志的字段才输出）；
`TdRedact` 是第二道防线（白名单过滤后的输出再过一遍元数据脱敏）。
TDLib 升级后重跑三个生成器（ir → arkts → sensitive），规则表随 schema 重新推导。


## GEN-001 交接说明（历史，已被 GEN-002 实现）

- 从 `core/td_api_generated/schema.ir.json` 读入即可，不要重新解析 .tl。
- 每个抽象 `type` 生成 discriminated union：`@type` 判别值 = 构造器 `name`。
- `functions` 的 `type` 即请求的返回类型；`Ok`/`Error` 为通用返回。
- 字段 ArkTS 映射建议：`int32/int53`→`number`，`int64`→`string`（精度），
  `double`→`number`，`string`→`string`，`bytes`→`string`（base64），
  `Bool`→`boolean`，`vectorDepth>0`→`T[]`。
- 生成代码必须整体提交、禁止手改；改动生成器后跑
  `generate --update-snapshot` 刷新快照，hash 变化会在 PROGRESS/CR 中显式可见。
