/**
 * core/common — Clock 抽象（CORE-001）。
 *
 * domain 代码只允许依赖 Clock 接口；system/monotonic/test fake 三实现：
 * - SystemClock：生产用，挂接系统时间；
 * - ManualClock：测试 fake，可注入固定时间、按测试意志前进，保证确定性。
 *
 * 注意：纯 ArkTS 层没有可移植的单调时钟 API（platform 适配层后续补足）。
 * SystemClock.monotonicMillis() 目前以 epoch 时间近似，仅供无严格单调
 * 需求的路径使用；需要真单调语义（如超时、序列号）的路径必须经
 * platform 注入单调实现后再启用。详见 core/common/README.md 交接说明。
 */

export interface Clock {
  nowMillis(): number;
  monotonicMillis(): number;
}

export class SystemClock implements Clock {
  nowMillis(): number {
    return Date.now();
  }

  monotonicMillis(): number {
    return Date.now();
  }
}

export class ManualClock implements Clock {
  private currentNowMillis: number;
  private currentMonotonicMillis: number;

  constructor(nowMillis: number = 0, monotonicMillis: number = 0) {
    this.currentNowMillis = nowMillis;
    this.currentMonotonicMillis = monotonicMillis;
  }

  nowMillis(): number {
    return this.currentNowMillis;
  }

  monotonicMillis(): number {
    return this.currentMonotonicMillis;
  }

  setNowMillis(nowMillis: number): void {
    this.currentNowMillis = nowMillis;
  }

  setMonotonicMillis(monotonicMillis: number): void {
    this.currentMonotonicMillis = monotonicMillis;
  }

  advanceBy(deltaMillis: number): void {
    this.currentNowMillis += deltaMillis;
    this.currentMonotonicMillis += deltaMillis;
  }
}
