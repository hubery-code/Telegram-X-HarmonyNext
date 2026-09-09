# Telegram X → HarmonyOS NEXT 迁移 — 工作协调看板

> 本文件是多 AI 并行协作的**单一协调入口**。开始任何工作包前，必须先在「进行中」登记；完成后移到「已完成」并写明证据（构建命令、commit、测试结果）。
>
> 状态机：`Backlog → Contract Ready → Implementing → Verifying → Accepted`，或 `Blocked / Deferred`。
> 规则来源：`/Users/mbjpeng-yu01/Downloads/Telegram-X-HarmonyOS-NEXT-迁移实施计划.md`（下称「计划」）。
>
> ⚠️ 目录约定：计划中的 `harmony/` 前缀由用户指定取消——**本仓库根目录即 HarmonyOS 工程根**（对应计划的 `harmony/` 内容），Android 参考工程仍在 `/Users/mbjpeng-yu01/androidProjects/Telegram-X`。

## 环境基线（已锁定，GOV-002）

| 项目 | 版本 / 路径 |
|---|---|
| DevEco Studio | `/Applications/DevEco-Studio.app` |
| HarmonyOS SDK (OpenHarmony) | API 26 / platform 26.0.0.105，路径 `…/sdk/default/openharmony` |
| Native (NDK/clang) | 同上 `native/` 子目录，API 26 |
| Hvigor | DevEco 内置 `…/tools/hvigor/hvigor`（wrapper 已拷入仓库 `hvigorw`） |
| Node（构建用） | DevEco 内置 `…/tools/node/bin/node`（勿用系统 node 23 跑 hvigor） |
| 设备 | Phone / arm64 优先（D-009）；x86_64 仅模拟器/CI |

## 进行中（Implementing）

| 工作包 | 负责人(AI) | 开始时间 | 说明 |
|---|---|---|---|
| CORE-003 AccountScope/Registry | 主会话 | 2026-09-09 | ✅ 已完成 |
| CORE-005 授权状态机 reducer | 主会话 | 2026-09-09 | ✅ 已完成 |
| BRG-006 生产桥 adapter | 主会话 | 2026-09-09 | 待启动（429 中断）；区域：`platform/tdcore-bridge/` |

> ⚠️ 并行约定：**不要执行 git commit**，完成后报告文件清单由主会话统一提交。core/account 禁止 import ArkUI/Kit。项目内有 `.agents/skills/harmony-next/` 离线参考（API 12-23 快照），编码遇 API 问题可查。

## 待认领（Backlog，按计划的 Phase 0 顺序）

| 工作包 | 依赖 | 一句话 |
|---|---|---|
| GOV-004 | 无 | 建立 Feature/Parity Matrix（P0/P1/P2/P3 功能表，含 Android 参考） |
| GOV-005 | GOV-004 | ✅ 已完成（事件说明版；真机录屏待设备） |
| GOV-006 | GOV-001/002 | ✅ 已完成 |
| QA-001 | GOV-001 | ✅ 已完成 |
| SEC-001 | GOV-004 | ✅ 已完成 |

### 下一批（Phase 1，按依赖顺序；G0 已实质达成）

| 工作包 | 依赖 | 一句话 |
|---|---|---|
| TDN-001 | GOV-002 | TDLib 依赖构建矩阵（依赖列表、来源、hash、ABI、许可证） |
| TDN-002 | TDN-001 | 用 HarmonyOS NDK 构建 zlib/SQLite/crypto 最小依赖（arm64） |
| TDN-003 | TDN-002 | TDLib arm64 Debug 构建（libtdjson），真机 getOption(version) |
| BRG-001~005 | TDN-003 | Node-API module → create/send/execute → TSFN 接收线程 → 有界队列 → close 生命周期 |
| GEN-001~004 | TDN-003 | 解析 td_api.tl 生成 ArkTS DTO/codec/validator/脱敏元数据 |

> 认领规则：一次只认领一个工作包；认领时把行移到「进行中」并注明你的身份和计划开始的内容。禁止修改未授权目录。

> 认领规则：一次只认领一个工作包；认领时把行移到「进行中」并注明你的身份和计划开始的内容。禁止修改未授权目录。

## 已完成（Accepted 或有保留）

| 工作包 | 完成日期 | 证据 |
|---|---|---|
| GEN-003 codec fixture round-trip | 2026-09-09 ✅ | AI-Agent-J：22 个全合成脱敏 fixture（TDLib 官方仓库无静态 JSON 样本，字段结构派生自 td_api.tl；13 个授权状态机 + 4 个 updateNewMessage 内容类型 + error/ok `@extra` 关联 + vector&lt;int64&gt; 大数 + 2 个未知类型 raw 回传；来源/脱敏规则/加 fixture 流程见 `core/td_api_generated/fixtures/README.md`）；每 fixture 独立用例 `decodeTdObject→encodeTdObject→canonicalJson 语义等价→二次 decode 稳定`，未知类型断言 `TdUnknownObject` 无损；`FixtureData.ets` 由 `fixtures/sync_fixtures.py` 从 json 确定性生成；`./hvigorw test --mode module -p module=core_td_api_generated@default -p product=default --no-daemon` `Tests run: 48, Failure: 0, Error: 0, Pass: 48`（既有 20 例不回归）；期间定位并清除损坏的 533MB `init_coverage.json` 构建缓存（00308018 假错误，`.test/` 产物非源码） |
| GOV-001 空工程 | 2026-09-08 | Debug/Release 构建均 BUILD SUCCESSFUL，产出 `entry/build/default/outputs/default/entry-default-unsigned.hap`（212 KB）；commit `7fe266b` |
| GOV-002 工具链锁定 | 2026-09-08 | `tools/toolchain-versions.json` + `tools/ci/setup-check.sh` 退出码 0（SDK 26.0.0.105 / hvigor 6.26.4）；版本不匹配会明确失败 |
| GOV-003 文档控制面 | 2026-09-08 | `docs/`（ARCHITECTURE、ADR-001/002、Feature/Parity、quality 五件、runbooks 三件）+ `work-items/templates/`（§17.1/17.2 原文模板） |
| GOV-007 秘密管理 | 2026-09-08 | `.gitignore` 覆盖签名/p12/cer/local_properties/api_hash；`tools/ci/secret-scan.sh` 已接入 ci.sh（PEM 私钥、api_hash 模式阳性 fixture 验证通过）；commit `7fe266b`+`b94e5a6` |
| GOV-004 Feature/Parity Matrix | 2026-09-08 | FEATURE_MATRIX：7 项 P0 + 38 项 P1（含真实 Android 类级路径+行号、TDLib 方法）、P2/P3 一行表；PARITY_MATRIX 45 行对齐骨架；commit `b94e5a6` |
| GOV-005 Android 行为样本 | 2026-09-08 | `docs/product/behavior-samples/` 5 份（登录/会话列表/发文本/通知/媒体）+ README，全部脱敏、含 TDLib 事件与 Harmony 验收观察点；截图/录屏待真机；commit `b94e5a6` |
| GOV-006 CI 最小流水线 | 2026-09-08 | `tools/ci/ci.sh` 6 步全链路实测通过（工具链闸→secret scan→lint/typecheck→单测→debug→release 构建）；`.github/workflows/ci.yml` self-hosted 模板；commit `b94e5a6` |
| QA-001 测试骨架 | 2026-09-08 | `hvigorw test` 真实执行通过：1 用例 Success（注意：本 hvigor 6.26.4 单测须放 `entry/src/test/*.test.ets`，ohosTest 壳留作设备测试）；commit `b94e5a6` |
| SEC-001 威胁模型 v0 | 2026-09-08 | `docs/architecture/threat-model-v0.md`：数据流图+6 信任边界、9 资产、16 威胁（账号/消息/文件/Push/bridge/存储全覆盖）、7 秘密管理规则、§18 风险映射；commit `b94e5a6` |
| TDN-001 依赖构建矩阵 | 2026-09-08 | `native/tdcore/README.md`：OpenSSL 3.5.8（必须，TD CMake 硬依赖）/ zlib 1.3.1（NDK sysroot）/ SQLite 3.31.0（TD 自带 amalgamation）/ TDLib d1085f9ce，各带版本、来源、hash、许可证；commit `0dd04ef` |
| TDN-002 最小依赖构建 | 2026-09-08 ✅ | OHOS NDK 交叉编译产出 `libtdjson.so`（arm64，strip 后 45.9MB，build-id 7b9c054b）+ `libcrypto.so.3`；musl 补丁 0001；**真机应用内 smoke PASS**：TDLib 1.8.67，execute(getTextEntities) 正常返回（hdc shell 域禁 exec ELF 的绕过方案见 runbook） |
| BRG-001/002 Node-API 桥 | 2026-09-08 ✅ | `libtdcore_napi.so` 导出 getVersion/execute/createClient/send（契约对照 §5.2，错误安全）；真机验证：页面显示 `TDLib 版本: 1.8.67` + textEntities JSON；证据 `native/tdcore/napibridge/EVIDENCE.md` + 设备截图；commit `c93ebd5` |
| BRG-003/004 receive+队列 | 2026-09-09 ✅ | receive 线程 → 有界队列 → TSFN → ArkTS 全管线；真机端到端 PASS：getOption 异步响应按序到达（seq #1-#4 单调），dropped=0，force-stop 重启无崩溃；证据 `napibridge/EVIDENCE.md` + 两张设备截图；commit `62b71a2` |
| 结构骨架 | 2026-09-08 | core×9 / platform×14 / feature×12 / native×3 / tools×4 / test×4 目录已建（仅 .gitkeep，未注册构建，符合 ADR-002） |
| GEN-001 schema IR | 2026-09-08 ✅ | AI-Agent-C：`tools/td_api_codegen/td_api_ir.py`（纯 python3 无依赖）解析 td_api.tl（16313 行）→ `core/td_api_generated/schema.ir.json` + golden 快照 `tools/td_api_codegen/snapshot/td_api.ir.json`；schemaHash `7fbae70a…c5929`（SHA-256，仅随 schema 内容变）；stats types=743 / constructors=3214（objects=2192+functions=1022）/ fields=6997；入口 `python3 tools/td_api_codegen/td_api_ir.py verify`（CI 用，不写文件）——重复运行字节级一致，故意改输入（加字段）verify/generate 均退出码 1、恢复后通过；README 含 GEN-002 交接说明 |
| GEN-002 ArkTS DTO/union 全量生成 | 2026-09-09 ✅ | AI-Agent-F：`tools/td_api_codegen/td_api_arkts.py` 从 schema.ir.json 生成全量 ArkTS（classes=3205、unions=743、49 个 .ets）：每构造器一个类（判别属性 `type`、`@extra` 载体、int64→string）+ 每抽象类型判别联合（恒含 `TdUnknownObject`）+ decode/encode + `TdResponseMap` 请求返回映射 + `decodeTdObject`/`encodeTdObject`；decode 永不抛错（未知 `@type`→`TdUnknownObject` 保 raw 可回传、未知字段忽略、缺字段取默认）；命名规则/避让（`type_`/`extra_`、`DateValue`/`ErrorValue`/`ProxyValue`、`TdJsonRaw`）与 panda index 上限分块约束（`TdUnions_<A-Z>` + `TdEntries`）见 README；`generate`/`verify` 双入口、重复生成字节级一致（shasum 两次相同）；har 模块 `core_td_api_generated`（`@tgx/td-api-generated`）`assembleHar` BUILD SUCCESSFUL；单测 20 用例全 Success（codec round-trip/未知 `@type` 与未知字段 fallback/int64 精度/`@extra`/响应映射）`./hvigorw test --mode module -p module=core_td_api_generated@default -p product=default --no-daemon`；首版生成物曾被 BRG-003/004 的 commit `032cdfa` 顺带提交（CI 需要），本轮为重构后最终版 |
| CORE-001 Result/AppError/Clock/Id | 2026-09-08 ✅ | AI-Agent-E：`core/common` 注册为 har 模块（build-profile.json5 modules 追加 `core_common`，未动 entry/signing）；Result 判别联合（map/flatMap/mapError/getOrElse/getOrNull/fold）+ AppError 七类稳定错误（含 fromTdlibError 稳定映射、toLogString 脱敏）+ Clock（System/Manual）+ IdGenerator（Random 可注入/Sequential fake）；纯单测 27 用例全 Success：`./hvigorw test --mode module -p module=core_common@default -p product=default --no-daemon`（全工程 `hvigorw test --no-daemon` 亦 BUILD SUCCESSFUL，entry 1 用例回归通过）；`assembleHar` BUILD SUCCESSFUL；交接说明见 `core/common/README.md`（单调时钟需 platform 注入） |
| UI-001 Design token/theme | 2026-09-08 ✅ | AI-Agent-G：`core/design_system` 注册为 har 模块（build-profile.json5 modules **仅追加** `core_design_system`）；19 个语义色 token 深浅两套（LightColors/DarkColors）+ 9 档字阶排版 + 间距/圆角/动画 token（曲线存贝塞尔控制点保持 Kit-free）；`Theme`/`createTheme(mode, fontScale)` + `resolveToken(theme, dottedName)` 五命名空间解析入口（未知名返回 undefined）；fontScale 适配 clamp [0.85,2.0] + 最小可读字号 11vp 下限；纯单测 25 用例全 Success（深浅色映射完整且互异、WCAG 对比度断言、fontScale 五边界、token 存在性/有序性）；`assembleHar` BUILD SUCCESSFUL；命名规范/加 token 流程/ArkUI 接入说明见 `core/design_system/README.md` |
| PLAT-001 Platform Port 契约 | 2026-09-08 ✅ | AI-Agent-H：`platform/ports` 注册为 har 模块（modules **仅追加** `platform_ports`，包名 `@tgx/platform-ports`，依赖 `@tgx/core-common` file: 引用）；5 个端口契约（PreferencesPort flush 派发/同 key 合并/通配事件、SecureKeyStorePort 锁屏/不可用语义 + 稳定平台错误码、NetworkStatePort 快照去重/初始值语义、AppFilesPort 路径越界拒绝/配额、MonotonicClockPort 单调不减）+ 5 个 Fake + `src/test/contract/` 同套参数化契约测试（生产 adapter 复用同一函数）；同套契约 36 用例全 Success（`Tests run: 36, Failure: 0, Error: 0, Pass: 36`），`assembleHar` BUILD SUCCESSFUL；语义约定/交接见 `platform/ports/README.md`；本地 har 依赖用 `oh_modules/@tgx/core-common → ../../../../core/common` 符号链接（gitignored） |
| UI-002 Typed navigation | 2026-09-08 ✅ | AI-Agent-I：`core/navigation` 注册为 har 模块（modules **仅追加** `core_navigation`，包名 `@tgx/core-navigation`，依赖 `@tgx/core-common`）；`AppRoute` discriminated union（8 路由）+ `ParamSpec` 参数 schema（int 限 safe-integer 范围/string maxLength+pattern/boolean）+ RouteRegistry（name↔path 模板互转、重复注册与非法模板拒绝）+ RouteCodec（parse/encode round-trip、缺失必填/类型错误/越界/未知路由/未知与重复参数/非法百分号编码全部 Err 不抛异常；parseDeepLink 白名单规则 scheme/host/query 映射，未知 URI 安全拒绝，junk query 忽略）+ NavigationStack（push/replace/pop/popToRoot、serialize/restore round-trip、连续重复去重、任一非法项整体拒绝）；纯单测 37 用例全 Success（`Tests run: 37, Failure: 0, Error: 0, Pass: 37`）：`./hvigorw test --mode module -p module=core_navigation@default -p product=default --no-daemon`；命名规范/加路由四步骤/ArkUI Navigation 接入预留见 `core/navigation/README.md`；**新工程要点**：跨 har 模块判 Result 分支禁用 `instanceof Ok/Err`（类身份跨模块可能不一致，实测误判），用 `result.ok === false` 收窄或 `fold` |
| UI-003 UiState/Intent/Effect 基类约定 | 2026-09-09 ✅ | AI-Agent-M：`feature/_template` 注册为 har 模块（modules **仅追加** `feature_template`，包名 `@tgx/feature-template`，依赖 `@tgx/core-common`）；UiState/Intent/Effect 空接口标记 + `Reducer<S,I,E>` 契约（`(state, intent, env) -> {state, effects}`，env 注入 Clock/IdGenerator，reducer 纯函数可测）+ 计数器示例 feature（`copyWith` 不可变更新——ArkTS 不支持对象 spread、`kind` 字面量判别、幂等防重返回原引用、参数校验走 Effect）；纯单测 15 用例全 Success（每 intent 分支、effect 数量/类型/参数精确断言、输入不可变、chained runs 独立）：`./hvigorw test --mode module -p module=feature_template@default -p product=default --no-daemon`；`assembleHar` BUILD SUCCESSFUL；四步创建法/reducer 五条禁忌见 `feature/_template/README.md`；commit `a892ce2` |
| PLAT-004 网络状态生产 adapter | 2026-09-09 ✅ | AI-Agent-L：`platform/network` 注册为 har 模块（modules **仅追加** `platform_network`，包名 `@tgx/platform-network`，依赖 `@tgx/core-common` + `@tgx/platform-ports` file: 引用，oh_modules 符号链接同 ports）；ConnectivityAdapter = Kit-free 引擎（`ConnectivitySource` 注入面）+ ConnectivityKitSource（唯一 import `@ohos.net.connection`：`createNetConnection` 监听 netAvailable/netLost/netCapabilitiesChange，current 用 getDefaultNetSync+getNetCapabilitiesSync）；映射表 bearer→wifi/cellular/ethernet/other（多 bearer 优先级 ethernet>wifi>cellular>other）+ metered（networkCap 无 NET_CAPABILITY_NOT_METERED=11）+ SnapshotDeduper 连续同值去重；注册即派初始快照（经去重器防 flicker）、注销幂等（本 SDK NetConnection 无 off，unregister 移除全部监听→单订阅设计，active 闭包丢迟到事件）、注册失败 err(platform 2100002)；纯单测 18 用例全 Success（映射 7 + 去重 4 + 契约镜像 7，含注册失败透传）：`./hvigorw test --mode module -p module=platform_network@default -p product=default --no-daemon`；`assembleHar` BUILD SUCCESSFUL；ohosTest 设备骨架就位未上真机；权限 GET_NETWORK_INFO 已声明；验证矩阵/已知限制见 `platform/network/README.md` |
| CORE-002 TdGateway+RequestRegistry | 2026-09-09 ✅ | `core/td_gateway`（`@tgx/td-gateway`）：RequestRegistry（@extra.requestId 注入、Promise 恒回 Result 不 reject、超时 10s 可配、取消、迟到丢弃计数、7 项指标）+ OrderedEventRouter（clientId+sequence 单调校验、乱序上报不静默、重复幂等）；FakeBridge 单测 53/53；CI 全绿；commit `4f1194e` |
| CORE-005 授权状态机 reducer | 2026-09-09 ✅ | authReducer（event-driven，10 状态/12 事件/effect union）+ AuthorizationStateMachine 不可变包装 + failed/closed 终态守卫；98 用例全 Success（60 原有 + 38 新增）；CI 全绿；commit `9d5e7a1` |
| CORE-003 AccountScope/Registry | 2026-09-09 ✅ | `core/account`（`@tgx/core-account`）：生命周期纯 reducer（active/hibernating/closed 终态幂等）、每账号独占 TdGateway + ScopeIsolatingBridge 事件边界隔离、restoreAll 逐账号失败隔离、迟到事件守卫丢弃；AuthorizationState 占位待 CORE-005；60/60 用例；CI 全绿；commit `832f11f` |
| GEN-004 敏感字段元数据+脱敏 | 2026-09-09 ✅ | 生成器 `td_api_sensitive.py`（generate/verify 双模式，字节级可复现）：124 构造器/154 字段/44 类型级清单（redact 75/mask 79，三层首匹配规则表带决策注释）；产物 `td_api_generated/.../redaction/`（TdSensitiveFields 3861 行 + TdRedact）；`core/observability`（`@tgx/observability`）白名单 Logger + 双防线脱敏，43/43 用例（secret fixture 100% 拦截）；commit `4f1194e` |
| PLAT-002 Preferences/RDB adapter | 2026-09-09 ✅（设备项待验） | AI-Agent-K：`platform/storage` 注册为 har 模块（modules **仅追加** `platform_storage`，包名 `@tgx/platform-storage`，依赖 `@tgx/core-common` + `@tgx/platform-ports` file: 引用，oh_modules 符号链接同 ports）；**两个 PreferencesPort 生产 adapter**：`HarmonyPreferencesAdapter`（@ohos.data.preferences，open/openSync）+ `RdbPreferencesAdapter`（@ohos.data.relationalStore，open/幂等 close），共享纯 ArkTS `PreferenceStoreCore`（内存视图/同 key 合并/flush 后派发/clear 通配/失败挂起重试，语义对齐 PLAT-001 契约）；**schema+migration**：`tgx_meta(user_version)` + `tgx_kv(key,type_tag,value_text,value_real,value_integer)` 类型分列，线性版本链 `planMigrations`（up/down 双路径、缺 down 步骤拒绝回滚、版本跳跃遍历）+ `runMigrations`（每步完成先推版本标记→中断可断点续跑，Kit 层 beginTransaction/commit/rollBack 整体回滚）；fake 注入中断/升级/回滚单测 **47 用例全 Success**（`Tests run: 47, Failure: 0, Error: 0, Pass: 47`）：`./hvigorw test --mode module -p module=platform_storage@default -p product=default --no-daemon`；`assembleHar` BUILD SUCCESSFUL（Kit adapter 严格编译通过）；`src/ohosTest` 设备测试（真实落盘+重开读回/事件派发）就位**待真机**；**新工程要点**：ArkTS 收窄仅块内 `if (r.ok/r.err)` 有效（取反/early-return/else 分支均不收窄，用 getOrNull/getOrElse 或 fold 规避）；内联对象字面量类型被禁（用 interface union）；PLAT-001 contract 函数在 ports 的 src/test、跨模块相对 import 被编译器拒绝→全量 contract 复用待 test_support 包；验证矩阵/交接见 `platform/storage/README.md` |

已知工程要点（runbook 已记录）：hvigorw 为 shell/JS polyglot；离线构建依赖 `~/.hvigor/project_caches`；`DEVECO_SDK_HOME` 必须指向 `…/Contents/sdk`（wrapper 已内置）；签名/真机待用户提供。

已知工程要点（CORE-001 实测）：① 后续 har 模块照 `core/common/` 模板注册：`hvigorfile.ts` 用 `harTasks`；模块自己的 `build-profile.json5`（`{"apiType":"stageMode","buildOption":{}}`）；`src/main/module.json5` 的 `type` 必须是 `"har"`（写 `"shared"` 会被当 HSP 导致 `PackageSignHar` 缺失）；oh-package.json5 的 `main` 指向 `./src/main/ets/Index.ets`。② har 模块单测入口固定为 `src/test/List.test.ets`（hvigor 生成 harness 硬编码 import 它，由它汇总其他 `*.test.ets`）。③ 模块本地单测需在 `<module>/oh_modules/@ohos/hypium` 建符号链接到根 `oh_modules/.ohpm/@ohos+hypium@1.0.21/...`（gitignored；照抄 entry 的做法）。

## 阻塞 / 风险记录

| 日期 | 事项 | 状态 |
|---|---|---|
| 2026-09-08 | 用户输入项（api_id/api_hash、真机、AGC/Push 配置）未提供 —— 阻塞 Phase 1 真机项，不阻塞 Phase 0 工程脚手架 | ✅ 已解决：api_id/api_hash 已放入 gitignored `local.properties`（取自 Android 工程）；VYG-AL00 真机已连（API 24 / 6.1.0.135），DevEco 自动签名已接入 |
| 2026-09-08 | compatibleSdkVersion 26 与设备 API 24 不匹配 | ✅ 已修复为 `6.1.1(24)`（hvigor 映射表 6.1.1→24）；signed hap 已真机安装成功（bundle 校验通过），启动待解锁屏幕 |
