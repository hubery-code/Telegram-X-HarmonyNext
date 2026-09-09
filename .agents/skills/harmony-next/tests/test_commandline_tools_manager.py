from __future__ import annotations

import importlib.util
import json
import os
import subprocess
import sys
import tempfile
import unittest
import zipfile
from pathlib import Path


SCRIPT_PATH = Path(__file__).resolve().parents[1] / "scripts" / "commandline_tools_manager.py"
SPEC = importlib.util.spec_from_file_location("commandline_tools_manager", SCRIPT_PATH)
MODULE = importlib.util.module_from_spec(SPEC)
assert SPEC.loader is not None
sys.modules[SPEC.name] = MODULE
SPEC.loader.exec_module(MODULE)


class CommandLineToolsManagerTests(unittest.TestCase):
    def setUp(self) -> None:
        self.temp_dir = tempfile.TemporaryDirectory()
        self.root = Path(self.temp_dir.name)
        self.archive = self.root / "command-line-tools.zip"
        self.profile = self.root / ".zshrc"
        self.dest = self.root / "install"
        self.create_archive(self.archive)

    def tearDown(self) -> None:
        self.temp_dir.cleanup()

    def create_archive(self, archive: Path) -> None:
        with zipfile.ZipFile(archive, "w") as zip_file:
            for name in ["codelinter", "hstack", "hvigorw", "ohpm"]:
                info = zipfile.ZipInfo(f"command-line-tools/bin/{name}")
                info.external_attr = 0o755 << 16
                zip_file.writestr(info, f"#!/bin/sh\necho {name} 1.0\n")
            zip_file.writestr("command-line-tools/sdk/openharmony/.keep", "")
            zip_file.writestr("command-line-tools/sdk/harmonyos/.keep", "")

    def make_executable(self, path: Path) -> None:
        path.chmod(path.stat().st_mode | 0o111)

    def test_install_archive_extracts_tools_and_updates_profile(self) -> None:
        result = subprocess.run(
            [
                sys.executable,
                str(SCRIPT_PATH),
                "install",
                "--archive",
                str(self.archive),
                "--dest",
                str(self.dest),
                "--profile",
                str(self.profile),
                "--include-sdk-env",
                "--json",
            ],
            check=True,
            capture_output=True,
            text=True,
        )

        payload = json.loads(result.stdout)
        tools_root = self.dest / "command-line-tools"
        profile_text = self.profile.read_text(encoding="utf-8")

        self.assertEqual(payload["installed"]["toolsRoot"], str(tools_root.resolve()))
        self.assertTrue((tools_root / "bin" / "codelinter").is_file())
        self.assertTrue(os.access(tools_root / "bin" / "codelinter", os.X_OK))
        self.assertIn("harmony-next command-line-tools", profile_text)
        self.assertIn('export HARMONY_COMMAND_LINE_TOOLS_HOME="', profile_text)
        self.assertIn('export PATH="$HARMONY_COMMAND_LINE_TOOLS_HOME/bin:$PATH"', profile_text)
        self.assertIn('export HOS_SDK_HOME="$HARMONY_COMMAND_LINE_TOOLS_HOME/sdk"', profile_text)

    def test_configure_replaces_existing_profile_block(self) -> None:
        tools_root = self.dest / "command-line-tools"
        MODULE.extract_archive(self.archive, self.dest)
        self.profile.write_text(
            "\n".join(
                [
                    "export BEFORE=1",
                    MODULE.PROFILE_BEGIN,
                    'export HARMONY_COMMAND_LINE_TOOLS_HOME="/old"',
                    MODULE.PROFILE_END,
                    "export AFTER=1",
                    "",
                ]
            ),
            encoding="utf-8",
        )

        MODULE.configure_tools(tools_root, str(self.profile))
        profile_text = self.profile.read_text(encoding="utf-8")

        self.assertEqual(profile_text.count(MODULE.PROFILE_BEGIN), 1)
        self.assertNotIn("/old", profile_text)
        self.assertIn("export BEFORE=1", profile_text)
        self.assertIn("export AFTER=1", profile_text)
        self.assertIn(str(tools_root.resolve()), profile_text)

    def test_doctor_reports_codelinter_version(self) -> None:
        MODULE.extract_archive(self.archive, self.dest)
        tools_root = self.dest / "command-line-tools"
        for tool in (tools_root / "bin").iterdir():
            self.make_executable(tool)

        result = MODULE.run_doctor(tools_root)

        self.assertTrue(result["exists"])
        self.assertEqual(result["codelinterExitCode"], 0)
        self.assertEqual(result["codelinterVersion"], "codelinter 1.0")

    def test_download_rejects_download_center_page_url(self) -> None:
        result = subprocess.run(
            [
                sys.executable,
                str(SCRIPT_PATH),
                "download",
                "--url",
                "https://developer.huawei.com/consumer/cn/download/command-line-tools-for-hmos",
                "--output-dir",
                str(self.root),
                "--json",
            ],
            check=False,
            capture_output=True,
            text=True,
        )

        self.assertEqual(result.returncode, 2)
        payload = json.loads(result.stdout)
        self.assertEqual(payload["decision"], "blocked")
        self.assertIn("actual archive link", payload["error"])
        self.assertIn("authenticated browser session", payload["error"])
        self.assertIn("install --archive", payload["error"])

    def test_install_refuses_sha256_mismatch(self) -> None:
        result = subprocess.run(
            [
                sys.executable,
                str(SCRIPT_PATH),
                "install",
                "--archive",
                str(self.archive),
                "--dest",
                str(self.dest),
                "--sha256",
                "0" * 64,
                "--json",
            ],
            check=False,
            capture_output=True,
            text=True,
        )

        self.assertEqual(result.returncode, 2)
        payload = json.loads(result.stdout)
        self.assertEqual(payload["decision"], "blocked")
        self.assertIn("sha256 mismatch", payload["error"])

    def test_zip_path_traversal_is_blocked(self) -> None:
        archive = self.root / "evil.zip"
        with zipfile.ZipFile(archive, "w") as zip_file:
            zip_file.writestr("../evil", "nope")

        with self.assertRaisesRegex(MODULE.CommandLineToolsError, "escapes destination"):
            MODULE.extract_archive(archive, self.dest)

        self.assertFalse((self.root / "evil").exists())

    def test_force_refuses_broad_destination(self) -> None:
        with self.assertRaisesRegex(MODULE.CommandLineToolsError, "broad destination"):
            MODULE.prepare_install_root(Path.cwd(), force=True)


if __name__ == "__main__":
    unittest.main()
