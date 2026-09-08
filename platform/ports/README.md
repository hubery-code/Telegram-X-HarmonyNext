# platform/ports（PLAT-001）

平台端口契约层：纯 ArkTS `interface` + 稳定数据类型，**不 import 任何 HarmonyOS Kit**（D-008：系统能力一律经 Port/Adapter 暴露）。Kit 实现分别由后续工作包提供：PLAT-002（Preferences Kit adapter）、PLAT-003（Asset Store/HUKS adapter）、PLAT-004（Network Kit adapter）、platform/files（文件 Kit adapter）、platform 单调时钟 adapter。

依赖 `@tgx/core-common`（`file:../../core/common`）：错误统一用 `Result<T, AppError>` 表达，不做异常控制流；`AppError.toLogString()` 的脱敏约定对所有实现生效（敏感值不进 message/cause，见计划 §5.6/§7）。

## 端口清单与语义约定

### 1. PreferencesPort — 键值偏好存储（键值偏好存储 port）

对应计划 §5.6：只保存小型、非敏感开关（主题、字号、UI 偏好）。

| 约定 | 内容 |
|---|---|
| 线程 | 读写同步、立即作用于内存视图；`flush()` 异步，是持久化点与变更事件派发点 |
| 类型安全 | `getString/getNumber/getBoolean`：key 不存在 → `ok(null)`；类型不匹配 → `err(parameter/invalid)` |
| 变更监听 | `put/remove/clear` 后**不立即**回调；`flush()` 成功后按批次派发；同一 key 多次变更合并为最后一次；`clear()` 派发 `key='*'`（`PREFERENCES_CLEAR_ALL_KEY`）、`value=null` 通配事件；flush 失败不产生事件且变更保持挂起 |
| 幂等 | `remove` 不存在 key → `ok`；`Subscription.unsubscribe()` 幂等，注销后零事件 |
| 错误 | `Result<_, AppError>`：参数问题 → `parameter`，持久化失败 → `storage/io`（retryable 由实现声明） |

### 2. SecureKeyStorePort — 安全密钥存储

承载 TDLib 数据库加密 key、账号令牌、代理凭据（计划 §5.6）。

| 约定 | 内容 |
|---|---|
| 线程 | 全部异步（`Promise`）；硬件-backed 运算可能在实现内部发生 |
| 锁屏语义 | 锁屏时 `getStatus()` 报 `{kind:'locked'}`；读写返回 `err(platform/SECURE_KEY_STORE_LOCKED_PLATFORM_CODE, retryable=true)`；解锁后同一调用预期成功 |
| 可用性 | `getStatus()` 如实报告 `available/locked/unavailable(reason)`；不可用时读写返回 `err(platform, retryable=false)`，不抛异常 |
| 值语义 | `Uint8Array` 二进制；存取均按字节拷贝；key 不存在 → `ok(null)`；`remove` 幂等 |
| 安全 | 密钥值绝不进入 `AppError.message/cause`（契约测试断言）；日志只可用 `AppErrors.toLogString` |

### 3. NetworkStatePort — 网络状态

对应计划 §5.7：网络可用性与 Wi‑Fi/蜂窝切换信号发给 gateway。

| 约定 | 内容 |
|---|---|
| 模型 | 快照式：`NetworkSnapshot{connected, transport: wifi/cellular/ethernet/other/null, metered}` |
| 去重 | 实现必须过滤值相同的连续快照（Fake 全字段相等去重；生产 adapter 底层重复上报也必须过滤） |
| 监听 | `observe()` 注册后立即派发当前快照（初始值语义），之后仅派发散逸；派发串行、不并发重入同一 listener |
| 断网 | `connected=false, transport=null, metered=false` |
| 错误 | `current()` 无失败路径；`observe()` 注册失败（权限等）返回 `err(platform)` |

### 4. AppFilesPort — 文件/应用目录

对应计划 §5.6 目录模型：`files/accounts/<key>/…`、`cache/thumbnails` 等。

| 约定 | 内容 |
|---|---|
| 路径安全 | 只接受相对路径；拒绝空、绝对路径、`..` 越界（`err(parameter/invalid)`）；分隔统一 `/`；`resolve` 返回规范化沙盒内路径 |
| 目录 | `AppDirectory`（`root: files|cache` + `sub: string|null`），构造用 `AppDirs.files()/cache()/filesSub(sub)/cacheSub(sub)`；`resolve` 不访问文件系统 |
| 读写 | `writeBytes/writeText` 覆盖写；读不存在 → `err(storage/io)`；`delete` 返回是否实际删除（不存在 → `ok(false)`） |
| 空间 | `freeSpaceBytes/totalSpaceBytes` 为文件系统语义；写超配额 → `err(storage/quota_exceeded, retryable=true)` |
| 原子性 | 生产实现应「临时文件 + rename」，adapter 文档须声明；Fake 为内存语义，对外契约一致 |

### 5. MonotonicClockPort — 单调时钟

背景：纯 ArkTS 无可移植单调时钟 API（`core/common` 的 `SystemClock.monotonicMillis` 以 `Date.now()` 近似，其 README 已登记此交接事项）。需要严格单调语义的路径（超时、事件排序、序列号）必须经本端口注入。

| 约定 | 内容 |
|---|---|
| 单调性 | `nowMillis()` 任意两次调用后者 ≥ 前者，与系统时间回拨无关；契约测试以 100 次采样验证 |
| 原点 | 未定义（不要求从 0 开始），调用方只做差值比较 |
| 失败 | 纯查询无失败路径，不包 `Result` |

## Fakes（内存实现）

| Fake | 行为要点 |
|---|---|
| `FakePreferencesStore` | 对齐 HarmonyOS Preferences 语义（flush 派发/同 key 合并/通配事件）；`failNextFlush()` 注入失败 |
| `FakeSecureKeyStore` | 字节拷贝存取；`setLocked()`/`setAvailable()` 模拟锁屏与能力缺失 |
| `FakeNetworkState` | 初始断网；`push()` 模拟底层切换，全字段相等去重；`setObserveEnabled(false)` 模拟注册失败 |
| `FakeAppFiles` | 内存文件表 + 路径规范化/越界拒绝；可注入 totalSpace 的配额模型；UTF-8 编解码内置 |
| `FakeMonotonicClock` | `advanceBy()` 推进；`setMillis()` 仅供构造初始状态 |

## 同套 contract 测试（验收「生产/fake 同套 contract」）

`src/test/contract/*.ets` 导出参数化测试函数：

```ts
preferencesPortContract('XxxPreferences', () => new XxxPreferences());
secureKeyStorePortContract('XxxKeyStore', factory, driverFor?);
networkStatePortContract('XxxNetwork', factory, driver);
appFilesPortContract('XxxFiles', factory); appFilesQuotaContract('XxxFiles', quotaFactory);
monotonicClockPortContract('XxxClock', factory, driver);
```

未来生产 adapter 的测试文件只需以 adapter 工厂调用同一函数（driver 用真实系统事件源适配），即复用全部断言。当前由 `src/test/Fake*.test.ets` 以 Fake 工厂套用；`List.test.ets` 为 hvigor 单测入口。

## 构建与测试

```bash
./hvigorw test --mode module -p module=platform_ports@default -p product=default --no-daemon
```

## 已知限制 / 交接

1. `SecureKeyStorePort` 锁屏语义依赖 fake driver 钩子；生产 adapter（PLAT-003）需把 HUKS/Asset Store 的锁屏错误映射到 `SECURE_KEY_STORE_LOCKED_PLATFORM_CODE` 并复用同一 contract。
2. `AppFilesPort` 暂无目录列举能力；如后续需要，走契约变更（契约 PR → 提供方 PR → 消费方 PR）。
3. `PreferencesPort` 的通配 change 语义对齐 HarmonyOS Preferences 的 flush 后回调；若 PLAT-002 发现 Kit 行为有出入，先更新本 README 契约，再改实现。
4. 本地单测依赖 `oh_modules/@ohos/hypium` 符号链接（gitignored，照 `core/common` 做法）。
