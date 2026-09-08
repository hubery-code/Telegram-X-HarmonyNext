#!/usr/bin/env python3
"""schema IR -> ArkTS DTO / discriminated unions / JSON codec (GEN-002).

Reads the machine-readable schema IR produced by GEN-001
(core/td_api_generated/schema.ir.json) and generates ArkTS:

  - one class per TDLib constructor (objects and functions), with a
    literal `type` discriminant and an optional `extra` field carrying
    the TDLib JSON "@extra" request tag;
  - one discriminated union type alias per abstract TDLib type, always
    including the TdUnknownObject forward-compatibility fallback member;
  - JSON decode functions (never throw: unknown @type -> TdUnknownObject,
    unknown fields ignored, missing fields -> schema defaults);
  - JSON encode functions (TDLib wire shape with "@type"/"@extra");
  - request response-type map (function name -> result union);
  - schema hash / generator version constants.

Type mapping (per GEN-001 README handoff):
  int32/int53/double -> number, int64 -> string (precision), string -> string,
  bytes -> string (base64, passed through), bool/Bool -> boolean,
  vector<nesting> -> T[] .

Naming:
  union  for abstract type T        -> Td<T>            (e.g. TdMessageContent)
  class  for constructor c          -> Pascal(c) with deterministic
                                        collision fallback (Td<Pascal>, then
                                        <Pascal>Value): TDLib type names collide
                                        with Pascal(constructor) names, and
                                        ctors `date`/`error`/`proxy` collide
                                        with ArkTS/JS globals.

Output layout (all under core/td_api_generated/src/main/ets):
  Index.ets               explicit re-exports
  runtime/TdJson.ets      TdJsonValue, TdUnknownObject, scalar/vector helpers
  types/TdTypes_<A-Z>.ets classes + per-constructor decode/encode (chunked
                          alphabetically by class name to keep files editable)
  types/TdUnions.ets      union aliases, union decode/encode, TdObject,
                          TdFunction, TdResponseMap

Generation is fully deterministic: repeated runs produce byte-identical
output (CI: `python3 tools/td_api_codegen/td_api_arkts.py verify`).

Generated code must not be hand-edited; change this generator instead.

Usage:
  python3 tools/td_api_codegen/td_api_arkts.py generate
  python3 tools/td_api_codegen/td_api_arkts.py verify   (CI entry)
  python3 tools/td_api_codegen/td_api_arkts.py info

No third-party dependencies. Python >= 3.9.
"""

from __future__ import annotations

import argparse
import json
import sys
from pathlib import Path

REPO_ROOT = Path(__file__).resolve().parents[2]
IR_PATH = REPO_ROOT / "core/td_api_generated/schema.ir.json"
OUT_ROOT = REPO_ROOT / "core/td_api_generated/src/main/ets"

CODEGEN_FORMAT_VERSION = 1
CODEGEN_NAME = "tools/td_api_codegen/td_api_arkts.py"

RUNTIME_FILE = "runtime/TdJson.ets"
UNIONS_FILE = "types/TdUnions.ets"

# ArkTS/JS globals that generated classes must not shadow.
GLOBALS = {
    "Error", "Object", "Array", "String", "Number", "Boolean", "Promise",
    "Date", "Map", "Set", "JSON", "Math", "RegExp", "Symbol", "Function",
    "TypeError", "RangeError", "SyntaxError", "ReferenceError", "EvalError",
    "URIError", "ArrayBuffer", "DataView", "WeakMap", "WeakSet", "Proxy",
    "Reflect", "Intl",
}

SCALARS = {"int32", "int53", "int64", "double", "string", "bytes", "bool", "Bool"}

# Runtime helpers defined in TdJson.ets that generated code may import.
HELPER_AS_NUMBER = "asNumber"
HELPER_AS_STRING = "asString"
HELPER_AS_BOOL = "asBool"
HELPER_AS_INT64 = "asInt64"
HELPER_AS_RECORD = "asRecord"
HELPER_DECODE_VECTOR = "decodeVector"
HELPER_ENCODE_VECTOR = "encodeVector"
HELPER_UNKNOWN = "TdUnknownObject"
HELPER_ENCODE_UNKNOWN = "encodeUnknownObject"
HELPER_JSON_VALUE = "TdJsonRaw"


def pascal(name: str) -> str:
    return name[0].upper() + name[1:]


# TDLib fields named `type`/`extra` collide with the discriminant / @extra
# properties; expose them with a trailing underscore (wire name unchanged).
def prop_name(field_name: str) -> str:
    if field_name in ("type", "extra"):
        return field_name + "_"
    return field_name


def doc_comment(text: str, indent: str = "") -> str:
    """Single-line JSDoc; strips comment terminators and newlines."""
    clean = text.replace("*/", "").replace("\r", " ").replace("\n", " ")
    clean = " ".join(clean.split())
    if not clean:
        return ""
    if len(clean) > 240:
        clean = clean[:237] + "..."
    return f"{indent}/** {clean} */\n"


class Schema:
    def __init__(self, ir: dict):
        self.ir = ir
        self.aliases = set(ir["builtins"]["aliases"])
        self.types = {t["name"]: t for t in ir["types"]}
        self.ctors = [c for c in ir["constructors"] if c["name"] not in self.aliases]
        self.ctor_by_name = {c["name"]: c for c in self.ctors}
        self.type_names = set(self.types.keys())
        # Name resolution (deterministic collision fallback).
        self.union_names = {t: "Td" + t for t in self.type_names}
        union_name_set = set(self.union_names.values())
        self.class_names: dict = {}
        used: set = set()
        for c in sorted(self.ctors, key=lambda c: c["name"]):
            base = pascal(c["name"])
            chosen = None
            for cand in (base, "Td" + base, base + "Value", "Td" + base + "Value"):
                if cand in GLOBALS or cand in union_name_set or cand in used:
                    continue
                chosen = cand
                break
            if chosen is None:  # pragma: no cover - schema would need to be bizarre
                sys.exit(f"error: cannot resolve ArkTS name for constructor {c['name']}")
            self.class_names[c["name"]] = chosen
            used.add(chosen)
        # Chunk classes alphabetically by first letter of the class name.
        self.chunks: dict = {}
        for c in self.ctors:
            letter = self.class_names[c["name"]][0]
            self.chunks.setdefault(letter, []).append(c)
        for letter in self.chunks:
            self.chunks[letter].sort(key=lambda c: c["name"])
        self.chunk_files = {
            letter: f"types/TdTypes_{letter}.ets" for letter in sorted(self.chunks)
        }
        # Where each exported symbol is defined.
        self.symbol_file: dict = {}
        for c in self.ctors:
            cls = self.class_names[c["name"]]
            letter = cls[0]
            self.symbol_file[cls] = self.chunk_files[letter]
            self.symbol_file["decode" + cls] = self.chunk_files[letter]
            self.symbol_file["encode" + cls] = self.chunk_files[letter]
        for t in self.type_names:
            self.symbol_file[self.union_names[t]] = UNIONS_FILE
            self.symbol_file["decode" + self.union_names[t]] = UNIONS_FILE
            self.symbol_file["encode" + self.union_names[t]] = UNIONS_FILE

    # -- type mapping -----------------------------------------------------

    def field_class(self, f: dict):
        """If the field references a constructor by name, return its ctor."""
        t = f["type"]
        if f["vectorDepth"] == 0 and t not in SCALARS and t not in self.type_names:
            return self.ctor_by_name.get(t)
        return None

    def ts_type(self, f: dict) -> str:
        t = f["type"]
        depth = f["vectorDepth"]
        if t in SCALARS:
            base = {
                "int32": "number", "int53": "number", "double": "number",
                "int64": "string", "string": "string", "bytes": "string",
                "bool": "boolean", "Bool": "boolean",
            }[t]
            nullable = False
        elif t in self.type_names:
            base = self.union_names[t]
            nullable = depth == 0
        else:
            base = self.class_names[t]
            nullable = depth == 0
        for _ in range(depth):
            base += "[]"
            nullable = False
        if nullable:
            base += " | null"
        return base

    def decode_expr(self, f: dict, value_expr: str) -> str:
        """Expression decoding `value_expr` (a TdJsonValue) into ts_type."""
        t = f["type"]
        depth = f["vectorDepth"]
        scalar_decoders = {
            "int32": HELPER_AS_NUMBER, "int53": HELPER_AS_NUMBER,
            "double": HELPER_AS_NUMBER, "int64": HELPER_AS_INT64,
            "string": HELPER_AS_STRING, "bytes": HELPER_AS_STRING,
            "bool": HELPER_AS_BOOL, "Bool": HELPER_AS_BOOL,
        }
        if depth == 0:
            if t in SCALARS:
                return f"{scalar_decoders[t]}({value_expr})"
            if t in self.type_names:
                return f"decode{self.union_names[t]}({value_expr})"
            return f"decode{self.class_names[t]}({value_expr})"
        # vector<...>: possibly nested.
        def elem_decoder(d: int) -> str:
            if d == 0:
                if t in SCALARS:
                    if scalar_decoders[t] == HELPER_AS_NUMBER:
                        return f"(item: {HELPER_JSON_VALUE}): number => {HELPER_AS_NUMBER}(item)"
                    if scalar_decoders[t] == HELPER_AS_INT64:
                        return f"(item: {HELPER_JSON_VALUE}): string => {HELPER_AS_INT64}(item)"
                    if scalar_decoders[t] == HELPER_AS_BOOL:
                        return f"(item: {HELPER_JSON_VALUE}): boolean => {HELPER_AS_BOOL}(item)"
                    return f"(item: {HELPER_JSON_VALUE}): string => {HELPER_AS_STRING}(item)"
                if t in self.type_names:
                    un = self.union_names[t]
                    return (
                        f"(item: {HELPER_JSON_VALUE}): {un} => "
                        f"decode{un}(item) as {un}"
                    )
                cls = self.class_names[t]
                return (
                    f"(item: {HELPER_JSON_VALUE}): {cls} => "
                    f"decode{cls}(item) as {cls}"
                )
            inner = elem_decoder(d - 1)
            inner_ret = self.ts_type({**f, "vectorDepth": d - 1})
            if d - 1 == 0 and (t in self.type_names or t not in SCALARS):
                inner_ret = inner_ret.replace(" | null", "")
            return (
                f"(items: {HELPER_JSON_VALUE}): ({inner_ret})[] => "
                f"{HELPER_DECODE_VECTOR}(items, {inner})"
            )
        return f"{HELPER_DECODE_VECTOR}({value_expr}, {elem_decoder(depth - 1)})"

    def encode_expr(self, f: dict, value_expr: str) -> str:
        t = f["type"]
        depth = f["vectorDepth"]
        if depth == 0:
            if t in SCALARS:
                return value_expr  # number/string/boolean pass through as TdJsonValue
            enc = (
                f"encode{self.union_names[t]}"
                if t in self.type_names
                else f"encode{self.class_names[t]}"
            )
            return f"{value_expr} === null ? null : {enc}({value_expr})"
        def elem_encoder(d: int) -> str:
            if d == 0:
                if t in SCALARS:
                    scalar_ts = self.ts_type({**f, "vectorDepth": 0})
                    return f"(item: {scalar_ts}): {HELPER_JSON_VALUE} => item"
                enc = (
                    f"encode{self.union_names[t]}"
                    if t in self.type_names
                    else f"encode{self.class_names[t]}"
                )
                elem_ts = self.ts_type({**f, "vectorDepth": 0})  # 'X | null'
                return (
                    f"(item: {elem_ts}): {HELPER_JSON_VALUE} => "
                    f"item === null ? null : {enc}(item)"
                )
            inner = elem_encoder(d - 1)
            row_ts = self.ts_type({**f, "vectorDepth": d - 1})
            return (
                f"(items: ({row_ts})[]): {HELPER_JSON_VALUE}[] => "
                f"{HELPER_ENCODE_VECTOR}(items, {inner})"
            )
        return f"{HELPER_ENCODE_VECTOR}({value_expr}, {elem_encoder(depth - 1)})"

    def class_ref_names(self, f: dict):
        """Type names referenced by a field (union or class names)."""
        t = f["type"]
        if t in SCALARS:
            return []
        if t in self.type_names:
            return [self.union_names[t]]
        return [self.class_names[t]]


HEADER = (
    "/**\n"
    " * GENERATED FILE — DO NOT EDIT.\n"
    " * Generated by tools/td_api_codegen/td_api_arkts.py (GEN-002) from\n"
    " * core/td_api_generated/schema.ir.json (GEN-001).\n"
    " * Regenerate: python3 tools/td_api_codegen/td_api_arkts.py generate\n"
    " */\n"
    "\n"
)


def gen_runtime(schema: Schema) -> str:
    ir = schema.ir
    out = [HEADER]
    out.append(f"// Schema: {ir['source']['path']}\n")
    out.append(f"// schemaHash: {ir['schemaHash']}\n")
    out.append("\n")
    out.append("/** JSON value as produced/consumed by the TDLib JSON interface. */\n")
    out.append(
        "export type TdJsonRaw = boolean | number | string | "
        "TdJsonRaw[] | TdJsonObject | null;\n"
        "export interface TdJsonObject extends Record<string, TdJsonRaw> {\n}\n"
    )
    out.append("\n")
    out.append(f"/** SHA-256 over the canonicalized schema (GEN-001). */\n")
    out.append(f"export const TD_SCHEMA_HASH: string = '{ir['schemaHash']}';\n")
    out.append(f"export const TD_CODEGEN: string = '{CODEGEN_NAME}';\n")
    out.append(
        f"export const TD_CODEGEN_FORMAT_VERSION: number = {CODEGEN_FORMAT_VERSION};\n"
    )
    out.append("\n")
    out.append(doc_comment(
        "Forward-compatibility fallback for an unknown TDLib constructor "
        "(`@type` not present in this schema). Never throws; preserves the raw "
        "record so it can be re-encoded losslessly."))
    out.append("export class TdUnknownObject {\n")
    out.append("  type: string = '';\n")
    out.append(f"  raw: Record<string, {HELPER_JSON_VALUE}> = {{}};\n")
    out.append("\n")
    out.append("  constructor(type: string = '', raw: Record<string, TdJsonRaw> = {}) {\n")
    out.append("    this.type = type;\n")
    out.append("    this.raw = raw;\n")
    out.append("  }\n")
    out.append("}\n")
    out.append("\n")
    out.append(doc_comment("Re-encode an unknown object preserving its raw JSON fields."))
    out.append(f"export function {HELPER_ENCODE_UNKNOWN}(value: {HELPER_UNKNOWN}): Record<string, {HELPER_JSON_VALUE}> {{\n")
    out.append(f"  const out: Record<string, {HELPER_JSON_VALUE}> = {{}};\n")
    out.append("  for (const key of Object.keys(value.raw)) {\n")
    out.append("    out[key] = value.raw[key];\n")
    out.append("  }\n")
    out.append("  return out;\n")
    out.append("}\n")
    out.append("\n")
    out.append(f"export function {HELPER_AS_RECORD}(value: {HELPER_JSON_VALUE}): Record<string, {HELPER_JSON_VALUE}> {{\n")
    out.append(f"  if (typeof value === 'object' && value !== null && !Array.isArray(value)) {{\n")
    out.append(f"    return value as Record<string, {HELPER_JSON_VALUE}>;\n")
    out.append("  }\n")
    out.append("  return {};\n")
    out.append("}\n")
    out.append("\n")
    out.append(f"export function {HELPER_AS_STRING}(value: {HELPER_JSON_VALUE}, defaultValue: string = ''): string {{\n")
    out.append("  if (typeof value === 'string') {\n")
    out.append("    return value;\n")
    out.append("  }\n")
    out.append("  if (typeof value === 'number') {\n")
    out.append("    return value.toString();\n")
    out.append("  }\n")
    out.append("  return defaultValue;\n")
    out.append("}\n")
    out.append("\n")
    out.append(f"export function {HELPER_AS_NUMBER}(value: {HELPER_JSON_VALUE}, defaultValue: number = 0): number {{\n")
    out.append("  if (typeof value === 'number') {\n")
    out.append("    return value;\n")
    out.append("  }\n")
    out.append("  if (typeof value === 'string') {\n")
    out.append("    const parsed: number = Number(value);\n")
    out.append("    if (!Number.isNaN(parsed)) {\n")
    out.append("      return parsed;\n")
    out.append("    }\n")
    out.append("  }\n")
    out.append("  return defaultValue;\n")
    out.append("}\n")
    out.append("\n")
    out.append(f"export function {HELPER_AS_INT64}(value: {HELPER_JSON_VALUE}): string {{\n")
    out.append("  if (typeof value === 'string') {\n")
    out.append("    return value;\n")
    out.append("  }\n")
    out.append("  if (typeof value === 'number') {\n")
    out.append("    return value.toString();\n")
    out.append("  }\n")
    out.append("  return '0';\n")
    out.append("}\n")
    out.append("\n")
    out.append(f"export function {HELPER_AS_BOOL}(value: {HELPER_JSON_VALUE}): boolean {{\n")
    out.append("  return value === true;\n")
    out.append("}\n")
    out.append("\n")
    out.append(f"export function {HELPER_DECODE_VECTOR}<T>(value: {HELPER_JSON_VALUE}, decoder: (item: {HELPER_JSON_VALUE}) => T): T[] {{\n")
    out.append("  if (!Array.isArray(value)) {\n")
    out.append("    return [];\n")
    out.append("  }\n")
    out.append("  const out: T[] = [];\n")
    out.append("  for (const item of value) {\n")
    out.append("    out.push(decoder(item));\n")
    out.append("  }\n")
    out.append("  return out;\n")
    out.append("}\n")
    out.append("\n")
    out.append(f"export function {HELPER_ENCODE_VECTOR}<T>(value: T[], encoder: (item: T) => {HELPER_JSON_VALUE}): {HELPER_JSON_VALUE}[] {{\n")
    out.append("  const out: TdJsonRaw[] = [];\n")
    out.append("  for (const item of value) {\n")
    out.append("    out.push(encoder(item));\n")
    out.append("  }\n")
    out.append("  return out;\n")
    out.append("}\n")
    return "".join(out)


def gen_class(schema: Schema, c: dict) -> str:
    cls = schema.class_names[c["name"]]
    out: list = []
    desc = c["doc"]["description"]
    header = f"{c['name']} = {c['type']}"
    out.append(doc_comment((header + (" — " + desc if desc else "")).strip()))
    out.append(f"export class {cls} {{\n")
    out.append(f"  type: '{c['name']}' = '{c['name']}';\n")
    out.append("  extra?: string;\n")
    for f in c["fields"]:
        fdoc = c["doc"]["fields"].get(f["name"], "")
        comment = f"{f['name']}: {f['signature']}"
        if fdoc:
            comment += " — " + fdoc
        out.append(doc_comment(comment.strip(), indent="  "))
        out.append(f"  {prop_name(f['name'])}: {schema.ts_type(f)} = {default_init(schema, f)};\n")
    out.append("}\n")
    return "".join(out)


def default_init(schema: Schema, f: dict) -> str:
    t = f["type"]
    depth = f["vectorDepth"]
    if depth > 0:
        return "[]"
    if t in ("int32", "int53", "double"):
        return "0"
    if t == "int64":
        return "''"
    if t in ("string", "bytes"):
        return "''"
    if t in ("bool", "Bool"):
        return "false"
    return "null"


def gen_decode(schema: Schema, c: dict) -> str:
    cls = schema.class_names[c["name"]]
    fn = "decode" + cls
    out: list = []
    out.append(doc_comment(f"Decode a TDLib `{c['name']}` object; null input -> null."))
    out.append(
        f"export function {fn}(json: {HELPER_JSON_VALUE}): {cls} | null {{\n"
    )
    out.append("  if (json === null) {\n")
    out.append("    return null;\n")
    out.append("  }\n")
    out.append(f"  const record: Record<string, {HELPER_JSON_VALUE}> = {HELPER_AS_RECORD}(json);\n")
    out.append(f"  const out: {cls} = new {cls}();\n")
    out.append(f"  if (typeof record['@extra'] === 'string') {{\n")
    out.append("    out.extra = record['@extra'];\n")
    out.append("  }\n")
    for f in c["fields"]:
        expr = schema.decode_expr(f, f"record['{f['name']}']")
        out.append(f"  out.{prop_name(f['name'])} = {expr};\n")
    out.append("  return out;\n")
    out.append("}\n")
    return "".join(out)


def gen_encode(schema: Schema, c: dict) -> str:
    cls = schema.class_names[c["name"]]
    fn = "encode" + cls
    out: list = []
    out.append(doc_comment(f"Encode a `{c['name']}` into TDLib JSON wire shape."))
    out.append(f"export function {fn}(value: {cls}): Record<string, {HELPER_JSON_VALUE}> {{\n")
    out.append(f"  const out: Record<string, {HELPER_JSON_VALUE}> = {{}};\n")
    out.append(f"  out['@type'] = '{c['name']}';\n")
    out.append("  if (value.extra !== undefined) {\n")
    out.append("    out['@extra'] = value.extra;\n")
    out.append("  }\n")
    for f in c["fields"]:
        expr = schema.encode_expr(f, f"value.{prop_name(f['name'])}")
        out.append(f"  out['{f['name']}'] = {expr};\n")
    out.append("  return out;\n")
    out.append("}\n")
    return "".join(out)


def collect_chunk_refs(schema: Schema, ctors: list) -> dict:
    """symbol -> set of chunk files whose decode/encode fns are referenced."""
    refs: dict = {}
    for c in ctors:
        mine = schema.chunk_files[schema.class_names[c["name"]][0]]
        used: set = set()
        used.add(RUNTIME_FILE)
        for f in c["fields"]:
            for name in schema.class_ref_names(f):
                file = schema.symbol_file.get(name)
                if file and file != mine:
                    used.add(file)
        # decode/encode fns of referenced ctors/unions
        for f in c["fields"]:
            t = f["type"]
            if t in SCALARS:
                continue
            if t in schema.type_names:
                used.add(UNIONS_FILE)
            else:
                target = schema.chunk_files[schema.class_names[t][0]]
                if target != mine:
                    used.add(target)
        refs[schema.class_names[c["name"]]] = used
    return refs


def gen_chunk(schema: Schema, letter: str) -> str:
    ctors = schema.chunks[letter]
    my_file = schema.chunk_files[letter]
    # Collect imports.
    imports: dict = {}  # file -> set of symbols
    for c in ctors:
        cls = schema.class_names[c["name"]]
        need = imports.setdefault(my_file, set())
        need.add(HELPER_JSON_VALUE)
        for f in c["fields"]:
            for name in schema.class_ref_names(f):
                file = schema.symbol_file.get(name)
                if file and file != my_file:
                    imports.setdefault(file, set()).add(name)
            t = f["type"]
            if t in SCALARS:
                continue
            if t in schema.type_names:
                imports.setdefault(UNIONS_FILE, set()).add("decode" + schema.union_names[t])
                imports.setdefault(UNIONS_FILE, set()).add("encode" + schema.union_names[t])
            else:
                target = schema.chunk_files[schema.class_names[t][0]]
                if target != my_file:
                    imports.setdefault(target, set()).add("decode" + schema.class_names[t])
                    imports.setdefault(target, set()).add("encode" + schema.class_names[t])
    # helpers needed from runtime
    runtime_syms = set()
    for c in ctors:
        for f in c["fields"]:
            t = f["type"]
            if t in ("int32", "int53", "double"):
                runtime_syms.add(HELPER_AS_NUMBER)
            elif t == "int64":
                runtime_syms.add(HELPER_AS_INT64)
            elif t in ("string", "bytes"):
                runtime_syms.add(HELPER_AS_STRING)
            elif t in ("bool", "Bool"):
                runtime_syms.add(HELPER_AS_BOOL)
            if f["vectorDepth"] > 0:
                runtime_syms.add(HELPER_DECODE_VECTOR)
                runtime_syms.add(HELPER_ENCODE_VECTOR)
    runtime_syms.add(HELPER_AS_RECORD)
    runtime_syms.add(HELPER_JSON_VALUE)
    imports.setdefault(RUNTIME_FILE, set()).update(runtime_syms)

    # Chunks live in types/, runtime in runtime/, unions in types/.
    out: list = [HEADER]
    for file in sorted(imports):
        if file == my_file:
            continue
        syms = sorted(imports[file])
        if file.startswith("types/"):
            rel = "./" + file[len("types/"):-4]
        else:
            rel = "../" + file[:-4]
        out.append(f"import {{ {', '.join(syms)} }} from '{rel}';\n")
    out.append("\n")
    for i, c in enumerate(ctors):
        if i > 0:
            out.append("\n")
        out.append(gen_class(schema, c))
        out.append("\n")
        out.append(gen_decode(schema, c))
        out.append("\n")
        out.append(gen_encode(schema, c))
    return "".join(out)


def gen_unions(schema: Schema) -> str:
    out: list = [HEADER]
    # imports: every class decode/encode from chunks
    for letter in sorted(schema.chunks):
        syms: list = []
        for c in schema.chunks[letter]:
            cls = schema.class_names[c["name"]]
            syms.append(cls)
            syms.append("decode" + cls)
            syms.append("encode" + cls)
        out.append(f"import {{ {', '.join(syms)} }} from './TdTypes_{letter}';\n")
    out.append(
        f"import {{ {HELPER_UNKNOWN}, {HELPER_ENCODE_UNKNOWN}, {HELPER_AS_RECORD}, "
        f"{HELPER_AS_STRING}, {HELPER_JSON_VALUE} }} from '../runtime/TdJson';\n"
    )
    out.append("\n")
    for t in sorted(schema.type_names):
        ctors = schema.types[t]["constructors"]
        un = schema.union_names[t]
        desc = schema.types[t].get("doc") or ""
        out.append(doc_comment(f"TDLib type {t} — {desc}".rstrip(" —")))
        out.append(f"export type {un} =")
        members = [schema.class_names[c] for c in ctors]
        members.append(HELPER_UNKNOWN)
        if len(members) == 1:
            out.append(f" {members[0]};\n")
        else:
            out.append("\n")
            for m in members:
                out.append(f"  | {m}\n")
            out.append("  ;\n")
        out.append("\n")
        # decode
        out.append(doc_comment(f"Decode any member of TDLib type {t}; unknown @type -> TdUnknownObject."))
        out.append(f"export function decode{un}(json: {HELPER_JSON_VALUE}): {un} | null {{\n")
        out.append("  if (json === null) {\n")
        out.append("    return null;\n")
        out.append("  }\n")
        out.append(f"  const record: Record<string, {HELPER_JSON_VALUE}> = {HELPER_AS_RECORD}(json);\n")
        out.append(f"  const typeName: string = {HELPER_AS_STRING}(record['@type'], '');\n")
        out.append("  switch (typeName) {\n")
        for c in ctors:
            out.append(f"    case '{c}':\n")
            out.append(f"      return decode{schema.class_names[c]}(json);\n")
        out.append("    default:\n")
        out.append(f"      return new {HELPER_UNKNOWN}(typeName, record);\n")
        out.append("  }\n")
        out.append("}\n")
        out.append("\n")
        # encode
        out.append(doc_comment(f"Encode any member of TDLib type {t}."))
        out.append(f"export function encode{un}(value: {un}): Record<string, {HELPER_JSON_VALUE}> {{\n")
        out.append("  switch (value.type) {\n")
        for c in ctors:
            cls = schema.class_names[c]
            out.append(f"    case '{c}':\n")
            out.append(f"      return encode{cls}(value as {cls});\n")
        out.append("    default:\n")
        out.append(f"      return {HELPER_ENCODE_UNKNOWN}(value as {HELPER_UNKNOWN});\n")
        out.append("  }\n")
        out.append("}\n")
        out.append("\n")
    # TdObject / TdFunction
    object_ctors = [c for c in schema.ctors if c["kind"] == "object"]
    function_ctors = [c for c in schema.ctors if c["kind"] == "function"]
    out.append(doc_comment("Any TDLib object (update/event payload)."))
    out.append("export type TdObject =\n")
    for c in sorted(object_ctors, key=lambda c: schema.class_names[c["name"]]):
        out.append(f"  | {schema.class_names[c['name']]}\n")
    out.append(f"  | {HELPER_UNKNOWN}\n")
    out.append("  ;\n\n")
    out.append(doc_comment("Any TDLib function (request)."))
    out.append("export type TdFunction =\n")
    for c in sorted(function_ctors, key=lambda c: schema.class_names[c["name"]]):
        out.append(f"  | {schema.class_names[c['name']]}\n")
    out.append("  ;\n\n")
    # response map
    out.append(doc_comment("Request name -> response type (TDLib function result type)."))
    out.append("export interface TdResponseMap {\n")
    for c in sorted(function_ctors, key=lambda c: c["name"]):
        un = schema.union_names[c["type"]]
        out.append(f"  readonly {c['name']}: {un};\n")
    out.append("}\n\n")
    return "".join(out)


def gen_index(schema: Schema) -> str:
    out: list = [HEADER]
    for letter in sorted(schema.chunks):
        syms: list = []
        for c in schema.chunks[letter]:
            cls = schema.class_names[c["name"]]
            syms.append(cls)
            syms.append("decode" + cls)
            syms.append("encode" + cls)
        out.append(f"export {{ {', '.join(syms)} }} from './types/TdTypes_{letter}';\n")
    union_syms: list = []
    for t in sorted(schema.type_names):
        un = schema.union_names[t]
        union_syms.append(un)
        union_syms.append("decode" + un)
        union_syms.append("encode" + un)
    union_syms.extend(["TdObject", "TdFunction", "TdResponseMap"])
    out.append(f"export {{ {', '.join(union_syms)} }} from './types/TdUnions';\n")
    out.append(
        "export { TdJsonRaw, TdUnknownObject, encodeUnknownObject, "
        "TD_SCHEMA_HASH, TD_CODEGEN, TD_CODEGEN_FORMAT_VERSION } from './runtime/TdJson';\n"
    )
    return "".join(out)


def build_files(ir: dict) -> dict:
    schema = Schema(ir)
    files: dict = {}
    files["Index.ets"] = gen_index(schema)
    files[RUNTIME_FILE] = gen_runtime(schema)
    for letter in sorted(schema.chunks):
        files[schema.chunk_files[letter]] = gen_chunk(schema, letter)
    files[UNIONS_FILE] = gen_unions(schema)
    return files


def cmd_generate(args) -> int:
    ir = json.loads(IR_PATH.read_text(encoding="utf-8"))
    files = build_files(ir)
    for rel in sorted(files):
        path = OUT_ROOT / rel
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_text(files[rel], encoding="utf-8")
    schema = Schema(ir)
    total_classes = len(schema.ctors)
    print(f"schema hash: {ir['schemaHash']}")
    print(f"generated {len(files)} files, classes={total_classes} unions={len(schema.type_names)}")
    print(f"output: {OUT_ROOT.relative_to(REPO_ROOT)}")
    return 0


def cmd_verify(args) -> int:
    ir = json.loads(IR_PATH.read_text(encoding="utf-8"))
    files = build_files(ir)
    ok = True
    for rel in sorted(files):
        path = OUT_ROOT / rel
        if not path.exists():
            print(f"MISSING: {path.relative_to(REPO_ROOT)}")
            ok = False
            continue
        if path.read_text(encoding="utf-8") != files[rel]:
            print(f"DIFFERS: {path.relative_to(REPO_ROOT)}")
            ok = False
    if ok:
        schema = Schema(ir)
        print(
            f"OK — ArkTS output is up to date "
            f"(classes={len(schema.ctors)} unions={len(schema.type_names)} files={len(files)})"
        )
        return 0
    print("FAIL — regenerate with: python3 tools/td_api_codegen/td_api_arkts.py generate")
    return 1


def cmd_info(args) -> int:
    ir = json.loads(IR_PATH.read_text(encoding="utf-8"))
    schema = Schema(ir)
    print(
        json.dumps(
            {
                "schemaHash": ir["schemaHash"],
                "classes": len(schema.ctors),
                "unions": len(schema.type_names),
                "chunks": len(schema.chunks),
            },
            indent=2,
        )
    )
    return 0


def main() -> int:
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    sub = ap.add_subparsers(dest="cmd", required=True)
    g = sub.add_parser("generate", help="write ArkTS files into core/td_api_generated")
    g.set_defaults(func=cmd_generate)
    v = sub.add_parser("verify", help="regenerate in-memory and diff against checked-in files (CI)")
    v.set_defaults(func=cmd_verify)
    i = sub.add_parser("info", help="print generation stats")
    i.set_defaults(func=cmd_info)
    args = ap.parse_args()
    return args.func(args)


if __name__ == "__main__":
    sys.exit(main())
