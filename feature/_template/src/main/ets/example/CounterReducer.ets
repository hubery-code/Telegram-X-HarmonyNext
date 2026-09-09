/**
 * feature/_template — 示例 feature：counterReducer（UI-003）。
 *
 * 全链路演示：(state, intent, env) -> { state, effects }。
 * 每个 intent 分支的语义即单测断言对象，见 src/test/CounterReducer.test.ets。
 */

import { Reducer, ReducerEnv, reduced } from '../contract/Reducer';
import { CounterState } from './CounterState';
import { CounterIntent } from './CounterIntent';
import { CounterEffect, PersistCount, ShowToast } from './CounterEffect';

const STEP_INVALID_TOAST: string = 'counter.stepInvalid';

export const counterReducer: Reducer<CounterState, CounterIntent, CounterEffect> =
  (state: CounterState, intent: CounterIntent, env: ReducerEnv) => {
    switch (intent.kind) {
      case 'incrementPressed':
        return reduced(state.copyWith(state.count + state.step));
      case 'decrementPressed':
        return reduced(state.copyWith(state.count - state.step));
      case 'stepChanged':
        if (intent.value < CounterState.MIN_STEP || intent.value > CounterState.MAX_STEP) {
          return reduced(state, [new ShowToast(STEP_INVALID_TOAST)]);
        }
        return reduced(state.copyWith(undefined, intent.value));
      case 'savePressed':
        if (state.saveInFlight) {
          return reduced(state);
        }
        const savedAtMillis: number = env.clock.monotonicMillis();
        return reduced(
          state.copyWith(undefined, undefined, true, savedAtMillis),
          [new PersistCount(env.ids.nextRequestId(), state.count, savedAtMillis)]
        );
      case 'resetPressed':
        return reduced(CounterState.initial());
      default:
        return reduced(state);
    }
  };
