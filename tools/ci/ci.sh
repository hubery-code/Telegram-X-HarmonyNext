#!/usr/bin/env bash
# tools/ci/ci.sh — GOV-006 CI 最小流水线单一入口。
#
# 链路（任一环节失败立即非 0 退出）：
#   1. setup-check.sh   工具链闸（GOV-002）
#   2. secret-scan.sh   秘密扫描（GOV-007 闭环 / SEC-002）
#   3. check_design_tokens.py  设计 token 静态校验（INTEG-002）
#   4. check_architecture.py   核心层架构依赖与 Kit-free 校验（P1-QA-003）
#   5. check_codegen.py        TDLib 代码生成与敏感字段一致性校验（P1-QA-003）
#   6. check_accessibility_labels.py 图标控件无障碍标签守卫（A11Y-101）
#   7. check_i18n_literals.py  视图层+数据层写死文案（中/英）、词典键、日期与时间形态、TDLib 语言档守卫，九条规则，每次先跑负向对照自证（I18N-LITERAL-101/102/103/104, I18N-DATE-101/102, I18N-GUARDSPAN-101, I18N-SYSLANG-101）
#   8. check_appstorage_pairs.py AppStorage 键读写配对守卫（APPSTORAGE-PAIR-101）
#   9. check.sh         codelinter（若存在）+ ArkTS typecheck 构建（GOV-006）
#   10. test_all_modules.py 全模块单元测试调度与断言（P1-QA-001 / QA-002）
#   11. build.sh debug   Debug HAP（GOV-001）
#   12. build.sh release Release HAP（GOV-001）
#
# 备注（INTEG-002）：拼错的 design token（如 T.typography.caption1）编译期不报错，
# 只在渲染到该分支时抛 TypeError 并杀进程（exit 254）。第 3 步把这类缺陷前移到 CI。
#
# 备注（QA-002 / P1-QA-001）：枚举 build-profile.json5 全量 21 模块，
# 调度 19 个具备单测的模块真实执行测试，并断言 Failures == 0, Errors == 0 且用例数 >= 770。
#
# 备注（I18N-LITERAL-101）：Lang 缺译文时原样回吐 key，所以「写了 this.t('X')」并不等于
# 屏幕上有文案 —— 拼错的键会渲染成英文标识本身。第 7 步同时拦视图层写死的中文与词典缺项。
#
# 备注（APPSTORAGE-PAIR-101）：AppStorage 的键是裸字符串约定，「只有写没有读」的键既不报错
# 也不显示，只表现为「设置完重启就变回默认」——语言（LANG-PERSIST-101）与主题本包各中一次。
# 第 8 步把这类形状前移到 CI。
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

run_step "1/13 toolchain gate (GOV-002)"       "${ROOT}/tools/ci/setup-check.sh"
run_step "2/13 secret scan (GOV-007)"          "${ROOT}/tools/ci/secret-scan.sh"
run_step "3/13 design tokens (INTEG-002)"      python3 "${ROOT}/tools/ci/check_design_tokens.py"
run_step "4/13 architecture guard (QA-002)"    python3 "${ROOT}/tools/ci/check_architecture.py"
run_step "5/13 codegen verify (QA-002)"        python3 "${ROOT}/tools/ci/check_codegen.py"
run_step "6/13 a11y label guard (A11Y-101)"    python3 "${ROOT}/tools/ci/check_accessibility_labels.py"
run_step "7/13 i18n literal guard (I18N-101/102/103/104, I18N-DATE-101/102, GUARDSPAN-101, DUPKEY-101, RETSPAN-101)" python3 "${ROOT}/tools/ci/check_i18n_literals.py"
run_step "8/13 appstorage pair guard (APPSTORAGE-PAIR-101)" python3 "${ROOT}/tools/ci/check_appstorage_pairs.py"
# PATH-PORTABLE-101：守卫脚本**自身**的路径口径自检（归一化 / parts 比较 / 子进程编码）。
# 它守的不是产品代码，而是前面那几个守卫的元数据层 —— 那一层坏掉时前面几个会静默失真，
# 而「静默失真」在输出里与「代码干净」长得一模一样。
run_step "9/13 path portability guard (PATH-PORTABLE-101)" python3 "${ROOT}/tools/ci/check_path_portability.py"
run_step "10/13 lint + typecheck (GOV-006)"     "${ROOT}/tools/ci/check.sh"
run_step "11/13 unit test all modules (QA-002)" python3 "${ROOT}/tools/ci/test_all_modules.py"
run_step "12/13 build debug (GOV-001)"         "${ROOT}/tools/ci/build.sh" debug
run_step "13/13 build release (GOV-001)"       "${ROOT}/tools/ci/build.sh" release

echo ""
echo "[ci] ALL STEPS PASSED"
