# DevEco Studio IDE 私有接口 Agent Playbook

> 面向 AI agent 使用。这里不是内部调研纪要或团队过程记录；它说明 agent 在处理 DevEco Studio IDE 本体、插件、本地服务和私有协议相关请求时，如何定位入口、判断风险、选择只读动作，并避免泄露用户数据。

## 何时使用

用户请求包含以下意图时使用本页：

- 调查或自动化 DevEco Studio IDE 本体能力。
- 使用或分析 CodeGenie、本地 RAG、MCP、LanceDB、OpenAI 风格本地转发服务。
- 处理 `devecostudio://` 私有协议。
- 分析 Previewer、ArkUI Inspector、Profiler、Doctor、Diagnostic、FaultLog、HiLog、UxTestService。
- 枚举插件 action、toolWindow、service、extension point、命令行入口或本地缓存边界。

## 先做什么

1. 明确用户是要“静态分析”“离线文件分析”“启动 IDE/服务”“连接设备”“读取用户数据”还是“调用 AI/网络能力”。
2. 先确认 DevEco Studio 安装路径和版本；不要复用旧版本的类名、端口、jar、URL scheme 或配置路径。
3. 默认只做静态、只读、小范围探测。
4. 凡是会启动 GUI/服务、连接设备、读取用户侧数据、写文件、调用 localhost/网络/LLM provider 的动作，都先请求确认。
5. 不公开 token、securityId、API key、cookie、项目源码片段、日志正文、内部接口 path 或用户路径细节。

## 常见路径候选

先探测，不要假设一定存在：

```bash
APP="/Applications/DevEco-Studio.app"
CONTENTS="$APP/Contents"
PLUGINS="$CONTENTS/plugins"
TOOLS="$CONTENTS/tools"
SDK="$CONTENTS/sdk/default/openharmony"
```

已知验证过的环境线索：DevEco Studio 6.0.2，Bundle ID `com.huawei.devecostudio.ds`，数据目录名 `DevEcoStudio6.0`，URL scheme `devecostudio`。其他版本必须重新探测。

## 风险分级

### 默认允许

静态、只读、低敏动作：

```bash
plutil -p /Applications/DevEco-Studio.app/Contents/Info.plist
cat /Applications/DevEco-Studio.app/Contents/Resources/product-info.json
cat /Applications/DevEco-Studio.app/Contents/Resources/build.txt
find /Applications/DevEco-Studio.app/Contents/plugins -maxdepth 2 -type d
find /Applications/DevEco-Studio.app/Contents/tools -maxdepth 3 -type f
jar tf <plugin.jar> | rg 'META-INF/.*\\.xml$'
unzip -p <plugin.jar> META-INF/plugin.xml
strings <plugin.jar> | rg -i 'localhost|127\\.0\\.0\\.1|websocket|grpc|token|mcp|port'
```

`strings` / `rg` 结果只能用于本地分类，不得原样回传。命中 `token`、`securityId`、`API key`、`Authorization`、cookie、内部 URL 或用户路径时，只报告“发现敏感字段线索”和类别，不显示值、上下文或完整路径。

允许分析离线文件：`.htrace`、profiler snapshot、faultlog、stacktrace、appFreeze/cppCrash 文本、`.arkli`、`.preview` 产物。

### 需要用户确认

- 启动 DevEco Studio、LightEdit、JCEF toolWindow、Preview Server、ArkUI Inspector、Profiler 或 Debug session。
- 连接设备或模拟器。
- 抓截图、录屏、layout、HiLog、诊断包或设备文件。
- 运行 `inspect.sh`、`format.sh`、`ltedit.sh`。
- 读取用户侧 recent projects、workspace、LocalHistory、聊天历史、缓存、日志正文或内部数据库。
- 调用 CodeGenie localhost HTTP/WebSocket、LanceDB server、MCP server 或外部 LLM provider。
- 创建、修改或删除 MCP 配置、模型配置、项目文件、SDK、缓存或 IDE 状态。
- 读取 MCP/model provider 配置正文、env、headers、workspace 绑定信息或任何 credential-adjacent 字段。

### 默认禁止

- 自动登录、上传、发布、部署、清缓存、删除状态。
- 在未隔离环境中打开未知 `devecostudio://` URL。
- 公开或写入日志：token、securityId、API key、cookie、Authorization header、refresh token、JWT、OAuth code、项目源码片段、日志正文、内部测试域名、完整云端 API path、团队/App/项目标识。

无法分类的动作按“需要用户确认”处理。

## IDE 命令入口

DevEco Studio 包内有 JetBrains 风格命令封装：

| 入口 | 路径 | agent 用法 | 风险 |
| --- | --- | --- | --- |
| `inspect.sh` | `Contents/bin/inspect.sh` | 仅在用户确认后用于离线 inspection | 可能启动 IDE 后端并写输出 |
| `format.sh` | `Contents/bin/format.sh` | 仅在用户确认后格式化源文件 | 会修改文件 |
| `ltedit.sh` | `Contents/bin/ltedit.sh` | 仅在用户确认后打开 LightEdit | 会启动 GUI |

可静态记录命令支持的线索，例如 `--line`、`--column`、`--wait`、`--temp-project`、`--project`；不要未经确认直接打开项目或文件。

## devecostudio://

DevEco Studio 注册了 macOS URL scheme：`devecostudio`。

静态线索：

- `Contents/Info.plist`
- `plugins/openharmony/lib/project-mgmt-6.0.2.642.jar`
- `com.huawei.deveco.projectmgmt.ohos.actions.protocol.IdeProtocolHandler`
- 扩展点：`com.huawei.devecoProtocolHandler`

已确认候选格式：

```text
devecostudio://sample/v1/import/git?param={...}
devecostudio://sample/v1/import/fs?param={...}
```

已发现 action：

| action | 用途 | 必需字段 | 默认策略 |
| --- | --- | --- | --- |
| `sample/v1/import/git` | 导入 Git 示例工程 | `repoUrl`、`branch`、`projectName`、`relativePath` | 只静态分析；实际打开需确认和隔离 |
| `sample/v1/import/fs` | 导入下载文件/Zip 示例工程 | `downloadUrl`、`checksum`、`projectName` | 只静态分析；实际打开需确认和隔离 |

URL 字符串解析属于 `allow`；实际 import、git remote 访问、download、写工程文件或打开 IDE 属于 `require_confirm`。未知 scheme/action 默认为 `deny`，除非用户明确要求在隔离测试环境中验证。

未静态确认 `devecostudio://openFile` 或 `devecostudio://openProject`。实际打开 URL 前必须使用隔离用户、临时 VM 或测试项目。

## CodeGenie、本地 AI、RAG、MCP

这些能力默认属于高风险数据面。agent 可以静态识别能力，不默认启动或调用。

静态线索：

- `Contents/plugins/codegenie-plugin/embedding_model/VESO-model/VESO-25M/`
- `Contents/plugins/codegenie-plugin/lancedb_server/main.js`
- `Contents/plugins/codegenie-plugin/lib/rag-core-6.0.2.642.jar`
- `Contents/plugins/codegenie-plugin/lib/instrumented-CodeChat.jar`
- `Contents/plugins/codegenie-plugin/lib/instrumented-codegenie-infrastructure.jar`

已确认能力类别仅适用于已验证的 DevEco Studio 6.0.2 环境，不作为稳定 API：

- 本地 VESO ONNX embedding 模型，输出维度线索为 `768`。
- LanceDB 本地向量库，常见表名线索为 `knowledge_base`。
- LanceDB WebSocket/Socket.IO 服务，形态类似 `node main.js <port> <securityId>`。
- OpenAI 风格本地 HTTP 转发服务，线索包含 `POST /chat/completions`、`GET /models`、streaming、`Chat-Id`。
- MCP 支持 stdio、HTTP/SSE、Streamable HTTP。
- 外部 LLM provider 线索包括 OpenAI、Anthropic、Gemini、自定义模型、proxy、SSE。

agent 规则：

- 不读取用户本地 `.lancedb`、聊天历史、模型配置数据库、headers、API key 或 token。
- 不读取 MCP/model provider 配置正文、env、headers、workspace 绑定或 provider account 字段，除非用户确认读取范围和脱敏策略。
- 不调用 `/models`、`/chat/completions`、WebSocket、MCP server 或外部 LLM provider，除非用户确认。
- 不记录 `securityId`、端口、RAG chunk、prompt、源码片段或模型配置详情。
- 若必须验证，先说明会触发的本地服务、网络流向、读取范围和脱敏策略。

## Previewer / Inspector / Profiler / Debug

| 能力 | 静态入口 | agent 默认动作 | 需要确认的动作 |
| --- | --- | --- | --- |
| Preview Server | `plugins/harmony/harmony-preview-server`、`plugins/openharmony/openharmony-preview-server` | 枚举插件、解析离线 `.preview` | 启动 server、访问端口、Debug Preview |
| ArkUI Inspector | `plugins/openharmony/arkui-inspector` | 分析离线 `.arkli` | 实时组件树、截图、live mode |
| Profiler / Trace | `ohos-profiler`、`ohos-trace` | 分析离线 `.htrace` 或 snapshot | 实时采集、`hdc fport`、hiprofiler |
| Doctor / Diagnostic | `ohos-doctor-view`、`diagnostic-plugin` | 静态建模检查项 | 执行 IDE action、收集或上传诊断包 |
| FaultLog / HiLog | `faultlog-ui`、`ohos_hilog-6.0.2.642.jar` | 离线日志摘要 | 在线 HiLog、截图/录屏、设备侧抓取 |
| Debug / PandaDAP | `ohos-debug-common`、`ace-debugger`、`ohos-debugger` | 静态协议分析 | run/debug/attach/ConnectServer |

DAP/LSP/WebSocket 线索都带 DevEco 私有约定；不要把 `sid`、内部 payload、hidden action 或测试 action 当长期稳定接口。

## 插件入口索引

高价值插件只用于静态导航，触发 action 需确认：

- `openharmony`：项目/模块/页面创建、Build HAP/App、Previewer、HiLog/FaultLog、ArkUI Inspector、Device File Explorer、Database、SDK 管理、Debug/Attach/Hot reload。
- `harmony`：Harmony 项目能力、登录、Cloud Toolkit、AppAnalyzer、Simulator/HVD、Cangjie 实验配置。
- `diagnostic-plugin`：Collect Logs and Diagnostic Data、UI freeze、low memory、crash、HDC 异常监听。
- `ohos-profiler`：Profiler、Graphics Profiler、SmartProfiler、gRPC/WebSocket/JCEF 数据通道。
- `ohos-trace`：trace/lemon、metric/log upload 扩展点。
- `ui-generator`：`Generate Project from...`、Android 到 ArkUI 转换、JCEF 文件选择与转换 handler。
- `Application-Agent-Plugin`：Application Agent、JCEF、OAuth、TokenManager、登录/登出事件监听。
- `operation-analyzer-plugin`：Operation Analyzer、账号/项目/App/团队/监控数据面。

## CLI 与 SDK 工具链

| 工具 | 路径线索 | 默认允许 | 需要确认 |
| --- | --- | --- | --- |
| `ohpm` | `Contents/tools/ohpm/bin/ohpm` | `info`、`list`、`root`、`config list` | install/update/clean/publish/unpublish |
| `hvigor` | `Contents/tools/hvigor/bin/hvigorw.js` | help/tasks | assemble/prune/daemon/watch |
| `hdc` | `Contents/sdk/default/openharmony/toolchains/hdc` | version/help/list | shell/install/file/fport/设备连接 |
| `restool` | SDK toolchains | help | 写输出或 `--forceWrite` |
| `idl` | SDK toolchains | help | 生成代码 |
| `syscap_tool` | SDK toolchains | help/version | 写输出 |
| `ark_disasm` | SDK toolchains | help | 写反汇编文件 |
| `hnpcli` | SDK toolchains | help | 打包写 `.hnp` |
| `rawheap_translator` | SDK toolchains | help | 生成 heapsnapshot |
| `hilogtool` | SDK toolchains | help | 写输出 |

## UxTestService

静态入口：

- `Contents/tools/UxTestService/ux_detect.py`
- `Contents/tools/UxTestService/CheckMethods.py`
- `Contents/tools/UxTestService/util/param_builder.py`
- `Contents/tools/UxTestService/config/config.py`

入口参数线索：

```text
--task_id
--task_type UxTest|GlobalReview
--check_param <检测参数文件路径>
```

agent 可以静态解析规则、参数 schema 和输入输出格式。真实运行检测会读取截图、layout、ArkUI JSON、HAP 或 record 信息并写结果，必须先确认。

## 用户侧配置与隐私

常见目录：

- 配置：`~/Library/Application Support/Huawei/DevEcoStudio6.0`
- 偏好：`~/Library/Preferences/com.huawei.devecostudio.ds.plist`
- 日志：`~/Library/Logs/Huawei/DevEcoStudio6.0`
- 缓存：`~/Library/Caches/Huawei/DevEcoStudio6.0`

高风险文件/目录：

- `options/recentProjects.xml`
- `workspace/*.xml`
- `options/CodeGenieChatHistoryPersistentState.xml`
- `idea.log`、`lsp-server/*.log`、`dap_server_*.log`
- `indexing-diagnostic/`
- `jcef_cache/`
- `LocalHistory`、`fileHistory`、`editor/`、`vcs-log/`
- `app-internal-state.db`

默认只允许确认目录是否存在、文件数量和文件类型分布。展示文件名、mtime、大小、完整路径模式或正文前必须确认并说明脱敏策略，因为文件名本身也可能暴露项目、团队或业务信息。

## 确认请求模板

需要确认时，明确将启动什么、读取什么、是否联网、是否写文件、脱敏策略和回滚边界：

```text
我需要执行高风险 DevEco IDE 动作：<启动服务/读取配置/调用 localhost/打开 URL/连接设备>。
会启动：<无/IDE/JCEF/Preview Server/CodeGenie/LanceDB/MCP>。
会读取：<插件静态文件/用户配置/日志/缓存/设备数据>。
网络或 localhost：<无/localhost/外部 provider>。
会写入：<无/配置文件/项目文件/诊断输出>。
脱敏：<只报告类别和摘要，不显示 token、路径、源码、日志正文>。
回滚：<无写入/可删除临时文件/不可自动回滚>。
是否允许？
```

## 输出格式

回答用户时优先给可行动摘要：

```text
scope: static-analysis|offline-file|service-start|device-connected
version: <DevEco version or unknown>
paths_checked: <small list>
actions_taken: <short list>
actions_skipped: <short list>
capability: <what was found>
risk: allow|require_confirm|deny
confirmation_needed: <yes/no + reason>
redaction: <what was removed or summarized>
evidence_level: static|offline-artifact|runtime-probe|user-confirmed
next_action: <one concrete step>
raw_sensitive_content_stored: false
```

不要把完整扫描输出、私有接口 payload、日志正文、聊天内容、源码片段、token 或真实用户路径贴回对话。
