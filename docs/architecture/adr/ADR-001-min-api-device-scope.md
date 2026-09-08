# ADR-001 最低 HarmonyOS API 与设备范围

- 状态：Accepted（2026-09-08，GOV-001/GOV-003）
- 决策者：迁移项目组（Phase 0 主会话 AI，待架构负责人确认）

## Context

Telegram X 依赖 TDLib（C++）、长连接保活、推送、媒体编解码与（后续）通话能力。HarmonyOS NEXT 的系统能力与 Kit 在不同 API 级别差异显著；支持过低 API 会显著增加 polyfill 和分支成本。当前可用基线：DevEco Studio 内置 HarmonyOS SDK 26.0.0.105（API 26，platformVersion 26.0.0）。

## Decision

- **最低/编译/目标 API 全部锁定为 26**（build-profile.json5: `compileSdkVersion = compatibleSdkVersion = targetSdkVersion = "26.0.0"`，`runtimeOS = "HarmonyOS"`）。
- **设备范围：Phone / arm64-v8a 优先**；x86_64 仅用于模拟器与 CI。
- 工具链锁定见 `tools/toolchain-versions.json`，由 `tools/ci/setup-check.sh` 强制校验。

## Alternatives

1. **兼容 API 12+（HarmonyOS 5）**：覆盖更大装机量，但 Kit 能力（Push Kit 新版本、Call Service、媒体）在 26 上才完整；早期 polyfill 成本高，且 TDLib  native 适配工作量与 API 级别弱相关、与 NDK/ABI 强相关。放弃（至少 G1 之前不重新讨论）。
2. **同时支持 arm64 + x86_64 真机**：当前无 x86_64 真机生态，徒增 ABI 矩阵。放弃。
3. **平板/折叠屏首发适配**：多窗口与布局成本后置到 P2（见 DEVICE_MATRIX.md）。暂不支持。

## Consequences

- 全部 ArkTS 代码可按 API 26 能力编写，无需低版本分支。
- 发布范围 = 已升级 HarmonyOS 26 的 Phone 设备；市场范围由用户在 §21 输入确认。
- 任何提升最低 API 或新增 ABI 的变更必须修改 ADR 并更新 DEVICE_MATRIX.md。

## Validation

- `tools/ci/setup-check.sh` 退出码 0 且校验 sdk.apiVersion == 26。
- Debug/Release HAP 均可在 `assembleHap` 下构建成功（已验证，见 runbooks/build.md）。

## Rollback

改回低 API 需要：build-profile.json5 版本串回退 + 全量 Kit 能力审计 + ADR 重开。回滚成本在 Phase 2 之前可接受；G2 之后默认不可回滚，除非架构负责人批准。
