/**
 * platform/keystore — PasscodeStorePort 的 HarmonyOS 实现（APPLOCK-101）。
 *
 * ## 存的是什么
 *
 * 不存 PIN，也不单独存哈希，存的是一条 `salt ‖ sha256(salt ‖ pin)` 的字节：
 * - 盐 16 字节，来自 `SecureRandomPort`（硬件随机池），每次 `set` 重新生成；
 * - 摘要 32 字节，`@kit.CryptoArchitectureKit` 的 SHA-256；
 * - 整条字节交给 `SecureKeyStorePort`（Asset Store，`ACCESSIBILITY=DEVICE_UNLOCKED`、
 *   `SYNC_TYPE=NEVER`），明文由系统安全服务加密托管。
 *
 * 这是 Android 侧 `Passcode.java` 的「SharedPreferences + 双重 MD5 + 固定盐」的替换件：
 * MD5 + 全局固定盐对 4 位数字这种 10⁴ 空间的秘密值等于没加盐（一次查表全解），
 * 所以本端换成一事一盐的 SHA-256，并把存放位置从可读的偏好文件换进安全存储。
 *
 * ## 为什么 `set` 里必须读回再验一次
 *
 * 派生实现只要有一次「写进去的和读出来的对不上」（编码截断、覆盖失败、资产被系统清理），
 * 用户就会在下一次冷启动被自己的密码锁死。本仓不允许卸载重装清数据（TDLib 会话要短信码），
 * 这个损失不可恢复。所以 `set` 是原子的：写完立刻读回、用同一个 PIN 重新派生并比对，
 * 对不上就抹掉刚写入的值、把状态回成「未设置」，并回 `err` —— 宁可设置失败让用户重试，
 * 也不能留下一个解不开的锁。
 *
 * ## 本文件与 core/PasscodeSecret.ets 的分界
 *
 * 长度、字符集、`salt ‖ digest` 的打包拆包、恒定时间比对全部在 `core/PasscodeSecret.ets`
 * 里（无 Kit、有单测）；本类只剩「取随机盐」「算摘要」「读写资产」三件必须真机的动作。
 * 分界的意义是：CI 能跑的那一半负责判据，跑不动的那一半只负责跟系统打交道。
 *
 * ## 保密边界
 *
 * 本类不提供任何把盐或摘要读出来的方法（端口语义）；错误对象里也不出现 PIN、盐、摘要，
 * `cause` 只带系统错误码与文案。
 */

import { cryptoFramework } from '@kit.CryptoArchitectureKit';
import { Result, AppError, ok, err, AppErrors } from '@tgx/core-common';
import {
  PasscodeStorePort,
  SecureKeyStorePort,
  SecureRandomPort
} from '@tgx/platform-ports';
import {
  DIGEST_LENGTH,
  PIN_LENGTH,
  SALT_LENGTH,
  SECRET_LENGTH,
  PasscodeSecret,
  constantTimeEquals,
  packSecret,
  pinBytes,
  unpackSecret,
  validatePin
} from './core/PasscodeSecret';

/** 安全存储中的别名（唯一一条应用锁资产）。 */
const PASSCODE_ALIAS: string = 'applock.passcode';

/**
 * 取 `Result` 里的值。ArkTS 不会在 `if (x.err) return` 之后收窄判别联合（AGENTS.md 第 3.1 条），
 * 所以拆值只能走 `fold`：成功回 `value`，失败回 `null`。
 * 调用方必须先排掉 `err` 分支再调这里，否则失败会被当成「值为 null」。
 */
function valueOr<T, E>(res: Result<T, E>): T | null {
  return res.fold<T | null>(
    (value: T): T | null => value,
    (_error: E): null => null
  );
}

export class HarmonyPasscodeStore implements PasscodeStorePort {
  private keyStore: SecureKeyStorePort;
  private random: SecureRandomPort;

  constructor(keyStore: SecureKeyStorePort, random: SecureRandomPort) {
    this.keyStore = keyStore;
    this.random = random;
  }

  async isSet(): Promise<Result<boolean, AppError>> {
    const got: Result<Uint8Array | null, AppError> = await this.keyStore.get(PASSCODE_ALIAS);
    if (got.err) {
      return err<boolean, AppError>(got.error);
    }
    return ok<boolean, AppError>(valueOr(got) !== null);
  }

  async set(pin: string): Promise<Result<void, AppError>> {
    const pinError: AppError | null = validatePin(pin);
    if (pinError !== null) {
      return err<void, AppError>(pinError);
    }

    const saltResult: Result<Uint8Array, AppError> = await this.random.generateRandom(SALT_LENGTH);
    if (saltResult.err) {
      return err<void, AppError>(saltResult.error);
    }
    const salt: Uint8Array | null = valueOr(saltResult);
    if (salt === null) {
      return err<void, AppError>(AppErrors.internal('random-empty', 'secure random returned no bytes'));
    }

    const secretResult: Result<Uint8Array, AppError> = await this.derive(salt, pin);
    if (secretResult.err) {
      return err<void, AppError>(secretResult.error);
    }
    const digest: Uint8Array | null = valueOr(secretResult);
    if (digest === null) {
      return err<void, AppError>(AppErrors.internal('digest-empty', 'sha256 returned no bytes'));
    }
    // 落盘的是 `salt ‖ digest`：`matches()` 只能从这一条资产里取回盐，
    // 少了前缀就等于每次校验都在拿随机盐和旧摘要比，永远对不上。
    const secret: Uint8Array | null = packSecret(salt, digest);
    if (secret === null) {
      return err<void, AppError>(AppErrors.internal(
        'passcode-secret-length',
        `salt+digest do not fill exactly ${SECRET_LENGTH} bytes`
      ));
    }

    const written: Result<void, AppError> = await this.keyStore.put(PASSCODE_ALIAS, secret);
    if (written.err) {
      return err<void, AppError>(written.error);
    }

    const verify: Result<boolean, AppError> = await this.matches(pin);
    if (verify.err) {
      await this.wipe();
      return err<void, AppError>(verify.error);
    }
    if (valueOr(verify) !== true) {
      // 写进去的东西读回来对不上：这台设备上的密码会把用户永久锁在外面，
      // 所以宁可回滚成「未设置」也不留半个坏秘密。
      await this.wipe();
      return err<void, AppError>(AppErrors.internal(
        'passcode-roundtrip-mismatch',
        'passcode write did not round-trip; rolled back to unset'
      ));
    }
    return ok<void, AppError>(undefined);
  }

  async matches(pin: string): Promise<Result<boolean, AppError>> {
    const pinError: AppError | null = validatePin(pin);
    if (pinError !== null) {
      return err<boolean, AppError>(pinError);
    }

    const got: Result<Uint8Array | null, AppError> = await this.keyStore.get(PASSCODE_ALIAS);
    if (got.err) {
      return err<boolean, AppError>(got.error);
    }
    const stored: Uint8Array | null = valueOr(got);
    if (stored === null) {
      return ok<boolean, AppError>(false);
    }

    const unpacked: Result<PasscodeSecret, AppError> = unpackSecret(stored);
    if (unpacked.err) {
      return err<boolean, AppError>(unpacked.error);
    }
    const secret: PasscodeSecret | null = valueOr(unpacked);
    if (secret === null) {
      return err<boolean, AppError>(AppErrors.internal(
        'passcode-secret-empty',
        'stored secret unpacked to nothing'
      ));
    }

    const derivedResult: Result<Uint8Array, AppError> = await this.derive(secret.salt, pin);
    if (derivedResult.err) {
      return err<boolean, AppError>(derivedResult.error);
    }
    const derived: Uint8Array | null = valueOr(derivedResult);
    if (derived === null) {
      return err<boolean, AppError>(AppErrors.internal('digest-empty', 'sha256 returned no bytes'));
    }
    return ok<boolean, AppError>(constantTimeEquals(secret.digest, derived));
  }

  async wipe(): Promise<Result<void, AppError>> {
    return await this.keyStore.remove(PASSCODE_ALIAS);
  }

  /** `sha256(salt ‖ utf8(pin))`，返回 32 字节摘要。 */
  private async derive(salt: Uint8Array, pin: string): Promise<Result<Uint8Array, AppError>> {
    const input: Uint8Array = new Uint8Array(salt.length + PIN_LENGTH);
    input.set(salt, 0);
    input.set(pinBytes(pin), salt.length);

    try {
      const md: cryptoFramework.Md = cryptoFramework.createMd('SHA256');
      await md.update({ data: input });
      const output: cryptoFramework.DataBlob = await md.digest();
      if (output.data.length !== DIGEST_LENGTH) {
        return err<Uint8Array, AppError>(AppErrors.internal(
          'passcode-digest-length',
          `sha256 returned ${output.data.length} bytes`
        ));
      }
      return ok<Uint8Array, AppError>(output.data);
    } catch (e) {
      const message: string = e instanceof Error ? e.message : String(e);
      return err<Uint8Array, AppError>(AppErrors.platform(
        -1,
        'failed to derive passcode digest',
        false,
        undefined,
        message
      ));
    }
  }
}
