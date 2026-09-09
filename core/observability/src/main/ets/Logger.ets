/**
 * core/observability — 白名单制脱敏 Logger（GEN-004 / OBS-001）。
 *
 * 计划 §14.4：日志按字段白名单输出，禁止先完整记录再正则脱敏。
 * 两道防线：
 *  1. 白名单（本文件）：只有显式标记可日志的字段才输出——按 TDLib @type
 *     逐字段声明，未声明字段一律不输出；未知 @type 只输出 @type 本身。
 *  2. 元数据脱敏（GEN-004 生成物 TdRedact）：白名单过滤后的 JSON 再过一遍
 *     敏感字段元数据，处理白名单遗漏/嵌套敏感字段（如
 *     authorizationStateWaitPassword.password_hint）。
 *
 * 禁止把 message.content / 聊天正文加入白名单（§14.4：真实聊天正文不得入日志）；
 * 需要消息排查信息时只白名单 id/date 级字段。
 */

import { AppError, AppErrors } from '@tgx/core-common';
import { TdJsonRaw } from '@tgx/td-api-generated/src/main/ets/runtime/TdJson';
import { TdObject, encodeTdObject } from '@tgx/td-api-generated/src/main/ets/types/TdEntries';
import { redactTdJson } from '@tgx/td-api-generated/src/main/ets/redaction/TdRedact';

export type LogLevel = 'debug' | 'info' | 'warn' | 'error';

/** level -> 权重（数值越大越严重）。 */
function levelWeight(level: LogLevel): number {
  switch (level) {
    case 'debug':
      return 10;
    case 'info':
      return 20;
    case 'warn':
      return 30;
    default:
      return 40;
  }
}

export type LogSink = (level: LogLevel, line: string) => void;

/** @type -> 允许输出的字段名（开放键映射；字面量请用空对象+索引赋值）。 */
export interface TdLogTypeFields extends Record<string, readonly string[]> {
}

/** TDLib 对象日志字段白名单。types 键为 wire @type 名，值为允许输出的字段名。 */
export interface TdLogWhitelist {
  /** @type -> 允许输出的字段名（蛇形 wire 名，不含 '@type'）。 */
  readonly types: TdLogTypeFields;
  /** 对所有类型生效的字段（如 '@extra' 请求关联 id）。 */
  readonly globalFields: readonly string[];
}

/**
 * 出厂白名单：只覆盖登录/连接/选项/错误等诊断必需且不含秘密的类型。
 * 维护流程见 core/observability/README.md；新增条目必须 review：
 * 该字段（含其子树）是否可能携带秘密、PII 或聊天正文。
 * （赋值方式构建：arkts linter 不接受带键字面量赋给开放键映射。）
 */
const DEFAULT_TYPES: TdLogTypeFields = {};
DEFAULT_TYPES['updateAuthorizationState'] = ['authorization_state'];
DEFAULT_TYPES['updateConnectionState'] = ['state'];
DEFAULT_TYPES['updateOption'] = ['name', 'value'];
DEFAULT_TYPES['error'] = ['code'];

export const DEFAULT_TD_LOG_WHITELIST: TdLogWhitelist = {
  types: DEFAULT_TYPES,
  globalFields: ['@extra'],
};

/**
 * 按白名单过滤一条 TDLib wire 记录的顶层字段。
 * '@type' 恒保留；其余字段须在 types[@type] 或 globalFields 中显式列出。
 * 不做递归过滤——保留的字段子树由 TdRedact 第二道防线细粒度脱敏。
 */
export function filterByWhitelist(
  record: Record<string, TdJsonRaw>,
  whitelist: TdLogWhitelist
): Record<string, TdJsonRaw> {
  const typeValue: TdJsonRaw = record['@type'];
  const typeName: string = typeof typeValue === 'string' ? typeValue : '';
  const types: TdLogTypeFields = whitelist.types;
  const allowed: readonly string[] | undefined = types[typeName];
  const globals: readonly string[] = whitelist.globalFields;
  const out: Record<string, TdJsonRaw> = {};
  for (const key of Object.keys(record)) {
    if (key === '@type') {
      out[key] = record[key];
      continue;
    }
    if (allowed !== undefined && allowed.indexOf(key) >= 0) {
      out[key] = record[key];
      continue;
    }
    if (globals.indexOf(key) >= 0) {
      out[key] = record[key];
    }
  }
  return out;
}

function defaultSink(level: LogLevel, line: string): void {
  if (typeof console === 'undefined') {
    return;
  }
  if (level === 'warn') {
    console.warn(line);
    return;
  }
  if (level === 'error') {
    console.error(line);
    return;
  }
  console.log(line);
}

/**
 * 白名单制 Logger。所有 TDLib 对象日志必经 filterByWhitelist + redactTdJson；
 * AppError 经 AppErrors.toLogString（只含 kind/code，不含 message/cause）。
 */
export class Logger {
  private readonly minLevel: LogLevel;
  private readonly sink: LogSink;
  private readonly whitelist: TdLogWhitelist;
  /** 最近一次 emit 的行（测试与内省用）。 */
  lastLine: string | null = null;
  /** 因 level 过滤未输出的累计条数。 */
  filteredCount: number = 0;

  constructor(
    minLevel: LogLevel = 'info',
    sink: LogSink = defaultSink,
    whitelist: TdLogWhitelist = DEFAULT_TD_LOG_WHITELIST
  ) {
    this.minLevel = minLevel;
    this.sink = sink;
    this.whitelist = whitelist;
  }

  isLoggable(level: LogLevel): boolean {
    return levelWeight(level) >= levelWeight(this.minLevel);
  }

  private emit(level: LogLevel, tag: string, event: string, payload?: string): string | null {
    if (!this.isLoggable(level)) {
      this.filteredCount += 1;
      return null;
    }
    const line: string =
      payload !== undefined
        ? `${level.toUpperCase()} ${tag} ${event} ${payload}`
        : `${level.toUpperCase()} ${tag} ${event}`;
    this.lastLine = line;
    this.sink(level, line);
    return line;
  }

  debug(tag: string, event: string, context?: string): string | null {
    return this.emit('debug', tag, event, context);
  }

  info(tag: string, event: string, context?: string): string | null {
    return this.emit('info', tag, event, context);
  }

  warn(tag: string, event: string, context?: string): string | null {
    return this.emit('warn', tag, event, context);
  }

  error(tag: string, event: string, context?: string): string | null {
    return this.emit('error', tag, event, context);
  }

  /**
   * AppError 日志：只输出 AppErrors.toLogString 的稳定分类串
   * （network/dns/retryable=true 这类），message/cause 永不入日志。
   */
  logError(tag: string, error: AppError): string | null {
    return this.emit('error', tag, 'error', AppErrors.toLogString(error));
  }

  /**
   * TDLib 对象日志（JSON 字符串入口）：白名单过滤 -> 元数据脱敏 -> 输出。
   * 输入非法 JSON 时不抛错，输出占位符（不可审计内容不放行）。
   */
  logTdJson(tag: string, event: string, json: string): string | null {
    let record: Record<string, TdJsonRaw>;
    try {
      const parsed: TdJsonRaw = JSON.parse(json) as TdJsonRaw;
      if (typeof parsed !== 'object' || parsed === null || Array.isArray(parsed)) {
        return this.emit('info', tag, event, redactTdJson(json));
      }
      record = parsed as Record<string, TdJsonRaw>;
    } catch (e) {
      return this.emit('info', tag, event, redactTdJson(json));
    }
    const filtered: Record<string, TdJsonRaw> = filterByWhitelist(record, this.whitelist);
    return this.emit('info', tag, event, redactTdJson(JSON.stringify(filtered)));
  }

  /** TDLib 对象日志（DTO 入口）：encode -> 白名单过滤 -> 元数据脱敏。 */
  logTdObject(tag: string, event: string, obj: TdObject): string | null {
    const wire: Record<string, TdJsonRaw> = encodeTdObject(obj);
    const filtered: Record<string, TdJsonRaw> = filterByWhitelist(wire, this.whitelist);
    return this.emit('info', tag, event, redactTdJson(JSON.stringify(filtered)));
  }
}
