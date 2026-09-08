/**
 * platform/ports — SecureKeyStorePort 安全密钥存储契约（PLAT-001）。
 *
 * 承载 TDLib database encryption key、账号令牌、代理凭据等敏感数据（计划 §5.6）。
 * 生产实现由 PLAT-003 基于 Asset Store / HUKS 提供；本模块只定义契约 + Fake。
 *
 * 语义约定：
 * - 值为二进制（Uint8Array），不做任何编码假设；
 * - 全部操作为异步（真实硬件-backed 存储可能涉及密码学运算）；
 * - 锁屏语义：设备锁屏时密钥不可访问，get/put/remove 返回
 *   err(platform/SECURE_KEY_STORE_LOCKED_PLATFORM_CODE, retryable=true)，
 *   解锁后同一调用预期成功；getStatus() 必须在锁屏状态下如实报告 locked；
 * - 可用性查询先于任何读写：不可用实现应让 getStatus() 返回
 *   unavailable_* 并让读写返回 err，而不是抛异常；
 * - key 不存在时 get 返回 ok(null)（与 Preferences 口径一致）；
 * - 错误统一用 Result<_, AppError>；敏感值本身绝不进入 message/cause。
 */

import { Result, AppError } from '@tgx/core-common';

/** 锁屏状态下读写被拦截时使用的稳定平台错误码（文档约定，非 HUKS 原始码）。 */
export const SECURE_KEY_STORE_LOCKED_PLATFORM_CODE: number = 48151623;

/** 可用性枚举：available / locked / unavailable_*。 */
export type SecureKeyStoreAvailability =
  'available'
  | 'locked'
  | 'unavailable_no_hardware'
  | 'unavailable_unsupported'
  | 'unavailable_disabled';

export interface SecureKeyStoreStatus {
  readonly availability: SecureKeyStoreAvailability;
}

export interface SecureKeyStorePort {
  /** 查询当前可用性（含锁屏状态）；不抛异常。 */
  getStatus(): Result<SecureKeyStoreStatus, AppError>;

  /** 便捷判断：availability 为 available 时为 true。 */
  isAvailable(): Result<boolean, AppError>;

  /** 存入密钥；覆盖已存在的同 key 值。 */
  put(key: string, value: Uint8Array): Promise<Result<void, AppError>>;

  /** 读取密钥；不存在返回 ok(null)。 */
  get(key: string): Promise<Result<Uint8Array | null, AppError>>;

  /** 移除密钥；不存在的 key 视为成功（幂等）。 */
  remove(key: string): Promise<Result<void, AppError>>;
}
