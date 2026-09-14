#!/usr/bin/env bash
# tools/ci/inject-credentials.sh — SEC-002: Credentials injection wrapper.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
exec python3 "${ROOT}/tools/ci/inject_credentials.py"
