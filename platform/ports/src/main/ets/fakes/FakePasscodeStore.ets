/**
 * platform/ports — FakePasscodeStore（APPLOCK-101）。
 *
 * PasscodeStorePort 的内存实现，供 entry 的门禁状态机与 feature/settings 的
 * 协调器测试注入。Fake **不做密码学**：直接把 PIN 当秘密值存在内存里，
 * 语义等价于「存得进、验得出」；测试里断言的是调用方的行为，不是派生算法。
 *
 * 注入点：
 * - `setFailOnSet(error)` / `setFailOnMatch(error)` / `setFailOnWipe(error)`：让某一步先失败，
 *   检查上层是否按失败分支处理（而不是假设写盘一定成功）；
 * - `setBreakRoundtrip(true)`：`set()` 写入后**故意**读回不一致，用来验「自校验不过就
 *   不算设置成功、也不会留下一个谁也解不开的密码」这条红线。
 */

import { Result, AppError, ok, err, AppErrors } from '@tgx/core-common';
import { PasscodeStorePort } from '../PasscodeStorePort';

export class FakePasscodeStore implements PasscodeStorePort {
  private secret: string | null = null;
  /** 测试驱动：写入后读回来应当是什么；null 表示「照抄写入值」。 */
  private roundtripOverride: string | null = null;
  private failOnSet: AppError | null = null;
  private failOnMatch: AppError | null = null;
  private failOnWipe: AppError | null = null;
  /** 诊断：调用次数，让测试能断言「校验失败时没有再去读盘」。 */
  setCalls: number = 0;
  matchCalls: number = 0;
  wipeCalls: number = 0;

  setFailOnSet(error: AppError | null): void {
    this.failOnSet = error;
  }

  setFailOnMatch(error: AppError | null): void {
    this.failOnMatch = error;
  }

  setFailOnWipe(error: AppError | null): void {
    this.failOnWipe = error;
  }

  /** 模拟「写进去的秘密读回来不是同一个」——派生实现出 bug 时的最坏情况。 */
  setBreakRoundtrip(breakIt: boolean): void {
    this.roundtripOverride = breakIt ? '__not_the_same__' : null;
  }

  async isSet(): Promise<Result<boolean, AppError>> {
    return ok<boolean, AppError>(this.secret !== null);
  }

  async set(pin: string): Promise<Result<void, AppError>> {
    this.setCalls += 1;
    if (this.failOnSet !== null) {
      return err<void, AppError>(this.failOnSet);
    }
    this.secret = pin;
    const readBack: string | null = this.secret;
    const expected: string | null = this.roundtripOverride === null ? pin : this.roundtripOverride;
    if (readBack !== expected) {
      this.secret = null;
      return err<void, AppError>(AppErrors.internal('passcode-roundtrip-mismatch', 'passcode write did not round-trip'));
    }
    return ok<void, AppError>(undefined);
  }

  async matches(pin: string): Promise<Result<boolean, AppError>> {
    this.matchCalls += 1;
    if (this.failOnMatch !== null) {
      return err<boolean, AppError>(this.failOnMatch);
    }
    if (this.secret === null) {
      return ok<boolean, AppError>(false);
    }
    return ok<boolean, AppError>(this.secret === pin);
  }

  async wipe(): Promise<Result<void, AppError>> {
    this.wipeCalls += 1;
    if (this.failOnWipe !== null) {
      return err<void, AppError>(this.failOnWipe);
    }
    this.secret = null;
    return ok<void, AppError>(undefined);
  }
}
