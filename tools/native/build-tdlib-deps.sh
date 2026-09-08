#!/usr/bin/env bash
# TDN-001/002 - Build TDLib's third-party native dependencies for HarmonyOS NEXT.
#
# Dependency matrix conclusion (see native/tdcore/README.md for details):
#   * OpenSSL  -> REQUIRED by TDLib (td/CMakeLists.txt stops the build when it
#                 is missing; tdmtproto links ${OPENSSL_CRYPTO_LIBRARY}).
#                 TDLib only needs libcrypto. Built here from the upstream
#                 openssl/openssl source pinned at the exact commit the
#                 Android reference build uses (see third_party/version pins).
#   * zlib     -> required by TDLib (ZLIB), but provided by the OHOS NDK
#                 sysroot (usr/include/zlib.h + usr/lib/<triple>/libz.so,
#                 zlib 1.3.1), i.e. part of the locked NDK. NOT built here.
#   * SQLite   -> TDLib bundles its own amalgamation (td/sqlite/sqlite/sqlite3.c,
#                 SQLite 3.31.0) and builds it via add_subdirectory(sqlite).
#                 NOT built standalone here.
#
# Usage: tools/native/build-tdlib-deps.sh [--skip-openssl]
#
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
TDCORE="$ROOT/native/tdcore"
DEPS_PREFIX="$TDCORE/build/deps"
OPENSSL_COMMIT="f4dc4d58b48d346a8270183f89acf826d459b0ca"  # openssl/openssl, version 3.5.8
OPENSSL_SRC="$TDCORE/third_party/openssl"
OHOS_NDK="${TDX_OHOS_NDK:-/Applications/DevEco-Studio.app/Contents/sdk/default/openharmony/native}"
TRIPLE="aarch64-linux-ohos"
ABI="arm64-v8a"

log() { echo "== [build-tdlib-deps] $*"; }

# --- Sanity checks -----------------------------------------------------------
[ -f "$OPENSSL_SRC/Configure" ] || { echo "OpenSSL source missing at $OPENSSL_SRC"; exit 1; }
[ -x "$OHOS_NDK/llvm/bin/clang" ] || { echo "OHOS clang missing at $OHOS_NDK/llvm/bin/clang"; exit 1; }

log "NDK clang: $("$OHOS_NDK/llvm/bin/clang" --version | head -1)"
log "zlib (NDK sysroot): $(grep '#define ZLIB_VERSION' "$OHOS_NDK/sysroot/usr/include/zlib.h" | awk '{print $3}') - using NDK copy, skip build"
log "sqlite (bundled in TD source): $(grep '#define SQLITE_VERSION ' "$TDCORE/third_party/td/sqlite/sqlite/sqlite3.h" | awk '{print $3}') - built by TDLib CMake, skip standalone build"

# --- OpenSSL -----------------------------------------------------------------
if [[ "${1:-}" == "--skip-openssl" && -f "$DEPS_PREFIX/openssl/$ABI/lib/libcrypto.so" ]]; then
  log "OpenSSL already built, skipping (--skip-openssl)"
else
  log "Building OpenSSL $OPENSSL_COMMIT for $TRIPLE ..."
  BUILD_DIR="$TDCORE/build/openssl-$ABI"
  INSTALL_DIR="$DEPS_PREFIX/openssl/$ABI"
  rm -rf "$BUILD_DIR" "$INSTALL_DIR"
  mkdir -p "$BUILD_DIR" "$INSTALL_DIR"

  # Same minimized feature set as the Android reference build
  # (tdlib/source/build-openssl.sh) - proven sufficient for TDLib's crypto use
  # (AES-IGE, SHA-1/2, RSA, DH/BN, HMAC, RAND). no-async avoids ucontext
  # dependence on musl. Plain sonames: HarmonyOS has no system libcrypto.so
  # conflict (system crypto is libohcrypto.so).
  PARAMS="no-tests no-docs no-apps no-legacy no-engine \
    no-ssl3 no-ssl3-method \
    no-ml-kem no-ml-dsa no-slh-dsa \
    no-sm2 no-sm3 no-sm4 \
    no-camellia no-aria no-cast no-idea \
    no-mdc2 no-md4 no-rc2 no-rc5 no-seed \
    no-whirlpool no-siphash \
    no-ocb no-siv \
    no-srp no-psk \
    no-cms no-ts \
    no-comp no-nextprotoneg \
    no-async no-uplink \
    no-autoerrinit no-autoload-config \
    no-http no-quic \
    no-gost no-fips no-padlockeng"

  pushd "$OPENSSL_SRC" >/dev/null
  make distclean >/dev/null 2>&1 || true

  # linux-aarch64 is a native config; point CC/CXX at the OHOS clang with the
  # OHOS target triple + sysroot. 16KB max page size for modern arm64 devices.
  CC="$OHOS_NDK/llvm/bin/clang" \
  CXX="$OHOS_NDK/llvm/bin/clang++" \
  CFLAGS="--target=$TRIPLE --sysroot=$OHOS_NDK/sysroot -O2 -ffunction-sections -fdata-sections -fstack-protector-strong -D_FORTIFY_SOURCE=2" \
  CXXFLAGS="--target=$TRIPLE --sysroot=$OHOS_NDK/sysroot -O2" \
  LDFLAGS="--target=$TRIPLE --sysroot=$OHOS_NDK/sysroot -Wl,-z,max-page-size=16384 -Wl,--build-id=sha1" \
    ./Configure linux-aarch64 shared $PARAMS --prefix="$INSTALL_DIR" || { popd; exit 1; }

  make -j"$(sysctl -n hw.ncpu)" || { popd; exit 1; }
  make install_sw || { popd; exit 1; }
  popd >/dev/null

  log "OpenSSL installed to $INSTALL_DIR"
fi

log "deps prefix contents:"
find "$DEPS_PREFIX" -maxdepth 4 \( -name "libcrypto.so*" -o -name "libssl.so*" -o -name "opensslv.h" \) | sort
