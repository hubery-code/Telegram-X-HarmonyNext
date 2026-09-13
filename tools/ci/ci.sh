#!/usr/bin/env bash
# tools/ci/ci.sh — GOV-006 CI 最小流水线单一入口。
#
# 链路（任一环节失败立即非 0 退出）：
#   1. setup-check.sh   工具链闸（GOV-002）
#   2. secret-scan.sh   秘密扫描（GOV-007 闭环）
#   3. check_design_tokens.py  设计 token 静态校验（INTEG-002 事故后引入）
#   4. check.sh         codelinter（若存在）+ ArkTS typecheck 构建
#   5. unit test        hvigorw test（QA-001：本机已实测，Hypium 用例真实执行，
#                       结果见 entry/.test/default/intermediates/test/coverage_data/test_result.txt）
#   6. build.sh debug   Debug HAP
#   7. build.sh release Release HAP
#
# 备注（INTEG-002）：拼错的 design token（如 T.typography.caption1）编译期不报错，
# 只在渲染到该分支时抛 TypeError 并杀进程（exit 254）。第 3 步把这类缺陷前移到 CI。
#
# 备注（QA-001）：本 hvigor 版本（6.26.4）的本地单元测试用例约定放在
# entry/src/test/*.test.ets（不是 ohosTest 内）；`hvigorw test` 在 CLI 下即可
# 真实执行用例并生成报告，无需真机。ohosTest 模块保留为设备测试壳
# （TestAbility/OpenHarmonyTestRunner），on-device 执行待 DEVICE_MATRIX 冻结后启用。
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
cd "${ROOT}"

run_step() {
  local name="$1"; shift
  echo ""
  echo "==================== [ci] ${name} ===================="
  if "$@"; then
    echo "==================== [ci] ${name}: OK ===================="
  else
    local code=$?
    echo "==================== [ci] ${name}: FAIL (exit ${code}) ====================" >&2
    exit "${code}"
  fi
}

run_step "1/7 toolchain gate (GOV-002)"        "${ROOT}/tools/ci/setup-check.sh"
run_step "2/7 secret scan (GOV-007)"           "${ROOT}/tools/ci/secret-scan.sh"
run_step "3/7 design tokens (INTEG-002)"       python3 "${ROOT}/tools/ci/check_design_tokens.py"
run_step "4/7 lint + typecheck (GOV-006)"      "${ROOT}/tools/ci/check.sh"
run_step "5/7 unit test (QA-001)"               "${ROOT}/hvigorw" test \
  --mode module -p module=entry@default -p product=default --no-daemon
run_step "6/7 build debug (GOV-001)"           "${ROOT}/tools/ci/build.sh" debug
run_step "7/7 build release (GOV-001)"         "${ROOT}/tools/ci/build.sh" release

echo ""
echo "[ci] ALL STEPS PASSED"
