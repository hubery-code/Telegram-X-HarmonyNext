/**
 * feature/settings — 应用锁 reducer 用例（APPLOCK-101）。
 *
 * 守住的回归：
 * 1. **状态里永远没有 PIN**：每次派发后遍历状态的可观察字段，断言没有哪一处留着提交过的密码
 *    —— 这条是整块功能的安全底线，写成人眼审查迟早会漏，所以做成断言；
 * 2. 进子页必须重读盘：锁屏遮罩会改本机状态，用缓存的「有没有 PIN」会显示成假；
 * 3. 在途与已有流程时不放行第二次开关（重复点行不该起两次写盘）；
 * 4. 档位是乐观改 + 失败回灌，且回灌的是**盘上真值**而不是猜的默认值；
 * 5. 密码错误只改提示、不改阶段（留在原地重输），锁屏与设置页同一条规则。
 */

import { describe, it, expect } from '@ohos/hypium';
import { ManualClock, SequentialIdGenerator } from '@tgx/core-common';
import { ReducerEnv } from '@tgx/feature-template';
import {
  APP_LOCK_ERROR_STORE,
  APP_LOCK_ERROR_WRONG,
  APP_LOCK_NOTICE_INVALID,
  APP_LOCK_NOTICE_MISMATCH,
  APP_LOCK_NOTICE_REMOVED,
  APP_LOCK_NOTICE_SAVED,
  AUTO_LOCK_CHOICES,
  AUTO_LOCK_DEFAULT,
  AutoLockChoice,
  nextAutoLockChoice
} from '@tgx/core-domain';
import { SettingsUiState, SettingsUiStateOptions } from '../main/ets/contract/SettingsUiState';
import {
  AutoLockChoiceRejected,
  CancelPasscodeFlow,
  ChangePasscodeRequested,
  ClosePasscodePage,
  CycleAutoLockChoice,
  LoadPasscodeState,
  OpenPasscodePage,
  PasscodeMismatched,
  PasscodeOperationDone,
  PasscodeOperationFailed,
  PasscodeRejected,
  PasscodeStateLoaded,
  PasscodeSubmitted,
  PasscodeVerified,
  TogglePasscodeRequested
} from '../main/ets/contract/SettingsIntent';
import {
  ClearPasscodeDraftEffect,
  CommitPasscodeEffect,
  LoadPasscodeStateEffect,
  PersistAutoLockChoiceEffect,
  StorePasscodeDraftEffect,
  VerifyPasscodeEffect
} from '../main/ets/contract/SettingsEffect';
import { settingsReducer } from '../main/ets/reducer/SettingsReducer';

function makeEnv(): ReducerEnv {
  return {
    clock: new ManualClock(1000, 500),
    ids: new SequentialIdGenerator('passcode-test-')
  };
}

function passcodeState(options: SettingsUiStateOptions): SettingsUiState {
  return SettingsUiState.initial().copyWith(options);
}

/**
 * 状态的可观察字段快照（含 `copyWith` 用到的 options 字段名）。
 * PIN 一旦进了状态，就会在这里被扫到 —— 不这么做的话，「顺手把输入存进 state」
 * 是最容易在后续迭代里溜回来的写法。
 */
function stateLeaksPin(state: SettingsUiState, pin: string): boolean {
  const text: string = JSON.stringify(state);
  return text.indexOf(pin) >= 0;
}

const TEST_PIN: string = '4271';

export default function passcodeReducerTest(): void {
  describe('PasscodeReducerTest', () => {

    it('openPasscodePage_alwaysReloadsLocalState', 0, () => {
      const state = passcodeState({ passcodeIsSet: true, autoLockChoice: 'one_hour' });
      const result = settingsReducer(state, new OpenPasscodePage(), makeEnv());

      expect(result.state.showPasscodePage).assertTrue();
      expect(result.effects.length).assertEqual(1);
      expect(result.effects[0].kind).assertEqual('loadPasscodeState');
      // 进页不改「有没有 PIN」：那是盘上的事实，要等 loadPasscodeState 回来才知道。
      expect(result.state.passcodeIsSet).assertTrue();
    });

    it('loadPasscodeState_emitsEffectWithoutChangingFlags', 0, () => {
      const result = settingsReducer(SettingsUiState.initial(), new LoadPasscodeState(), makeEnv());
      expect(result.effects.length).assertEqual(1);
      expect(result.effects[0].kind).assertEqual('loadPasscodeState');
    });

    it('passcodeStateLoaded_fillsRowWithoutBusy', 0, () => {
      const state = passcodeState({ isUpdatingPasscode: true });
      const result = settingsReducer(state, new PasscodeStateLoaded(true, 'five_minutes'), makeEnv());

      expect(result.state.passcodeIsSet).assertTrue();
      expect(result.state.autoLockChoice).assertEqual('five_minutes');
      expect(result.state.isUpdatingPasscode).assertFalse();
    });

    it('toggleStartsEnterWhenUnsetAndVerifyWhenSet', 0, () => {
      const unset = settingsReducer(SettingsUiState.initial(), new TogglePasscodeRequested(), makeEnv());
      expect(unset.state.passcodeFlow).assertEqual('enter');

      const set = settingsReducer(passcodeState({ passcodeIsSet: true }),
        new TogglePasscodeRequested(), makeEnv());
      expect(set.state.passcodeFlow).assertEqual('verify-disable');
    });

    it('toggleIsBlockedWhileBusyOrMidFlow', 0, () => {
      const busy = settingsReducer(passcodeState({ isUpdatingPasscode: true }),
        new TogglePasscodeRequested(), makeEnv());
      expect(busy.state.passcodeFlow).assertEqual('idle');

      const midFlow = settingsReducer(passcodeState({ passcodeFlow: 'confirm' }),
        new TogglePasscodeRequested(), makeEnv());
      expect(midFlow.state.passcodeFlow).assertEqual('confirm');
    });

    it('changePasscodeRequiresAnExistingPasscode', 0, () => {
      const unset = settingsReducer(SettingsUiState.initial(), new ChangePasscodeRequested(), makeEnv());
      expect(unset.state.passcodeFlow).assertEqual('idle');

      const set = settingsReducer(passcodeState({ passcodeIsSet: true }),
        new ChangePasscodeRequested(), makeEnv());
      expect(set.state.passcodeFlow).assertEqual('verify-change');
    });

    it('submitShortPinNoticesAndStoresNothing', 0, () => {
      const state = passcodeState({ passcodeFlow: 'enter' });
      const result = settingsReducer(state, new PasscodeSubmitted('12'), makeEnv());

      expect(result.state.passcodeNotice).assertEqual(APP_LOCK_NOTICE_INVALID);
      expect(result.effects.length).assertEqual(0);
      expect(result.state.passcodeFlow).assertEqual('enter');
    });

    it('submitAtEnterDraftsIntoConfirmAndLeaksNothing', 0, () => {
      const state = passcodeState({ passcodeFlow: 'enter' });
      const result = settingsReducer(state, new PasscodeSubmitted(TEST_PIN), makeEnv());

      expect(result.state.passcodeFlow).assertEqual('confirm');
      expect(result.effects.length).assertEqual(1);
      expect(result.effects[0].kind).assertEqual('storePasscodeDraft');
      expect(stateLeaksPin(result.state, TEST_PIN)).assertFalse();
    });

    it('submitAtConfirmCommitsAndStateStaysClean', 0, () => {
      const state = passcodeState({ passcodeFlow: 'confirm' });
      const result = settingsReducer(state, new PasscodeSubmitted(TEST_PIN), makeEnv());

      expect(result.state.isUpdatingPasscode).assertTrue();
      expect(result.effects.length).assertEqual(1);
      expect(result.effects[0] instanceof CommitPasscodeEffect).assertTrue();
      expect(stateLeaksPin(result.state, TEST_PIN)).assertFalse();
    });

    it('verifyStagesCarryTheirPurposeIntoTheEffect', 0, () => {
      const disable = settingsReducer(passcodeState({ passcodeIsSet: true, passcodeFlow: 'verify-disable' }),
        new PasscodeSubmitted(TEST_PIN), makeEnv());
      expect(disable.effects.length).assertEqual(1);
      expect((disable.effects[0] as VerifyPasscodeEffect).purpose).assertEqual('disable');

      const change = settingsReducer(passcodeState({ passcodeIsSet: true, passcodeFlow: 'verify-change' }),
        new PasscodeSubmitted(TEST_PIN), makeEnv());
      expect((change.effects[0] as VerifyPasscodeEffect).purpose).assertEqual('change');
    });

    it('submitWhileIdleIsIgnored', 0, () => {
      const result = settingsReducer(SettingsUiState.initial(), new PasscodeSubmitted(TEST_PIN), makeEnv());
      expect(result.effects.length).assertEqual(0);
      expect(result.state.passcodeFlow).assertEqual('idle');
    });

    it('verifiedForChangeAdvancesToEnterAndDropsDraft', 0, () => {
      const state = passcodeState({ passcodeFlow: 'verify-change', isUpdatingPasscode: true });
      const result = settingsReducer(state, new PasscodeVerified('change'), makeEnv());

      expect(result.state.passcodeFlow).assertEqual('enter');
      expect(result.state.isUpdatingPasscode).assertFalse();
      expect(result.effects.length).assertEqual(1);
      expect(result.effects[0] instanceof ClearPasscodeDraftEffect).assertTrue();
    });

    it('verifiedForDisableOnlyClearsBusy', 0, () => {
      const state = passcodeState({ passcodeFlow: 'verify-disable', isUpdatingPasscode: true });
      const result = settingsReducer(state, new PasscodeVerified('disable'), makeEnv());

      expect(result.state.isUpdatingPasscode).assertFalse();
      expect(result.effects.length).assertEqual(0);
      // 抹盘由 coordinator 紧接着做，所以阶段还留在 verify-disable。
      expect(result.state.passcodeFlow).assertEqual('verify-disable');
    });

    it('rejectedKeepsStageSoTheUserRetriesInPlace', 0, () => {
      const state = passcodeState({ passcodeIsSet: true, passcodeFlow: 'verify-disable', isUpdatingPasscode: true });
      const result = settingsReducer(state, new PasscodeRejected(APP_LOCK_ERROR_WRONG), makeEnv());

      expect(result.state.passcodeFlow).assertEqual('verify-disable');
      expect(result.state.isUpdatingPasscode).assertFalse();
      expect(result.state.passcodeNotice).assertEqual(APP_LOCK_ERROR_WRONG);
    });

    it('mismatchReturnsToEnterAndDropsDraft', 0, () => {
      const state = passcodeState({ passcodeFlow: 'confirm', isUpdatingPasscode: true });
      const result = settingsReducer(state, new PasscodeMismatched(), makeEnv());

      expect(result.state.passcodeFlow).assertEqual('enter');
      expect(result.state.passcodeNotice).assertEqual(APP_LOCK_NOTICE_MISMATCH);
      expect(result.effects[0] instanceof ClearPasscodeDraftEffect).assertTrue();
    });

    it('operationDoneRecordsTheDiskTruthNotAGuess', 0, () => {
      const saved = settingsReducer(passcodeState({ passcodeFlow: 'confirm' }),
        new PasscodeOperationDone(APP_LOCK_NOTICE_SAVED, true), makeEnv());
      expect(saved.state.passcodeIsSet).assertTrue();
      expect(saved.state.passcodeFlow).assertEqual('idle');
      expect(saved.state.passcodeNotice).assertEqual(APP_LOCK_NOTICE_SAVED);

      const removed = settingsReducer(passcodeState({ passcodeIsSet: true, passcodeFlow: 'verify-disable' }),
        new PasscodeOperationDone(APP_LOCK_NOTICE_REMOVED, false), makeEnv());
      expect(removed.state.passcodeIsSet).assertFalse();
    });

    it('operationFailedLeavesFlowAndClearsDraft', 0, () => {
      const state = passcodeState({ passcodeFlow: 'confirm', isUpdatingPasscode: true });
      const result = settingsReducer(state, new PasscodeOperationFailed(APP_LOCK_ERROR_STORE), makeEnv());

      expect(result.state.passcodeFlow).assertEqual('idle');
      expect(result.state.isUpdatingPasscode).assertFalse();
      expect(result.state.passcodeNotice).assertEqual(APP_LOCK_ERROR_STORE);
      expect(result.effects[0] instanceof ClearPasscodeDraftEffect).assertTrue();
    });

    it('cancelClosesKeyboardAndDropsDraft', 0, () => {
      const state = passcodeState({ passcodeFlow: 'confirm', isUpdatingPasscode: true });
      const result = settingsReducer(state, new CancelPasscodeFlow(), makeEnv());

      expect(result.state.passcodeFlow).assertEqual('idle');
      expect(result.state.isUpdatingPasscode).assertFalse();
      expect(result.effects[0] instanceof ClearPasscodeDraftEffect).assertTrue();

      // 已经 idle 时再点是空操作；清草稿只在真离开流程时发。
      const again = settingsReducer(result.state, new CancelPasscodeFlow(), makeEnv());
      expect(again.effects.length).assertEqual(0);
      expect(result.effects.length).assertEqual(1);
    });

    it('closePageAlwaysClearsDraft', 0, () => {
      const state = passcodeState({ showPasscodePage: true, passcodeFlow: 'confirm' });
      const result = settingsReducer(state, new ClosePasscodePage(), makeEnv());

      expect(result.state.showPasscodePage).assertFalse();
      expect(result.state.passcodeFlow).assertEqual('idle');
      expect(result.effects[0] instanceof ClearPasscodeDraftEffect).assertTrue();
    });

    it('autoLockChoiceCyclesOptimisticallyWithPersist', 0, () => {
      const state = passcodeState({ autoLockChoice: AUTO_LOCK_DEFAULT });
      const result = settingsReducer(state, new CycleAutoLockChoice(), makeEnv());
      const expected: AutoLockChoice = nextAutoLockChoice(AUTO_LOCK_DEFAULT);

      expect(result.state.autoLockChoice).assertEqual(expected);
      expect(result.effects.length).assertEqual(1);
      expect((result.effects[0] as PersistAutoLockChoiceEffect).choice).assertEqual(expected);
    });

    it('autoLockRollbackRestoresDiskValue', 0, () => {
      const state = passcodeState({ autoLockChoice: 'one_hour' });
      const result = settingsReducer(state, new AutoLockChoiceRejected('five_hours'), makeEnv());
      expect(result.state.autoLockChoice).assertEqual('five_hours');
    });

    it('fullCreateFlowNeverLeaksThePin', 0, () => {
      // 走一遍「进页 → 开 → 输入 → 确认 → 落盘成功」，每一步都扫一次状态。
      let state = settingsReducer(SettingsUiState.initial(), new OpenPasscodePage(), makeEnv()).state;
      state = settingsReducer(state, new TogglePasscodeRequested(), makeEnv()).state;
      expect(state.passcodeFlow).assertEqual('enter');
      expect(stateLeaksPin(state, TEST_PIN)).assertFalse();
      state = settingsReducer(state, new PasscodeSubmitted(TEST_PIN), makeEnv()).state;
      expect(stateLeaksPin(state, TEST_PIN)).assertFalse();
      const effects = settingsReducer(state, new PasscodeSubmitted(TEST_PIN), makeEnv()).effects;
      expect(effects[0] instanceof CommitPasscodeEffect).assertTrue();
      state = settingsReducer(state, new PasscodeOperationDone(APP_LOCK_NOTICE_SAVED, true), makeEnv()).state;
      expect(stateLeaksPin(state, TEST_PIN)).assertFalse();
      expect(state.passcodeIsSet).assertTrue();
    });

    it('everyChoiceIsReachableByCycling', 0, () => {
      let current: AutoLockChoice = SettingsUiState.initial().autoLockChoice;
      for (let i = 0; i < AUTO_LOCK_CHOICES.length; i++) {
        const result = settingsReducer(passcodeState({ autoLockChoice: current }),
          new CycleAutoLockChoice(), makeEnv());
        current = result.state.autoLockChoice;
      }
      expect(current).assertEqual(SettingsUiState.initial().autoLockChoice);
    });

    it('loadEffectKindIsStable', 0, () => {
      // reducer 与 coordinator 靠 kind 字符串分流，改名会静默断链，所以钉一次。
      expect(new LoadPasscodeStateEffect().kind).assertEqual('loadPasscodeState');
      expect(new StorePasscodeDraftEffect(TEST_PIN).kind).assertEqual('storePasscodeDraft');
    });
  });
}
