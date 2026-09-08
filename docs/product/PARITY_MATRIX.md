# Parity Matrix（Android ↔ HarmonyOS 行为对等矩阵）

> 单一事实源（计划 §20）。记录**行为差异**，不是功能清单（功能清单见 FEATURE_MATRIX.md）。
> 方法论：Android 参考行为以脱敏录屏/截图/结构化样本为证据（GOV-005，`docs/product/behavior-samples/`），
> HarmonyOS 侧以相同场景的输出对比。差分测试（计划 §12.2-4）用此表驱动。
> 表行与 FEATURE_MATRIX.md 的功能 ID 一一对应。

## 状态定义

| 状态 | 含义 |
|---|---|
| `Not Started` | 尚未采集 Android 基线 |
| `Baseline Captured` | Android 行为样本已入库（GOV-005 证据） |
| `Dev Match` | HarmonyOS 实现与基线一致（自动化差分通过） |
| `Deviation` | 有意差异：必须在「差异说明」列注明理由、批准人、失效日期（计划 §16） |
| `Gap` | 无意差异 / 未实现：P0/P1 项即为缺陷，进入风险登记册 |

## 对齐表（骨架，初始全部 Not Started）

| 功能 ID | Android 行为证据 | Harmony 当前状态 | 差异说明 |
|---|---|---|---|
| FEAT-FEAS-001 | 待采集（构建脚本产物哈希） | Not Started | — |
| FEAT-FEAS-002 | 待采集（Tdlib.java Client 封装行为说明） | Not Started | — |
| FEAT-FEAS-003 | 待采集（login-flow / chat-list / send-text-message 样本） | Not Started | — |
| FEAT-FEAS-004 | 待采集（杀进程恢复观察点） | Not Started | — |
| FEAT-FEAS-005 | 待采集（连接状态日志） | Not Started | — |
| FEAT-FEAS-006 | 待采集（Push 唤醒链路记录） | Not Started | — |
| FEAT-FEAS-007 | 待采集（通话 PoC 验证记录） | Not Started | — |
| FEAT-AUTH-001 | 待采集（login-flow.md：手机号页 UI 状态） | Not Started | — |
| FEAT-AUTH-002 | 待采集（login-flow.md：验证码页与错误提示） | Not Started | — |
| FEAT-AUTH-003 | 待采集（login-flow.md：2FA 密码页） | Not Started | — |
| FEAT-AUTH-004 | 待采集（login-flow.md：注册姓名页） | Not Started | — |
| FEAT-AUTH-005 | 无 Android 对等实现（MainActivity.java:604 明确不支持）；以 TDLib 语义为准 | Not Started | 预期为有意 Deviation，实现时需记录批准 |
| FEAT-AUTH-006 | 待采集（登出流程观察点） | Not Started | — |
| FEAT-ACC-001 | 待采集（TdlibManager 多实例行为说明） | Not Started | — |
| FEAT-ACC-002 | 待采集（DrawerController 切换交互） | Not Started | — |
| FEAT-ACC-003 | 待采集（登出/添加账号入口观察点） | Not Started | — |
| FEAT-CHAT-001 | 待采集（chat-list.md：排序与分页行为） | Not Started | — |
| FEAT-CHAT-002 | 待采集（chat-list.md：置顶交互与排序） | Not Started | — |
| FEAT-CHAT-003 | 待采集（chat-list.md：归档/还原交互） | Not Started | — |
| FEAT-CHAT-004 | 待采集（chat-list.md：未读/提及徽标） | Not Started | — |
| FEAT-CHAT-005 | 待采集（草稿展示样式） | Not Started | — |
| FEAT-MSG-001 | 待采集（send-text-message.md / 消息流观察点） | Not Started | — |
| FEAT-MSG-002 | 待采集（群组/频道署名展示） | Not Started | — |
| FEAT-MSG-003 | 待采集（分页加载行为） | Not Started | — |
| FEAT-MSG-004 | 待采集（已读态流转） | Not Started | — |
| FEAT-COMP-001 | 待采集（send-text-message.md：pending→sent→failed） | Not Started | — |
| FEAT-COMP-002 | 待采集（链接预览渲染） | Not Started | — |
| FEAT-COMP-003 | 待采集（回复气泡样式） | Not Started | — |
| FEAT-COMP-004 | 待采集（转发选择器交互） | Not Started | — |
| FEAT-COMP-005 | 待采集（编辑与「已编辑」标注） | Not Started | — |
| FEAT-COMP-006 | 待采集（删除确认与即时移除） | Not Started | — |
| FEAT-COMP-007 | 待采集（复制交互） | Not Started | — |
| FEAT-MEDIA-001 | 待采集（media-basic.md：图片收发与进度） | Not Started | — |
| FEAT-MEDIA-002 | 待采集（media-basic.md：视频行为） | Not Started | — |
| FEAT-MEDIA-003 | 待采集（media-basic.md：文件行为） | Not Started | — |
| FEAT-MEDIA-004 | 待采集（语音录制/播放交互） | Not Started | — |
| FEAT-MEDIA-005 | 待采集（失败重试交互） | Not Started | — |
| FEAT-MEDIA-006 | 待采集（media-basic.md：查看器手势） | Not Started | — |
| FEAT-SEARCH-001 | 待采集（全局搜索结果分组） | Not Started | — |
| FEAT-SEARCH-002 | 待采集（聊天内搜索跳转） | Not Started | — |
| FEAT-PUSH-001 | 待采集（notification-behavior.md） | Not Started | — |
| FEAT-PUSH-002 | 待采集（notification-behavior.md：聚合与点击跳转） | Not Started | — |
| FEAT-PUSH-003 | 待采集（前后台恢复观察点） | Not Started | — |
| FEAT-SET-001 | 待采集（设置主列表结构） | Not Started | — |
| FEAT-SET-002 | 待采集（语言切换即时生效） | Not Started | — |
| FEAT-SET-003 | 待采集（通知开关生效路径） | Not Started | — |
| FEAT-SET-004 | 待采集（存储清理流程） | Not Started | — |
| FEAT-UI-001 | 待采集（深浅色关键页色值） | Not Started | — |
| FEAT-UI-002 | 待采集（大字体布局） | Not Started | — |
| FEAT-UI-003 | 待采集（中英文案抽查） | Not Started | — |

## 使用规则

1. 每个 P0/P1 工作包开工前，先把涉及行推进到 `Baseline Captured`（GOV-005 证据，对应 `docs/product/behavior-samples/` 下的样本文件）。
2. `Deviation` 必须包含：理由、批准人、失效日期（最长一个里程碑，见计划 §16）。
3. `Gap` 在 P0/P1 范围即为缺陷，进入计划 §18 风险登记册。
