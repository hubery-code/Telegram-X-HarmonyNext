# feature/_template（UI-003）

UiState / Intent / Effect 基类约定 + Reducer 契约 + 最小示例 feature（计数器），
是计划 §5.11「MVVM + 单向数据流」在 feature 层的落地模板。纯 ArkTS：
**不 import ArkUI / Ability / 任何 Kit**，唯一依赖是 `@tgx/core-common`
（`file:../../core/common`，Clock / IdGenerator 注入用）。

## 内容

| 文件 | 说明 |
|---|---|
| `src/main/ets/contract/UiState.ets` | 三个空接口标记：`UiState`（可观察状态）、`Intent`（用户/系统意图）、`Effect`（一次性副作用描述）。编译期约定标记，无运行时行为。 |
| `src/main/ets/contract/Reducer.ets` | `Reducer<S, I, E>` 类型：`(state, intent, env) -> ReducerResult{ state, effects }`；`ReducerEnv { clock, ids }`；`reduced()` 便捷构造（effects 默认空）。 |
| `src/main/ets/example/` | 计数器示例：State（copyWith 不可变派生）+ 5 个 Intent（kind 判别字面量）+ 2 种 Effect（PersistCount / ShowToast）+ `counterReducer` 全分支实现。 |
| `src/test/CounterReducer.test.ets` | 15 个用例：每个 intent 分支、effect 数量/类型/参数精确断言、输入不可变、同输入同输出、env 差异可观测。 |

## 约定清单

**什么进 UiState**：页面渲染所需的全部可观察数据（含 loading / error 展示态）。
状态必须可整体替换：字段全部 `readonly`，变化经 `copyWith` 派生新实例。

**什么进 Intent**：用户动作（点击、输入、下拉）与系统事件（恢复、超时到期、
异步结果返回）。Intent 是 reducer 的唯一输入，UI 不直接改状态。

**什么进 Effect**：一次性、不可渲染的事情——导航跳转、弹 toast/对话框、
震动、发起异步请求（effect 只描述「要发起」，参数里带 requestId）。
Effect 由 EffectHandler / UseCase 执行，reducer 绝不执行。

**Reducer 禁忌（五条）**：
1. 禁止修改入参 `state`；未变化时返回原引用（UI 据此最小刷新）。
2. 禁止 `Date.now()` / `Math.random()` 等隐式源头，时间/ID 一律走 `env`。
3. 禁止 I/O 与异步：不发请求、不读存储、不弹窗，只产出 Effect 描述。
4. 禁止持有可变单例 / 全局缓存；同输入必须同输出。
5. 禁止在 reducer 内做 UI 文案拼接，Effect 携带本地化 key（messageKey）。

## 新 feature 四步创建法

1. **拷目录**：`cp -R feature/_template feature/<name>`，改模块名——
   `oh-package.json5` 的 `name`（如 `@tgx/feature-chat-list`）、
   `src/main/module.json5` 的 `name`（如 `feature_chat_list`）、
   删除 `src/main/ets/example/` 与 `src/test/CounterReducer.test.ets`
   （换自己的 feature 与测试）。
2. **建三件套**：State（copyWith）/ Intent（kind 判别字面量联合）/ Effect。
3. **写 reducer**：`export const xReducer: Reducer<XState, XIntent, XEffect> = ...`，
   `switch (intent.kind)` 穷尽分支。
4. **注册与接线**：根 `build-profile.json5` 的 `modules` **追加**本模块；
   建 `oh_modules/@tgx/core-common -> ../../../../core/common` 与
   `oh_modules/@ohos/hypium -> ../../../../oh_modules/.ohpm/@ohos+hypium@1.0.21/oh_modules/@ohos/hypium`
   符号链接（gitignored）；写 `src/test/List.test.ets` 汇总测试后跑：

```bash
./hvigorw test --mode module -p module=feature_<name>@default -p product=default --no-daemon
```

## ArkTS 严格模式注意（实测要点）

- **不支持对象 spread**：`{...state, count: n}` 不可写，必须显式 `copyWith` 工厂。
- **判别联合收窄靠字面量类型**：`readonly kind: 'savePressed' = 'savePressed'`
  （不是 `string`），否则 switch 分支内取不到变体字段。
- **未变化返回原引用**：`reduced(state)`；测试里用 `expect(result.state === state).assertTrue()` 守住。
- **跨 har 模块判 Result 分支禁用 `instanceof Ok/Err`**（类身份跨模块可能不一致，
  见 core/navigation 交接记录）；本模块未用 Result，若接入请用 `result.ok === false` 收窄。

## 测试

```bash
./hvigorw test --mode module -p module=feature_template@default -p product=default --no-daemon
```
