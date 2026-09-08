# TDN-001/002 Build Evidence — TDLib native for HarmonyOS NEXT

Date: 2026-09-08. Builder: Native AI (Phase 1 work packages TDN-001, TDN-002).
Host: macOS, Apple Silicon. Device target: Phone arm64-v8a (ADR-001).

## Toolchain (locked, matches tools/toolchain-versions.json / GOV-002)

| Tool | Version |
|---|---|
| OHOS NDK (sdk-native) | 26.0.0.105 (`/Applications/DevEco-Studio.app/Contents/sdk/default/openharmony/native`) |
| clang (OHOS, llvm-project `329916b990b43824d4b7e67de911fee7a966b1c8`) | 15.0.4 |
| CMake | 3.22.1-g37088a8 |
| Ninja | 1.10.2 |
| TDLib | 1.8.67, commit `d1085f9cebc5a62379991ae1652673954f229c1f` |
| OpenSSL | 3.5.8, commit `f4dc4d58b48d346a8270183f89acf826d459b0ca` |
| zlib | 1.3.1 (NDK sysroot) |
| SQLite | 3.31.0 (TD-bundled amalgamation) |

## What TDLib needs (dependency matrix conclusion)

See `native/tdcore/README.md`. Key finding: **OpenSSL is mandatory** —
`td/CMakeLists.txt` aborts the build when `find_package(OpenSSL)` fails and
`tdmtproto` links `libcrypto`. zlib comes from the locked NDK sysroot; SQLite
is compiled by TD's own CMake from its in-tree amalgamation.

## Patches applied to third_party/td (patch series, per plan §5.1)

| Patch | File | Why |
|---|---|---|
| `patches/0001-ohos-musl-thread-affinity.patch` | `tdutils/td/utils/port/detail/ThreadPthread.cpp` | OHOS libc is musl-based; `pthread_setaffinity_np`/`pthread_getaffinity_np` are glibc-only. OHOS is routed to the `TD_LINUX` branch because clang targets `aarch64-linux-ohos` (`__linux__`). Patch excludes `__OHOS__` so affinity reports the existing "Unsupported" path (perf hint only, no correctness impact). |

## Build commands (encoded in tools/native/*.sh)

```bash
# one-time host generation of TDLib sources (not checked in upstream)
cmake -DCMAKE_BUILD_TYPE=Release -GNinja -DTD_GENERATE_SOURCE_FILES=ON ../../third_party/td  # in build/host-generate
cmake --build .
# deps (OpenSSL; zlib/sqlite intentionally skipped — see README)
tools/native/build-tdlib-deps.sh
# TDLib
tools/native/build-tdlib.sh        # RelWithDebInfo, TD_ENABLE_LTO=OFF, JNI OFF, OHOS_STL=c++_static
```

Notable fixes discovered during the build:
1. NDK toolchain restricts `find_*` to `CMAKE_FIND_ROOT_PATH` (ONLY modes) but
   does not include the sysroot → `find_package(ZLIB)` failed. Fix: toolchain
   wrapper appends `${OHOS_SDK_NATIVE}/sysroot` (and the deps prefix) to
   `CMAKE_FIND_ROOT_PATH`.
2. CMake has no `Platform/OHOS` module → no default `/usr/include` search path,
   so ZLIB paths are passed explicitly (`-DZLIB_INCLUDE_DIR/-DZLIB_LIBRARY`).
3. musl thread-affinity patch above.

## Artifacts (native/tdcore/build/)

| File | Size | sha256 | build-id |
|---|---|---|---|
| `arm64-v8a/libtdjson.so` (RelWithDebInfo, unstripped) | 387,786,704 B | `4115a09ad9bd9f6114ad5b3ac920ffea8162796b7730051962a0134d954599d8` | `7b9c054b3e5b8e2f94a9a4aea3178f6fc6f8d24b` |
| `arm64-v8a/libtdjson.so` stripped of debug (preview, TDN-004 will own stripping) | 47,888,496 B | — | — |
| `deps/openssl/arm64-v8a/lib/libcrypto.so.3` | 4,497,400 B | `2461ddb258f5607682a238946143b13f12ea34f001e1989416c75174ba6b14a0` | `342de1539a4f654c8a0924b5854ab0dbceeb3b2c` |
| `deps/openssl/arm64-v8a/lib/libssl.so.3` (built, unused by TDLib) | — | `0591a1101e9596b892ec142305175b7118e94fa87fae5950b306e3e3d988988f` | — |
| `td_smoke` (smoke executable, arm64 PIE, musl interp `/lib/ld-musl-aarch64.so.1`) | 14,664 B | `3935be0e8f99f8cb62d86ca4cfe2987edd03ebdaad0296f8d73f59051814c54e` | `36d2f3bdcff8640e3ea5be8f56ccfa87691f0716` |

`llvm-readelf -d arm64-v8a/libtdjson.so`:

```
(NEEDED) libssl.so.3
(NEEDED) libcrypto.so.3
(NEEDED) libz.so      # device system library
(NEEDED) libc.so
```

`llvm-nm -D` confirms exports: `td_create_client_id`, `td_send`,
`td_receive`, `td_execute`, plus the legacy `td_json_client_*` set.

## Smoke test

Source: `native/tdcore/smoke/td_smoke.c` — links `libtdjson.so`, calls only the
synchronous global API `td_execute` with `getOption("version")` and
`getTextEntities` (no network / account / storage needed).

Exact compile command:

```bash
$NDK/llvm/bin/clang --target=aarch64-linux-ohos --sysroot=$NDK/sysroot -O2 \
  -o build/td_smoke smoke/td_smoke.c \
  -Ithird_party/td -Ibuild/arm64-v8a \
  -Lbuild/arm64-v8a -ltdjson \
  -Lbuild/deps/openssl/arm64-v8a/lib -lssl -lcrypto \
  -L$NDK/sysroot/usr/lib/aarch64-linux-ohos -lz -lm \
  -lunwind -Wl,-z,max-page-size=16384 -Wl,--build-id=sha1 \
  -Wl,-rpath,/data/local/tmp/tdsmoke
```

### Real-device result (VYG-AL00 / hdc target 6XE0225A27023538)

<!-- DEVICE-SMOKE-RESULT -->

**STATUS: BLOCKED (device hardware disconnect) — everything up to and including
push-ready artifacts is done; only the on-device execution is missing.**
Timeline: `hdc list targets` succeeded at session start
(17:30, target `6XE0225A27023538`); before the first `hdc shell` the USB device
disappeared from the host (system_profiler shows no phone, hdc `[Empty]`).
Polled for reconnection for 40+ minutes (two 20-minute rounds, 30 s interval) —
device never came back. This is a physical disconnect, not an hdc software
issue (`hdc kill/start`, server restart, and USB re-enumeration were tried).

```bash
HDC=/Applications/DevEco-Studio.app/Contents/sdk/default/openharmony/toolchains/hdc
hdc shell mkdir -p /data/local/tmp/tdsmoke
hdc file send native/tdcore/build/td_smoke /data/local/tmp/tdsmoke/td_smoke
hdc file send native/tdcore/build/arm64-v8a/libtdjson.so /data/local/tmp/tdsmoke/libtdjson.so
hdc file send native/tdcore/build/deps/openssl/arm64-v8a/lib/libcrypto.so.3 /data/local/tmp/tdsmoke/libcrypto.so.3
hdc file send native/tdcore/build/deps/openssl/arm64-v8a/lib/libssl.so.3 /data/local/tmp/tdsmoke/libssl.so.3
hdc shell "chmod +x /data/local/tmp/tdsmoke/td_smoke && \
  LD_LIBRARY_PATH=/data/local/tmp/tdsmoke /data/local/tmp/tdsmoke/td_smoke"
```

Expected PASS output:

```
getOption(version): {"@type":"option","name":"version","value":{"@type":"optionValueString","value":"1.8.67"}}
getTextEntities: {"@type":"textEntities","entities":[{"@type":"textEntity","offset":6,"length":9,"type":{"@type":"textEntityTypeMention"}}]}
SMOKE RESULT: PASS
```
