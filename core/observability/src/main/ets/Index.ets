/**
 * core/observability — 白名单制脱敏 Logger（GEN-004 / OBS-001）。
 * 纯 ArkTS，无 ArkUI / Kit 依赖。
 */

export { Logger, DEFAULT_TD_LOG_WHITELIST, filterByWhitelist } from './Logger';
export type { LogLevel, LogSink, TdLogWhitelist } from './Logger';
export { redactTdJson, redactFields } from '@tgx/td-api-generated/src/main/ets/redaction/TdRedact';
export { TD_SENSITIVE_FIELDS, TD_SENSITIVE_TYPES } from '@tgx/td-api-generated/src/main/ets/redaction/TdSensitiveFields';
