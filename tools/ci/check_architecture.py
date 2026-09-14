#!/usr/bin/env python3
"""Architecture rule checker (QA-002 / P1-ARCH-001 / P1-QA-003).

Enforces clean architectural boundaries:
1. Core domain packages (core/*/src/main/ets/**) must be 100% Kit-free:
   never import from '@kit.*' or '@ohos.*'.
2. Feature state reducers (feature/*/src/main/ets/reducer/**) must be pure MVI:
   never import from '@kit.*' or '@ohos.*'.
3. No production source file may import from private directories (.test, .system_generated).

Exit codes:
  0: all architecture rules passed
  1: architecture violations detected
"""

import glob
import os
import re
import sys

ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), "../.."))

def check_architecture() -> int:
    violations = []

    # Rule 1: core/*/src/main/ets/** must not import @kit or @ohos
    core_main_pattern = os.path.join(ROOT, "core", "*", "src", "main", "ets", "**", "*.ets")
    for file_path in glob.glob(core_main_pattern, recursive=True):
        rel_path = os.path.relpath(file_path, ROOT)
        with open(file_path, "r", encoding="utf-8", errors="ignore") as f:
            for line_no, line in enumerate(f, 1):
                if re.search(r"from\s+['\"]@(kit|ohos)\b", line):
                    violations.append(
                        f"[CORE_KIT_FREE] {rel_path}:{line_no}: Core domain must not import system Kit: {line.strip()}"
                    )

    # Rule 2: feature/*/src/main/ets/reducer/** must not import @kit or @ohos (pure MVI)
    feature_reducer_pattern = os.path.join(ROOT, "feature", "*", "src", "main", "ets", "reducer", "**", "*.ets")
    for file_path in glob.glob(feature_reducer_pattern, recursive=True):
        rel_path = os.path.relpath(file_path, ROOT)
        with open(file_path, "r", encoding="utf-8", errors="ignore") as f:
            for line_no, line in enumerate(f, 1):
                if re.search(r"from\s+['\"]@(kit|ohos)\b", line):
                    violations.append(
                        f"[PURE_REDUCER] {rel_path}:{line_no}: Reducer must be pure MVI without system Kit: {line.strip()}"
                    )

    # Rule 3: No production source may import from test or system generated folders
    prod_pattern = os.path.join(ROOT, "*", "src", "main", "ets", "**", "*.ets")
    for file_path in glob.glob(prod_pattern, recursive=True):
        rel_path = os.path.relpath(file_path, ROOT)
        with open(file_path, "r", encoding="utf-8", errors="ignore") as f:
            for line_no, line in enumerate(f, 1):
                if re.search(r"from\s+['\"].*\b(\.test|\.system_generated)\b", line):
                    violations.append(
                        f"[PRIVATE_IMPORT] {rel_path}:{line_no}: Illegal import from private directory: {line.strip()}"
                    )

    # Rule 4: feature/*/src/main/ets/coordinator/** must not import @kit or @ohos (Kit-free Coordinators, ARCH-001)
    feature_coord_pattern = os.path.join(ROOT, "feature", "*", "src", "main", "ets", "coordinator", "**", "*.ets")
    for file_path in glob.glob(feature_coord_pattern, recursive=True):
        rel_path = os.path.relpath(file_path, ROOT)
        with open(file_path, "r", encoding="utf-8", errors="ignore") as f:
            for line_no, line in enumerate(f, 1):
                if re.search(r"from\s+['\"]@(kit|ohos)\b", line):
                    violations.append(
                        f"[COORDINATOR_KIT_FREE] {rel_path}:{line_no}: Feature coordinator must not import system Kit directly: {line.strip()}"
                    )

    if violations:
        print(f"[check_architecture] FAIL: {len(violations)} architectural boundary violations found:")
        for v in violations:
            print(f"  {v}")
        return 1

    print("[check_architecture] OK: 0 architectural boundary violations in core domain, reducers, and coordinators")
    return 0

if __name__ == "__main__":
    sys.exit(check_architecture())
