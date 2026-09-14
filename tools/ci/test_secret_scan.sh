#!/usr/bin/env bash
# tools/ci/test_secret_scan.sh — SEC-002: Positive and Negative test suite for secret-scan.
#
# Validates:
#   1. Positive test: Clean repository passes with exit code 0.
#   2. Negative tests: Synthetic secret patterns are detected and blocked (exit code 1).
#   3. Zero-leakage: Secret values are NEVER leaked in test output.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
cd "${ROOT}"

PASS_COUNT=0
FAIL_COUNT=0

cleanup() {
  git reset --quiet HEAD -- . 2>/dev/null || true
  rm -f .test_secret_* 2>/dev/null || true
}
trap cleanup EXIT INT TERM

assert_pass() {
  local desc="$1"
  shift
  echo -n "[test_secret_scan] CASE: ${desc} ... "
  if output=$("$@" 2>&1); then
    echo "PASS (exit 0 as expected)"
    PASS_COUNT=$((PASS_COUNT + 1))
  else
    echo "FAIL (unexpected non-zero exit)"
    echo "${output}"
    FAIL_COUNT=$((FAIL_COUNT + 1))
  fi
}

assert_blocked() {
  local desc="$1"
  local secret_marker="$2"
  shift 2
  echo -n "[test_secret_scan] CASE: ${desc} ... "
  if output=$("$@" 2>&1); then
    echo "FAIL (expected to be blocked, but exited 0)"
    FAIL_COUNT=$((FAIL_COUNT + 1))
  else
    # Check that it exited non-zero
    if [[ "${output}" == *"[secret-scan] FAIL"* ]]; then
      # Check zero-leakage: the secret marker must NOT appear in output
      if [[ -n "${secret_marker}" && "${output}" == *"${secret_marker}"* ]]; then
        echo "FAIL (leaked secret marker '${secret_marker}' in output!)"
        FAIL_COUNT=$((FAIL_COUNT + 1))
      else
        echo "PASS (blocked with non-zero exit, zero-leakage verified)"
        PASS_COUNT=$((PASS_COUNT + 1))
      fi
    else
      echo "FAIL (did not contain FAIL banner: ${output})"
      FAIL_COUNT=$((FAIL_COUNT + 1))
    fi
  fi
}

echo "=== Running Positive Test ==="
assert_pass "Clean repository must pass secret-scan" ./tools/ci/secret-scan.sh

echo ""
echo "=== Running Negative Tests (Synthetic Injections) ==="

# Test 1: Telegram api_hash literal
SECRET_HASH="aabbccddeeff00112233445566778899"
TEST_FILE_1=".test_secret_api_hash.ts"
echo "export const config = { api_hash: '${SECRET_HASH}' };" > "${TEST_FILE_1}"
git add "${TEST_FILE_1}"
assert_blocked "Detect api_hash hex literal" "${SECRET_HASH}" ./tools/ci/secret-scan.sh
git reset --quiet HEAD "${TEST_FILE_1}"
rm -f "${TEST_FILE_1}"

# Test 2: Signing keyPassword
SECRET_KP="super_secret_key_pass_xyz"
TEST_FILE_2=".test_secret_kp.json5"
echo "{ material: { keyPassword: '${SECRET_KP}' } }" > "${TEST_FILE_2}"
git add "${TEST_FILE_2}"
assert_blocked "Detect keyPassword sensitive field" "${SECRET_KP}" ./tools/ci/secret-scan.sh
git reset --quiet HEAD "${TEST_FILE_2}"
rm -f "${TEST_FILE_2}"

# Test 3: Signing storePassword
SECRET_SP="super_secret_store_pass_xyz"
TEST_FILE_3=".test_secret_sp.json5"
echo "{ material: { storePassword: '${SECRET_SP}' } }" > "${TEST_FILE_3}"
git add "${TEST_FILE_3}"
assert_blocked "Detect storePassword sensitive field" "${SECRET_SP}" ./tools/ci/secret-scan.sh
git reset --quiet HEAD "${TEST_FILE_3}"
rm -f "${TEST_FILE_3}"

# Test 4: Private key PEM
SECRET_PEM="FAKE_PRIVATE_KEY_BYTES"
TEST_FILE_4=".test_secret_key.pem"
echo "-----BEGIN RSA PRIVATE KEY-----" > "${TEST_FILE_4}"
echo "${SECRET_PEM}" >> "${TEST_FILE_4}"
echo "-----END RSA PRIVATE KEY-----" >> "${TEST_FILE_4}"
git add "${TEST_FILE_4}"
assert_blocked "Detect private key PEM block" "${SECRET_PEM}" ./tools/ci/secret-scan.sh
git reset --quiet HEAD "${TEST_FILE_4}"
rm -f "${TEST_FILE_4}"

# Test 5: Absolute user home path in config
TEST_FILE_5=".test_secret_path.json5"
echo '{ "certpath": "/Users/someone/my_cert.cer" }' > "${TEST_FILE_5}"
git add "${TEST_FILE_5}"
assert_blocked "Detect absolute user home path in config" "/Users/someone" ./tools/ci/secret-scan.sh
git reset --quiet HEAD "${TEST_FILE_5}"
rm -f "${TEST_FILE_5}"

# Test 6: Tracked signing material file
TEST_FILE_6=".test_secret_cert.p12"
touch "${TEST_FILE_6}"
git add -f "${TEST_FILE_6}"
assert_blocked "Detect tracked .p12 signing material file" "" ./tools/ci/secret-scan.sh
git reset --quiet HEAD "${TEST_FILE_6}"
rm -f "${TEST_FILE_6}"

# Test 7: Tracked local.properties
TEST_FILE_7="local.properties"
# Note: local.properties exists on disk; stage it to simulate accidental git add
git add -f "${TEST_FILE_7}"
assert_blocked "Detect tracked local.properties" "" ./tools/ci/secret-scan.sh
git reset --quiet HEAD "${TEST_FILE_7}"

echo ""
echo "========================================================"
echo "Results: ${PASS_COUNT} passed, ${FAIL_COUNT} failed"
echo "========================================================"

if [[ "${FAIL_COUNT}" -gt 0 ]]; then
  exit 1
fi
exit 0
