/**
 * platform/keystore — SecureKeyStorePort 的 HarmonyOS Asset Store adapter（PLAT-003）。
 *
 * 基于 @kit.AssetStoreKit（asset）：关键资产明文由系统安全服务（TEE/安全芯片）加密托管，
 * adapter 自身不做密码学运算；alias = ALIAS_PREFIX + key 作为每条资产的唯一索引。
 *
 * 锁屏语义（契约约定）：
 * - 资产以 ACCESSIBILITY = DEVICE_UNLOCKED 写入：设备锁屏期间 add/query/remove
 *   抛 STATUS_MISMATCH (24000005)，统一映射为
 *   err(platform/SECURE_KEY_STORE_LOCKED_PLATFORM_CODE, retryable=true)，解锁后重试预期成功；
 * - 未设置锁屏密码的设备上 DEVICE_UNLOCKED 退化为「开机后可访问」（系统行为），
 *   即该设备不存在 locked 状态；
 * - getStatus() 用 asset.querySync 探测一个永不写入的 probe alias（同步、不抛异常）：
 *   成功或 NOT_FOUND → available；STATUS_MISMATCH → locked；
 *   SERVICE_UNAVAILABLE → unavailable_no_hardware；UNSUPPORTED → unavailable_unsupported；
 *   ACCESS_DENIED / PERMISSION_DENIED → unavailable_disabled；其余错误 → err。
 *
 * 其余契约语义：
 * - 覆盖写：add 时 CONFLICT_RESOLUTION = OVERWRITE（覆盖已存在的同 key 值）；
 * - 缺失读：query 抛 NOT_FOUND → ok(null)；
 * - 幂等删：remove 抛 NOT_FOUND → ok(undefined)；
 * - 值按字节拷贝存取（slice()），调用方持有的数组不被后续修改影响；
 * - SYNC_TYPE = NEVER：密钥不参与跨设备同步/备份。
 *
 * 错误映射：
 * - 锁屏/服务不可用映射到契约稳定平台码（与 FakeSecureKeyStore 口径一致：
 *   locked = SECURE_KEY_STORE_LOCKED_PLATFORM_CODE retryable=true；
 *   unavailable = LOCKED_CODE + 1 retryable=false）；
 * - INVALID_ARGUMENT (401) 说明 adapter 属性组装有误 → internal；
 * - 其余 Asset 数字错误码原样作为 platform/<code>，retryable 按瞬时性分类
 *   （内存不足/数据库/IPC/系统服务失败 → true；损坏/算法/权限/不支持 → false）；
 * - 敏感值本身绝不进入 message/cause（cause 只含系统错误码与系统文案）。
 */

import { asset } from '@kit.AssetStoreKit';
import { util } from '@kit.ArkTS';
import { BusinessError } from '@ohos.base';
import { Result, AppError, ok, err, AppErrors } from '@tgx/core-common';
import {
  SECURE_KEY_STORE_LOCKED_PLATFORM_CODE,
  SecureKeyStoreStatus,
  SecureKeyStorePort
} from '@tgx/platform-ports';

const ALIAS_PREFIX: string = 'tgx.keystore.';
const PROBE_ALIAS: string = ALIAS_PREFIX + '__probe__';

const ASSET_PERMISSION_DENIED: number = 201;
const ASSET_INVALID_ARGUMENT: number = 401;
const ASSET_SERVICE_UNAVAILABLE: number = 24000001;
const ASSET_NOT_FOUND: number = 24000002;
const ASSET_ACCESS_DENIED: number = 24000004;
const ASSET_STATUS_MISMATCH: number = 24000005;
const ASSET_OUT_OF_MEMORY: number = 24000006;
const ASSET_DATABASE_ERROR: number = 24000008;
const ASSET_IPC_ERROR: number = 24000010;
const ASSET_BMS_ERROR: number = 24000011;
const ASSET_ACCOUNT_ERROR: number = 24000012;
const ASSET_ACCESS_TOKEN_ERROR: number = 24000013;
const ASSET_FILE_OPERATION_ERROR: number = 24000014;
const ASSET_GET_SYSTEM_TIME_ERROR: number = 24000015;
const ASSET_UNSUPPORTED: number = 24000017;

/** 不可用状态使用的稳定平台错误码（与 FakeSecureKeyStore 口径一致）。 */
const SECURE_KEY_STORE_UNAVAILABLE_PLATFORM_CODE: number = SECURE_KEY_STORE_LOCKED_PLATFORM_CODE + 1;

function encodeAlias(key: string): Uint8Array {
  return new util.TextEncoder().encodeInto(ALIAS_PREFIX + key);
}

function businessErrorCode(e: Object): number | null {
  const be: BusinessError = e as BusinessError;
  if (be !== null && be !== undefined && typeof be.code === 'number') {
    return be.code;
  }
  return null;
}

function isRetryableAssetError(code: number): boolean {
  return code === ASSET_OUT_OF_MEMORY
    || code === ASSET_DATABASE_ERROR
    || code === ASSET_IPC_ERROR
    || code === ASSET_BMS_ERROR
    || code === ASSET_ACCOUNT_ERROR
    || code === ASSET_ACCESS_TOKEN_ERROR
    || code === ASSET_FILE_OPERATION_ERROR
    || code === ASSET_GET_SYSTEM_TIME_ERROR;
}

function mapAssetError(origin: string, e: Object): AppError {
  const code: number | null = businessErrorCode(e);
  if (code === null) {
    return AppErrors.unknown(origin, `${origin} failed (non-business error)`);
  }
  const be: BusinessError = e as BusinessError;
  const cause: string = `${code}:${be.message}`;
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
  return AppErrors.platform(code, `${origin} failed`, isRetryableAssetError(code), undefined, cause);
}

function validateKey(key: string): AppError | null {
  if (key.length === 0) {
    return AppErrors.parameter('invalid', 'key', 'key must not be empty');
  }
  return null;
}

export class HarmonySecureKeyStore implements SecureKeyStorePort {
  getStatus(): Result<SecureKeyStoreStatus, AppError> {
    const probe: asset.AssetMap = new Map<asset.Tag, asset.Value>();
    probe.set(asset.Tag.ALIAS, new util.TextEncoder().encodeInto(PROBE_ALIAS));
    probe.set(asset.Tag.RETURN_TYPE, asset.ReturnType.ATTRIBUTES);
    try {
      asset.querySync(probe);
      return ok<SecureKeyStoreStatus, AppError>({ availability: 'available' });
    } catch (e) {
      const code: number | null = businessErrorCode(e);
      if (code === null) {
        return err(AppErrors.unknown('getStatus', 'getStatus probe failed (non-business error)'));
      }
      if (code === ASSET_NOT_FOUND) {
        return ok<SecureKeyStoreStatus, AppError>({ availability: 'available' });
      }
      if (code === ASSET_STATUS_MISMATCH) {
        return ok<SecureKeyStoreStatus, AppError>({ availability: 'locked' });
      }
      if (code === ASSET_SERVICE_UNAVAILABLE) {
        return ok<SecureKeyStoreStatus, AppError>({ availability: 'unavailable_no_hardware' });
      }
      if (code === ASSET_UNSUPPORTED) {
        return ok<SecureKeyStoreStatus, AppError>({ availability: 'unavailable_unsupported' });
      }
      if (code === ASSET_ACCESS_DENIED || code === ASSET_PERMISSION_DENIED) {
        return ok<SecureKeyStoreStatus, AppError>({ availability: 'unavailable_disabled' });
      }
      return err(mapAssetError('getStatus', e));
    }
  }

  isAvailable(): Result<boolean, AppError> {
    const status: Result<SecureKeyStoreStatus, AppError> = this.getStatus();
    return status.fold(
      (s: SecureKeyStoreStatus) => ok<boolean, AppError>(s.availability === 'available'),
      (error: AppError) => err<boolean, AppError>(error)
    );
  }

  async put(key: string, value: Uint8Array): Promise<Result<void, AppError>> {
    const keyError: AppError | null = validateKey(key);
    if (keyError !== null) {
      return err<void, AppError>(keyError);
    }
    const attributes: asset.AssetMap = new Map<asset.Tag, asset.Value>();
    attributes.set(asset.Tag.ALIAS, encodeAlias(key));
    attributes.set(asset.Tag.SECRET, value.slice());
    attributes.set(asset.Tag.ACCESSIBILITY, asset.Accessibility.DEVICE_UNLOCKED);
    attributes.set(asset.Tag.SYNC_TYPE, asset.SyncType.NEVER);
    attributes.set(asset.Tag.CONFLICT_RESOLUTION, asset.ConflictResolution.OVERWRITE);
    try {
      await asset.add(attributes);
      return ok<void, AppError>(undefined);
    } catch (e) {
      return err<void, AppError>(mapAssetError('put', e));
    }
  }

  async get(key: string): Promise<Result<Uint8Array | null, AppError>> {
    const keyError: AppError | null = validateKey(key);
    if (keyError !== null) {
      return err<Uint8Array | null, AppError>(keyError);
    }
    const query: asset.AssetMap = new Map<asset.Tag, asset.Value>();
    query.set(asset.Tag.ALIAS, encodeAlias(key));
    query.set(asset.Tag.RETURN_TYPE, asset.ReturnType.ALL);
    try {
      const results: Array<asset.AssetMap> = await asset.query(query);
      if (results.length === 0) {
        return ok<Uint8Array | null, AppError>(null);
      }
      const secret: asset.Value | undefined = results[0].get(asset.Tag.SECRET);
      if (secret === undefined || !(secret instanceof Uint8Array)) {
        return err<Uint8Array | null, AppError>(AppErrors.internal(
          'asset-secret-missing',
          'get succeeded but SECRET attribute is absent or not bytes'
        ));
      }
      return ok<Uint8Array | null, AppError>(secret.slice());
    } catch (e) {
      const code: number | null = businessErrorCode(e);
      if (code === ASSET_NOT_FOUND) {
        return ok<Uint8Array | null, AppError>(null);
      }
      return err<Uint8Array | null, AppError>(mapAssetError('get', e));
    }
  }

  async remove(key: string): Promise<Result<void, AppError>> {
    const keyError: AppError | null = validateKey(key);
    if (keyError !== null) {
      return err<void, AppError>(keyError);
    }
    const query: asset.AssetMap = new Map<asset.Tag, asset.Value>();
    query.set(asset.Tag.ALIAS, encodeAlias(key));
    try {
      await asset.remove(query);
      return ok<void, AppError>(undefined);
    } catch (e) {
      const code: number | null = businessErrorCode(e);
      if (code === ASSET_NOT_FOUND) {
        return ok<void, AppError>(undefined);
      }
      return err<void, AppError>(mapAssetError('remove', e));
    }
  }
}
