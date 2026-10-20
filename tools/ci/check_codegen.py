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
        # encoding='utf-8' 是 Windows 上的必需项，不是装饰：中文 Windows 的 locale 默认 GBK，
        # subprocess 若不显式指定就用 GBK 解子进程的 stdout，而生成器输出含 UTF-8 字符
        # （"— up to date" 的 em dash 等）—— 解码失败会让读线程抛 UnicodeDecodeError、
        # r.stdout 变成 None，接着在下面 `res.stdout.strip()` 处 AttributeError。
        # 症状是「明明 up to date 却报崩」，且指向本脚本而不是生成器，极难定位。
        # errors='replace' 让偶发的坏字节也不至于把整条管道废掉。
        res = subprocess.run(cmd, cwd=ROOT, capture_output=True, text=True,
                             encoding='utf-8', errors='replace')
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
