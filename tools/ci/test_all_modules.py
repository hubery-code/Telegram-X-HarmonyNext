#!/usr/bin/env python3
"""All-module test runner and assertion gate (QA-002 / P1-QA-001).

Replaces single-module entry testing with comprehensive whole-project
test execution:
1. Enumerates all modules registered in build-profile.json5.
2. Identifies testable modules (containing src/test/List.test.ets) and explicitly
   declares exempt adapter modules (tested via integration/on-device suites).
3. Invokes hvigorw test across all testable modules.
4. Collects and parses test_result.txt from every testable module.
5. Prints a markdown summary matrix and asserts:
   - 0 Failures, 0 Errors
   - Every testable module executed and produced results
   - Total tests >= baseline (770) to prevent silent test drop

Exit codes:
  0: all module tests passed and assertions satisfied
  1: test failure, error, missing results, or test regression
"""

import json
import os
import re
import subprocess
import sys

ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), "../.."))
MIN_BASELINE_TEST_COUNT = int(os.environ.get("MIN_TEST_COUNT", "790"))


EXEMPT_MODULE_REASONS = {
    "platform_files": "System app files adapter; covered via entry integration tests and on-device test suites",
    "platform_keystore": "Hardware HUKS keystore & random; covered via entry/src/test/lifecycle/BootstrapKeystore.test.ets (8 tests) and on-device test suites",
}

def parse_json5(text: str):
    """Strip single-line comments and trailing commas for simple JSON5 parsing."""
    lines = []
    for line in text.splitlines():
        stripped = line.strip()
        if stripped.startswith("//"):
            continue
        line = re.sub(r"//.*$", "", line)
        lines.append(line)
    clean = "\n".join(lines)
    clean = re.sub(r",\s*([\]}])", r"\1", clean)
    return json.loads(clean)

def get_modules_from_profile():
    profile_path = os.path.join(ROOT, "build-profile.json5")
    with open(profile_path, "r", encoding="utf-8") as f:
        data = parse_json5(f.read())
    return data.get("modules", [])

def main():
    print("==================== [test_all_modules] 1/3 Module Discovery ====================")
    raw_modules = get_modules_from_profile()
    testable = []
    exempt = []

    for mod in raw_modules:
        name = mod["name"]
        src_path = mod["srcPath"].lstrip("./")
        full_src = os.path.join(ROOT, src_path)
        list_test = os.path.join(full_src, "src", "test", "List.test.ets")
        if os.path.exists(list_test):
            testable.append((name, src_path))
        else:
            reason = EXEMPT_MODULE_REASONS.get(name, "No local unit test suite defined")
            exempt.append((name, src_path, reason))

    print(f"[test_all_modules] Found {len(raw_modules)} total modules:")
    print(f"  - Testable with unit suites: {len(testable)}")
    for name, path in testable:
        print(f"      • {name:<24} ({path})")
    print(f"  - Exempt modules with explicit rationale: {len(exempt)}")
    for name, path, reason in exempt:
        print(f"      • {name:<24} ({path}) -> {reason}")

    if not testable:
        print("[test_all_modules] ERROR: No testable modules found!")
        return 1

    print("\n==================== [test_all_modules] 2/3 Executing Tests ====================")
    module_arg = ",".join(f"{name}@default" for name, _ in testable)
    hvigorw_path = os.path.join(ROOT, "hvigorw")

    cmd = [
        hvigorw_path,
        "test",
        "--mode", "module",
        "-p", f"module={module_arg}",
        "--no-daemon"
    ]
    print(f"[test_all_modules] Running: {' '.join(cmd[:4])} -p module=[{len(testable)} modules] --no-daemon")

    collect_only = "--collect-only" in sys.argv or "--skip-run" in sys.argv
    if not collect_only:
        # Run hvigorw test
        res = subprocess.run(cmd, cwd=ROOT)
        if res.returncode != 0:
            print(f"[test_all_modules] ERROR: hvigorw test failed with exit code {res.returncode}")
            return res.returncode
    else:
        print("[test_all_modules] (Skipping execution, collecting existing results as requested)")

    print("\n==================== [test_all_modules] 3/3 Collecting Results & Assertions ====================")
    total_run = 0
    total_pass = 0
    total_fail = 0
    total_error = 0
    missing_modules = []

    results = []

    for name, path in testable:
        # Search candidate locations for test_result.txt
        res_file = os.path.join(ROOT, path, ".test/default/intermediates/test/coverage_data/test_result.txt")
        if not os.path.exists(res_file):
            alt_file = os.path.join(ROOT, path, "build/default/cache/default/default@PackageHar/.test/default/intermediates/test/coverage_data/test_result.txt")
            if os.path.exists(alt_file):
                res_file = alt_file

        if os.path.exists(res_file):
            with open(res_file, "r", encoding="utf-8", errors="ignore") as f:
                content = f.read()
            m = re.search(r"Tests run:\s*(\d+),\s*Failure:\s*(\d+),\s*Error:\s*(\d+),\s*Pass:\s*(\d+)", content)
            if m:
                run, fail, err, pas = int(m.group(1)), int(m.group(2)), int(m.group(3)), int(m.group(4))
                total_run += run
                total_pass += pas
                total_fail += fail
                total_error += err
                status = "PASS" if (fail == 0 and err == 0 and run > 0) else "FAIL"
                results.append((name, path, run, pas, fail, err, status))
            else:
                missing_modules.append((name, path, "Malformed test_result.txt"))
        else:
            missing_modules.append((name, path, "test_result.txt not generated"))

    # Print results table
    print(f"| {'Module':<24} | {'Path':<22} | {'Run':<5} | {'Pass':<5} | {'Fail':<5} | {'Error':<5} | {'Status':<6} |")
    print(f"|{'-'*26}|{'-'*24}|{'-'*7}|{'-'*7}|{'-'*7}|{'-'*7}|{'-'*8}|")
    for name, path, run, pas, fail, err, status in results:
        print(f"| {name:<24} | {path:<22} | {run:<5} | {pas:<5} | {fail:<5} | {err:<5} | {status:<6} |")

    print(f"|{'='*26}|{'='*24}|{'='*7}|{'='*7}|{'='*7}|{'='*7}|{'='*8}|")
    overall_status = "PASS" if (total_fail == 0 and total_error == 0 and not missing_modules and total_run >= MIN_BASELINE_TEST_COUNT) else "FAIL"
    print(f"| {'TOTAL':<24} | {'[19 modules]':<22} | {total_run:<5} | {total_pass:<5} | {total_fail:<5} | {total_error:<5} | {overall_status:<6} |")

    # Assertions
    failures = []
    if missing_modules:
        for name, path, reason in missing_modules:
            failures.append(f"Missing results for {name} ({path}): {reason}")

    if total_fail > 0:
        failures.append(f"Detected {total_fail} test failures across modules")

    if total_error > 0:
        failures.append(f"Detected {total_error} test errors across modules")

    if total_run < MIN_BASELINE_TEST_COUNT:
        failures.append(f"Test count regression: ran {total_run} tests, expected at least baseline {MIN_BASELINE_TEST_COUNT}")

    if failures:
        print("\n[test_all_modules] ASSERTION FAILED:")
        for f in failures:
            print(f"  • {f}")
        return 1

    print(f"\n[test_all_modules] ALL ASSERTIONS PASSED: {total_run}/{total_run} tests passed across {len(testable)} modules.")
    return 0

if __name__ == "__main__":
    sys.exit(main())
