/**
 * platform/ports — FakeSecureRandom。
 *
 * SecureRandomPort 的测试实现：
 * - 默认使用随机数填充（Math.random 混合散列）；
 * - setPresetBytes() 允许注入固定的测试字节（确定性测试）；
 * - setFailure() 允许注入错误（测试错误回滚路径）。
 */

import { Result, AppError, ok, err, AppErrors } from '@tgx/core-common';
import { SecureRandomPort } from '../SecureRandomPort';

export class FakeSecureRandom implements SecureRandomPort {
  private presetBytes: Uint8Array | null = null;
  private failureError: AppError | null = null;

  setPresetBytes(bytes: Uint8Array | null): void {
    this.presetBytes = bytes !== null ? bytes.slice() : null;
  }

  setFailure(error: AppError | null): void {
    this.failureError = error;
  }

  async generateRandom(length: number): Promise<Result<Uint8Array, AppError>> {
    if (length <= 0) {
      return err(AppErrors.parameter('invalid', 'length', 'length must be greater than 0'));
    }

    if (this.failureError !== null) {
      return err(this.failureError);
    }

    if (this.presetBytes !== null) {
      if (this.presetBytes.length !== length) {
        return err(AppErrors.parameter(
          'invalid',
          'length',
          `preset bytes length ${this.presetBytes.length} does not match requested length ${length}`
        ));
      }
      return ok(this.presetBytes.slice());
    }

    const bytes: Uint8Array = new Uint8Array(length);
    for (let i = 0; i < length; i++) {
      bytes[i] = Math.floor(Math.random() * 256);
    }
    return ok(bytes);
  }
}
