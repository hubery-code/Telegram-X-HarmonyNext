# Test Matrix（测试策略与用例全景）

> 单一事实源（计划 §12）。测试金字塔：
> - 60–70% 单元测试（ArkTS 领域逻辑 / Reducer / 导航 / 编解码 / 密钥 / 数据存储）；
> - 20–30% 架构与契约测试（NAPI 重入与代际 / Ports & Adapters 契约 / 代码生成一致性 / 架构 Kit-free 检查）；
> - 5–10% 真机 UI/E2E 验证（真实设备长连接 / 授权 / 会话列表 / 聊天收发 / 撤回 / 编辑 / 搜索）。

---

## 1. 单元测试全景（19 个可测试模块，793/793 PASS）

通过 `python3 tools/ci/test_all_modules.py` 执行全量自动化调度（Hvigor module test runner）：

| 序号 | 模块名称 | 模块源码路径 | 单测文件路径 | 用例数 | 状态 | 关键验证域 |
|---|---|---|---|---|---|---|
| 1 | `entry` | `entry` | `entry/src/test/List.test.ets` | 21 | PASS | 生命周期协调、HUKS 密钥装配、类型化路由控制器 |
| 2 | `core_common` | `core/common` | `core/common/src/test/List.test.ets` | 33 | PASS | RFC 4648 Base64 算法、时钟、ID 生成器、错误类型 |
| 3 | `core_design_system` | `core/design_system` | `core/design_system/src/test/List.test.ets` | 25 | PASS | 设计令牌（颜色/排版/间距/圆角）一致性 |
| 4 | `platform_ports` | `platform/ports` | `platform/ports/src/test/List.test.ets` | 38 | PASS | 剪贴板/Toast 契约、内存型测试 Doubles (Fakes) |
| 5 | `core_navigation` | `core/navigation` | `core/navigation/src/test/List.test.ets` | 37 | PASS | 强类型路由注册表、路径编解码、深链解析、返回栈序列化 |
| 6 | `core_td_api_generated` | `core/td_api_generated` | `core/td_api_generated/src/test/List.test.ets` | 48 | PASS | TDLib 3205 个 DTO 编解码、空安全与联合判别 |
| 7 | `core_td_gateway` | `core/td_gateway` | `core/td_gateway/src/test/List.test.ets` | 53 | PASS | 有序事件队列、背压、重试调度与账号隔离 |
| 8 | `core_observability` | `core/observability` | `core/observability/src/test/List.test.ets` | 43 | PASS | 统一 Logger、日志级别、结构化元数据与脱敏过滤 |
| 9 | `feature_template` | `feature/_template` | `feature/_template/src/test/List.test.ets` | 15 | PASS | Feature MVI 脚手架纯函数契约 |
| 10 | `platform_network` | `platform/network` | `platform/network/src/test/List.test.ets` | 18 | PASS | 网络快照监听、类型映射与断网探测 |
| 11 | `platform_storage` | `platform/storage` | `platform/storage/src/test/List.test.ets` | 47 | PASS | KV 存储适配器、缓存淘汰与持久化 |
| 12 | `core_account` | `core/account` | `core/account/src/test/List.test.ets` | 105 | PASS | AccountRegistry、AccountScope、HUKS 密钥管理器 |
| 13 | `platform_tdcore_bridge` | `platform/tdcore-bridge` | `platform/tdcore-bridge/src/test/List.test.ets` | 15 | PASS | NAPI 回调重入安全、快照迭代、延迟退订、Session Generation |
| 14 | `core_domain` | `core/domain` | `core/domain/src/test/List.test.ets` | 60 | PASS | ChatListProjection、MessageProjection、未读/置顶状态 |
| 15 | `feature_auth` | `feature/auth` | `feature/auth/src/test/List.test.ets` | 47 | PASS | AuthReducer、二维码登录、状态流转、DB 加密在线平滑迁移 |
| 16 | `feature_chat_list` | `feature/chat_list` | `feature/chat_list/src/test/List.test.ets` | 15 | PASS | ChatListReducer、置顶、标未读、长按菜单意图处理 |
| 17 | `feature_chat` | `feature/chat` | `feature/chat/src/test/List.test.ets` | 124 | PASS | ChatReducer、文本收发、回复/编辑/删除、转发选择器 |
| 18 | `feature_settings` | `feature/settings` | `feature/settings/src/test/List.test.ets` | 30 | PASS | SettingsReducer、配置持久化、登出回调触发 |
| 19 | `feature_search` | `feature/search` | `feature/search/src/test/List.test.ets` | 19 | PASS | SearchReducer、全局搜索过滤、联系人/会话/消息分组 |
| **合计** | **19 个模块** | — | — | **793** | **100%** | **Failures: 0, Errors: 0** |

豁免模块说明：
- `platform/files`：系统应用文件存储适配器，由 `entry` 端到端集成测试与真机套件覆盖；
- `platform/keystore`：硬件 HUKS 密钥管理，由 `entry/src/test/lifecycle/BootstrapKeystore.test.ets`（8 组单测）与真机环境覆盖。

---

## 2. CI 门禁验证流水线 (`./tools/ci/ci.sh`)

全量 9 步静态与动态防线：

1. `setup-check.sh`：工具链自动探测与 DevEco/Node/SDK 26 版本锁定；
2. `secret-scan.sh`：全仓严格凭据与签名扫描，严禁密钥字面量入库；
3. `check_design_tokens.py`：设计系统令牌拼写静态扫描，防止运行时 undefined 异常；
4. `check_architecture.py`：核心域、Reducer 及 Coordinator 100% Kit-free 架构防线；
5. `check_codegen.py`：3205 个 DTO 类与 154 个敏感字段代码生成一致性字节比对；
6. `check.sh`：全仓 linter 与 ArkTS 静态类型检查；
7. `test_all_modules.py`：全量 19 模块 793 项单元测试执行与基线断言（≥780 项）；
8. `build.sh debug`：构建 Debug HAP 产物；
9. `build.sh release`：构建 Release HAP 产物，断言构建后工作区 100% 洁净无污染。

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
