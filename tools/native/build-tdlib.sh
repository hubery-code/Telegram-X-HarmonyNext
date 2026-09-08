#!/usr/bin/env bash
# TDN-001/002 - Cross-compile TDLib (libtdjson) for HarmonyOS NEXT arm64-v8a.
#
# Prerequisites:
#   1. TDLib generated sources present in native/tdcore/third_party/td/td/generate/auto
#      (host build, see below).
#   2. tools/native/build-tdlib-deps.sh has produced OpenSSL in
#      native/tdcore/build/deps/openssl/arm64-v8a.
#
# Host source generation (one-time, after a fresh third_party/td checkout):
#   mkdir -p native/tdcore/build/host-generate && cd native/tdcore/build/host-generate
#   cmake -DCMAKE_BUILD_TYPE=Release -GNinja -DTD_GENERATE_SOURCE_FILES=ON ../../third_party/td
#   cmake --build .
#
# Usage: tools/native/build-tdlib.sh [--clean]
#
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
TDCORE="$ROOT/native/tdcore"
SRC="$TDCORE/third_party/td"
BUILD_DIR="$TDCORE/build/arm64-v8a"
DEPS_PREFIX="$TDCORE/build/deps/openssl/arm64-v8a"
OHOS_NDK="${TDX_OHOS_NDK:-/Applications/DevEco-Studio.app/Contents/sdk/default/openharmony/native}"
ABI="arm64-v8a"

log() { echo "== [build-tdlib] $*"; }

[ -f "$SRC/CMakeLists.txt" ] || { echo "TDLib source missing at $SRC"; exit 1; }
[ -f "$SRC/td/generate/auto/td/telegram/td_api.h" ] || {
  echo "TDLib generated sources missing (td/generate/auto). Run the host generation step first (see header of this script)."; exit 1; }
[ -f "$DEPS_PREFIX/lib/libcrypto.so" ] || {
  echo "OpenSSL for OHOS missing at $DEPS_PREFIX. Run tools/native/build-tdlib-deps.sh first."; exit 1; }

if [[ "${1:-}" == "--clean" ]]; then
  log "removing $BUILD_DIR"
  rm -rf "$BUILD_DIR"
fi
mkdir -p "$BUILD_DIR"

log "cmake: $(cmake --version | head -1)"
log "ninja: $(ninja --version 2>/dev/null || echo 'not found - using default generator')"
log "TDLib version: $(grep -m1 'project(TDLib VERSION' "$SRC/CMakeLists.txt" | sed 's/.*VERSION \([0-9.]*\).*/\1/')"

GENERATOR=()
if command -v ninja >/dev/null 2>&1; then GENERATOR=(-GNinja); fi

log "configuring ($ABI) ..."
# ZLIB paths are passed explicitly: CMake knows no Platform/OHOS module, so
# find_path() has no default /usr/include search path even with a sysroot.
ZLIB_INCLUDE_DIR="$OHOS_NDK/sysroot/usr/include"
ZLIB_LIBRARY="$OHOS_NDK/sysroot/usr/lib/aarch64-linux-ohos/libz.so"
[ -f "$ZLIB_INCLUDE_DIR/zlib.h" ] || { echo "NDK zlib missing at $ZLIB_INCLUDE_DIR"; exit 1; }
[ -f "$ZLIB_LIBRARY" ] || { echo "NDK libz missing at $ZLIB_LIBRARY"; exit 1; }
cmake -S "$SRC" -B "$BUILD_DIR" "${GENERATOR[@]}" \
  -DCMAKE_TOOLCHAIN_FILE="$TDCORE/cmake/ohos-toolchain.cmake" \
  -DOHOS_NDK_PATH="$OHOS_NDK" \
  -DTDX_DEPS_PREFIX="$DEPS_PREFIX" \
  -DCMAKE_BUILD_TYPE=RelWithDebInfo \
  -DTD_ENABLE_LTO=OFF \
  -DOPENSSL_ROOT_DIR="$DEPS_PREFIX" \
  -DZLIB_INCLUDE_DIR="$ZLIB_INCLUDE_DIR" \
  -DZLIB_LIBRARY="$ZLIB_LIBRARY" \
  -DTD_ENABLE_JNI=OFF

log "building target tdjson ..."
cmake --build "$BUILD_DIR" --target tdjson --parallel "$(sysctl -n hw.ncpu)"

log "artifacts:"
ls -l "$BUILD_DIR"/td/libtdjson.so* 2>/dev/null || find "$BUILD_DIR" -name "libtdjson.so*" -exec ls -l {} \;
