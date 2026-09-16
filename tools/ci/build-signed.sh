#!/usr/bin/env bash
# tools/ci/build-signed.sh — Build signed HAP using local.signing.json5 without dirtying git.
# Usage:
#   ./tools/ci/build-signed.sh [debug|release]
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
cd "${ROOT}"

SIGNING_FILE="${ROOT}/local.signing.json5"
BUILD_PROFILE="${ROOT}/build-profile.json5"

if [[ ! -f "${SIGNING_FILE}" ]]; then
  echo "[build-signed] ERROR: '${SIGNING_FILE}' not found." >&2
  echo "  Please create '${SIGNING_FILE}' with your local signing configuration." >&2
  echo "  Reference template: build-profile.signing.json5.template" >&2
  exit 1
fi

MODE="${1:-debug}"

# Preserve original content to restore on exit
ORIG_PROFILE="$(cat "${BUILD_PROFILE}")"

cleanup() {
  echo "[build-signed] Restoring clean build-profile.json5..."
  echo "${ORIG_PROFILE}" > "${BUILD_PROFILE}"
}
trap cleanup EXIT INT TERM

echo "[build-signed] Injecting local signing configuration into build-profile.json5..."
python3 - << 'PYEOF'
import json, os, sys

root = os.getcwd()
profile_path = os.path.join(root, "build-profile.json5")
signing_path = os.path.join(root, "local.signing.json5")

# Strip comments if json5
with open(profile_path, "r", encoding="utf-8") as f:
    text = f.read()
    # Simple parse assuming valid JSON structure
    profile = json.loads(text)

with open(signing_path, "r", encoding="utf-8") as f:
    signing = json.loads(f.read())

profile["app"]["signingConfigs"] = signing.get("signingConfigs", [])
for p in profile["app"].get("products", []):
    p["signingConfig"] = "default"

with open(profile_path, "w", encoding="utf-8") as f:
    json.dump(profile, f, indent=2, ensure_ascii=False)
PYEOF

echo "[build-signed] Building ${MODE} HAP with signature..."
"${ROOT}/tools/ci/build.sh" "${MODE}"

echo "[build-signed] SUCCESS: Signed HAP generated at entry/build/default/outputs/default/entry-default-signed.hap"
