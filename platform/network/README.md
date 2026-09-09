# platform/network（PLAT-004）

NetworkStatePort 的生产 adapter：基于 HarmonyOS Network Kit（`@ohos.net.connection`）把系统连通性事件转成契约快照流（PLAT-001 契约的实现侧）。

## 结构

| 文件 | 说明 | Kit 依赖 |
|---|---|---|
| `src/main/ets/ConnectivityMapping.ets` | 映射表 + 去重器（纯逻辑）：bearer → wifi/cellular/ethernet/other、多 bearer 优先级（ethernet > wifi > cellular > other，与系统默认网络优先级一致）、metered 判定（`networkCap` 不含 `NET_CAPABILITY_NOT_METERED`=11 即计费）、`SnapshotDeduper` 连续同值去重 | 无 |
| `src/main/ets/ConnectivitySource.ets` | 事件源抽象接口（`current()` + `register(listener)`） | 无 |
| `src/main/ets/ConnectivityAdapter.ets` | `NetworkStatePort` 生产 adapter（Kit-free 引擎）：注册即派初始快照（经去重器，防与紧随的 Kit 事件重复）、事件去重、注册失败透传 err、`current()` 异常兜底断网快照。构造可注入 `ConnectivitySource`，默认 `ConnectivityKitSource` | 间接（默认构造） |
| `src/main/ets/ConnectivityKitSource.ets` | Kit 实现：`createNetConnection()` 监听 `netAvailable`/`netLost`/`netCapabilitiesChange`；`current()` 用 `getDefaultNetSync()`+`getNetCapabilitiesSync()` 同步取默认网络。注销 = `unregister()`（本 SDK 的 NetConnection 无 `off`，unregister 移除全部监听）+ active 闭包丢弃迟到事件，幂等 | **唯一 import Kit 的文件** |

## 契约语义落实（NetworkStatePort）

- observe() 注册成功即派发当前快照一次；之后仅派发与上一快照不连续同值的事件（Kit 天然重复上报被 `SnapshotDeduper` 过滤）；
- 断网：`transport=null`、`metered=false`；`netLost`、注册异步失败、`getDefaultNetSync` 无默认网络（netId=0）或抛错均为断网语义；
- 注销幂等：重复 `unsubscribe()` 无副作用，迟到 Kit 事件不再派发；
- 错误模型：`current()` 无失败路径；`observe()` 在 Kit 注册抛错时返回 `err(AppError platform 2100002)`（如 `ohos.permission.GET_NETWORK_INFO` 未授予）。

## 使用

```ts
const network: NetworkStatePort = new ConnectivityAdapter(); // 生产
network.observe((s) => { /* 派发给 gateway */ });
```

依赖：`@tgx/core-common`、`@tgx/platform-ports`（均 file: 引用，oh_modules 符号链接方式同 platform/ports）。

权限：`ohos.permission.GET_NETWORK_INFO` 已在 `src/main/module.json5` 声明（随应用合并生效）。

## 验证矩阵

| 层 | 覆盖 | 命令 | 环境 |
|---|---|---|---|
| 纯逻辑单测 | 映射表（bearer/优先级/metered/断网形状）、`SnapshotDeduper` 状态机、契约 6 项镜像 + 注册失败透传 | `./hvigorw test --mode module -p module=platform_network@default -p product=default --no-daemon` | 本地（Kit 不可用也可跑，fake 事件源驱动） |
| 严格编译 | 全量 ArkTS 编译含 Kit 文件 | `./hvigorw assembleHar --mode module -p module=platform_network@default -p product=default --no-daemon` | 本地 |
| Kit 真连接 | `src/ohosTest` 骨架：`current()` 形状、observe 注册/注销 smoke | 需真机/模拟器（ohosTest harness）；开关 Wi-Fi/飞行模式人工观察 wifi/cellular/offline 切换事件 | 设备 |

本地单测不加载 `ConnectivityKitSource`（Kit 在单测环境不可用）；事件源注入面 = `ConnectivitySource` 接口。

## 已知限制 / 后续

1. **契约镜像**：`src/test/ConnectivityAdapterContract.test.ets` 镜像 platform/ports 的 `NetworkStatePortContract`（其在 ports 的 src/test，跨模块不可导入，且 hypium 依赖不宜进 har 主代码）。ports 契约变更时需手动同步；后续可把契约函数提升到公共测试包。
2. **ohosTest 骨架**：设备测试壳（TestAbility/TestRunner）已就位但尚未在真机跑过；真机事件流验证待执行后补证据。
3. **permission 级别**：`GET_NETWORK_INFO` 若目标设备为受限分发（未放开 normal 级），observe 会返回 err、current 恒为断网快照——语义安全降级，但需真机确认权限授予。
4. 枚举数值（bearer=0..4、NOT_METERED=11）以 SDK d.ts（API 24/26）为准核对过；Kit 演进时只需改 `ConnectivityMapping.ets` 常量。
5. **单订阅设计**：本 SDK 的 `connection.NetConnection` 无 `off()`，`unregister()` 会移除该连接上的全部监听，因此 `ConnectivityKitSource` 按「一个 source 实例一个 observe 订阅」设计（`ConnectivityAdapter` 默认构造即一一对应）。同一 adapter 上并发多个 observe 需每个订阅各建 adapter 实例。
