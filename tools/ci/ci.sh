#!/usr/bin/env bash
# tools/ci/ci.sh — GOV-006 CI 最小流水线单一入口。
#
# 链路（任一环节失败立即非 0 退出）：
#   1. setup-check.sh   工具链闸（GOV-002）
#   2. secret-scan.sh   秘密扫描（GOV-007 闭环 / SEC-002）
#   3. check_design_tokens.py  设计 token 静态校验（INTEG-002）
#   4. check_architecture.py   核心层架构依赖与 Kit-free 校验（P1-QA-003）
#   5. check_codegen.py        TDLib 代码生成与敏感字段一致性校验（P1-QA-003）
#   6. check.sh         codelinter（若存在）+ ArkTS typecheck 构建（GOV-006）
#   7. test_all_modules.py 全模块单元测试调度与断言（P1-QA-001 / QA-002）
#   8. build.sh debug   Debug HAP（GOV-001）
#   9. build.sh release Release HAP（GOV-001）
#
# 备注（INTEG-002）：拼错的 design token（如 T.typography.caption1）编译期不报错，
# 只在渲染到该分支时抛 TypeError 并杀进程（exit 254）。第 3 步把这类缺陷前移到 CI。
#
# 备注（QA-002 / P1-QA-001）：枚举 build-profile.json5 全量 21 模块，
# 调度 19 个具备单测的模块真实执行测试，并断言 Failures == 0, Errors == 0 且用例数 >= 770。
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

run_step "1/9 toolchain gate (GOV-002)"        "${ROOT}/tools/ci/setup-check.sh"
run_step "2/9 secret scan (GOV-007)"           "${ROOT}/tools/ci/secret-scan.sh"
run_step "3/9 design tokens (INTEG-002)"       python3 "${ROOT}/tools/ci/check_design_tokens.py"
run_step "4/9 architecture guard (QA-002)"     python3 "${ROOT}/tools/ci/check_architecture.py"
run_step "5/9 codegen verify (QA-002)"         python3 "${ROOT}/tools/ci/check_codegen.py"
run_step "6/9 lint + typecheck (GOV-006)"      "${ROOT}/tools/ci/check.sh"
run_step "7/9 unit test all modules (QA-002)"  python3 "${ROOT}/tools/ci/test_all_modules.py"
run_step "8/9 build debug (GOV-001)"           "${ROOT}/tools/ci/build.sh" debug
run_step "9/9 build release (GOV-001)"         "${ROOT}/tools/ci/build.sh" release

echo ""
echo "[ci] ALL STEPS PASSED"
