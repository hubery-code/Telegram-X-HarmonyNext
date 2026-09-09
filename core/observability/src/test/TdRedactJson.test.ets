import { describe, it, expect } from '@ohos/hypium';
import { redactTdJson } from '@tgx/td-api-generated/src/main/ets/redaction/TdRedact';
import { TdJsonRaw } from '@tgx/td-api-generated/src/main/ets/runtime/TdJson';
import { FIXTURES, ALL_SECRETS } from './SensitiveFixtures';
import { jsonObj, jsonArr } from './TestJson';

/** 断言输出不含任何敏感假值（验收线：secret fixtures 100% 拦截）。 */
function assertNoSecrets(output: string): void {
  for (const secret of ALL_SECRETS) {
    expect(output.indexOf(secret) >= 0).assertFalse();
  }
}

function wire(record: Record<string, TdJsonRaw>): string {
  return JSON.stringify(record);
}

export default function tdRedactJsonTest() {
  describe('TdRedactJsonTest', () => {

    // —— 认证链路 ——
    it('phoneNumberRequest_isMasked', 0, () => {
      const rec = jsonObj();
      rec['@type'] = 'setAuthenticationPhoneNumber';
      rec['phone_number'] = FIXTURES.phoneNumber;
      const out: string = redactTdJson(wire(rec));
      assertNoSecrets(out);
      expect(out.indexOf(FIXTURES.phoneMasked) >= 0).assertTrue();
    });

    it('authCode_isFullyRedacted', 0, () => {
      const rec = jsonObj();
      rec['@type'] = 'checkAuthenticationCode';
      rec['code'] = FIXTURES.authCode;
      const out: string = redactTdJson(wire(rec));
      assertNoSecrets(out);
      expect(out.indexOf(`"code":"${FIXTURES.redacted}"`) >= 0).assertTrue();
    });

    it('authPassword_isFullyRedacted', 0, () => {
      const rec = jsonObj();
      rec['@type'] = 'checkAuthenticationPassword';
      rec['password'] = FIXTURES.password;
      const out: string = redactTdJson(wire(rec));
      assertNoSecrets(out);
      expect(out.indexOf(FIXTURES.redacted) >= 0).assertTrue();
    });

    it('setPassword_oldNewRedacted_recoveryEmailMasked', 0, () => {
      const rec = jsonObj();
      rec['@type'] = 'setPassword';
      rec['old_password'] = FIXTURES.oldPassword;
      rec['new_password'] = FIXTURES.newPassword;
      rec['new_hint'] = FIXTURES.passwordHint;
      rec['set_recovery_email_address'] = true;
      rec['new_recovery_email_address'] = FIXTURES.emailAddress;
      const out: string = redactTdJson(wire(rec));
      assertNoSecrets(out);
      expect(out.indexOf(FIXTURES.redacted) >= 0).assertTrue();
    });

    it('premiumGiftCodeRequest_isRedacted', 0, () => {
      const rec = jsonObj();
      rec['@type'] = 'checkPremiumGiftCode';
      rec['code'] = FIXTURES.giftCode;
      const out: string = redactTdJson(wire(rec));
      assertNoSecrets(out);
      expect(out.indexOf(FIXTURES.redacted) >= 0).assertTrue();
    });

    // —— 代理凭据 ——
    it('proxySocks5_usernamePasswordRedacted', 0, () => {
      const rec = jsonObj();
      rec['@type'] = 'proxyTypeSocks5';
      rec['username'] = FIXTURES.proxyUsername;
      rec['password'] = FIXTURES.proxyPassword;
      rec['http_only'] = false;
      const out: string = redactTdJson(wire(rec));
      assertNoSecrets(out);
      // 普通 username 在别处是公开标识，但代理构造器上是凭据
      expect(out.indexOf(FIXTURES.proxyUsername) >= 0).assertFalse();
      expect(out.indexOf(FIXTURES.redacted) >= 0).assertTrue();
    });

    it('proxyMtproto_secretRedacted', 0, () => {
      const rec = jsonObj();
      rec['@type'] = 'proxyTypeMtproto';
      rec['secret'] = FIXTURES.proxySecret;
      const out: string = redactTdJson(wire(rec));
      assertNoSecrets(out);
    });

    // —— 初始化参数 ——
    it('tdlibParameters_apiHashRedacted_apiIdZeroed_dbKeyRedacted', 0, () => {
      const rec = jsonObj();
      rec['@type'] = 'setTdlibParameters';
      rec['api_id'] = 12345678;
      rec['api_hash'] = FIXTURES.apiHash;
      rec['database_encryption_key'] = FIXTURES.dbEncryptionKey;
      rec['use_test_dc'] = false;
      rec['files_directory'] = '/fake/path';
      const out: string = redactTdJson(wire(rec));
      assertNoSecrets(out);
      expect(out.indexOf('"api_id":0') >= 0).assertTrue();
      expect(out.indexOf('"use_test_dc":false') >= 0).assertTrue();
      expect(out.indexOf('/fake/path') >= 0).assertTrue();
    });

    it('databaseEncryptionKeyRequest_isRedacted', 0, () => {
      const rec = jsonObj();
      rec['@type'] = 'setDatabaseEncryptionKey';
      rec['new_encryption_key'] = FIXTURES.dbEncryptionKey;
      const out: string = redactTdJson(wire(rec));
      assertNoSecrets(out);
    });

    // —— PII ——
    it('session_ipAddressMasked', 0, () => {
      const rec = jsonObj();
      rec['@type'] = 'session';
      rec['id'] = '42';
      rec['ip_address'] = FIXTURES.ipAddress;
      rec['application_name'] = 'FakeApp';
      const out: string = redactTdJson(wire(rec));
      assertNoSecrets(out);
      expect(out.indexOf('"id":"42"') >= 0).assertTrue();
      expect(out.indexOf('FakeApp') >= 0).assertTrue();
    });

    it('user_nameMasked_phoneMasked_usernameKept', 0, () => {
      const rec = jsonObj();
      rec['@type'] = 'user';
      rec['first_name'] = FIXTURES.firstName;
      rec['last_name'] = FIXTURES.lastName;
      rec['phone_number'] = FIXTURES.phoneNumber;
      rec['username'] = 'public_handle';
      const out: string = redactTdJson(wire(rec));
      assertNoSecrets(out);
      expect(out.indexOf('public_handle') >= 0).assertTrue();
    });

    it('orderInfo_shippingAddressSubtreeRedacted_emailMasked', 0, () => {
      const address = jsonObj();
      address['@type'] = 'address';
      address['country_code'] = 'CN';
      address['street_line1'] = 'Fake Street 1';
      const rec = jsonObj();
      rec['@type'] = 'orderInfo';
      rec['name'] = 'Buyer Fake';
      rec['email_address'] = FIXTURES.emailAddress;
      rec['shipping_address'] = address;
      const out: string = redactTdJson(wire(rec));
      assertNoSecrets(out);
      // 整棵收货地址子树被替换
      expect(out.indexOf('Fake Street 1') >= 0).assertFalse();
      expect(out.indexOf('Buyer Fake') >= 0).assertTrue();
    });

    // —— keep 决策（反向断言：非敏感字段不得被误伤）——
    it('error_codeIsErrorCode_notAuthCode_kept', 0, () => {
      const rec = jsonObj();
      rec['@type'] = 'error';
      rec['code'] = 400;
      rec['message'] = 'fake error text';
      const out: string = redactTdJson(wire(rec));
      expect(out.indexOf('"code":400') >= 0).assertTrue();
    });

    it('boolFlags_hasPasswordIsNotSecret_kept', 0, () => {
      const rec = jsonObj();
      rec['@type'] = 'passwordState';
      rec['has_password'] = true;
      rec['password_hint'] = FIXTURES.passwordHint;
      rec['has_recovery_email_address'] = false;
      const out: string = redactTdJson(wire(rec));
      assertNoSecrets(out);
      expect(out.indexOf('"has_password":true') >= 0).assertTrue();
      expect(out.indexOf('"has_recovery_email_address":false') >= 0).assertTrue();
    });

    it('languagePackKeyIsNotCryptoKey_kept', 0, () => {
      const value = jsonObj();
      value['@type'] = 'languagePackStringValueOrdinary';
      value['value'] = 'hello';
      const rec = jsonObj();
      rec['@type'] = 'languagePackString';
      rec['key'] = 'app.fakeKey';
      rec['value'] = value;
      const out: string = redactTdJson(wire(rec));
      expect(out.indexOf('app.fakeKey') >= 0).assertTrue();
      expect(out.indexOf('hello') >= 0).assertTrue();
    });

    it('pushToken_isMasked', 0, () => {
      const rec = jsonObj();
      rec['@type'] = 'deviceTokenApplePush';
      rec['device_token'] = FIXTURES.deviceToken;
      rec['is_app_sandbox'] = true;
      const out: string = redactTdJson(wire(rec));
      assertNoSecrets(out);
      expect(out.indexOf('"is_app_sandbox":true') >= 0).assertTrue();
    });

    // —— 嵌套与 @extra ——
    it('nestedKnownConstructor_insideParent_getsOwnRules', 0, () => {
      const state = jsonObj();
      state['@type'] = 'authorizationStateWaitPassword';
      state['password_hint'] = FIXTURES.passwordHint;
      state['recovery_email_address_pattern'] = 'f***@e***';
      const rec = jsonObj();
      rec['@type'] = 'updateAuthorizationState';
      rec['authorization_state'] = state;
      const out: string = redactTdJson(wire(rec));
      assertNoSecrets(out);
      expect(out.indexOf('authorizationStateWaitPassword') >= 0).assertTrue();
    });

    it('extraField_isMasked', 0, () => {
      const rec = jsonObj();
      rec['@type'] = 'checkAuthenticationCode';
      rec['code'] = FIXTURES.authCode;
      rec['@extra'] = FIXTURES.extra;
      const out: string = redactTdJson(wire(rec));
      assertNoSecrets(out);
    });

    it('vectorOfKnownConstructors_eachElementRedacted', 0, () => {
      const optionValue = jsonObj();
      optionValue['@type'] = 'optionValueString';
      optionValue['value'] = 'keepme';
      const s1 = jsonObj();
      s1['@type'] = 'session';
      s1['id'] = '1';
      s1['ip_address'] = FIXTURES.ipAddress;
      const s2 = jsonObj();
      s2['@type'] = 'session';
      s2['id'] = '2';
      s2['ip_address'] = '198.51.100.23';
      const sessions = jsonArr();
      sessions.push(s1);
      sessions.push(s2);
      const rec = jsonObj();
      rec['@type'] = 'updateOption';
      rec['name'] = 'my_id';
      rec['value'] = optionValue;
      rec['sessions'] = sessions;
      const out: string = redactTdJson(wire(rec));
      assertNoSecrets(out);
      expect(out.indexOf('198.51.100.23') >= 0).assertFalse();
      expect(out.indexOf('keepme') >= 0).assertTrue();
    });

    // —— 未知 @type 保守兜底 ——
    it('unknownType_suspiciousFieldsConservativelyMasked', 0, () => {
      const rec = jsonObj();
      rec['@type'] = 'futureConstructorFromNewTdlib';
      rec['phone_number'] = FIXTURES.phoneNumber;
      rec['access_token'] = FIXTURES.token;
      rec['api_hash'] = FIXTURES.apiHash;
      rec['database_key'] = FIXTURES.dbEncryptionKey;
      rec['session_data'] = 'whatever-session-payload';
      rec['plain_count'] = 7;
      rec['enabled'] = true;
      const out: string = redactTdJson(wire(rec));
      assertNoSecrets(out);
      // 不敏感字段保留
      expect(out.indexOf('"plain_count":7') >= 0).assertTrue();
      expect(out.indexOf('"enabled":true') >= 0).assertTrue();
      expect(out.indexOf(FIXTURES.redacted) >= 0).assertTrue();
    });

    it('unknownType_nestedObjectWithoutType_usesSubstringFallback', 0, () => {
      const data = jsonObj();
      data['secret_material'] = 'hide-me-please';
      const meta = jsonObj();
      meta['label'] = 'visible';
      const rec = jsonObj();
      rec['@type'] = 'futureThing';
      rec['data'] = data;
      rec['meta'] = meta;
      const out: string = redactTdJson(wire(rec));
      expect(out.indexOf('hide-me-please') >= 0).assertFalse();
      expect(out.indexOf('visible') >= 0).assertTrue();
    });

    it('unknownType_keptFieldsWithKnownNestedType_routedByNestedType', 0, () => {
      const owner = jsonObj();
      owner['@type'] = 'user';
      owner['first_name'] = FIXTURES.firstName;
      owner['username'] = 'public_handle_2';
      const rec = jsonObj();
      rec['@type'] = 'futureThing';
      rec['owner'] = owner;
      const out: string = redactTdJson(wire(rec));
      assertNoSecrets(out);
      expect(out.indexOf('public_handle_2') >= 0).assertTrue();
    });

    // —— 永不抛错 ——
    it('invalidJson_returnsPlaceholderWithoutThrowing', 0, () => {
      const out: string = redactTdJson('{"@type":"user","phone_number":"+861390123');
      expect(out).assertEqual(FIXTURES.redacted);
    });

    it('nonObjectTopLevel_returnsPlaceholder', 0, () => {
      expect(redactTdJson('"just a string"')).assertEqual(FIXTURES.redacted);
      expect(redactTdJson('[1,2,3]')).assertEqual(FIXTURES.redacted);
      expect(redactTdJson('42')).assertEqual(FIXTURES.redacted);
    });

    it('nullInput_returnsPlaceholder', 0, () => {
      expect(redactTdJson('null')).assertEqual(FIXTURES.redacted);
    });
  });
}
