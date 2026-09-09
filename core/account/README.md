# core/account（CORE-003）

账号作用域与生命周期：`AccountScope`（单账号的完整作用域）+ `AccountRegistry`（scope 生命周期的唯一管理点）。纯 ArkTS，**无 ArkUI / Ability / Kit import**；文件系统一律经 `@tgx/platform-ports` 的 `AppFilesPort` 注入；事件/请求全部建立在 `@tgx/td-gateway`（CORE-002）之上，错误统一 `Result<_, AppError>`（`@tgx/core-common`）。

## 内容

| 文件 | 说明 |
|---|---|
| `AccountLifecycle.ets` | 生命周期纯 reducer：`active/hibernating/closed` × `activate/hibernate/close`。closed 终态对任何事件幂等返回 closed；未知事件 err(internal)。无副作用、无时钟，直接单测。 |
| `AccountIds.ets` | `AccountIdGenerator`（`nextAccountId()`，可注入）：`RandomAccountIdGenerator`（生产）/ `SequentialAccountIdGenerator`（测试）。accountId 是稳定字符串，跨进程存活，与进程内 clientId 不同。 |
| `AccountDirectories.ets` | 账号目录描述（计划 §5.6）：`files/accounts/<key>/{tdlib/db, tdlib/files, exports}` 的 `AppDirectory` 布局。**只描述不碰文件系统**；accountKey 校验（拒空/分隔符/`..`）是持久化路径安全的第一道闸。 |
| `AccountDescriptor.ets` | 持久化描述符（accountKey/accountId/createdAtMillis/enabled）+ 单条与清单（manifest schemaVersion=1）的编解码。任何形状问题 err(storage/corrupted)，原始内容不进错误 message。 |
| `AccountManifest.ets` | `AccountManifestStore`：清单经注入的 `AppFilesPort` 读写（`files/accounts/registry.json`），load/save/upsert/remove；清单不存在 = 空注册表（合法状态）。 |
| `AccountCancellation.ets` | 账号级取消域：`scope.request()` 的每个 `TdPendingRequest` 登记入域、结算自动注销；`close()` 时 `cancelAll()` 一次取消全部（迟到响应由 CORE-002 tombstone 安全丢弃）。 |
| `AccountEventIsolator.ets` | 跨账号事件隔离：每个 scope 的 gateway 包一层 `ScopeIsolatingBridge`（只放行本账号 clientId 的事件，其余在桥边界丢弃）；registry 的 monitor 订阅负责未知 clientId 记账 + `AppError(internal/core_account.unknown_client_id)` 上报（不静默）。 |
| `AuthorizationState.ets` | **占位**（交接 CORE-005）：`AuthorizationState` 联合类型（waitParams/waitDbKey/waitPhone/waitCode/wait2fa/waitRegistration/ready/loggingOut/closing/closed/failed）+ `AuthorizationStateHolder`（scope 持有它的位置）。转换 reducer 本包不实现。 |
| `AccountScope.ets` | 单账号作用域：accountKey/accountId/clientId、独占 `TdGateway`、生命周期、取消域、目录描述、授权状态挂载点、事件订阅（`subscribeEvents`）。 |
| `AccountRegistry.ets` | 唯一管理点：create/activate/hibernate/close/restoreAll/list/get/metrics。 |

## 生命周期状态图

```text
                 open(startActive=true)
                          │
        ┌─────────────────┼──────────────────┐
        ▼                 │                  ▼
     ┌───────┐  hibernate │              ┌───────────┐  activate   ┌───────┐
     │ active│ ─────────► │ hibernating │ ──────────► │ active│
     └───┬───┘            └──────┬──────┘             └───┬───┘
         │                       │                        │
         │ close                 │ close                  │ close
         ▼                       ▼                        ▼
     ┌──────────────────────────────────────────────────────┐
     │ closed（终态：任何事件幂等返回 closed；迟到事件由守卫丢弃计数） │
     └──────────────────────────────────────────────────────┘

create 幂等：同 accountKey 已有非 closed scope → 返回既有；closed → 移除重建。
restoreAll（冷启动 §6.1）：enabled=true → active；enabled=false → hibernating（可再 activate）。
```

## 契约要点（对照计划 §7）

- **所有者/版本**：`@tgx/core-account` 0.1.0（har 模块 `core_account`）。破坏性变更走「契约 PR → 提供方 PR → 消费方 PR」。
- **线程**：全部方法在 ArkTS 线程同步执行；事件经 CORE-002 的 TSFN/有序管线到达，无重入、无锁。
- **无全局可变单例**：`AccountRegistry` 由调用方（entry 装配层）构造持有；本模块不导出任何全局实例。registry 内部承载全部可变状态（scopes/clientId 集/清单）。
- **幂等**：create（同 key 返回既有）、activate/hibernate（同状态 no-op）、close（终态重复调用安全，registry 级重复 close 返回既有 closed scope）、registry start/stop、scope 级 cancel（复用 CORE-002 语义）。
- **取消**：close → `AccountCancellation.cancelAll()` → 全部 pending 以稳定取消错误结算（`isCancelledRequestError` 判定）；closed scope 的 `request()` 返回 err(unknown/`core_account.scope_closed`)，绝不向已关闭账号发请求。
- **迟到事件**：hibernate/close 停 bridge 订阅后，内部路由订阅保留作守卫——能到达的迟到/直达事件被丢弃并计入 `droppedEventCount`，绝不向监听泄漏。
- **事件隔离**：`ScopeIsolatingBridge` 按 clientId 在桥边界过滤，A 账号事件不进入 B 的 gateway/router/registry；未知 clientId 由 monitor 计数并上报 AppError internal。
- **恢复**：`restoreAll()` 逐账号隔离失败（单账号建 client 失败/重复管理 key/描述符损坏只影响该账号，failures 逐账号上报；清单整体损坏 → 单条 `accountKey='*'` 失败）。clientId **不持久化**（TDLib clientId 进程内有效，冷启动重新 createClient）。
- **持久化失败语义**：create 清单写失败 → 关闭已开 scope 并 err（注册表不留半态）；close 清单移除失败 → scope 已关但保留在注册表，可重试；activate/hibernate 清单写失败 → 运行时状态已翻转，err 透传由调用方决定重试（不静默回滚）。
- **敏感数据**：描述符/清单不含手机号以外秘密；编解码错误 cause 不含原始内容；账号目录解析越界由 AppFilesPort 拒绝（`..`/绝对路径 err(parameter/invalid)）。

## 冷启动时序（§6.1 落地）

1. entry 装配层构造 `AccountRegistry`（注入 bridge/files/idGenerator/clock），`registry.start()`（未知 clientId monitor）。
2. `registry.restoreAll()`：读 `files/accounts/registry.json` → 逐账号 `AccountScope.open`（隔离桥 → createClient → 内部事件订阅 → enabled 时 gateway.start）。
3. 每个 scope 以 `authorization = waitParams` 起步；CORE-005 的 auth reducer 订阅 `scope.subscribeEvents` 接收 `updateAuthorizationState` 并驱动 `authorizationHolder.replace(...)`。
4. entry 用 `registry.list()` 渲染账号感知的根状态。

## 交接点

- **CORE-005（AuthorizationStateMachine）**：状态联合与 holder 已定义（`AuthorizationState.ets`）。实现 `updateAuthorizationState` 事件 → `AuthorizationState` 的纯转换 reducer，经 `scope.subscribeEvents()` 订阅、`scope.authorizationHolder.replace()` 提交。UI 只读 `scope.authorization`。
- **AUTH-001（登录 UI）**：经 `registry.create(accountKey)` 开新号流程；渲染 `scope.authorization`；每个账号的数据访问走 `scope.request(method, params)`（自动登记取消域）与 `scope.subscribeEvents`。
- **BRG/platform native**：生产 `TdNativeBridgeLike` 由 platform adapter 提供；**`closeClient/shutdown` 仍不在桥契约内**——close 目前只停订阅与取消请求，native client 句柄的释放归属后续平台桥扩展（CORE-002 README 交接点 2）。
- **platform/files**：`AppFilesPort` 生产 adapter 落地后原样注入；清单写应满足 PLAT-001 的原子写约定（临时文件 + rename）。
- **PLAT-002 RDB**：账号清单当前为 JSON 文件（manifest schemaVersion=1）；若迁移到 RDB 账号表，替换 `AccountManifestStore` 即可，registry/scope 接口不变。
- **单调时钟**：gateway 超时语义依赖注入 `Clock`（同 CORE-002 交接：生产待 MonotonicClockPort 注入替换 SystemClock 近似）。

## ArkTS 工程要点（实测新增）

- **字段与 getter 不得同名**（private 字段 `current` + getter `current` → Duplicate identifier），私有字段用 `currentState`/`droppedEventCountValue` 之类区分命名。
- `Result.getOrNull()` 返回类型是 `T | null`（Err 分支返回 null），**严格空检查下不能直接赋给 `T`**；测试 harness 用「`if (result.ok) return result.value;` + 不可达 `throw`（前置 `expect(...).assertTrue()` 必抛）」的 helper 收窄。
- 跨模块依赖 `@tgx/td-gateway` 的 `TdWireObject`/`wireString` 等可直接复用（本包编解码即基于 wire 类型，与 GEN 的 `TdJsonObject` 同形）。

## 测试

```bash
./hvigorw test --mode module -p module=core_account@default -p product=default --no-daemon
# Tests run: 60, Failure: 0, Error: 0, Pass: 60
```

`src/test/`：`FakeAccountBridge`（多 client 桥 fake，createClient/send 失败注入）、`FlakyFiles`（FakeAppFiles + 读写失败注入）、`TestWire`。覆盖：生命周期 reducer 全矩阵、描述符/清单编解码、目录校验、scope 启停/取消/迟到丢弃/事件过滤/授权占位、registry 幂等/持久化往返/恢复隔离/未知 clientId/跨账号隔离。
