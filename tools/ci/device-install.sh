#!/usr/bin/env bash
# tools/ci/device-install.sh — Install and launch HAP on connected device/emulator via CLI.
# Usage:
#   ./tools/ci/device-install.sh [target_id] [hap_path]
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
cd "${ROOT}"

# shellcheck source=/dev/null
source "${ROOT}/tools/ci/resolve-toolchain.sh"

if [[ ! -x "${HDC_PATH}" ]]; then
  echo "[device-install] ERROR: hdc tool not found or not executable at: ${HDC_PATH}" >&2
  exit 1
fi

TARGET="${1:-}"
if [[ -z "${TARGET}" ]]; then
  # Find all connected targets
  TARGETS=($("${HDC_PATH}" list targets | grep -v '\[Empty\]' || true))
  if [[ ${#TARGETS[@]} -eq 0 ]]; then
    echo "[device-install] ERROR: No device or emulator connected." >&2
    echo "  - For physical device: connect USB and enable Developer Mode + USB Debugging." >&2
    echo "  - For emulator: connect via '${HDC_PATH} tconn 127.0.0.1:5555'" >&2
    exit 1
  fi
  TARGET="${TARGETS[0]}"
  echo "[device-install] Auto-detected target: ${TARGET}"
fi

HAP_PATH="${2:-}"
if [[ -z "${HAP_PATH}" ]]; then
  SIGNED_HAP="entry/build/default/outputs/default/entry-default-signed.hap"
  UNSIGNED_HAP="entry/build/default/outputs/default/entry-default-unsigned.hap"

  if [[ "${TARGET}" == *"127.0.0.1"* ]] || [[ "${TARGET}" == *"emulator"* ]]; then
    # Emulator can use unsigned hap or signed hap
    if [[ -f "${UNSIGNED_HAP}" ]]; then
      HAP_PATH="${UNSIGNED_HAP}"
    elif [[ -f "${SIGNED_HAP}" ]]; then
      HAP_PATH="${SIGNED_HAP}"
    fi
  else
    # Physical device requires signed hap!
    if [[ -f "${SIGNED_HAP}" ]]; then
      HAP_PATH="${SIGNED_HAP}"
    elif [[ -f "${UNSIGNED_HAP}" ]]; then
      echo "[device-install] WARNING: Target is a physical device, but only unsigned HAP was found." >&2
      echo "[device-install] HarmonyOS NEXT physical devices require signed HAPs." >&2
      HAP_PATH="${UNSIGNED_HAP}"
    fi
  fi
fi

if [[ -z "${HAP_PATH}" || ! -f "${HAP_PATH}" ]]; then
  echo "[device-install] ERROR: HAP bundle not found at '${HAP_PATH:-<empty>}'." >&2
  echo "  Run './tools/ci/build.sh debug' first." >&2
  exit 1
fi

echo "[device-install] Installing '${HAP_PATH}' to target '${TARGET}'..."
"${HDC_PATH}" -t "${TARGET}" app install -r "${HAP_PATH}"

echo "[device-install] Waking up screen..."
"${HDC_PATH}" -t "${TARGET}" shell "power-shell wakeup" 2>/dev/null || true

echo "[device-install] Launching EntryAbility (org.telegram.x.harmony)..."
"${HDC_PATH}" -t "${TARGET}" shell aa start -a EntryAbility -b org.telegram.x.harmony

echo "[device-install] DONE: Application installed and launched successfully."
