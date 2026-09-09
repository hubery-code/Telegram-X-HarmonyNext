/**
 * feature/_template — Reducer 契约（UI-003）。
 *
 * 计划 §5.11：Reducer 是纯函数；异步副作用由 UseCase/EffectHandler 执行。
 *
 *   (state, intent, env) -> { state, effects }
 *
 * 纯函数保证：
 * - 禁止修改入参 state；未变化时原样返回同一引用（UI 据此做最小刷新）；
 * - 禁止直接调用 Date.now() / Math.random() 等隐式源头，
 *   时间与 ID 一律经 env（Clock / IdGenerator，来自 @tgx/core-common）注入，
 *   测试用 ManualClock / SequentialIdGenerator 获得完全确定性；
 * - 不产生任何 I/O，副作用只以 Effect 描述的形式出现在返回值里。
 */

import { Clock, IdGenerator } from '@tgx/core-common';
import { Effect, Intent, UiState } from './UiState';

export interface ReducerEnv {
  readonly clock: Clock;
  readonly ids: IdGenerator;
}

export class ReducerResult<S extends UiState, E extends Effect> {
  readonly state: S;
  readonly effects: readonly E[];

  constructor(state: S, effects: readonly E[]) {
    this.state = state;
    this.effects = effects;
  }
}

export type Reducer<S extends UiState, I extends Intent, E extends Effect> =
  (state: S, intent: I, env: ReducerEnv) => ReducerResult<S, E>;

export function reduced<S extends UiState, E extends Effect>(state: S, effects: readonly E[] = []): ReducerResult<S, E> {
  return new ReducerResult<S, E>(state, effects);
}
