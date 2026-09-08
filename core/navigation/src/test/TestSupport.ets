import type { Result, AppError } from '@tgx/core-common';

export function mustOk<T>(result: Result<T, AppError>): T {
  return result.fold(
    (value: T) => value,
    (error: AppError) => {
      throw new Error(`expected Ok, got ${error.kind}: ${error.message}`);
    }
  );
}

export function mustErr<T>(result: Result<T, AppError>): AppError {
  if (result.ok === false) {
    return result.error;
  }
  throw new Error(`expected Err, got Ok`);
}

/** 取 parameter 错误的 field；非 parameter 错误返回空串（断言会失败）。 */
export function paramField(error: AppError): string {
  return error.kind === 'parameter' ? error.field : '';
}

/** 取 parameter 错误的 code；internal 错误返回 'internal'；其余返回空串。 */
export function paramCode(error: AppError): string {
  if (error.kind === 'parameter') {
    return error.code;
  }
  if (error.kind === 'internal') {
    return 'internal';
  }
  return '';
}
