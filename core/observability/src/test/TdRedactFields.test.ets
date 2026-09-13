import { describe, it, expect } from '@ohos/hypium';
import {
  TdObject,
  TdJsonRaw,
  TdUnknownObject,
  SetAuthenticationPhoneNumber,
  CheckAuthenticationCode,
  encodeSetAuthenticationPhoneNumber,
  encodeCheckAuthenticationCode,
  ProxyTypeSocks5,
  User,
  decodeTdObject,
} from '@tgx/core-td-api-generated';
import { redactFields, redactTdJson } from '@tgx/core-td-api-generated/src/main/ets/redaction/TdRedact';
import { FIXTURES, ALL_SECRETS } from './SensitiveFixtures';
import { jsonObj } from './TestJson';

function assertNoSecrets(output: string): void {
  for (const secret of ALL_SECRETS) {
    expect(output.indexOf(secret) >= 0).assertFalse();
  }
}

export default function tdRedactFieldsTest() {
  describe('TdRedactFieldsTest', () => {

    it('userDto_nameMasked_phoneMasked', 0, () => {
      const user: User = new User();
      user.first_name = FIXTURES.firstName;
      user.last_name = FIXTURES.lastName;
      user.phone_number = FIXTURES.phoneNumber;
      const redacted: TdObject = redactFields(user);
      const json: string = JSON.stringify(redacted);
      assertNoSecrets(json);
      expect(json.indexOf(FIXTURES.phoneMasked) >= 0).assertTrue();
    });

    it('proxySocks5Dto_credentialsRedacted_originalUntouched', 0, () => {
      const proxy: ProxyTypeSocks5 = new ProxyTypeSocks5();
      proxy.username = FIXTURES.proxyUsername;
      proxy.password = FIXTURES.proxyPassword;
      const redacted: TdObject = redactFields(proxy);
      const json: string = JSON.stringify(redacted);
      assertNoSecrets(json);
      // 深拷贝：原对象不被修改
      expect(proxy.username).assertEqual(FIXTURES.proxyUsername);
      expect(proxy.password).assertEqual(FIXTURES.proxyPassword);
    });

    it('requestDto_viaEncodeThenRedactTdJson_isRedacted', 0, () => {
      // redactFields 面向 TdObject；请求（TdFunction）走 encode -> redactTdJson。
      const req: SetAuthenticationPhoneNumber = new SetAuthenticationPhoneNumber();
      req.phone_number = FIXTURES.phoneNumber;
      const wire: Record<string, TdJsonRaw> = encodeSetAuthenticationPhoneNumber(req);
      const out: string = redactTdJson(JSON.stringify(wire));
      assertNoSecrets(out);
      expect(out.indexOf(FIXTURES.phoneMasked) >= 0).assertTrue();
    });

    it('requestDto_authCodeRedacted', 0, () => {
      const req: CheckAuthenticationCode = new CheckAuthenticationCode();
      req.code = FIXTURES.authCode;
      req.extra = FIXTURES.extra;
      const wire: Record<string, TdJsonRaw> = encodeCheckAuthenticationCode(req);
      const out: string = redactTdJson(JSON.stringify(wire));
      assertNoSecrets(out);
      expect(out.indexOf(FIXTURES.redacted) >= 0).assertTrue();
    });

    it('decodedDto_roundTripsThroughRedaction', 0, () => {
      const rec = jsonObj();
      rec['@type'] = 'user';
      rec['first_name'] = FIXTURES.firstName;
      rec['phone_number'] = FIXTURES.phoneNumber;
      const decoded: TdObject | null = decodeTdObject(JSON.parse(JSON.stringify(rec)));
      expect(decoded === null).assertFalse();
      if (decoded === null) {
        return;
      }
      const redacted: TdObject = redactFields(decoded);
      const json: string = JSON.stringify(redacted);
      assertNoSecrets(json);
      // @type 保留
      expect(json.indexOf('"type":"user"') >= 0).assertTrue();
      expect(json.indexOf(FIXTURES.phoneMasked) >= 0).assertTrue();
    });

    it('unknownObjectDto_suspiciousRawFieldsRedacted', 0, () => {
      const raw = jsonObj();
      raw['token'] = FIXTURES.token;
      raw['note'] = 'harmless note';
      const unknown: TdUnknownObject = new TdUnknownObject('brandNewConstructor', raw);
      const redacted: TdObject = redactFields(unknown);
      const json: string = JSON.stringify(redacted);
      assertNoSecrets(json);
      expect(json.indexOf('harmless note') >= 0).assertTrue();
    });

    it('errorDto_codeKept', 0, () => {
      const rec = jsonObj();
      rec['@type'] = 'error';
      rec['code'] = 429;
      rec['message'] = 'x';
      const decoded: TdObject | null = decodeTdObject(JSON.parse(JSON.stringify(rec)));
      expect(decoded === null).assertFalse();
      if (decoded === null) {
        return;
      }
      const redacted: TdObject = redactFields(decoded);
      const json: string = JSON.stringify(redacted);
      expect(json.indexOf('"code":429') >= 0).assertTrue();
    });
  });
}
