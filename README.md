# Telegram X · HarmonyOS NEXT

将 [Telegram X](https://github.com/TGX-Android/Telegram-X) 迁移到 HarmonyOS NEXT（纯血鸿蒙）的社区开源项目。

本项目**不包含任何 Android 代码**：UI、导航、状态管理、系统能力全部基于 ArkTS / ArkUI 重写，通信协议核心复用 [TDLib](https://core.telegram.org/tdlib)（C++），两者之间通过 HarmonyOS Node-API 建立窄接口。Telegram X 的 Android 实现仅作为**行为参考、差分测试基准（oracle）与资源来源**。

> ⚠️ 本项目是社区驱动的非官方迁移，与 Telegram、Telegram X（TGX-Android）团队及华为均无隶属关系。Telegram 是 Telegram FZ-LLC 的注册商标。

## 当前进展

### ✅ 已完成（真机验证通过）

| 功能 | 说明 |
|---|---|
| TDLib 移植 | TDLib 1.8.67 经 HarmonyOS NDK 交叉编译跑在真机上，Node-API 桥异步事件有序不丢 |
| 扫码登录 | 用手机 Telegram 扫二维码完成授权，国内网络环境的人机验证拦截有兜底方案 |
| 登录态恢复 | 杀进程冷启动直接回到会话列表，不用重新登录 |
| 会话列表 | 真实会话数据：头像、未读角标、最后一条消息预览、分页加载、下拉刷新 |
| 聊天页 | 文本气泡（发出靠右/收到靠左）、历史消息分页、对方新消息实时到达 |
| 发送文本 | 气泡立即上屏（发送中/失败状态可见），断网时自动排队、网络恢复后自动重发 |
| 消息操作 | 长按气泡可回复（带引用条）、编辑（带"已编辑"标记）、删除（为自己/为双方） |
| 富文本渲染 | 消息里的加粗、斜体、删除线、代码（等宽字体）、链接与 @提及着色可点击、剧透点击揭开 |
| 群聊消息署名 | 群消息显示发送者彩色头像（首字母）与名字，不同成员不同颜色 |
| 消息已读回执 | 发出的消息显示已读（双勾）/未读（单勾），对方已读后实时变双勾；打开会话即上报已读；发送失败点气泡可重发 |
| 消息转发 | 长按菜单进入多选态（勾选圈、顶栏计数），选目标会话（可搜索过滤）后转发，支持 "Send as copy" 隐藏原发送者 |
| 会话置顶与标未读 | 长按会话行：置顶/取消置顶（置顶区浮顶并显示 📌）、标未读/标已读（无未读数时出圆点徽标） |
| 设置主页 | 会话列表右上角齿轮进入：账号信息展示、通知开关、主题切换入口、存储占用展示与一键清理、登出（经二次确认） |
| 全局搜索 | 会话列表搜索入口进入：All/Chats/Messages 分栏，结果按会话与消息分组（真实 TDLib 搜索），点结果直达会话，返回保留查询与结果 |
| 媒体查看与视频预览 | 头像/缩略图自动下载、视频流播放、动图贴纸展示与全屏媒体查看器（大图缩放、左右滑动切换） |
| 工程基座 | 21 个工程模块解耦；19 个模块 793 项单元测试 100% 通过；全量 CI 9 步严格门禁；纯 typed navigation 状态机接管路由；HUKS 硬件密钥数据库加密全链路与平滑迁移；工具链多级自动发现与零污染构建；零泄密安全扫描 |

### 📋 后续规划（按优先级排序）

| 功能 | 说明 |
|---|---|
| 核心媒体发送 | 图片发送（选图+进度）、文件消息发送、语音消息录制与波形播放 |
| 聊天内搜索 | 聊天详情内历史关键字搜索 + 结果跳转定位到原消息（全局搜索已完成） |
| 链接预览 | 消息内 URL 气泡渲染 linkPreview 卡片（MSG-107） |
| 多账号界面 | 底层已支持多账号与数据隔离，缺抽屉切换/添加账号的 UI |
| 设置与本地化完善 | 深色主题全局适配、中英文文案资源补全与切换 |
| Push 通知 (Blocked) | Telegram 后端暂无华为 Push Kit 原生支持（见 ADR-003），MVP-Core 采用受控前台长连接通信 |
| 通话 (Deferred) | 语音/视频通话（见 ADR-004，Post-MVP / G4 独立攻关） |

开发 AI 应先阅读 **[计划与架构审计入口](docs/plans/README.md)**。详细工作分配与验收状态见 **[PROGRESS.md](PROGRESS.md)**；功能范围与对齐矩阵见 [docs/product/](docs/product/)。

## 架构速览

```
ArkUI 页面 → Feature ViewModel → UseCase → Repository Port
     ↑                                        ↓
Ordered Event Router ← TdGateway ← 生成的 TDLib DTO/Codec
                                              ↓
                                    Node-API 桥 (libtdcore_napi.so)
                                              ↓
                              TDLib C++ 核心 (libtdjson.so) → Telegram 网络
```

- 依赖只允许从上向下；系统能力（Push、媒体、相机、存储等）一律经 Platform Port / Adapter 接入
- TDLib 是消息数据的唯一权威来源，不建第二套消息数据库
- 目录结构：`core/`（领域、gateway、生成的 TDLib 类型）、`platform/`（系统能力适配）、`feature/`（业务功能）、`native/`（TDLib/桥接/媒体原生库）、`entry/`（装配与 UI）

## 构建

### 前置要求

- macOS 或 Linux
- [DevEco Studio](https://developer.harmonyos.com/)（内置 HarmonyOS SDK，API 26 工具链；工程 `compatibleSdkVersion` 为 `6.1.1(24)`，兼容 API 24+ 真机）
- 约 1GB 磁盘（含预编译 TDLib 依赖源码）

### 步骤

```bash
# 1. Telegram API 凭据（去 https://core.telegram.org/api/obtaining_api_id 申请），
#    写入仓库根目录的 local.properties（已被 .gitignore 忽略）：
echo "telegram.api_id=你的ID" >> local.properties
echo "telegram.api_hash=你的HASH" >> local.properties

# 2. 构建与部署（纯命令行无头闭环，无需打开 IDE 界面）
# 详见 runbook: docs/runbooks/build.md §7

# 方案 A：针对物理真机（带签名编译 + 自动推包装机 + 唤醒拉起）
./tools/ci/build-signed.sh debug   # 自动读取 local.signing.json5 出 signed.hap
./tools/ci/device-install.sh        # 自动探测真机、安装、唤醒并启动 EntryAbility

# 方案 B：针对模拟器（免签名）
./tools/ci/build.sh debug          # 产出 entry-default-unsigned.hap
./tools/ci/device-install.sh        # 自动探测模拟器并安装拉起
```

### 其他常用命令

```bash
./tools/ci/ci.sh          # 完整门禁：工具链校验 → 秘密扫描 → lint/类型检查 → 单元测试 → Debug/Release 构建
./tools/ci/setup-check.sh # 校验本机工具链版本与锁定清单一致
./tools/ci/device-install.sh # 一键推包到设备并拉起 Ability
```

## 参与贡献

这是一个大工程，**非常欢迎社区加入**，无论是代码、文档、测试还是真机验证。

- **认领任务**：所有工作以「工作包」为单位登记在 [PROGRESS.md](PROGRESS.md)（多 AI / 多人协作的协调看板）。开工前先看 Backlog 和认领规则，一个工作包一个负责人
- **工作包模板**：[work-items/templates/](work-items/templates/) 里有目标、验收标准、测试要求的标准格式；完成后按模板提交实现报告
- **架构与契约**：动手前请先读 [docs/architecture/ARCHITECTURE.md](docs/architecture/ARCHITECTURE.md) 和 [docs/architecture/adr/](docs/architecture/adr/)，跨模块接口变更需要先过契约
- **行为参考**：Android 侧对照实现位于 [TGX-Android/Telegram-X](https://github.com/TGX-Android/Telegram-X)，本仓库 [docs/product/](docs/product/) 有脱敏行为样本与 Feature/Parity 矩阵
- **安全红线**：不要把 api_hash、验证码、手机号、token、聊天内容或任何签名材料提交进仓库（CI 有秘密扫描会拦）；日志按字段白名单输出
- **真机验证分工**：涉及复杂真机交互的验证（点按/滑屏/断网/杀进程等操作链）优先由人来做，AI 负责构建安装并给出可勾选的验证清单（步骤 + 预期现象），不做长时间的手机代操作——详见 PROGRESS.md 顶部约定

建议的切入方向（由小到大）：单元测试与 fixture 回放 → 平台 adapter（存储/通知）→ 消息流功能切片 → TDLib 工具链。

## 许可证

- 本项目代码以 [GNU GPL v3](LICENSE) 发布（与上游 Telegram X 一致，衍生作品要求保持同许可）
- TDLib 以 [Boost Software License 1.0](https://github.com/tdlib/td/blob/master/LICENSE_1_0.txt) 发布
- OpenSSL 以 [Apache License 2.0](https://www.openssl.org/source/license.html) 发布
- `native/tdcore/third_party/` 内的上游源码各自遵循其原始许可证
