import { describe, it, expect } from '@ohos/hypium';
import { AppError, AppErrors } from '../main/ets/AppError';

export default function appErrorTest() {
  describe('AppErrorTest', () => {
    it('networkFactory_producesNetworkError', 0, () => {
      const e: AppError = AppErrors.network('timeout', 'request timed out', true, 'error.network.timeout', 'socket error');
      expect(e.kind).assertEqual('network');
      if (e.kind === 'network') {
        expect(e.code).assertEqual('timeout');
        expect(e.retryable).assertTrue();
        expect(e.messageKey).assertEqual('error.network.timeout');
        expect(e.cause).assertEqual('socket error');
      } else {
        expect(false).assertTrue();
      }
    });

    it('storageFactory_producesStorageError', 0, () => {
      const e: AppError = AppErrors.storage('quota_exceeded', 'disk full', false);
      expect(e.kind).assertEqual('storage');
      if (e.kind === 'storage') {
        expect(e.code).assertEqual('quota_exceeded');
        expect(e.retryable).assertFalse();
      } else {
        expect(false).assertTrue();
      }
    });

    it('parameterFactory_carriesField', 0, () => {
      const e: AppError = AppErrors.parameter('missing', 'phoneNumber', 'phone number is required');
      expect(e.kind).assertEqual('parameter');
      if (e.kind === 'parameter') {
        expect(e.field).assertEqual('phoneNumber');
        expect(e.code).assertEqual('missing');
      } else {
        expect(false).assertTrue();
      }
    });

    it('platformFactory_carriesNumericCode', 0, () => {
      const e: AppError = AppErrors.platform(3300100, 'push kit error', true);
      expect(e.kind).assertEqual('platform');
      if (e.kind === 'platform') {
        expect(e.code).assertEqual(3300100);
        expect(e.retryable).assertTrue();
      } else {
        expect(false).assertTrue();
      }
    });

    it('internalFactory_defaultsMessageFromInvariant', 0, () => {
      const e: AppError = AppErrors.internal('chat.order', undefined, 'detail');
      expect(e.kind).assertEqual('internal');
      if (e.kind === 'internal') {
        expect(e.invariant).assertEqual('chat.order');
        expect(e.message.indexOf('chat.order') >= 0).assertTrue();
      } else {
        expect(false).assertTrue();
      }
    });

    it('unknownFactory_carriesOrigin', 0, () => {
      const e: AppError = AppErrors.unknown('authUseCase', 'unexpected failure');
      expect(e.kind).assertEqual('unknown');
      if (e.kind === 'unknown') {
        expect(e.origin).assertEqual('authUseCase');
      } else {
        expect(false).assertTrue();
      }
    });

    it('fromTdlibError_mapsStableCategories', 0, () => {
      const unauthorized: AppError = AppErrors.fromTdlibError(401, 'Unauthorized');
      if (unauthorized.kind === 'tdlib') {
        expect(unauthorized.code).assertEqual('unauthorized');
        expect(unauthorized.retryable).assertFalse();
      } else {
        expect(false).assertTrue();
      }

      const limited: AppError = AppErrors.fromTdlibError(429, 'Too Many Requests: retry after 15');
      if (limited.kind === 'tdlib') {
        expect(limited.code).assertEqual('too_many_requests');
        expect(limited.retryable).assertTrue();
      } else {
        expect(false).assertTrue();
      }

      const unknown: AppError = AppErrors.fromTdlibError(430, 'whatever');
      if (unknown.kind === 'tdlib') {
        expect(unknown.code).assertEqual('unknown');
        expect(unknown.retryable).assertTrue();
      } else {
        expect(false).assertTrue();
      }
    });

    it('fromTdlibError_keepsRawMessageOutOfUserMessage', 0, () => {
      const e: AppError = AppErrors.fromTdlibError(429, 'Too Many Requests: retry after 15');
      expect(e.message.indexOf('Too Many Requests') < 0).assertTrue();
      if (e.kind === 'tdlib') {
        expect(e.cause !== undefined && e.cause.indexOf('Too Many Requests') >= 0).assertTrue();
      } else {
        expect(false).assertTrue();
      }
    });

    it('isRetryable_reflectsVariantSemantics', 0, () => {
      expect(AppErrors.isRetryable(AppErrors.network('unreachable', 'offline', true))).assertTrue();
      expect(AppErrors.isRetryable(AppErrors.network('tls', 'pinning failed', false))).assertFalse();
      expect(AppErrors.isRetryable(AppErrors.storage('io', 'write failed', true))).assertTrue();
      expect(AppErrors.isRetryable(AppErrors.parameter('invalid', 'code', 'bad code'))).assertFalse();
      expect(AppErrors.isRetryable(AppErrors.internal('x.y'))).assertFalse();
      expect(AppErrors.isRetryable(AppErrors.unknown('origin', 'oops'))).assertFalse();
    });

    it('toLogString_isStableAndRedacted', 0, () => {
      const e: AppError = AppErrors.network('timeout', 'raw sensitive detail', true);
      expect(AppErrors.toLogString(e)).assertEqual('network/timeout/retryable=true');
      expect(AppErrors.toLogString(e).indexOf('raw sensitive detail') < 0).assertTrue();

      const p: AppError = AppErrors.parameter('missing', 'phone', 'raw phone detail');
      expect(AppErrors.toLogString(p)).assertEqual('parameter/missing/field=phone');

      const t: AppError = AppErrors.fromTdlibError(429, 'Too Many Requests');
      expect(AppErrors.toLogString(t)).assertEqual('tdlib/too_many_requests/retryable=true');
    });
  });
}
