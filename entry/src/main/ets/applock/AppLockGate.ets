/**
 * entry 装配层 — 应用锁状态机（APPLOCK-101）。
 *
 * 只负责「什么时候要密码、答错了怎么办」这两件事，不负责界面：
 * - **锁的时机**：冷启动即锁（设了 PIN 的话）、回前台按档位判定；
 * - **答错的代价**：每错 4 次进一次冷却，首档 30s、其后每档 +15s、封顶 5 分钟
 *   （Android `Settings.java:5390-5400` 的 `blockPasscode`）。
 *
 * 判定算术全部在 `core/domain/applock`（`shouldLockOnResume` / `appLockBlockSecondsFor` /
 * `appLockShouldBlockAfterError` / `appLockRemainingSeconds`）—— 设置页和遮罩层要按同一套
 * 规则显示「再等 Ns」，不能各写一份。
 *
 * ## 保密边界
 *
 * PIN 只作为 `submit(pin)` 的**入参**存在：不写进快照、不进日志、不进 `AppStorage`。
 * 快照里只有阶段、剩余秒数、错误次数这三样可以说给用户的东西。
 *
 * ## 为什么冷却期内不查存储
 *
 * Android 在冷却期直接吞掉输入（`PasscodeView` 只让继续倒计时）。这里同样先判冷却再验密码：
 * 一是冷却的意义就是让在线穷举慢下来，二是存储层出错时也不该把「你还有 20 秒」这句话冲掉。
 */

import {
  APP_LOCK_ERROR_WRONG,
  AppLockStore,
  appLockBlockSecondsFor,
  appLockNoticeKeyForError,
  appLockRemainingSeconds,
  appLockShouldBlockAfterError,
  shouldLockOnResume
} from '@tgx/core-domain';
import { AppError, Clock, Result, SystemClock } from '@tgx/core-common';

/** 遮罩层与设置页共用的阶段。 */
export type AppLockStage = 'unlocked' | 'awaiting-passcode' | 'cooling-down';

/** `submit()` 的四答；UI 按此挑文案，不在本类里存文案。 */
export type AppLockSubmitOutcome = 'unlocked' | 'wrong' | 'cooling-down' | 'store-error';

/** 可观察快照；`pin` 相关的任何值都不在这里。 */
export interface AppLockSnapshot {
  readonly stage: AppLockStage;
  readonly coolingDownSeconds: number;
  readonly wrongAttempts: number;
  /** 最近一次 `submit` 的失败原因（Lang key）；成功或空闲为 null。 */
  readonly failureKey: string | null;
}

export class AppLockGate {
  private readonly store: AppLockStore;
  private readonly clock: Clock;
  private readonly listeners: ((snapshot: AppLockSnapshot) => void)[] = [];

  private lockedValue: boolean = false;
  private backgroundAtMs: number = 0;
  /** 本轮锁定周期内的累计错误次数；解锁或重新上锁时清零。 */
  private wrongAttemptsValue: number = 0;
  /** 已进过的冷却档数（= 错误次数 / 4）。 */
  private blockLevel: number = 0;
  private blockedUntilMs: number = 0;
  private failureKeyValue: string | null = null;
  private bootstrapped: boolean = false;

  constructor(store: AppLockStore, clock?: Clock) {
    this.store = store;
    this.clock = clock !== undefined ? clock : new SystemClock();
  }

  /**
   * 冷启动入口：确认本机是否设过 PIN，设过就立刻上锁（差异 ②：不看档位）。
   * 读盘失败时**不锁**也不解锁 —— 此时 `isPasscodeSet()` 的缓存是 false，
   * 表现等同于「本机没设密码」；下次成功读到会纠正。宁可误开也不要把读盘抖动
   * 变成锁死。
   */
  async bootstrap(): Promise<AppLockSnapshot> {
    if (!this.bootstrapped) {
      this.bootstrapped = true;
      const res: Result<boolean, AppError> = await this.store.refreshPasscodeSet();
      if (res.ok && res.value) {
        this.enterLock();
      }
    }
    return this.snapshot();
  }

  get stage(): AppLockStage {
    return this.snapshot().stage;
  }

  isLocked(): boolean {
    return this.lockedValue;
  }

  snapshot(): AppLockSnapshot {
    const remaining: number = appLockRemainingSeconds(this.clock.nowMillis(), this.blockedUntilMs);
    const stage: AppLockStage = !this.lockedValue
      ? 'unlocked'
      : (remaining > 0 ? 'cooling-down' : 'awaiting-passcode');
    return {
      stage: stage,
      coolingDownSeconds: remaining,
      wrongAttempts: this.wrongAttemptsValue,
      failureKey: this.failureKeyValue
    };
  }

  /**
   * 遮罩输入时是否明文（APPLOCK-102）：与设置页读同一个持久偏好，
   * 否则「设置里说明文、锁屏上按圆点」，用户会以为自己按错了。
   */
  passcodeVisible(): boolean {
    return this.store.passcodeVisible();
  }

  subscribe(listener: (snapshot: AppLockSnapshot) => void): () => void {
    this.listeners.push(listener);
    const self: AppLockGate = this;
    return (): void => {
      self.removeListener(listener);
    };
  }

  /**
   * 供遮罩层挂秒级定时器：冷却归零时把阶段推回 `awaiting-passcode`。
   * 只在真的有变化时通知，避免每秒重绘一次输入点。
   */
  tick(): void {
    if (!this.lockedValue || this.blockedUntilMs === 0) {
      return;
    }
    if (appLockRemainingSeconds(this.clock.nowMillis(), this.blockedUntilMs) > 0) {
      this.notify();
      return;
    }
    this.blockedUntilMs = 0;
    this.notify();
  }

  /** 设置页里「关闭密码」成功后调用：本机已经没有 PIN，遮罩应当消失。 */
  markUnlocked(): void {
    this.lockedValue = false;
    this.resetAttemptAccounting();
    this.notify();
  }

  /** 设置页里「创建/修改密码」成功后调用：立刻生效，避免回遮罩时状态不一致。 */
  markLocked(): void {
    this.enterLock();
  }

  onBackground(): void {
    this.backgroundAtMs = this.clock.nowMillis();
  }

  /** 回到前台：按档位判定是否要重新上锁。 */
  onForeground(): AppLockSnapshot {
    if (!this.lockedValue) {
      if (this.store.isPasscodeSet()
        && shouldLockOnResume(this.clock.nowMillis(), this.backgroundAtMs, this.store.autoLockChoice())) {
        this.enterLock();
      } else {
        this.backgroundAtMs = 0;
      }
    }
    return this.snapshot();
  }

  /**
   * 提交一个 PIN。
   * 冷却未结束 → 直接回 `cooling-down`，不查存储；
   * 存储报错（含派生值损坏）→ `store-error`，错误次数照记，让攻击者拿不到「数据坏了」的免费重试；
   * 校验失败 → `wrong`，满 4 次进一档冷却。
   */
  async submit(pin: string): Promise<AppLockSubmitOutcome> {
    if (!this.lockedValue) {
      return 'wrong';
    }
    const now: number = this.clock.nowMillis();
    if (appLockRemainingSeconds(now, this.blockedUntilMs) > 0) {
      this.failureKeyValue = null;
      this.notify();
      return 'cooling-down';
    }

    const res: Result<boolean, AppError> = await this.store.verifyPasscode(pin);
    if (res.err) {
      this.countFailure(res.error);
      return 'store-error';
    }
    // ArkTS 不在提前 return 后收窄 Result，取值走 fold（AGENTS.md 第 3.1 条）。
    const matched: boolean = res.fold<boolean>(
      (value: boolean): boolean => value,
      (_error: AppError): boolean => false
    );
    if (matched) {
      this.lockedValue = false;
      this.backgroundAtMs = 0;
      this.resetAttemptAccounting();
      this.notify();
      return 'unlocked';
    }
    this.countFailure(null);
    return 'wrong';
  }

  private countFailure(error: AppError | null): void {
    this.wrongAttemptsValue = this.wrongAttemptsValue + 1;
    if (error !== null) {
      this.failureKeyValue = appLockNoticeKeyForError(error);
    } else {
      this.failureKeyValue = APP_LOCK_ERROR_WRONG;
    }
    if (appLockShouldBlockAfterError(this.wrongAttemptsValue)) {
      this.blockLevel = this.blockLevel + 1;
      const seconds: number = appLockBlockSecondsFor(this.blockLevel);
      this.blockedUntilMs = this.clock.nowMillis() + seconds * 1000;
    }
    this.notify();
  }

  private enterLock(): void {
    this.lockedValue = true;
    this.backgroundAtMs = 0;
    this.resetAttemptAccounting();
    this.notify();
  }

  private resetAttemptAccounting(): void {
    this.wrongAttemptsValue = 0;
    this.blockLevel = 0;
    this.blockedUntilMs = 0;
    this.failureKeyValue = null;
  }

  private removeListener(listener: (snapshot: AppLockSnapshot) => void): void {
    const index: number = this.listeners.indexOf(listener);
    if (index >= 0) {
      this.listeners.splice(index, 1);
    }
  }

  private notify(): void {
    const snapshot: AppLockSnapshot = this.snapshot();
    for (let i = 0; i < this.listeners.length; i++) {
      this.listeners[i](snapshot);
    }
  }
}
