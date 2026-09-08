/**
 * platform/ports — FakeMonotonicClock（PLAT-001）。
 *
 * MonotonicClockPort 的测试实现：当前值由测试注入，
 * advanceBy 推进；回退由测试纪律保证（契约测试用 advanceBy 验证单调性）。
 */

import { MonotonicClockPort } from '../MonotonicClockPort';

export class FakeMonotonicClock implements MonotonicClockPort {
  private currentMillis: number;

  constructor(startMillis: number = 0) {
    this.currentMillis = startMillis;
  }

  nowMillis(): number {
    return this.currentMillis;
  }

  /** 测试驱动：按 delta 前进（delta 可为 0，模拟无前进）。 */
  advanceBy(deltaMillis: number): void {
    if (deltaMillis < 0) {
      return;
    }
    this.currentMillis += deltaMillis;
  }

  /** 测试驱动：直接设定当前值（仅供构造初始状态使用，生产语义下不允许回退）。 */
  setMillis(millis: number): void {
    this.currentMillis = millis;
  }
}
