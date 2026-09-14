#!/usr/bin/env bash
# tools/ci/resolve-toolchain.sh — GOV-002 / BUILD-001 Shell adapter for toolchain discovery.
#
# Usage:
#   source tools/ci/resolve-toolchain.sh   # exports DEVECO_HOME, NODE_PATH, SDK_PATH, etc.
#   ./tools/ci/resolve-toolchain.sh check  # runs full verification check
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"

if [[ "${1:-}" == "check" ]]; then
  python3 "${ROOT}/tools/ci/resolve_toolchain.py" --check
  exit $?
fi

# Export variables into calling shell
eval "$(python3 "${ROOT}/tools/ci/resolve_toolchain.py" --shell)"
