# napibridge — TDLib Node-API 桥 (BRG-001..004)

`libtdcore_napi.so`：Node-API 原生模块，把 TDLib 全局 client C API
(`td_create_client_id` / `td_send` / `td_receive` / `td_execute`) 暴露给
ArkTS。TDLib 本体以 `libtdjson.so` 随 HAP 打包（TDN-002 产物），本模块经
imported target 链接。

## 接口契约（计划 §5.2 TdNativeBridge + §5.4 事件模型）

### 请求面（BRG-001/002）

| ArkTS 签名 | 语义 | 原生实现 |
|---|---|---|
| `getVersion(): string` | TDLib 版本号（如 `1.8.67`） | `td_execute(getOption version)` + 解析 `optionValueString`（失败回退原始 JSON） |
| `execute(requestUtf8: string): string \| null` | 同步执行 | `td_execute(request)` |
| `createClient(): number` | 创建客户端 | `td_create_client_id()`（int32 校验） |
| `send(clientId: number, requestUtf8: string): void` | 异步发送 | `td_send(clientId, request)` |

### 事件面（BRG-003）

| ArkTS 签名 | 语义 |
|---|---|
| `subscribeUpdates(sink: TdEventSinkRaw): number` | 注册回调，返回 subscriptionId；首个订阅惰性启动 receive 线程 + TSFN |
| `unsubscribe(subscriptionId: number): void` | 注销；最后一个订阅移除时停止 receive 线程并释放 TSFN |

sink 签名（与 §5.2 TdNativeEvent 对齐）：

```ts
type TdEventSinkRaw = (
  schemaVersion: number,   // 当前固定 1
  clientId: number,        // TDLib 全局 API 的 @client_id
  sequence: string,        // per-client 单调递增，十进制字符串（避免 JS number 精度问题）
  payloadUtf8: string,     // 原始 TDLib JSON（含 @type/@client_id/@extra）
  receivedAtMonotonicMs: number  // steady_clock 毫秒（double）
) => void;
```

`entry/src/main/ets/tdbridge/TdBridge.ts` 将其包装为
`TdNativeEvent`（sequence 转 `bigint`）。该文件是 entry 内临时验证封装，
正式 facade 归 core/td_gateway。

### 指标（BRG-004）

`getMetrics(): { queueSize, overflowWaitCount, droppedCount, eventsForwarded,
subscriptions, dispatcherRunning }`

| 指标 | 含义 |
|---|---|
| `queueSize` | 有界队列当前深度（容量 1024） |
| `overflowWaitCount` | receive 线程因队列满而阻塞等待的次数（背压生效计数） |
| `droppedCount` | 丢弃事件数。**语义保证恒为 0**（新消息/删除编辑/授权状态/文件完成绝不丢弃） |
| `eventsForwarded` | 已从队列分发到 ArkTS 的事件总数 |
| `subscriptions` / `dispatcherRunning` | 订阅数 / 分发线程是否在跑 |

## 事件管线与背压策略（§5.4 落地）

```
td_receive 线程 (100ms 轮询, 可停止)
  -> 解析 @client_id, 分配 per-client 单调 sequence
  -> 有界队列 (1024, mutex+condvar)
       满: 阻塞 receive 线程等待消费, overflowWaitCount++
       (TDLib 自身有缓冲; 绝不丢语义事件)
  -> napi_call_threadsafe_function (空唤醒信号, TSFN 队列不设上限)
  -> ArkTS 线程 TsfnDispatch: 整批出队(保序) -> 逐个事件调用每个订阅 sink
```

决策记录：

- **有界队列位置**：队列在 receive 线程与 TSFN 之间，TSFN 只做空唤醒
  （数据不出队列），因此内存有界与 1024 上限严格成立。
- **批量 vs 单事件回调**：TSFN 每次唤醒在 ArkTS 线程**批量出队**，但
  对 sink **逐事件回调**（保序简单、契约直观）。TSFN 唤醒本身天然合并
  （drain-all 语义）。若 P0 压测证明延迟不足，再按字节/延迟双阈值改
  批量数组回调（§5.4 允许），届时需 ArkTS 侧配套改造。
- **顺序保证**：单 receive 线程分配 sequence ⇒ 同 client 严格有序；
  多 client 交错事件靠 clientId 区分（跨账户隔离在 core/td_gateway
  的 Ordered Event Router 完成）。
- **线程安全**：napi_env/napi_ref 仅在 ArkTS 线程使用（subscribe/
  unsubscribe/TsfnDispatch 都在该线程）；receive 线程只碰队列与 TSFN
  句柄。BridgeState 为进程生命周期单例（静态对象，不销毁），
  unsubscribe 与在途回调之间不存在 use-after-free。TSFN 在 receive
  线程 join 之后才 release。
- **可合并事件降采样**（下载/上传进度、typing 等）：本次未实现
  （BRG-004 范围仅队列+背压+指标），后续按 §5.4 在 ArkTS 侧或
  dispatcher 层增加。

### 错误与校验约定

- 参数类型错误（非 string / 空串 / clientId 非非负 int32 / sink 非
  function）→ 抛 TypeError，不 crash。
- `execute` 收到非 JSON 对象 → 直接返回 TDLib 风格 error JSON；
  其余畸形 JSON 由 TDLib 自身返回 error 对象。
- C++ 异常不穿越 ABI。

### 尚未实现（后续工作包）

- `closeClient` / `shutdown` 生命周期（BRG-005）
- `@extra.requestId` 关联、超时、取消（core/td_gateway RequestRegistry）
- 可合并事件降采样；P1 性能门禁前的 ArrayBuffer/原生过滤（§5.4）

## 构建

- HAP 内构建（正式路径）：`entry/build-profile.json5`
  `buildOption.externalNativeOptions` → `entry/src/main/cpp/CMakeLists.txt`
  → `add_subdirectory(native/tdcore/napibridge)`。hvigor 自动把 imported
  的 `libtdjson.so` / `libcrypto.so.3` / `libssl.so.3` 打进 hap（不要再放
  `entry/libs/`，会报 00306049 重复文件）。
- 环境要求：TDLib 构建产物（`tools/native/build-tdlib.sh`，含
  `build/arm64-v8a/stripped/libtdjson.so`，soname=`libtdjson.so`）。
- 构建命令：`./tools/ci/build.sh debug`。

## 已知限制

- `import 'libtdcore_napi.so'` 缺 `.d.ts`，hvigor 告警 "not verified"
  （功能正常）。
- `eventsForwarded` 按事件计数（一次事件多个订阅者只计一次）。
- 进程内只有一个分发管线（所有订阅共享一条 receive 线程），多订阅是
  扇出而非多路独立消费；需要独立消费时在 core 层开多个订阅即可（事件
  会扇出给每个 sink）。
- 桥在 ArkTS 调用线程同步执行 `execute`/`send`；TDLib 内部自有 actor
  线程，但长 JSON 编排在 UI 线程的耗时预算（§14.2 ≤4ms）需在正式封装
  时评估。
