#!/usr/bin/env bash
# tools/ci/secret-scan.sh — GOV-007 最小秘密扫描。
# 静态 grep 常见泄密模式（接 GOV-006 ci.sh；不替代 CI 平台的 SAST/SBOM 扫描）：
#   1. Telegram api_hash 值形态（16+ 位十六进制，常见于 api_id/api_hash 配置）
#   2. PEM 私钥块
#   3. 已被 git 跟踪的签名材料（*.p12/*.cer/*.csr/*.p7b/keystore）——.gitignore 应挡住，
#      若被跟踪说明有人强行 add
# 命中任一模式 → 打印证据并退出 1；干净 → 退出 0。
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
cd "${ROOT}"

VIOLATIONS=0

report() {
  echo "[secret-scan] HIT: $1"
  VIOLATIONS=$((VIOLATIONS + 1))
}

echo "[secret-scan] scanning tracked sources under ${ROOT}"

# 上游源码自带的公开测试 PEM（OpenSSL apps/*.pem 等）不属于秘密，排除 third_party；
# .agents/skills 下是第三方 SDK 参考文档（含厂商示例 PEM 形态字符串，非真实密钥），
# 同样不属于本工程秘密面。
EXCLUDE=':!native/tdcore/third_party'
EXCLUDE_SKILL_DOCS=':!.agents'

# 1. 私钥 PEM 块（任何被 git 跟踪的文件里都不允许；上游 vendored 测试材料除外）
if git grep -n --no-color -I -E -e "-----BEGIN (RSA |EC |OPENSSH |PGP |ENCRYPTED )?PRIVATE KEY( BLOCK)?-----" -- . "$EXCLUDE" "$EXCLUDE_SKILL_DOCS" ; then
  report "private key PEM block found in tracked files"
fi

# 2. api_hash 赋值形态：api_hash\s*[:=]\s*["'][0-9a-fA-F]{16,}["']
#    以及通用变量名承载的 32 位十六进制 secret
if git grep -n --no-color -I -iE -e "api[_-]?hash[\"' ]*[:=][\"' ]*[0-9a-f]{16,}[\"' ]*" -- . "$EXCLUDE" ; then
  report "api_hash literal found in tracked files"
fi
# TDLib 常见初始化字段名
if git grep -n --no-color -I -iE -e "(api_hash|apiHash)[\"' ]*[:=][\"' ]*[\"'][0-9a-f]{16,}" -- '*.ts' '*.ets' '*.json5' '*.json' '*.cpp' '*.h' '*.c' "$EXCLUDE" ; then
  report "api_hash-like field with hex value found"
fi

# 3. 签名材料被 git 跟踪（.gitignore 的兜底检查）
TRACKED_SECRETS="$(git ls-files | grep -iE '\.(p12|cer|csr|p7b|keystore)$|\.signing-config' || true)"
if [[ -n "${TRACKED_SECRETS}" ]]; then
  echo "${TRACKED_SECRETS}" | while read -r f; do
    echo "[secret-scan] HIT: signing material tracked by git: $f"
  done
  VIOLATIONS=$((VIOLATIONS + 1))
fi

if [[ "${VIOLATIONS}" -gt 0 ]]; then
  echo "[secret-scan] FAIL: ${VIOLATIONS} violation(s). Remove secrets per SECURITY_BASELINE.md."
  exit 1
fi
echo "[secret-scan] OK: no secrets detected in tracked files"
exit 0
