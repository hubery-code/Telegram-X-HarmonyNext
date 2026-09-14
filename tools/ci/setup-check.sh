#!/usr/bin/env bash
# tools/ci/setup-check.sh — GOV-002 environment gate.
# Validates that SDK / NDK / hvigor / node on this machine match
# tools/toolchain-versions.json exactly. Supports environment overrides
# (DEVECO_HOME, DEVECO_SDK_HOME, etc.) and auto-discovery. Any mismatch prints a clear error
# and exits non-zero. Run before any build.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/../.." && pwd)"

exec "${ROOT}/tools/ci/resolve-toolchain.sh" check

