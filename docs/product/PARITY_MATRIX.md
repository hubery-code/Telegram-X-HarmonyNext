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
| `Dev Match` | HarmonyOS 实现与基线一致（自动化差分与真机用例通过） |
| `Deviation` | 有意差异：必须在「差异说明」列注明理由、批准人、失效日期（计划 §16） |
| `Gap` | 无意差异 / 未实现：P0/P1 项即为缺陷，进入风险登记册 |

## 对齐表

| 功能 ID | Android 行为证据 | Harmony 当前状态 | 差异说明 |
|---|---|---|---|
| FEAT-FEAS-001 | TDLib CMake/Ninja 构建产物哈希 | Dev Match | HarmonyOS NDK clang Release arm64 构建复现通过 |
| FEAT-FEAS-002 | `Tdlib.java` Client 封装 | Dev Match | C++ Node-API bridge，快照派发、延迟退订与会话隔离 |
| FEAT-FEAS-003 | 垂直链路真机样本 | Dev Match | 真实机型 Huawei VYG-AL00 全链路验证通过 |
| FEAT-FEAS-004 | 数据库加密与异常退出恢复 | Dev Match | HUKS AES-256-GCM 硬件密钥存储与 Base64 迁移 |
| FEAT-FEAS-005 | 连接状态与重连日志 | Dev Match | 网络状态监听器与网络类型实时映射 |
| FEAT-FEAS-006 | Push 唤醒链路记录 | Gap | 状态为 Blocked（ADR-003，无官方华为推送通道，MVP-Core 仅前台保活） |
| FEAT-FEAS-007 | 通话 PoC 记录 | Gap | 状态为 Deferred（ADR-004，音视频后置至 Post-MVP / G4） |
| FEAT-AUTH-001 | `login-flow.md` 手机号输入 | Dev Match | AuthCoordinator 手机号与国家码输入交互对齐 |
| FEAT-AUTH-002 | `login-flow.md` 验证码校验 | Dev Match | 验证码输入、错误重试与超时提示 |
| FEAT-AUTH-003 | `login-flow.md` 2FA 密码 | Dev Match | 2FA 密码页与本地提示校验对齐 |
| FEAT-AUTH-004 | `login-flow.md` 注册姓名 | Dev Match | 新用户设置姓名并进入 Ready |
| FEAT-AUTH-005 | Android TGX 明确不支持扫码 | Deviation | 有意差异：HarmonyOS 侧新增扫码登录，经架构确认批准 |
| FEAT-AUTH-006 | 登出流程 | Dev Match | 登出后重置清栈（replaceRoot），回到登录页 |
| FEAT-ACC-001 | `TdlibManager` 多实例行为 | Dev Match | AccountRegistry 与 AccountScope 严格目录与密钥隔离 |
| FEAT-ACC-002 | `DrawerController` 账号切换 | Dev Match | 设置页弹层 AccountSwitcherDialog 快速切换账号与添加账号闭环 |
| FEAT-ACC-003 | 登出当前账号 | Dev Match | SettingsCoordinator 登出触发会话销毁 |
| FEAT-CHAT-001 | 会话列表分页加载与排序 | Dev Match | ChatListProjection 本地缓存加载与置顶重排对齐 |
| FEAT-CHAT-002 | 置顶/取消置顶 | Dev Match | 长按菜单 Pin/Unpin，时间戳左侧 📌 标记对齐 |
| FEAT-CHAT-003 | 归档/还原交互 | Not Started | 归档区待后续工作包接入 |
| FEAT-CHAT-004 | 未读数与手动标未读 | Dev Match | 长按标未读，未读数与蓝色圆点展示对齐 |
| FEAT-CHAT-005 | 草稿展示样式 | Dev Match | 输入栏草稿退出自动保存至 TDLib，列表项红色 Draft: 前缀与重进恢复 |
| FEAT-MSG-001 | 私聊消息流展示 | Dev Match | 气泡、时间戳、发送态（pending/sent/read）对齐 |
| FEAT-MSG-002 | 群组/频道署名与头像 | Dev Match | 群聊用户署名解析与彩底头像对齐 |
| FEAT-MSG-003 | 历史分页向上滚动 | Dev Match | MessageProjection 自动拉取更早历史无空洞 |
| FEAT-MSG-004 | 已读上报与回执 | Dev Match | 入屏触发 viewMessages，双勾已读态对齐 |
| FEAT-COMP-001 | 文本消息发送 | Dev Match | 发送即上屏、失败重试、发送成功确认 |
| FEAT-COMP-002 | 链接预览 | Dev Match | 发送带 linkPreviewOptions，气泡渲染 Telegram X 风格带蓝竖条链接预览卡片，缩略图自动下载与点击访问（MSG-107） |
| FEAT-COMP-003 | 回复消息 | Dev Match | 引用条展示原文摘要，气泡内嵌回复对齐 |
| FEAT-COMP-004 | 转发消息 | Dev Match | 装配层 ForwardPickerPage 目标选择器与原作者保留对齐 |
| FEAT-COMP-005 | 编辑消息 | Dev Match | 文本消息就地编辑与「已编辑」标注对齐 |
| FEAT-COMP-006 | 删除消息 | Dev Match | 支持双方删除与单方删除，列表即时移除 |
| FEAT-COMP-007 | 复制消息文本 | Dev Match | 剪贴板 Port 抽象与系统 pasteboard 写入对齐 |
| FEAT-MEDIA-001 | 图片发送 | Dev Match | 相册选图发送带进度圈，沙箱零拷贝物理转换，真机实测验证通过 |
| FEAT-MEDIA-002 | 视频消息 | Dev Match | 缩略图与本地视频查看已具备，上传待接入 |
| FEAT-MEDIA-003 | 文件消息 | Dev Match | 系统文档选择器选取发送/下载，进度环与一键撤回，真机实测验证通过 |
| FEAT-MEDIA-004 | 语音消息 | Not Started | 待 MEDIA-106 工作包接入 |
| FEAT-MEDIA-005 | 失败重试/取消 | Dev Match | 下载/上传传输中取消、发送失败重试与长按菜单 Resend/Delete 完整闭环（FILE-103） |
| FEAT-MEDIA-006 | 媒体查看器 | Dev Match | 支持全屏展示与滑动翻页 |
| FEAT-SEARCH-001 | 全局搜索 | Dev Match | 联系人与消息分组，点击跳入聊天，返回栈保活对齐 |
| FEAT-SEARCH-002 | 聊天内搜索 | Not Started | 待 SEARCH-102 工作包接入 |
| FEAT-PUSH-001 | Push token 注册 | Gap | 状态为 Blocked（ADR-003） |
| FEAT-PUSH-002 | 通知聚合 | Gap | 状态为 Blocked（ADR-003） |
| FEAT-PUSH-003 | 连接恢复 | Dev Match | 前后台切换与网络变化自动同步 |
| FEAT-SET-001 | 设置主列表 | Dev Match | 个人信息与常用设置项展示对齐 |
| FEAT-SET-002 | 语言切换 | Not Started | 待 SET-002 工作包接入 |
| FEAT-SET-003 | 通知设置 | Not Started | 待 SET-003 工作包接入 |
| FEAT-SET-004 | 存储管理 | Not Started | 待 SET-004 工作包接入 |
| FEAT-UI-001 | 深浅色主题 | Dev Match | LightTheme 设计令牌规范对齐 |
| FEAT-UI-002 | 大字体缩放 | Not Started | 待 UI-002 工作包接入 |
| FEAT-UI-003 | 多语言资源 | Not Started | 待 UI-003 工作包接入 |
