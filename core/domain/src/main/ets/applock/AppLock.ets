/**
 * core/domain — 应用锁（Passcode）的纯模型与判定（APPLOCK-101 / FEAT-P2-008）。
 *
 * 对标 Telegram X `unsorted/Passcode.java`：本机四位数字 PIN + 按档位的自动锁定。
 * 本模块 Kit-free —— 设置页、锁屏遮罩、entry 装配共用同一套判据，避免出现
 * 「页面上写着 1 分钟、实际按 5 分钟锁」的两套真相。
 *
 * 与 Android 的三处**有意**差异，都记在这里：
 * 1. **PIN 派生值不落 SharedPreferences**。Android 是 `md5(md5(pin + 固定盐))`
 *    存在偏好里（`Passcode.java:82-83, 334-336`）；本端把 `盐 + sha256(盐 ‖ pin)`
 *    交给系统安全服务托管（`platform/keystore`），偏好里只有档位这种非敏感整数。
 * 2. **不设 PIN 时冷启动不锁，设了 PIN 就锁**（不看档位）。Android 冷启动读
 *    `pc_locked` 且只在 `autolockMode != NONE` 时才 `checkAutoLock()`
 *    （`Passcode.java:118-124`），配合它 header 上的手动锁按钮；本端没有那个按钮，
 *    「杀进程重来不用输密码」只会让人觉得锁没生效。
 * 3. **超时从「切入后台」起算**，不是从最后一次触摸起算。Android 用全局触摸追踪
 *    不断刷新 `autolockTime`（`Passcode.java:242-254`），所以前台闲置也会锁；本端
 *    没有那层全局触摸钩子，前台闲置不锁（列为遗留）。
 */

import { AppError, Result } from '@tgx/core-common';

/** Android `PINCODE_SIZE = 4`（`Passcode.java:79`）；本端只做数字 PIN，不做图案/手势/自定义密码。 */
export const APP_LOCK_PIN_LENGTH: number = 4;

/**
 * 自动锁定档。`never` 即 Android 的 `AUTOLOCK_MODE_NONE`（`Passcode.java:66`）——
 * 后台回来不锁，只有冷启动锁。
 */
export type AutoLockChoice =
  | 'instant'
  | 'one_minute'
  | 'five_minutes'
  | 'one_hour'
  | 'five_hours'
  | 'never';

/** 页面与存储的档位顺序（对齐 Android `AUTOLOCK_MODE_*` 的语义枚举，索引即存储值）。 */
export const AUTO_LOCK_CHOICES: AutoLockChoice[] = [
  'instant',
  'one_minute',
  'five_minutes',
  'one_hour',
  'five_hours',
  'never'
];

/**
 * 默认档：即时。
 * Android 的默认是 `AUTOLOCK_MODE_NONE`，但它是「默认没开 PIN」的默认值 ——
 * 用户专门去开 PIN 之后还默认不锁，等于这个开关没起作用。
 */
export const AUTO_LOCK_DEFAULT: AutoLockChoice = 'instant';

/**
 * Android `getAutolockTime()`（`Passcode.java:197-206`）：`instant` 不是 0 而是 170ms ——
 * 那一下是为了让「切后台再切回来」这个动作本身必然跨过阈值，同时又不至于把
 * 「误触 Home 键马上回来」也判成超时。`never` 用 -1 表示「没有阈值可达」。
 */
export function autoLockTimeoutMs(choice: AutoLockChoice): number {
  if (choice === 'instant') {
    return 170;
  }
  if (choice === 'one_minute') {
    return 60000;
  }
  if (choice === 'five_minutes') {
    return 300000;
  }
  if (choice === 'one_hour') {
    return 3600000;
  }
  if (choice === 'five_hours') {
    return 18000000;
  }
  return -1;
}

/** 档位文案（Lang 字典的英文 key，由页面 `t()` 翻译；模型层零 Lang 依赖）。 */
export function autoLockLabelKey(choice: AutoLockChoice): string {
  if (choice === 'instant') {
    return 'Immediately';
  }
  if (choice === 'one_minute') {
    return 'After 1 minute';
  }
  if (choice === 'five_minutes') {
    return 'After 5 minutes';
  }
  if (choice === 'one_hour') {
    return 'After 1 hour';
  }
  if (choice === 'five_hours') {
    return 'After 5 hours';
  }
  return 'Never';
}

/** 档位 → 存储索引。偏好里只存这个整数（非敏感）。 */
export function autoLockStoredIndex(choice: AutoLockChoice): number {
  for (let i = 0; i < AUTO_LOCK_CHOICES.length; i++) {
    if (AUTO_LOCK_CHOICES[i] === choice) {
      return i;
    }
  }
  return autoLockStoredIndex(AUTO_LOCK_DEFAULT);
}

/**
 * 存储索引 → 档位；脏值（旧版本留下的、越界的、非整数）一律收敛到默认档。
 * 设置读不出来不该影响启动，更不该让锁判定拿到一个 `undefined`。
 */
export function autoLockChoiceAt(index: number | null): AutoLockChoice {
  if (index === null) {
    return AUTO_LOCK_DEFAULT;
  }
  if (!Number.isInteger(index) || index < 0 || index >= AUTO_LOCK_CHOICES.length) {
    return AUTO_LOCK_DEFAULT;
  }
  return AUTO_LOCK_CHOICES[index];
}

/** 点一行即循环到下一档（设置页与子页同一口径）。 */
export function nextAutoLockChoice(current: AutoLockChoice): AutoLockChoice {
  const index: number = autoLockStoredIndex(current);
  return AUTO_LOCK_CHOICES[(index + 1) % AUTO_LOCK_CHOICES.length];
}

/** PIN 是否为合法的四位十进制数字（含前导 0，所以不能按数字大小判）。 */
export function isAppLockPin(pin: string): boolean {
  if (pin.length !== APP_LOCK_PIN_LENGTH) {
    return false;
  }
  for (let i = 0; i < pin.length; i++) {
    const code: number = pin.charCodeAt(i);
    if (code < 48 || code > 57) {
      return false;
    }
  }
  return true;
}

/** 满位或非法字符直接原样返回 —— 键盘多按一下就静默丢弃，不报错。 */
export function appendPinDigit(digits: string, digit: string): string {
  if (digits.length >= APP_LOCK_PIN_LENGTH) {
    return digits;
  }
  if (digit.length !== 1) {
    return digits;
  }
  const code: number = digit.charCodeAt(0);
  if (code < 48 || code > 57) {
    return digits;
  }
  return digits + digit;
}

export function popPinDigit(digits: string): string {
  return digits.length === 0 ? digits : digits.substring(0, digits.length - 1);
}

export function isPinComplete(digits: string): boolean {
  return digits.length === APP_LOCK_PIN_LENGTH;
}

/**
 * 回到前台时该不该锁（差异 ③：`backgroundAtMs` 是**切入后台**的时刻）。
 * 没进过后台（`backgroundAtMs === 0`，冷启动第一帧就是前台）不锁；`never` 不锁。
 */
export function shouldLockOnResume(nowMs: number, backgroundAtMs: number, choice: AutoLockChoice): boolean {
  if (backgroundAtMs <= 0) {
    return false;
  }
  const timeoutMs: number = autoLockTimeoutMs(choice);
  if (timeoutMs < 0) {
    return false;
  }
  return nowMs - backgroundAtMs >= timeoutMs;
}

/** Android `Settings.java:5468-5498`：每 4 次错误进一次冷却。 */
export const APP_LOCK_BLOCK_ERROR_THRESHOLD: number = 4;

/** 首档 30s，其后每档 +15s，封顶 5 分钟（`Settings.java:5390-5400`）。 */
export const APP_LOCK_BLOCK_BASE_SECONDS: number = 30;
export const APP_LOCK_BLOCK_STEP_SECONDS: number = 15;
export const APP_LOCK_BLOCK_MAX_SECONDS: number = 300;

/**
 * 第 `blockLevel` 次冷却（从 1 起）的秒数；0 表示不冷却。
 * 注意 `level <= 1` 走的是基础档而不是 `30 - 15`，Android 就是在这个分支上写的。
 */
export function appLockBlockSecondsFor(blockLevel: number): number {
  if (blockLevel <= 0) {
    return 0;
  }
  if (blockLevel === 1) {
    return APP_LOCK_BLOCK_BASE_SECONDS;
  }
  const seconds: number = APP_LOCK_BLOCK_BASE_SECONDS + APP_LOCK_BLOCK_STEP_SECONDS * (blockLevel - 1);
  return seconds > APP_LOCK_BLOCK_MAX_SECONDS ? APP_LOCK_BLOCK_MAX_SECONDS : seconds;
}

/** 第 `errors` 次错误是否刚好触发一次新的冷却（每满 4 次触发一档）。 */
export function appLockShouldBlockAfterError(errors: number): boolean {
  return errors > 0 && errors % APP_LOCK_BLOCK_ERROR_THRESHOLD === 0;
}

/** 冷却剩余秒数；向上取整，因为页面显示的是「再等 Ns」。 */
export function appLockRemainingSeconds(nowMs: number, blockedUntilMs: number): number {
  if (blockedUntilMs <= nowMs) {
    return 0;
  }
  return Math.ceil((blockedUntilMs - nowMs) / 1000);
}

/** 设置页与锁屏遮罩共用的业务契约；生产实现在 `entry`（偏好 + `platform/keystore`）。 */
export interface AppLockStore {
  /** 本机是否已设 PIN；同步读缓存，缓存由 `refreshPasscodeSet()` 或写操作刷新。 */
  isPasscodeSet(): boolean;

  /** 读盘确认是否已设 PIN（进程启动时调一次），返回确认后的值。 */
  refreshPasscodeSet(): Promise<Result<boolean, AppError>>;

  autoLockChoice(): AutoLockChoice;

  /** 写档位；返回是否落盘成功，调用方据此决定页面是回滚还是提示。 */
  setAutoLockChoice(choice: AutoLockChoice): boolean;

  /**
   * 输入时是否明文显示已按下的位数（Android `Passcode.setVisible` / 偏好 `pc_visible`）。
   * 默认 `false`（圆点）。这只影响**输入过程**的呈现，设置的 PIN 本身从不落盘（见 `HarmonyPasscodeStore`）。
   */
  passcodeVisible(): boolean;

  /** 写可见性偏好；返回是否落盘成功，页面据此回滚开关。 */
  setPasscodeVisible(visible: boolean): boolean;

  setPasscode(pin: string): Promise<Result<void, AppError>>;

  verifyPasscode(pin: string): Promise<Result<boolean, AppError>>;

  removePasscode(): Promise<Result<void, AppError>>;
}

/**
 * 应用锁失败原因的 Lang key（`core/common` 的 `Lang` 索引键）。
 *
 * 放在 core/domain 而不是各页面里写字符串：判定层（`entry` 的锁态机）只知道「存储说不过去」，
 * 呈现层（设置页、锁屏遮罩）要按同一个键取文案，两边拼写不一致就会静默显示成 key 本身。
 */
export const APP_LOCK_ERROR_WRONG: string = 'PasscodeErrorWrong';
export const APP_LOCK_ERROR_STORE: string = 'PasscodeErrorStoreUnavailable';
export const APP_LOCK_ERROR_CORRUPT: string = 'PasscodeErrorCorrupt';

/** 流程提示的 Lang key（成功与本地校验失败都不经存储，所以只有 key）。 */
export const APP_LOCK_NOTICE_INVALID: string = 'PasscodeNoticeInvalid';
export const APP_LOCK_NOTICE_MISMATCH: string = 'PasscodeNoticeMismatch';
export const APP_LOCK_NOTICE_SAVED: string = 'PasscodeNoticeSaved';
export const APP_LOCK_NOTICE_REMOVED: string = 'PasscodeNoticeRemoved';

/**
 * 存储层报错 → 给用户看的那句（Lang key）。
 *
 * 派生值损坏和「此刻读不出来」必须分开说：前者要告诉用户别再试了，去把密码重新设一遍；
 * 后者只要说稍后再试。两者的文案混在一起，用户会对着一个坏掉的数据反复输密码。
 * 原文（`error.message` / `cause`）不进文案表，本仓口径是只按 kind/code 分类。
 */
export function appLockNoticeKeyForError(error: AppError): string {
  if (error.kind === 'internal') {
    return error.invariant === 'passcode-secret-corrupt' ? APP_LOCK_ERROR_CORRUPT : APP_LOCK_ERROR_STORE;
  }
  return APP_LOCK_ERROR_STORE;
}
