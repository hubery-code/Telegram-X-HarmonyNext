# Test Matrix（测试策略与用例全景）

> 单一事实源（计划 §12）。测试金字塔：
> - 60–70% 单元测试（ArkTS 领域逻辑 / Reducer / 导航 / 编解码 / 密钥 / 数据存储）；
> - 20–30% 架构与契约测试（NAPI 重入与代际 / Ports & Adapters 契约 / 代码生成一致性 / 架构 Kit-free 检查）；
> - 5–10% 真机 UI/E2E 验证（真实设备长连接 / 授权 / 会话列表 / 聊天收发 / 撤回 / 编辑 / 搜索）。

---

## 1. 单元测试全景（19 个可测试模块）

> ⚠️ **数字口径（2026-10-20 校准）**：本表的用例数长期由各工作包自行回写，已出现大幅漂移 ——
> 例如 `entry` 记 21 而实测 **160**、`core_common` 记 33 而实测 **86**、`feature_chat` 记 130
> 而实测 **514**（差额主要来自 2026-09-29 至 10-14 那批只落代码未回写文档的提交）。
> 下表**仅 `entry` / `core_common` / `feature_chat` 三行是 2026-10-20 实测值**
> （`devecocli` + hvigorw `test --mode module`，读 `<module>/.test/default/intermediates/test/coverage_data/test_result.txt`
> 的 `Tests run:` 汇总行，不认 BUILD SUCCESSFUL）；**其余行的数字未复跑，标记为「未校准」**，
> 按本仓口径宁可留旧值加标注，也不填没跑过的数。全量数字待跑 `test_all_modules.py` 后一次性回写。

通过 `python3 tools/ci/test_all_modules.py` 执行全量自动化调度（Hvigor module test runner）：

| 序号 | 模块名称 | 模块源码路径 | 单测文件路径 | 用例数 | 状态 | 关键验证域 |
|---|---|---|---|---|---|---|
| 1 | `entry` | `entry` | `entry/src/test/List.test.ets` | **160**（2026-10-20 实测） | PASS | 生命周期协调、HUKS 密钥装配、类型化路由控制器 |
| 2 | `core_common` | `core/common` | `core/common/src/test/List.test.ets` | **86**（2026-10-20 实测） | PASS | RFC 4648 Base64 算法、时钟、ID 生成器、错误类型、Lang 词典与日期形态 |
| 3 | `core_design_system` | `core/design_system` | `core/design_system/src/test/List.test.ets` | 38 | PASS | 设计令牌（颜色/排版/间距/圆角）一致性、ThemeManager 全局主题 |
| 4 | `platform_ports` | `platform/ports` | `platform/ports/src/test/List.test.ets` | 42 | PASS | 剪贴板/Toast/MediaPicker 契约、内存型测试 Doubles (Fakes) |
| 5 | `core_navigation` | `core/navigation` | `core/navigation/src/test/List.test.ets` | 37 | PASS | 强类型路由注册表、路径编解码、深链解析、返回栈序列化 |
| 6 | `core_td_api_generated` | `core/td_api_generated` | `core/td_api_generated/src/test/List.test.ets` | 48 | PASS | TDLib 3205 个 DTO 编解码、空安全与联合判别 |
| 7 | `core_td_gateway` | `core/td_gateway` | `core/td_gateway/src/test/List.test.ets` | 53 | PASS | 有序事件队列、背压、重试调度与账号隔离 |
| 8 | `core_observability` | `core/observability` | `core/observability/src/test/List.test.ets` | 43 | PASS | 统一 Logger、日志级别、结构化元数据与脱敏过滤 |
| 9 | `feature_template` | `feature/_template` | `feature/_template/src/test/List.test.ets` | 15 | PASS | Feature MVI 脚手架纯函数契约 |
| 10 | `platform_network` | `platform/network` | `platform/network/src/test/List.test.ets` | 18 | PASS | 网络快照监听、类型映射与断网探测 |
| 11 | `platform_storage` | `platform/storage` | `platform/storage/src/test/List.test.ets` | 47 | PASS | KV 存储适配器、缓存淘汰与持久化 |
| 12 | `core_account` | `core/account` | `core/account/src/test/List.test.ets` | 105 | PASS | AccountRegistry、AccountScope、HUKS 密钥管理器 |
| 13 | `platform_tdcore_bridge` | `platform/tdcore-bridge` | `platform/tdcore-bridge/src/test/List.test.ets` | 20 | PASS | NAPI 回调重入安全、快照迭代、延迟退订、Session Generation、24h Update Soak |
| 14 | `core_domain` | `core/domain` | `core/domain/src/test/List.test.ets` | 64 | PASS | ChatListProjection、MessageProjection、图片发送组包、上传进度 |
| 15 | `feature_auth` | `feature/auth` | `feature/auth/src/test/List.test.ets` | 47 | PASS | AuthReducer、二维码登录、状态流转、DB 加密在线平滑迁移 |
| 16 | `feature_chat_list` | `feature/chat_list` | `feature/chat_list/src/test/List.test.ets` | 15 | PASS | ChatListReducer、置顶、标未读、长按菜单意图处理 |
| 17 | `feature_chat` | `feature/chat` | `feature/chat/src/test/List.test.ets` | **514**（2026-10-20 实测，35 个测试类） | PASS | ChatReducer、文本/图片收发、回复/编辑/删除、转发选择器、上传取消 |
| 18 | `feature_settings` | `feature/settings` | `feature/settings/src/test/List.test.ets` | 41 | PASS | SettingsReducer、配置持久化、全局深浅色主题切换 |
| 19 | `feature_search` | `feature/search` | `feature/search/src/test/List.test.ets` | 19 | PASS | SearchReducer、全局搜索过滤、联系人/会话/消息分组 |
| **合计** | **19 个模块** | — | — | **未给出（待全量复跑）** | 实测 3 模块全 PASS | **Failures: 0, Errors: 0**（就 2026-10-20 实测的 entry/core_common/feature_chat 三模块而言） |


豁免模块说明：
- `platform/files`：系统应用文件存储适配器，由 `entry` 端到端集成测试与真机套件覆盖；
- `platform/keystore`：硬件 HUKS 密钥管理，由 `entry/src/test/lifecycle/BootstrapKeystore.test.ets`（8 组单测）与真机环境覆盖。

---

## 2. CI 门禁验证流水线 (`./tools/ci/ci.sh`)

全量 13 步静态与动态防线：

1. `setup-check.sh`：工具链自动探测与 DevEco/Node/SDK 26 版本锁定；
2. `secret-scan.sh`：全仓严格凭据与签名扫描，严禁密钥字面量入库；
3. `check_design_tokens.py`：设计系统令牌拼写静态扫描，防止运行时 undefined 异常；
4. `check_architecture.py`：核心域、Reducer 及 Coordinator 100% Kit-free 架构防线；
5. `check_codegen.py`：3205 个 DTO 类与 154 个敏感字段代码生成一致性字节比对；
6. `check_accessibility_labels.py`：图标控件无障碍标签与分组吞并守卫（A11Y-101/102）；
7. `check_i18n_literals.py`：十条规则 —— 视图层与数据层写死中文（R1/R5a）、**看着像文案**的英文字面量落进视图层文案槽位（R4'，按「含空格 / 首字母大写 / 命中词典」的形状判定，不再只认词典已有的英文；I18N-RETSPAN-101 起还覆盖**页面类方法里的 `return` 操作数**）、数据层展示串落在 `return`/Toast 出口/**赋值右侧**/**构造器实参** 四个位置（R5b，构造器靠全仓 class→参数表索引认 `*Key` 豁免）、字面量 key 双词典命中（R2，两层同检）、`*Key` 载体收到的字面量也必须双词典命中（R6，I18N-LITERAL-104 补上豁免自己开的洞）、EN/ZH 键集合全等（R3）、日期形态单文件（R8）、TDLib 语言档（R9）、**同一本词典内不许重名**（R10，I18N-DUPKEY-101 —— R3 的集合口径天然去重，结构上看不见重复）、视图层方法 return（R4' 扩展）（I18N-LITERAL-101~104）；
8. `check_appstorage_pairs.py`：`AppStorage` 键读写配对（APPSTORAGE-PAIR-101）；
9. `check_path_portability.py`：**守卫脚本自身的路径口径自检**（PATH-PORTABLE-101）—— 归一化 / `Path.parts` 比较 / `subprocess` 编码三类；它守的是前 8 步的元数据层，那一层坏掉时前面几个会静默失真（带 `--self-test`，8 项负向对照）；
10. `check.sh`：全仓 linter 与 ArkTS 静态类型检查；
11. `test_all_modules.py`：全量 19 模块单元测试执行与基线断言（≥790 项；**实际条数已高于该基线，但精确值待全量复跑后回写本表**）；
12. `build.sh debug`：构建 Debug HAP 产物；
13. `build.sh release`：构建 Release HAP 产物，断言构建后工作区 100% 洁净无污染。

---

## 3. 真机 E2E 验证状态

- 已验证设备：`Huawei VYG-AL00`（序列号 `6XE0225A27023538`），HarmonyOS NEXT API 26；
- 垂直链路已验证场景：
  - [x] 真机扫码与手机号登录全流程；
  - [x] 会话列表拉取、头像异步加载与渲染；
  - [x] 进入聊天详情、发送文本消息实时上屏；
  - [x] 消息长按菜单：复制文本、回复、编辑与双向删除；
  - [x] 消息转发目标选择器覆盖渲染与跨会话转发；
  - [x] 会话置顶/取消置顶与手动标未读；
  - [x] 全局搜索与搜索→聊天→返回栈保活；
  - [x] 进程杀掉重启后状态无缝恢复。
