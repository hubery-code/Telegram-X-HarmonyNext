/**
 * platform/ports — FakeSecureKeyStore（PLAT-001）。
 *
 * SecureKeyStorePort 的内存实现，模拟硬件安全存储语义：
 * - setLocked(true) 进入锁屏状态：get/put/remove 返回 err(platform/SECURE_KEY_STORE_LOCKED_PLATFORM_CODE)，
 *   getStatus() 报告 locked；setLocked(false) 解锁后同一调用预期成功；
 * - setAvailable(false) 模拟设备无安全硬件/能力：status 报 unavailable_no_hardware，
 *   读写返回 err(platform/…, retryable=false)；
 * - 值按字节拷贝存取，避免调用方持有的数组被后续修改影响；
 * - key 不存在时 get 返回 ok(null)；remove 幂等。
 */

import { Result, AppError, ok, err, AppErrors } from '@tgx/core-common';
import {
  SECURE_KEY_STORE_LOCKED_PLATFORM_CODE,
  SecureKeyStoreStatus,
  SecureKeyStorePort
} from '../SecureKeyStorePort';

export class FakeSecureKeyStore implements SecureKeyStorePort {
  private data: Map<string, Uint8Array> = new Map();
  private locked: boolean = false;
  private available: boolean = true;

  /** 测试驱动：模拟锁屏/解锁。 */
  setLocked(locked: boolean): void {
    this.locked = locked;
  }

  /** 测试驱动：模拟安全能力缺失（无硬件 / 被禁用）。 */
  setAvailable(available: boolean): void {
    this.available = available;
  }

  getStatus(): Result<SecureKeyStoreStatus, AppError> {
    if (!this.available) {
      return ok<SecureKeyStoreStatus, AppError>({ availability: 'unavailable_no_hardware' });
    }
    if (this.locked) {
      return ok<SecureKeyStoreStatus, AppError>({ availability: 'locked' });
    }
    return ok<SecureKeyStoreStatus, AppError>({ availability: 'available' });
  }

  isAvailable(): Result<boolean, AppError> {
    const status: Result<SecureKeyStoreStatus, AppError> = this.getStatus();
    return status.fold(
      (s: SecureKeyStoreStatus) => ok<boolean, AppError>(s.availability === 'available'),
      (error: AppError) => err<boolean, AppError>(error)
    );
  }

  async put(key: string, value: Uint8Array): Promise<Result<void, AppError>> {
    const guard: Result<void, AppError> = this.guardAccess();
    if (guard.ok === false) {
      return err(guard.error);
    }
    this.data.set(key, value.slice());
    return ok(undefined);
  }

  async get(key: string): Promise<Result<Uint8Array | null, AppError>> {
    const guard: Result<void, AppError> = this.guardAccess();
    if (guard.ok === false) {
      return err(guard.error);
    }
    const stored: Uint8Array | undefined = this.data.get(key);
    if (stored === undefined) {
      return ok(null);
    }
    return ok(stored.slice());
  }

  async remove(key: string): Promise<Result<void, AppError>> {
    const guard: Result<void, AppError> = this.guardAccess();
    if (guard.ok === false) {
      return err(guard.error);
    }
    this.data.delete(key);
    return ok(undefined);
  }

  private guardAccess(): Result<void, AppError> {
    if (!this.available) {
      return err(AppErrors.platform(
        SECURE_KEY_STORE_LOCKED_PLATFORM_CODE + 1,
        'secure key store unavailable on this device',
        false
      ));
    }
    if (this.locked) {
      return err(AppErrors.platform(
        SECURE_KEY_STORE_LOCKED_PLATFORM_CODE,
        'secure key store is locked (device locked)',
        true
      ));
    }
    return ok(undefined);
  }
}
