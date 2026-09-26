/**
 * platform/keystore — `core/AssetErrorMap.ets` 单元测试（APPLOCK-102）。
 *
 * 这块映射是应用锁的「故障语义」总闸：`getStatus()` 把「说不清」归类成 available
 * 还是 err，决定了锁屏遮罩到底能不能读写资产；`mapAssetFailure` 的 retryable 决定
 * 上层是重试还是提示。两条都只能靠喂码表来测，真机上反而造不出这些状态。
 *
 * 守住的回归：
 * 1. 只有 STATUS_MISMATCH 才是「锁屏」，且必须映射成契约的稳定平台码 + retryable=true；
 * 2. 探测码归类**不确定时必须回 null**（调用方转成错误），不能顺手算 available ——
 *    把未知当可用，等于在安全服务异常期间允许写密钥；
 * 3. 瞬时/确定性分类的边界（权限、不支持、损坏不重试）；
 * 4. alias 前缀统一，空 key 拦在参数层。
 */

import { describe, it, expect } from '@ohos/hypium';
import { AppError } from '@tgx/core-common';
import { SECURE_KEY_STORE_LOCKED_PLATFORM_CODE } from '@tgx/platform-ports';
import {
  ALIAS_PREFIX,
  ASSET_ACCESS_DENIED,
  ASSET_ACCOUNT_ERROR,
  ASSET_ACCESS_TOKEN_ERROR,
  ASSET_BMS_ERROR,
  ASSET_DATABASE_ERROR,
  ASSET_FILE_OPERATION_ERROR,
  ASSET_GET_SYSTEM_TIME_ERROR,
  ASSET_INVALID_ARGUMENT,
  ASSET_IPC_ERROR,
  ASSET_NOT_FOUND,
  ASSET_OUT_OF_MEMORY,
  ASSET_PERMISSION_DENIED,
  ASSET_SERVICE_UNAVAILABLE,
  ASSET_STATUS_MISMATCH,
  ASSET_UNSUPPORTED,
  PROBE_ALIAS,
  SECURE_KEY_STORE_UNAVAILABLE_PLATFORM_CODE,
  aliasFor,
  isRetryableAssetCode,
  mapAssetFailure,
  probeAvailability,
  validateKeyError
} from '../main/ets/core/AssetErrorMap';

export default function assetErrorMapTest(): void {
  describe('AssetErrorMapTest', () => {

    it('lockedMapsToContractCodeAndIsRetryable', 0, () => {
      // 锁屏是可恢复状态：解锁后同一次调用应当成功，所以 retryable 必须是 true。
      const error: AppError = mapAssetFailure('get', ASSET_STATUS_MISMATCH, 'locked');
      const text: string = JSON.stringify(error);
      expect(error.kind).assertEqual('platform');
      expect(text.indexOf(String(SECURE_KEY_STORE_LOCKED_PLATFORM_CODE)) >= 0).assertTrue();
      expect(text.indexOf('true') >= 0).assertTrue();
    });

    it('unavailableHasItsOwnStableCode', 0, () => {
      const error: AppError = mapAssetFailure('put', ASSET_SERVICE_UNAVAILABLE, null);
      const text: string = JSON.stringify(error);
      expect(error.kind).assertEqual('platform');
      expect(text.indexOf(String(SECURE_KEY_STORE_UNAVAILABLE_PLATFORM_CODE)) >= 0).assertTrue();
      // 与 locked 是两个不同的码：上层「等设备解锁」和「换实现」是两种处理。
      expect(SECURE_KEY_STORE_UNAVAILABLE_PLATFORM_CODE === SECURE_KEY_STORE_LOCKED_PLATFORM_CODE).assertFalse();
    });

    it('invalidArgumentIsAnInternalBugNotADeviceState', 0, () => {
      const error: AppError = mapAssetFailure('put', ASSET_INVALID_ARGUMENT, 'bad map');
      expect(JSON.stringify(error).indexOf('asset-invalid-argument') >= 0).assertTrue();
    });

    it('nonBusinessThrowBecomesUnknown', 0, () => {
      const error: AppError = mapAssetFailure('remove', null, 'whatever');
      expect(error.kind).assertEqual('unknown');
    });

    it('retryableSplitIsExact', 0, () => {
      const transient: number[] = [
        ASSET_OUT_OF_MEMORY,
        ASSET_DATABASE_ERROR,
        ASSET_IPC_ERROR,
        ASSET_BMS_ERROR,
        ASSET_ACCOUNT_ERROR,
        ASSET_ACCESS_TOKEN_ERROR,
        ASSET_FILE_OPERATION_ERROR,
        ASSET_GET_SYSTEM_TIME_ERROR
      ];
      for (let i = 0; i < transient.length; i++) {
        expect(isRetryableAssetCode(transient[i])).assertTrue();
      }
      // 确定性失败：重试只会让用户多等一轮。
      expect(isRetryableAssetCode(ASSET_STATUS_MISMATCH)).assertFalse();
      expect(isRetryableAssetCode(ASSET_SERVICE_UNAVAILABLE)).assertFalse();
      expect(isRetryableAssetCode(ASSET_NOT_FOUND)).assertFalse();
      expect(isRetryableAssetCode(ASSET_ACCESS_DENIED)).assertFalse();
      expect(isRetryableAssetCode(ASSET_UNSUPPORTED)).assertFalse();
    });

    it('probeCodesClassifyOnlyWhatTheyKnow', 0, () => {
      expect(probeAvailability(ASSET_NOT_FOUND)).assertEqual('available');
      expect(probeAvailability(ASSET_STATUS_MISMATCH)).assertEqual('locked');
      expect(probeAvailability(ASSET_SERVICE_UNAVAILABLE)).assertEqual('unavailable_no_hardware');
      expect(probeAvailability(ASSET_UNSUPPORTED)).assertEqual('unavailable_unsupported');
      expect(probeAvailability(ASSET_ACCESS_DENIED)).assertEqual('unavailable_disabled');
      expect(probeAvailability(ASSET_PERMISSION_DENIED)).assertEqual('unavailable_disabled');
      // 未知码必须是 null → 调用方成一条错误。回 'available' 就等于在异常期间放行读写。
      expect(probeAvailability(ASSET_DATABASE_ERROR) === null).assertTrue();
      expect(probeAvailability(ASSET_INVALID_ARGUMENT) === null).assertTrue();
      expect(probeAvailability(0) === null).assertTrue();
    });

    it('aliasIsPrefixedAndKeyValidated', 0, () => {
      expect(aliasFor('applock.passcode')).assertEqual(ALIAS_PREFIX + 'applock.passcode');
      // probe alias 不能撞上任何真实 key，否则 getStatus 会把「探测到资产」当成 available。
      expect(PROBE_ALIAS).assertEqual(ALIAS_PREFIX + '__probe__');
      expect(validateKeyError('') !== null).assertTrue();
      expect(validateKeyError('applock.passcode') === null).assertTrue();
    });

    it('causeNeverCarriesSecretBytes', 0, () => {
      // 映射层只接 (code, message)，结构上就拿不到 SECRET；这里守住 cause 的形状。
      const error: AppError = mapAssetFailure('get', ASSET_UNSUPPORTED, 'no biometric hardware');
      const text: string = JSON.stringify(error);
      expect(text.indexOf('24000017:no biometric hardware') >= 0).assertTrue();
      expect(text.indexOf('SECRET') < 0).assertTrue();
    });
  });
}
