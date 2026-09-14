#!/usr/bin/env python3
# tools/ci/inject_credentials.py — SEC-002: Build-time credentials injection.
#
# Reads Telegram API credentials from local.properties or environment variables,
# validates format, and generates entry/src/main/ets/config/AppCredentials.ets.
#
# NEVER prints or logs the actual secret values.
import os
import re
import sys

def get_root_dir():
    script_dir = os.path.dirname(os.path.abspath(__file__))
    return os.path.abspath(os.path.join(script_dir, "../.."))

def parse_properties(filepath):
    props = {}
    if not os.path.isfile(filepath):
        return props
    with open(filepath, "r", encoding="utf-8", errors="replace") as f:
        for line in f:
            line = line.strip()
            if not line or line.startswith("#") or line.startswith("!"):
                continue
            if "=" in line:
                k, v = line.split("=", 1)
                props[k.strip()] = v.strip().strip("'\"")
            elif ":" in line:
                k, v = line.split(":", 1)
                props[k.strip()] = v.strip().strip("'\"")
    return props

def main():
    root = get_root_dir()
    local_props_path = os.path.join(root, "local.properties")
    props = parse_properties(local_props_path)

    api_id = os.environ.get("TELEGRAM_API_ID") or props.get("telegram.api_id") or props.get("api_id")
    api_hash = os.environ.get("TELEGRAM_API_HASH") or props.get("telegram.api_hash") or props.get("api_hash")

    # Validate presence and non-trivial values
    missing = []
    if not api_id or str(api_id).strip() == "" or str(api_id).strip() == "0":
        missing.append("telegram.api_id / TELEGRAM_API_ID")
    if not api_hash or str(api_hash).strip() == "":
        missing.append("telegram.api_hash / TELEGRAM_API_HASH")

    if missing:
        sys.stderr.write("\n================================================================================\n")
        sys.stderr.write("[inject-credentials] ERROR: Missing Telegram API credentials!\n")
        sys.stderr.write(f"Missing required parameter(s): {', '.join(missing)}\n\n")
        sys.stderr.write("Please configure your credentials in 'local.properties' (project root):\n")
        sys.stderr.write("    telegram.api_id=<YOUR_API_ID>\n")
        sys.stderr.write("    telegram.api_hash=<YOUR_API_HASH>\n\n")
        sys.stderr.write("Or set environment variables:\n")
        sys.stderr.write("    export TELEGRAM_API_ID=<YOUR_API_ID>\n")
        sys.stderr.write("    export TELEGRAM_API_HASH=<YOUR_API_HASH>\n\n")
        sys.stderr.write("To obtain API credentials, register at https://my.telegram.org ('API development tools').\n")
        sys.stderr.write("See 'local.properties.template' and 'README.md' for more information.\n")
        sys.stderr.write("================================================================================\n\n")
        sys.exit(1)

    # Format validation
    try:
        api_id_int = int(str(api_id).strip())
        if api_id_int <= 0:
            raise ValueError()
    except ValueError:
        sys.stderr.write("[inject-credentials] ERROR: api_id must be a positive integer.\n")
        sys.exit(1)

    api_hash_clean = str(api_hash).strip()
    if not re.match(r"^[0-9a-fA-F]{16,}$", api_hash_clean):
        sys.stderr.write("[inject-credentials] ERROR: api_hash format invalid (expected hexadecimal string, min 16 chars).\n")
        sys.exit(1)

    out_dir = os.path.join(root, "entry/src/main/ets/config")
    os.makedirs(out_dir, exist_ok=True)
    out_file = os.path.join(out_dir, "AppCredentials.ets")

    content = f"""// AUTO-GENERATED AT BUILD TIME - DO NOT EDIT OR COMMIT TO GIT
import {{ TelegramCredentials }} from './AppCredentials.template';

export {{ TelegramCredentials }} from './AppCredentials.template';

export const TELEGRAM_CREDENTIALS: TelegramCredentials = {{
  apiId: {api_id_int},
  apiHash: '{api_hash_clean}'
}};
"""
    # Write atomically
    tmp_file = out_file + ".tmp"
    with open(tmp_file, "w", encoding="utf-8") as f:
        f.write(content)
    os.chmod(tmp_file, 0o600)
    os.replace(tmp_file, out_file)

    source = "local.properties" if ("telegram.api_id" in props or "api_id" in props) else "environment"
    print(f"[inject-credentials] OK: credentials successfully injected from {source} (mode 0600)")
    sys.exit(0)

if __name__ == "__main__":
    main()
