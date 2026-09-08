# napibridge — TDLib Node-API 桥 (BRG-001/002)

`libtdcore_napi.so`：Node-API 原生模块，把 TDLib 全局 client C API
(`td_create_client_id` / `td_send` / `td_receive` / `td_execute`) 暴露给
ArkTS。TDLib 本体静态不可变地以 `libtdjson.so` 形式随 HAP 打包（TDN-002
产物），本模块通过 imported target 链接它。

## 接口契约（对照计划 §5.2 TdNativeBridge 最小子集）

| ArkTS 签名 | 语义 | 原生实现 |
|---|---|---|
| `getVersion(): string` | TDLib 版本号（如 `1.8.67`） | `td_execute(getOption version)`，解析 `optionValueString`；解析失败回退返回原始 option JSON |
| `execute(requestUtf8: string): string \| null` | 同步执行 TDLib 请求 | `td_execute(request)`；无同步响应时返回 `null` |
| `createClient(): number` | 创建客户端，返回 int32 clientId | `td_create_client_id()` |
| `send(clientId: number, requestUtf8: string): void` | 异步发送请求（fire-and-forget） | `td_send(clientId, request)` |

### 错误与校验约定（§5.2 约束的落地）

- 参数类型错误（非 string / 空串 / clientId 非非负 int32）→ 抛 ArkTS
  TypeError，不 crash。
- `execute` 收到非 JSON 对象（首非空白字符不是 `{`）→ 不调用 TDLib，
  直接返回 TDLib 风格的错误结构字符串
  `{"@type":"error","code":400,"message":"request must be a JSON object starting with '{'"}`。
- 其余非法 JSON 交给 TDLib 自身处理（TDLib 对畸形输入返回 error 对象）。
- C++ 异常不穿过 ABI：模块编译为 `-fno-exceptions` 风格使用（未启用），
  所有失败路径走 napi error/null。

### 尚未实现（后续工作包）

- `receive` / `subscribeUpdates`（TSFN 回调线程）→ BRG-003
- 有界队列 / 背压 → BRG-004
- `closeClient` / `shutdown` 生命周期 → BRG-005
- `@extra.requestId` 关联、超时、取消（RequestRegistry 属于
  core/td_gateway 层，不属本模块）

## ArkTS 侧使用（当前为验证页；正式封装在 core/td_gateway）

```ts
import native from 'libtdcore_napi.so';
const version: string = native.getVersion();
const resp: string | null = native.execute('{"@type":"getTextEntities","text":"@telegram"}');
const clientId: number = native.createClient();
native.send(clientId, '{"@type":"setTdlibParameters",...}');
```

当前调用点：`entry/src/main/ets/pages/Index.ets`（验证页，临时）。
后续由 core/td_gateway 定义稳定 facade，验证页代码届时移除。

## 构建

- HAP 内构建（正式路径）：`entry/build-profile.json5` 的
  `buildOption.externalNativeOptions` → `entry/src/main/cpp/CMakeLists.txt`
  → `add_subdirectory(native/tdcore/napibridge)`。hvigor 自动把
  imported 的 `libtdjson.so` / `libcrypto.so.3` / `libssl.so.3` 打进
  hap（不要再放 `entry/libs/`，会报重复文件 00306049）。
- 环境要求：TDLib 构建产物存在（`tools/native/build-tdlib.sh`，含
  `build/arm64-v8a/stripped/libtdjson.so`，soname=`libtdjson.so`）。
- 构建命令：`./tools/ci/build.sh debug`。

## 已知限制

- `import native from 'libtdcore_napi.so'` 目前无 `.d.ts`，hvigor 编译
  告警 "module for 'libtdcore_napi.so' is not verified"（功能正常；
  后续补 d.ts 消除告警并启用类型校验）。
- `send` 之后没有 `receive`，异步响应暂不可见（BRG-003）。
- hap 中 tdjson 为 RelWithDebInfo 编译、strip 后 ~32MB；正式 Release
  管线（符号归档、build-id 绑定）属 TDN-004。
- 桥当前在 ArkTS 调用线程同步执行 `execute`/`send`；TDLib 内部有
  自己的 actor 线程，不会阻塞 TDLib worker，但长 JSON 编排在 UI 线程
  的耗时预算（§14.2 ≤4ms）需在 BRG-002 正式封装时评估。
