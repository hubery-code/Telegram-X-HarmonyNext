/**
 * core/common — AppError 稳定错误结构（CORE-001）。
 *
 * 与迁移实施计划 §7「统一错误模型」对齐：
 * - kind 分类覆盖 network / tdlib / storage / parameter / platform / internal / unknown；
 * - code 为稳定的枚举式字符串（或平台数字码），message 为诊断文案（禁止直接当用户文案）；
 * - messageKey 供 UI 层做本地化映射（可选）；
 * - cause 为原始诊断信息（可选，仅日志/调试，不进用户文案）；
 * - TDLib 原始错误码经 fromTdlibError 映射为稳定错误，不把 error.message 透传出去。
 *
 * toLogString() 输出稳定、脱敏的分类串，供日志聚合使用。
 */

export type AppErrorKind =
  'network'
  | 'tdlib'
  | 'storage'
  | 'parameter'
  | 'platform'
  | 'internal'
  | 'unknown';

export type NetworkErrorCode =
  'dns'
  | 'timeout'
  | 'unreachable'
  | 'tls'
  | 'server'
  | 'unknown';

export type TdlibErrorCode =
  'unauthorized'
  | 'too_many_requests'
  | 'bad_request'
  | 'not_found'
  | 'internal'
  | 'unknown';

export type StorageErrorCode =
  'io'
  | 'quota_exceeded'
  | 'corrupted'
  | 'migration'
  | 'unknown';

export type ParameterErrorCode =
  'missing'
  | 'invalid'
  | 'out_of_range';

export interface NetworkAppError {
  readonly kind: 'network';
  readonly code: NetworkErrorCode;
  readonly message: string;
  readonly retryable: boolean;
  readonly messageKey?: string;
  readonly cause?: string;
}

export interface TdlibAppError {
  readonly kind: 'tdlib';
  readonly code: TdlibErrorCode;
  readonly message: string;
  readonly retryable: boolean;
  readonly messageKey?: string;
  readonly cause?: string;
}

export interface StorageAppError {
  readonly kind: 'storage';
  readonly code: StorageErrorCode;
  readonly message: string;
  readonly retryable: boolean;
  readonly messageKey?: string;
  readonly cause?: string;
}

export interface ParameterAppError {
  readonly kind: 'parameter';
  readonly code: ParameterErrorCode;
  readonly field: string;
  readonly message: string;
  readonly messageKey?: string;
  readonly cause?: string;
}

export interface PlatformAppError {
  readonly kind: 'platform';
  readonly code: number;
  readonly message: string;
  readonly retryable: boolean;
  readonly messageKey?: string;
  readonly cause?: string;
}

export interface InternalAppError {
  readonly kind: 'internal';
  readonly invariant: string;
  readonly message: string;
  readonly cause?: string;
}

export interface UnknownAppError {
  readonly kind: 'unknown';
  readonly origin: string;
  readonly message: string;
  readonly cause?: string;
}

export type AppError =
  NetworkAppError
  | TdlibAppError
  | StorageAppError
  | ParameterAppError
  | PlatformAppError
  | InternalAppError
  | UnknownAppError;

export class AppErrors {
  static network(
    code: NetworkErrorCode,
    message: string,
    retryable: boolean,
    messageKey?: string,
    cause?: string
  ): AppError {
    return { kind: 'network', code: code, message: message, retryable: retryable, messageKey: messageKey, cause: cause };
  }

  static tdlib(
    code: TdlibErrorCode,
    message: string,
    retryable: boolean,
    messageKey?: string,
    cause?: string
  ): AppError {
    return { kind: 'tdlib', code: code, message: message, retryable: retryable, messageKey: messageKey, cause: cause };
  }

  static storage(
    code: StorageErrorCode,
    message: string,
    retryable: boolean,
    messageKey?: string,
    cause?: string
  ): AppError {
    return { kind: 'storage', code: code, message: message, retryable: retryable, messageKey: messageKey, cause: cause };
  }

  static parameter(
    code: ParameterErrorCode,
    field: string,
    message: string,
    messageKey?: string,
    cause?: string
  ): AppError {
    return { kind: 'parameter', code: code, field: field, message: message, messageKey: messageKey, cause: cause };
  }

  static platform(
    code: number,
    message: string,
    retryable: boolean,
    messageKey?: string,
    cause?: string
  ): AppError {
    return { kind: 'platform', code: code, message: message, retryable: retryable, messageKey: messageKey, cause: cause };
  }

  static internal(invariant: string, message?: string, cause?: string): AppError {
    const text: string = message !== undefined ? message : `invariant violated: ${invariant}`;
    return { kind: 'internal', invariant: invariant, message: text, cause: cause };
  }

  static unknown(origin: string, message: string, cause?: string): AppError {
    return { kind: 'unknown', origin: origin, message: message, cause: cause };
  }

  /**
   * TDLib 数字错误码 → 稳定错误映射。
   * TDLib 的 error.message 只允许进入 cause（诊断/日志），不得直接作为用户文案。
   */
  static fromTdlibError(code: number, tdlibMessage: string): AppError {
    if (code === 401) {
      return AppErrors.tdlib('unauthorized', 'TDLib unauthorized', false, undefined, `${code}:${tdlibMessage}`);
    }
    if (code === 429) {
      return AppErrors.tdlib('too_many_requests', 'TDLib rate limited', true, undefined, `${code}:${tdlibMessage}`);
    }
    if (code === 400) {
      return AppErrors.tdlib('bad_request', 'TDLib rejected the request', false, undefined, `${code}:${tdlibMessage}`);
    }
    if (code === 404) {
      return AppErrors.tdlib('not_found', 'TDLib target not found', false, undefined, `${code}:${tdlibMessage}`);
    }
    if (code === 500) {
      return AppErrors.tdlib('internal', 'TDLib internal error', true, undefined, `${code}:${tdlibMessage}`);
    }
    return AppErrors.tdlib('unknown', 'TDLib request failed', true, undefined, `${code}:${tdlibMessage}`);
  }

  static isRetryable(error: AppError): boolean {
    switch (error.kind) {
      case 'network':
        return error.retryable;
      case 'tdlib':
        return error.retryable;
      case 'storage':
        return error.retryable;
      case 'platform':
        return error.retryable;
      default:
        return false;
    }
  }

  /**
   * 稳定、脱敏的日志表示：只含 kind/code/分类字段，不含 message/cause
   * （原始消息可能携带敏感信息，不进普通日志，见计划 §5.6 日志规则）。
   */
  static toLogString(error: AppError): string {
    switch (error.kind) {
      case 'network':
        return `network/${error.code}/retryable=${error.retryable}`;
      case 'tdlib':
        return `tdlib/${error.code}/retryable=${error.retryable}`;
      case 'storage':
        return `storage/${error.code}/retryable=${error.retryable}`;
      case 'parameter':
        return `parameter/${error.code}/field=${error.field}`;
      case 'platform':
        return `platform/${error.code}/retryable=${error.retryable}`;
      case 'internal':
        return `internal/${error.invariant}`;
      default:
        return `unknown/${error.origin}`;
    }
  }
}
