/**
 * core/td_gateway — 超时调度抽象（CORE-002）。
 *
 * RequestRegistry 的默认超时 10s（计划 §5.2/§7 超时契约）需要可注入的
 * 定时器以便确定性单测（真实 setTimeout 不可测、不可用真实等待）。
 * domain 代码只依赖 TdTimeoutScheduler 接口：
 * - RealTimeoutScheduler：生产用，挂接全局 setTimeout/clearTimeout；
 * - ManualTimeoutScheduler：测试 fake，由测试按意志推进虚拟时间。
 */

export interface TdTimeoutScheduler {
  setTimeout(callback: () => void, delayMillis: number): number;
  clearTimeout(handle: number): void;
}

export class RealTimeoutScheduler implements TdTimeoutScheduler {
  setTimeout(callback: () => void, delayMillis: number): number {
    return setTimeout(callback, delayMillis);
  }

  clearTimeout(handle: number): void {
    clearTimeout(handle);
  }
}

interface ScheduledTask {
  readonly id: number;
  readonly fireAtMillis: number;
  readonly callback: () => void;
}

/**
 * 测试 fake：虚拟时间只随 advanceBy/advanceTo 前进，
 * 到期的任务按调度顺序触发；clearTimeout 的任务不再触发。
 */
export class ManualTimeoutScheduler implements TdTimeoutScheduler {
  private currentMillis: number = 0;
  private nextId: number = 1;
  private readonly tasks: ScheduledTask[] = [];

  nowMillis(): number {
    return this.currentMillis;
  }

  setTimeout(callback: () => void, delayMillis: number): number {
    const id: number = this.nextId;
    this.nextId += 1;
    const task: ScheduledTask = {
      id: id,
      fireAtMillis: this.currentMillis + Math.max(0, delayMillis),
      callback: callback
    };
    this.tasks.push(task);
    return id;
  }

  clearTimeout(handle: number): void {
    const index: number = this.tasks.findIndex((task: ScheduledTask) => task.id === handle);
    if (index >= 0) {
      this.tasks.splice(index, 1);
    }
  }

  advanceBy(deltaMillis: number): void {
    this.advanceTo(this.currentMillis + deltaMillis);
  }

  advanceTo(targetMillis: number): void {
    if (targetMillis < this.currentMillis) {
      return;
    }
    this.currentMillis = targetMillis;
    // 反复扫描：任务回调里可能再调度新任务（reschedule 语义）。
    for (;;) {
      let earliest: ScheduledTask | null = null;
      for (const task of this.tasks) {
        if (task.fireAtMillis <= this.currentMillis &&
          (earliest === null || task.fireAtMillis < earliest.fireAtMillis ||
            (task.fireAtMillis === earliest.fireAtMillis && task.id < earliest.id))) {
          earliest = task;
        }
      }
      if (earliest === null) {
        return;
      }
      const fired: ScheduledTask = earliest;
      const index: number = this.tasks.findIndex((task: ScheduledTask) => task.id === fired.id);
      if (index >= 0) {
        this.tasks.splice(index, 1);
      }
      fired.callback();
    }
  }
}
