/**
 * entry 装配层 — 应用锁存储实现（APPLOCK-101）。
 *
 * 契约在 `core/domain`（`AppLockStore`），这里把它接到两个真实的持久化面上：
 * - **档位**：`preferences`（`store/SettingsStore.ets` 那份已验证可用的实现）里的一个
 *   小整数。非敏感，可读可写，脏值由 `autoLockChoiceAt` 收敛到默认档。
 * - **PIN 派生值**：`PasscodeStorePort`（`platform/keystore` 走系统安全存储）。
 *
 * ## 为什么要缓存「是否已设 PIN」
 *
 * `AppLockStore.isPasscodeSet()` 是**同步**的 —— 前后台切换、页面首帧都要问，而安全存储
 * 的查询是异步 IPC。所以约定：进程启动时 `refreshPasscodeSet()` 读一次盘，之后缓存只由
 * 本类的写操作（set/remove）刷新。缓存不会因为外部（系统清理）改动而自动同步，这是
 * 有意的取舍：宁可下次启动纠正，也不在热路径上等一次 IPC。
 */

import {
  AppLockStore,
  AutoLockChoice,
  autoLockChoiceAt,
  autoLockStoredIndex
} from '@tgx/core-domain';
import { AppError, Result, ok, err } from '@tgx/core-common';
import { PasscodeStorePort } from '@tgx/platform-ports';
import { readSettingsNumber, writeSettingsNumber } from './SettingsStore';

/** 自动锁定档位在偏好里的键；值是 `AUTO_LOCK_CHOICES` 的索引。 */
export const KEY_APP_LOCK_AUTO_LOCK: string = 'appLockAutoLock';

export class PreferencesAppLockStore implements AppLockStore {
  private readonly passcode: PasscodeStorePort;
  private cachedIsSet: boolean = false;
  private cachedChoice: AutoLockChoice | null = null;

  constructor(passcode: PasscodeStorePort) {
    this.passcode = passcode;
  }

  isPasscodeSet(): boolean {
    return this.cachedIsSet;
  }

  async refreshPasscodeSet(): Promise<Result<boolean, AppError>> {
    const res: Result<boolean, AppError> = await this.passcode.isSet();
    if (res.err) {
      return err<boolean, AppError>(res.error);
    }
    // ArkTS 不在提前 return 后收窄 Result，取值走 fold（AGENTS.md 第 3.1 条）。
    const isSet: boolean = res.fold<boolean>(
      (value: boolean): boolean => value,
      (_error: AppError): boolean => false
    );
    this.cachedIsSet = isSet;
    return ok<boolean, AppError>(isSet);
  }

  autoLockChoice(): AutoLockChoice {
    if (this.cachedChoice === null) {
      this.cachedChoice = autoLockChoiceAt(readSettingsNumber(KEY_APP_LOCK_AUTO_LOCK));
    }
    return this.cachedChoice;
  }

  setAutoLockChoice(choice: AutoLockChoice): boolean {
    if (!writeSettingsNumber(KEY_APP_LOCK_AUTO_LOCK, autoLockStoredIndex(choice))) {
      return false;
    }
    this.cachedChoice = choice;
    return true;
  }

  async setPasscode(pin: string): Promise<Result<void, AppError>> {
    const res: Result<void, AppError> = await this.passcode.set(pin);
    if (res.err) {
      return err<void, AppError>(res.error);
    }
    this.cachedIsSet = true;
    return ok<void, AppError>(undefined);
  }

  /** 校验不改缓存：校验失败不代表 PIN 被抹掉了。 */
  verifyPasscode(pin: string): Promise<Result<boolean, AppError>> {
    return this.passcode.matches(pin);
  }

  async removePasscode(): Promise<Result<void, AppError>> {
    const res: Result<void, AppError> = await this.passcode.wipe();
    if (res.err) {
      return err<void, AppError>(res.error);
    }
    this.cachedIsSet = false;
    return ok<void, AppError>(undefined);
  }
}
