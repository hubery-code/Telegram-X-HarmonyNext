from __future__ import annotations

import json
import os
import sqlite3
import subprocess
import sys
import tempfile
import textwrap
import unittest
from pathlib import Path


SCRIPT_PATH = Path(__file__).resolve().parents[1] / "scripts" / "profiler_trace_audit.py"


class ProfilerTraceAuditTests(unittest.TestCase):
    def setUp(self) -> None:
        self.temp_dir = tempfile.TemporaryDirectory()
        self.root = Path(self.temp_dir.name)
        self.trace = self.root / "input.ftrace"
        self.trace.write_text("# synthetic trace\n", encoding="utf-8")
        self.template_db = self.root / "template.db"
        self.fake_streamer = self.root / "trace_streamer"
        self.create_template_database(self.template_db)
        self.create_fake_trace_streamer(self.fake_streamer)

    def tearDown(self) -> None:
        self.temp_dir.cleanup()

    def create_template_database(self, path: Path) -> None:
        connection = sqlite3.connect(path)
        try:
            connection.executescript(
                """
                create table meta(name text, value text);
                insert into meta values('parse_tool', 'trace_streamer');
                insert into meta values('tool_version', '4.3.7');
                insert into meta values('source_type', 'txt-based-trace');
                create table trace_range(start_ts integer, end_ts integer);
                insert into trace_range values(1000000000000, 1000083000000);
                create table process(id integer, pid integer, name text);
                insert into process values(1, 123, 'app');
                insert into process values(2, 456, 'render');
                create table thread(id integer, tid integer, name text);
                insert into thread values(1, 123, 'main');
                insert into thread values(2, 124, 'render');
                create table callstack(id integer, ts integer, dur integer, name text);
                insert into callstack values(1, 1000000000000, 16000000, 'renderFrame');
                insert into callstack values(2, 1000020000000, 50000000, 'slowLayout');
                create table frame_slice(id integer, ts integer, dur integer, name text);
                insert into frame_slice values(1, 1000000000000, 17000000, 'frame-1');
                """
            )
            connection.commit()
        finally:
            connection.close()

    def create_fake_trace_streamer(self, path: Path) -> None:
        path.write_text(
            textwrap.dedent(
                """\
                #!/usr/bin/env python3
                import os
                import shutil
                import sys

                if "-v" in sys.argv:
                    print("version 4.3.7")
                    sys.exit(1)
                if "--list" in sys.argv:
                    print("the enable ability list:")
                    print("\\thtrace")
                    print("\\tbytrace")
                    sys.exit(0)
                if "-e" not in sys.argv:
                    print("missing -e", file=sys.stderr)
                    sys.exit(2)
                output = sys.argv[sys.argv.index("-e") + 1]
                shutil.copyfile(os.environ["FAKE_TRACE_DB"], output)
                print("ParserDuration:\\t1 ms")
                sys.exit(0)
                """
            ),
            encoding="utf-8",
        )
        path.chmod(0o755)

    def test_doctor_reports_fake_trace_streamer(self) -> None:
        result = subprocess.run(
            [
                sys.executable,
                str(SCRIPT_PATH),
                "doctor",
                "--trace-streamer",
                str(self.fake_streamer),
                "--json",
            ],
            check=True,
            capture_output=True,
            text=True,
        )

        payload = json.loads(result.stdout)
        self.assertEqual(payload["decision"], "allowed")
        self.assertEqual(payload["traceStreamer"]["version"], "version 4.3.7")
        self.assertIn("htrace", payload["traceStreamer"]["abilities"])

    def test_audit_generates_sqlite_and_json_evidence(self) -> None:
        output_dir = self.root / "audit"
        env = {**os.environ, "FAKE_TRACE_DB": str(self.template_db)}

        result = subprocess.run(
            [
                sys.executable,
                str(SCRIPT_PATH),
                "audit",
                "--trace-streamer",
                str(self.fake_streamer),
                "--input",
                str(self.trace),
                "--output-dir",
                str(output_dir),
                "--json",
            ],
            check=True,
            capture_output=True,
            text=True,
            env=env,
        )

        payload = json.loads(result.stdout)
        self.assertEqual(payload["decision"], "analyzed")
        self.assertEqual(payload["counts"]["callstack"], 2)
        self.assertEqual(payload["topCallstack"][0]["name"], "slowLayout")
        self.assertEqual(payload["thresholds"][0]["count"], 1)
        self.assertTrue((output_dir / "trace.db").is_file())
        self.assertTrue((output_dir / "summary.json").is_file())
        self.assertTrue((output_dir / "spans_over_16_67ms.json").is_file())
        self.assertTrue((output_dir / "trace_streamer.stdout").is_file())

    def test_audit_refuses_output_inside_app_bundle(self) -> None:
        output_dir = self.root / "DevEco-Studio.app" / "Contents" / "audit"
        env = {**os.environ, "FAKE_TRACE_DB": str(self.template_db)}

        result = subprocess.run(
            [
                sys.executable,
                str(SCRIPT_PATH),
                "audit",
                "--trace-streamer",
                str(self.fake_streamer),
                "--input",
                str(self.trace),
                "--output-dir",
                str(output_dir),
                "--json",
            ],
            check=False,
            capture_output=True,
            text=True,
            env=env,
        )

        payload = json.loads(result.stdout)
        self.assertEqual(result.returncode, 2)
        self.assertEqual(payload["decision"], "blocked")
        self.assertIn(".app bundle", payload["error"])


if __name__ == "__main__":
    unittest.main()
