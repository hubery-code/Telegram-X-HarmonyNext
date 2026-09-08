import monotonicClockPortContract, { MonotonicClockDriver } from './contract/MonotonicClockPortContract';
import { FakeMonotonicClock } from '../main/ets/fakes/FakeMonotonicClock';

class FakeMonotonicClockHolder {
  fake: FakeMonotonicClock = new FakeMonotonicClock();
}

class FakeMonotonicClockDriver implements MonotonicClockDriver {
  private readonly holder: FakeMonotonicClockHolder;

  constructor(holder: FakeMonotonicClockHolder) {
    this.holder = holder;
  }

  advanceBy(deltaMillis: number): void {
    this.holder.fake.advanceBy(deltaMillis);
  }
}

export default function fakeMonotonicClockContractTest() {
  const holder: FakeMonotonicClockHolder = new FakeMonotonicClockHolder();
  monotonicClockPortContract(
    'FakeMonotonicClock',
    () => {
      holder.fake = new FakeMonotonicClock();
      return holder.fake;
    },
    new FakeMonotonicClockDriver(holder)
  );
}
