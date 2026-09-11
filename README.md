# Telegram X · HarmonyOS NEXT（社区迁移版）

将 [Telegram X](https://github.com/TGX-Android/Telegram-X) 迁移到 HarmonyOS NEXT（纯血鸿蒙）的社区开源项目。

本项目**不包含任何 Android 代码**：UI、导航、状态管理、系统能力全部基于 ArkTS / ArkUI 重写，通信协议核心复用 [TDLib](https://core.telegram.org/tdlib)（C++），两者之间通过 HarmonyOS Node-API 建立窄接口。Telegram X 的 Android 实现仅作为**行为参考、差分测试基准（oracle）与资源来源**。

> ⚠️ 本项目是社区驱动的非官方迁移，与 Telegram、Telegram X（TGX-Android）团队及华为均无隶属关系。Telegram 是 Telegram FZ-LLC 的注册商标。

## 当前进展

### ✅ 已完成（真机验证通过）

| 功能 | 一句话说明 |
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
| 工程基座 | CI 门禁、单元测试体系、深浅色设计 token、多账号底层框架、敏感信息防泄漏 |

### 🔨 进行中

| 功能 | 一句话说明 |
|---|---|
| 设置页接入 | 设置主页（账号、主题、缓存、登出）已开发完成，正在接入应用导航 |

### 📋 未开始（按优先级排序）

| 功能 | 一句话说明 |
|---|---|
| 消息转发与置顶 | 消息转发、会话置顶、链接预览卡片 |
| 媒体消息 | 图片/视频/文件消息的收发、下载进度与全屏查看 |
| 语音消息 | 按住录音、松开发送、波形播放 |
| 搜索 | 全局搜索（联系人/群组/消息）与聊天内搜索 |
| 通知推送 | Push Kit 推送、通知聚合、点击直达聊天 |
| 设置 | 设置主页、深色主题、语言切换、存储清理、登出 |
| 多账号界面 | 底层已支持多账号，缺切换/添加账号的界面 |
| Beta 功能 | 群组/频道管理、联系人、表情与 Sticker、系统分享、深色模式完善等 |
| 通话 | 语音/视频通话（远期，依赖 tgcalls 移植） |

详细工作分配与验收状态见 **[PROGRESS.md](PROGRESS.md)**；功能范围与对齐矩阵见 [docs/product/](docs/product/)。

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

# 2. 签名：用 DevEco 打开工程，File → Project Structure → Signing Configs
#    勾选 Automatically generate signature 自动生成；
#    或将自己的 p12/cer/p7b 放入 signing/ 并修改 build-profile.json5。
#    （只想编出不签名的 hap：删除 product 里的 "signingConfig": "default" 一行）

# 3. 构建（wrapper 会自动使用 DevEco 内置的 node / hvigor）
./tools/ci/build.sh debug     # 或 release
```

### 其他常用命令

```bash
./tools/ci/ci.sh          # 完整门禁：工具链校验 → 秘密扫描 → lint/类型检查 → 单元测试 → Debug/Release 构建
./tools/ci/setup-check.sh # 校验本机工具链版本与锁定清单一致
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
