#!/usr/bin/env bash
# tools/ci/setup-check.sh — GOV-002 environment gate.
# Validates that SDK / NDK / hvigor / node on this machine match
# tools/toolchain-versions.json exactly. Any mismatch prints a clear error
# and exits non-zero. Run before any build.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
LOCK_FILE="${ROOT}/tools/toolchain-versions.json"

fail() {
  echo "[setup-check] FAIL: $*" >&2
  exit 1
}

jqr() {
  # minimal json reader via python3 (macOS-friendly, no jq dependency)
  python3 -c 'import json,sys; d=json.load(open(sys.argv[1])); p=sys.argv[2].split(".");
v=d
for k in p:
    v=v[k]
print(v)' "$1" "$2" 2>/dev/null
}

echo "[setup-check] lock file: ${LOCK_FILE}"
[[ -f "${LOCK_FILE}" ]] || fail "lock file not found"

DEVECO_PATH="$(jqr "${LOCK_FILE}" deveco.path)"
SDK_PATH="$(jqr "${LOCK_FILE}" sdk.path)"
SDK_VERSION="$(jqr "${LOCK_FILE}" sdk.version)"
SDK_API="$(jqr "${LOCK_FILE}" sdk.apiVersion)"
NDK_PATH="$(jqr "${LOCK_FILE}" ndk.path)"
HVIGOR_PATH="$(jqr "${LOCK_FILE}" hvigor.path)"
HVIGOR_VERSION="$(jqr "${LOCK_FILE}" hvigor.version)"
NODE_PATH="$(jqr "${LOCK_FILE}" node.path)"
OHPM_PATH="$(jqr "${LOCK_FILE}" ohpm.path)"

# --- DevEco Studio -----------------------------------------------------------
[[ -d "${DEVECO_PATH}" ]] || fail "DevEco Studio not found at ${DEVECO_PATH} (deveco.path)"

# --- HarmonyOS SDK -----------------------------------------------------------
SDK_PKG_JSON="${SDK_PATH}/ets/oh-uni-package.json"
[[ -f "${SDK_PKG_JSON}" ]] || fail "SDK not found at ${SDK_PATH} (sdk.path)"
ACTUAL_SDK_VERSION="$(python3 -c 'import json,sys; print(json.load(open(sys.argv[1]))["version"])' "${SDK_PKG_JSON}")"
[[ "${ACTUAL_SDK_VERSION}" == "${SDK_VERSION}" ]] \
  || fail "SDK version mismatch: expected ${SDK_VERSION}, found ${ACTUAL_SDK_VERSION} (${SDK_PKG_JSON})"
ACTUAL_SDK_API="$(python3 -c 'import json,sys; print(json.load(open(sys.argv[1]))["apiVersion"])' "${SDK_PKG_JSON}")"
[[ "${ACTUAL_SDK_API}" == "${SDK_API}" ]] \
  || fail "SDK apiVersion mismatch: expected ${SDK_API}, found ${ACTUAL_SDK_API}"

# --- NDK (bundled inside the SDK) --------------------------------------------
[[ -d "${NDK_PATH}/llvm" ]] || fail "NDK llvm toolchain not found at ${NDK_PATH}/llvm (ndk.path)"
[[ -f "${NDK_PATH}/oh-uni-package.json" ]] || fail "NDK package manifest missing under ${NDK_PATH}"

# --- hvigor ------------------------------------------------------------------
HVIGOR_PKG_JSON="${HVIGOR_PATH}/hvigor/package.json"
[[ -f "${HVIGOR_PKG_JSON}" ]] || fail "hvigor package not found at ${HVIGOR_PKG_JSON} (hvigor.path)"
ACTUAL_HVIGOR_VERSION="$(python3 -c 'import json,sys; print(json.load(open(sys.argv[1]))["version"])' "${HVIGOR_PKG_JSON}")"
[[ "${ACTUAL_HVIGOR_VERSION}" == "${HVIGOR_VERSION}" ]] \
  || fail "hvigor version mismatch: expected ${HVIGOR_VERSION}, found ${ACTUAL_HVIGOR_VERSION}"

# --- build node --------------------------------------------------------------
[[ -x "${NODE_PATH}" ]] || fail "build node not executable at ${NODE_PATH} (node.path)"
NODE_VERSION="$("${NODE_PATH}" --version)"
echo "[setup-check] build node: ${NODE_VERSION}"

# --- ohpm --------------------------------------------------------------------
[[ -x "${OHPM_PATH}" ]] || fail "ohpm not found at ${OHPM_PATH} (ohpm.path)"

echo "[setup-check] OK: SDK ${SDK_VERSION} (api ${SDK_API}), hvigor ${HVIGOR_VERSION}, node ${NODE_VERSION}"
