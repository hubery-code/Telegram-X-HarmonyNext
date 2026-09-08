import { describe, it, expect } from '@ohos/hypium';
import { Clock, SystemClock, ManualClock } from '../main/ets/Clock';

export default function clockTest() {
  describe('ClockTest', () => {
    it('manualClock_isDeterministic', 0, () => {
      const clock: ManualClock = new ManualClock(1000, 500);
      expect(clock.nowMillis()).assertEqual(1000);
      expect(clock.monotonicMillis()).assertEqual(500);

      clock.advanceBy(250);
      expect(clock.nowMillis()).assertEqual(1250);
      expect(clock.monotonicMillis()).assertEqual(750);

      clock.setNowMillis(9999);
      expect(clock.nowMillis()).assertEqual(9999);
      expect(clock.monotonicMillis()).assertEqual(750);

      clock.setMonotonicMillis(42);
      expect(clock.monotonicMillis()).assertEqual(42);
    });

    it('systemClock_nowIsPositiveAndNonDecreasing', 0, () => {
      const clock: SystemClock = new SystemClock();
      const first: number = clock.nowMillis();
      const second: number = clock.nowMillis();
      expect(first > 0).assertTrue();
      expect(second >= first).assertTrue();
    });

    it('clockAbstraction_worksThroughInterface', 0, () => {
      const fake: Clock = new ManualClock(10, 20);
      expect(fake.nowMillis()).assertEqual(10);
      expect(fake.monotonicMillis()).assertEqual(20);
    });
  });
}
