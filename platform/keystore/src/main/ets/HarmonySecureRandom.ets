/**
 * platform/keystore — HarmonySecureRandom。
 *
 * SecureRandomPort 的 HarmonyOS 生产实现。
 * 基于 @kit.CryptoArchitectureKit 的 cryptoFramework.createRandom()，
 * 由系统安全服务（硬件/内核安全随机数池）提供密码学安全的高熵随机字节。
 */

import { cryptoFramework } from '@kit.CryptoArchitectureKit';
import { Result, AppError, ok, err, AppErrors } from '@tgx/core-common';
import { SecureRandomPort } from '@tgx/platform-ports';

export class HarmonySecureRandom implements SecureRandomPort {
  private random: cryptoFramework.Random | null = null;

  constructor() {
    if (canIUse('SystemCapability.Security.CryptoFramework')) {
      this.random = cryptoFramework.createRandom();
    }
  }

  async generateRandom(length: number): Promise<Result<Uint8Array, AppError>> {
    if (length <= 0) {
      return err(AppErrors.parameter('invalid', 'length', 'length must be greater than 0'));
    }

    if (this.random === null) {
      return err(AppErrors.platform(
        -1,
        'CryptoFramework is not supported on this device',
        false
      ));
    }

    try {
      const blob: cryptoFramework.DataBlob = await this.random.generateRandom(length);
      return ok(blob.data);
    } catch (e) {
      const message: string = e instanceof Error ? e.message : String(e);
      return err(AppErrors.platform(
        -1,
        'failed to generate cryptographically secure random bytes',
        false,
        undefined,
        message
      ));
    }
  }
}
