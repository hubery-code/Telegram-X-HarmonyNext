#!/bin/bash
# 真机 TDLib smoke：等设备出现 → push 产物 → 运行 → 输出结果。
# 用法: tools/native/smoke-on-device.sh [等待秒数，默认 7200]
# 退出码 0 = smoke 通过；结果写入 native/tdcore/build/device-smoke-result.txt
set -u
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
HDC="/Applications/DevEco-Studio.app/Contents/sdk/default/openharmony/toolchains/hdc"
WAIT="${1:-7200}"
BUILD="$ROOT/native/tdcore/build"
REMOTE=/data/local/tmp/tdsmoke
RESULT="$BUILD/device-smoke-result.txt"
mkdir -p "$BUILD"
rm -f "$RESULT"

deadline=$(( $(date +%s) + WAIT ))
attempt=0
while [ "$(date +%s)" -lt "$deadline" ]; do
  t=$("$HDC" list targets 2>/dev/null | grep -v "^\[Empty\]" | head -1)
  if [ -z "$t" ]; then sleep 10; continue; fi
  attempt=$((attempt + 1))
  echo "[watch] target=$t attempt=$attempt $(date +%H:%M:%S)"

  if ! "$HDC" shell "echo ok" 2>/dev/null | grep -q ok; then
    echo "[watch] shell not ready, retry in 10s"; sleep 10; continue
  fi
  "$HDC" shell "rm -rf $REMOTE && mkdir -p $REMOTE" 2>/dev/null
  "$HDC" file send "$BUILD/arm64-v8a/libtdjson.so" "$REMOTE/libtdjson.so" >/dev/null 2>&1
  "$HDC" file send "$BUILD/deps/openssl/arm64-v8a/lib/libcrypto.so.3" "$REMOTE/libcrypto.so.3" >/dev/null 2>&1
  "$HDC" file send "$BUILD/deps/openssl/arm64-v8a/lib/libssl.so.3" "$REMOTE/libssl.so.3" >/dev/null 2>&1
  if ! "$HDC" file send "$BUILD/td_smoke" "$REMOTE/td_smoke" >/dev/null 2>&1; then
    echo "[watch] push failed, retry"; sleep 10; continue
  fi
  OUT=$("$HDC" shell "chmod +x $REMOTE/td_smoke && LD_LIBRARY_PATH=$REMOTE $REMOTE/td_smoke" 2>&1)
  echo "$OUT" | tee "$RESULT"
  if echo "$OUT" | grep -q "SMOKE-OK"; then
    echo "PASS" | tee -a "$RESULT"
    exit 0
  fi
  echo "FAIL (will retry)"; sleep 15
done
echo "TIMEOUT: smoke not passed within ${WAIT}s" | tee "$RESULT"
exit 2
