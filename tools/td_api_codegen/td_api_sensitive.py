#!/usr/bin/env python3
"""schema IR -> 敏感字段元数据 + 日志脱敏 helper（GEN-004）。

Reads core/td_api_generated/schema.ir.json (GEN-001) and generates, under
core/td_api_generated/src/main/ets/redaction/:

  - TdSensitiveFields.ets: structured sensitive-field metadata derived from
    the schema IR — per-constructor field rules (policy + decision comment),
    a type-level sensitive type list, and the conservative name-substring
    tables used for unknown @type objects.
  - TdRedact.ets: runtime redaction helpers — redactTdJson(json: string)
    redacts a TDLib JSON string per the metadata (unknown @type -> conservative
    substring-based masking of suspicious field names), and
    redactFields(obj: TdObject) deep-copies a generated DTO with the same
    rules applied (encode -> redact -> decode).

Policies:
  'redact' — value fully replaced by a type-preserving placeholder
             (string -> '«redacted»', number -> 0, bool -> false,
             object/array subtree -> '«redacted»').
  'mask'   — strings partially masked (head/tail kept, see maskString in
             TdRedact.ets); non-string scalars replaced by 0/false;
             object/array subtrees are recursed into (so nested known
             constructors still get per-field treatment).
  'keep'   — unchanged (default for unlisted fields).

Design notes (计划 §14.4 / §5.2):
  - 日志按字段白名单输出，禁止先完整记录再正则脱敏 — these helpers are the
    second line of defense behind core/observability's whitelist Logger; the
    metadata is generated from the schema so a TDLib upgrade re-derives it.
  - Field rules are matched in order: constructor-scoped overrides first,
    then exact field-name rules, then suffix rules. First match wins.
    Field names are matched exactly (not by substring) so that e.g.
    `next_code_type` (a type tag, not a code value) is never redacted, and
    `country_code` / `language_code` / `postal_code` stay loggable.

Usage:
  python3 tools/td_api_codegen/td_api_sensitive.py generate
  python3 tools/td_api_codegen/td_api_sensitive.py verify   (CI entry)
  python3 tools/td_api_codegen/td_api_sensitive.py info

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
OUT_DIR = "redaction"
SENSITIVE_FILE = f"{OUT_DIR}/TdSensitiveFields.ets"
REDACT_FILE = f"{OUT_DIR}/TdRedact.ets"

CODEGEN_FORMAT_VERSION = 1
CODEGEN_NAME = "tools/td_api_codegen/td_api_sensitive.py"

# ---------------------------------------------------------------------------
# Rule table — the single place where redaction decisions are made.
#
# Each rule is (policy, reason). Matching precedence:
#   1. SCOPED_RULES[ctor][field]   — per-constructor override (highest)
#   2. EXACT_RULES[field]          — exact field name, any constructor
#   3. SUFFIX_RULES[(suffix)]      — field name ends with suffix
# Default: keep.
# ---------------------------------------------------------------------------

# Per-constructor overrides. Needed where the same field name means different
# things in different constructors (e.g. `username` is a public Telegram
# handle on users, but a proxy credential on proxyTypeHttp/proxyTypeSocks5).
SCOPED_RULES: dict = {
    "proxyTypeHttp": {
        "username": ("redact", "HTTP 代理用户名，属代理凭据"),
        "password": ("redact", "HTTP 代理密码，属代理凭据"),
    },
    "proxyTypeSocks5": {
        "username": ("redact", "SOCKS5 代理用户名，属代理凭据"),
        "password": ("redact", "SOCKS5 代理密码，属代理凭据"),
    },
    "proxyTypeMtproto": {
        "secret": ("redact", "MTProxy secret（generic secret 规则亦覆盖，此处显式声明）"),
    },
    # 初始化参数：api_id/api_hash 对客户端是半公开标识，但 §14.4 要求
    # 不入日志——遮蔽即可，不必完全遮蔽。
    "setTdlibParameters": {
        "api_id": ("mask", "客户端 api_id，半公开标识，遮蔽处理"),
        "api_hash": ("redact", "客户端 api_hash 属秘密（§14.4 明令不得入日志）"),
        "database_encryption_key": (
            "redact",
            "本地数据库加密密钥，泄漏即等于交出全部本地消息",
        ),
    },
    # error.code 是 TDLib 数字错误码（400/401/…），非验证码，保留以便排障。
    "error": {
        "code": ("keep", "TDLib 错误码 int32，非验证码值"),
    },
}

# Exact field-name rules. Deliberate decisions worth knowing:
#   - 'code' 遮蔽验证码（auth code 可直接接管账号）；next_code_type / code_info
#     等字段名不同，不受此规则影响。
#   - 'country_code' / 'language_code' / 'postal_code' / 'match_code'（贴纸）
#     不含敏感值，保持 keep（默认），不在此表。
#   - 无名为 'answer' 的字段（poll 只有 allows_multiple_answers 布尔），
#     故无 answer 规则。
EXACT_RULES: dict = {
    # —— 密码与恢复凭据 ——
    "password": ("redact", "账号密码明文"),
    "old_password": ("redact", "旧密码明文（setPassword）"),
    "new_password": ("redact", "新密码明文（setPassword）"),
    "password_hint": ("redact", "密码提示可能泄漏密码线索"),
    "recovery_code": ("redact", "两步验证恢复码"),
    # —— 验证码 / 兑换码 ——
    "code": ("redact", "登录/验证验证码，可接管账号"),
    "gift_code": ("mask", "礼品码可兑换，部分遮蔽保留可排查性"),
    # —— 令牌 ——
    "token": ("redact", "OAuth/支付令牌（inputCredentials 等）"),
    "access_token": ("redact", "支付提供商 access token"),
    "provider_token": ("redact", "支付提供商令牌"),
    "purchase_token": ("redact", "应用内购 token"),
    "public_token": ("mask", "公开发布的 token，遮蔽即可"),
    "device_token": ("mask", "推送 device token 可定位设备，部分遮蔽"),
    "zoom_token": ("mask", "视频聊天 zoom token，部分遮蔽"),
    "authentication_tokens": ("redact", "认证 token 对象列表，整棵遮蔽"),
    # —— 密钥 / 哈希 ——
    "secret": ("redact", "MTProxy secret 等"),
    "encryption_key": ("redact", "端到端加密密钥"),
    "new_encryption_key": ("redact", "数据库新加密密钥"),
    "database_encryption_key": ("redact", "数据库加密密钥"),
    "public_key": ("mask", "公钥非机密但具标识性"),
    "api_hash": ("redact", "客户端 api_hash 属秘密"),
    "hash": ("mask", "通用 hash 字段（如 messageSender 标识）"),
    # —— 手机号 / 邮箱 / IP / 姓名（PII）——
    "phone_number": ("mask", "手机号 PII（§14.4），保留国家码段便于排查"),
    "formatted_phone_number": ("mask", "格式化手机号 PII"),
    "email_address": ("mask", "邮箱 PII"),
    "new_recovery_email_address": ("mask", "新恢复邮箱 PII"),
    "new_login_email_address": ("mask", "新登录邮箱 PII"),
    "recovery_email_address_pattern": ("mask", "邮箱模式仍是 PII"),
    "login_email_address_pattern": ("mask", "登录邮箱模式 PII"),
    "ip_address": ("mask", "IP 地址，部分遮蔽"),
    "ipv6_address": ("mask", "IPv6 地址，部分遮蔽"),
    "first_name": ("mask", "姓名 PII"),
    "last_name": ("mask", "姓名 PII"),
    "shipping_address": ("redact", "收货地址整棵 PII 组合，直接遮蔽"),
    # —— 支付凭据 ——
    "credentials": ("redact", "支付凭据（银行卡/卡数据）"),
    "saved_credentials": ("redact", "已保存支付凭据标识"),
    "saved_credentials_id": ("mask", "已保存凭据 id，遮蔽"),
    # —— 显式 keep（防止后续 suffix 规则误伤；此处列决策，运行时默认 keep）——
    "country_code": ("keep", "国家码非敏感（文档化决策）"),
    "language_code": ("keep", "语言码非敏感（文档化决策）"),
    "postal_code": ("keep", "邮编单独非敏感（文档化决策）"),
    "match_code": ("keep", "贴纸 match code 非敏感（文档化决策）"),
    "next_code_type": ("keep", "仅验证码类型标签，不含验证码值（文档化决策）"),
    "is_secret": ("keep", "限时媒体标记布尔值，非秘密值（防 _secret suffix 误伤）"),
    "has_password": ("keep", "布尔标记不含密码值（防 _password suffix 误伤）"),
    "need_password": ("keep", "布尔标记不含密码值（防 _password suffix 误伤）"),
    "key": ("keep", "全部现有 key 字段均为语言包/JSON 键名，非密钥（文档化决策）"),
    "username": ("keep", "Telegram 用户名是公开标识（文档化决策）"),
    "usernames": ("keep", "Telegram 用户名是公开标识（文档化决策）"),
    "author_signature": ("keep", "频道署名公开可见（文档化决策）"),
}

# Suffix rules (checked after exact rules). Narrow on purpose: no generic
# '_code' suffix here — that would redact country_code/language_code.
SUFFIX_RULES: dict = {
    "_password": ("redact", "以 _password 结尾的字段（如未来新增的旧/新密码变体）"),
    "_hint": ("redact", "密码提示类字段（new_hint 等），可能泄漏密码线索"),
    "_secret": ("redact", "以 _secret 结尾的字段"),
    "_token": ("mask", "以 _token 结尾的字段（具体令牌已在精确表定级）"),
    "_hash": ("mask", "以 _hash 结尾的字段（data_hash/file_hash/key_hash 等）"),
}

# 未知 @type 的保守兜底：字段名包含这些子串即按对应策略遮蔽。
# 仅用于 schema 之外的构造器（TDLib 升级/私有 fork），宁可过度遮蔽。
UNKNOWN_TYPE_REDACT_SUBSTRINGS = [
    "password",
    "secret",
    "token",
    "phone",
]
UNKNOWN_TYPE_MASK_SUBSTRINGS = [
    "hash",
    "code",
    "key",
    "email",
    "session",
    "credential",
    "address",
]

HEADER = (
    "/**\n"
    " * GENERATED FILE — DO NOT EDIT.\n"
    " * Generated by tools/td_api_codegen/td_api_sensitive.py (GEN-004) from\n"
    " * core/td_api_generated/schema.ir.json (GEN-001).\n"
    " * Regenerate: python3 tools/td_api_codegen/td_api_sensitive.py generate\n"
    " */\n"
    "\n"
)

SCALARS = {"int32", "int53", "int64", "double", "string", "bytes", "bool", "Bool"}


def match_rule(ctor_name: str, field_name: str):
    """First-match-wins rule lookup; returns (policy, reason) or None."""
    scoped = SCOPED_RULES.get(ctor_name)
    if scoped and field_name in scoped:
        return scoped[field_name]
    if field_name in EXACT_RULES:
        return EXACT_RULES[field_name]
    for suffix, rule in SUFFIX_RULES.items():
        if field_name.endswith(suffix):
            return rule
    return None


def compute_rules(ir: dict):
    """Walk the IR and return {ctor: {field: (policy, reason)}} for non-keep rules."""
    rules: dict = {}
    for c in ir["constructors"]:
        ctor_rules: dict = {}
        # Constructor-scoped overrides are emitted even if the field would
        # otherwise default to keep (proxyTypeHttp.username 等）。
        scoped = SCOPED_RULES.get(c["name"], {})
        for f in c["fields"]:
            name = f["name"]
            if name in scoped:
                if scoped[name][0] != "keep":
                    ctor_rules[name] = scoped[name]
                continue
            matched = match_rule(c["name"], name)
            if matched is not None and matched[0] != "keep":
                ctor_rules[name] = matched
        if ctor_rules:
            rules[c["name"]] = ctor_rules
    return rules


def compute_sensitive_types(ir: dict, rules: dict):
    """Abstract types having at least one OBJECT constructor with a flagged field.

    Function constructors are excluded: a request's sensitive input (e.g.
    getGramWithdrawalUrl.password) must not mark its result type (HttpUrl)
    as sensitive.
    """
    sensitive = set()
    types = {t["name"]: t for t in ir["types"]}
    for c in ir["constructors"]:
        if c["kind"] != "object":
            continue
        if c["name"] not in rules:
            continue
        tname = c["type"]
        if tname in types:
            sensitive.add(tname)
    return sorted(sensitive)


def astring(s: str) -> str:
    """ArkTS single-quoted string literal."""
    return "'" + s.replace("\\", "\\\\").replace("'", "\\'") + "'"


def gen_sensitive_fields(ir: dict, rules: dict, sensitive_types: list) -> str:
    out = [HEADER]
    out.append(f"// Schema: {ir['source']['path']}\n")
    out.append(f"// schemaHash: {ir['schemaHash']}\n")
    out.append(f"// generator: {CODEGEN_NAME} (format {CODEGEN_FORMAT_VERSION})\n")
    out.append("\n")
    out.append("/**\n")
    out.append(" * 脱敏策略：\n")
    out.append(" * - 'redact' 完全遮蔽：字符串 -> '«redacted»'，数字 -> 0，布尔 -> false，\n")
    out.append(" *   对象/数组子树整体替换为 '«redacted»'（见 TdRedact.ets）。\n")
    out.append(" * - 'mask' 部分遮蔽：字符串保留头尾若干字符，数字/布尔置 0/false，\n")
    out.append(" *   对象/数组子树递归按子字段规则处理。\n")
    out.append(" * - 'keep' 保留（未列入此表的字段默认 keep）。\n")
    out.append(" */\n")
    out.append("export type TdRedactPolicy = 'redact' | 'mask' | 'keep';\n")
    out.append("\n")
    out.append("/** 单条字段规则：策略 + 决策理由（生成器规则表原文，可审计）。 */\n")
    out.append("export interface TdSensitiveFieldRule {\n")
    out.append("  readonly policy: TdRedactPolicy;\n")
    out.append("  readonly reason: string;\n")
    out.append("}\n")
    out.append("\n")
    out.append("/**\n")
    out.append(" * 敏感字段元数据：TDLib 构造器名 -> 字段名 -> 规则。\n")
    out.append(" * 仅收录非 keep 规则；未收录字段一律按 keep 处理。\n")
    out.append(" * 以赋值方式构建（arkts-no-untyped-obj-literals 不允许把带键字面量\n")
    out.append(" * 赋给开放键映射；空字面量 + 索引赋值是仓库内通行做法）。\n")
    out.append(" */\n")
    out.append("export interface TdFieldRuleMap extends Record<string, TdSensitiveFieldRule> {\n")
    out.append("}\n")
    out.append("export interface TdCtorRuleMap extends Record<string, TdFieldRuleMap> {\n")
    out.append("}\n")
    out.append("function makeRule(policy: TdRedactPolicy, reason: string): TdSensitiveFieldRule {\n")
    out.append("  return { policy: policy, reason: reason };\n")
    out.append("}\n")
    out.append("export const TD_SENSITIVE_FIELDS: TdCtorRuleMap = {};\n")
    out.append("\n")
    for ctor in sorted(rules):
        var = "TD_RULES_" + ctor
        out.append(f"const {var}: TdFieldRuleMap = {{}};\n")
        for fname in sorted(rules[ctor]):
            policy, reason = rules[ctor][fname]
            out.append(f"{var}[{astring(fname)}] = ")
            out.append(f"makeRule({astring(policy)}, {astring(reason)});\n")
        out.append(f"TD_SENSITIVE_FIELDS[{astring(ctor)}] = {var};\n")
        out.append("\n")
    # Known-constructor set: redactRecord must distinguish "known ctor without
    # rules" (keep) from "unknown @type" (conservative substring fallback).
    out.append("/**\n")
    out.append(" * 全部已知 TDLib 构造器名（schema IR 的 objects + functions）。\n")
    out.append(" * 供脱敏运行时区分「已知但无规则」（keep）与「未知 @type」（保守兜底）。\n")
    out.append(" */\n")
    out.append("export interface TdKnownCtorMap extends Record<string, boolean> {\n")
    out.append("}\n")
    out.append("export const TD_KNOWN_CONSTRUCTORS: TdKnownCtorMap = {};\n")
    for c in sorted({c["name"] for c in ir["constructors"]}):
        out.append(f"TD_KNOWN_CONSTRUCTORS[{astring(c)}] = true;\n")
    out.append("\n")
    out.append("\n")
    out.append("/**\n")
    out.append(" * 类型级敏感清单：包含至少一个敏感字段的抽象 TDLib 类型。\n")
    out.append(" * 用途：整对象日志时提示「该类型整体敏感」；file 等不含敏感字段\n")
    out.append(" * 的类型不在此列。\n")
    out.append(" */\n")
    out.append("export const TD_SENSITIVE_TYPES: readonly string[] = [\n")
    for t in sensitive_types:
        out.append(f"  {astring(t)},\n")
    out.append("];\n")
    out.append("\n")
    out.append("/** 字段名包含这些子串（未知 @type 兜底）→ 完全遮蔽。 */\n")
    out.append("export const TD_UNKNOWN_TYPE_REDACT_SUBSTRINGS: readonly string[] = [\n")
    for s in UNKNOWN_TYPE_REDACT_SUBSTRINGS:
        out.append(f"  {astring(s)},\n")
    out.append("];\n")
    out.append("\n")
    out.append("/** 字段名包含这些子串（未知 @type 兜底）→ 部分遮蔽。 */\n")
    out.append("export const TD_UNKNOWN_TYPE_MASK_SUBSTRINGS: readonly string[] = [\n")
    for s in UNKNOWN_TYPE_MASK_SUBSTRINGS:
        out.append(f"  {astring(s)},\n")
    out.append("];\n")
    return "".join(out)


def gen_redact(ir: dict) -> str:
    out = [HEADER]
    out.append(f"// Schema: {ir['source']['path']}\n")
    out.append(f"// schemaHash: {ir['schemaHash']}\n")
    out.append(f"// generator: {CODEGEN_NAME} (format {CODEGEN_FORMAT_VERSION})\n")
    out.append("\n")
    out.append("import {\n")
    out.append("  TD_KNOWN_CONSTRUCTORS,\n")
    out.append("  TD_SENSITIVE_FIELDS,\n")
    out.append("  TD_UNKNOWN_TYPE_REDACT_SUBSTRINGS,\n")
    out.append("  TD_UNKNOWN_TYPE_MASK_SUBSTRINGS,\n")
    out.append("  TdFieldRuleMap,\n")
    out.append("  TdRedactPolicy,\n")
    out.append("} from './TdSensitiveFields';\n")
    out.append("import { TdJsonRaw } from '../runtime/TdJson';\n")
    out.append("import { TdObject, decodeTdObject, encodeTdObject } from '../types/TdEntries';\n")
    out.append("\n")
    out.append("/** 完全遮蔽占位符（与原值同 JSON 类型，便于消费侧解析）。 */\n")
    out.append("const REDACTED_STRING: string = '\\u00ABredacted\\u00BB'; // «redacted»\n")
    out.append("const MASK_SEP: string = '\\u2026'; // …\n")
    out.append("\n")
    out.append("/** 完全遮蔽值：保持 JSON 标量类型；子树整体替换为占位字符串。 */\n")
    out.append("function redactedValue(value: TdJsonRaw): TdJsonRaw {\n")
    out.append("  if (typeof value === 'string') {\n")
    out.append("    return REDACTED_STRING;\n")
    out.append("  }\n")
    out.append("  if (typeof value === 'number') {\n")
    out.append("    return 0;\n")
    out.append("  }\n")
    out.append("  if (typeof value === 'boolean') {\n")
    out.append("    return false;\n")
    out.append("  }\n")
    out.append("  return REDACTED_STRING;\n")
    out.append("}\n")
    out.append("\n")
    out.append("/** 部分遮蔽字符串：长度 <= 4 全遮；<= 10 留首末各 1；其余留首 3 末 2。 */\n")
    out.append("function maskString(value: string): string {\n")
    out.append("  const len: number = value.length;\n")
    out.append("  if (len <= 4) {\n")
    out.append("    return '***';\n")
    out.append("  }\n")
    out.append("  if (len <= 10) {\n")
    out.append("    return value.substring(0, 1) + MASK_SEP + value.substring(len - 1);\n")
    out.append("  }\n")
    out.append("  return value.substring(0, 3) + MASK_SEP + value.substring(len - 2);\n")
    out.append("}\n")
    out.append("\n")
    out.append("function isRecord(value: TdJsonRaw): boolean {\n")
    out.append("  return typeof value === 'object' && value !== null && !Array.isArray(value);\n")
    out.append("}\n")
    out.append("\n")
    out.append("/** 未知 @type 的保守兜底：按字段名子串判定遮蔽力度。 */\n")
    out.append("function unknownTypePolicy(fieldName: string): TdRedactPolicy {\n")
    out.append("  for (const s of TD_UNKNOWN_TYPE_REDACT_SUBSTRINGS) {\n")
    out.append("    if (fieldName.indexOf(s) >= 0) {\n")
    out.append("      return 'redact';\n")
    out.append("    }\n")
    out.append("  }\n")
    out.append("  for (const s of TD_UNKNOWN_TYPE_MASK_SUBSTRINGS) {\n")
    out.append("    if (fieldName.indexOf(s) >= 0) {\n")
    out.append("      return 'mask';\n")
    out.append("    }\n")
    out.append("  }\n")
    out.append("  return 'keep';\n")
    out.append("}\n")
    out.append("\n")
    out.append("function applyPolicy(value: TdJsonRaw, policy: TdRedactPolicy): TdJsonRaw {\n")
    out.append("  if (policy === 'redact') {\n")
    out.append("    return redactedValue(value);\n")
    out.append("  }\n")
    out.append("  if (policy === 'mask') {\n")
    out.append("    if (typeof value === 'string') {\n")
    out.append("      return maskString(value);\n")
    out.append("    }\n")
    out.append("    if (isRecord(value) || Array.isArray(value)) {\n")
    out.append("      // mask 作用于子树：递归进去，让已知构造器仍可按字段细粒度遮蔽。\n")
    out.append("      return redactAny(value);\n")
    out.append("    }\n")
    out.append("    return redactedValue(value);\n")
    out.append("  }\n")
    out.append("  return value;\n")
    out.append("}\n")
    out.append("\n")
    out.append("/**\n")
    out.append(" * 对一条 TDLib JSON 记录按元数据脱敏。\n")
    out.append(" * @param record TDLib wire 记录（含 '@type'）\n")
    out.append(" * @param ctorName 已知构造器名；未知类型传空串走保守子串兜底。\n")
    out.append(" */\n")
    out.append("function redactRecord(\n")
    out.append("  record: Record<string, TdJsonRaw>,\n")
    out.append("  ctorName: string\n")
    out.append("): Record<string, TdJsonRaw> {\n")
    out.append("  const fieldRules: TdFieldRuleMap | undefined =\n")
    out.append("    ctorName.length > 0 ? TD_SENSITIVE_FIELDS[ctorName] : undefined;\n")
    out.append("  const knownConstructors: Record<string, boolean> = TD_KNOWN_CONSTRUCTORS;\n")
    out.append("  const known: boolean =\n")
    out.append("    ctorName.length > 0 && knownConstructors[ctorName] === true;\n")
    out.append("  const out: Record<string, TdJsonRaw> = {};\n")
    out.append("  for (const key of Object.keys(record)) {\n")
    out.append("    const value: TdJsonRaw = record[key];\n")
    out.append("    if (key === '@type') {\n")
    out.append("      out[key] = value;\n")
    out.append("      continue;\n")
    out.append("    }\n")
    out.append("    if (key === '@extra') {\n")
    out.append("      // 请求关联 id，属应用内部标识，部分遮蔽。\n")
    out.append("      out[key] = typeof value === 'string' ? maskString(value) : redactedValue(value);\n")
    out.append("      continue;\n")
    out.append("    }\n")
    out.append("    let policy: TdRedactPolicy;\n")
    out.append("    if (fieldRules !== undefined && fieldRules[key] !== undefined) {\n")
    out.append("      policy = fieldRules[key].policy;\n")
    out.append("    } else if (known) {\n")
    out.append("      // 已知构造器：未列入规则的字段按白名单制保留。\n")
    out.append("      policy = 'keep';\n")
    out.append("    } else {\n")
    out.append("      // 未知 @type（含空名）：按字段名子串保守遮蔽。\n")
    out.append("      policy = unknownTypePolicy(key);\n")
    out.append("    }\n")
    out.append("    if (policy === 'keep') {\n")
    out.append("      out[key] = redactAny(value);\n")
    out.append("    } else {\n")
    out.append("      out[key] = applyPolicy(value, policy);\n")
    out.append("    }\n")
    out.append("  }\n")
    out.append("  return out;\n")
    out.append("}\n")
    out.append("\n")
    out.append("/** 递归处理任意 JSON 值：记录按 @type 路由，数组逐元素，标量原样。 */\n")
    out.append("function redactAny(value: TdJsonRaw): TdJsonRaw {\n")
    out.append("  if (isRecord(value)) {\n")
    out.append("    const record = value as Record<string, TdJsonRaw>;\n")
    out.append("    const typeValue: TdJsonRaw = record['@type'];\n")
    out.append("    const ctorName: string = typeof typeValue === 'string' ? typeValue : '';\n")
    out.append("    return redactRecord(record, ctorName);\n")
    out.append("  }\n")
    out.append("  if (Array.isArray(value)) {\n")
    out.append("    const out: TdJsonRaw[] = [];\n")
    out.append("    for (const item of value) {\n")
    out.append("      out.push(redactAny(item));\n")
    out.append("    }\n")
    out.append("    return out;\n")
    out.append("  }\n")
    out.append("  return value;\n")
    out.append("}\n")
    out.append("\n")
    out.append("/**\n")
    out.append(" * 对 TDLib JSON 字符串按敏感字段元数据脱敏。永不抛错：\n")
    out.append(" * - 非法 JSON / 非对象输入 -> '«redacted»'（不允许把不可审计的内容原样放行）。\n")
    out.append(" * - 未知 @type -> 按字段名子串保守遮蔽疑似敏感字段。\n")
    out.append(" * 已知构造器未列入规则的字段默认 keep（白名单制，见计划 §14.4）。\n")
    out.append(" */\n")
    out.append("export function redactTdJson(json: string): string {\n")
    out.append("  let parsed: TdJsonRaw;\n")
    out.append("  try {\n")
    out.append("    parsed = JSON.parse(json) as TdJsonRaw;\n")
    out.append("  } catch (e) {\n")
    out.append("    return REDACTED_STRING;\n")
    out.append("  }\n")
    out.append("  if (!isRecord(parsed)) {\n")
    out.append("    return REDACTED_STRING;\n")
    out.append("  }\n")
    out.append("  return JSON.stringify(redactAny(parsed));\n")
    out.append("}\n")
    out.append("\n")
    out.append("/**\n")
    out.append(" * 基于生成 DTO 的深拷贝脱敏：encode -> redact -> decode。\n")
    out.append(" * decode 阶段未知字段会被丢弃（GEN-002 forward-compat 语义），\n")
    out.append(" * 如需保留未知字段请使用 redactTdJson。永不抛错。\n")
    out.append(" */\n")
    out.append("export function redactFields(obj: TdObject): TdObject {\n")
    out.append("  const wire: Record<string, TdJsonRaw> = encodeTdObject(obj);\n")
    out.append("  const redacted: Record<string, TdJsonRaw> = redactRecord(\n")
    out.append("    wire,\n")
    out.append("    wire['@type'] !== undefined && typeof wire['@type'] === 'string'\n")
    out.append("      ? (wire['@type'] as string)\n")
    out.append("      : ''\n")
    out.append("  );\n")
    out.append("  const decoded: TdObject | null = decodeTdObject(redacted);\n")
    out.append("  if (decoded === null) {\n")
    out.append("    return obj;\n")
    out.append("  }\n")
    out.append("  return decoded;\n")
    out.append("}\n")
    return "".join(out)


def build_files(ir: dict) -> dict:
    rules = compute_rules(ir)
    sensitive_types = compute_sensitive_types(ir, rules)
    return {
        SENSITIVE_FILE: gen_sensitive_fields(ir, rules, sensitive_types),
        REDACT_FILE: gen_redact(ir),
    }


def stats(ir: dict) -> dict:
    rules = compute_rules(ir)
    flagged_fields = sum(len(v) for v in rules.values())
    return {
        "schemaHash": ir["schemaHash"],
        "ctorsWithRules": len(rules),
        "flaggedFields": flagged_fields,
        "sensitiveTypes": len(compute_sensitive_types(ir, rules)),
        "exactRules": len(EXACT_RULES),
        "suffixRules": len(SUFFIX_RULES),
        "scopedRules": sum(len(v) for v in SCOPED_RULES.values()),
    }


def cmd_generate(args) -> int:
    ir = json.loads(IR_PATH.read_text(encoding="utf-8"))
    files = build_files(ir)
    for rel in sorted(files):
        path = OUT_ROOT / rel
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_text(files[rel], encoding="utf-8")
    s = stats(ir)
    print(f"schema hash: {ir['schemaHash']}")
    print(
        f"generated {len(files)} files: ctorsWithRules={s['ctorsWithRules']} "
        f"flaggedFields={s['flaggedFields']} sensitiveTypes={s['sensitiveTypes']}"
    )
    print(f"output: {(OUT_ROOT / OUT_DIR).relative_to(REPO_ROOT)}")
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
        s = stats(ir)
        print(f"OK — sensitive-field metadata is up to date ({json.dumps(s, sort_keys=True)})")
        return 0
    print("FAIL — regenerate with: python3 tools/td_api_codegen/td_api_sensitive.py generate")
    return 1


def cmd_info(args) -> int:
    ir = json.loads(IR_PATH.read_text(encoding="utf-8"))
    print(json.dumps(stats(ir), indent=2, sort_keys=True))
    rules = compute_rules(ir)
    by_policy: dict = {}
    for ctor in rules:
        for fname in rules[ctor]:
            p = rules[ctor][fname][0]
            by_policy[p] = by_policy.get(p, 0) + 1
    print("byPolicy:", json.dumps(by_policy, sort_keys=True))
    return 0


def main() -> int:
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    sub = ap.add_subparsers(dest="cmd", required=True)
    g = sub.add_parser("generate", help="write redaction metadata + helpers into core/td_api_generated")
    g.set_defaults(func=cmd_generate)
    v = sub.add_parser("verify", help="regenerate in-memory and diff against checked-in files (CI)")
    v.set_defaults(func=cmd_verify)
    i = sub.add_parser("info", help="print rule statistics")
    i.set_defaults(func=cmd_info)
    args = ap.parse_args()
    return args.func(args)


if __name__ == "__main__":
    sys.exit(main())
