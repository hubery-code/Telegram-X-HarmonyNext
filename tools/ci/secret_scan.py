#!/usr/bin/env python3
# tools/ci/secret_scan.py — SEC-002: Enhanced zero-leakage secret scanner.
#
# Scans git-tracked files for:
#   1. Private key PEM blocks
#   2. Telegram api_hash / api_id literals
#   3. Signing passwords (keyPassword, storePassword, etc.)
#   4. Absolute user paths in configuration files (/Users/..., /home/...)
#   5. Sensitive/credential files tracked by git
#
# GUARANTEE: Never prints secret values or sensitive lines to stdout/stderr.
# Reports only: file, line number, rule name, and [REDACTED].
import os
import re
import subprocess
import sys

EXCLUDED_PATHS = [
    "native/tdcore/third_party/",
    ".agents/",
    "tools/ci/test_secret_scan.sh",
]

def get_root_dir():
    script_dir = os.path.dirname(os.path.abspath(__file__))
    return os.path.abspath(os.path.join(script_dir, "../.."))

def get_tracked_files(root):
    try:
        res = subprocess.run(
            ["git", "ls-files"],
            cwd=root,
            capture_output=True,
            text=True,
            check=True
        )
        files = res.stdout.splitlines()
        return [f for f in files if f.strip()]
    except Exception as e:
        sys.stderr.write(f"[secret-scan] Failed to list git-tracked files: {e}\n")
        sys.exit(2)

def is_excluded(filepath):
    normalized = filepath.replace("\\", "/")
    for ex in EXCLUDED_PATHS:
        if normalized.startswith(ex) or f"/{ex}" in normalized:
            return True
    return False

def scan_file_contents(root, filepath):
    full_path = os.path.join(root, filepath)
    if not os.path.isfile(full_path):
        return []

    violations = []
    try:
        with open(full_path, "r", encoding="utf-8", errors="ignore") as f:
            lines = f.readlines()
    except Exception:
        return []

    # 1. Private key PEM
    pem_pattern = re.compile(r"-----BEGIN (?:RSA |EC |OPENSSH |PGP |ENCRYPTED )?PRIVATE KEY")

    # 2. Telegram api_hash literal: 16+ hex characters assigned to api_hash/apiHash
    api_hash_pattern = re.compile(
        r"""(?i)(?:api[_-]?hash|apiHash)\s*[:=]\s*["']([0-9a-fA-F]{16,})["']"""
    )

    # 3. Hardcoded real api_id literal (>1000) in production code (skip tests/fixtures/templates)
    api_id_pattern = re.compile(
        r"""(?i)(?:api[_-]?id|apiId)\s*[:=]\s*([1-9][0-9]{3,})"""
    )
    is_test_or_template = any(x in filepath.lower() for x in ["test", "fixture", "template", "mock"])

    # 4. Signing passwords: keyPassword / storePassword with non-empty non-template string
    password_pattern = re.compile(
        r"""(?i)["']?(keyPassword|storePassword|keystorePassword)["']?\s*[:=]\s*["']([^"'\s]+)["']"""
    )

    # 5. Absolute user paths in config files
    is_config_file = filepath.endswith((".json5", ".json", ".properties", ".yaml", ".yml"))
    abs_path_pattern = re.compile(r"""["']/(?:Users|home)/[^"']+["']""")

    for idx, line in enumerate(lines, start=1):
        # Check PEM
        if pem_pattern.search(line):
            violations.append((idx, "private key PEM block detected"))

        # Check api_hash
        m_hash = api_hash_pattern.search(line)
        if m_hash:
            val = m_hash.group(1)
            # Skip if clearly dummy/zero
            if set(val) != {"0"}:
                violations.append((idx, "Telegram api_hash literal detected"))

        # Check api_id
        if not is_test_or_template:
            m_id = api_id_pattern.search(line)
            if m_id:
                violations.append((idx, "hardcoded Telegram apiId literal detected in production code"))

        # Check passwords
        m_pwd = password_pattern.search(line)
        if m_pwd:
            field_name = m_pwd.group(1)
            val = m_pwd.group(2).strip()
            # Allow empty string, template placeholders
            is_placeholder = (
                val == ""
                or val.startswith("<")
                or val.startswith("${")
                or "YOUR_" in val.upper()
                or "PLACEHOLDER" in val.upper()
                or "DUMMY" in val.upper()
            )
            if not is_placeholder:
                violations.append((idx, f"signing credential detected in field '{field_name}'"))

        # Check absolute user paths in config files
        if is_config_file:
            if abs_path_pattern.search(line):
                violations.append((idx, "absolute user home directory path detected in configuration"))

    return violations

def scan_tracked_filenames(tracked_files):
    violations = []
    # Block tracked signing materials and secret files
    sensitive_file_patterns = [
        (re.compile(r"\.(p12|cer|csr|p7b|keystore)$", re.IGNORECASE), "signing material tracked by git"),
        (re.compile(r"(^|/)local\.properties$", re.IGNORECASE), "local.properties tracked by git"),
        (re.compile(r"(^|/)\.signing-config(/|$)", re.IGNORECASE), "signing-config directory tracked by git"),
        (re.compile(r"(^|/)(?:api-config|secrets|tdlib-credentials)\.json5?$", re.IGNORECASE), "secret json/json5 tracked by git"),
        (re.compile(r"(^|/)AppCredentials\.ets$", re.IGNORECASE), "generated AppCredentials.ets tracked by git (only .template.ets allowed)"),
    ]

    for f in tracked_files:
        if is_excluded(f):
            continue
        for pattern, desc in sensitive_file_patterns:
            if pattern.search(f):
                violations.append((f, desc))

    return violations

def main():
    root = get_root_dir()
    print(f"[secret-scan] Scanning tracked files under: {root}")

    tracked_files = get_tracked_files(root)
    total_violations = 0

    # 1. Filename checks
    file_violations = scan_tracked_filenames(tracked_files)
    for f, desc in file_violations:
        total_violations += 1
        print(f"[secret-scan] HIT in {f}: {desc}")

    # 2. Content checks
    for f in tracked_files:
        if is_excluded(f):
            continue
        content_violations = scan_file_contents(root, f)
        for line_no, desc in content_violations:
            total_violations += 1
            # REDACTION: Never print line content or matched secret!
            print(f"[secret-scan] HIT in {f}:{line_no}: {desc} [CONTENT REDACTED]")

    if total_violations > 0:
        print(f"\n[secret-scan] FAIL: {total_violations} violation(s) found.")
        print("[secret-scan] No secret values were printed above. Remove secrets per SECURITY_BASELINE.md.")
        sys.exit(1)

    print("[secret-scan] OK: 0 secrets detected in tracked files")
    sys.exit(0)

if __name__ == "__main__":
    main()
