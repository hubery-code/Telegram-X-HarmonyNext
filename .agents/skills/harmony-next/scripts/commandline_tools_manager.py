#!/usr/bin/env python3
from __future__ import annotations

import argparse
import hashlib
import json
import os
import shutil
import subprocess
import sys
import tarfile
import urllib.parse
import urllib.request
import zipfile
from dataclasses import dataclass
from pathlib import Path


DEFAULT_INSTALL_ROOT = Path.home() / ".harmony" / "command-line-tools"
PROFILE_BEGIN = "# >>> harmony-next command-line-tools >>>"
PROFILE_END = "# <<< harmony-next command-line-tools <<<"
ARCHIVE_SUFFIXES = (".zip", ".tar", ".tar.gz", ".tgz", ".tar.xz", ".txz")
DIRECT_DOWNLOAD_HINT = "https://developer.huawei.com/consumer/cn/download/command-line-tools-for-hmos"
DOWNLOAD_CENTER_LOGIN_HINT = (
    "Huawei download center requires an authenticated browser session for package selection. "
    "Open the download center in a browser, sign in, copy the actual archive link, then pass it with --url; "
    "or download the archive manually and use install --archive."
)


class CommandLineToolsError(RuntimeError):
    pass


@dataclass(frozen=True)
class InstallResult:
    install_root: Path
    tools_root: Path
    bin_dir: Path
    profile: Path | None = None
    source_command: str | None = None

    def to_json(self) -> dict[str, object]:
        return {
            "installRoot": str(self.install_root),
            "toolsRoot": str(self.tools_root),
            "binDir": str(self.bin_dir),
            "profile": str(self.profile) if self.profile else None,
            "sourceCommand": self.source_command,
        }


def print_json(payload: object) -> None:
    print(json.dumps(payload, ensure_ascii=False, indent=2))


def is_archive_name(name: str) -> bool:
    lowered = name.lower()
    return any(lowered.endswith(suffix) for suffix in ARCHIVE_SUFFIXES)


def require_archive_url(url: str) -> None:
    parsed = urllib.parse.urlparse(url)
    if parsed.scheme not in {"http", "https"}:
        raise CommandLineToolsError("download URL must use http or https")
    if not is_archive_name(parsed.path):
        raise CommandLineToolsError(
            "download URL must point to a Command Line Tools archive, not the Huawei download center page. "
            f"{DOWNLOAD_CENTER_LOGIN_HINT} Download center: {DIRECT_DOWNLOAD_HINT}"
        )


def sha256_file(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as handle:
        for chunk in iter(lambda: handle.read(1024 * 1024), b""):
            digest.update(chunk)
    return digest.hexdigest()


def verify_sha256(path: Path, expected: str | None) -> str:
    if not path.is_file():
        raise CommandLineToolsError(f"archive does not exist: {path}")
    actual = sha256_file(path)
    if expected and actual.lower() != expected.lower():
        raise CommandLineToolsError(f"sha256 mismatch for {path}: expected {expected}, got {actual}")
    return actual


def download_archive(url: str, output_dir: Path, filename: str | None = None, sha256: str | None = None) -> Path:
    require_archive_url(url)
    output_dir = output_dir.expanduser().resolve()
    output_dir.mkdir(parents=True, exist_ok=True)

    parsed = urllib.parse.urlparse(url)
    archive_name = filename or Path(urllib.parse.unquote(parsed.path)).name
    if not archive_name or not is_archive_name(archive_name):
        raise CommandLineToolsError("cannot infer archive filename; pass --filename with a supported archive suffix")

    destination = output_dir / archive_name
    try:
        with urllib.request.urlopen(url) as response, destination.open("wb") as output:
            shutil.copyfileobj(response, output)
    except OSError as error:
        raise CommandLineToolsError(f"download failed: {error}") from error

    verify_sha256(destination, sha256)
    return destination


def ensure_within_directory(root: Path, target: Path) -> None:
    root_real = root.resolve()
    target_real = target.resolve()
    if target_real != root_real and root_real not in target_real.parents:
        raise CommandLineToolsError(f"archive member escapes destination: {target}")


def safe_extract_zip(archive: Path, destination: Path) -> None:
    with zipfile.ZipFile(archive) as zip_file:
        for member in zip_file.infolist():
            target = destination / member.filename
            ensure_within_directory(destination, target)
        zip_file.extractall(destination)
        for member in zip_file.infolist():
            mode = member.external_attr >> 16
            if mode:
                extracted = destination / member.filename
                if extracted.exists():
                    extracted.chmod(mode)


def ensure_safe_force_target(install_root: Path) -> None:
    root_real = install_root.resolve()
    dangerous_roots = {Path("/").resolve(), Path.home().resolve(), Path.cwd().resolve()}
    if root_real in dangerous_roots:
        raise CommandLineToolsError(f"refusing to replace broad destination: {install_root}")


def safe_extract_tar(archive: Path, destination: Path) -> None:
    with tarfile.open(archive) as tar_file:
        for member in tar_file.getmembers():
            if member.issym() or member.islnk():
                raise CommandLineToolsError(f"archive link entries are not supported: {member.name}")
            target = destination / member.name
            ensure_within_directory(destination, target)
        tar_file.extractall(destination)


def prepare_install_root(install_root: Path, force: bool) -> Path:
    install_root = install_root.expanduser().resolve()
    if install_root.exists() and any(install_root.iterdir()):
        if not force:
            raise CommandLineToolsError(f"install root is not empty: {install_root}; pass --force to replace it")
        ensure_safe_force_target(install_root)
        shutil.rmtree(install_root)
    install_root.mkdir(parents=True, exist_ok=True)
    return install_root


def extract_archive(archive: Path, install_root: Path, force: bool = False) -> Path:
    archive = archive.expanduser().resolve()
    if not archive.is_file():
        raise CommandLineToolsError(f"archive does not exist: {archive}")
    if not is_archive_name(archive.name):
        raise CommandLineToolsError(f"unsupported archive format: {archive.name}")

    install_root = prepare_install_root(install_root, force)
    if archive.name.lower().endswith(".zip"):
        safe_extract_zip(archive, install_root)
    else:
        safe_extract_tar(archive, install_root)
    return install_root


def find_command_line_tools_root(search_root: Path) -> Path:
    search_root = search_root.expanduser().resolve()
    direct = search_root / "command-line-tools"
    candidates = []
    if search_root.name == "command-line-tools":
        candidates.append(search_root)
    candidates.append(direct)
    candidates.extend(path for path in search_root.glob("*/command-line-tools") if path.is_dir())

    for candidate in candidates:
        bin_dir = candidate / "bin"
        if bin_dir.is_dir():
            return candidate.resolve()

    raise CommandLineToolsError(f"cannot find command-line-tools/bin under {search_root}")


def infer_profile_path(profile: str | None) -> Path | None:
    if not profile:
        return None
    if profile != "auto":
        return Path(profile).expanduser().resolve()
    shell = os.environ.get("SHELL", "")
    if shell.endswith("zsh"):
        return Path.home() / ".zshrc"
    if shell.endswith("bash"):
        return Path.home() / ".bash_profile"
    return Path.home() / ".profile"


def build_profile_block(tools_root: Path, include_sdk_env: bool = False) -> str:
    tools_root = tools_root.expanduser().resolve()
    lines = [
        PROFILE_BEGIN,
        f'export HARMONY_COMMAND_LINE_TOOLS_HOME="{tools_root}"',
        'export PATH="$HARMONY_COMMAND_LINE_TOOLS_HOME/bin:$PATH"',
    ]
    sdk_root = tools_root / "sdk"
    if include_sdk_env and sdk_root.is_dir():
        lines.extend(
            [
                'export HOS_SDK_HOME="$HARMONY_COMMAND_LINE_TOOLS_HOME/sdk"',
                'export OHOS_BASE_SDK_HOME="$HOS_SDK_HOME/openharmony"',
                'export DEVECO_SDK_HOME="$HOS_SDK_HOME/harmonyos"',
            ]
        )
    lines.append(PROFILE_END)
    return "\n".join(lines) + "\n"


def update_profile(profile: Path, tools_root: Path, include_sdk_env: bool = False) -> None:
    profile = profile.expanduser().resolve()
    profile.parent.mkdir(parents=True, exist_ok=True)
    block = build_profile_block(tools_root, include_sdk_env)
    existing = profile.read_text(encoding="utf-8") if profile.exists() else ""

    begin_index = existing.find(PROFILE_BEGIN)
    end_index = existing.find(PROFILE_END)
    if begin_index != -1 and end_index != -1 and end_index > begin_index:
        end_index += len(PROFILE_END)
        updated = existing[:begin_index].rstrip() + "\n\n" + block + existing[end_index:].lstrip()
    else:
        updated = existing.rstrip() + "\n\n" + block if existing.strip() else block
    profile.write_text(updated, encoding="utf-8")


def configure_tools(tools_root: Path, profile: str | None, include_sdk_env: bool = False) -> InstallResult:
    tools_root = find_command_line_tools_root(tools_root)
    bin_dir = tools_root / "bin"
    profile_path = infer_profile_path(profile)
    source_command = None
    if profile_path:
        update_profile(profile_path, tools_root, include_sdk_env)
        source_command = f"source {profile_path}"
    return InstallResult(
        install_root=tools_root.parent,
        tools_root=tools_root,
        bin_dir=bin_dir,
        profile=profile_path,
        source_command=source_command,
    )


def install_archive(
    archive: Path,
    install_root: Path,
    sha256: str | None = None,
    force: bool = False,
    profile: str | None = None,
    include_sdk_env: bool = False,
) -> InstallResult:
    verify_sha256(archive.expanduser().resolve(), sha256)
    extracted_root = extract_archive(archive, install_root, force=force)
    return configure_tools(extracted_root, profile=profile, include_sdk_env=include_sdk_env)


def run_doctor(tools_root: Path) -> dict[str, object]:
    tools_root = find_command_line_tools_root(tools_root)
    bin_dir = tools_root / "bin"
    checks: dict[str, object] = {
        "toolsRoot": str(tools_root),
        "binDir": str(bin_dir),
        "exists": bin_dir.is_dir(),
        "tools": {},
    }
    tools = checks["tools"]
    assert isinstance(tools, dict)

    for name in ["codelinter", "hstack", "hvigorw", "ohpm"]:
        path = bin_dir / name
        tools[name] = {
            "path": str(path),
            "exists": path.exists(),
            "executable": os.access(path, os.X_OK),
        }

    codelinter = bin_dir / "codelinter"
    if codelinter.exists() and os.access(codelinter, os.X_OK):
        result = subprocess.run([str(codelinter), "-v"], capture_output=True, text=True, check=False)
        checks["codelinterVersion"] = (result.stdout or result.stderr).strip()
        checks["codelinterExitCode"] = result.returncode
    return checks


def build_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(description="Download and configure HarmonyOS Command Line Tools.")
    parser.add_argument("--json", action="store_true", help="Print machine-readable JSON")
    subparsers = parser.add_subparsers(dest="command", required=True)

    download_parser = subparsers.add_parser("download", help="Download a Command Line Tools archive from a direct URL")
    download_parser.add_argument("--url", required=True, help="Direct archive URL copied from Huawei download center")
    download_parser.add_argument("--output-dir", type=Path, default=Path.cwd(), help="Directory for the downloaded archive")
    download_parser.add_argument("--filename", help="Override downloaded archive filename")
    download_parser.add_argument("--sha256", help="Expected SHA256 from Huawei integrity check")
    download_parser.add_argument("--json", action="store_true", help="Print machine-readable JSON")

    install_parser = subparsers.add_parser("install", help="Verify, extract, and optionally configure a local archive")
    install_parser.add_argument("--archive", type=Path, required=True)
    install_parser.add_argument("--dest", type=Path, default=DEFAULT_INSTALL_ROOT)
    install_parser.add_argument("--sha256", help="Expected SHA256 from Huawei integrity check")
    install_parser.add_argument("--force", action="store_true", help="Replace a non-empty destination")
    install_parser.add_argument("--profile", help="Shell profile to update, or 'auto'")
    install_parser.add_argument("--include-sdk-env", action="store_true", help="Also export SDK env vars when sdk/ exists")
    install_parser.add_argument("--json", action="store_true", help="Print machine-readable JSON")

    bootstrap_parser = subparsers.add_parser("bootstrap", help="Download, extract, and configure in one command")
    bootstrap_parser.add_argument("--url", required=True, help="Direct archive URL copied from Huawei download center")
    bootstrap_parser.add_argument("--download-dir", type=Path, default=Path.cwd())
    bootstrap_parser.add_argument("--dest", type=Path, default=DEFAULT_INSTALL_ROOT)
    bootstrap_parser.add_argument("--filename")
    bootstrap_parser.add_argument("--sha256", help="Expected SHA256 from Huawei integrity check")
    bootstrap_parser.add_argument("--force", action="store_true", help="Replace a non-empty destination")
    bootstrap_parser.add_argument("--profile", help="Shell profile to update, or 'auto'")
    bootstrap_parser.add_argument("--include-sdk-env", action="store_true", help="Also export SDK env vars when sdk/ exists")
    bootstrap_parser.add_argument("--json", action="store_true", help="Print machine-readable JSON")

    configure_parser = subparsers.add_parser("configure", help="Configure PATH for an extracted Command Line Tools")
    configure_parser.add_argument("--tools-root", type=Path, required=True)
    configure_parser.add_argument("--profile", required=True, help="Shell profile to update, or 'auto'")
    configure_parser.add_argument("--include-sdk-env", action="store_true", help="Also export SDK env vars when sdk/ exists")
    configure_parser.add_argument("--json", action="store_true", help="Print machine-readable JSON")

    doctor_parser = subparsers.add_parser("doctor", help="Validate an extracted Command Line Tools layout")
    doctor_parser.add_argument("--tools-root", type=Path, required=True)
    doctor_parser.add_argument("--json", action="store_true", help="Print machine-readable JSON")

    return parser


def main(argv: list[str] | None = None) -> int:
    parser = build_parser()
    args = parser.parse_args(argv)
    try:
        if args.command == "download":
            archive = download_archive(args.url, args.output_dir, filename=args.filename, sha256=args.sha256)
            payload = {"downloaded": str(archive), "sha256": sha256_file(archive)}
        elif args.command == "install":
            result = install_archive(args.archive, args.dest, args.sha256, args.force, args.profile, args.include_sdk_env)
            payload = {"installed": result.to_json()}
        elif args.command == "bootstrap":
            archive = download_archive(args.url, args.download_dir, filename=args.filename, sha256=args.sha256)
            result = install_archive(archive, args.dest, None, args.force, args.profile, args.include_sdk_env)
            payload = {"downloaded": str(archive), "sha256": sha256_file(archive), "installed": result.to_json()}
        elif args.command == "configure":
            result = configure_tools(args.tools_root, args.profile, args.include_sdk_env)
            payload = {"configured": result.to_json()}
        elif args.command == "doctor":
            payload = {"doctor": run_doctor(args.tools_root)}
        else:
            parser.error(f"Unknown command: {args.command}")
            return 2

        if args.json:
            print_json(payload)
        else:
            print(json.dumps(payload, ensure_ascii=False))
        return 0
    except CommandLineToolsError as error:
        payload = {"decision": "blocked", "error": str(error)}
        if getattr(args, "json", False):
            print_json(payload)
        else:
            print(f"blocked: {error}", file=sys.stderr)
        return 2


if __name__ == "__main__":
    raise SystemExit(main())
