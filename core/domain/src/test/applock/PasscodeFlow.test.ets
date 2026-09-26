/**
 * core/domain — PIN 输入流程阶段判据单元测试（APPLOCK-101）。
 *
 * 守住的回归：
 * 1. `idle` 阶段收到提交必须是 `ignore` —— 键盘本就不该在，出现提交说明有人绕过界面直接派发；
 * 2. 校验阶段的提交必须带着**它自己的**阶段名回传（`verify-disable` / `verify-change`），
 *    弄丢了这个值，coordinator 就不知道验完是「关闭」还是「转修改」；
 * 3. 长度不足四位一律 `invalid`，不进草稿也不进存储；
 * 4. 每条阶段都要有文案，且校验两步共用同一句「输入当前密码」是有意的 —— 用户不需要
 *    在输密码时被告知「你是来关密码的还是来改密码的」；
 * 5. 「明文显示输入」的覆盖关系：设置步首次输入恒明文、确认步恒不明文，与偏好无关
 *    （Android `PasscodeController:663` / `PasscodeView:238-240` 的语义）。
 */

import { describe, it, expect } from '@ohos/hypium';
import {
  PasscodeFlowStage,
  PasscodeStepResult,
  passcodeStagePrompt,
  passcodeStageReveal,
  passcodeStepFor
} from '../../main/ets/applock/PasscodeFlow';

export default function passcodeFlowTest(): void {
  describe('PasscodeFlowTest', () => {

    it('idleStageIgnoresSubmissions', 0, () => {
      const step: PasscodeStepResult = passcodeStepFor('idle', '1234');
      expect(step.action).assertEqual('ignore');
      expect(step.verifyFor).assertNull();
    });

    it('shortInputIsInvalidAndNeverStored', 0, () => {
      const stages: PasscodeFlowStage[] = ['enter', 'confirm', 'verify-disable', 'verify-change'];
      for (let i = 0; i < stages.length; i++) {
        expect(passcodeStepFor(stages[i], '').action).assertEqual('invalid');
        expect(passcodeStepFor(stages[i], '123').action).assertEqual('invalid');
        expect(passcodeStepFor(stages[i], '12345').action).assertEqual('invalid');
      }
    });

    it('createFlowGoesEnterThenConfirmThenCommit', 0, () => {
      expect(passcodeStepFor('enter', '1234').action).assertEqual('draft');
      const commit: PasscodeStepResult = passcodeStepFor('confirm', '1234');
      expect(commit.action).assertEqual('commit');
      // commit 不带校验意图：它是落盘，不是「验完再决定下一步」。
      expect(commit.verifyFor).assertNull();
    });

    it('verifyStagesCarryTheirOwnIntent', 0, () => {
      const disable: PasscodeStepResult = passcodeStepFor('verify-disable', '1234');
      expect(disable.action).assertEqual('verify');
      expect(disable.verifyFor).assertEqual('verify-disable');

      const change: PasscodeStepResult = passcodeStepFor('verify-change', '1234');
      expect(change.action).assertEqual('verify');
      expect(change.verifyFor).assertEqual('verify-change');
    });

    it('everyStageHasAPrompt', 0, () => {
      const stages: PasscodeFlowStage[] = ['idle', 'enter', 'confirm', 'verify-disable', 'verify-change'];
      for (let i = 0; i < stages.length; i++) {
        expect(passcodeStagePrompt(stages[i]).length > 0).assertTrue();
      }
      // 创建流程两步的提示必须不同，否则用户不知道自己在重复还是在首次输入。
      expect(passcodeStagePrompt('enter') === passcodeStagePrompt('confirm')).assertFalse();
      // 两个校验步共用一句是刻意的（见文件头 4.）。
      expect(passcodeStagePrompt('verify-disable')).assertEqual(passcodeStagePrompt('verify-change'));
    });

    it('revealPrefOnlyAppliesToVerifyStages', 0, () => {
      // 设置密码的首次输入即使偏好是「圆点」也要明文：用户正在写的东西看不见，
      // 打错一位就会在确认步变成「两次不一致」，比明文多露一位数字代价大得多。
      expect(passcodeStageReveal('enter', false)).assertTrue();
      expect(passcodeStageReveal('enter', true)).assertTrue();
      // 确认步反过来：即使偏好明文也不显示，这一步的产出是比对不是复读。
      expect(passcodeStageReveal('confirm', true)).assertFalse();
      expect(passcodeStageReveal('confirm', false)).assertFalse();
      // 校验旧密码的两步与锁屏（idle）交给偏好，两边各自跟随、互不覆盖。
      expect(passcodeStageReveal('verify-disable', true)).assertTrue();
      expect(passcodeStageReveal('verify-disable', false)).assertFalse();
      expect(passcodeStageReveal('verify-change', true)).assertTrue();
      expect(passcodeStageReveal('verify-change', false)).assertFalse();
      expect(passcodeStageReveal('idle', true)).assertTrue();
      expect(passcodeStageReveal('idle', false)).assertFalse();
    });
  });
}
