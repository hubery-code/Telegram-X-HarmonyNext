/**
 * platform/keystore — Asset Store 错误与别名的纯映射（APPLOCK-102）。
 *
 * 从 `HarmonySecureKeyStore` 里拆出来的是**不含任何 Kit 调用**的那一半：
 * 系统错误码常量、可重试分类、`AppError` 映射、`getStatus()` 探测码到可用性枚举的归类，
 * 以及 alias 前缀。拆出来的理由不是整洁：带 `asset` 调用的那半在 CI 里跑不动
 * （要真实安全服务与锁屏状态），只有落进本文件的判据才谈得上被单测守住。
 *
 * 因此本文件的入参一律是**原始值**（`code: number | null`、`message: string | null`），
 * 不接 `BusinessError`：adapter 负责从 catch 到的对象里取这两个字段，
 * 本文件则保持零 Kit 依赖、可在单测里直接喂码表。
 */

import { AppError, AppErrors } from '@tgx/core-common';
import {
  SECURE_KEY_STORE_LOCKED_PLATFORM_CODE,
  SecureKeyStoreAvailability
} from '@tgx/platform-ports';

/** 安全存储中所有 key 的统一前缀（隔离同名资产）。 */
export const ALIAS_PREFIX: string = 'tgx.keystore.';

/** `getStatus()` 的探测 alias：永不写入，只用来问「现在能不能查」。 */
export const PROBE_ALIAS: string = ALIAS_PREFIX + '__probe__';

export const ASSET_PERMISSION_DENIED: number = 201;
export const ASSET_INVALID_ARGUMENT: number = 401;
export const ASSET_SERVICE_UNAVAILABLE: number = 24000001;
export const ASSET_NOT_FOUND: number = 24000002;
export const ASSET_ACCESS_DENIED: number = 24000004;
export const ASSET_STATUS_MISMATCH: number = 24000005;
export const ASSET_OUT_OF_MEMORY: number = 24000006;
export const ASSET_DATABASE_ERROR: number = 24000008;
export const ASSET_IPC_ERROR: number = 24000010;
export const ASSET_BMS_ERROR: number = 24000011;
export const ASSET_ACCOUNT_ERROR: number = 24000012;
export const ASSET_ACCESS_TOKEN_ERROR: number = 24000013;
export const ASSET_FILE_OPERATION_ERROR: number = 24000014;
export const ASSET_GET_SYSTEM_TIME_ERROR: number = 24000015;
export const ASSET_UNSUPPORTED: number = 24000017;

/** 不可用状态使用的稳定平台错误码（与 FakeSecureKeyStore 口径一致）。 */
export const SECURE_KEY_STORE_UNAVAILABLE_PLATFORM_CODE: number = SECURE_KEY_STORE_LOCKED_PLATFORM_CODE + 1;

/** key → 资产 alias。空 key 由 `validateKeyError` 拦，不在这里补默认值。 */
export function aliasFor(key: string): string {
  return ALIAS_PREFIX + key;
}

/** 空 key 是本类调用方的编程错误，不是设备状态：报 parameter，不让它变成一条 alias。 */
export function validateKeyError(key: string): AppError | null {
  if (key.length === 0) {
    return AppErrors.parameter('invalid', 'key', 'key must not be empty');
  }
  return null;
}

/**
 * 瞬时性分类：内存不足 / 数据库 / IPC / 系统服务侧的失败重试有意义；
 * 损坏、权限、不支持这类是确定性失败，重试只是让用户多等一轮。
 */
export function isRetryableAssetCode(code: number): boolean {
  return code === ASSET_OUT_OF_MEMORY
    || code === ASSET_DATABASE_ERROR
    || code === ASSET_IPC_ERROR
    || code === ASSET_BMS_ERROR
    || code === ASSET_ACCOUNT_ERROR
    || code === ASSET_ACCESS_TOKEN_ERROR
    || code === ASSET_FILE_OPERATION_ERROR
    || code === ASSET_GET_SYSTEM_TIME_ERROR;
}

/**
 * 系统失败 → `AppError`。
 * `code === null` 表示 catch 到的不是业务错误对象（不该发生，但发生时必须成一条错误
 * 而不是让读写路径抛异常）。`cause` 只带错误码与系统文案，敏感值不进这里。
 */
export function mapAssetFailure(origin: string, code: number | null, message: string | null): AppError {
  if (code === null) {
    return AppErrors.unknown(origin, `${origin} failed (non-business error)`);
  }
  const cause: string = `${code}:${message === null ? '' : message}`;
  if (code === ASSET_STATUS_MISMATCH) {
    return AppErrors.platform(
      SECURE_KEY_STORE_LOCKED_PLATFORM_CODE,
      'secure key store is locked (device locked)',
      true,
      undefined,
      cause
    );
  }
  if (code === ASSET_SERVICE_UNAVAILABLE) {
    return AppErrors.platform(
      SECURE_KEY_STORE_UNAVAILABLE_PLATFORM_CODE,
      'secure key store unavailable on this device',
      false,
      undefined,
      cause
    );
  }
  if (code === ASSET_INVALID_ARGUMENT) {
    return AppErrors.internal(
      'asset-invalid-argument',
      `${origin} rejected by asset store parameter check`,
      cause
    );
  }
  return AppErrors.platform(code, `${origin} failed`, isRetryableAssetCode(code), undefined, cause);
}

/**
 * `getStatus()` 探测结果的归类：返回 `null` 表示这个码不归本函数管，
 * 调用方回落到 `mapAssetFailure` 成一条错误 —— 「说不清」必须表现为错误，
 * 不能表现为 available，否则锁屏期间会被当成可以读写。
 */
export function probeAvailability(code: number): SecureKeyStoreAvailability | null {
  if (code === ASSET_NOT_FOUND) {
    return 'available';
  }
  if (code === ASSET_STATUS_MISMATCH) {
    return 'locked';
  }
  if (code === ASSET_SERVICE_UNAVAILABLE) {
    return 'unavailable_no_hardware';
  }
  if (code === ASSET_UNSUPPORTED) {
    return 'unavailable_unsupported';
  }
  if (code === ASSET_ACCESS_DENIED || code === ASSET_PERMISSION_DENIED) {
    return 'unavailable_disabled';
  }
  return null;
}
