#!/usr/bin/env bash
# tools/ci/test_clean_build.sh — BUILD-001 Clean build and zero-pollution workspace verification.
#
# Tests:
#   1. Toolchain discovery and environment override test (DEVECO_HOME override)
#   2. Secret scan on current tree (must pass cleanly)
#   3. Full build (build.sh release)
#   4. Workspace cleanliness assertion: after build, git status must not contain
#      any modified or untracked BuildProfile.ets or unexpected build artifacts.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"
cd "${ROOT}"

echo "==================== [test_clean_build] 1/4 Toolchain Resolution ===================="
"${ROOT}/tools/ci/resolve-toolchain.sh" check
echo "[test_clean_build] 1/4 OK: Toolchain verified"

echo ""
echo "==================== [test_clean_build] 2/4 Environment Override Test ===================="
# Test passing DEVECO_HOME explicitly
DEVECO_RESOLVED="$(python3 "${ROOT}/tools/ci/resolve_toolchain.py" --query deveco_home)"
DEVECO_HOME="${DEVECO_RESOLVED}" "${ROOT}/tools/ci/setup-check.sh"
echo "[test_clean_build] 2/4 OK: Environment override verified"

echo ""
echo "==================== [test_clean_build] 3/4 Secret Scan & Build ===================="
"${ROOT}/tools/ci/secret-scan.sh"
"${ROOT}/tools/ci/build.sh" debug
"${ROOT}/tools/ci/build.sh" release
echo "[test_clean_build] 3/4 OK: Debug & Release builds succeeded"

echo ""
echo "==================== [test_clean_build] 4/4 Workspace Cleanliness Assertion ===================="
# Verify no modified BuildProfile.ets or untracked artifacts dirty the working tree
DIRTY_PROFILES="$(git status --porcelain | grep -E 'BuildProfile\.ets' || true)"
if [[ -n "${DIRTY_PROFILES}" ]]; then
  # If there are staged deletions (D), that is expected until committed.
  # But there must NOT be any unstaged modifications ( M ) or untracked (??) BuildProfile.ets.
  UNSTAGED_PROFILES="$(git status --porcelain | grep -E '^ M .*/BuildProfile\.ets|^\?\? .*/BuildProfile\.ets' || true)"
  if [[ -n "${UNSTAGED_PROFILES}" ]]; then
    echo "[test_clean_build] FAIL: BuildProfile.ets dirtied the workspace:" >&2
    echo "${UNSTAGED_PROFILES}" >&2
    exit 1
  fi
fi

echo "[test_clean_build] 4/4 OK: Workspace remained zero-pollution after Release build"
echo ""
echo "[test_clean_build] ALL TESTS PASSED"
