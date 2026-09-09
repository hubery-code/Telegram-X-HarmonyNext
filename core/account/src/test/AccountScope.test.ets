/**
 * AccountScope 单测（CORE-003）：生命周期副作用、取消域、事件守卫/过滤、
 * 目录解析、授权状态占位。FakeBridge/FakeFiles/FakeClock 全注入。
 */

import { describe, it, expect } from '@ohos/hypium';
import { AppError, ManualClock, Result, SequentialIdGenerator } from '@tgx/core-common';
import { FakeAppFiles } from '@tgx/platform-ports';
import {
  isCancelledRequestError,
  ManualTimeoutScheduler,
  TdNativeEvent,
  TdPendingRequest,
  TdRoutedEvent,
  TdWireObject,
  wireString
} from '@tgx/td-gateway';
import { AccountLifecycleState } from '../main/ets/AccountLifecycle';
import { AccountDirectoryLayout, buildAccountDirectories } from '../main/ets/AccountDirectories';
import { createDescriptor } from '../main/ets/AccountDescriptor';
import { AccountScope } from '../main/ets/AccountScope';
import { FakeAccountBridge } from './FakeAccountBridge';
import { tdWire } from './TestWire';

interface ScopeHarness {
  bridge: FakeAccountBridge;
  clock: ManualClock;
  scheduler: ManualTimeoutScheduler;
  files: FakeAppFiles;
  scope: AccountScope;
}

function unwrap<T>(result: Result<T, AppError>): T {
  if (result.ok) {
    return result.value;
  }
  expect(result.ok).assertTrue();
  throw new Error('unreachable: expected ok result');
}

function newScopeHarness(startActive: boolean, accountKey: string): ScopeHarness {
  const bridge: FakeAccountBridge = new FakeAccountBridge();
  const clock: ManualClock = new ManualClock(0, 0);
  const scheduler: ManualTimeoutScheduler = new ManualTimeoutScheduler();
  const files: FakeAppFiles = new FakeAppFiles();
  const layout: AccountDirectoryLayout = unwrap(buildAccountDirectories(accountKey));
  const opened: Result<AccountScope, AppError> = AccountScope.open({
    bridge: bridge,
    files: files,
    descriptor: createDescriptor(accountKey, 'acct-test-1', 0, true),
    directories: layout,
    gatewayOptions: {
      idGenerator: new SequentialIdGenerator(),
      clock: clock,
      scheduler: scheduler
    },
    startActive: startActive
  });
  const scope: AccountScope = unwrap(opened);
  return { bridge: bridge, clock: clock, scheduler: scheduler, files: files, scope: scope };
}

function nativeEvent(clientId: number, sequence: string, payloadUtf8: string): TdNativeEvent {
  return {
    schemaVersion: 1,
    clientId: clientId,
    sequence: sequence,
    payloadUtf8: payloadUtf8,
    receivedAtMonotonicMs: 0
  };
}

export default function accountScopeTest() {
  describe('AccountScopeTest', () => {

    it('openActive_startsGatewayAndAssignsClientId', 0, () => {
      const h: ScopeHarness = newScopeHarness(true, 'acc-a');
      expect(h.scope.lifecycle).assertEqual('active');
      expect(h.scope.clientId).assertEqual(1);
      expect(h.scope.accountKey).assertEqual('acc-a');
      expect(h.scope.accountId).assertEqual('acct-test-1');
      expect(h.bridge.subscriptionCount()).assertEqual(1);
      expect(h.bridge.createdClientCount()).assertEqual(1);
    });

    it('openInactive_startsHibernatingWithoutGateway', 0, () => {
      const h: ScopeHarness = newScopeHarness(false, 'acc-a');
      expect(h.scope.lifecycle).assertEqual('hibernating');
      expect(h.bridge.subscriptionCount()).assertEqual(0);
    });

    it('request_sendsWithExtraAndResolves', 0, async () => {
      const h: ScopeHarness = newScopeHarness(true, 'acc-a');
      const requested: Result<TdPendingRequest, AppError> = h.scope.request('getOption', tdWire('{"name":"version"}'));
      const pending: TdPendingRequest = unwrap(requested);
      expect(h.scope.pendingRequestCount).assertEqual(1);
      const sent: TdWireObject = h.bridge.lastSentWire();
      const extraValue: TdWireObject = sent['@extra'] as TdWireObject;
      expect(wireString(extraValue['requestId'])).assertEqual('req-test-1');
      h.bridge.deliverResponse(h.scope.clientId, pending.requestId, tdWire('{"@type":"option","value":"1.8.67"}'));
      const result: Result<TdWireObject, AppError> = await pending.promise;
      expect(result.ok).assertTrue();
      expect(h.scope.pendingRequestCount).assertEqual(0);
    });

    it('request_onClosedScope_returnsErr_neverSends', 0, () => {
      const h: ScopeHarness = newScopeHarness(true, 'acc-a');
      h.scope.close();
      const sentBefore: number = h.bridge.sent.length;
      const requested: Result<TdPendingRequest, AppError> = h.scope.request('getOption');
      expect(requested.ok).assertFalse();
      if (requested.ok === false) {
        expect(requested.error.kind).assertEqual('unknown');
        if (requested.error.kind === 'unknown') {
          expect(requested.error.origin).assertEqual('core_account.scope_closed');
        }
      }
      expect(h.bridge.sent.length).assertEqual(sentBefore);
    });

    it('hibernate_stopsSubscription_keepsDescriptorAndDirectories', 0, () => {
      const h: ScopeHarness = newScopeHarness(true, 'acc-a');
      const result: Result<AccountLifecycleState, AppError> = h.scope.hibernate();
      expect(result.ok).assertTrue();
      expect(h.scope.lifecycle).assertEqual('hibernating');
      expect(h.bridge.subscriptionCount()).assertEqual(0);
      expect(h.scope.descriptor.accountKey).assertEqual('acc-a');
      expect(h.scope.directories.accountDir.sub).assertEqual('accounts/acc-a');
    });

    it('activateAfterHibernate_roundTripsBackToActive', 0, () => {
      const h: ScopeHarness = newScopeHarness(true, 'acc-a');
      h.scope.hibernate();
      const result: Result<AccountLifecycleState, AppError> = h.scope.activate();
      expect(result.ok).assertTrue();
      expect(h.scope.lifecycle).assertEqual('active');
      expect(h.bridge.subscriptionCount()).assertEqual(1);
    });

    it('close_cancelsAllPendingRequests', 0, async () => {
      const h: ScopeHarness = newScopeHarness(true, 'acc-a');
      const first: Result<TdPendingRequest, AppError> = h.scope.request('getOption');
      const second: Result<TdPendingRequest, AppError> = h.scope.request('getOption');
      expect(first.ok).assertTrue();
      expect(second.ok).assertTrue();
      const firstPending: TdPendingRequest = unwrap(first);
      const secondPending: TdPendingRequest = unwrap(second);
      h.scope.close();
      const firstResult: Result<TdWireObject, AppError> = await firstPending.promise;
      const secondResult: Result<TdWireObject, AppError> = await secondPending.promise;
      expect(firstResult.ok).assertFalse();
      expect(secondResult.ok).assertFalse();
      if (firstResult.ok === false) {
        expect(isCancelledRequestError(firstResult.error)).assertTrue();
      }
      if (secondResult.ok === false) {
        expect(isCancelledRequestError(secondResult.error)).assertTrue();
      }
      expect(h.scope.gatewayInstance.getMetrics().registry.cancelledCount).assertEqual(2);
      expect(h.scope.pendingRequestCount).assertEqual(0);
    });

    it('close_isIdempotent_withoutDoubleCancel', 0, () => {
      const h: ScopeHarness = newScopeHarness(true, 'acc-a');
      h.scope.request('getOption');
      h.scope.close();
      h.scope.close();
      expect(h.scope.lifecycle).assertEqual('closed');
      expect(h.scope.gatewayInstance.getMetrics().registry.cancelledCount).assertEqual(1);
      expect(h.bridge.subscriptionCount()).assertEqual(0);
    });

    it('close_lateEventIsDroppedAndCounted_listenerNotLeaked', 0, () => {
      const h: ScopeHarness = newScopeHarness(true, 'acc-a');
      const received: TdRoutedEvent[] = [];
      h.scope.subscribeEvents((event: TdRoutedEvent): void => {
        received.push(event);
      });
      h.scope.close();
      const late: TdNativeEvent = nativeEvent(
        h.scope.clientId,
        '1',
        '{"@type":"updateNewMessage","message":{}}'
      );
      h.scope.gatewayInstance.handleNativeEvent(late);
      expect(received.length).assertEqual(0);
      expect(h.scope.droppedEventCount).assertEqual(1);
      expect(h.scope.getMetrics().lifecycle).assertEqual('closed');
    });

    it('event_otherClientId_filteredBySubscription', 0, () => {
      const h: ScopeHarness = newScopeHarness(true, 'acc-a');
      const received: TdRoutedEvent[] = [];
      h.scope.subscribeEvents((event: TdRoutedEvent): void => {
        received.push(event);
      });
      h.bridge.deliverUpdate(999, 'updateNewMessage', tdWire('{}'));
      expect(received.length).assertEqual(0);
      h.bridge.deliverUpdate(h.scope.clientId, 'updateNewMessage', tdWire('{}'));
      expect(received.length).assertEqual(1);
      expect(received[0].type).assertEqual('updateNewMessage');
    });

    it('hibernate_directEventIsDroppedAndCounted', 0, () => {
      const h: ScopeHarness = newScopeHarness(true, 'acc-a');
      h.scope.hibernate();
      const event: TdNativeEvent = nativeEvent(
        h.scope.clientId,
        '1',
        '{"@type":"updateConnectionState","state":{}}'
      );
      h.scope.gatewayInstance.handleNativeEvent(event);
      expect(h.scope.droppedEventCount).assertEqual(1);
      expect(h.scope.lifecycle).assertEqual('hibernating');
    });

    it('authorizationHolder_initialWaitParams_replaceableForCore005', 0, () => {
      const h: ScopeHarness = newScopeHarness(true, 'acc-a');
      expect(h.scope.authorization).assertEqual('waitParams');
      h.scope.authorizationHolder.replace('ready');
      expect(h.scope.authorization).assertEqual('ready');
      h.scope.authorizationHolder.replace('waitCode');
      expect(h.scope.authorization).assertEqual('waitCode');
    });

    it('resolveAccountPath_goesThroughFilesPort', 0, () => {
      const h: ScopeHarness = newScopeHarness(true, 'acc-a');
      const resolved: Result<string, AppError> = h.scope.resolveAccountPath('tdlib/db/td.binlog');
      expect(resolved.ok).assertTrue();
      if (resolved.ok) {
        expect(resolved.value).assertEqual('/sandbox/files/accounts/acc-a/tdlib/db/td.binlog');
      }
      const escaped: Result<string, AppError> = h.scope.resolveAccountPath('../outside');
      expect(escaped.ok).assertFalse();
    });
  });
}
