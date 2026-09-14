#!/usr/bin/env python3
"""
tools/ci/resolve_toolchain.py — GOV-002 / BUILD-001 工具链多级自动发现与校验器。

发现优先级：
  1. 显式环境变量：DEVECO_HOME / DEVECO_SDK_HOME / OHOS_NDK / etc.
  2. 探测系统/用户常见安装路径（macOS / Linux）
  3. 回退基线配置文件 tools/toolchain-versions.json

模式：
  --shell:   输出可直接 eval 的 shell 环境变量导出语句
  --json:    输出解析出的工具链路径 JSON
  --query K: 查询单个字段（如 node, sdk, ndk, hvigorw, ohpm）
  --check:   严格校验工具链存在性及版本是否匹配 toolchain-versions.json
"""

import json
import os
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent.parent
LOCK_FILE = ROOT / "tools" / "toolchain-versions.json"

CANDIDATE_DEVECO_DIRS = [
    Path("/Applications/DevEco-Studio.app/Contents"),
    Path("/Applications/DevEco-Studio.app"),
    Path.home() / "Applications/DevEco-Studio.app/Contents",
    Path.home() / "Applications/DevEco-Studio.app",
    Path("/opt/deveco-studio"),
    Path("/usr/local/deveco-studio"),
    Path.home() / "deveco-studio",
]


def load_lock():
    if not LOCK_FILE.exists():
        sys.stderr.write(f"[resolve-toolchain] ERROR: lock file missing at {LOCK_FILE}\n")
        sys.exit(1)
    with open(LOCK_FILE, "r", encoding="utf-8") as f:
        return json.load(f)


def find_deveco_home(lock_data: dict) -> Path:
    # 1. 环境变量
    env_home = os.environ.get("DEVECO_HOME")
    if env_home:
        p = Path(env_home).resolve()
        if (p / "Contents").exists():
            return p / "Contents"
        return p

    # 2. 探测常见路径
    for cand in CANDIDATE_DEVECO_DIRS:
        if cand.exists():
            if (cand / "Contents").exists():
                return cand / "Contents"
            return cand

    # 3. 回退锁定配置
    lock_path = Path(lock_data.get("deveco", {}).get("path", "/Applications/DevEco-Studio.app"))
    if (lock_path / "Contents").exists():
        return lock_path / "Contents"
    return lock_path


def resolve_toolchain() -> dict:
    lock = load_lock()
    deveco_home = find_deveco_home(lock)

    # SDK Home (hvigor expects DEVECO_SDK_HOME to be the parent of the sdk instance dir)
    env_sdk_home = os.environ.get("DEVECO_SDK_HOME")
    if env_sdk_home:
        sdk_home = Path(env_sdk_home).resolve()
    else:
        sdk_home = deveco_home / "sdk"

    # SDK Path
    env_sdk_path = os.environ.get("OHOS_SDK_HOME") or os.environ.get("SDK_PATH")
    if env_sdk_path:
        sdk_path = Path(env_sdk_path).resolve()
    else:
        # Check standard layout
        if (sdk_home / "default" / "openharmony").exists():
            sdk_path = sdk_home / "default" / "openharmony"
        elif (sdk_home / "openharmony").exists():
            sdk_path = sdk_home / "openharmony"
        else:
            sdk_path = sdk_home / "default" / "openharmony"

    # NDK Path
    env_ndk = os.environ.get("OHOS_NDK") or os.environ.get("TDX_OHOS_NDK") or os.environ.get("NDK_PATH")
    if env_ndk:
        ndk_path = Path(env_ndk).resolve()
    else:
        ndk_path = sdk_path / "native"

    # Node Path
    env_node = os.environ.get("DEVECO_NODE") or os.environ.get("NODE_PATH")
    if env_node:
        node_path = Path(env_node).resolve()
    else:
        node_path = deveco_home / "tools" / "node" / "bin" / "node"

    # Hvigor
    env_hvigor = os.environ.get("HVIGOR_PATH")
    if env_hvigor:
        hvigor_path = Path(env_hvigor).resolve()
    else:
        hvigor_path = deveco_home / "tools" / "hvigor"

    hvigorw_js = hvigor_path / "bin" / "hvigorw.js"

    # ohpm
    env_ohpm = os.environ.get("OHPM_PATH")
    if env_ohpm:
        ohpm_path = Path(env_ohpm).resolve()
    else:
        ohpm_path = deveco_home / "tools" / "ohpm" / "bin" / "ohpm"

    # hdc
    env_hdc = os.environ.get("HDC_PATH")
    if env_hdc:
        hdc_path = Path(env_hdc).resolve()
    else:
        hdc_path = sdk_path / "toolchains" / "hdc"

    return {
        "deveco_home": str(deveco_home),
        "deveco_sdk_home": str(sdk_home),
        "sdk_path": str(sdk_path),
        "ndk_path": str(ndk_path),
        "node_path": str(node_path),
        "hvigor_path": str(hvigor_path),
        "hvigorw_js": str(hvigorw_js),
        "ohpm_path": str(ohpm_path),
        "hdc_path": str(hdc_path),
        "expected_sdk_version": lock.get("sdk", {}).get("version", "26.0.0.105"),
        "expected_sdk_api": lock.get("sdk", {}).get("apiVersion", "26"),
        "expected_hvigor_version": lock.get("hvigor", {}).get("version", "6.26.4"),
    }


def check_toolchain(tc: dict) -> bool:
    errors = []

    # 1. 检查 Node
    node_path = Path(tc["node_path"])
    if not node_path.is_file() or not os.access(node_path, os.X_OK):
        errors.append(f"Node binary not found or not executable at {node_path}")

    # 2. 检查 SDK 与版本
    sdk_pkg = Path(tc["sdk_path"]) / "ets" / "oh-uni-package.json"
    if not sdk_pkg.is_file():
        errors.append(f"SDK manifest not found at {sdk_pkg}")
    else:
        try:
            with open(sdk_pkg, "r", encoding="utf-8") as f:
                pkg_data = json.load(f)
            actual_ver = pkg_data.get("version")
            actual_api = str(pkg_data.get("apiVersion"))
            if actual_ver != tc["expected_sdk_version"]:
                errors.append(
                    f"SDK version mismatch: expected {tc['expected_sdk_version']}, found {actual_ver} ({sdk_pkg})"
                )
            if actual_api != tc["expected_sdk_api"]:
                errors.append(
                    f"SDK apiVersion mismatch: expected {tc['expected_sdk_api']}, found {actual_api} ({sdk_pkg})"
                )
        except Exception as e:
            errors.append(f"Failed to read SDK manifest {sdk_pkg}: {e}")

    # 3. 检查 NDK
    ndk_llvm = Path(tc["ndk_path"]) / "llvm"
    ndk_pkg = Path(tc["ndk_path"]) / "oh-uni-package.json"
    if not ndk_llvm.is_dir():
        errors.append(f"NDK llvm toolchain not found at {ndk_llvm}")
    if not ndk_pkg.is_file():
        errors.append(f"NDK package manifest missing under {tc['ndk_path']}")

    # 4. 检查 hvigor
    hvigor_pkg = Path(tc["hvigor_path"]) / "hvigor" / "package.json"
    if not hvigor_pkg.is_file():
        errors.append(f"hvigor package manifest not found at {hvigor_pkg}")
    else:
        try:
            with open(hvigor_pkg, "r", encoding="utf-8") as f:
                hpkg_data = json.load(f)
            actual_hver = hpkg_data.get("version")
            if actual_hver != tc["expected_hvigor_version"]:
                errors.append(
                    f"hvigor version mismatch: expected {tc['expected_hvigor_version']}, found {actual_hver} ({hvigor_pkg})"
                )
        except Exception as e:
            errors.append(f"Failed to read hvigor package manifest {hvigor_pkg}: {e}")

    # 5. 检查 ohpm
    ohpm_path = Path(tc["ohpm_path"])
    if not ohpm_path.is_file() or not os.access(ohpm_path, os.X_OK):
        errors.append(f"ohpm not found or not executable at {ohpm_path}")

    if errors:
        sys.stderr.write("[resolve-toolchain] FAIL:\n")
        for err in errors:
            sys.stderr.write(f"  - {err}\n")
        return False

    return True


def main():
    tc = resolve_toolchain()

    mode = sys.argv[1] if len(sys.argv) > 1 else "--shell"

    if mode == "--shell":
        # 输出可 eval 的语句
        print(f'export DEVECO_HOME="{tc["deveco_home"]}"')
        print(f'export DEVECO_SDK_HOME="{tc["deveco_sdk_home"]}"')
        print(f'export SDK_PATH="{tc["sdk_path"]}"')
        print(f'export NDK_PATH="{tc["ndk_path"]}"')
        print(f'export NODE_PATH="{tc["node_path"]}"')
        print(f'export HVIGOR_PATH="{tc["hvigor_path"]}"')
        print(f'export HVIGORW_JS="{tc["hvigorw_js"]}"')
        print(f'export OHPM_PATH="{tc["ohpm_path"]}"')
        print(f'export HDC_PATH="{tc["hdc_path"]}"')
        print(f'export TDX_OHOS_NDK="{tc["ndk_path"]}"')
    elif mode == "--json":
        print(json.dumps(tc, indent=2))
    elif mode == "--query":
        if len(sys.argv) < 3:
            sys.stderr.write("Usage: resolve_toolchain.py --query <field>\n")
            sys.exit(1)
        key = sys.argv[2]
        if key in tc:
            print(tc[key])
        else:
            sys.stderr.write(f"Unknown field: {key}\n")
            sys.exit(1)
    elif mode == "--check":
        ok = check_toolchain(tc)
        if not ok:
            sys.exit(1)
        print(
            f"[resolve-toolchain] OK: DevEco={tc['deveco_home']}, SDK={tc['expected_sdk_version']} (API {tc['expected_sdk_api']}), hvigor={tc['expected_hvigor_version']}"
        )
    else:
        sys.stderr.write(f"Unknown option: {mode}\n")
        sys.exit(1)


if __name__ == "__main__":
    main()
