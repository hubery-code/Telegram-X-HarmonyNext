/**
 * core/domain — 应用锁纯模型单元测试（APPLOCK-101）。
 *
 * 守住的回归：
 * 1. `instant` 的阈值是 170ms 而不是 0（Android `Passcode.java:197-206`）—— 写成 0 的话
 *    「切后台马上回来」也会锁，用户会觉得锁坏了；
 * 2. 脏档位索引必须收敛到默认档：偏好里的整数可能是旧版本留下的，判据拿到 undefined
 *    就等于锁的行为不确定；
 * 3. 冷却曲线 `30 / 45 / 60 … ≤300`（`Settings.java:5390-5400`），且第 1 档不吃 `−15`；
 * 4. 每满 4 次错误才进一档冷却（`Settings.java:5468-5498`），第 5 次错误不该再叠一档；
 * 5. 带前导 0 的四位 PIN 合法（按数字大小判会把 "0042" 判成三位）。
 */

import { describe, it, expect } from '@ohos/hypium';
import { AppError, AppErrors } from '@tgx/core-common';
import {
  APP_LOCK_BLOCK_BASE_SECONDS,
  APP_LOCK_BLOCK_MAX_SECONDS,
  APP_LOCK_BLOCK_ERROR_THRESHOLD,
  APP_LOCK_ERROR_CORRUPT,
  APP_LOCK_ERROR_STORE,
  AUTO_LOCK_CHOICES,
  AUTO_LOCK_DEFAULT,
  AutoLockChoice,
  appLockBlockSecondsFor,
  appLockNoticeKeyForError,
  appLockRemainingSeconds,
  appLockShouldBlockAfterError,
  appendPinDigit,
  autoLockChoiceAt,
  autoLockLabelKey,
  autoLockStoredIndex,
  autoLockTimeoutMs,
  isAppLockPin,
  isPinComplete,
  nextAutoLockChoice,
  popPinDigit,
  shouldLockOnResume
} from '../../main/ets/applock/AppLock';

export default function appLockTest(): void {
  describe('AppLockTest', () => {

    it('instantUsesAndroidSeventyMsThreshold', 0, () => {
      expect(autoLockTimeoutMs('instant')).assertEqual(170);
      expect(autoLockTimeoutMs('one_minute')).assertEqual(60000);
      expect(autoLockTimeoutMs('five_minutes')).assertEqual(300000);
      expect(autoLockTimeoutMs('one_hour')).assertEqual(3600000);
      expect(autoLockTimeoutMs('five_hours')).assertEqual(18000000);
      // never 用负数表示「没有可达的阈值」，不是 0 —— 0 会让前台一回来就锁。
      expect(autoLockTimeoutMs('never')).assertEqual(-1);
    });

    it('storedIndexRoundTripsAndDirtyValuesFallBack', 0, () => {
      for (let i = 0; i < AUTO_LOCK_CHOICES.length; i++) {
        expect(autoLockStoredIndex(AUTO_LOCK_CHOICES[i])).assertEqual(i);
        expect(autoLockChoiceAt(i)).assertEqual(AUTO_LOCK_CHOICES[i]);
      }
      expect(autoLockChoiceAt(null)).assertEqual(AUTO_LOCK_DEFAULT);
      expect(autoLockChoiceAt(-1)).assertEqual(AUTO_LOCK_DEFAULT);
      expect(autoLockChoiceAt(AUTO_LOCK_CHOICES.length)).assertEqual(AUTO_LOCK_DEFAULT);
      expect(autoLockChoiceAt(1.5)).assertEqual(AUTO_LOCK_DEFAULT);
      expect(autoLockChoiceAt(Number.NaN)).assertEqual(AUTO_LOCK_DEFAULT);
    });

    it('everyChoiceHasItsOwnLabel', 0, () => {
      const seen: string[] = [];
      for (let i = 0; i < AUTO_LOCK_CHOICES.length; i++) {
        const label: string = autoLockLabelKey(AUTO_LOCK_CHOICES[i]);
        expect(label.length > 0).assertTrue();
        // 两个档位共用一条文案 = 界面上看不出区别，所以按去重断言。
        expect(seen.indexOf(label) < 0).assertTrue();
        seen.push(label);
      }
    });

    it('cycleCoversEveryChoiceAndWraps', 0, () => {
      let current: AutoLockChoice = AUTO_LOCK_DEFAULT;
      for (let i = 0; i < AUTO_LOCK_CHOICES.length; i++) {
        current = nextAutoLockChoice(current);
      }
      // 点满一圈必须回到原点，少一档就永远点不到。
      expect(current).assertEqual(AUTO_LOCK_DEFAULT);
    });

    it('pinMustBeFourAsciiDigits', 0, () => {
      expect(isAppLockPin('0042')).assertTrue();
      expect(isAppLockPin('1234')).assertTrue();
      expect(isAppLockPin('123')).assertFalse();
      expect(isAppLockPin('12345')).assertFalse();
      expect(isAppLockPin('12a4')).assertFalse();
      expect(isAppLockPin('')).assertFalse();
      expect(isPinComplete('0000')).assertTrue();
      expect(isPinComplete('000')).assertFalse();
    });

    it('keypadInputIsSwallowedNotErrored', 0, () => {
      expect(appendPinDigit('12', '3')).assertEqual('123');
      // 满位后再按：原样返回，不报错也不吞掉已输入的值。
      expect(appendPinDigit('1234', '5')).assertEqual('1234');
      expect(appendPinDigit('12', 'a')).assertEqual('12');
      expect(appendPinDigit('12', '')).assertEqual('12');
      expect(popPinDigit('123')).assertEqual('12');
      expect(popPinDigit('')).assertEqual('');
    });

    it('lockOnResumeMeasuresBackgroundTime', 0, () => {
      // 没进过后台（冷启动第一帧）不锁。
      expect(shouldLockOnResume(100000, 0, 'instant')).assertFalse();
      expect(shouldLockOnResume(100000, 99999, 'instant')).assertFalse();
      expect(shouldLockOnResume(100000, 99830, 'instant')).assertTrue();
      expect(shouldLockOnResume(100000, 99000, 'one_minute')).assertFalse();
      expect(shouldLockOnResume(160000, 100000, 'one_minute')).assertTrue();
      // never 档后台多久都不锁（差异 ②：冷启动是否锁由「有没有 PIN」判，不归这里）。
      expect(shouldLockOnResume(9999999, 0, 'never')).assertFalse();
      expect(shouldLockOnResume(9999999, 1, 'never')).assertFalse();
    });

    it('blockCurveMatchesAndroid', 0, () => {
      expect(appLockBlockSecondsFor(0)).assertEqual(0);
      // 第 1 档是基础档，不是 30−15 —— Android 在同一个分支上写的就是这个。
      expect(appLockBlockSecondsFor(1)).assertEqual(APP_LOCK_BLOCK_BASE_SECONDS);
      expect(appLockBlockSecondsFor(2)).assertEqual(45);
      expect(appLockBlockSecondsFor(3)).assertEqual(60);
      expect(appLockBlockSecondsFor(20)).assertEqual(APP_LOCK_BLOCK_MAX_SECONDS);
    });

    it('cooldownTriggersOncePerFourErrors', 0, () => {
      expect(appLockShouldBlockAfterError(0)).assertFalse();
      expect(appLockShouldBlockAfterError(1)).assertFalse();
      expect(appLockShouldBlockAfterError(APP_LOCK_BLOCK_ERROR_THRESHOLD)).assertTrue();
      expect(appLockShouldBlockAfterError(5)).assertFalse();
      expect(appLockShouldBlockAfterError(8)).assertTrue();
    });

    it('remainingSecondsRoundsUp', 0, () => {
      expect(appLockRemainingSeconds(1000, 1000)).assertEqual(0);
      expect(appLockRemainingSeconds(1000, 999)).assertEqual(0);
      expect(appLockRemainingSeconds(1000, 1001)).assertEqual(1);
      expect(appLockRemainingSeconds(1000, 3500)).assertEqual(3);
    });

    it('storeErrorsMapToDistinctNotices', 0, () => {
      const corrupt: AppError = AppErrors.internal('passcode-secret-corrupt', 'x');
      expect(appLockNoticeKeyForError(corrupt)).assertEqual(APP_LOCK_ERROR_CORRUPT);
      const other: AppError = AppErrors.internal('passcode-digest-length', 'x');
      expect(appLockNoticeKeyForError(other)).assertEqual(APP_LOCK_ERROR_STORE);
      const platform: AppError = AppErrors.platform(24000005, 'locked', true);
      expect(appLockNoticeKeyForError(platform)).assertEqual(APP_LOCK_ERROR_STORE);
    });
  });
}
