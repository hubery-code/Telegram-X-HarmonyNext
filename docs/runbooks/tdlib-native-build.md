# Runbook: TDLib native build & smoke (OHOS arm64)

Scope: TDN-001/002. Produces `libtdjson.so` for arm64-v8a and verifies it on a
real device. Full evidence: `native/tdcore/BUILD-EVIDENCE.md`.

## Prerequisites

- DevEco Studio SDK per `tools/toolchain-versions.json` (NDK 26.0.0.105).
- Host: cmake ≥ 3.10 + ninja + clang (used only for the one-time source
  generation step). macOS Command Line Tools are enough.
- Device with hdc connected: `hdc list targets` must show a target.

## Procedure

```bash
# 1) One-time after a fresh third_party/td checkout: generate TDLib sources
#    (upstream does not check them in; the build writes into the source tree,
#    which is why third_party/td is a byte copy, not a submodule).
mkdir -p native/tdcore/build/host-generate && cd native/tdcore/build/host-generate
cmake -DCMAKE_BUILD_TYPE=Release -GNinja -DTD_GENERATE_SOURCE_FILES=ON ../../third_party/td
cmake --build .
cd -

# 2) Cross-compiled deps (OpenSSL only; zlib=NDK sysroot, SQLite=TD-bundled)
tools/native/build-tdlib-deps.sh

# 3) TDLib
tools/native/build-tdlib.sh          # add --clean to reconfigure

# 4) Smoke binary
NDK=/Applications/DevEco-Studio.app/Contents/sdk/default/openharmony/native
cd native/tdcore
$NDK/llvm/bin/clang --target=aarch64-linux-ohos --sysroot=$NDK/sysroot -O2 \
  -o build/td_smoke smoke/td_smoke.c \
  -Ithird_party/td -Ibuild/arm64-v8a \
  -Lbuild/arm64-v8a -ltdjson \
  -Lbuild/deps/openssl/arm64-v8a/lib -lssl -lcrypto \
  -L$NDK/sysroot/usr/lib/aarch64-linux-ohos -lz -lm \
  -lunwind -Wl,-z,max-page-size=16384 -Wl,--build-id=sha1 \
  -Wl,-rpath,/data/local/tmp/tdsmoke

# 5) Push & run on device
HDC=$NDK/../toolchains/hdc   # or: sdk/default/openharmony/toolchains/hdc
$HDC shell mkdir -p /data/local/tmp/tdsmoke
$HDC file send build/td_smoke /data/local/tmp/tdsmoke/td_smoke
$HDC file send build/arm64-v8a/libtdjson.so /data/local/tmp/tdsmoke/libtdjson.so
$HDC file send build/deps/openssl/arm64-v8a/lib/libcrypto.so.3 /data/local/tmp/tdsmoke/libcrypto.so.3
$HDC file send build/deps/openssl/arm64-v8a/lib/libssl.so.3 /data/local/tmp/tdsmoke/libssl.so.3
$HDC shell "chmod +x /data/local/tmp/tdsmoke/td_smoke && \
  LD_LIBRARY_PATH=/data/local/tmp/tdsmoke /data/local/tmp/tdsmoke/td_smoke"
```

Expected final line: `SMOKE RESULT: PASS`.

## Known issues

- `hdc` "need connect-key?" / `[Empty]`: restart the server (`hdc kill;
  hdc start`), re-check the cable/unlock the device; `system_profiler
  SPUSBDataType` must list the phone.
- CMake reconfigure with a changed toolchain: always `tools/native/build-tdlib.sh --clean`.
