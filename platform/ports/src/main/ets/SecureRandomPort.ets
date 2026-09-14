/**
 * platform/ports — SecureRandomPort：高熵密码学安全随机数生成契约。
 *
 * 承载 TDLib 数据库加密密钥（256 位 / 32 字节）、安全令牌、一次性挑战等生成需求。
 * 生产实现由 platform/keystore 基于 @kit.CryptoArchitectureKit 提供；
 * 测试注入 FakeSecureRandom 保证可控性或伪随机高熵分布。
 */

import { Result, AppError } from '@tgx/core-common';

export interface SecureRandomPort {
  /**
   * 生成指定长度的高熵密码学安全随机字节。
   *
   * @param length 生成字节数（必须大于 0）。
   * @returns 成功返回 Uint8Array，失败返回 AppError。
   */
  generateRandom(length: number): Promise<Result<Uint8Array, AppError>>;
}
