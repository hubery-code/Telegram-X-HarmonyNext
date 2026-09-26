/**
 * platform/keystore — SecureKeyStorePort 的 HarmonyOS Asset Store adapter（PLAT-003）。
 *
 * 基于 @kit.AssetStoreKit（asset）：关键资产明文由系统安全服务（TEE/安全芯片）加密托管，
 * adapter 自身不做密码学运算；alias = ALIAS_PREFIX + key 作为每条资产的唯一索引。
 *
 * 错误码分类、alias 前缀、探测码到可用性的归类都在 `core/AssetErrorMap.ets`（无 Kit、有单测）。
 * 本类只负责三件事：组 `asset.AssetMap`、调 `asset` 的同步/异步接口、把 catch 到的
 * 业务错误拆成 (code, message) 交给映射层。
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
 * 敏感值本身绝不进入 message/cause（cause 只含系统错误码与系统文案）。
 */

import { asset } from '@kit.AssetStoreKit';
import { util } from '@kit.ArkTS';
import { BusinessError } from '@ohos.base';
import { Result, AppError, ok, err, AppErrors } from '@tgx/core-common';
import {
  SecureKeyStoreStatus,
  SecureKeyStorePort,
  SecureKeyStoreAvailability
} from '@tgx/platform-ports';
import {
  ASSET_NOT_FOUND,
  aliasFor,
  mapAssetFailure,
  probeAvailability,
  validateKeyError
} from './core/AssetErrorMap';

const PROBE_ALIAS: string = aliasFor('__probe__');

function encodeAlias(key: string): Uint8Array {
  return new util.TextEncoder().encodeInto(aliasFor(key));
}

function businessErrorCode(e: Object): number | null {
  const be: BusinessError = e as BusinessError;
  if (be !== null && be !== undefined && typeof be.code === 'number') {
    return be.code;
  }
  return null;
}

function businessErrorMessage(e: Object): string | null {
  const be: BusinessError = e as BusinessError;
  if (be === null || be === undefined || be.message === undefined) {
    return null;
  }
  return be.message;
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
      const availability: SecureKeyStoreAvailability | null = probeAvailability(code);
      if (availability !== null) {
        return ok<SecureKeyStoreStatus, AppError>({ availability });
      }
      return err(mapAssetFailure('getStatus', code, businessErrorMessage(e)));
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
    const keyError: AppError | null = validateKeyError(key);
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
      return err<void, AppError>(mapAssetFailure('put', businessErrorCode(e), businessErrorMessage(e)));
    }
  }

  async get(key: string): Promise<Result<Uint8Array | null, AppError>> {
    const keyError: AppError | null = validateKeyError(key);
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
      return err<Uint8Array | null, AppError>(mapAssetFailure('get', code, businessErrorMessage(e)));
    }
  }

  async remove(key: string): Promise<Result<void, AppError>> {
    const keyError: AppError | null = validateKeyError(key);
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
      return err<void, AppError>(mapAssetFailure('remove', code, businessErrorMessage(e)));
    }
  }
}
