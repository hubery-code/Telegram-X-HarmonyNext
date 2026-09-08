#!/usr/bin/env bash
# tools/ci/check.sh — GOV-006 minimal quality gate.
# Runs the fastest available static checks. Currently:
#   1. setup-check.sh (toolchain gate, GOV-002)
#   2. codelinter if present in the SDK build-tools
#   3. an ArkTS type-check build of the entry module (assembleHap performs the
#      ArkTS compile + type check; failures exit non-zero)
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
NODE="/Applications/DevEco-Studio.app/Contents/tools/node/bin/node"
SDK_HOME="/Applications/DevEco-Studio.app/Contents/sdk/default/openharmony"

"${ROOT}/tools/ci/setup-check.sh"

CODELINTER="${SDK_HOME}/ets/build-tools/codelinter"
if [[ -x "${CODELINTER}" ]]; then
  echo "[check] running codelinter"
  "${CODELINTER}" "${ROOT}"
else
  echo "[check] codelinter not found at ${CODELINTER}; relying on ArkTS type-check build"
fi

echo "[check] ArkTS type-check via assembleHap (debug)"
cd "${ROOT}"
exec "${NODE}" "${ROOT}/hvigorw" assembleHap \
  --mode module \
  -p module=entry@default \
  -p product=default \
  -p buildMode=debug \
  --no-daemon
