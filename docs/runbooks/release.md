# Runbook：发布（Release）

> Phase 0 状态：仅构建流程可用；签名/上架依赖用户输入（§21）后冻结。

## 1. 发布构建

```bash
./tools/ci/setup-check.sh       # 工具链闸
./tools/ci/build.sh release     # 产物：entry/build/default/outputs/default/entry-default-unsigned.hap
```

## 2. 签名（待配置）

1. 通过安全渠道获取发布签名材料（`.p12` / `.cer` / `.p7b` 或 HarmonyOS 新版签名材料）。
   **材料绝不入库**（`.gitignore` 已排除 `*.p12`/`*.cer`/`*.csr`/`*.p7b` 与 `.signing-config`）。
2. 在根 `build-profile.json5` 的 `app.signingConfigs` 增加配置（材料用本机绝对路径或环境变量），
   并在 product `default` 上指定 `"signingConfig": "<name>"`。
3. 重新执行 release 构建，产出 `entry-default-signed.hap`。

> 注意：本地 `local.properties` 也不入库；CI 通过环境注入。

## 3. 上架检查清单（G7/G8 前逐步补全）

- [ ] 版本号策略：AppScope/app.json5 `versionCode`/`versionName` 递增规则确定。
- [ ] 混淆：entry `obfuscation-rules.txt` 启用并通过回归。
- [ ] symbols / source maps / SBOM / NOTICE 可追溯（计划 §24-6）。
- [ ] 高危漏洞扫描通过；威胁模型与数据流图更新到当前版本。
- [ ] 设备矩阵（DEVICE_MATRIX.md）全档位回归通过。
- [ ] 升级/回滚演练通过。

## 4. 回滚

- 应用侧回滚 = 商店发布上一版本；数据侧回滚依赖 TDLib 数据库前向兼容（G4 数据迁移演练覆盖）。
- 任何发布必须能从干净环境复现构建（runbooks/build.md §0–§1）。
