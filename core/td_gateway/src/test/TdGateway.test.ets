import { describe, it, expect } from '@ohos/hypium';
import { AppError, ManualClock, Result, SequentialIdGenerator } from '@tgx/core-common';
import { TdGateway, isCancelledRequestError } from '../main/ets/TdGateway';
import { TdPendingRequest } from '../main/ets/RequestRegistry';
import { TdRoutedEvent } from '../main/ets/OrderedEventRouter';
import { TdNativeEvent } from '../main/ets/TdNativeBridgeLike';
import { ManualTimeoutScheduler } from '../main/ets/TimeoutScheduler';
import { TdWireObject } from '../main/ets/TdWire';
import { tdWire } from './TestWire';
import { FakeBridge } from './FakeBridge';

interface GatewayHarness {
  bridge: FakeBridge;
  clock: ManualClock;
  scheduler: ManualTimeoutScheduler;
  gateway: TdGateway;
  protocolErrors: AppError[];
}

function newGatewayHarness(): GatewayHarness {
  const bridge: FakeBridge = new FakeBridge();
  const clock: ManualClock = new ManualClock(0, 0);
  const scheduler: ManualTimeoutScheduler = new ManualTimeoutScheduler();
  const protocolErrors: AppError[] = [];
  const gateway: TdGateway = new TdGateway(bridge, {
    idGenerator: new SequentialIdGenerator(),
    clock: clock,
    scheduler: scheduler,
    onProtocolError: (error: AppError): void => {
      protocolErrors.push(error);
    }
  });
  return { bridge: bridge, clock: clock, scheduler: scheduler, gateway: gateway, protocolErrors: protocolErrors };
}

function expectOkValue(result: Result<TdWireObject, AppError>): TdWireObject {
  expect(result.ok).assertTrue();
  if (result.ok) {
    return result.value;
  }
  return tdWire('{}');
}

/** AppError 宽松视图（声明式接口替代内联字面量类型断言）。 */
interface ErrorView {
  kind: string;
  code?: string;
}

function viewOf(error: AppError): ErrorView {
  return error as ErrorView;
}

export default function tdGatewayTest() {
  describe('TdGatewayTest', () => {

    it('start_subscribesBridgeAndIsIdempotent', 0, () => {
      const h: GatewayHarness = newGatewayHarness();
      const id1: number = h.gateway.start();
      const id2: number = h.gateway.start();
      expect(id1 >= 0).assertTrue();
      expect(id2).assertEqual(id1);
      expect(h.bridge.getMetrics().subscriptions).assertEqual(1);
      expect(h.gateway.started).assertTrue();
    });

    it('stop_unsubscribesAndIsIdempotent', 0, () => {
      const h: GatewayHarness = newGatewayHarness();
      h.gateway.start();
      h.gateway.stop();
      expect(h.bridge.getMetrics().subscriptions).assertEqual(0);
      expect(h.gateway.started).assertFalse();
      h.gateway.stop(); // 幂等
      expect(h.bridge.getMetrics().subscriptions).assertEqual(0);
    });

    it('responseEventWithExtra_resolvesPendingRequest', 0, async () => {
      const h: GatewayHarness = newGatewayHarness();
      h.gateway.start();
      const pending: TdPendingRequest = h.gateway.request(1, 'getOption', tdWire('{"name":"version"}'));
      h.bridge.deliverResponse(1, pending.requestId, tdWire('{"@type":"optionValueString","value":"1.8.67"}'));
      const value: TdWireObject = expectOkValue(await pending.promise);
      expect(value['value'] as string).assertEqual('1.8.67');
      // 响应不进 update 流。
      expect(h.gateway.getMetrics().router.deliveredCount).assertEqual(0);
    });

    it('updateEventWithoutExtra_routesToUpdateStream', 0, () => {
      const h: GatewayHarness = newGatewayHarness();
      h.gateway.start();
      const updates: TdWireObject[] = [];
      h.gateway.subscribeUpdates({ types: ['updateNewMessage'] }, (event: TdRoutedEvent): void => {
        updates.push(event.payload);
      });
      h.bridge.deliverUpdate(1, 'updateNewMessage', tdWire('{"message_id":"42"}'));
      h.bridge.deliverUpdate(1, 'updateChatTitle', tdWire('{"title":"x"}'));
      expect(updates.length).assertEqual(1);
      expect((updates[0]['message_id']) as string).assertEqual('42');
    });

    it('errorEventWithExtra_goesToRegistryNotRouter', 0, async () => {
      const h: GatewayHarness = newGatewayHarness();
      h.gateway.start();
      const pending: TdPendingRequest = h.gateway.request(1, 'getMe', tdWire('{}'));
      h.bridge.deliverError(1, pending.requestId, 401, 'Unauthorized');
      const result: Result<TdWireObject, AppError> = await pending.promise;
      expect(result.ok === false).assertTrue();
      if (result.ok === false) {
        expect(result.error.kind).assertEqual('tdlib');
      }
      expect(h.gateway.getMetrics().router.deliveredCount).assertEqual(0);
    });

    it('unknownRequestIdResponse_countedNotRouted', 0, () => {
      const h: GatewayHarness = newGatewayHarness();
      h.gateway.start();
      h.bridge.deliverResponse(1, 'never-registered', tdWire('{"@type":"ok"}'));
      expect(h.gateway.getMetrics().registry.unmatchedResponseCount).assertEqual(1);
      expect(h.gateway.getMetrics().router.deliveredCount).assertEqual(0);
    });

    it('undecodablePayload_countsDecodeErrorAndReports', 0, () => {
      const h: GatewayHarness = newGatewayHarness();
      h.gateway.start();
      const bad: TdNativeEvent = {
        schemaVersion: 1,
        clientId: 1,
        sequence: '1',
        payloadUtf8: '{not valid json',
        receivedAtMonotonicMs: 0
      };
      h.bridge.emitRaw(bad);
      expect(h.gateway.getMetrics().decodeErrorCount).assertEqual(1);
      expect(h.protocolErrors.length).assertEqual(1);
      expect(h.protocolErrors[0].kind).assertEqual('internal');
      // 后续事件不受影响（订阅者照常收到）。
      let afterBad: number = 0;
      h.gateway.subscribeUpdates({}, (event: TdRoutedEvent): void => {
        afterBad += 1;
      });
      h.bridge.deliverUpdate(1, 'updateOption', tdWire('{}'), '2');
      expect(afterBad).assertEqual(1);
    });

    it('nonObjectPayload_countsDecodeError', 0, () => {
      const h: GatewayHarness = newGatewayHarness();
      h.gateway.start();
      const arr: TdNativeEvent = {
        schemaVersion: 1,
        clientId: 1,
        sequence: '1',
        payloadUtf8: '[1,2,3]',
        receivedAtMonotonicMs: 0
      };
      h.bridge.emitRaw(arr);
      expect(h.gateway.getMetrics().decodeErrorCount).assertEqual(1);
    });

    it('outOfOrderUpdate_reachesProtocolErrorSink', 0, () => {
      const h: GatewayHarness = newGatewayHarness();
      h.gateway.start();
      h.bridge.deliverUpdate(1, 'updateOption', tdWire('{}'), '10');
      h.bridge.deliverUpdate(1, 'updateOption', tdWire('{}'), '9');
      expect(h.gateway.getMetrics().router.outOfOrderCount).assertEqual(1);
      expect(h.protocolErrors.length).assertEqual(1);
    });

    it('mixedResponseAndUpdates_bothFlowInOrder', 0, async () => {
      const h: GatewayHarness = newGatewayHarness();
      h.gateway.start();
      const seen: string[] = [];
      h.gateway.subscribeUpdates({}, (event: TdRoutedEvent): void => {
        seen.push(`${event.sequence}:${event.type}`);
      });
      const pending: TdPendingRequest = h.gateway.request(1, 'sendMessage', tdWire('{"chat_id":"7"}'));
      // §6.2：响应与 update 以各自通道到达，update 保持有序。
      h.bridge.deliverUpdate(1, 'updateMessageSendingStatePending', tdWire('{}'), '1');
      h.bridge.deliverResponse(1, pending.requestId, tdWire('{"@type":"message","id":"7"}'));
      h.bridge.deliverUpdate(1, 'updateNewMessage', tdWire('{}'), '2');
      const value: TdWireObject = expectOkValue(await pending.promise);
      expect(value['@type'] as string).assertEqual('message');
      expect(seen.length).assertEqual(2);
      expect(seen[0]).assertEqual('1:updateMessageSendingStatePending');
      expect(seen[1]).assertEqual('2:updateNewMessage');
    });

    it('gatewayTimeout_endToEnd', 0, async () => {
      const h: GatewayHarness = newGatewayHarness();
      h.gateway.start();
      const pending: TdPendingRequest = h.gateway.request(1, 'getMe', tdWire('{}'), { timeoutMillis: 500 });
      h.clock.advanceBy(501);
      h.scheduler.advanceBy(501);
      const result: Result<TdWireObject, AppError> = await pending.promise;
      expect(result.ok === false).assertTrue();
      if (result.ok === false) {
        expect(result.error.kind).assertEqual('network');
        expect(viewOf(result.error).code).assertEqual('timeout');
      }
    });

    it('gatewayCancel_isCancelledRequestError', 0, async () => {
      const h: GatewayHarness = newGatewayHarness();
      h.gateway.start();
      const pending: TdPendingRequest = h.gateway.request(1, 'getMe', tdWire('{}'));
      pending.cancel();
      const result: Result<TdWireObject, AppError> = await pending.promise;
      expect(result.ok === false).assertTrue();
      if (result.ok === false) {
        expect(isCancelledRequestError(result.error)).assertTrue();
      }
    });

    it('executeSync_passthrough', 0, () => {
      const h: GatewayHarness = newGatewayHarness();
      const response: string | null = h.gateway.executeSync('{"@type":"getTextEntities"}');
      expect(response !== null && response.indexOf('textEntities') >= 0).assertTrue();
    });
  });
}
