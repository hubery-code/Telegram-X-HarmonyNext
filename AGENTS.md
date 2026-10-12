# AI Agent 协作与研发行为准则 (AGENTS.md)

本项目有多个 AI Agent（OpenAI Codex、Google Antigravity、Kimi Code、DeepSeek 等）与人类工程师共同协作。所有参与本项目的 AI 必须严格遵守以下规则：

---

## 1. 🚨 CI 运行与测试执行准则（强制规则）

> **核心红线**：
> **除非用户在当前对话中明确要求“全量跑 CI”或“运行全模块测试”，否则在任何常规任务、Bugfix 或功能完成后，严禁私自运行全量 CI（`./tools/ci/ci.sh`）或全模块单测（`python3 tools/ci/test_all_modules.py`）。**

### 为什么禁止默认全量 CI？
全模块单元测试包含数十个模块的 ArkTS coverage 编译与用例执行，单次完整构建耗时长达 20 ~ 30 分钟。在频繁迭代的日常开发中，每次提交或任务后都跑全量 CI 极其耗时且现阶段完全没有必要。

### 日常任务完成的标准验证流程（轻量快速）：
日常只需执行以下秒级至分钟级的局部验证，全部通过即可提交/交付：
1. **秒级架构与代码生成防线（必跑，< 2 秒）**：
   ```bash
   python3 tools/ci/check_architecture.py
   python3 tools/ci/check_codegen.py
   ```
2. **仅跑当前任务受影响模块的局部测试（按需运行）**：
   ```bash
   # 例如本次只改动了 feature_chat_list：
   ./hvigorw test --mode module -p module=feature_chat_list@default --no-daemon
   ```
3. **零污染机密检查（若涉及敏感或构建文件）**：
   ```bash
   python3 tools/ci/secret_scan.py
   ```

---

## 2. 跨 Agent 状态协同准则 (`cross-agent-session`)

本项目接入了全局跨 Agent 状态看板与文件防冲突中心。
1. **动工前探查**：执行 `agent-session state get`，检查是否有其他 Agent 正在修改相同文件。
2. **声明锁定**：动工前执行 `agent-session state set --agent <name> --status BUSY --task "<任务描述>" --files <锁定文件列表> --cwd "$(pwd)"`。
3. **完工后释放**：任务交付或提交后，及时更新状态为 `COMPLETED`，释放文件锁。
4. **无交叉独立提交**：若工作区存在其他 Agent 未提交的改动，必须通过 `git add <精确文件>` 进行隔离提交，绝对不要使用 `git commit -a` 或包含他人正在修改的文件。

---

## 3. ArkTS / HarmonyOS 编码关键防坑点

1. **ArkTS `Result` 类型收窄限制**：
   ArkTS 编译器不能在 `else` 或提前 `return` 后自动收窄 `Result<T, E>` 类型。必须分别写显式的 `if (res.ok)` 和 `if (res.err)` 分支，否则报编译错误。
2. **ArkUI 状态与组件生命周期**：
   UI 组件不要直接依赖私有字段的变化驱动渲染，状态变更必须经规范的 `@State`、`@Prop` 或 Reducer 状态流。
3. **分层架构红线**：
   `feature/*` 之间严禁直接相互依赖；业务功能与系统能力之间严禁直接穿透，必须经 `platform/*` 隔离；所有改动必须通过 `check_architecture.py` 检验。

---

## 4. 业务范围与研发决策准则（用户明确红线）

1. **华为 Push 短期内不做（Blocked / Deferred）**：
   - 华为 Push Kit 离线唤醒链路因 Telegram 官方后端缺乏原生对接（参见 ADR-003），经用户明确指示**短期内不做**。
   - 所有 AI Agent 严禁认领或开发 `NOTIF-101`、`NOTIF-102`、`FEAT-PUSH-001/002` 及相关 Push Kit 工作包，保持现有的前台长连接/前台保活方案即可，无需在此方向消耗研发工时。
2. **无障碍（Accessibility / A11Y）不做（Deferred / Non-Goal）**：
   - 经用户明确指示，**无障碍相关能力不做**。
   - 现有的基础静态守卫（`check_accessibility_labels.py`）仅作防劣化保留，严禁认领或开展 `A11Y-104` 以及任何新增的屏幕朗读、无障碍听感适配或专项 A11Y 取证任务。
3. **App 默认显示中文（Default Language = 简体中文）**：
   - 经用户明确指示，**应用默认界面语言必须显示为中文**。
   - 无论是新用户首装、未配置偏好、环境缺失回落，还是新功能/UI 研发对齐，均必须以**简体中文（zh / zh-Hans）**为默认基准；单测、UI 验证与截图取证均以中文环境为第一优先级。
