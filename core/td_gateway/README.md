# core/td_gateway（CORE-002）

TDLib JSON 接口的 ArkTS 侧网关层：`TdNativeBridgeLike` 契约 + `RequestRegistry`（`@extra.requestId` 关联 / 超时 / 取消 / 迟到响应）+ `OrderedEventRouter`（按 client 严格有序分发）+ `TdGateway` facade。纯 ArkTS，无 ArkUI / Ability / Kit / Node-API 依赖，全部经 `@tgx/core-common` 的 Result/AppError/Clock/IdGenerator 表达失败与注入依赖。

## 内容

| 文件 | 说明 |
|---|---|
| `src/main/ets/TdWire.ets` | TDLib JSON wire 类型：`TdWireValue`/`TdWireObject`（与 GEN 的 `TdJsonRaw`/`TdJsonObject` 同形）、`@` 字段读取助手、十进制字符串比较（64 位安全）、clientId 校验。 |
| `src/main/ets/TdNativeBridgeLike.ets` | 计划 §5.2 Node-API 最小契约的 ArkTS 镜像：`getVersion/createClient/send/execute/subscribeUpdates/unsubscribe/getMetrics`；事件 envelope 携带 `clientId` + 十进制 string `sequence` + `payloadUtf8`。 |
| `src/main/ets/TimeoutScheduler.ets` | 超时定时器抽象：`RealTimeoutScheduler`（生产）+ `ManualTimeoutScheduler`（测试虚拟时间）。 |
| `src/main/ets/RequestRegistry.ets` | 请求注册表：注入 `@extra.requestId` → send → 挂起；响应/TDLib error/超时/取消四种结算；迟到响应安全丢弃并计数。 |
| `src/main/ets/OrderedEventRouter.ets` | update 流路由器：按 (clientId, sequence) 校验单调性（乱序上报 AppError internal，不静默；重复幂等丢弃），按 `@type`/`clientId` 订阅。 |
| `src/main/ets/TdGateway.ets` | facade：桥事件流分流——带 `@extra.requestId` 的负载进 registry，其余进 router；payload 解析失败计数并上报。 |

## 接口契约（对照计划 §7 契约规范）

- **所有者/版本**：`@tgx/td-gateway` 0.1.0（har 模块 `core_td_gateway`）。破坏性变更走「契约 PR → 提供方 PR → 消费方 PR」。
- **线程**：所有方法在 ArkTS 线程调用；事件由 native TSFN 在 ArkTS 线程回调（§5.2/§5.4）。`handleNativeEvent` 内部全同步、按 native sequence 顺序进、无重入。
- **顺序保证**：update 流按 (clientId, sequence) 严格单调分发；sequence 为十进制 string（64 位不走 JS number/bigint，比较经 `compareDecimalString`）。乱序 → `AppError(internal/td_gateway.sequence_monotonic)` 经 `onProtocolError` 上报且事件丢弃（不静默）；重复 sequence → 丢弃并计 `duplicateCount`（幂等）。
- **请求关联**：每个 request 注入唯一 `@extra.requestId`（IdGenerator 可注入；已存在 `@extra` 合并保留其他字段、不污染调用方对象）。响应按 requestId 匹配；同 requestId 多请求靠唯一 ID 隔离，多 client 互不串话（跨 client 响应计 `crossClientResponseCount` 拒绝结算）。
- **超时**：默认 10s（`defaultTimeoutMillis` 可配、每请求 `timeoutMillis` 可覆盖）→ `Err(AppError network/timeout, retryable=true)`。超时判定以注入的 `Clock.monotonicMillis()` 为准（生产 `SystemClock`；**真单调语义待 platform 单调时钟注入**，见 core/common 交接说明）。
- **取消**：`TdPendingRequest.cancel()`（幂等，重复返回 false）或 `TdAbortSignal`（注册时与结算时检查）→ `Err(unknown/td_gateway.request_cancelled)`，用 `isCancelledRequestError()` 判定（AppError 七类无 cancel 专用 kind，此为稳定映射）。取消后迟到响应只计数不改判。
- **迟到响应**：已 settle（resolved/timed_out/cancelled）后到达的响应绝不二次 resolve，计 `lateResponseCount` 后丢弃；从未注册过的 requestId 计 `unmatchedResponseCount`（两类分开统计）。
- **错误码**：TDLib error 对象（`@type:"error"`）经 `AppErrors.fromTdlibError(code, message)` 映射为稳定 tdlib 分类（401→unauthorized 不重试 / 429→too_many_requests 重试 / 400→bad_request / 404→not_found / 500→internal 重试 / 其他→unknown 重试）；**原始 error.message 只允许进 cause**（§7 禁止当用户文案）。桥 send 同步抛异常 → `platform/-1` 可重试。非法 clientId → `parameter/invalid` 且不发送。
- **永不 reject/throw**：`TdPendingRequest.promise` 恒为 `Promise<Result<TdWireObject, AppError>>`。
- **背压/内存**：事件不在本层缓存（native 有界队列负责，§5.4）；registry 的 tombstone（已 settle requestId）无界增长，修剪策略归 AccountScope（见下）。
- **敏感字段/日志**：本层不进用户文案、不落日志；诊断串只含 kind/code/requestId。
- **幂等/重复事件**：`cancel()`/`unsubscribe()`/`start()`/`stop()` 全部幂等；重复 sequence 不重复分发。
- **测试向量**：`src/test/` 53 用例（FakeBridge 模拟异步响应、TDLib error、乱序、重复、迟到、send 失败、非法 JSON）：

```bash
./hvigorw test --mode module -p module=core_td_gateway@default -p product=default --no-daemon
```

## 与 BRG 桥、GEN 类型的对接

- **BRG（native/tdcore/napibridge）**：生产 adapter 把 `libtdcore_napi.so` 导出包成 `TdNativeBridgeLike`。当前 entry 的临时 `TdBridge`（`entry/src/main/ets/tdbridge/TdBridge.ts`）即其雏形：它已把 `sequence: string` 从 native 十进制字符串侧保留（entry 内转 bigint，本层直接用 string，不经过 bigint）。迁移时 entry 临时封装删除，由 platform/native adapter 实现本契约。**closeClient/shutdown**：§5.2 要求 `closeClient` 幂等、关闭后事件安全丢弃并计数——本接口刻意未包含它们，归属 AccountScope 生命周期（CORE-003）扩展（见下）。
- **GEN（core/td_api_generated）**：本层 `TdWireValue/TdWireObject` 与 `TdJsonRaw/TdJsonObject` 同形，`JSON.parse` 产物可直接 `as` 互转。分工：gateway 只搬运 wire 记录（不 decode），消费方在订阅回调里用 `decodeTdObject`/`TdResponseMap` 把 `TdRoutedEvent.payload` 解码成 DTO；请求侧由调用方用 GEN 的 `encodeXxx` 产出参数记录传给 `TdGateway.request(clientId, 'methodName', params)`。
- **ArkTS 工程要点（实测）**：① `TdWireObject` 是「空 interface extends Record」（类型别名经 Record 自引用会被判循环引用；空 interface 不是合法参数字面量目标）。② 参数位置的对象字面量只认「带自有属性的 interface」——本模块 API 全部接收变量/表达式，测试用 `TestWire.ets` 的 `tdWire(json)`（JSON.parse + as）构造 wire 记录。③ ArkTS 禁结构类型隐式转换：回调参数类型必须与声明完全一致。④ 跨 har 判 Result 用 `r.ok === false` 收窄，禁用 `instanceof`。

## 交给 CORE-003（AccountScope）的扩展点

1. **Tombstone 修剪**：`RequestRegistry` 用 tombstone 集合判迟到响应，长期运行需按 client 生命周期修剪（client 关闭时清除该 client 历史；当前 tombstone 为全局）。
2. **closeClient/shutdown**：§5.2 的幂等关闭与「关闭后事件安全丢弃并计数」在 AccountScope 层实现（持有 registry/router 句柄，关闭时 `router.resetClient(clientId)` 并拒绝新请求）。
3. **单调时钟注入**：生产超时语义依赖 `Clock.monotonicMillis()` 真单调实现（PLAT MonotonicClockPort 落地后注入，替换 `SystemClock` 近似）。
4. **clientId → AccountKey 映射**：registry/router 以 int32 clientId 为键；AccountScope 负责 clientId 与账号作用域的映射及多账号隔离策略（本层已保证多 client 数据互不串话）。
5. **update → domain event 的 decode/降采样**：§5.4 允许合并/降采样的类别（下载进度、typing 等）与禁止丢弃的类别（新消息、授权状态等）的分流策略在 AccountScope/reducer 层落地，router 只保证有序与过滤订阅。

## 测试

```bash
./hvigorw test --mode module -p module=core_td_gateway@default -p product=default --no-daemon
# Tests run: 53, Failure: 0, Error: 0, Pass: 53
```
