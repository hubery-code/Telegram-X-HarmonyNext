# core/observability — 白名单制脱敏 Logger（GEN-004 / OBS-001）

纯 ArkTS，无 ArkUI / Kit 依赖。包名 `@tgx/observability`，har 模块名
`core_observability`（build-profile.json5 仅追加注册）。

## 设计：两道防线（计划 §14.4）

> 日志按字段白名单输出，禁止先完整记录再正则脱敏。

1. **白名单（第一道，本模块 `DEFAULT_TD_LOG_WHITELIST`）**：只有显式标记
   可日志的字段才输出。按 TDLib `@type` 逐字段声明（wire 蛇形名），
   `@type` 恒保留；**未知 `@type` 只输出 `@type` 本身**；不做递归过滤。
2. **元数据脱敏（第二道，GEN-004 生成物 `TdRedact`）**：白名单放行后的
   JSON 再过一遍敏感字段元数据——处理白名单放行的子树内部的敏感字段
   （例：`updateAuthorizationState` 白名单放行 `authorization_state`，
   其中的 `authorizationStateWaitPassword.password_hint` 由第二道红线遮蔽）。

`Logger.logTdJson` / `Logger.logTdObject` 把两道防线串成固定管线：
`白名单过滤 -> redactTdJson -> 输出`，调用方无法绕过。

### 反向调用（脱敏不依赖白名单）

`redactTdJson(json)` / `redactFields(obj)` 可直接使用（重导出自
`@tgx/td-api-generated/redaction`），适用于回放工具、诊断导出等
「非日志」场景。语义见 GEN-004 生成器 README：
`redact`=完全遮蔽、`mask`=部分遮蔽、未知 `@type` 按字段名子串保守遮蔽、
非法输入永不抛错（返回 `«redacted»`，不可审计内容不放行）。

## Logger API

```ts
const logger = new Logger('info', (level, line) => { /* 接平台日志/HMLog */ });
logger.info('Auth', 'phoneSubmitted');                    // 无负载
logger.logTdJson('Auth', 'onState', tdJsonString);        // TDLib JSON 入口
logger.logTdObject('Td', 'onOption', tdObject);           // DTO 入口
logger.logError('Net', appError);                         // AppErrors.toLogString
logger.isLoggable('debug'); logger.lastLine; logger.filteredCount;
```

- `logError` 只输出 `AppErrors.toLogString` 的稳定分类串
  （如 `network/dns/retryable=true`）；`message`/`cause` 永不入日志。
- level 过滤：`debug < info < warn < error`，被过滤的条数计入
  `filteredCount`；`emit` 返回 `null`。
- sink 可注入（默认 `console`）；接平台日志时在构造器传入。

## 白名单维护流程

`DEFAULT_TD_LOG_WHITELIST`（`src/main/ets/Logger.ets`）是**出厂最小集**，
目前只有 `updateAuthorizationState` / `updateConnectionState` /
`updateOption` / `error` 四个类型 + 全局 `@extra`。

新增一个 `@type` 条目必须 review（缺一不可）：

1. 该字段的子树是否可能携带**秘密**（密码/验证码/令牌/密钥/api_hash）？
   可能则不允许，或确认 GEN-004 元数据已覆盖（查
   `core/td_api_generated/src/main/ets/redaction/TdSensitiveFields.ets`）。
2. 是否可能携带 **PII**（手机号/邮箱/IP/姓名/地址）？同上网查 mask 规则。
3. 是否可能携带**聊天正文/媒体路径**？§14.4 禁止真实聊天正文入日志——
   不要白名单 `message.content`、`message.text`、`file.local.path` 这类字段；
   需要排查信息时白名单 id/date/count 级字段。
4. 在 `src/test/WhitelistLogger.test.ets` 补一条「含敏感假值的 fixture
   经 logTdJson 输出 100% 拦截」的用例。

## 与 GEN-004 元数据的关系

- 敏感字段元数据由 `tools/td_api_codegen/td_api_sensitive.py` 从
  schema IR 生成（规则表集中在生成器顶部：scoped/exact/suffix 三层 +
  决策注释；当前 124 构造器 / 154 字段 / 44 类型级清单）。
- TDLib 升级后跑三个生成器：`td_api_ir.py generate` →
  `td_api_arkts.py generate` → `td_api_sensitive.py generate`，
  再 `verify` 确认工作树无差异（CI 一致性检查）。
- 白名单是本模块的手写决策（业务相关），元数据是生成决策（schema 相关），
  两者独立演进；白名单漏字段时第二道防线仍按元数据兜底。

## 测试

```
./hvigorw test --mode module -p module=core_observability@default -p product=default --no-daemon
```

`src/test/` 全部 fixture 为假值（fake phone/token/password 等，见
`SensitiveFixtures.ets`），三个测试文件：

- `TdRedactJson.test.ets` — `redactTdJson` 全链路（认证/代理/初始化/
  PII/keep 决策/嵌套/@extra/数组/未知 @type 兜底/永不抛错）。
- `TdRedactFields.test.ets` — `redactFields` DTO 深拷贝（原对象不被修改）。
- `WhitelistLogger.test.ets` — 白名单过滤、两道防线串联、level 过滤、
  `logError` 稳定串、自定义白名单。

验收线：所有用例断言输出不含 `SensitiveFixtures.ALL_SECRETS` 中任何值
（secret fixtures 100% 拦截）。
