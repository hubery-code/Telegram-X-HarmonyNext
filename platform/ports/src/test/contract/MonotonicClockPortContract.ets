/**
 * platform/ports — MonotonicClockPort 同套契约测试（PLAT-001）。
 *
 * 任何 MonotonicClockPort 实现（当前 FakeMonotonicClock，未来基于
 * native/系统能力的单调时钟 adapter）都通过
 * `monotonicClockPortContract('name', factory, driver)` 套用同一组断言。
 */

import { describe, it, expect } from '@ohos/hypium';
import { MonotonicClockPort } from '../../main/ets/MonotonicClockPort';

export interface MonotonicClockDriver {
  advanceBy(deltaMillis: number): void;
}

export default function monotonicClockPortContract(
  name: string,
  factory: () => MonotonicClockPort,
  driver: MonotonicClockDriver
) {
  describe(`${name}_MonotonicClockPortContract`, () => {
    it('nowMillis_isMonotonicallyNonDecreasing', 0, () => {
      const clock: MonotonicClockPort = factory();
      let previous: number = clock.nowMillis();
      for (let i = 0; i < 100; i++) {
        driver.advanceBy(i % 3);
        const current: number = clock.nowMillis();
        expect(current >= previous).assertTrue();
        previous = current;
      }
    });

    it('advanceByZero_keepsClockStable', 0, () => {
      const clock: MonotonicClockPort = factory();
      driver.advanceBy(5);
      const before: number = clock.nowMillis();
      driver.advanceBy(0);
      expect(clock.nowMillis()).assertEqual(before);
    });

    it('deltaComparisons_measureElapsedTime', 0, () => {
      const clock: MonotonicClockPort = factory();
      driver.advanceBy(100);
      const start: number = clock.nowMillis();
      driver.advanceBy(250);
      const end: number = clock.nowMillis();
      expect(end - start).assertEqual(250);
    });
  });
}
