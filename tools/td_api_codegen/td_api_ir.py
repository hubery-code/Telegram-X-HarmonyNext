#!/usr/bin/env python3
"""td_api.tl parser -> schema IR -> stable schema hash -> snapshot verify.

Single source of truth: native/tdcore/third_party/td/td/generate/scheme/td_api.tl

Usage:
  python3 tools/td_api_codegen/td_api_ir.py generate
      Parse the .tl file and write:
        - core/td_api_generated/schema.ir.json   (machine-readable IR export)
      Then compare against the checked-in golden snapshot
        - tools/td_api_codegen/snapshot/td_api.ir.json
      Exit non-zero if the regenerated IR differs from the snapshot.

  python3 tools/td_api_codegen/td_api_ir.py generate --update-snapshot
      Regenerate and overwrite the golden snapshot + exported IR
      (use only when the input .tl file was intentionally updated).

  python3 tools/td_api_codegen/td_api_ir.py verify
      Same as `generate` without writing anything: parse, hash, compare
      against snapshot. This is the CI entry point; it must produce no
      working-tree diff on a clean checkout.

  python3 tools/td_api_codegen/td_api_ir.py info
      Print schema hash and statistics only.

No third-party dependencies. Python >= 3.9.
"""

from __future__ import annotations

import argparse
import hashlib
import json
import re
import sys
from dataclasses import dataclass, field as dc_field
from pathlib import Path

REPO_ROOT = Path(__file__).resolve().parents[2]
DEFAULT_INPUT = (
    REPO_ROOT
    / "native/tdcore/third_party/td/td/generate/scheme/td_api.tl"
)
IR_EXPORT_PATH = REPO_ROOT / "core/td_api_generated/schema.ir.json"
SNAPSHOT_PATH = REPO_ROOT / "tools/td_api_codegen/snapshot/td_api.ir.json"

IR_FORMAT_VERSION = 1

# Constructors whose result type is one of these are primitive aliases
# (e.g. `int32 = Int32;`, `string ? = String;`), not real schema classes.
BUILTIN_RESULT_TYPES = {"Double", "String", "Int32", "Int53", "Int64", "Bytes", "Bool", "Vector"}

# Scalar field types as written in td_api.tl. Lowercase aliases (int32 …)
# are primitive constructor names; Bool is referenced directly by fields.
BUILTIN_SCALARS = ["int32", "int53", "int64", "double", "string", "bytes", "bool", "Bool"]

_IDENT = r"[A-Za-z][A-Za-z0-9_]*"


class TlParseError(Exception):
    pass


# ---------------------------------------------------------------------------
# Parsing
# ---------------------------------------------------------------------------


def _strip_comments(text: str) -> str:
    """Remove /* block comments */ and // line comments (keeping newlines)."""
    out = []
    i = 0
    n = len(text)
    while i < n:
        if text.startswith("/*", i):
            end = text.find("*/", i + 2)
            if end == -1:
                raise TlParseError("unterminated block comment")
            out.append("\n" * text[i : end + 2].count("\n"))
            i = end + 2
        elif text.startswith("//", i):
            end = text.find("\n", i)
            if end == -1:
                break
            out.append("\n")
            i = end + 1
        else:
            out.append(text[i])
            i += 1
    return "".join(out)


@dataclass
class Field:
    name: str
    type_name: str  # scalar name or class name, as written in the .tl file
    vector_depth: int  # 0 = scalar, 1 = vector<T>, 2 = vector<vector<T>>

    @property
    def is_array(self) -> bool:
        return self.vector_depth > 0

    def to_ir(self) -> dict:
        return {
            "name": self.name,
            "type": self.type_name,
            "isArray": self.is_array,
            "vectorDepth": self.vector_depth,
            "signature": self.signature,
        }

    @property
    def signature(self) -> str:
        t = self.type_name
        for _ in range(self.vector_depth):
            t = f"vector<{t}>"
        return t


@dataclass
class Constructor:
    name: str
    result_type: str
    result_type_args: list  # e.g. ["t"] for `= Vector t`
    fields: list  # list[Field], declaration order
    type_vars: list  # e.g. ["t"] for `vector {t:Type} ...`
    kind: str  # "object" or "function"
    line: int
    doc_description: str = ""
    doc_fields: dict = dc_field(default_factory=dict)
    cls: str = ""  # nearest preceding //@class section annotation

    def to_ir(self) -> dict:
        return {
            "name": self.name,
            "kind": self.kind,
            "type": self.result_type,
            "typeArgs": self.result_type_args,
            "typeVars": self.type_vars,
            "class": self.cls,
            "fields": [f.to_ir() for f in self.fields],
            "doc": {
                "description": self.doc_description,
                "fields": {k: self.doc_fields[k] for k in sorted(self.doc_fields)},
            },
        }


@dataclass
class RawComment:
    tags: list  # list[(tag, text)]  tag: "description" | "class" | field-name
    continuations: list  # list[str] trailing //- lines


def _parse_doc_comments(lines, def_line_idx):
    """Collect the contiguous block of `//@...` doc lines (and `//-`
    continuation lines) directly above the definition at def_line_idx."""
    tags = []
    continuations = []
    i = def_line_idx - 1
    block = []
    while i >= 0:
        stripped = lines[i].strip()
        if stripped.startswith("//@") or stripped.startswith("//-"):
            block.append((i, stripped))
            i -= 1
            continue
        break
    block.reverse()
    for _, text in block:
        if text.startswith("//@class"):
            continue  # handled by the section-level pre-scan in parse_td_api
        if text.startswith("//@description"):
            tags.append(("description", text[len("//@description") :].strip()))
            continue
        if text.startswith("//@"):  # @field_name description
            body = text[2:]
            m = re.match(r"@(%s)\s*(.*)$" % _IDENT, body, re.S)
            if m:
                tags.append((m.group(1), m.group(2).strip()))
            continue
        if text.startswith("//-"):
            continuations.append(text[3:].strip())
    return RawComment(tags=tags, continuations=continuations)


def _extract_inline_field_docs(description: str):
    """`//@description text @field_name more text ...` -> (description, {field: text})."""
    field_docs = {}
    parts = re.split(r"(?=@%s\b)" % _IDENT, description)
    main = parts[0].strip() if parts else ""
    for part in parts[1:]:
        m = re.match(r"@(%s)\s*(.*)$" % _IDENT, part, re.S)
        if m:
            field_docs[m.group(1)] = m.group(2).strip()
    return main, field_docs


def _split_inline_docs(tag_texts):
    """Multiple @description segments can appear on one logical line after
    inline @field splits; merge them, collecting inline field docs."""
    descriptions = []
    field_docs = {}
    for tag, text in tag_texts:
        if tag == "description":
            desc, fdocs = _extract_inline_field_docs(text)
            descriptions.append(desc)
            field_docs.update(fdocs)
        else:
            field_docs[tag] = text
    return " ".join(d for d in descriptions if d), field_docs


def _parse_field_type(raw: str, line_no: int) -> tuple:
    """Parse `int32` / `string` / `vector<foo>` / `vector<vector<foo>>`."""
    depth = 0
    t = raw.strip()
    while t.startswith("vector<"):
        depth += 1
        t = t[len("vector<") :]
        if not t.endswith(">"):
            raise TlParseError(f"line {line_no}: malformed vector type {raw!r}")
        t = t[:-1].strip()
    if depth == 0 and not re.fullmatch(_IDENT, t):
        raise TlParseError(f"line {line_no}: unsupported field type {raw!r}")
    if not re.fullmatch(_IDENT, t):
        raise TlParseError(f"line {line_no}: unsupported field type {raw!r}")
    return t, depth


def parse_td_api(text: str) -> dict:
    """Parse td_api.tl content into the intermediate representation (IR)."""
    stripped = _strip_comments(text)
    raw_lines = text.splitlines()
    lines = stripped.splitlines()

    constructors = []
    section = "types"
    class_docs = {}  # class name -> description from //@class lines

    # //@class Name @description ... is a SECTION-level annotation: it applies
    # to every constructor after it until the next //@class line. Pre-scan
    # raw lines to build a per-line class context.
    class_context = {}
    running_class = None
    for i, raw in enumerate(raw_lines):
        m = re.match(r"^//@class\s+(%s)\s*(.*)$" % _IDENT, raw.strip())
        if m:
            running_class = m.group(1)
            rest = m.group(2)
            dm = re.search(r"@description\s+(.*)$", rest)
            if dm:
                class_docs.setdefault(running_class, dm.group(1).strip())
        class_context[i] = running_class

    for idx, line in enumerate(lines):
        line_no = idx + 1
        entry = line.strip()
        if not entry:
            continue
        if entry.startswith("---") and entry.endswith("---"):
            name = entry.strip("-").strip()
            if name == "functions":
                section = "functions"
                continue
            raise TlParseError(f"line {line_no}: unknown section {entry!r}")

        m = re.match(
            r"^(%s)((?:\s+\{%s:Type\})*)\s*(.*?)\s*=\s*(%s)((?:\s+%s)*)\s*;$"
            % (_IDENT, _IDENT, _IDENT, _IDENT),
            entry,
        )
        if not m:
            raise TlParseError(f"line {line_no}: cannot parse definition: {entry!r}")
        name, type_vars_raw, fields_raw, result, result_args_raw = m.groups()
        type_vars = re.findall(r"\{%s:Type\}" % _IDENT, type_vars_raw)
        type_vars = [v[1:-6] for v in type_vars]  # strip { and :Type}
        result_args = result_args_raw.split()

        # `vector {t:Type} # [ t ] = Vector t;` — the # [ t ] body survives
        # comment stripping only if written as real tokens; handle it here.
        if fields_raw.startswith("#"):
            fields_raw = ""

        fields = []
        if fields_raw and fields_raw != "?":
            for fm in re.finditer(r"(%s):(\S+)" % _IDENT, fields_raw):
                tname, depth = _parse_field_type(fm.group(2), line_no)
                fields.append(Field(name=fm.group(1), type_name=tname, vector_depth=depth))
            consumed = re.sub(r"(%s):(\S+)" % _IDENT, "", fields_raw).strip()
            if consumed:
                raise TlParseError(
                    f"line {line_no}: unparsed field fragment {consumed!r} in {entry!r}"
                )

        comment = _parse_doc_comments(raw_lines, idx)
        # The doc block directly above a definition contains only the
        # constructor description and per-field docs; class annotations were
        # handled by the section-level pre-scan above.
        description, fdocs = _split_inline_docs(comment.tags)
        for c in comment.continuations:
            description = (description + "\n" + c).strip() if description else c

        constructors.append(
            Constructor(
                name=name,
                result_type=result,
                result_type_args=result_args,
                fields=fields,
                type_vars=type_vars,
                kind="function" if section == "functions" else "object",
                line=line_no,
                doc_description=description,
                doc_fields=fdocs,
            )
        )
        constructors[-1].cls = class_context.get(idx) or ""

    return _build_ir(text, constructors, class_docs)


def _build_ir(source_text: str, constructors: list, class_docs: dict) -> dict:
    objects = [c for c in constructors if c.kind == "object"]
    functions = [c for c in constructors if c.kind == "function"]

    # Primitive aliases: constructors returning builtin result types.
    builtin_aliases = sorted(
        {
            c.name
            for c in objects
            if c.result_type in BUILTIN_RESULT_TYPES and not c.fields
        }
    )

    # Abstract types = result types of non-builtin constructors.
    abstract_names = sorted(
        {
            c.result_type
            for c in objects + functions
            if c.result_type not in BUILTIN_RESULT_TYPES
        }
    )

    types_ir = []
    for tname in abstract_names:
        ctors = sorted(
            (
                c.name
                for c in objects
                if c.result_type == tname and c.name not in builtin_aliases
            )
        )
        types_ir.append(
            {
                "name": tname,
                "kind": "object",
                "constructors": ctors,
                "doc": class_docs.get(tname, ""),
            }
        )
    # Function "types" (request families) — result types produced only by functions.
    fn_result_types = sorted({c.result_type for c in functions})
    for tname in fn_result_types:
        if tname not in abstract_names:
            types_ir.append(
                {"name": tname, "kind": "functionResult", "constructors": [], "doc": class_docs.get(tname, "")}
            )
    types_ir.sort(key=lambda t: t["name"])

    ctor_ir = [c.to_ir() for c in sorted(constructors, key=lambda c: c.name)]

    total_fields = sum(len(c.fields) for c in constructors)

    ir = {
        "formatVersion": IR_FORMAT_VERSION,
        "generator": "tools/td_api_codegen/td_api_ir.py",
        "source": {
            "path": "native/tdcore/third_party/td/td/generate/scheme/td_api.tl",
            "sha256": hashlib.sha256(source_text.encode("utf-8")).hexdigest(),
        },
        "stats": {
            "types": len(types_ir),
            "constructors": len(ctor_ir),
            "objects": len(objects),
            "functions": len(functions),
            "fields": total_fields,
            "builtinAliases": len(builtin_aliases),
        },
        "builtins": {
            "scalars": BUILTIN_SCALARS,
            "aliases": builtin_aliases,
        },
        "types": types_ir,
        "constructors": ctor_ir,
    }
    ir["schemaHash"] = compute_schema_hash(ir)
    return ir


def compute_schema_hash(ir: dict) -> str:
    """SHA-256 over the canonicalized schema content (types + constructors).

    Deliberately excludes source path / source file hash / stats so that the
    hash only changes when the schema itself changes. Canonical form: JSON,
    keys sorted, no whitespace, UTF-8.
    """
    payload = {"builtins": ir["builtins"], "types": ir["types"], "constructors": ir["constructors"]}
    canonical = json.dumps(payload, sort_keys=True, separators=(",", ":"), ensure_ascii=False)
    return hashlib.sha256(canonical.encode("utf-8")).hexdigest()


def dump_ir(ir: dict) -> str:
    """Stable, human-diffable serialization of the full IR."""
    return json.dumps(ir, indent=2, ensure_ascii=False, sort_keys=False) + "\n"


# ---------------------------------------------------------------------------
# CLI
# ---------------------------------------------------------------------------


def _load_input(path: Path) -> str:
    if not path.exists():
        sys.exit(f"error: input file not found: {path}")
    return path.read_text(encoding="utf-8")


def cmd_generate(args) -> int:
    text = _load_input(Path(args.input))
    ir = parse_td_api(text)
    serialized = dump_ir(ir)

    SNAPSHOT_PATH.parent.mkdir(parents=True, exist_ok=True)
    IR_EXPORT_PATH.parent.mkdir(parents=True, exist_ok=True)

    if args.update_snapshot:
        SNAPSHOT_PATH.write_text(serialized, encoding="utf-8")
        IR_EXPORT_PATH.write_text(serialized, encoding="utf-8")
        print(f"updated snapshot: {SNAPSHOT_PATH.relative_to(REPO_ROOT)}")
        print(f"updated export:   {IR_EXPORT_PATH.relative_to(REPO_ROOT)}")
        print(f"schema hash:      {ir['schemaHash']}")
        return 0

    IR_EXPORT_PATH.write_text(serialized, encoding="utf-8")
    changed = []
    if SNAPSHOT_PATH.exists():
        golden = SNAPSHOT_PATH.read_text(encoding="utf-8")
        if golden != serialized:
            changed.append(SNAPSHOT_PATH.relative_to(REPO_ROOT))
    else:
        sys.exit(f"error: snapshot missing: {SNAPSHOT_PATH}\nrun with --update-snapshot first")

    print(f"schema hash: {ir['schemaHash']}")
    print(f"stats: {json.dumps(ir['stats'], sort_keys=True)}")
    if changed:
        print("SNAPSHOT MISMATCH — regenerate with --update-snapshot if intentional:")
        for p in changed:
            print(f"  modified: {p}")
        return 1
    print("snapshot OK — regenerated IR is identical to checked-in snapshot")
    return 0


def cmd_verify(args) -> int:
    text = _load_input(Path(args.input))
    ir = parse_td_api(text)
    serialized = dump_ir(ir)
    if not SNAPSHOT_PATH.exists():
        sys.exit(f"error: snapshot missing: {SNAPSHOT_PATH}")
    golden = SNAPSHOT_PATH.read_text(encoding="utf-8")
    export = IR_EXPORT_PATH.read_text(encoding="utf-8") if IR_EXPORT_PATH.exists() else None

    ok = True
    if golden != serialized:
        print("FAIL: regenerated IR differs from checked-in snapshot")
        ok = False
    if export is None:
        print(f"FAIL: IR export missing: {IR_EXPORT_PATH}")
        ok = False
    elif export != serialized:
        print(f"FAIL: {IR_EXPORT_PATH.relative_to(REPO_ROOT)} differs from fresh generation")
        ok = False
    if ok:
        print(f"OK schema hash {ir['schemaHash']} stats {json.dumps(ir['stats'], sort_keys=True)}")
        return 0
    return 1


def cmd_info(args) -> int:
    text = _load_input(Path(args.input))
    ir = parse_td_api(text)
    print(json.dumps({"schemaHash": ir["schemaHash"], "stats": ir["stats"]}, indent=2))
    return 0


def main() -> int:
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--input", default=str(DEFAULT_INPUT), help="path to td_api.tl")
    sub = ap.add_subparsers(dest="cmd", required=True)
    g = sub.add_parser("generate", help="parse + write IR export + compare with snapshot")
    g.add_argument("--update-snapshot", action="store_true", help="overwrite golden snapshot and IR export")
    g.set_defaults(func=cmd_generate)
    v = sub.add_parser("verify", help="parse + compare with snapshot, write nothing (CI entry)")
    v.set_defaults(func=cmd_verify)
    i = sub.add_parser("info", help="print schema hash and stats")
    i.set_defaults(func=cmd_info)
    args = ap.parse_args()
    return args.func(args)


if __name__ == "__main__":
    sys.exit(main())
