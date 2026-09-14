#!/usr/bin/env bash
# tools/ci/secret-scan.sh — GOV-007 / SEC-002: Zero-leakage secret scan entry point.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
exec python3 "${ROOT}/tools/ci/secret_scan.py"
