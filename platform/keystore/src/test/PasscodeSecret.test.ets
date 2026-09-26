/**
 * platform/keystore — `core/PasscodeSecret.ets` 单元测试（APPLOCK-102）。
 *
 * 这个套件是 platform_keystore 第一次进 CI：在此之前本模块整体挂在
 * `test_all_modules.py` 的豁免名单上，理由是「要真实安全服务」—— 那句话只对
 * `asset` / `cryptoFramework` 成立。把不含 Kit 的判据拆进 `core/` 之后，
 * 「锁死用户」最常见的那几种写法（长度不校验、打包顺序反了、比对提前返回）
 * 就全部可以在本地被测到。
 *
 * 守住的回归：
 * 1. 进存储之前的输入合法性：只接受恰好 4 位 ASCII 数字，长度对但字符不对也拦；
 * 2. `salt ‖ digest` 的**顺序**与长度：round-trip 取回的盐必须是写进去的那一份；
 * 3. 坏数据必须是错误而不是「密码不对」：长度不是 48 的资产要成一条可诊断的 err；
 * 4. 比对不因位置提前失败（恒定时间），且错误文案里不出现秘密值。
 */

import { describe, it, expect } from '@ohos/hypium';
import { AppError, Result } from '@tgx/core-common';
import {
  DIGEST_LENGTH,
  PIN_LENGTH,
  SALT_LENGTH,
  SECRET_LENGTH,
  PasscodeSecret,
  constantTimeEquals,
  isAsciiDigits,
  packSecret,
  pinBytes,
  unpackSecret,
  validatePin
} from '../main/ets/core/PasscodeSecret';

const PIN: string = '4271';

function saltFilled(): Uint8Array {
  const salt: Uint8Array = new Uint8Array(SALT_LENGTH);
  for (let i = 0; i < SALT_LENGTH; i = i + 1) {
    salt[i] = 16 + i;
  }
  return salt;
}

function digestFilled(): Uint8Array {
  const digest: Uint8Array = new Uint8Array(DIGEST_LENGTH);
  for (let i = 0; i < DIGEST_LENGTH; i = i + 1) {
    digest[i] = 200 - i;
  }
  return digest;
}

/** 错误对象的 kind 判别式可读，其余字段要走 fold/序列化，所以断言文案统一查这里。 */
function errorText(error: AppError): string {
  return JSON.stringify(error);
}

export default function passcodeSecretTest(): void {
  describe('PasscodeSecretTest', () => {

    it('secretLayoutIsSaltThenDigest', 0, () => {
      // 48 这个数字一旦变化，盘上已有的资产全部作废，用户会被锁在外面 —— 所以钉死。
      expect(PIN_LENGTH).assertEqual(4);
      expect(SALT_LENGTH).assertEqual(16);
      expect(DIGEST_LENGTH).assertEqual(32);
      expect(SECRET_LENGTH).assertEqual(48);
    });

    it('pinValidationRejectsWrongShape', 0, () => {
      expect(isAsciiDigits(PIN)).assertTrue();
      expect(isAsciiDigits('0000')).assertTrue();
      expect(validatePin(PIN) === null).assertTrue();

      // 长度
      expect(isAsciiDigits('')).assertFalse();
      expect(isAsciiDigits('123')).assertFalse();
      expect(isAsciiDigits('12345')).assertFalse();
      // 长度对但字符不对：全角数字、空格、符号、十六进制字母都必须拦下。
      expect(isAsciiDigits('１２３４')).assertFalse();
      expect(isAsciiDigits('12 4')).assertFalse();
      expect(isAsciiDigits('12-4')).assertFalse();
      expect(isAsciiDigits('abcd')).assertFalse();
      expect(validatePin('12 4') !== null).assertTrue();
    });

    it('pinBytesAreTheAsciiCodes', 0, () => {
      // `derive` 拼进摘要的字节必须是 '4','2','7','1' 本身；
      // 写成 UTF-16 码元或漏一位，都会让「同一个 PIN 两次派生不同摘要」，永远校验不过。
      const bytes: Uint8Array = pinBytes(PIN);
      expect(bytes.length).assertEqual(PIN_LENGTH);
      expect(bytes[0]).assertEqual(52);
      expect(bytes[1]).assertEqual(50);
      expect(bytes[2]).assertEqual(55);
      expect(bytes[3]).assertEqual(49);
    });

    it('packUnpackRoundTripsBothHalves', 0, () => {
      const salt: Uint8Array = saltFilled();
      const digest: Uint8Array = digestFilled();
      const packed: Uint8Array | null = packSecret(salt, digest);
      expect(packed !== null).assertTrue();
      if (packed === null) {
        return;
      }
      expect(packed.length).assertEqual(SECRET_LENGTH);

      const unpacked: Result<PasscodeSecret, AppError> = unpackSecret(packed);
      expect(unpacked.ok).assertTrue();
      const got: PasscodeSecret | null = unpacked.fold<PasscodeSecret | null>(
        (value: PasscodeSecret): PasscodeSecret | null => value,
        (_error: AppError): null => null
      );
      expect(got !== null).assertTrue();
      if (got === null) {
        return;
      }
      // 顺序反了会在这里露出来：盐在前、摘要在后。
      expect(constantTimeEquals(got.salt, salt)).assertTrue();
      expect(constantTimeEquals(got.digest, digest)).assertTrue();
    });

    it('packRefusesWrongSideLengths', 0, () => {
      const salt: Uint8Array = saltFilled();
      const digest: Uint8Array = digestFilled();
      expect(packSecret(salt.slice(0, 15), digest) === null).assertTrue();
      expect(packSecret(salt, digest.slice(0, 31)) === null).assertTrue();
      expect(packSecret(salt, new Uint8Array(DIGEST_LENGTH + 1)) === null).assertTrue();
    });

    it('corruptLengthIsAnErrorNotAMismatch', 0, () => {
      // 「密码错误」和「数据坏了」必须是两种结果：前者让用户继续试，后者要能诊断。
      const packed: Uint8Array | null = packSecret(saltFilled(), digestFilled());
      expect(packed !== null).assertTrue();
      if (packed === null) {
        return;
      }
      const tooShort: Uint8Array = packed.slice(0, SECRET_LENGTH - 1);
      const shortRes: Result<PasscodeSecret, AppError> = unpackSecret(tooShort);
      expect(shortRes.err).assertTrue();
      if (shortRes.err) {
        const error: AppError = shortRes.error;
        expect(error.kind).assertEqual('internal');
        const text: string = errorText(error);
        expect(text.indexOf('passcode-secret-corrupt') >= 0).assertTrue();
        // 文案里带的是长度这个非秘密值，不带任何字节内容。
        expect(text.indexOf('47') >= 0).assertTrue();
      }

      expect(unpackSecret(new Uint8Array(0)).err).assertTrue();
      expect(unpackSecret(new Uint8Array(SECRET_LENGTH + 1)).err).assertTrue();
    });

    it('constantTimeCompareCoversEveryPosition', 0, () => {
      const base: Uint8Array = digestFilled();
      expect(constantTimeEquals(base, base.slice())).assertTrue();
      // 逐位翻转：每一位都必须被读到，且结果都是 false。
      for (let i = 0; i < base.length; i = i + 1) {
        const other: Uint8Array = base.slice();
        other[i] = base[i] ^ 0xff;
        expect(constantTimeEquals(base, other)).assertFalse();
      }
      expect(constantTimeEquals(base, base.slice(0, base.length - 1))).assertFalse();
      expect(constantTimeEquals(new Uint8Array(0), new Uint8Array(0))).assertTrue();
    });

    it('validationErrorsCarryNoPinBytes', 0, () => {
      const error: AppError | null = validatePin('12 4');
      expect(error !== null).assertTrue();
      if (error === null) {
        return;
      }
      expect(errorText(error).indexOf('12 4') < 0).assertTrue();
    });
  });
}
