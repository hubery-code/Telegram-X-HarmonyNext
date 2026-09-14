# Telegram X HarmonyOS NEXT 代码审计与计划偏差报告

> 审计日期：2026-09-14  
> 报告版本：v1.0  
> 实现仓库：`/Users/mbjpeng-yu01/androidProjects/Telegram-X-HarmonyNext`  
> 审计基线：`master@7e75c89`，与 `origin/master` 一致，工作区审计开始时干净  
> 对照计划：[迁移实施与架构计划](HARMONY_NEXT_MIGRATION_PLAN.md)  
> 审计角色：架构、质量门禁与后续 AI 调度检查  
> 注意：本文不记录任何凭据、签名口令或密钥原文。

---

## 1. 审计结论

项目的技术路线没有跑偏：ArkTS/ArkUI 重写客户端、TDLib C++ 复用、Node-API 窄桥接、HAR 模块化，这些核心方向都成立。实现速度也很快，登录、会话列表、文本聊天、部分消息操作、搜索、设置以及媒体接收链路已经形成可运行的真机纵向切片。

但当前状态不能认定为“Phase 3/G3 已通过”，更不能据此继续无约束扩展功能。准确判断是：

> **已有 G3 功能证据的工程原型，但安全、数据保护、Native 稳定性、CI、架构边界和项目治理仍未满足 G0/G1/G2 的退出条件。**

当前必须暂停非关键新功能，先执行 1～2 周的 Quality Recovery Sprint。否则继续开发会放大返工面，并让“功能可演示”与“工程可交付”的差距继续扩大。

### 1.1 总体评级

| 维度 | 当前判断 | 说明 |
|---|---|---|
| 技术路线 | 符合 | TDLib + Node-API + ArkTS 的主路线正确 |
| 功能纵向切片 | 良好 | 登录、会话、文本聊天、部分媒体已在真机形成证据 |
| 安全与秘密管理 | **阻断** | 源码中存在真实 API 凭据；签名配置也含明文敏感信息 |
| 数据保护 | **阻断** | HUKS adapter 存在，但 TDLib 数据库仍使用空加密密钥 |
| Native 稳定性 | 高风险 | 回调期间取消订阅可能导致容器迭代器失效；缺原生压力测试与 24h soak |
| 架构一致性 | 需整改 | Feature 直接依赖多个系统 Kit；typed navigation 与统一 Logger 未真正接入 |
| 自动化质量 | 不达标 | 主 CI 只跑 entry 测试；缺全模块、覆盖率、代码生成和架构规则门禁 |
| 文档与状态治理 | 失真 | 多个“单一事实源”仍停留在项目初始化状态 |
| 可复现构建 | 不达标 | 工具链和签名路径绑定当前 Mac，无法证明干净环境可构建 |

---

## 2. 已实现能力与合理进展

本次审计确认以下能力并非空壳：

- 已建立 `core`、`feature`、`platform`、`entry` 与 `native` 的模块骨架。
- TDLib arm64 原生库、Node-API bridge 和 ArkTS gateway 已进入实际应用链路。
- 手机号/验证码/2FA/二维码等授权流程已有实现，支持重启恢复会话。
- 会话列表、头像、基础聊天消息、文本发送、回复、编辑、删除、转发、置顶/未读等已有不同程度实现。
- 全局搜索、基础设置与存储管理已有实现。
- 图片/视频/贴纸的接收、渲染与部分查看体验已有近期真机证据。
- Design Token 检查通过，Debug assemble 通过。
- 实现仓库在审计基线时与远端一致且无未提交改动。

这些结果可以保留，不需要推倒重来。整改重点是把已经能跑的功能放回可验证、可维护、可扩展的工程轨道。

---

## 3. Gate 偏差

| Gate | 计划要求 | 当前证据 | 审计状态 |
|---|---|---|---|
| G0 范围与基线 | 安全基线、可复现工具链、契约和控制文件 | 有模块与模板；秘密管理、可移植构建、控制文件维护不成立 | **未通过** |
| G1 原生可行性 | TDLib/Node-API、数据库加密、Push 或明确 Blocked、RTC PoC 或明确 Deferred、24h soak、原生测试 | TDLib 和真机链路成立；其余关键证据缺失 | **未通过** |
| G2 架构骨架 | 依赖边界、typed navigation、日志脱敏、全模块 CI | 组件已创建，但多处没有接入生产路径 | **未通过** |
| G3 最小纵向切片 | 登录→会话→聊天→收发→重启恢复 | 已有较强功能证据 | **证据已收集，不能越级判定通过** |
| G4 核心聊天 MVP | 完整 P1、Push、媒体收发、搜索、多语言/主题/设备矩阵 | P1 部分完成，关键缺口较多 | **未通过** |

### 3.1 Gate 语义修正

后续不允许把“后续阶段的一条路径跑通”解释为前置 Gate 自动通过。可以提前收集 G3 功能证据，但 G3 的正式状态必须保持 `Pending upstream gates`，直到 G0～G2 全部满足退出条件。

---

## 4. 阻断问题

### P0-SEC-001：公开代码中存在真实 Telegram API 凭据

**证据**

- `entry/src/main/ets/entryability/EntryAbility.ets:19` 含真实 `api_hash` 字面量。
- `./tools/ci/ci.sh` 当前在 secrets scan 阶段失败，因此完整 CI 不是绿色。
- 该值已经进入远端历史，单纯删除当前行不能消除泄露。
- README 描述为由本地配置注入，但生产代码和构建脚本并未实现该描述。

**影响**

- 视同凭据已经泄露；可能被第三方从当前版本或历史提交中取得。
- 阻断所有正式构建、外部测试包和后续发布活动。

**必须处理**

1. 立即轮换对应 Telegram 凭据；旧值按已泄露处理。
2. 使用 build-time generated config 或本地不入库配置注入，源码只保留空模板。
3. 清理 Git 全历史并强制更新远端；提前通知所有协作者重新同步。
4. 扩展 secrets scan，并在提交前和 CI 同时阻断。
5. 检查已生成 HAP、日志、制品和协作记录中是否存在相同秘密。

### P0-SEC-002：签名配置含本机路径和明文口令

**证据**

- 受版本控制的 `build-profile.json5` 包含用户绝对路径和签名相关明文敏感字段。
- 当前秘密扫描规则没有发现这类字段。

**必须处理**

- 轮换涉事调试签名材料和口令。
- 仓库只保留无秘密模板；真实配置由本地/CI secret store 注入。
- 增加签名口令、keystore 路径与常见配置字段的扫描规则。

### P0-DATA-001：TDLib 数据库加密未接入 HUKS

**证据**

- `platform/keystore/HarmonySecureKeyStore.ets` 已实现，但生产 Bootstrap 没有实例化或注入它。
- `feature/auth/src/main/ets/coordinator/AuthCoordinator.ets:280` 对 `checkDatabaseEncryptionKey` 发送空 `encryption_key`。

**影响**

- “密钥由 HUKS 保存”和“数据库加密完成”的验收结论不成立。
- 当前重启恢复只证明未加密数据库能够恢复。

**必须处理**

- 为每个 AccountScope 生成/获取 HUKS 保护的高熵数据库密钥。
- 明确首次创建、已有空密钥数据库迁移、登出销毁、备份恢复和失败回滚语义。
- 增加 kill/restart、升级迁移、错误密钥、密钥丢失和多账号隔离测试。

---

## 5. 高优先级工程偏差

### P1-BRG-001：Native 回调重入存在未定义行为风险

`native/tdcore/napibridge/src/tdcore_napi.cpp:175-197` 直接遍历 `g_state.sinks` 并同步调用 ArkTS；`Unsubscribe` 在 `:471-475` 删除同一容器元素。若回调内取消订阅，可能使当前迭代器失效并导致崩溃或内存错误。

整改方式：回调前创建稳定快照或采用 generation/token 机制；回调期间不得直接破坏正在遍历的容器。必须增加原生级重入取消订阅、close、重复订阅和并发压力测试。

### P1-BRG-002：Bridge 生命周期与陈旧事件未定义

进程级队列没有在最后一个订阅取消、client close 或重新初始化时建立明确的 generation 边界。旧会话排队事件可能在重新订阅后送到新消费者。

整改方式：为 client/session 增加 generation；close 后丢弃旧 generation 的事件；测试重登、崩溃恢复和重复初始化。

### P1-QA-001：CI 没有运行全模块测试

- `tools/ci/ci.sh:43-44` 和 `.github/workflows/ci.yml:43-45` 只执行 `entry@default`。
- 各 HAR 的测试不能由 entry 测试等价替代。
- 工作流在找不到固定 DevEco 路径时整体 skip，可能形成误导性的绿色状态。

整改方式：由根脚本枚举 `build-profile.json5` 注册模块并逐模块测试；任何模块未运行、无结果或测试数异常下降都失败。CI 环境缺 DevEco 必须失败或明确标记为不可用，不得静默成功。

### P1-QA-002：覆盖率远低于计划门槛且未被门禁

本次重跑后的模块自有源码覆盖率显示：

| 模块 | 行覆盖 | 分支覆盖 |
|---|---:|---:|
| `core/account` | 89.9% | 78.6% |
| `core/common` | 82.8% | 61.5% |
| `core/domain` | 63.8% | 50.7% |
| `core/navigation` | 91.0% | 79.7% |
| `core/td_gateway` | 79.8% | 72.2% |
| `feature/auth` | 45.4% | 50.3% |
| `feature/chat` | 28.4% | 23.3% |
| `feature/chat_list` | 14.7% | 12.7% |
| `feature/search` | 22.6% | 20.0% |
| `feature/settings` | 25.9% | 33.7% |
| `platform/storage` | 43.1% | 49.3% |
| `platform/tdcore-bridge` | 46.0% | 37.5% |

关键文件中，`ChatListProjection` 行覆盖约 33%、分支约 36%；`MessageProjection` 行约 40%、分支约 30%；`ChatCoordinator` 行约 1.9%、分支约 1.1%。相对地，`ChatReducer` 约 88% 行、77% 分支，说明合理拆分后的纯状态逻辑是可测的。

计划要求核心域行覆盖不低于 85%、分支不低于 75%，bridge/storage 不低于 80%，adapter 不低于 70%。“测试全部通过”只说明已执行用例没有失败，不代表覆盖率达标。

### P1-QA-003：关键自动校验没有进入 CI

以下门禁缺失：

- TDLib schema/ArkTS/sensitive metadata 的代码生成一致性 verify。
- Feature → 系统 Kit 的架构依赖检查。
- 覆盖率阈值和覆盖率下降检查。
- C++ bridge 的单元、重入和压力测试。
- 24 小时 update soak、内存趋势和事件顺序报告。
- 崩溃符号化有效性验证。

### P1-ARCH-001：Feature 绕过 Port/Adapter 直接依赖系统 Kit

典型位置：

- `feature/chat/src/main/ets/coordinator/ChatCoordinator.ets:30-33`
- `feature/chat/src/main/ets/pages/ChatPage.ets:42-45`
- `feature/auth/src/main/ets/pages/RecaptchaPage.ets:1-3`
- `feature/search/src/main/ets/coordinator/SearchCoordinator.ets:10`
- `feature/chat_list/src/main/ets/coordinator/ChatListCoordinator.ets:17`
- `feature/settings/src/main/ets/coordinator/SettingsCoordinator.ets:11`

这与 D-008 冲突，也使业务逻辑难以在无设备 Kit 的环境中单测。应将剪贴板、Toast、文件选择、WebView、日志等能力通过窄 Port 注入；纯 UI 类型可保留在 Page 边界，但协调器不得直接调用 Kit。

### P1-ARCH-002：统一日志和脱敏策略未接入生产路径

`core/observability` 已存在，但生产代码广泛直接调用 `hilog`。这绕过了计划中的结构化日志、敏感字段掩码和一致的事件字段约束。搜索协调器还会以 public 字段记录搜索词，属于隐私风险。

整改方式：Feature 只能依赖 `Logger` 接口；默认禁止记录手机号、搜索词、消息文本、token、文件路径和 TDLib 原始 JSON；通过静态扫描和测试固定规则。

### P1-ARCH-003：typed navigation 存在但未接入

`core/navigation` 已建立，但 `entry/src/main/ets/pages/Index.ets:78-88` 仍以多个 boolean 和 nullable id 控制页面。随着弹层和深链增多，该模式会产生非法组合与返回栈错误。

整改方式：使用单一 typed route/navigation stack；页面只派发导航意图，不维护互相竞争的显示标志；补返回栈、搜索→聊天→返回、通知/深链冷启动测试。

### P1-GOV-001：控制文档已经失去“单一事实源”作用

- `docs/architecture/ARCHITECTURE.md:63-66` 仍描述为 Phase 0 空工程。
- `docs/product/FEATURE_MATRIX.md:18` 和 `PARITY_MATRIX.md:18` 仍把功能列为初始 Backlog/Not Started。
- `docs/quality/TEST_MATRIX.md:22-30` 仍是骨架。
- `docs/quality/DEVICE_MATRIX.md:32-35` 仍写无真机，而实际已有一台 VYG-AL00 证据。
- README 仍笼统写媒体消息未开始，与近期接收/渲染/查看实现不一致。
- `work-items/active`、`accepted`、`backlog` 只有 `.gitkeep`；证据被集中堆入 `PROGRESS.md`。

整改方式：一个工作包一个文件、一个 evidence；矩阵只由架构负责人依据 Accepted evidence 更新。`PROGRESS.md` 仅做索引，不再承载所有执行明细。

---

## 6. 中优先级问题

### P2-BUILD-001：构建只在当前 Mac 上可复现

脚本硬编码 `/Applications/DevEco-Studio.app/...`，签名配置引用当前用户名下的绝对路径，而 README 又声明支持 macOS/Linux。当前只能证明“本机热构建通过”，不能证明干净环境可构建。

整改方式：工具链由参数、环境配置或可验证的自动发现提供；增加 clean clone 构建；CI 保存编译器/SDK/NDK/TDLib lock 信息。

### P2-BUILD-002：Release 构建会改写受版本控制的生成文件

本次 `./tools/ci/build.sh release` 成功后，17 个模块的 `BuildProfile.ets` 被从 debug 状态改写为 release 状态，使工作区变脏。审计已把这些纯构建副作用恢复，未保留实现改动。构建产物不应改变受版本控制源码；应将这些文件移出版本控制、生成到 build 目录，或在 CI 中增加“构建后 git diff 必须为空”门禁。

### P2-BUILD-003：仓库和制品体积治理不足

仓库跟踪了大量 OpenSSL 构建输出、归档和测试数据；本次 Release signed HAP 约 40 MB，strip 后 `libtdjson` 仍约 31 MB。暂不阻断功能验证，但需要依赖来源、哈希、构建配方、缓存和制品体积预算，避免二进制历史持续膨胀。

### P2-UX-001：API 与 SDK 警告未纳入清债计划

- Node-API 模块验证仍有 SDK/verification warning。
- `promptAction.showToast` 已出现 deprecated warning。
- 多个 HAR 存在 `applyToProducts` warning。

这些不应与 P0 混排，但必须进入有截止版本的技术债清单。

### P2-SCOPE-001：媒体状态描述过粗

媒体接收、展示、视频和贴纸已有实现；真正未完成的主要是图片发送、通用文件消息、语音消息、完整传输失败/取消交互和高级查看器。后续工作包应按“发送/接收/渲染/缓存/失败恢复”拆分，不能再用“媒体消息完成”作为单一状态。

---

## 7. 质量恢复迭代（立即执行）

建议冻结新功能 1～2 周，按下列顺序恢复。任何 P0 未关闭前，不产生可分发测试包。

| 顺序 | 工作包 | 目标 | 退出证据 |
|---:|---|---|---|
| 1 | SEC-002 | 凭据轮换、源码/历史清理、签名秘密治理 | 新凭据有效；仓库全历史扫描通过；旧凭据失效 |
| 2 | BUILD-001 | 实际 build-time 注入与可移植工具链 | 空模板入库；本机与 clean clone 均构建；日志无秘密 |
| 3 | DATA-001 | HUKS → AccountScope → TDLib DB key 全链路 | 新装、升级、重启、错误密钥、多账号测试通过 |
| 4 | BRG-007 | Bridge 重入、generation 与关闭语义 | 原生测试 + ArkTS 集成测试 + sanitizer/压力证据 |
| 5 | QA-002 | 全模块 CI、代码生成 verify、覆盖率、禁止静默 skip | 每个模块有明确用例数；阈值失败能阻断合并 |
| 6 | ARCH-001 | 系统 Kit 收口到 Port/Adapter；Logger 接入 | 架构扫描通过；敏感日志测试通过 |
| 7 | NAV-001 | typed navigation 接管生产路由 | 深链/返回栈/进程恢复状态测试通过 |
| 8 | GOV-008 | 同步五个矩阵、ADR、work-item/evidence | 文档状态与代码证据一致；无模糊“完成” |
| 9 | SPIKE-002 | 24h update soak | 无乱序/重复、内存趋势可接受、报告可复跑 |
| 10 | PUSH-001 / CALL-001 | 形成 Go/Blocked/Deferred 决策 | 不允许保持“以后再做”的隐含状态 |

### 7.1 恢复期并行边界

- 安全/构建、数据库密钥、Native bridge 可以由不同 AI 并行，但不得修改同一文件。
- CI 负责人只能在各工作包提供标准命令后汇总，不替功能工作包补测试。
- 架构负责人独占根配置、ADR、矩阵和 Accepted 状态更新。
- Worker 不直接提交或推送；只提交 patch、测试日志和 evidence，由架构负责人复核后合并。
- 所有文件写入前登记 owner/lock；出现重叠立即停止其中一个任务。

---

## 8. 恢复完成后的功能顺序

1. 补齐核心媒体发送：图片 → 文件 → 语音；每类均覆盖上传、取消、失败和重试。
2. 聊天内搜索、下载策略与缓存管理。
3. Push/通知：若 AGC/Telegram 后端链路不可用，正式标记 Blocked，并定义前台版边界。
4. 多账号 UI 与数据隔离。
5. 中英文、深浅色、大字体、读屏和第二台设备矩阵。
6. 到 G4 后再进入群组管理、联系人、复杂媒体等 P2。
7. 通话保持独立流；没有 tgcalls 真机 PoC 和正式 ADR 时不得承诺发布日期。

建议用两个里程碑避免状态混淆：

- **MVP-Core**：允许 Push/通话明确 Blocked/Deferred，面向受控前台验证；仍必须满足安全、数据保护、稳定性和 CI 门禁。
- **Release Candidate**：必须解决或正式裁决 Push，覆盖完整设备矩阵、升级/恢复、性能和长稳测试。

---

## 9. 工期判断调整

现有功能进度比原计划快，但主要是纵向功能实现领先，不能抵扣安全、基础设施和验证债务。

- Quality Recovery Sprint：**1～2 周**，前提是凭据轮换权限和测试设备可用。
- 恢复后完成 MVP-Core 的剩余核心能力：**约 4～8 周**，媒体发送和 Push 决策是主要变量。
- 可持续测试的核心聊天 MVP：原计划的 **总计 4～6 个月**仍合理，不建议因当前演示进度下调。
- 对外 Release/Beta：仍需按 **8～12 个月**量级管理，取决于 Push、通话取舍、设备覆盖和团队并行度。

这些区间不是承诺日期。只有 G1 真正通过并关闭安全与数据阻断项后，才冻结正式排期。

---

## 10. 审计执行与结果

已执行或检查：

- Git 状态、提交历史、远端同步状态和模块树。
- README、PROGRESS、Architecture、Feature/Parity/Test/Device Matrix。
- 入口、授权、HUKS、日志、导航、Chat/Search 协调器和 Native bridge 关键路径。
- `python3 tools/ci/check_design_tokens.py`：通过。
- `./tools/ci/check.sh`：通过，Debug assemble 成功；存在 NAPI verification、deprecated API 和 HAR 配置警告。
- `./tools/ci/ci.sh`：**失败**，在 secret scan 阶段发现受版本控制的凭据。
- 逐个重跑当前 19 个有测试套件的模块：**756/756 通过，0 Failure，0 Error**。这项结果是审计临时补跑的证据，现有 CI 尚不会自动执行它；无测试套件的模块仍需由 CI 显式列出并说明策略。
- `./tools/ci/build.sh release`：通过，约 28 秒；生成约 40 MB signed HAP。存在 NAPI verification、deprecated API、HAR `applyToProducts` 和未启用 obfuscation 警告。
- Release 构建产生的 17 个 `BuildProfile.ets` 工作区改动已恢复；最终实现仓库重新保持干净并与 `origin/master` 一致。

审计没有修改 Harmony 实现代码；只更新审计报告和上位计划。安全问题修复应作为独立、可审查工作包实施。

---

## 11. 架构负责人后续 Check 清单

每个实现 AI 交付时必须逐项回答：

- 是否只修改授权文件，是否与其他 AI 的 owner/lock 冲突？
- 是否有真实生产调用链，而不只是创建了 interface/class？
- 是否有失败、取消、重入、重启和旧数据迁移语义？
- 是否新增系统 Kit、全局状态、原始 JSON、明文秘密或敏感日志？
- 是否新增/更新模块测试，CI 是否真实执行该模块？
- 覆盖率是否满足所属层级阈值，是否出现关键路径下降？
- 是否更新 work-item evidence；Feature/Parity/Test/Device Matrix 是否有依据？
- 是否由检查 AI 做过独立风险审查，并由架构负责人重跑命令？
- 是否满足当前 Gate，而不是只证明界面可见或真机点击可走通？

只有全部成立，状态才能从 `Verifying` 进入 `Accepted`。
