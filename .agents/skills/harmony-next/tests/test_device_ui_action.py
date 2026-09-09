from __future__ import annotations

import json
import os
import subprocess
import sys
import tempfile
import textwrap
import unittest
from pathlib import Path


SCRIPT_PATH = Path(__file__).resolve().parents[1] / "scripts" / "device_ui_action.py"


class DeviceUiActionTests(unittest.TestCase):
    def setUp(self) -> None:
        self.temp_dir = tempfile.TemporaryDirectory()
        self.root = Path(self.temp_dir.name)
        self.remote_root = self.root / "remote"
        self.remote_root.mkdir()
        self.fake_hdc = self.root / "hdc"
        self.fake_hdc.write_text(
            textwrap.dedent(
                """\
                #!/usr/bin/env python3
                import json
                import os
                import shutil
                import struct
                import sys
                from pathlib import Path

                args = sys.argv[1:]
                remote_root = Path(os.environ["FAKE_HDC_REMOTE_ROOT"])
                clicked = remote_root / "clicked"

                def remote_file(remote):
                    return remote_root / remote.strip("/").replace("/", "_")

                if args == ["-v"]:
                    print("Ver: 3.1.0")
                    raise SystemExit(0)
                if args[:2] == ["list", "targets"]:
                    print("127.0.0.1:10100 TCP Connected localhost")
                    raise SystemExit(0)
                if len(args) < 3 or args[0] != "-t":
                    raise SystemExit(2)

                rest = args[2:]
                if rest[:2] == ["file", "recv"]:
                    shutil.copyfile(remote_file(rest[2]), Path(rest[3]))
                    raise SystemExit(0)
                if rest[0] != "shell":
                    raise SystemExit(2)
                shell = rest[1:]
                if shell[:2] == ["uitest", "dumpLayout"]:
                    remote = shell[shell.index("-p") + 1]
                    children = [
                        {
                            "type": "Button",
                            "id": "smoke-increment",
                            "text": "Tapped" if clicked.exists() else "Tap me",
                            "bounds": "[100,200][300,300]",
                        }
                    ]
                    if os.environ.get("FAKE_HDC_DUPLICATE_TEXT"):
                        children.append(
                            {
                                "type": "Button",
                                "id": "smoke-increment-secondary",
                                "text": "Tap me",
                                "bounds": "[400,200][600,300]",
                            }
                        )
                    remote_file(remote).write_text(
                        json.dumps(
                            {
                                "bundleName": "com.example",
                                "type": "Window",
                                "bounds": "[0,0][1080,1920]",
                                "children": children,
                            }
                        ),
                        encoding="utf-8",
                    )
                    print("No Error")
                    raise SystemExit(0)
                if shell[:2] == ["uitest", "screenCap"]:
                    remote = shell[shell.index("-p") + 1]
                    png = b"\\x89PNG\\r\\n\\x1a\\n" + struct.pack(">I", 13) + b"IHDR" + struct.pack(">II", 1080, 1920)
                    remote_file(remote).write_bytes(png)
                    print("No Error")
                    raise SystemExit(0)
                if shell[:4] == ["uitest", "uiInput", "click", "200"] and shell[4] == "250":
                    clicked.write_text("yes", encoding="utf-8")
                    print("No Error")
                    raise SystemExit(0)
                if shell[:2] == ["hilog", "-z"]:
                    print("bounded synthetic log")
                    raise SystemExit(0)
                if shell[:2] == ["rm", "-f"]:
                    for remote in shell[2:]:
                        path = remote_file(remote)
                        if path.exists():
                            path.unlink()
                    raise SystemExit(0)
                print("unknown: " + " ".join(shell), file=sys.stderr)
                raise SystemExit(2)
                """
            ),
            encoding="utf-8",
        )
        self.fake_hdc.chmod(0o755)
        self.env = {**os.environ, "FAKE_HDC_REMOTE_ROOT": str(self.remote_root)}

    def tearDown(self) -> None:
        self.temp_dir.cleanup()

    def test_tap_resolves_layout_bounds_and_captures_before_after(self) -> None:
        artifact_dir = self.root / "artifacts"
        result = subprocess.run(
            [
                sys.executable,
                str(SCRIPT_PATH),
                "tap",
                "--hdc",
                str(self.fake_hdc),
                "--artifact-dir",
                str(artifact_dir),
                "--text",
                "Tap me",
                "--settle-seconds",
                "0",
                "--json",
            ],
            check=False,
            capture_output=True,
            text=True,
            env=self.env,
        )

        payload = json.loads(result.stdout)
        after_layout = json.loads((artifact_dir / "after-layout.json").read_text(encoding="utf-8"))
        self.assertEqual(result.returncode, 0)
        self.assertEqual(payload["decision"], "completed")
        self.assertEqual(payload["action"]["source"], "dumpLayout-bounds")
        self.assertEqual(payload["action"]["point"], {"x": 200, "y": 250})
        self.assertEqual(payload["coordinateSpace"]["width"], 1080)
        self.assertEqual(after_layout["children"][0]["text"], "Tapped")
        self.assertTrue((artifact_dir / "before-screen.png").is_file())
        self.assertTrue((artifact_dir / "after-screen.png").is_file())
        self.assertTrue((artifact_dir / "command_ledger.json").is_file())

    def test_tap_blocks_without_exactly_one_target(self) -> None:
        artifact_dir = self.root / "missing-target"
        result = subprocess.run(
            [
                sys.executable,
                str(SCRIPT_PATH),
                "tap",
                "--hdc",
                str(self.fake_hdc),
                "--artifact-dir",
                str(artifact_dir),
                "--settle-seconds",
                "0",
                "--json",
            ],
            check=False,
            capture_output=True,
            text=True,
            env=self.env,
        )

        payload = json.loads(result.stdout)
        self.assertEqual(result.returncode, 2)
        self.assertEqual(payload["decision"], "blocked")
        self.assertIn("actionTarget", payload["missingConfig"])

    def test_tap_ambiguous_selector_cleans_remote_files_and_writes_ledger(self) -> None:
        artifact_dir = self.root / "ambiguous"
        env = {**self.env, "FAKE_HDC_DUPLICATE_TEXT": "1"}
        result = subprocess.run(
            [
                sys.executable,
                str(SCRIPT_PATH),
                "tap",
                "--hdc",
                str(self.fake_hdc),
                "--artifact-dir",
                str(artifact_dir),
                "--text",
                "Tap me",
                "--settle-seconds",
                "0",
                "--json",
            ],
            check=False,
            capture_output=True,
            text=True,
            env=env,
        )

        payload = json.loads(result.stdout)
        ledger = json.loads((artifact_dir / "command_ledger.json").read_text(encoding="utf-8"))
        self.assertEqual(result.returncode, 2)
        self.assertEqual(payload["decision"], "blocked")
        self.assertIn("matchIndex", payload["missingConfig"])
        self.assertTrue(any(item["purpose"] == "cleanup.remote-artifacts" for item in ledger))
        self.assertEqual(list(self.remote_root.iterdir()), [])


if __name__ == "__main__":
    unittest.main()
