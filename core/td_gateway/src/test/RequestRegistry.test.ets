import { describe, it, expect } from '@ohos/hypium';
import { AppError, IdGenerator, ManualClock, RandomIdGenerator, Result, SequentialIdGenerator } from '@tgx/core-common';
import { RequestRegistry, TdPendingRequest, TdGatewayCancelledError, TdAbortSignal } from '../main/ets/RequestRegistry';
import { ManualTimeoutScheduler } from '../main/ets/TimeoutScheduler';
import { TdWireObject } from '../main/ets/TdWire';
import { tdWire } from './TestWire';
import { FakeBridge } from './FakeBridge';

function expectOkValue(result: Result<TdWireObject, AppError>): TdWireObject {
  expect(result.ok).assertTrue();
  if (result.ok) {
    return result.value;
  }
  return tdWire('{}');
}

function expectErr(result: Result<TdWireObject, AppError>): AppError {
  expect(result.ok === false).assertTrue();
  if (result.ok === false) {
    return result.error;
  }
  return TdGatewayCancelledError('unreachable');
}

/** AppError 宽松视图（声明式接口替代内联字面量类型断言）。 */
interface ErrorView {
  kind: string;
  code?: string;
  retryable?: boolean;
  origin?: string;
  field?: string;
  invariant?: string;
  cause?: string;
}

function viewOf(error: AppError): ErrorView {
  return error as ErrorView;
}

interface Harness {
  bridge: FakeBridge;
  clock: ManualClock;
  scheduler: ManualTimeoutScheduler;
  registry: RequestRegistry;
}

function newHarness(idGenerator?: IdGenerator): Harness {
  const bridge: FakeBridge = new FakeBridge();
  const clock: ManualClock = new ManualClock(0, 0);
  const scheduler: ManualTimeoutScheduler = new ManualTimeoutScheduler();
  const registry: RequestRegistry = new RequestRegistry(bridge, {
    idGenerator: idGenerator !== undefined ? idGenerator : new SequentialIdGenerator(),
    clock: clock,
    scheduler: scheduler
  });
  // 本套件直接测 registry：桥的响应/错误负载直接喂给 registry
  // （gateway 集成测试才走 start() 的事件封套路径）。
  bridge.payloadListener = (clientId: number, payload: TdWireObject): void => {
    registry.handleResponse(clientId, payload);
  };
  return { bridge: bridge, clock: clock, scheduler: scheduler, registry: registry };
}

/** 同时推进单调时钟与调度器（超时判定以单调时钟为准）。 */
function advance(h: Harness, millis: number): void {
  h.clock.advanceBy(millis);
  h.scheduler.advanceBy(millis);
}

export default function requestRegistryTest() {
  describe('RequestRegistryTest', () => {

    it('normal_response_resolvesOkWithPayload', 0, async () => {
      const h: Harness = newHarness();
      const pending: TdPendingRequest = h.registry.request(1, 'getOption', tdWire('{"name":"version"}'));
      h.bridge.deliverResponse(1, pending.requestId, tdWire('{"@type":"optionValueString","value":"1.8.67"}'));
      const result: Result<TdWireObject, AppError> = await pending.promise;
      const value: TdWireObject = expectOkValue(result);
      expect(value['@type'] as string).assertEqual('optionValueString');
      expect(value['value'] as string).assertEqual('1.8.67');
      expect(h.registry.getMetrics().resolvedCount).assertEqual(1);
    });

    it('request_injectsExtraRequestIdIntoWire', 0, () => {
      const h: Harness = newHarness();
      h.registry.request(1, 'getOption', tdWire('{"name":"version"}'));
      const wire: TdWireObject = h.bridge.lastSent();
      expect(wire['@type'] as string).assertEqual('getOption');
      expect(wire['name'] as string).assertEqual('version');
      const extra: TdWireObject = wire['@extra'] as TdWireObject;
      expect(extra['requestId'] as string).assertEqual('req-test-1');
    });

    it('request_mergesExistingExtraPreservingOtherFields', 0, () => {
      const h: Harness = newHarness();
      const params: TdWireObject = tdWire('{"name":"x"}');
      const extra: TdWireObject = tdWire('{"trace":"abc"}');
      params['@extra'] = extra;
      h.registry.request(1, 'getOption', params);
      const wire: TdWireObject = h.bridge.lastSent();
      const merged: TdWireObject = wire['@extra'] as TdWireObject;
      expect(merged['trace'] as string).assertEqual('abc');
      expect(merged['requestId'] as string).assertEqual('req-test-1');
      // 原 params 里的 @extra 不被原地污染（copy 后注入）。
      expect(extra['requestId'] === undefined).assertTrue();
    });

    it('requestId_uniqueAcrossRequests', 0, () => {
      const h: Harness = newHarness();
      const a: TdPendingRequest = h.registry.request(1, 'getOption', tdWire('{"name":"a"}'));
      const b: TdPendingRequest = h.registry.request(1, 'getOption', tdWire('{"name":"b"}'));
      expect(a.requestId === b.requestId).assertFalse();
      // 生产随机生成器：批量生成也不碰撞。
      const random: RandomIdGenerator = new RandomIdGenerator();
      const seen: Set<string> = new Set();
      for (let i: number = 0; i < 200; i++) {
        seen.add(random.nextRequestId());
      }
      expect(seen.size).assertEqual(200);
    });

    it('tdlibError_mapsToStableAppError', 0, async () => {
      const h: Harness = newHarness();
      const pending: TdPendingRequest = h.registry.request(1, 'sendMessage', tdWire('{}'));
      h.bridge.deliverError(1, pending.requestId, 400, 'can\'t parse entities');
      const error: AppError = expectErr(await pending.promise);
      expect(error.kind).assertEqual('tdlib');
      expect(viewOf(error).code).assertEqual('bad_request');
      expect(viewOf(error).retryable).assertFalse();
      // 原始 message 只允许进 cause，不透传。
      expect(error.message === 'can\'t parse entities').assertFalse();
      expect(error.cause !== undefined && error.cause.indexOf('can\'t parse entities') >= 0).assertTrue();
    });

    it('tdlibError_401unauthorized_notRetryable', 0, async () => {
      const h: Harness = newHarness();
      const pending: TdPendingRequest = h.registry.request(1, 'getMe', tdWire('{}'));
      h.bridge.deliverError(1, pending.requestId, 401, 'Unauthorized');
      const error: AppError = expectErr(await pending.promise);
      expect(error.kind).assertEqual('tdlib');
      expect(viewOf(error).code).assertEqual('unauthorized');
      expect(viewOf(error).retryable).assertFalse();
    });

    it('tdlibError_429rateLimited_retryable', 0, async () => {
      const h: Harness = newHarness();
      const pending: TdPendingRequest = h.registry.request(1, 'getMe', tdWire('{}'));
      h.bridge.deliverError(1, pending.requestId, 429, 'Too Many Requests');
      const error: AppError = expectErr(await pending.promise);
      expect(viewOf(error).code).assertEqual('too_many_requests');
      expect(viewOf(error).retryable).assertTrue();
    });

    it('tdlibError_404notFound', 0, async () => {
      const h: Harness = newHarness();
      const pending: TdPendingRequest = h.registry.request(1, 'getChat', tdWire('{}'));
      h.bridge.deliverError(1, pending.requestId, 404, 'Not Found');
      const error: AppError = expectErr(await pending.promise);
      expect(viewOf(error).code).assertEqual('not_found');
      expect(viewOf(error).retryable).assertFalse();
    });

    it('tdlibError_500internal_retryable', 0, async () => {
      const h: Harness = newHarness();
      const pending: TdPendingRequest = h.registry.request(1, 'getMe', tdWire('{}'));
      h.bridge.deliverError(1, pending.requestId, 500, 'internal');
      const error: AppError = expectErr(await pending.promise);
      expect(viewOf(error).code).assertEqual('internal');
      expect(viewOf(error).retryable).assertTrue();
    });

    it('tdlibError_unknownCode_mapsToUnknownRetryable', 0, async () => {
      const h: Harness = newHarness();
      const pending: TdPendingRequest = h.registry.request(1, 'getMe', tdWire('{}'));
      h.bridge.deliverError(1, pending.requestId, 420, 'whatever');
      const error: AppError = expectErr(await pending.promise);
      expect(viewOf(error).code).assertEqual('unknown');
      expect(viewOf(error).retryable).assertTrue();
    });

    it('timeout_mapsToNetworkTimeoutRetryable', 0, async () => {
      const h: Harness = newHarness();
      const pending: TdPendingRequest = h.registry.request(1, 'getMe', tdWire('{}'));
      advance(h, 10001);
      const error: AppError = expectErr(await pending.promise);
      expect(error.kind).assertEqual('network');
      expect(viewOf(error).code).assertEqual('timeout');
      expect(viewOf(error).retryable).assertTrue();
      expect(h.registry.getMetrics().timedOutCount).assertEqual(1);
      expect(h.registry.getMetrics().pendingCount).assertEqual(0);
    });

    it('timeout_defaultIsTenSeconds', 0, async () => {
      const h: Harness = newHarness();
      const pending: TdPendingRequest = h.registry.request(1, 'getMe', tdWire('{}'));
      advance(h, 9999);
      expect(pending.settled).assertFalse();
      advance(h, 1);
      expect(pending.settled).assertTrue();
      expectErr(await pending.promise);
    });

    it('timeout_perRequestOverride', 0, async () => {
      const h: Harness = newHarness();
      const pending: TdPendingRequest = h.registry.request(1, 'getMe', tdWire('{}'), { timeoutMillis: 250 });
      advance(h, 249);
      expect(pending.settled).assertFalse();
      advance(h, 1);
      expect(pending.settled).assertTrue();
      const error: AppError = expectErr(await pending.promise);
      expect(viewOf(error).code).assertEqual('timeout');
    });

    it('cancel_beforeResponse_settlesCancelled', 0, async () => {
      const h: Harness = newHarness();
      const pending: TdPendingRequest = h.registry.request(1, 'getMe', tdWire('{}'));
      expect(pending.cancel()).assertTrue();
      const error: AppError = expectErr(await pending.promise);
      expect(error.kind).assertEqual('unknown');
      expect(viewOf(error).origin).assertEqual('td_gateway.request_cancelled');
      expect(h.registry.getMetrics().cancelledCount).assertEqual(1);
    });

    it('cancel_isIdempotent', 0, async () => {
      const h: Harness = newHarness();
      const pending: TdPendingRequest = h.registry.request(1, 'getMe', tdWire('{}'));
      expect(pending.cancel()).assertTrue();
      expect(pending.cancel()).assertFalse();
      expect(h.registry.getMetrics().cancelledCount).assertEqual(1);
      // 取消后再来响应也绝不二次结算。
      h.bridge.deliverResponse(1, pending.requestId, tdWire('{"@type":"ok"}'));
      expect(h.registry.getMetrics().lateResponseCount).assertEqual(1);
      expectErr(await pending.promise);
    });

    it('cancel_afterResolve_returnsFalse', 0, async () => {
      const h: Harness = newHarness();
      const pending: TdPendingRequest = h.registry.request(1, 'getMe', tdWire('{}'));
      h.bridge.deliverResponse(1, pending.requestId, tdWire('{"@type":"ok"}'));
      expectOkValue(await pending.promise);
      expect(pending.cancel()).assertFalse();
    });

    it('signalAbortedAtRequestTime_cancelsImmediately', 0, async () => {
      const h: Harness = newHarness();
      const signal: TdAbortSignal = { aborted: true };
      const pending: TdPendingRequest = h.registry.request(1, 'getMe', tdWire('{}'), { signal: signal });
      expect(pending.settled).assertTrue();
      expectErr(await pending.promise);
      expect(h.registry.getMetrics().cancelledCount).assertEqual(1);
    });

    it('lateResponseAfterTimeout_droppedAndCounted', 0, async () => {
      const h: Harness = newHarness();
      const pending: TdPendingRequest = h.registry.request(1, 'getMe', tdWire('{}'));
      advance(h, 10001);
      const error: AppError = expectErr(await pending.promise);
      expect(viewOf(error).code).assertEqual('timeout');
      // 迟到响应：不得改判，只计数。
      h.bridge.deliverResponse(1, pending.requestId, tdWire('{"@type":"ok"}'));
      expect(h.registry.getMetrics().lateResponseCount).assertEqual(1);
      expect(h.registry.getMetrics().resolvedCount).assertEqual(0);
      advance(h, 50000);
      expectErr(await pending.promise);
    });

    it('lateErrorResponseAfterCancel_droppedAndCounted', 0, async () => {
      const h: Harness = newHarness();
      const pending: TdPendingRequest = h.registry.request(1, 'getMe', tdWire('{}'));
      pending.cancel();
      expectErr(await pending.promise);
      h.bridge.deliverError(1, pending.requestId, 400, 'bad');
      expect(h.registry.getMetrics().lateResponseCount).assertEqual(1);
    });

    it('responseWithoutRequestId_countedUnmatched', 0, () => {
      const h: Harness = newHarness();
      h.registry.handleResponse(1, tdWire('{"@type":"ok"}'));
      expect(h.registry.getMetrics().unmatchedResponseCount).assertEqual(1);
      expect(h.registry.getMetrics().lateResponseCount).assertEqual(0);
    });

    it('unknownRequestId_countedUnmatchedNotLate', 0, () => {
      const h: Harness = newHarness();
      const extra: TdWireObject = tdWire('{"requestId":"never-registered"}');
      const response: TdWireObject = tdWire('{"@type":"ok"}');
      response['@extra'] = extra;
      h.registry.handleResponse(1, response);
      expect(h.registry.getMetrics().unmatchedResponseCount).assertEqual(1);
      expect(h.registry.getMetrics().lateResponseCount).assertEqual(0);
    });

    it('crossClientResponse_countedNotResolved', 0, async () => {
      const h: Harness = newHarness();
      const pending: TdPendingRequest = h.registry.request(1, 'getMe', tdWire('{}'));
      // 响应从错误的 client 到达：不得结算。
      h.bridge.deliverResponse(2, pending.requestId, tdWire('{"@type":"ok"}'));
      expect(h.registry.getMetrics().crossClientResponseCount).assertEqual(1);
      expect(pending.settled).assertFalse();
      // 正确 client 到达后正常结算。
      h.bridge.deliverResponse(1, pending.requestId, tdWire('{"@type":"ok"}'));
      expectOkValue(await pending.promise);
    });

    it('concurrentRequests_matchedByRequestId', 0, async () => {
      const h: Harness = newHarness();
      const first: TdPendingRequest = h.registry.request(1, 'getOption', tdWire('{"name":"a"}'));
      const second: TdPendingRequest = h.registry.request(1, 'getOption', tdWire('{"name":"b"}'));
      // 逆序响应也能各归各。
      h.bridge.deliverResponse(1, second.requestId, tdWire('{"@type":"optionValueString","value":"vb"}'));
      h.bridge.deliverResponse(1, first.requestId, tdWire('{"@type":"optionValueString","value":"va"}'));
      const r1: TdWireObject = expectOkValue(await first.promise);
      const r2: TdWireObject = expectOkValue(await second.promise);
      expect(r1['value'] as string).assertEqual('va');
      expect(r2['value'] as string).assertEqual('vb');
    });

    it('multiClient_isolation', 0, async () => {
      const h: Harness = newHarness();
      const clientA: TdPendingRequest = h.registry.request(1, 'getMe', tdWire('{}'));
      const clientB: TdPendingRequest = h.registry.request(2, 'getMe', tdWire('{}'));
      h.bridge.deliverResponse(2, clientB.requestId, tdWire('{"@type":"ok","client":"b"}'));
      h.bridge.deliverResponse(1, clientA.requestId, tdWire('{"@type":"ok","client":"a"}'));
      const ra: TdWireObject = expectOkValue(await clientA.promise);
      const rb: TdWireObject = expectOkValue(await clientB.promise);
      expect(ra['client'] as string).assertEqual('a');
      expect(rb['client'] as string).assertEqual('b');
    });

    it('sendFailure_mapsToPlatformErrorWithoutThrowing', 0, async () => {
      const h: Harness = newHarness();
      h.bridge.failSendForeverFlag = true;
      const pending: TdPendingRequest = h.registry.request(1, 'getMe', tdWire('{}'));
      const error: AppError = expectErr(await pending.promise);
      expect(error.kind).assertEqual('platform');
      expect(h.registry.getMetrics().sendFailureCount).assertEqual(1);
    });

    it('invalidClientId_parameterErrorNoSend', 0, async () => {
      const h: Harness = newHarness();
      const pending: TdPendingRequest = h.registry.request(-1, 'getMe', tdWire('{}'));
      const error: AppError = expectErr(await pending.promise);
      expect(error.kind).assertEqual('parameter');
      expect(viewOf(error).field).assertEqual('clientId');
      expect(h.bridge.sent.length).assertEqual(0);
    });

    it('resolvedBeforeTimeout_timerCleared', 0, async () => {
      const h: Harness = newHarness();
      const pending: TdPendingRequest = h.registry.request(1, 'getMe', tdWire('{}'));
      h.bridge.deliverResponse(1, pending.requestId, tdWire('{"@type":"ok"}'));
      expectOkValue(await pending.promise);
      advance(h, 60000);
      expect(h.registry.getMetrics().timedOutCount).assertEqual(0);
      expect(h.registry.getMetrics().lateResponseCount).assertEqual(0);
    });
  });
}
