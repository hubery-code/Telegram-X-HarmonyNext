#!/usr/bin/env python3
from __future__ import annotations

import argparse
import json
import os
import platform
import re
import shutil
import sqlite3
import subprocess
import sys
import tempfile
import time
from dataclasses import dataclass
from pathlib import Path


TRACE_STREAMER_RELATIVE_PATH = Path("Contents") / "tools" / "profiler" / "dic_server" / "trace_streamer"
DEFAULT_OUTPUT_ROOT = Path(".hvigor") / "outputs"
TRACE_STREAMER_ENV_KEYS = ["DEVECO_TRACE_STREAMER", "HARMONY_TRACE_STREAMER", "TRACE_STREAMER"]
DEVECO_APP_ENV_KEYS = ["DEVECO_STUDIO_APP", "DEVECO_APP", "HARMONY_DEVECO_APP"]
DEFAULT_THRESHOLDS_MS = [16.67, 33.34]


class ProfilerTraceAuditError(RuntimeError):
    def __init__(self, message: str, payload: dict[str, object] | None = None) -> None:
        super().__init__(message)
        self.payload = payload


@dataclass(frozen=True)
class ToolProbe:
    path: Path | None
    source: str
    exists: bool
    executable: bool
    version: str | None = None
    abilities: str | None = None

    def to_json(self) -> dict[str, object]:
        return {
            "path": str(self.path) if self.path else None,
            "source": self.source,
            "exists": self.exists,
            "executable": self.executable,
            "version": self.version,
            "abilities": self.abilities,
        }


def print_json(payload: object) -> None:
    print(json.dumps(payload, ensure_ascii=False, indent=2))


def first_env_path(keys: list[str]) -> tuple[Path | None, str | None]:
    for key in keys:
        value = os.environ.get(key)
        if value:
            return Path(value).expanduser(), key
    return None, None


def dedupe_candidates(candidates: list[tuple[Path, str]]) -> list[tuple[Path, str]]:
    seen: set[str] = set()
    deduped: list[tuple[Path, str]] = []
    for path, source in candidates:
        key = str(path.expanduser())
        if key not in seen:
            seen.add(key)
            deduped.append((path, source))
    return deduped


def trace_streamer_from_deveco_app(path: Path) -> Path:
    expanded = path.expanduser()
    if expanded.name == "Contents":
        return expanded / "tools" / "profiler" / "dic_server" / "trace_streamer"
    return expanded / TRACE_STREAMER_RELATIVE_PATH


def candidate_trace_streamers(trace_streamer: Path | None = None, deveco_app: Path | None = None) -> list[tuple[Path, str]]:
    candidates: list[tuple[Path, str]] = []
    if trace_streamer:
        candidates.append((trace_streamer, "arg:trace-streamer"))

    env_tool, env_tool_key = first_env_path(TRACE_STREAMER_ENV_KEYS)
    if env_tool and env_tool_key:
        candidates.append((env_tool, f"env:{env_tool_key}"))

    if deveco_app:
        candidates.append((trace_streamer_from_deveco_app(deveco_app), "arg:deveco-app"))

    env_app, env_app_key = first_env_path(DEVECO_APP_ENV_KEYS)
    if env_app and env_app_key:
        candidates.append((trace_streamer_from_deveco_app(env_app), f"env:{env_app_key}"))

    if platform.system() == "Darwin":
        candidates.append((Path("/Applications/DevEco-Studio.app") / TRACE_STREAMER_RELATIVE_PATH, "macos:default-app"))
    else:
        candidates.extend(
            [
                (Path("/opt/DevEco-Studio") / TRACE_STREAMER_RELATIVE_PATH.relative_to("Contents"), "linux:/opt"),
                (Path("/opt/deveco-studio") / TRACE_STREAMER_RELATIVE_PATH.relative_to("Contents"), "linux:/opt"),
            ]
        )

    resolved = shutil.which("trace_streamer")
    if resolved:
        candidates.append((Path(resolved), "path:trace_streamer"))
    return dedupe_candidates(candidates)


def probe_trace_streamer(trace_streamer: Path | None = None, deveco_app: Path | None = None) -> ToolProbe:
    fallback_path: Path | None = None
    fallback_source = "not-found"
    for path, source in candidate_trace_streamers(trace_streamer, deveco_app):
        expanded = path.expanduser()
        if fallback_path is None:
            fallback_path = expanded
            fallback_source = source
        if expanded.exists():
            resolved = expanded.resolve()
            executable = os.access(resolved, os.X_OK)
            version = run_probe_command([str(resolved), "-v"]).strip() if executable else None
            abilities = run_probe_command([str(resolved), "--list"]).strip() if executable else None
            return ToolProbe(
                path=resolved,
                source=source,
                exists=True,
                executable=executable,
                version=version or None,
                abilities=abilities or None,
            )
    return ToolProbe(path=fallback_path, source=fallback_source, exists=False, executable=False)


def run_probe_command(command: list[str]) -> str:
    try:
        result = subprocess.run(command, capture_output=True, text=True, timeout=10, check=False)
    except (OSError, subprocess.TimeoutExpired) as error:
        return str(error)
    return (result.stdout or result.stderr or "").strip()


def block(message: str, missing_config: list[str] | None = None, **extra: object) -> None:
    payload: dict[str, object] = {
        "decision": "blocked",
        "error": message,
        "missingConfig": missing_config or [],
    }
    payload.update(extra)
    raise ProfilerTraceAuditError(message, payload)


def timestamp() -> str:
    return time.strftime("%Y%m%d-%H%M%S")


def ensure_not_inside_app_bundle(path: Path) -> None:
    expanded = path.expanduser()
    for part in expanded.parts:
        if part.endswith(".app"):
            block(
                "refusing to write profiler audit artifacts inside an .app bundle; choose an external artifact directory",
                missing_config=["outputDir"],
                outputDir=str(expanded),
            )


def prepare_output_dir(output_dir: Path | None, force: bool, db_name: str) -> Path:
    if output_dir:
        target = output_dir.expanduser()
    else:
        target = DEFAULT_OUTPUT_ROOT / f"profiler-trace-audit-{timestamp()}"
    ensure_not_inside_app_bundle(target)
    target = target.resolve()
    target.mkdir(parents=True, exist_ok=True)
    database = target / db_name
    if database.exists() and not force:
        block(f"database already exists: {database}; pass --force or choose a new --output-dir", missing_config=["outputDir"])
    return target


def should_use_arch_x86_64(trace_streamer: Path, arch_mode: str) -> bool:
    if arch_mode == "never":
        return False
    if arch_mode == "x86_64":
        return True
    if platform.system() != "Darwin" or platform.machine() not in {"arm64", "aarch64"}:
        return False
    try:
        result = subprocess.run(["file", str(trace_streamer)], capture_output=True, text=True, timeout=5, check=False)
    except (OSError, subprocess.TimeoutExpired):
        return False
    return "Mach-O 64-bit executable x86_64" in result.stdout


def build_trace_streamer_command(
    trace_streamer: Path,
    input_trace: Path,
    database: Path,
    log_level: str,
    arch_mode: str,
) -> list[str]:
    command = [str(trace_streamer), str(input_trace), "-e", str(database), "-l", log_level]
    if should_use_arch_x86_64(trace_streamer, arch_mode):
        return ["/usr/bin/arch", "-x86_64", *command]
    return command


def run_trace_streamer(
    trace_streamer: Path,
    input_trace: Path,
    database: Path,
    output_dir: Path,
    log_level: str,
    timeout_seconds: float,
    arch_mode: str,
) -> dict[str, object]:
    command = build_trace_streamer_command(trace_streamer, input_trace, database, log_level, arch_mode)
    try:
        result = subprocess.run(command, capture_output=True, text=True, timeout=timeout_seconds, check=False)
    except subprocess.TimeoutExpired as error:
        block(
            f"trace_streamer timed out after {timeout_seconds:g}s",
            missing_config=[],
            command=command,
            stdout=(error.stdout or "")[:4000] if isinstance(error.stdout, str) else "",
            stderr=(error.stderr or "")[:4000] if isinstance(error.stderr, str) else "",
        )
    except OSError as error:
        block(f"failed to execute trace_streamer: {error}", missing_config=["traceStreamer"], command=command)

    stdout_path = output_dir / "trace_streamer.stdout"
    stderr_path = output_dir / "trace_streamer.stderr"
    stdout_path.write_text(result.stdout or "", encoding="utf-8")
    stderr_path.write_text(result.stderr or "", encoding="utf-8")

    run_info: dict[str, object] = {
        "command": command,
        "exitCode": result.returncode,
        "stdout": str(stdout_path),
        "stderr": str(stderr_path),
    }
    if result.returncode != 0:
        block(
            f"trace_streamer failed with exit code {result.returncode}",
            missing_config=[],
            traceStreamer=run_info,
            stdoutSnippet=(result.stdout or "")[-4000:],
            stderrSnippet=(result.stderr or "")[-4000:],
        )
    if not database.is_file():
        block("trace_streamer completed but did not create the SQLite database", missing_config=[], traceStreamer=run_info)
    return run_info


def write_json(path: Path, payload: object) -> None:
    path.write_text(json.dumps(payload, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")


def table_names(connection: sqlite3.Connection) -> list[str]:
    rows = connection.execute("select name from sqlite_master where type='table' order by name").fetchall()
    return [str(row[0]) for row in rows]


def table_columns(connection: sqlite3.Connection, table: str) -> set[str]:
    if table not in table_names(connection):
        return set()
    rows = connection.execute(f'pragma table_info("{table}")').fetchall()
    return {str(row[1]) for row in rows}


def query_rows(connection: sqlite3.Connection, sql: str, params: tuple[object, ...] = ()) -> list[dict[str, object]]:
    connection.row_factory = sqlite3.Row
    rows = connection.execute(sql, params).fetchall()
    return [dict(row) for row in rows]


def query_table_count(connection: sqlite3.Connection, table: str) -> int | None:
    if table not in table_names(connection):
        return None
    row = connection.execute(f'select count(*) from "{table}"').fetchone()
    return int(row[0])


def threshold_slug(threshold_ms: float) -> str:
    rendered = f"{threshold_ms:g}".replace(".", "_")
    return re.sub(r"[^0-9A-Za-z_]+", "_", rendered)


def summarize_database(database: Path, output_dir: Path, thresholds_ms: list[float]) -> dict[str, object]:
    connection = sqlite3.connect(database)
    try:
        tables = table_names(connection)
        (output_dir / "tables.txt").write_text("\n".join(tables) + "\n", encoding="utf-8")

        meta = query_rows(connection, "select name,value from meta order by name") if "meta" in tables else []
        trace_range = (
            query_rows(connection, "select start_ts,end_ts,(end_ts-start_ts) as dur_ns from trace_range")
            if "trace_range" in tables
            else []
        )
        counts = {
            "process": query_table_count(connection, "process"),
            "thread": query_table_count(connection, "thread"),
            "callstack": query_table_count(connection, "callstack"),
            "frameSlice": query_table_count(connection, "frame_slice"),
        }

        top_callstack: list[dict[str, object]] = []
        threshold_summaries: list[dict[str, object]] = []
        callstack_columns = table_columns(connection, "callstack")
        if {"name", "dur"}.issubset(callstack_columns):
            top_callstack = query_rows(
                connection,
                "select name,dur,round(dur/1000000.0,3) as dur_ms from callstack order by dur desc limit 20",
            )
            for threshold_ms in thresholds_ms:
                threshold_ns = int(threshold_ms * 1_000_000)
                spans = query_rows(
                    connection,
                    "select name,dur,round(dur/1000000.0,3) as dur_ms from callstack where dur >= ? order by dur desc",
                    (threshold_ns,),
                )
                file_name = f"spans_over_{threshold_slug(threshold_ms)}ms.json"
                write_json(output_dir / file_name, spans)
                threshold_summaries.append(
                    {"thresholdMs": threshold_ms, "thresholdNs": threshold_ns, "count": len(spans), "file": file_name}
                )

        frame_slice: dict[str, object] = {"count": counts["frameSlice"]}
        frame_columns = table_columns(connection, "frame_slice")
        if counts["frameSlice"] and "dur" in frame_columns:
            name_expr = "name" if "name" in frame_columns else "id"
            frame_slice["top"] = query_rows(
                connection,
                f"select {name_expr} as name,dur,round(dur/1000000.0,3) as dur_ms from frame_slice order by dur desc limit 20",
            )

        files = {
            "tables": "tables.txt",
            "meta": "meta.json",
            "traceRange": "trace_range.json",
            "counts": "counts.json",
            "topCallstack": "top_callstack.json",
            "frameSlice": "frame_slice.json",
        }
        write_json(output_dir / files["meta"], meta)
        write_json(output_dir / files["traceRange"], trace_range)
        write_json(output_dir / files["counts"], counts)
        write_json(output_dir / files["topCallstack"], top_callstack)
        write_json(output_dir / files["frameSlice"], frame_slice)

        return {
            "tables": tables,
            "meta": meta,
            "traceRange": trace_range,
            "counts": counts,
            "topCallstack": top_callstack,
            "thresholds": threshold_summaries,
            "frameSlice": frame_slice,
            "files": files,
        }
    finally:
        connection.close()


def audit_trace_file(args: argparse.Namespace) -> dict[str, object]:
    input_trace = args.input.expanduser().resolve()
    if not input_trace.is_file():
        block(f"trace input does not exist: {input_trace}", missing_config=["input"])

    probe = probe_trace_streamer(args.trace_streamer, args.deveco_app)
    if not probe.exists:
        block(
            f"trace_streamer was not found: {probe.path}",
            missing_config=["traceStreamer"],
            traceStreamer=probe.to_json(),
        )
    if not probe.executable:
        block(
            f"trace_streamer is not executable: {probe.path}",
            missing_config=["traceStreamerExecutable"],
            traceStreamer=probe.to_json(),
        )
    assert probe.path is not None

    output_dir = prepare_output_dir(args.output_dir, args.force, args.db_name)
    database = output_dir / args.db_name
    if database.exists() and args.force:
        database.unlink()

    trace_streamer_run = run_trace_streamer(
        trace_streamer=probe.path,
        input_trace=input_trace,
        database=database,
        output_dir=output_dir,
        log_level=args.log_level,
        timeout_seconds=args.timeout,
        arch_mode=args.arch_mode,
    )
    summary = summarize_database(database, output_dir, args.threshold_ms)
    payload: dict[str, object] = {
        "decision": "analyzed",
        "operation": "profiler.trace.offline-audit",
        "input": str(input_trace),
        "outputDir": str(output_dir),
        "database": str(database),
        "traceStreamer": probe.to_json(),
        "traceStreamerRun": trace_streamer_run,
        **summary,
    }
    summary_path = output_dir / "summary.json"
    payload["summary"] = str(summary_path)
    write_json(summary_path, payload)
    return payload


def run_doctor(args: argparse.Namespace) -> tuple[int, dict[str, object]]:
    probe = probe_trace_streamer(args.trace_streamer, args.deveco_app)
    missing_config: list[str] = []
    issues: list[str] = []
    if not probe.exists:
        missing_config.append("traceStreamer")
        issues.append("trace_streamer was not found")
    elif not probe.executable:
        missing_config.append("traceStreamerExecutable")
        issues.append("trace_streamer exists but is not executable")

    payload: dict[str, object] = {
        "decision": "allowed" if not missing_config else "blocked",
        "operation": "profiler.trace.doctor",
        "traceStreamer": probe.to_json(),
        "missingConfig": missing_config,
        "issues": issues,
        "recommendations": [
            "Pass --deveco-app <DevEco-Studio.app> or --trace-streamer <path> when DevEco Studio is installed outside the default location.",
            "Write audit artifacts to .hvigor/outputs or another directory outside the DevEco .app bundle.",
        ],
    }
    return (0 if not missing_config else 2), payload


def add_tool_arguments(parser: argparse.ArgumentParser) -> None:
    parser.add_argument("--deveco-app", type=Path, help="Path to DevEco-Studio.app or its Contents directory")
    parser.add_argument("--trace-streamer", type=Path, help="Path to tools/profiler/dic_server/trace_streamer")


def build_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(description="Offline DevEco trace_streamer audit for HarmonyOS profiler traces.")
    subparsers = parser.add_subparsers(dest="command", required=True)

    doctor = subparsers.add_parser("doctor", help="Locate and validate DevEco trace_streamer")
    add_tool_arguments(doctor)
    doctor.add_argument("--json", action="store_true", help="Print machine-readable JSON")

    audit = subparsers.add_parser("audit", help="Convert a trace file to SQLite and emit JSON performance evidence")
    add_tool_arguments(audit)
    audit.add_argument("--input", type=Path, required=True, help="Input .ftrace/.htrace/bytrace/rawtrace file")
    audit.add_argument("--output-dir", type=Path, help="Artifact directory; defaults to .hvigor/outputs/profiler-trace-audit-*")
    audit.add_argument("--db-name", default="trace.db", help="SQLite output filename inside --output-dir")
    audit.add_argument("--threshold-ms", type=float, action="append", default=None, help="Long span threshold in milliseconds")
    audit.add_argument("--log-level", default="I", choices=["D", "I", "W", "E", "F"], help="trace_streamer log level")
    audit.add_argument("--timeout", type=float, default=300, help="trace_streamer timeout in seconds")
    audit.add_argument("--arch-mode", choices=["auto", "never", "x86_64"], default="auto", help="macOS Rosetta arch wrapper mode")
    audit.add_argument("--force", action="store_true", help="Replace an existing --db-name in --output-dir")
    audit.add_argument("--json", action="store_true", help="Print machine-readable JSON")

    return parser


def main(argv: list[str] | None = None) -> int:
    parser = build_parser()
    args = parser.parse_args(argv)
    if getattr(args, "threshold_ms", None) is None:
        args.threshold_ms = DEFAULT_THRESHOLDS_MS

    try:
        if args.command == "doctor":
            exit_code, payload = run_doctor(args)
        elif args.command == "audit":
            payload = audit_trace_file(args)
            exit_code = 0
        else:
            parser.error(f"Unknown command: {args.command}")
            return 2

        if args.json:
            print_json(payload)
        else:
            print(json.dumps(payload, ensure_ascii=False))
        return exit_code
    except ProfilerTraceAuditError as error:
        payload = error.payload or {"decision": "blocked", "error": str(error), "missingConfig": []}
        if getattr(args, "json", False):
            print_json(payload)
        else:
            print(f"blocked: {error}", file=sys.stderr)
        return 2


if __name__ == "__main__":
    raise SystemExit(main())
