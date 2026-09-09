import { describe, it, expect } from '@ohos/hypium';
import { ManualClock, SequentialIdGenerator } from '@tgx/core-common';
import { ReducerEnv, reduced } from '../main/ets/contract/Reducer';
import { CounterState } from '../main/ets/example/CounterState';
import {
  IncrementPressed,
  DecrementPressed,
  StepChanged,
  SavePressed,
  ResetPressed,
  CounterIntent
} from '../main/ets/example/CounterIntent';
import { CounterEffect, PersistCount, ShowToast } from '../main/ets/example/CounterEffect';
import { counterReducer } from '../main/ets/example/CounterReducer';

function makeEnv(nowMillis: number = 1000, monotonicMillis: number = 500): ReducerEnv {
  const env: ReducerEnv = {
    clock: new ManualClock(nowMillis, monotonicMillis),
    ids: new SequentialIdGenerator('req-test-')
  };
  return env;
}

export default function counterReducerTest() {
  describe('CounterReducerTest', () => {
    it('incrementPressed_addsStepToCount_noEffects', 0, () => {
      const result = counterReducer(CounterState.initial(), new IncrementPressed(), makeEnv());
      expect(result.state.count).assertEqual(1);
      expect(result.state.step).assertEqual(1);
      expect(result.effects.length).assertEqual(0);
    });

    it('decrementPressed_subtractsStepFromCount', 0, () => {
      const result = counterReducer(CounterState.initial(), new DecrementPressed(), makeEnv());
      expect(result.state.count).assertEqual(-1);
      expect(result.effects.length).assertEqual(0);
    });

    it('incrementPressed_honorsCustomStep', 0, () => {
      const state = CounterState.initial().copyWith(0, 5);
      const result = counterReducer(state, new IncrementPressed(), makeEnv());
      expect(result.state.count).assertEqual(5);
      expect(result.state.step).assertEqual(5);
    });

    it('stepChanged_validValue_updatesStep', 0, () => {
      const result = counterReducer(CounterState.initial(), new StepChanged(3), makeEnv());
      expect(result.state.step).assertEqual(3);
      expect(result.state.count).assertEqual(0);
      expect(result.effects.length).assertEqual(0);
    });

    it('stepChanged_boundaryValues_accepted', 0, () => {
      const min = counterReducer(CounterState.initial(), new StepChanged(CounterState.MIN_STEP), makeEnv());
      expect(min.state.step).assertEqual(CounterState.MIN_STEP);
      expect(min.effects.length).assertEqual(0);
      const max = counterReducer(CounterState.initial(), new StepChanged(CounterState.MAX_STEP), makeEnv());
      expect(max.state.step).assertEqual(CounterState.MAX_STEP);
      expect(max.effects.length).assertEqual(0);
    });

    it('stepChanged_belowMin_rejectedWithToast_sameStateRef', 0, () => {
      const state = CounterState.initial();
      const result = counterReducer(state, new StepChanged(0), makeEnv());
      expect(result.state === state).assertTrue();
      expect(result.effects.length).assertEqual(1);
      const effect: CounterEffect = result.effects[0];
      expect(effect.kind).assertEqual('showToast');
      expect((effect as ShowToast).messageKey).assertEqual('counter.stepInvalid');
    });

    it('stepChanged_aboveMax_rejectedWithToast', 0, () => {
      const result = counterReducer(CounterState.initial(), new StepChanged(11), makeEnv());
      expect(result.effects.length).assertEqual(1);
      const effect: CounterEffect = result.effects[0];
      expect(effect.kind).assertEqual('showToast');
      expect((effect as ShowToast).messageKey).assertEqual('counter.stepInvalid');
    });

    it('savePressed_setsInFlightAndEmitsPersistEffectFromEnv', 0, () => {
      const env = makeEnv(2000, 777);
      const result = counterReducer(CounterState.initial().copyWith(42), new SavePressed(), env);
      expect(result.state.saveInFlight).assertTrue();
      expect(result.state.lastSavedAtMillis).assertEqual(777);
      expect(result.effects.length).assertEqual(1);
      const effect: CounterEffect = result.effects[0];
      expect(effect.kind).assertEqual('persistCount');
      const persist = effect as PersistCount;
      expect(persist.requestId).assertEqual('req-test-1');
      expect(persist.count).assertEqual(42);
      expect(persist.savedAtMillis).assertEqual(777);
    });

    it('savePressed_whileInFlight_isIdempotentNoOp', 0, () => {
      const state = CounterState.initial().copyWith(7, 1, true, 123);
      const result = counterReducer(state, new SavePressed(), makeEnv());
      expect(result.state === state).assertTrue();
      expect(result.effects.length).assertEqual(0);
    });

    it('resetPressed_restoresInitialValues', 0, () => {
      const state = CounterState.initial().copyWith(9, 4, true, 321);
      const result = counterReducer(state, new ResetPressed(), makeEnv());
      const initial = CounterState.initial();
      expect(result.state.count).assertEqual(initial.count);
      expect(result.state.step).assertEqual(initial.step);
      expect(result.state.saveInFlight).assertEqual(initial.saveInFlight);
      expect(result.state.lastSavedAtMillis).assertEqual(initial.lastSavedAtMillis);
      expect(result.effects.length).assertEqual(0);
    });

    it('reducer_doesNotMutateInputState', 0, () => {
      const state = CounterState.initial().copyWith(10, 2, false, 55);
      const countBefore: number = state.count;
      const stepBefore: number = state.step;
      const inFlightBefore: boolean = state.saveInFlight;
      const savedAtBefore: number = state.lastSavedAtMillis;
      const intents: CounterIntent[] = [
        new IncrementPressed(), new DecrementPressed(), new StepChanged(5),
        new StepChanged(99), new SavePressed(), new ResetPressed()
      ];
      for (let i = 0; i < intents.length; i++) {
        counterReducer(state, intents[i], makeEnv());
      }
      expect(state.count).assertEqual(countBefore);
      expect(state.step).assertEqual(stepBefore);
      expect(state.saveInFlight).assertEqual(inFlightBefore);
      expect(state.lastSavedAtMillis).assertEqual(savedAtBefore);
    });

    it('reducer_isPure_sameInputsProduceIdenticalOutputs', 0, () => {
      const intent = new SavePressed();
      const first = counterReducer(CounterState.initial().copyWith(42), intent, makeEnv(2000, 777));
      const second = counterReducer(CounterState.initial().copyWith(42), intent, makeEnv(2000, 777));
      expect(first.state.count).assertEqual(second.state.count);
      expect(first.state.saveInFlight).assertEqual(second.state.saveInFlight);
      expect(first.state.lastSavedAtMillis).assertEqual(second.state.lastSavedAtMillis);
      expect(first.effects.length).assertEqual(second.effects.length);
      const a = first.effects[0] as PersistCount;
      const b = second.effects[0] as PersistCount;
      expect(a.requestId).assertEqual(b.requestId);
      expect(a.count).assertEqual(b.count);
      expect(a.savedAtMillis).assertEqual(b.savedAtMillis);
    });

    it('reducer_chainedRunsFromSameBase_areIndependent', 0, () => {
      const base = CounterState.initial();
      const r1 = counterReducer(base, new IncrementPressed(), makeEnv());
      const r2 = counterReducer(base, new IncrementPressed(), makeEnv());
      expect(r1.state.count).assertEqual(1);
      expect(r2.state.count).assertEqual(1);
      expect(base.count).assertEqual(0);
    });

    it('reducer_envDifferences_areObservableInEffects', 0, () => {
      const state = CounterState.initial().copyWith(5);
      const early = counterReducer(state, new SavePressed(), makeEnv(1000, 100));
      const late = counterReducer(state, new SavePressed(), makeEnv(1000, 200));
      expect((early.effects[0] as PersistCount).savedAtMillis).assertEqual(100);
      expect((late.effects[0] as PersistCount).savedAtMillis).assertEqual(200);
    });

    it('reducedHelper_defaultsToEmptyEffects', 0, () => {
      const state = CounterState.initial();
      const result = reduced(state);
      expect(result.state === state).assertTrue();
      expect(result.effects.length).assertEqual(0);
    });
  });
}
