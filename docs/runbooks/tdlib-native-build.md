# Runbook: TDLib native build & smoke (OHOS arm64)

Scope: TDN-001/002 (+ BRG-001/002 应用内验证路径). Produces `libtdjson.so`
for arm64-v8a and verifies it on a real device. Full evidence:
`native/tdcore/BUILD-EVIDENCE.md`, `native/tdcore/napibridge/EVIDENCE.md`.

> 实测结论：真机 hdc shell 域被 SELinux 禁止 exec 任意 ELF，smoke 必须在
> 应用进程内运行（BRG-001 验证页 onPageShow 自动执行）。

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

## 应用内验证路径（BRG-001/002，推荐）

hdc shell 无法 exec ELF，改为：Node-API 桥 (`native/tdcore/napibridge`) +
entry 验证页 (`Index.ets`，加载即自动执行 TDLib 检查)。

```bash
# 0) 前提：TDLib 构建产物存在（含 stripped/ 副本，soname 已修正）
tools/native/build-tdlib.sh

# 1) 构建并安装
./tools/ci/build.sh debug
HDC=/Applications/DevEco-Studio.app/Contents/sdk/default/openharmony/toolchains/hdc
$HDC install -r entry/build/default/outputs/default/entry-default-signed.hap

# 2) 启动应用（页面 onPageShow 自动执行验证）
$HDC shell aa start -a EntryAbility -b org.telegram.x.harmony
sleep 5

# 3) 截屏取证
$HDC shell snapshot_display -f /data/local/tmp/tdx_verify.jpeg
$HDC file recv /data/local/tmp/tdx_verify.jpeg .

# 4) 日志兜底（ArkTS 侧同一内容也会打 hilog）
$HDC shell "hilog | grep -i -e telegram -e tdlib -e tdx | tail -30"
```

预期页面显示：`TDLib 版本: 1.8.67` + `execute 结果:
{"@type":"textEntities",...}` + 订阅区显示 `收到请求响应: clientId=... 
sequence=... @type=option`（BRG-003 receive 线程 + TSFN 端到端）+
指标行 `queue=0 overflowWait=0 dropped=0 forwarded=... subs=1
running=true`。

### 订阅/销毁验证（BRG-003/004）

- 验证页 `aboutToAppear` 自动：subscribe → createClient → send
  getOption(version, @extra.requestId=smoke-1) → 事件回调显示响应。
- 「刷新指标 / 退订」按钮：退订后 `subs=0 running=false`（receive 线程
  停止、TSFN 释放）；再次进入页面自动重建订阅，反复进出不崩溃即销毁
  安全。也可用 `hdc shell aa force-stop org.telegram.x.harmony` 后重启
  验证冷启动路径。

### 打包要点（已踩过的坑）

- hvigor 会把 CMake imported SHARED 库自动拷进 hap —— 不要再把这些
  .so 放 `entry/libs/`（00306049 duplicated files）。
- imported 路径必须指向**真实 versioned 文件名**（`libcrypto.so.3`，
  不是 `libcrypto.so` 符号链接），否则打包后的文件名与 DT_NEEDED 的
  soname 不匹配。
- tdjson 上游不设 SONAME → 链接它的目标会记录绝对路径到 DT_NEEDED；
  `build-tdlib.sh` 已用 `-Wl,-soname,libtdjson.so` 修正。
- hvigor 对打包 .so 执行 DoNativeStrip；hap 内 tdjson ~32MB。

## Known issues

- `hdc` "need connect-key?" / `[Empty]`: restart the server (`hdc kill;
  hdc start`), re-check the cable/unlock the device; `system_profiler
  SPUSBDataType` must list the phone.
- CMake reconfigure with a changed toolchain: always `tools/native/build-tdlib.sh --clean`.

## 真机限制（2026-09-08 实测，重要）

**HarmonyOS 6.1（API 24）真机的 hdc shell（uid=shell）域被 SELinux 禁止直接 exec 任意 ELF**：`chmod 755` 后执行仍报 `Permission denied`（`/lib/ld-musl-aarch64.so.1` 同样被拒）。无 shebang 的脚本会由 shell 兜底解释执行，所以 shell 脚本可以跑、原生二进制不行。

**结论**：native smoke / TDLib 验证必须**在应用进程内**进行——通过 Node-API 桥（见 BRG-001/002）在 debug HAP 里调用 `td_execute` 等接口，UI 展示结果后截图取证。`tools/native/smoke-on-device.sh` 保留仅作 push 工具。
