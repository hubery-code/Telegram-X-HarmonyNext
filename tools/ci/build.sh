#!/usr/bin/env bash
# tools/ci/build.sh — GOV-002/GOV-006 build entry point.
# Usage: ./tools/ci/build.sh [debug|release]   (default: debug)
# Builds the entry HAP with the DevEco-bundled node + project hvigorw wrapper.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
MODE="${1:-debug}"

case "${MODE}" in
  debug|release) ;;
  *) echo "usage: $0 [debug|release]" >&2; exit 2 ;;
esac

NODE="/Applications/DevEco-Studio.app/Contents/tools/node/bin/node"

echo "[build] mode=${MODE} root=${ROOT}"
cd "${ROOT}"

# hvigorw sets DEVECO_SDK_HOME itself; run the environment gate first.
"${ROOT}/tools/ci/setup-check.sh"
"${ROOT}/tools/ci/inject-credentials.sh"

# shellcheck disable=SC2086
exec "${NODE}" "${ROOT}/hvigorw" assembleHap \
  --mode module \
  -p module=entry@default \
  -p product=default \
  -p buildMode=${MODE} \
  --no-daemon
