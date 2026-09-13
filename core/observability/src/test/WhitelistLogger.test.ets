import { describe, it, expect } from '@ohos/hypium';
import { AppErrors } from '@tgx/core-common';
import { UpdateOption } from '@tgx/core-td-api-generated';
import { TdJsonRaw } from '@tgx/core-td-api-generated/src/main/ets/runtime/TdJson';
import { Logger, DEFAULT_TD_LOG_WHITELIST, filterByWhitelist, TdLogWhitelist, LogLevel } from '../main/ets/Index';
import { FIXTURES, ALL_SECRETS } from './SensitiveFixtures';
import { jsonObj } from './TestJson';

function assertNoSecrets(output: string): void {
  for (const secret of ALL_SECRETS) {
    expect(output.indexOf(secret) >= 0).assertFalse();
  }
}

interface CollectingLogger {
  logger: Logger;
  lines: string[];
}

/** 收集 sink 输出的 Logger。 */
function collectingLogger(minLevel: LogLevel = 'debug', whitelist?: TdLogWhitelist): CollectingLogger {
  const lines: string[] = [];
  const logger: Logger = new Logger(
    minLevel,
    (level: LogLevel, line: string) => {
      lines.push(line);
    },
    whitelist !== undefined ? whitelist : DEFAULT_TD_LOG_WHITELIST
  );
  const out: CollectingLogger = { logger: logger, lines: lines };
  return out;
}

export default function whitelistLoggerTest() {
  describe('WhitelistLoggerTest', () => {

    // —— ① 白名单日志不含任何敏感值 ——
    it('whitelist_dropsNonWhitelistedTopLevelFields', 0, () => {
      const state = jsonObj();
      state['@type'] = 'authorizationStateWaitCode';
      const rec = jsonObj();
      rec['@type'] = 'updateAuthorizationState';
      rec['authorization_state'] = state;
      // 注入的白名单外字段：即便带了敏感值也根本不会被输出
      rec['phone_number'] = FIXTURES.phoneNumber;
      rec['code'] = FIXTURES.authCode;
      const ctx: CollectingLogger = collectingLogger();
      const line: string | null = ctx.logger.logTdJson('Auth', 'onState', JSON.stringify(rec));
      expect(line === null).assertFalse();
      assertNoSecrets(line as string);
      expect((line as string).indexOf('authorizationStateWaitCode') >= 0).assertTrue();
      expect((line as string).indexOf('phone_number') >= 0).assertFalse();
    });

    it('whitelist_nestedSensitiveInWhitelistedField_redactedBySecondLine', 0, () => {
      const state = jsonObj();
      state['@type'] = 'authorizationStateWaitPassword';
      state['password_hint'] = FIXTURES.passwordHint;
      state['recovery_email_address_pattern'] = 'f***@e***';
      const rec = jsonObj();
      rec['@type'] = 'updateAuthorizationState';
      rec['authorization_state'] = state;
      const ctx: CollectingLogger = collectingLogger();
      const line: string | null = ctx.logger.logTdJson('Auth', 'onState', JSON.stringify(rec));
      expect(line === null).assertFalse();
      assertNoSecrets(line as string);
      // 白名单放行的子树仍被第二道防线细粒度脱敏
      expect((line as string).indexOf('password_hint') >= 0).assertTrue();
      expect((line as string).indexOf(FIXTURES.redacted) >= 0).assertTrue();
    });

    it('whitelist_unknownType_emitsOnlyTypeName', 0, () => {
      const rec = jsonObj();
      rec['@type'] = 'updateFromFutureTdlib';
      rec['phone_number'] = FIXTURES.phoneNumber;
      rec['token'] = FIXTURES.token;
      rec['payload'] = 'anything';
      const ctx: CollectingLogger = collectingLogger();
      const line: string | null = ctx.logger.logTdJson('Td', 'onUpdate', JSON.stringify(rec));
      expect(line === null).assertFalse();
      assertNoSecrets(line as string);
      expect((line as string).indexOf('updateFromFutureTdlib') >= 0).assertTrue();
      expect((line as string).indexOf('payload') >= 0).assertFalse();
    });

    it('whitelist_globalFields_extraMaskedByRedaction', 0, () => {
      const state = jsonObj();
      state['@type'] = 'connectionStateReady';
      const rec = jsonObj();
      rec['@type'] = 'updateConnectionState';
      rec['state'] = state;
      rec['@extra'] = FIXTURES.extra;
      const ctx: CollectingLogger = collectingLogger();
      const line: string | null = ctx.logger.logTdJson('Td', 'onUpdate', JSON.stringify(rec));
      expect(line === null).assertFalse();
      assertNoSecrets(line as string);
      expect((line as string).indexOf('@extra') >= 0).assertTrue();
      expect((line as string).indexOf('connectionStateReady') >= 0).assertTrue();
    });

    it('whitelist_logTdObjectEntry_filtersAndRedacts', 0, () => {
      const update: UpdateOption = new UpdateOption();
      update.name = 'version';
      const ctx: CollectingLogger = collectingLogger();
      const line: string | null = ctx.logger.logTdObject('Td', 'onOption', update);
      expect(line === null).assertFalse();
      expect((line as string).indexOf('version') >= 0).assertTrue();
      expect((line as string).indexOf('updateOption') >= 0).assertTrue();
    });

    it('whitelist_customWhitelist_respected', 0, () => {
      const types: Record<string, readonly string[]> = {};
      types['user'] = ['username'];
      const custom: TdLogWhitelist = { types: types, globalFields: [] };
      const rec = jsonObj();
      rec['@type'] = 'user';
      rec['username'] = 'public_handle';
      rec['first_name'] = FIXTURES.firstName;
      rec['phone_number'] = FIXTURES.phoneNumber;
      const ctx: CollectingLogger = collectingLogger('debug', custom);
      const line: string | null = ctx.logger.logTdJson('User', 'snapshot', JSON.stringify(rec));
      expect(line === null).assertFalse();
      assertNoSecrets(line as string);
      expect((line as string).indexOf('public_handle') >= 0).assertTrue();
      expect((line as string).indexOf('first_name') >= 0).assertFalse();
    });

    // —— level 过滤 ——
    it('levelFilter_debugBelowInfo_isDroppedAndCounted', 0, () => {
      const ctx: CollectingLogger = collectingLogger('info');
      const line: string | null = ctx.logger.debug('T', 'evt', 'ctx');
      expect(line === null).assertTrue();
      expect(ctx.logger.filteredCount).assertEqual(1);
      expect(ctx.lines.length).assertEqual(0);
      const infoLine: string | null = ctx.logger.info('T', 'evt2');
      expect(infoLine === null).assertFalse();
      expect(ctx.lines.length).assertEqual(1);
    });

    // —— toLogString(AppError) 接 core/common ——
    it('logError_usesStableString_messageCauseNeverLeak', 0, () => {
      const ctx: CollectingLogger = collectingLogger();
      const secret = 'secret-in-cause-9x';
      const error = AppErrors.network('dns', `msg ${secret}`, true, undefined, `cause ${secret}`);
      const line: string | null = ctx.logger.logError('Net', error);
      expect(line === null).assertFalse();
      expect((line as string).indexOf(secret) >= 0).assertFalse();
      expect((line as string).indexOf('network/dns/retryable=true') >= 0).assertTrue();
    });

    it('logError_tdlibError_stableMapping', 0, () => {
      const ctx: CollectingLogger = collectingLogger();
      const error = AppErrors.fromTdlibError(429, 'too many requests: FLOOD_WAIT_42');
      const line: string | null = ctx.logger.logError('Td', error);
      expect(line === null).assertFalse();
      expect((line as string).indexOf('tdlib/too_many_requests/retryable=true') >= 0).assertTrue();
      expect((line as string).indexOf('FLOOD_WAIT_42') >= 0).assertFalse();
    });

    // —— 永不抛错 ——
    it('logTdJson_invalidJson_noThrow_outputsPlaceholder', 0, () => {
      const ctx: CollectingLogger = collectingLogger();
      const line: string | null = ctx.logger.logTdJson('Td', 'raw', 'not-json{{');
      expect(line === null).assertFalse();
      expect((line as string).indexOf(FIXTURES.redacted) >= 0).assertTrue();
    });

    // —— filterByWhitelist 单测 ——
    it('filterByWhitelist_typeMissOnlyGlobalAndTypeKept', 0, () => {
      const record: Record<string, TdJsonRaw> = jsonObj();
      record['@type'] = 'unlistedType';
      record['a'] = 1;
      record['@extra'] = 'x';
      const expected: Record<string, TdJsonRaw> = jsonObj();
      expected['@type'] = 'unlistedType';
      expected['@extra'] = 'x';
      const filtered: Record<string, TdJsonRaw> = filterByWhitelist(record, DEFAULT_TD_LOG_WHITELIST);
      expect(JSON.stringify(filtered)).assertEqual(JSON.stringify(expected));
    });
  });
}
