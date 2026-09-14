#!/usr/bin/env python3
"""TDLib code generation verification runner (QA-002 / P1-QA-003).

Runs verification modes of the TDLib code generators to assert that
all generated ArkTS classes, unions, and sensitive field redaction
metadata are 100% in sync with the schema IR (schema.ir.json).

Exit codes:
  0: all codegen files are up to date
  1: codegen files are out of sync or generator failed
"""

import os
import subprocess
import sys

ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), "../.."))

def check_codegen() -> int:
    generators = [
        ("ArkTS DTO & unions (GEN-002)", [sys.executable, os.path.join(ROOT, "tools/td_api_codegen/td_api_arkts.py"), "verify"]),
        ("Sensitive metadata (GEN-004)", [sys.executable, os.path.join(ROOT, "tools/td_api_codegen/td_api_sensitive.py"), "verify"]),
    ]

    failed = False
    for name, cmd in generators:
        print(f"[check_codegen] Verifying {name}...")
        res = subprocess.run(cmd, cwd=ROOT, capture_output=True, text=True)
        if res.returncode != 0:
            print(f"[check_codegen] FAIL: {name} verify failed (exit {res.returncode}):")
            if res.stdout:
                print(res.stdout)
            if res.stderr:
                print(res.stderr)
            failed = True
        else:
            output = res.stdout.strip()
            print(f"[check_codegen] OK: {name} — {output}")

    if failed:
        print("[check_codegen] One or more generators reported out-of-date files. Run 'generate' to regenerate.")
        return 1

    print("[check_codegen] ALL CODEGEN CHECKS PASSED")
    return 0

if __name__ == "__main__":
    sys.exit(check_codegen())
