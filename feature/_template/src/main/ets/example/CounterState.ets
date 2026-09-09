/**
 * feature/_template — 示例 feature：CounterState（UI-003）。
 *
 * 不可变状态约定（ArkTS 严格模式实践）：
 * - ArkTS 不支持对象 spread，禁止 `{...state, count: n}` 式拷贝；
 *   一律使用显式 copyWith 工厂，构造新实例；
 * - 所有字段 readonly，构造后不可再变；
 * - 未变化的派生返回原引用（见 reducer 的 no-op 分支）。
 */

import { UiState } from '../contract/UiState';

export class CounterState implements UiState {
  static readonly MIN_STEP: number = 1;
  static readonly MAX_STEP: number = 10;

  readonly count: number;
  readonly step: number;
  readonly saveInFlight: boolean;
  readonly lastSavedAtMillis: number;

  private constructor(count: number, step: number, saveInFlight: boolean, lastSavedAtMillis: number) {
    this.count = count;
    this.step = step;
    this.saveInFlight = saveInFlight;
    this.lastSavedAtMillis = lastSavedAtMillis;
  }

  static initial(): CounterState {
    return new CounterState(0, 1, false, -1);
  }

  copyWith(count?: number, step?: number, saveInFlight?: boolean, lastSavedAtMillis?: number): CounterState {
    return new CounterState(
      count !== undefined ? count : this.count,
      step !== undefined ? step : this.step,
      saveInFlight !== undefined ? saveInFlight : this.saveInFlight,
      lastSavedAtMillis !== undefined ? lastSavedAtMillis : this.lastSavedAtMillis
    );
  }
}
