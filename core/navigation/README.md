# core/navigation — Typed navigation（UI-002）

强类型路由契约 + 参数编解码 + 导航栈抽象。纯 ArkTS，不依赖 ArkUI `Navigation`
组件、不依赖任何 Kit；`entry` 侧组件适配见下文「与 ArkUI Navigation 的接入预留」。

模块名：`core_navigation`；包名：`@tgx/core-navigation`；依赖 `@tgx/core-common`
（Result / AppError）。

## 文件与职责

| 文件 | 职责 |
|---|---|
| `src/main/ets/Route.ets` | `AppRoute` discriminated union（判别字段 `name`）、`ParamSpec` 参数 schema、`RouteDefinition`、`ROUTE_DEFINITIONS` 内置路由表 |
| `src/main/ets/RouteRegistry.ets` | 注册/查找路由；route name ↔ path 模板互转；重复 name/模板与非法模板注册即拒绝 |
| `src/main/ets/RouteCodec.ets` | `parse`（path → 类型化 route）、`encode`（route → path）、`parseDeepLink`（外部 URI → route）、`DeepLinkRule` 白名单规则 |
| `src/main/ets/NavigationStack.ets` | 纯逻辑导航栈：push / replace / pop / popToRoot / 恢复序列化（连续重复去重） |

约定：**所有解析失败返回 `Err(AppError)`，不抛异常**（计划 §5.11：参数必须可
序列化、可恢复；非法输入在解析层被拒绝）。

## 路由命名规范

- route name：小驼峰（`'chat'`、`'chatInfo'`、`'settingsSection'`），即 union 判别
  字段取值，全工程唯一；
- path 模板：小驼峰段 + `{param}` 占位（`'chat/{chatId}'`、`'mediaViewer/{chatId}/{messageId}'`），
  不带前导 `/`；
- 参数名：小驼峰。模板内参数为位置参数；**可选参数不进模板**，parse/encode 走
  query string（`'chat/5?threadId=7'`、`'search?query=abc'`）；
- 参数类型三种可序列化标量：`string` / `int` / `boolean`。
  - `int` 必须是十进制整数且在 `Number.isSafeInteger` 范围内（TDLib int53 数据
    安全往返），可配 `min` / `max`；
  - `string` 可配 `maxLength` / `pattern`（如 settingsSection 的
    `SECTION_PATTERN = /^[a-z][a-zA-Z0-9_]*$/`）；
  - `boolean` 仅接受 `'true'` / `'false'`。

严格性：未知路由、未知参数（含 query 中未声明的 key）、重复参数 key、空段、非法
百分号编码一律 `Err`；所有参数值经 `encodeURIComponent`，path 中不会出现结构字符。

## 内置路由

| route name | path 模板 | 参数 |
|---|---|---|
| `home` | `home` | — |
| `auth` | `auth` | — |
| `chat` | `chat/{chatId}` | `chatId: int` 必填；`threadId: int` 可选（query，≥1） |
| `chatInfo` | `chatInfo/{chatId}` | `chatId: int` 必填 |
| `settings` | `settings` | — |
| `settingsSection` | `settings/{section}` | `section: string` 必填，≤64，pattern 见上 |
| `search` | `search` | `query: string` 可选，≤256 |
| `mediaViewer` | `mediaViewer/{chatId}/{messageId}` | `chatId: int`；`messageId: int` ≥1 |

## 加新路由的步骤

1. `Route.ets`：在 `AppRoute` union 增加接口（`readonly name: '新名字'` + 参数字段，
   可选参数用 `readonly xxx?: T`）；
2. `Route.ets`：在 `ROUTE_DEFINITIONS` 增加 `RouteDefinition`（`pathTemplate` +
   参数 `ParamSpec` 列表；模板占位必须在 schema 中声明，注册时会校验）；
3. `RouteCodec.ets`：`buildRoute` 的 switch 增加构造分支；`collectRouteParams`
   增加字段收集分支（encode 用）；
4. 如需外部 deep link：在 `defaultDeepLinkRules` 增加 `DeepLinkRule`
   （scheme/host 白名单 + query 参数名映射）；
5. 在 `RouteCodec.test.ets` 补 round-trip 与非法参数用例。

## Deep link

`parseDeepLink(uri, rules)` 按白名单规则解析外部 URI：

```ts
const codec = new RouteCodec(defaultRegistry());
const r = codec.parseDeepLink('tg://chat?chatId=123&threadId=5', defaultDeepLinkRules());
// Ok({ name: 'chat', chatId: 123, threadId: 5 })
```

- 规则 = `{ scheme, host, pathTemplate?, route, queryParams: [{from, to}] }`；
  host 匹配前转小写；未映射的 query 参数**忽略**（外部 URI 常带无关参数），
  映射后的参数走与内部 path 相同的 schema 校验；
- 未知 scheme/host、path 与模板不符、参数缺失或非法 → 安全拒绝（`Err`）；
- 默认规则含示例：`tg://chat?chatId=…`、`tg://settings`、`tg://search?query=…`、
  `https://t.me/chat/{chatId}`。真实 t.me 映射（`resolve?domain=…` 等）在
  feature 接入阶段按产品需求细化扩充。

## 导航栈与恢复

```ts
const stack = new NavigationStack();
stack.push({ name: 'home' });
stack.push({ name: 'chat', chatId: 123 });
stack.replace({ name: 'chat', chatId: 456 }); // 替换栈顶；空栈等价 push
stack.pop();          // LIFO；空栈返回 null
stack.popToRoot();    // 保留栈底
```

- `serialize(codec)`：换行分隔的 path 列表（编码后值不含结构字符，换行分隔安全）；
- `NavigationStack.restore(text, codec)`：逐条 parse；任一非法 → 整体 `Err`
  （恢复数据不可信时宁可丢弃）；**与前一条完全相同的连续项去重**；
- 栈内只能存 `AppRoute` 值对象（可序列化），禁止塞 ViewModel/native handle
  （计划 §5.11）。

### 与 ArkUI Navigation 组件的接入预留（entry 后续工作）

本模块不含任何 ArkUI 依赖。entry 侧 adapter 建议：

- 持有 `NavigationStack` 作为唯一事实源，push/replace/pop/popToRoot 同步桥接到
  ArkUI `Navigation` 的 `NavPathStack`（或拦截 `NavPathStack` 回调回写栈）；
- 页面 onReady 时从 route 参数（`NavDestination` 入参）还原 `AppRoute`；参数传递
  用 `encode` 后的 path 字符串或 `AppRoute` 值对象本身（均可序列化）；
- 进程回收/退后台恢复：在 Ability 的 `onSaveState`/存储里持久化
  `stack.serialize(codec)`，冷启动 `restore` 重建；
- deep link 入口（EntryAbility `onCreate`/`onNewWant`）统一走
  `parseDeepLink` → 成功后 push，失败进 fallback 路由并记录脱敏日志
  （`AppErrors.toLogString`）。

## 测试

```bash
./hvigorw test --mode module -p module=core_navigation@default -p product=default --no-daemon
```

单测入口 `src/test/List.test.ets`（hvigor harness 固定 import 它）。覆盖验收点：
解析↔编码 round-trip（全部内置路由）、缺失必填参数、类型/范围/pattern 错误参数、
未知路由、未知/重复/非法编码参数、deep link 正常与各类非法输入、导航栈
push/pop/replace/popToRoot、恢复序列化 round-trip 与连续重复去重。
