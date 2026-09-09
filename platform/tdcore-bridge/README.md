# platform/tdcore-bridge — TdCoreBridge 生产适配器（BRG-006）

`libtdcore_napi.so` 的 Node-API 导出 → `TdNativeBridgeLike` 契约（CORE-002）。

替代 `entry/src/main/ets/tdbridge/TdBridge.ts`（BRG-003/004 临时验证封装）。

## 契约实现对照表

| TdNativeBridgeLike 方法 | 实现方式 | 说明 |
|---|---|---|
| `getVersion(): string` | 直透 `native.getVersion()` | TDLib 版本号 |
| `execute(requestUtf8: string): string \| null` | 直透 `native.execute()` | 同步执行 |
| `createClient(): number` | 直透 `native.createClient()` | TDLib int32 clientId |
| `send(clientId, requestUtf8): void` | 直透 `native.send()` | 异步发送 |
| `subscribeUpdates(sink): number` | 位置参数 → TdNativeEvent 对象 | sequence 保持十进制 string（64 位安全） |
| `unsubscribe(subscriptionId): void` | 直透 `native.unsubscribe()` | 幂等（native 侧对未知 id 安全） |
| `getMetrics(): TdNativeBridgeMetrics` | 直透 `native.getMetrics()` | 字段名一致 |

### sequence 转换

native sink 签名（5 个位置参数）：
```ts
(schemaVersion: number, clientId: number, sequence: string,
  payloadUtf8: string, receivedAtMonotonicMs: number) => void
```

契约 sink 签名（事件对象）：
```ts
(event: TdNativeEvent) => void
```

适配器把 5 个位置参数组装为 `TdNativeEvent` 对象，sequence 保持 string，
不做 BigInt 转换（与临时 TdBridge.ts 的 BigInt 转换不同，遵循 CORE-002 契约）。

### closeClient / shutdown

不在 `TdNativeBridgeLike` 接口（CORE-002 刻意最小化），由 AccountScope（CORE-003）层保证。

## 可注入性

构造器接受可选 `nativeModule: TdCoreNativeModule`：
- 缺省（production）：用模块级 `import native from 'libtdcore_napi.so'`
- 注入（测试）：传入 FakeNativeModule，不依赖 .so

## 单测

| 用例 | 需真机 | 说明 |
|---|---|---|
| module_imports_and_class_exists | 否 | 注入 Fake，验证类实例化 |
| implements_TdNativeBridgeLike_contract | 否 | 验证 7 个方法存在 |
| getVersion_returns_nonempty_string | 否 | 注入 Fake |
| createClient_returns_number | 否 | 注入 Fake |
| subscribeUpdates_returns_number_subscriptionId | 否 | 注入 Fake |
| unsubscribe_is_idempotent_no_throw | 否 | 注入 Fake，重复 unsubscribe 不抛 |
| getMetrics_returns_object_with_droppedCount | 否 | 注入 Fake |
| getMetrics_has_all_required_fields | 否 | 注入 Fake |
| subscribe_delivers_TdNativeEvent_with_string_sequence | 否 | 注入 Fake，验证位置参数→事件对象组装 |
| execute_returns_response_or_null | 否 | 注入 Fake |
| createClient_returns_incrementing_ids | 否 | 注入 Fake |

**需真机的测试（NeedsDevice，未在 CI 执行）：**
- TdCoreBridge() 无参构造（production native import）
- getVersion() 返回真实 TDLib 版本
- createClient() 创建真实 TDLib client
- send() 投递到真实 TDLib actor
- subscribeUpdates() 接收真实 TDLib update 事件

## 与 entry 装配的关系

entry 通过 `@tgx/platform-tdcore-bridge` 依赖引入本模块，构造 `TdCoreBridge` 实例，
传入 `AccountRegistry` 作为 `TdNativeBridgeLike` 桥。entry 的临时 `TdBridge.ts`
在装配完成后可删除（本模块已替代其全部功能）。
