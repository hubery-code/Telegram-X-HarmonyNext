/**
 * platform/keystore — PIN 秘密值的纯字节逻辑（APPLOCK-102）。
 *
 * 从 `HarmonyPasscodeStore` 里拆出来的是不含密码学、不含 Kit 的那一半：
 * 输入合法性、`salt ‖ digest` 的打包/拆包、恒定时间比对。
 * 留在 adapter 里的只有「取随机盐」和「算 SHA-256」两步 —— 那两步要真实安全服务，
 * CI 跑不动，所以本文件承担的恰恰是**跑不动的那一半一旦写错会锁死用户**的判据：
 * 打包时少写一个前缀、拆包时不校验长度，现象都是「用户被自己的密码锁在外面」，
 * 而且没有任何日志能解释为什么。
 */

import { AppError, AppErrors, Result, ok, err } from '@tgx/core-common';

/** Android `Passcode.PINCODE_SIZE`：本端只支持 4 位数字 PIN。 */
export const PIN_LENGTH: number = 4;

/** 盐字节数（每次 `set` 重新生成，见 `HarmonyPasscodeStore`）。 */
export const SALT_LENGTH: number = 16;

/** SHA-256 摘要字节数。 */
export const DIGEST_LENGTH: number = 32;

/** 落盘的一条资产应有的长度：`salt ‖ digest`。 */
export const SECRET_LENGTH: number = SALT_LENGTH + DIGEST_LENGTH;

/** 只接受 ASCII 十进制数字：长度、字符区间都必须在进任何存储之前定死。 */
export function isAsciiDigits(pin: string): boolean {
  if (pin.length !== PIN_LENGTH) {
    return false;
  }
  for (let i: number = 0; i < pin.length; i = i + 1) {
    const c: number = pin.charCodeAt(i);
    if (c < 48 || c > 57) {
      return false;
    }
  }
  return true;
}

/** 合法返回 `null`；否则回一条 parameter 错误（错误文案里没有 PIN 本身）。 */
export function validatePin(pin: string): AppError | null {
  if (!isAsciiDigits(pin)) {
    return AppErrors.parameter('invalid', 'pin', `pin must be ${PIN_LENGTH} ASCII digits`);
  }
  return null;
}

/**
 * PIN 的字节表示。ASCII 数字的 UTF-8 编码等于其码点，所以这里不需要 `util.TextEncoder`；
 * 前提是调用方已经过 `validatePin` —— 非 ASCII 输入进不到这一步。
 */
export function pinBytes(pin: string): Uint8Array {
  const bytes: Uint8Array = new Uint8Array(PIN_LENGTH);
  for (let i: number = 0; i < PIN_LENGTH; i = i + 1) {
    bytes[i] = pin.charCodeAt(i);
  }
  return bytes;
}

/** 拼接成落盘字节。长度不对直接抛给调用方的断言之外没有意义，所以回 `null`。 */
export function packSecret(salt: Uint8Array, digest: Uint8Array): Uint8Array | null {
  if (salt.length !== SALT_LENGTH || digest.length !== DIGEST_LENGTH) {
    return null;
  }
  const secret: Uint8Array = new Uint8Array(SECRET_LENGTH);
  secret.set(salt, 0);
  secret.set(digest, SALT_LENGTH);
  return secret;
}

/** 从落盘字节取回的盐与摘要。 */
export class PasscodeSecret {
  readonly salt: Uint8Array;
  readonly digest: Uint8Array;

  constructor(salt: Uint8Array, digest: Uint8Array) {
    this.salt = salt;
    this.digest = digest;
  }
}

/**
 * 拆包：长度不是 48 就是这条资产坏了（被截断、被别的实现写过）。
 * 这里必须成一条可诊断的错误，而不是回 `false` —— 静默「密码错误」会让用户
 * 永远猜不到真正坏掉的是数据。
 */
export function unpackSecret(stored: Uint8Array): Result<PasscodeSecret, AppError> {
  if (stored.length !== SECRET_LENGTH) {
    return err<PasscodeSecret, AppError>(AppErrors.internal(
      'passcode-secret-corrupt',
      `stored secret has unexpected length ${stored.length}`
    ));
  }
  return ok<PasscodeSecret, AppError>(new PasscodeSecret(
    stored.slice(0, SALT_LENGTH),
    stored.slice(SALT_LENGTH)
  ));
}

/** 恒定长度比较：不相等时也不提前返回，避免按前缀命中与否测出摘要字节。 */
export function constantTimeEquals(a: Uint8Array, b: Uint8Array): boolean {
  if (a.length !== b.length) {
    return false;
  }
  let diff: number = 0;
  for (let i: number = 0; i < a.length; i = i + 1) {
    diff = diff | (a[i] ^ b[i]);
  }
  return diff === 0;
}
