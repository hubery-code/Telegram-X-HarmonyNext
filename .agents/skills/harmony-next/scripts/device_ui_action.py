#!/usr/bin/env python3
from __future__ import annotations

import argparse
import json
import re
import struct
import sys
import time
import uuid
from pathlib import Path

import device_evidence_bundle as evidence


BOUNDS_PATTERN = re.compile(r"\[\s*(-?\d+)\s*,\s*(-?\d+)\s*\]\[\s*(-?\d+)\s*,\s*(-?\d+)\s*\]")
SAFE_KEY_PATTERN = re.compile(r"^[A-Za-z0-9_.-]{1,64}$")


def parse_bounds(value: object) -> tuple[int, int, int, int] | None:
    if isinstance(value, str):
        match = BOUNDS_PATTERN.fullmatch(value.strip())
        if match:
            return tuple(int(match.group(index)) for index in range(1, 5))
        parts = [part.strip() for part in value.split(",")]
        if len(parts) == 4 and all(re.fullmatch(r"-?\d+", part) for part in parts):
            return tuple(int(part) for part in parts)
    if isinstance(value, (list, tuple)) and len(value) == 4 and all(isinstance(item, (int, float)) for item in value):
        return tuple(int(item) for item in value)
    if isinstance(value, dict):
        keys = ("left", "top", "right", "bottom")
        if all(isinstance(value.get(key), (int, float)) for key in keys):
            return tuple(int(value[key]) for key in keys)
    return None


def valid_bounds(bounds: tuple[int, int, int, int]) -> bool:
    left, top, right, bottom = bounds
    return left >= 0 and top >= 0 and right > left and bottom > top


def center(bounds: tuple[int, int, int, int]) -> tuple[int, int]:
    left, top, right, bottom = bounds
    return ((left + right) // 2, (top + bottom) // 2)


def png_dimensions(path: Path) -> dict[str, object]:
    try:
        data = path.read_bytes()[:24]
    except OSError as error:
        return {"available": False, "error": str(error)}
    if len(data) < 24 or data[:8] != b"\x89PNG\r\n\x1a\n" or data[12:16] != b"IHDR":
        return {"available": False, "error": "screenshot is not a PNG with an IHDR header"}
    width, height = struct.unpack(">II", data[16:24])
    return {"available": True, "width": width, "height": height, "coordinateSpace": "raw-device-pixels"}


def walk_nodes(value: object) -> list[dict[str, object]]:
    nodes: list[dict[str, object]] = []
    if isinstance(value, dict):
        if any(key in value for key in ("bounds", "origBounds", "text", "id", "resourceId", "type")):
            nodes.append(value)
        for child in value.values():
            nodes.extend(walk_nodes(child))
    elif isinstance(value, list):
        for item in value:
            nodes.extend(walk_nodes(item))
    return nodes


def node_bounds(node: dict[str, object]) -> tuple[int, int, int, int] | None:
    for key in ("bounds", "origBounds"):
        parsed = parse_bounds(node.get(key))
        if parsed and valid_bounds(parsed):
            return parsed
    return None


def node_values(node: dict[str, object], keys: tuple[str, ...]) -> list[str]:
    values: list[str] = []
    for key in keys:
        value = node.get(key)
        if isinstance(value, str) and value:
            values.append(value)
    return values


def resolve_layout_target(
    layout_path: Path,
    text: str | None,
    resource_id: str | None,
    contains: bool,
    match_index: int | None,
) -> dict[str, object]:
    try:
        layout = json.loads(layout_path.read_text(encoding="utf-8"))
    except (OSError, json.JSONDecodeError) as error:
        evidence.block("before layout is not valid JSON", missing_config=["layout"], errorDetail=str(error))

    text_keys = ("text", "content", "description", "accessibilityText", "hint", "value")
    resource_keys = ("id", "resourceId", "resource-id", "key", "inspectorKey")
    matches: list[dict[str, object]] = []
    for node in walk_nodes(layout):
        bounds = node_bounds(node)
        if not bounds:
            continue
        if text is not None:
            values = node_values(node, text_keys)
            matched = any(text in value for value in values) if contains else text in values
        else:
            values = node_values(node, resource_keys)
            matched = any(resource_id in value for value in values) if contains else resource_id in values
        if matched:
            matches.append(
                {
                    "bounds": bounds,
                    "type": node.get("type"),
                    "id": next(iter(node_values(node, resource_keys)), None),
                    "text": next(iter(node_values(node, text_keys)), None),
                }
            )

    if not matches:
        evidence.block(
            "no layout node matched the requested selector",
            missing_config=["actionTarget"],
            selector={"text": text, "resourceId": resource_id, "contains": contains},
        )
    if match_index is None and len(matches) > 1:
        evidence.block(
            "multiple layout nodes matched the requested selector; pass --match-index",
            missing_config=["matchIndex"],
            matchCount=len(matches),
            candidates=matches[:20],
        )
    selected_index = match_index or 0
    if not 0 <= selected_index < len(matches):
        evidence.block(
            "--match-index is outside the matched node range",
            missing_config=["matchIndex"],
            matchCount=len(matches),
        )
    selected = matches[selected_index]
    selected["matchCount"] = len(matches)
    selected["matchIndex"] = selected_index
    return selected


def validate_point(point: tuple[int, int], dimensions: dict[str, object], label: str) -> None:
    x, y = point
    if x < 0 or y < 0:
        evidence.block(f"{label} coordinates must be non-negative", missing_config=["coordinates"])
    if dimensions.get("available"):
        width = int(dimensions["width"])
        height = int(dimensions["height"])
        if x >= width or y >= height:
            evidence.block(
                f"{label} coordinates fall outside the raw screenshot coordinate space",
                missing_config=["coordinates"],
                point={"x": x, "y": y},
                screenshotDimensions=dimensions,
            )


def capture_state(
    label: str,
    hdc: Path,
    target: str,
    artifact_dir: Path,
    timeout: float,
    hilog_lines: int,
    run_id: str,
    commands: list[dict[str, object]],
    artifacts: list[dict[str, object]],
    remote_files: list[str],
    no_cleanup: bool,
) -> dict[str, object]:
    remote_layout = evidence.remote_path(run_id, f"{label}-layout.json")
    remote_screen = evidence.remote_path(run_id, f"{label}-screen.png")
    local_layout = artifact_dir / f"{label}-layout.json"
    local_screen = artifact_dir / f"{label}-screen.png"
    remote_files.extend([remote_layout, remote_screen])

    layout_record = evidence.run_hdc_capture_command(
        hdc,
        target,
        ["shell", "uitest", "dumpLayout", "-p", remote_layout, "-a"],
        f"{label}.uitest.dump-layout",
        artifact_dir,
        timeout,
        f"{label}_dump_layout.txt",
        snippet=True,
    )
    commands.append(layout_record)
    evidence.require_command_success(
        layout_record,
        ["layout"],
        artifact_dir,
        commands,
        artifacts,
        cleanup_hdc=hdc,
        cleanup_target=target,
        cleanup_remote_files=remote_files,
        cleanup_timeout=timeout,
        no_cleanup=no_cleanup,
    )
    recv_layout = evidence.receive_remote_file(
        hdc, target, remote_layout, local_layout, artifact_dir, timeout, f"{label}_recv_layout"
    )
    commands.append(recv_layout)
    evidence.require_command_success(
        recv_layout,
        ["layout"],
        artifact_dir,
        commands,
        artifacts,
        cleanup_hdc=hdc,
        cleanup_target=target,
        cleanup_remote_files=remote_files,
        cleanup_timeout=timeout,
        no_cleanup=no_cleanup,
    )
    evidence.require_artifact_file(
        local_layout,
        "layout",
        ["layout"],
        artifact_dir,
        commands,
        artifacts,
        cleanup_hdc=hdc,
        cleanup_target=target,
        cleanup_remote_files=remote_files,
        cleanup_timeout=timeout,
        no_cleanup=no_cleanup,
    )

    screen_record = evidence.run_hdc_capture_command(
        hdc,
        target,
        ["shell", "uitest", "screenCap", "-p", remote_screen],
        f"{label}.uitest.screencap",
        artifact_dir,
        timeout,
        f"{label}_screencap.txt",
        snippet=True,
    )
    commands.append(screen_record)
    evidence.require_command_success(
        screen_record,
        ["screenshot"],
        artifact_dir,
        commands,
        artifacts,
        cleanup_hdc=hdc,
        cleanup_target=target,
        cleanup_remote_files=remote_files,
        cleanup_timeout=timeout,
        no_cleanup=no_cleanup,
    )
    recv_screen = evidence.receive_remote_file(
        hdc, target, remote_screen, local_screen, artifact_dir, timeout, f"{label}_recv_screen"
    )
    commands.append(recv_screen)
    evidence.require_command_success(
        recv_screen,
        ["screenshot"],
        artifact_dir,
        commands,
        artifacts,
        cleanup_hdc=hdc,
        cleanup_target=target,
        cleanup_remote_files=remote_files,
        cleanup_timeout=timeout,
        no_cleanup=no_cleanup,
    )
    evidence.require_artifact_file(
        local_screen,
        "screenshot",
        ["screenshot"],
        artifact_dir,
        commands,
        artifacts,
        cleanup_hdc=hdc,
        cleanup_target=target,
        cleanup_remote_files=remote_files,
        cleanup_timeout=timeout,
        no_cleanup=no_cleanup,
    )

    log_record = evidence.run_hdc_capture_command(
        hdc,
        target,
        ["shell", "hilog", "-z", str(hilog_lines)],
        f"{label}.hilog.tail",
        artifact_dir,
        timeout,
        f"{label}_hilog.txt",
    )
    commands.append(log_record)

    artifacts.extend(
        [
            evidence.artifact_record(f"{label}-layout", local_layout),
            evidence.artifact_record(f"{label}-screenshot", local_screen),
            evidence.artifact_record(f"{label}-hilog", artifact_dir / f"{label}_hilog.txt"),
        ]
    )
    return {
        "layout": str(local_layout),
        "screenshot": str(local_screen),
        "hilog": str(artifact_dir / f"{label}_hilog.txt"),
        "layoutSummary": evidence.summarize_layout(local_layout),
        "screenshotDimensions": png_dimensions(local_screen),
    }


def resolve_action(args: argparse.Namespace, before: dict[str, object]) -> tuple[list[str], dict[str, object]]:
    dimensions = dict(before["screenshotDimensions"])
    if args.command == "tap":
        raw_point = args.x is not None or args.y is not None
        selectors = [raw_point, args.text is not None, args.resource_id is not None, args.bounds is not None]
        if sum(bool(item) for item in selectors) != 1 or raw_point and (args.x is None or args.y is None):
            evidence.block(
                "tap requires exactly one target: --x/--y, --text, --resource-id, or --bounds",
                missing_config=["actionTarget"],
            )
        target_summary: dict[str, object]
        if raw_point:
            point = (args.x, args.y)
            target_summary = {"source": "explicit-raw-device-coordinates", "point": {"x": point[0], "y": point[1]}}
        elif args.bounds:
            bounds = parse_bounds(args.bounds)
            if not bounds or not valid_bounds(bounds):
                evidence.block("--bounds must define a valid x1,y1,x2,y2 rectangle", missing_config=["bounds"])
            point = center(bounds)
            target_summary = {"source": "explicit-raw-device-bounds", "bounds": bounds}
        else:
            selected = resolve_layout_target(
                Path(str(before["layout"])),
                args.text,
                args.resource_id,
                args.contains,
                args.match_index,
            )
            bounds = tuple(selected["bounds"])
            point = center(bounds)
            target_summary = {"source": "dumpLayout-bounds", **selected}
        validate_point(point, dimensions, "tap")
        target_summary["point"] = {"x": point[0], "y": point[1]}
        return ["shell", "uitest", "uiInput", "click", str(point[0]), str(point[1])], target_summary

    if args.command == "swipe":
        start = (args.x1, args.y1)
        end = (args.x2, args.y2)
        validate_point(start, dimensions, "swipe start")
        validate_point(end, dimensions, "swipe end")
        return (
            ["shell", "uitest", "uiInput", "swipe", str(args.x1), str(args.y1), str(args.x2), str(args.y2)],
            {
                "source": "explicit-raw-device-coordinates",
                "start": {"x": args.x1, "y": args.y1},
                "end": {"x": args.x2, "y": args.y2},
            },
        )

    if not SAFE_KEY_PATTERN.fullmatch(args.key):
        evidence.block("key name contains unsupported characters", missing_config=["key"])
    return ["shell", "uitest", "uiInput", "keyEvent", args.key], {"source": "explicit-key", "key": args.key}


def validate_action_config(args: argparse.Namespace) -> None:
    if args.timeout <= 0:
        evidence.block("command timeout must be positive", missing_config=["timeout"])
    if not 1 <= args.hilog_lines <= 10000:
        evidence.block("--hilog-lines must be in range 1..10000", missing_config=["hilogLines"])
    if args.settle_seconds < 0:
        evidence.block("--settle-seconds must be non-negative", missing_config=["settleSeconds"])
    if args.command == "tap":
        raw_point = args.x is not None or args.y is not None
        selectors = [raw_point, args.text is not None, args.resource_id is not None, args.bounds is not None]
        if sum(bool(item) for item in selectors) != 1 or raw_point and (args.x is None or args.y is None):
            evidence.block(
                "tap requires exactly one target: --x/--y, --text, --resource-id, or --bounds",
                missing_config=["actionTarget"],
            )
    elif args.command == "key" and not SAFE_KEY_PATTERN.fullmatch(args.key):
        evidence.block("key name contains unsupported characters", missing_config=["key"])


def run_action(args: argparse.Namespace) -> dict[str, object]:
    validate_action_config(args)
    probe = evidence.probe_hdc(args.hdc, args.deveco_app)
    if not probe.exists:
        evidence.block(f"hdc was not found: {probe.path}", missing_config=["hdc"], hdc=probe.to_json())
    if not probe.executable:
        evidence.block(f"hdc is not executable: {probe.path}", missing_config=["hdcExecutable"], hdc=probe.to_json())
    assert probe.path is not None

    artifact_dir = evidence.prepare_artifact_dir(args.artifact_dir)
    target, connected_targets, list_command = evidence.choose_target(probe.path, args.target, args.timeout)
    commands: list[dict[str, object]] = [list_command]
    artifacts: list[dict[str, object]] = []
    remote_files: list[str] = []
    run_id = f"{evidence.timestamp()}-{uuid.uuid4().hex[:8]}"

    before = capture_state(
        "before",
        probe.path,
        target,
        artifact_dir,
        args.timeout,
        args.hilog_lines,
        run_id,
        commands,
        artifacts,
        remote_files,
        args.no_cleanup,
    )
    try:
        action_args, target_summary = resolve_action(args, before)
    except evidence.DeviceEvidenceError as error:
        if remote_files and not args.no_cleanup:
            commands.append(
                evidence.run_hdc_capture_command(
                    probe.path,
                    target,
                    ["shell", "rm", "-f", *remote_files],
                    "cleanup.remote-artifacts",
                    artifact_dir,
                    args.timeout,
                    "cleanup_remote.txt",
                    snippet=True,
                )
            )
        ledger_path = artifact_dir / "command_ledger.json"
        ledger_path.write_text(json.dumps(commands, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
        blocked_payload = error.payload or {"decision": "blocked", "error": str(error), "missingConfig": []}
        blocked_payload.update(
            {
                "artifactDir": str(artifact_dir),
                "commandLedger": str(ledger_path),
                "artifacts": artifacts + [evidence.artifact_record("command-ledger", ledger_path, "summary-safe")],
            }
        )
        raise evidence.DeviceEvidenceError(str(error), blocked_payload) from error
    action_record = evidence.run_hdc_capture_command(
        probe.path,
        target,
        action_args,
        f"ui-action.{args.command}",
        artifact_dir,
        args.timeout,
        "ui_action.txt",
        snippet=True,
    )
    commands.append(action_record)
    evidence.require_command_success(
        action_record,
        ["uiAction"],
        artifact_dir,
        commands,
        artifacts,
        cleanup_hdc=probe.path,
        cleanup_target=target,
        cleanup_remote_files=remote_files,
        cleanup_timeout=args.timeout,
        no_cleanup=args.no_cleanup,
    )
    if args.settle_seconds > 0:
        time.sleep(args.settle_seconds)

    after = capture_state(
        "after",
        probe.path,
        target,
        artifact_dir,
        args.timeout,
        args.hilog_lines,
        run_id,
        commands,
        artifacts,
        remote_files,
        args.no_cleanup,
    )

    if remote_files and not args.no_cleanup:
        commands.append(
            evidence.run_hdc_capture_command(
                probe.path,
                target,
                ["shell", "rm", "-f", *remote_files],
                "cleanup.remote-artifacts",
                artifact_dir,
                args.timeout,
                "cleanup_remote.txt",
                snippet=True,
            )
        )

    ledger_path = artifact_dir / "command_ledger.json"
    ledger_path.write_text(json.dumps(commands, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    artifacts.append(evidence.artifact_record("command-ledger", ledger_path, "summary-safe"))
    payload: dict[str, object] = {
        "decision": "completed",
        "operation": f"device.ui-action.{args.command}",
        "riskLevel": "automation",
        "policy": "automation",
        "redactionPolicy": args.redaction_policy,
        "target": target,
        "connectedTargets": connected_targets,
        "hdc": probe.to_json(),
        "coordinateSpace": before["screenshotDimensions"],
        "action": target_summary,
        "before": before,
        "after": after,
        "artifactDir": str(artifact_dir),
        "artifacts": artifacts,
        "commandLedger": str(ledger_path),
        "rawSensitiveContentStored": True,
        "notes": [
            "Coordinates are raw device pixels from dumpLayout bounds or explicit device-space input.",
            "Preview-image coordinates must not be used unless converted back to the raw screenshot dimensions.",
            "Before/after screenshots, layouts, and logs can contain private content and must be redacted before sharing.",
        ],
        "feedback": evidence.feedback_payload(
            "redacted summary JSON",
            "redacted command ledger",
            "before/after layout summaries and screenshot dimensions",
        ),
    }
    summary_path = artifact_dir / "summary.json"
    payload["summary"] = str(summary_path)
    summary_path.write_text(json.dumps(payload, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    return payload


def add_common_arguments(parser: argparse.ArgumentParser) -> None:
    evidence.add_hdc_arguments(parser)
    parser.add_argument("--target", help="HDC target, required when multiple targets are connected")
    parser.add_argument("--artifact-dir", type=Path, help="Required directory for before/after evidence")
    parser.add_argument("--redaction-policy", default=evidence.DEFAULT_REDACTION_POLICY)
    parser.add_argument("--hilog-lines", type=int, default=100)
    parser.add_argument("--settle-seconds", type=float, default=0.5)
    parser.add_argument("--no-cleanup", action="store_true")
    parser.add_argument("--json", action="store_true", help="Print machine-readable JSON")


def build_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(description="Perform one bounded HarmonyOS UI action with before/after HDC evidence.")
    subparsers = parser.add_subparsers(dest="command", required=True)

    tap = subparsers.add_parser("tap", help="Tap a layout node, raw bounds, or raw device coordinate")
    add_common_arguments(tap)
    tap.add_argument("--text", help="Exact visible text to resolve from before-layout")
    tap.add_argument("--resource-id", help="Exact id/resourceId/key to resolve from before-layout")
    tap.add_argument("--contains", action="store_true", help="Use substring matching for --text or --resource-id")
    tap.add_argument("--match-index", type=int, help="Zero-based match index when a selector matches multiple nodes")
    tap.add_argument("--bounds", help="Raw device bounds as x1,y1,x2,y2 or [x1,y1][x2,y2]")
    tap.add_argument("--x", type=int)
    tap.add_argument("--y", type=int)

    swipe = subparsers.add_parser("swipe", help="Swipe between two raw device coordinates")
    add_common_arguments(swipe)
    swipe.add_argument("--x1", type=int, required=True)
    swipe.add_argument("--y1", type=int, required=True)
    swipe.add_argument("--x2", type=int, required=True)
    swipe.add_argument("--y2", type=int, required=True)

    key = subparsers.add_parser("key", help="Send one bounded uitest keyEvent")
    add_common_arguments(key)
    key.add_argument("--key", required=True, help="Key name such as Back or Home")
    return parser


def main(argv: list[str] | None = None) -> int:
    parser = build_parser()
    args = parser.parse_args(argv)
    try:
        payload = run_action(args)
        if args.json:
            evidence.print_json(payload)
        else:
            print(json.dumps(payload, ensure_ascii=False))
        return 0
    except evidence.DeviceEvidenceError as error:
        payload = error.payload or {"decision": "blocked", "error": str(error), "missingConfig": []}
        if getattr(args, "json", False):
            evidence.print_json(payload)
        else:
            print(f"blocked: {error}", file=sys.stderr)
        return 2


if __name__ == "__main__":
    raise SystemExit(main())
