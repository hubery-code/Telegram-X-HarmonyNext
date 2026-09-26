/**
 * core/domain — 应用锁 PIN 输入流程的阶段模型（APPLOCK-101）。
 *
 * 设置页的「创建 / 修改 / 关闭」三条流程和锁屏遮罩共用一套阶段名，判据集中在 reducer：
 * 放在页面上做条件判断的话，「输入两次」和「先验旧密码」这两条规则会在两个页面各写一遍。
 *
 * ## 为什么这里没有「第一次输入的 PIN」
 *
 * 两次输入是否一致必须由状态机判，但**判定用的草稿值不进状态**：`SettingsUiState` 每帧都要
 * 被复制和比较，把用户输入的密码放进去，等于让它在日志、快照、调试面板里到处留副本。
 * 草稿只存在 `SettingsCoordinator` 的私有字段里，流程走完即清空。所以本文件只有阶段与
 * 阶段迁移的纯判据，没有一个方法能把 PIN 读出来。
 */

import { APP_LOCK_PIN_LENGTH } from './AppLock';

export type PasscodeFlowStage =
  /** 键盘不出现。 */
  | 'idle'
  /** 输入新密码（第一次）。 */
  | 'enter'
  /** 再输入一次确认。 */
  | 'confirm'
  /** 关闭前先验当前密码。 */
  | 'verify-disable'
  /** 修改前先验当前密码。 */
  | 'verify-change';

/** 一次 `submit` 之后 reducer 要做的事；把「判据」和「执行」分开，reducer 保持纯函数。 */
export type PasscodeStepAction =
  /** 阶段不允许输入（键盘本就不在），或输入不合法。 */
  | 'ignore'
  /** 格式不对：四位数字之外一律不接受，也不进任何存储。 */
  | 'invalid'
  /** 存草稿并进入确认步。 */
  | 'draft'
  /** 把这次输入交给 coordinator 与草稿比对后落盘。 */
  | 'commit'
  /** 交给 coordinator 校验，`operation` 决定验完是关闭还是转修改。 */
  | 'verify';

export interface PasscodeStepResult {
  readonly action: PasscodeStepAction;
  /** 'verify' 时的后续意图；其余动作为 null。 */
  readonly verifyFor: PasscodeFlowStage | null;
}

/** 阶段对应的提示文案 Lang key（页面与遮罩共用）。 */
export function passcodeStagePrompt(stage: PasscodeFlowStage): string {
  if (stage === 'enter') {
    return 'Enter a new passcode';
  }
  if (stage === 'confirm') {
    return 'Repeat the passcode';
  }
  if (stage === 'verify-disable' || stage === 'verify-change') {
    return 'Enter your current passcode';
  }
  return 'Passcode';
}

/**
 * 键盘在某个阶段收到一次提交后的迁移判据（纯函数，reducer 与单测共用）。
 *
 * 长度不够四位不算一次提交 —— 键盘本身就不允许满四位之前把 `submit` 发出来，
 * 这里再挡一道是防调用方绕过键盘直接 dispatch。
 */
export function passcodeStepFor(stage: PasscodeFlowStage, digits: string): PasscodeStepResult {
  if (stage === 'idle') {
    return { action: 'ignore', verifyFor: null };
  }
  if (digits.length !== APP_LOCK_PIN_LENGTH) {
    return { action: 'invalid', verifyFor: null };
  }
  if (stage === 'enter') {
    return { action: 'draft', verifyFor: null };
  }
  if (stage === 'confirm') {
    return { action: 'commit', verifyFor: null };
  }
  return { action: 'verify', verifyFor: stage };
}
