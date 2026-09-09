import { describe, it, expect } from '@ohos/hypium';
import { AppError } from '@tgx/core-common';
import { OrderedEventRouter, TdRoutedEvent, TdUpdateSubscription } from '../main/ets/OrderedEventRouter';
import { TdWireObject } from '../main/ets/TdWire';

interface Captured {
  errors: AppError[];
  events: TdRoutedEvent[];
}

/** AppError 宽松视图（声明式接口替代内联字面量类型断言）。 */
interface ErrorView {
  kind: string;
  invariant?: string;
}

function viewOf(error: AppError): ErrorView {
  return error as ErrorView;
}

function newRouter(captured: Captured): OrderedEventRouter {
  return new OrderedEventRouter((error: AppError, event: TdRoutedEvent): void => {
    captured.errors.push(error);
    captured.events.push(event);
  });
}

function updatePayload(type: string): TdWireObject {
  const payload: TdWireObject = {};
  payload['@type'] = type;
  return payload;
}

export default function orderedEventRouterTest() {
  describe('OrderedEventRouterTest', () => {

    it('deliversEventToSubscriber', 0, () => {
      const captured: Captured = { errors: [], events: [] };
      const router: OrderedEventRouter = newRouter(captured);
      const received: TdRoutedEvent[] = [];
      router.subscribe({}, (event: TdRoutedEvent): void => {
        received.push(event);
      });
      expect(router.routePayload(1, '1', updatePayload('updateOption'))).assertTrue();
      expect(received.length).assertEqual(1);
      expect(received[0].type).assertEqual('updateOption');
      expect(received[0].sequence).assertEqual('1');
      expect(router.getMetrics().deliveredCount).assertEqual(1);
    });

    it('filtersByType', 0, () => {
      const captured: Captured = { errors: [], events: [] };
      const router: OrderedEventRouter = newRouter(captured);
      const received: TdRoutedEvent[] = [];
      router.subscribe({ types: ['updateNewMessage'] }, (event: TdRoutedEvent): void => {
        received.push(event);
      });
      router.routePayload(1, '1', updatePayload('updateChatTitle'));
      router.routePayload(1, '2', updatePayload('updateNewMessage'));
      expect(received.length).assertEqual(1);
      expect(received[0].type).assertEqual('updateNewMessage');
    });

    it('filtersByClientId', 0, () => {
      const captured: Captured = { errors: [], events: [] };
      const router: OrderedEventRouter = newRouter(captured);
      const received: TdRoutedEvent[] = [];
      router.subscribe({ clientId: 2 }, (event: TdRoutedEvent): void => {
        received.push(event);
      });
      router.routePayload(1, '1', updatePayload('updateOption'));
      router.routePayload(2, '1', updatePayload('updateOption'));
      expect(received.length).assertEqual(1);
      expect(received[0].clientId).assertEqual(2);
    });

    it('filtersByTypeAndClientId', 0, () => {
      const captured: Captured = { errors: [], events: [] };
      const router: OrderedEventRouter = newRouter(captured);
      const received: TdRoutedEvent[] = [];
      router.subscribe({ clientId: 1, types: ['updateNewMessage'] }, (event: TdRoutedEvent): void => {
        received.push(event);
      });
      router.routePayload(1, '1', updatePayload('updateNewMessage'));
      router.routePayload(1, '2', updatePayload('updateChatTitle'));
      router.routePayload(2, '1', updatePayload('updateNewMessage'));
      expect(received.length).assertEqual(1);
    });

    it('unsubscribeStopsDelivery', 0, () => {
      const captured: Captured = { errors: [], events: [] };
      const router: OrderedEventRouter = newRouter(captured);
      const received: TdRoutedEvent[] = [];
      const subscription: TdUpdateSubscription = router.subscribe({}, (event: TdRoutedEvent): void => {
        received.push(event);
      });
      router.routePayload(1, '1', updatePayload('updateOption'));
      subscription.unsubscribe();
      router.routePayload(1, '2', updatePayload('updateOption'));
      subscription.unsubscribe(); // 幂等
      expect(received.length).assertEqual(1);
    });

    it('multipleListenersBothReceive', 0, () => {
      const captured: Captured = { errors: [], events: [] };
      const router: OrderedEventRouter = newRouter(captured);
      const a: TdRoutedEvent[] = [];
      const b: TdRoutedEvent[] = [];
      router.subscribe({}, (event: TdRoutedEvent): void => {
        a.push(event);
      });
      router.subscribe({}, (event: TdRoutedEvent): void => {
        b.push(event);
      });
      router.routePayload(1, '1', updatePayload('updateOption'));
      expect(a.length).assertEqual(1);
      expect(b.length).assertEqual(1);
      expect(router.getMetrics().deliveredCount).assertEqual(2);
    });

    it('inOrderDeliveryPreservesOrder', 0, () => {
      const captured: Captured = { errors: [], events: [] };
      const router: OrderedEventRouter = newRouter(captured);
      const order: string[] = [];
      router.subscribe({}, (event: TdRoutedEvent): void => {
        order.push(event.sequence);
      });
      router.routePayload(1, '1', updatePayload('a'));
      router.routePayload(1, '2', updatePayload('b'));
      router.routePayload(1, '3', updatePayload('c'));
      expect(order.length).assertEqual(3);
      expect(order[0]).assertEqual('1');
      expect(order[1]).assertEqual('2');
      expect(order[2]).assertEqual('3');
      expect(router.getMetrics().outOfOrderCount).assertEqual(0);
      expect(router.getMetrics().duplicateCount).assertEqual(0);
    });

    it('duplicateSequence_droppedCountedNotDelivered', 0, () => {
      const captured: Captured = { errors: [], events: [] };
      const router: OrderedEventRouter = newRouter(captured);
      const received: TdRoutedEvent[] = [];
      router.subscribe({}, (event: TdRoutedEvent): void => {
        received.push(event);
      });
      expect(router.routePayload(1, '5', updatePayload('first'))).assertTrue();
      // 同 sequence 重复投递：幂等丢弃，不重复分发。
      expect(router.routePayload(1, '5', updatePayload('dup'))).assertFalse();
      expect(received.length).assertEqual(1);
      expect((received[0].payload['@type']) as string).assertEqual('first');
      expect(router.getMetrics().duplicateCount).assertEqual(1);
      expect(captured.errors.length).assertEqual(0);
    });

    it('outOfOrder_reportsInternalErrorAndDrops', 0, () => {
      const captured: Captured = { errors: [], events: [] };
      const router: OrderedEventRouter = newRouter(captured);
      const received: TdRoutedEvent[] = [];
      router.subscribe({}, (event: TdRoutedEvent): void => {
        received.push(event);
      });
      router.routePayload(1, '10', updatePayload('a'));
      // 乱序回退：不得静默吞掉。
      expect(router.routePayload(1, '9', updatePayload('b'))).assertFalse();
      expect(received.length).assertEqual(1);
      expect(router.getMetrics().outOfOrderCount).assertEqual(1);
      expect(captured.errors.length).assertEqual(1);
      expect(captured.errors[0].kind).assertEqual('internal');
      expect(viewOf(captured.errors[0]).invariant).assertEqual('td_gateway.sequence_monotonic');
      expect(captured.events[0].sequence).assertEqual('9');
    });

    it('multiClient_sequenceIndependent', 0, () => {
      const captured: Captured = { errors: [], events: [] };
      const router: OrderedEventRouter = newRouter(captured);
      const received: TdRoutedEvent[] = [];
      router.subscribe({}, (event: TdRoutedEvent): void => {
        received.push(event);
      });
      router.routePayload(1, '100', updatePayload('a'));
      router.routePayload(2, '3', updatePayload('b'));
      router.routePayload(1, '101', updatePayload('c'));
      router.routePayload(2, '4', updatePayload('d'));
      expect(received.length).assertEqual(4);
      expect(router.getMetrics().outOfOrderCount).assertEqual(0);
    });

    it('bigSequenceNumbers_compareAsDecimalStrings', 0, () => {
      const captured: Captured = { errors: [], events: [] };
      const router: OrderedEventRouter = newRouter(captured);
      const received: TdRoutedEvent[] = [];
      router.subscribe({}, (event: TdRoutedEvent): void => {
        received.push(event);
      });
      const big1: string = '9007199254740993'; // > 2^53，JS number 会丢精度
      const big2: string = '9007199254740994';
      router.routePayload(1, big1, updatePayload('a'));
      router.routePayload(1, big2, updatePayload('b'));
      expect(received.length).assertEqual(2);
      // 反向（大数回退 1）仍被精确识别为乱序，不误判为重复或有序。
      expect(router.routePayload(1, big1, updatePayload('c'))).assertFalse();
      expect(router.getMetrics().outOfOrderCount).assertEqual(1);
      expect(router.getMetrics().duplicateCount).assertEqual(0);
    });

    it('resetClient_allowsSequenceRestart', 0, () => {
      const captured: Captured = { errors: [], events: [] };
      const router: OrderedEventRouter = newRouter(captured);
      const received: TdRoutedEvent[] = [];
      router.subscribe({}, (event: TdRoutedEvent): void => {
        received.push(event);
      });
      router.routePayload(1, '9', updatePayload('a'));
      router.resetClient(1);
      router.routePayload(1, '1', updatePayload('fresh'));
      expect(received.length).assertEqual(2);
      expect(router.getMetrics().outOfOrderCount).assertEqual(0);
    });

    it('routedEvent_keepsWirePayloadForConsumerDecode', 0, () => {
      const captured: Captured = { errors: [], events: [] };
      const router: OrderedEventRouter = newRouter(captured);
      const received: TdRoutedEvent[] = [];
      router.subscribe({}, (event: TdRoutedEvent): void => {
        received.push(event);
      });
      const payload: TdWireObject = updatePayload('updateNewMessage');
      payload['message_id'] = '12345678901234567'; // int64 以 string 保留
      router.routePayload(1, '1', payload);
      expect((received[0].payload['message_id']) as string).assertEqual('12345678901234567');
    });
  });
}
