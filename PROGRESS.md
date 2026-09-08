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

| 工作包 | 负责人(AI) | 开始时间 | 说明 |
|---|---|---|---|
| GOV-001/GOV-002/GOV-003/GOV-007 | 本 AI（主会话） | 2026-09-08 | 空 HAP 脚手架 + 工具链锁定 + 文档控制面 + 秘密管理；完成后转入验证 |

## 待认领（Backlog，按计划的 Phase 0 顺序）

| 工作包 | 依赖 | 一句话 |
|---|---|---|
| GOV-004 | 无 | 建立 Feature/Parity Matrix（P0/P1/P2/P3 功能表，含 Android 参考） |
| GOV-005 | GOV-004 | 采集 Android 核心行为脱敏样本（截图/录屏/事件说明） |
| GOV-006 | GOV-001/002 | CI 最小流水线（lint/typecheck/unit/build wrapper） |
| QA-001 | GOV-001 | Test Kit/Hypium 骨架 + 本地 ohosTest 可跑 |
| SEC-001 | GOV-004 | 威胁模型 v0 |

> 认领规则：一次只认领一个工作包；认领时把行移到「进行中」并注明你的身份和计划开始的内容。禁止修改未授权目录。

## 已完成（Accepted 或有保留）

（暂无）

## 阻塞 / 风险记录

| 日期 | 事项 | 状态 |
|---|---|---|
| 2026-09-08 | 用户输入项（api_id/api_hash、真机、AGC/Push 配置）未提供 —— 阻塞 Phase 1 真机项，不阻塞 Phase 0 工程脚手架 | 记录 |
