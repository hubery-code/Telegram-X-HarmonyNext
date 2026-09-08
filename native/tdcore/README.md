# tdcore — TDLib native core for HarmonyOS NEXT

TDLib C++ core cross-compiled with the locked HarmonyOS NDK (see
`tools/toolchain-versions.json`, ADR-001). This module currently delivers the
upstream `libtdjson` (global client C API: `td_create_client_id` / `td_send` /
`td_receive` / `td_execute`). The Node-API wrapper (`libtdcore_napi.so`) is a
later work package (BRG-*); it will statically link the artifacts built here.

## Dependency matrix (TDN-001)

| Library | Version | Source | Build options | Target ABI | License | Artifacts |
|---|---|---|---|---|---|---|
| TDLib | 1.8.67 (commit `d1085f9cebc5a62379991ae1652673954f229c1f`) | `third_party/td` — byte copy of read-only reference `Telegram-X/tdlib/source/td` (no `.git`) | CMake, `RelWithDebInfo`, `TD_ENABLE_LTO=OFF`, `TD_ENABLE_JNI=OFF`, OHOS STL `c++_static`; generated sources produced by one host build (`TD_GENERATE_SOURCE_FILES=ON`, they are **not** checked in upstream) | arm64-v8a (API 26 NDK) | Boost Software License 1.0 (`LICENSE_1_0.txt`) | `build/arm64-v8a/libtdjson.so` (+ static `tdjson_private`, `tdcore`, `tdapi`, … in the same build tree) |
| OpenSSL | 3.5.8 (commit `f4dc4d58b48d346a8270183f89acf826d459b0ca`) | `third_party/openssl` — official `openssl/openssl` tarball pinned to the **same commit as the Android reference build** (`Telegram-X/tdlib/openssl/version.txt`); tarball sha256 `14067f511684d80698ffe97b8ad7989b9271ef6eef1b4b115cb00966c13e89d3` | `./Configure linux-aarch64 shared` with OHOS clang (`--target=aarch64-linux-ohos`), minimized feature set copied from `tdlib/source/build-openssl.sh` (`no-legacy no-engine no-async no-ssl3 no-camellia no-aria no-cast no-idea no-rc2 no-rc5 no-md4 …`), 16 KB max page size | arm64-v8a | Apache-2.0 | `build/deps/openssl/arm64-v8a/lib/libcrypto.so.3`, `libssl.so.3` |
| zlib | 1.3.1 | **OHOS NDK sysroot** (`sysroot/usr/include/zlib.h`, `sysroot/usr/lib/aarch64-linux-ohos/libz.so`) — part of the locked NDK, not built by us; linked shared, provided by the device system image | — | arm64-v8a | zlib/libpng license (NDK `NOTICE.txt`) | sysroot `libz.so` (runtime: system `/lib64/libz.so`) |
| SQLite | 3.31.0 (amalgamation) | Bundled in the TD tree at `third_party/td/sqlite/sqlite/sqlite3.c` | Built by TD's own CMake (`add_subdirectory(sqlite)` → static `tdsqlite`), linked into `libtdjson.so`. No standalone build. | arm64-v8a | Public domain (sqlite.org blessing; see header of `sqlite3.c`) | statically linked into `libtdjson.so` |
| libc++ / libc++abi | LLVM 15.0.4 (NDK clang `329916b990b43824d4b7e67de911fee7a966b1c8`) | OHOS NDK llvm | `OHOS_STL=c++_static` → `-static-libstdc++` | arm64-v8a | Apache-2.0 + LLVM exception | statically linked into every artifact |

### Does TDLib need OpenSSL? (matrix conclusion)

**Yes — unconditionally.** `td/CMakeLists.txt` does `find_package(OpenSSL)` and
**stops the build** (`message(WARNING "Can't find OpenSSL: stop building")` +
`return()`) when it is missing; `tdmtproto` links
`${OPENSSL_CRYPTO_LIBRARY}` (TDLib uses AES-IGE, SHA-1/2, RSA, DH/BN, HMAC).
TDLib's CMake has no option to use a different TLS/crypto provider, and it
cannot consume HarmonyOS's system crypto (`libohcrypto.so` has no OpenSSL
headers/ABI). Therefore OpenSSL is cross-compiled from the pinned upstream
commit above and lives in `build/deps/`. Only `libcrypto` is functionally
required; `libssl` is produced by the same build but unused by TDLib.

### zlib / SQLite

- **zlib**: no copy is vendored inside the TD source tree (tdutils includes
  `<zlib.h>` only). The locked NDK sysroot already ships zlib 1.3.1 headers
  and a shared `libz.so` that the device system image provides, so no
  separate zlib build exists (`tools/native/build-tdlib-deps.sh` verifies and
  documents this instead of building).
- **SQLite**: TDLib pins its own amalgamation (3.31.0) in-tree and always
  builds it itself; a separate sqlite build would be wrong.

## Layout

```
cmake/ohos-toolchain.cmake   OHOS NDK toolchain wrapper (locks arm64-v8a, c++_static)
third_party/td               TDLib 1.8.67 source (byte copy, generated sources populated)
third_party/openssl          OpenSSL 3.5.8 source (pinned commit)
smoke/td_smoke.c             minimal synchronous smoke (td_execute)
build/host-generate/         host build that generated TD sources (one-time)
build/deps/openssl/          cross-compiled OpenSSL
build/arm64-v8a/             TDLib cross build output (libtdjson.so)
build/td_smoke               smoke executable (arm64)
```

## Local patches

`patches/` holds the OHOS patch series applied to `third_party/td`
(`0001-ohos-musl-thread-affinity.patch` and later). After upgrading the TD
snapshot, re-apply/refresh these.

## Build

```bash
# 0) one-time: populate generated TD sources (host build, writes into third_party/td)
mkdir -p native/tdcore/build/host-generate && cd native/tdcore/build/host-generate
cmake -DCMAKE_BUILD_TYPE=Release -GNinja -DTD_GENERATE_SOURCE_FILES=ON ../../third_party/td
cmake --build .

# 1) OpenSSL (zlib/sqlite intentionally skipped — see matrix)
tools/native/build-tdlib-deps.sh

# 2) TDLib libtdjson
tools/native/build-tdlib.sh
```

## Smoke test (real device)

```bash
# build smoke binary (see native/tdcore/BUILD-EVIDENCE.md for the exact command)
# then push and run:
hdc shell mkdir -p /data/local/tmp/tdsmoke
hdc file send td_smoke /data/local/tmp/tdsmoke/
hdc file send build/arm64-v8a/td/libtdjson.so /data/local/tmp/tdsmoke/
hdc file send build/deps/openssl/arm64-v8a/lib/libcrypto.so.3 /data/local/tmp/tdsmoke/
hdc shell "chmod +x /data/local/tmp/tdsmoke/td_smoke && \
  LD_LIBRARY_PATH=/data/local/tmp/tdsmoke /data/local/tmp/tdsmoke/td_smoke"
```
