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

（暂无 — Phase 0 已完成，下一批 TDN-001/002 待认领）

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
| GOV-001 空工程 | 2026-09-08 | Debug/Release 构建均 BUILD SUCCESSFUL，产出 `entry/build/default/outputs/default/entry-default-unsigned.hap`（212 KB）；commit `7fe266b` |
| GOV-002 工具链锁定 | 2026-09-08 | `tools/toolchain-versions.json` + `tools/ci/setup-check.sh` 退出码 0（SDK 26.0.0.105 / hvigor 6.26.4）；版本不匹配会明确失败 |
| GOV-003 文档控制面 | 2026-09-08 | `docs/`（ARCHITECTURE、ADR-001/002、Feature/Parity、quality 五件、runbooks 三件）+ `work-items/templates/`（§17.1/17.2 原文模板） |
| GOV-007 秘密管理 | 2026-09-08 | `.gitignore` 覆盖签名/p12/cer/local_properties/api_hash；`tools/ci/secret-scan.sh` 已接入 ci.sh（PEM 私钥、api_hash 模式阳性 fixture 验证通过）；commit `7fe266b`+`b94e5a6` |
| GOV-004 Feature/Parity Matrix | 2026-09-08 | FEATURE_MATRIX：7 项 P0 + 38 项 P1（含真实 Android 类级路径+行号、TDLib 方法）、P2/P3 一行表；PARITY_MATRIX 45 行对齐骨架；commit `b94e5a6` |
| GOV-005 Android 行为样本 | 2026-09-08 | `docs/product/behavior-samples/` 5 份（登录/会话列表/发文本/通知/媒体）+ README，全部脱敏、含 TDLib 事件与 Harmony 验收观察点；截图/录屏待真机；commit `b94e5a6` |
| GOV-006 CI 最小流水线 | 2026-09-08 | `tools/ci/ci.sh` 6 步全链路实测通过（工具链闸→secret scan→lint/typecheck→单测→debug→release 构建）；`.github/workflows/ci.yml` self-hosted 模板；commit `b94e5a6` |
| QA-001 测试骨架 | 2026-09-08 | `hvigorw test` 真实执行通过：1 用例 Success（注意：本 hvigor 6.26.4 单测须放 `entry/src/test/*.test.ets`，ohosTest 壳留作设备测试）；commit `b94e5a6` |
| SEC-001 威胁模型 v0 | 2026-09-08 | `docs/architecture/threat-model-v0.md`：数据流图+6 信任边界、9 资产、16 威胁（账号/消息/文件/Push/bridge/存储全覆盖）、7 秘密管理规则、§18 风险映射；commit `b94e5a6` |
| 结构骨架 | 2026-09-08 | core×9 / platform×14 / feature×12 / native×3 / tools×4 / test×4 目录已建（仅 .gitkeep，未注册构建，符合 ADR-002） |

已知工程要点（runbook 已记录）：hvigorw 为 shell/JS polyglot；离线构建依赖 `~/.hvigor/project_caches`；`DEVECO_SDK_HOME` 必须指向 `…/Contents/sdk`（wrapper 已内置）；签名/真机待用户提供。

## 阻塞 / 风险记录

| 日期 | 事项 | 状态 |
|---|---|---|
| 2026-09-08 | 用户输入项（api_id/api_hash、真机、AGC/Push 配置）未提供 —— 阻塞 Phase 1 真机项，不阻塞 Phase 0 工程脚手架 | ✅ 已解决：api_id/api_hash 已放入 gitignored `local.properties`（取自 Android 工程）；VYG-AL00 真机已连（API 24 / 6.1.0.135），DevEco 自动签名已接入 |
| 2026-09-08 | compatibleSdkVersion 26 与设备 API 24 不匹配 | ✅ 已修复为 `6.1.1(24)`（hvigor 映射表 6.1.1→24）；signed hap 已真机安装成功（bundle 校验通过），启动待解锁屏幕 |
