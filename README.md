# Telegram X → HarmonyOS NEXT（Phase 0 工程脚手架）

本仓库是 Telegram X 迁移到 HarmonyOS NEXT（API 26）的 HarmonyOS 工程根。
Android 参考实现不在本仓库：`/Users/mbjpeng-yu01/androidProjects/Telegram-X`。

> **先读 [`PROGRESS.md`](PROGRESS.md)** —— 多 AI 协作的单一协调入口
> （工作包认领、状态机、环境基线、阻塞记录）。
> 规则来源：`~/Downloads/Telegram-X-HarmonyOS-NEXT-迁移实施计划.md`。

## 快速开始

```bash
./tools/ci/setup-check.sh     # 工具链闸（GOV-002，不匹配则非 0 退出）
./tools/ci/build.sh debug     # Debug HAP → entry/build/default/outputs/default/entry-default-unsigned.hap
./tools/ci/build.sh release   # Release HAP
node hvigorw --version        # hvigor 6.26.4
```

## 目录速览

| 目录 | 用途 |
|---|---|
| `AppScope/` `entry/` | 可构建最小集：单 Entry HAP（空壳页）+ 本地测试骨架 |
| `core/*` `platform/*` `feature/*` `native/*` | Phase 1+ 模块骨架（**未注册进构建**，见 ADR-002） |
| `docs/` | 控制文档面（GOV-003）：架构、ADR、产品矩阵、质量预算、runbooks |
| `tools/` | 工具链锁定（`toolchain-versions.json`）+ CI 脚本（`tools/ci/`） |
| `test/` | 测试支撑/fixture/契约/E2E 骨架 |
| `work-items/` | 工作包 backlog/active/accepted + 模板（§17.1/17.2） |

## 关键文档

- `docs/architecture/ARCHITECTURE.md` — 分层与模块依赖规则（6+1 条）
- `docs/architecture/adr/ADR-001-min-api-device-scope.md` — API 26 / Phone / arm64
- `docs/architecture/adr/ADR-002-single-hap-har-modularity.md` — 单 HAP + HAR 策略
- `docs/product/FEATURE_MATRIX.md` `PARITY_MATRIX.md` — 功能与对等矩阵
- `docs/quality/` — Gates、测试矩阵、性能预算、安全基线、设备矩阵
- `docs/runbooks/` — 构建 / 测试 / 发布 本机实测命令

## 秘密管理（GOV-007）

签名材料、`local.properties`、任何含 `api_hash` 的文件均被 `.gitignore` 排除，永不入库。
当前构建不需要任何秘密（产物为 unsigned hap；release 签名流程见 `docs/runbooks/release.md`）。
