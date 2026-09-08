#!/bin/bash
# 真机 TDLib smoke：等设备出现 → push 产物 → 运行 → 输出结果。
# 用法: tools/native/smoke-on-device.sh [等待秒数，默认 3600]
# 退出码 0 = smoke 通过；结果写入 native/tdcore/build/device-smoke-result.txt
set -u
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
HDC="/Applications/DevEco-Studio.app/Contents/sdk/default/openharmony/toolchains/hdc"
WAIT="${1:-3600}"
BUILD="$ROOT/native/tdcore/build"
REMOTE=/data/local/tmp/tdsmoke
mkdir -p "$BUILD"

deadline=$(( $(date +%s) + WAIT ))
while [ -z "$("$HDC" list targets 2>/dev/null)" ]; do
  if [ "$(date +%s)" -ge "$deadline" ]; then
    echo "TIMEOUT: device not connected within ${WAIT}s" | tee "$BUILD/device-smoke-result.txt"
    exit 2
  fi
  sleep 10
done

set -e
"$HDC" shell "rm -rf $REMOTE && mkdir -p $REMOTE"
"$HDC" file send "$BUILD/arm64-v8a/libtdjson.so" "$REMOTE/libtdjson.so" >/dev/null
"$HDC" file send "$BUILD/deps/openssl/arm64-v8a/lib/libcrypto.so.3" "$REMOTE/libcrypto.so.3" >/dev/null
"$HDC" file send "$BUILD/deps/openssl/arm64-v8a/lib/libssl.so.3" "$REMOTE/libssl.so.3" >/dev/null 2>&1 || true
"$HDC" file send "$BUILD/td_smoke" "$REMOTE/td_smoke" >/dev/null
OUT=$("$HDC" shell "chmod +x $REMOTE/td_smoke && LD_LIBRARY_PATH=$REMOTE $REMOTE/td_smoke" 2>&1)
echo "$OUT" | tee "$BUILD/device-smoke-result.txt"
if echo "$OUT" | grep -q "SMOKE-OK"; then
  echo "PASS" | tee -a "$BUILD/device-smoke-result.txt"
  exit 0
fi
echo "FAIL" | tee -a "$BUILD/device-smoke-result.txt"
exit 1
