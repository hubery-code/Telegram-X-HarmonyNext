/**
 * entry/src/test/applock/AppLockGate.test.ets — 应用锁状态机（APPLOCK-101）。
 *
 * 这里测的是「什么时候要密码、答错了代价多大」，判定算术本身在 core/domain 已有单测；
 * 本文件守的是把那些判据接成生命周期行为的这条线：
 * 1. **冷启动读盘失败不锁**：抖动不该把用户锁在自己的应用外面，下次读到会纠正；
 * 2. **超时从切入后台起算**，且判定过一次就把 `backgroundAtMs` 清掉 ——
 *    留着它会让「回前台没锁」在下一次回前台时莫名其妙地锁上；
 * 3. 冷却期内**不查存储**（否则在线穷举的代价被绕开，存储报错还会冲掉倒计时文案）；
 * 4. 快照里永远没有 PIN（与 reducer 侧同一条不变量，两边形成才算闭环）。
 */

import { describe, it, expect } from '@ohos/hypium';
import { AppError, AppErrors, err, ok, Result, ManualClock } from '@tgx/core-common';
import {
  APP_LOCK_ERROR_CORRUPT,
  APP_LOCK_ERROR_STORE,
  APP_LOCK_ERROR_WRONG,
  AppLockStore,
  AutoLockChoice
} from '@tgx/core-domain';
import { AppLockGate, AppLockSnapshot } from '../../main/ets/applock/AppLockGate';

const PIN: string = '4271';

class FakeAppLockStore implements AppLockStore {
  isSet: boolean = false;
  choice: AutoLockChoice = 'instant';
  accepted: string = PIN;
  refreshFails: boolean = false;
  verifyError: AppError | null = null;

  refreshCalls: number = 0;
  verifyCalls: number = 0;
  wipeCalls: number = 0;

  isPasscodeSet(): boolean {
    return this.isSet;
  }

  async refreshPasscodeSet(): Promise<Result<boolean, AppError>> {
    this.refreshCalls = this.refreshCalls + 1;
    if (this.refreshFails) {
      return err<boolean, AppError>(AppErrors.platform(1, 'asset store unavailable', true));
    }
    return ok<boolean, AppError>(this.isSet);
  }

  autoLockChoice(): AutoLockChoice {
    return this.choice;
  }

  setAutoLockChoice(choice: AutoLockChoice): boolean {
    this.choice = choice;
    return true;
  }

  async setPasscode(pin: string): Promise<Result<void, AppError>> {
    this.accepted = pin;
    this.isSet = true;
    return ok<void, AppError>(undefined);
  }

  async verifyPasscode(pin: string): Promise<Result<boolean, AppError>> {
    this.verifyCalls = this.verifyCalls + 1;
    if (this.verifyError !== null) {
      return err<boolean, AppError>(this.verifyError);
    }
    return ok<boolean, AppError>(pin === this.accepted);
  }

  async removePasscode(): Promise<Result<void, AppError>> {
    this.wipeCalls = this.wipeCalls + 1;
    this.isSet = false;
    this.accepted = '';
    return ok<void, AppError>(undefined);
  }
}

function gateOn(store: FakeAppLockStore, nowMs: number = 1000): AppLockGate {
  return new AppLockGate(store, new ManualClock(nowMs, nowMs));
}

/** 走完「冷启动即锁 → 输入正确密码」这段真实路径，把机器停在已解锁态。 */
async function unlockedGate(store: FakeAppLockStore): Promise<AppLockGate> {
  const gate: AppLockGate = gateOn(store);
  await gate.bootstrap();
  await gate.submit(PIN);
  return gate;
}

export default function appLockGateTest(): void {
  describe('AppLockGateTest', () => {

    it('bootstrap_locksImmediatelyWhenAPasscodeExists', 0, async (): Promise<void> => {
      const store: FakeAppLockStore = new FakeAppLockStore();
      store.isSet = true;
      const gate: AppLockGate = gateOn(store);

      const snapshot: AppLockSnapshot = await gate.bootstrap();
      expect(snapshot.stage).assertEqual('awaiting-passcode');
      expect(gate.isLocked()).assertTrue();
    });

    it('bootstrap_readFailureLeavesTheAppUnlocked', 0, async (): Promise<void> => {
      // 读盘抖动 ≠ 没设密码，但更不能拿一个读不到的值去锁人。
      const store: FakeAppLockStore = new FakeAppLockStore();
      store.isSet = true;
      store.refreshFails = true;
      const gate: AppLockGate = gateOn(store);

      const snapshot: AppLockSnapshot = await gate.bootstrap();
      expect(snapshot.stage).assertEqual('unlocked');
      expect(gate.isLocked()).assertFalse();
    });

    it('bootstrap_withoutPasscodeStaysUnlocked', 0, async (): Promise<void> => {
      const store: FakeAppLockStore = new FakeAppLockStore();
      const gate: AppLockGate = gateOn(store);

      const snapshot: AppLockSnapshot = await gate.bootstrap();
      expect(snapshot.stage).assertEqual('unlocked');
      expect(gate.stage).assertEqual('unlocked');
    });

    it('bootstrap_readsTheDiskOncePerProcess', 0, async (): Promise<void> => {
      const store: FakeAppLockStore = new FakeAppLockStore();
      store.isSet = true;
      const gate: AppLockGate = gateOn(store);

      await gate.bootstrap();
      await gate.submit(PIN);
      await gate.bootstrap();
      expect(store.refreshCalls).assertEqual(1);
      // 第二次 bootstrap 不能把刚解锁的用户再锁回去。
      expect(gate.isLocked()).assertFalse();
    });

    it('resume_locksOnceTheInstantThresholdIsCrossed', 0, async (): Promise<void> => {
      const store: FakeAppLockStore = new FakeAppLockStore();
      store.isSet = true;
      const clock: ManualClock = new ManualClock(1000, 1000);
      const gate: AppLockGate = new AppLockGate(store, clock);
      await gate.bootstrap();
      await gate.submit(PIN);

      clock.setNowMillis(20000);
      gate.onBackground();
      clock.setNowMillis(20170);
      expect(gate.onForeground().stage).assertEqual('awaiting-passcode');
    });

    it('resume_withinTheTierKeepsWorkingAndForgetsTheBackgroundStamp', 0, async (): Promise<void> => {
      const store: FakeAppLockStore = new FakeAppLockStore();
      store.isSet = true;
      store.choice = 'one_minute';
      const clock: ManualClock = new ManualClock(1000, 1000);
      const gate: AppLockGate = new AppLockGate(store, clock);
      await gate.bootstrap();
      await gate.submit(PIN);

      gate.onBackground();
      clock.setNowMillis(31000);
      expect(gate.onForeground().stage).assertEqual('unlocked');

      // 没锁就得把后台时刻清零，否则用户前台待上十分钟，下一次回前台会被旧的时刻锁住。
      clock.setNowMillis(600000);
      expect(gate.onForeground().stage).assertEqual('unlocked');
    });

    it('resume_locksAfterTheFullTierElapsed', 0, async (): Promise<void> => {
      const store: FakeAppLockStore = new FakeAppLockStore();
      store.isSet = true;
      store.choice = 'one_minute';
      const clock: ManualClock = new ManualClock(1000, 1000);
      const gate: AppLockGate = new AppLockGate(store, clock);
      await gate.bootstrap();
      await gate.submit(PIN);

      gate.onBackground();
      clock.setNowMillis(62000);
      expect(gate.onForeground().stage).assertEqual('awaiting-passcode');
    });

    it('resume_neverTierNeverLocks', 0, async (): Promise<void> => {
      const store: FakeAppLockStore = new FakeAppLockStore();
      store.isSet = true;
      store.choice = 'never';
      const clock: ManualClock = new ManualClock(1000, 1000);
      const gate: AppLockGate = new AppLockGate(store, clock);
      await gate.bootstrap();
      await gate.submit(PIN);

      gate.onBackground();
      clock.setNowMillis(86400000);
      expect(gate.onForeground().stage).assertEqual('unlocked');
    });

    it('resume_doesNotUnlockAnExistingLock', 0, async (): Promise<void> => {
      const store: FakeAppLockStore = new FakeAppLockStore();
      store.isSet = true;
      const gate: AppLockGate = gateOn(store);
      await gate.bootstrap();

      gate.onBackground();
      expect(gate.onForeground().stage).assertEqual('awaiting-passcode');
      expect(gate.isLocked()).assertTrue();
    });

    it('wrongAttempts_blockStartsOnTheFourth', 0, async (): Promise<void> => {
      const store: FakeAppLockStore = new FakeAppLockStore();
      const gate: AppLockGate = await unlockedGate(store);
      gate.markLocked();

      for (let i = 0; i < 3; i++) {
        expect(await gate.submit('1111')).assertEqual('wrong');
      }
      let snapshot: AppLockSnapshot = gate.snapshot();
      expect(snapshot.wrongAttempts).assertEqual(3);
      expect(snapshot.stage).assertEqual('awaiting-passcode');
      expect(snapshot.failureKey).assertEqual(APP_LOCK_ERROR_WRONG);

      expect(await gate.submit('1111')).assertEqual('wrong');
      snapshot = gate.snapshot();
      expect(snapshot.stage).assertEqual('cooling-down');
      expect(snapshot.coolingDownSeconds).assertEqual(30);
    });

    it('cooldown_skipsTheStoreEntirely', 0, async (): Promise<void> => {
      const store: FakeAppLockStore = new FakeAppLockStore();
      const gate: AppLockGate = await unlockedGate(store);
      gate.markLocked();
      for (let i = 0; i < 4; i++) {
        await gate.submit('1111');
      }
      const calls: number = store.verifyCalls;

      expect(await gate.submit(PIN)).assertEqual('cooling-down');
      // 连正确密码也不放过：否则「先试一下，错了再说」还能继续，冷却就只是提示。
      expect(store.verifyCalls).assertEqual(calls);
      expect(gate.snapshot().failureKey).assertNull();
    });

    it('cooldown_secondLevelIsLongerAndSurvivesTick', 0, async (): Promise<void> => {
      const store: FakeAppLockStore = new FakeAppLockStore();
      const clock: ManualClock = new ManualClock(1000, 1000);
      const gate: AppLockGate = new AppLockGate(store, clock);
      gate.markLocked();

      for (let i = 0; i < 4; i++) {
        await gate.submit('1111');
      }
      expect(gate.snapshot().coolingDownSeconds).assertEqual(30);
      clock.advanceBy(30000);
      gate.tick();
      expect(gate.snapshot().stage).assertEqual('awaiting-passcode');
      // 解锁计数不清零，否则每次都只进第一档。
      expect(gate.snapshot().wrongAttempts).assertEqual(4);

      for (let i = 0; i < 4; i++) {
        await gate.submit('1111');
      }
      expect(gate.snapshot().coolingDownSeconds).assertEqual(45);
    });

    it('tick_withoutCooldownIsSilent', 0, async (): Promise<void> => {
      // 遮罩层每秒调一次；没有冷却时它必须什么都不发，否则输入点每秒重绘一次。
      const store: FakeAppLockStore = new FakeAppLockStore();
      store.isSet = true;
      const gate: AppLockGate = gateOn(store);
      await gate.bootstrap();

      let notices: number = 0;
      gate.subscribe((_snapshot: AppLockSnapshot): void => {
        notices = notices + 1;
      });
      gate.tick();
      expect(notices).assertEqual(0);

      gate.markUnlocked();
      expect(notices).assertEqual(1);
      gate.tick();
      expect(notices).assertEqual(1);
    });

    it('correctPin_unlocksAndClearsAccounting', 0, async (): Promise<void> => {
      const store: FakeAppLockStore = new FakeAppLockStore();
      const gate: AppLockGate = await unlockedGate(store);
      gate.markLocked();
      await gate.submit('1111');
      await gate.submit('1111');

      expect(await gate.submit(PIN)).assertEqual('unlocked');
      const snapshot: AppLockSnapshot = gate.snapshot();
      expect(snapshot.stage).assertEqual('unlocked');
      expect(snapshot.wrongAttempts).assertEqual(0);
      expect(snapshot.failureKey).assertNull();
    });

    it('storeError_stillCountsAndSaysStore', 0, async (): Promise<void> => {
      const store: FakeAppLockStore = new FakeAppLockStore();
      const gate: AppLockGate = await unlockedGate(store);
      gate.markLocked();
      store.verifyError = AppErrors.platform(2, 'cannot read', false);

      expect(await gate.submit(PIN)).assertEqual('store-error');
      expect(gate.snapshot().failureKey).assertEqual(APP_LOCK_ERROR_STORE);
      expect(gate.snapshot().wrongAttempts).assertEqual(1);
      expect(gate.isLocked()).assertTrue();
    });

    it('corruptSecret_saysCorruptNotWrong', 0, async (): Promise<void> => {
      // 派生值坏了要说「重新设一遍」；说成密码错会让用户对着坏数据反复试。
      const store: FakeAppLockStore = new FakeAppLockStore();
      const gate: AppLockGate = await unlockedGate(store);
      gate.markLocked();
      store.verifyError = AppErrors.internal('passcode-secret-corrupt');

      expect(await gate.submit(PIN)).assertEqual('store-error');
      expect(gate.snapshot().failureKey).assertEqual(APP_LOCK_ERROR_CORRUPT);
    });

    it('submitWhileUnlockedAnswersWrongWithoutTouchingTheStore', 0, async (): Promise<void> => {
      const store: FakeAppLockStore = new FakeAppLockStore();
      const gate: AppLockGate = await unlockedGate(store);
      const calls: number = store.verifyCalls;

      expect(await gate.submit('0000')).assertEqual('wrong');
      expect(store.verifyCalls).assertEqual(calls);
    });

    it('markUnlockedAndMarkLockedAreTheSettingsHooks', 0, async (): Promise<void> => {
      const store: FakeAppLockStore = new FakeAppLockStore();
      const gate: AppLockGate = await unlockedGate(store);
      expect(gate.isLocked()).assertFalse();

      gate.markLocked();
      expect(gate.stage).assertEqual('awaiting-passcode');
      gate.markUnlocked();
      expect(gate.stage).assertEqual('unlocked');
      expect(gate.snapshot().wrongAttempts).assertEqual(0);
    });

    it('subscribe_notifiesOnTransitionsUntilUnsubscribed', 0, async (): Promise<void> => {
      const store: FakeAppLockStore = new FakeAppLockStore();
      store.isSet = true;
      const gate: AppLockGate = gateOn(store);
      let notices: number = 0;
      const unsubscribe: () => void = gate.subscribe((_snapshot: AppLockSnapshot): void => {
        notices = notices + 1;
      });

      await gate.bootstrap();
      expect(notices).assertEqual(1);
      gate.markUnlocked();
      expect(notices).assertEqual(2);

      unsubscribe();
      gate.markLocked();
      expect(notices).assertEqual(2);
    });

    it('snapshotNeverCarriesThePin', 0, async (): Promise<void> => {
      const store: FakeAppLockStore = new FakeAppLockStore();
      const gate: AppLockGate = await unlockedGate(store);
      gate.markLocked();
      await gate.submit(PIN);
      await gate.submit('1111');
      await gate.submit('9999');

      const text: string = JSON.stringify(gate.snapshot());
      expect(text.indexOf(PIN) >= 0).assertFalse();
      expect(text.indexOf('1111') >= 0).assertFalse();
    });
  });
}
