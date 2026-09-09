/**
 * AccountRegistry 单测（CORE-003）：幂等创建、生命周期编排、持久化往返、
 * 冷启动恢复（单账号失败隔离）、未知 clientId 记账、跨账号事件隔离。
 */

import { describe, it, expect } from '@ohos/hypium';
import { AppError, ManualClock, Result, SequentialIdGenerator } from '@tgx/core-common';
import {
  isCancelledRequestError,
  ManualTimeoutScheduler,
  TdPendingRequest,
  TdRoutedEvent,
  TdWireObject
} from '@tgx/td-gateway';
import { SequentialAccountIdGenerator } from '../main/ets/AccountIds';
import { AccountScope } from '../main/ets/AccountScope';
import {
  AccountRegistry,
  AccountRegistryOptions,
  AccountRestoreReport
} from '../main/ets/AccountRegistry';
import { FakeAccountBridge } from './FakeAccountBridge';
import { FlakyFiles } from './FlakyFiles';
import { tdWire } from './TestWire';

interface RegistryHarness {
  bridge: FakeAccountBridge;
  files: FlakyFiles;
  registry: AccountRegistry;
  unknownErrors: AppError[];
}

function newRegistryHarness(files?: FlakyFiles): RegistryHarness {
  const bridge: FakeAccountBridge = new FakeAccountBridge();
  const sharedFiles: FlakyFiles = files !== undefined ? files : new FlakyFiles();
  const unknownErrors: AppError[] = [];
  const clock: ManualClock = new ManualClock(1725840000000, 0);
  const options: AccountRegistryOptions = {
    bridge: bridge,
    files: sharedFiles,
    idGenerator: new SequentialAccountIdGenerator(),
    clock: clock,
    gatewayOptions: {
      idGenerator: new SequentialIdGenerator(),
      clock: clock,
      scheduler: new ManualTimeoutScheduler()
    },
    onUnknownClientId: (error: AppError): void => {
      unknownErrors.push(error);
    }
  };
  const registry: AccountRegistry = new AccountRegistry(options);
  return { bridge: bridge, files: sharedFiles, registry: registry, unknownErrors: unknownErrors };
}

function expectScope(result: Result<AccountScope, AppError>): AccountScope {
  if (result.ok) {
    return result.value;
  }
  expect(result.ok).assertTrue();
  throw new Error('unreachable: expected ok result');
}

export default function accountRegistryTest() {
  describe('AccountRegistryTest', () => {

    it('create_returnsActiveScopeWithGeneratedAccountId', 0, () => {
      const h: RegistryHarness = newRegistryHarness();
      const scope: AccountScope = expectScope(h.registry.create('8613800138000'));
      expect(scope.lifecycle).assertEqual('active');
      expect(scope.accountId).assertEqual('acct-test-1');
      expect(scope.descriptor.enabled).assertTrue();
      expect(scope.descriptor.createdAtMillis).assertEqual(1725840000000);
      expect(h.registry.getMetrics().activeCount).assertEqual(1);
    });

    it('create_duplicateKey_returnsExistingScope', 0, () => {
      const h: RegistryHarness = newRegistryHarness();
      const first: AccountScope = expectScope(h.registry.create('a'));
      const second: AccountScope = expectScope(h.registry.create('a'));
      expect(second === first).assertTrue();
      expect(h.registry.getMetrics().scopeCount).assertEqual(1);
      expect(h.bridge.createdClientCount()).assertEqual(1);
      expect(h.registry.list().length).assertEqual(1);
    });

    it('create_afterClose_buildsFreshScope', 0, () => {
      const h: RegistryHarness = newRegistryHarness();
      const first: AccountScope = expectScope(h.registry.create('a'));
      expectScope(h.registry.close('a'));
      const second: AccountScope = expectScope(h.registry.create('a'));
      expect(second === first).assertFalse();
      expect(second.lifecycle).assertEqual('active');
      expect(second.clientId).assertEqual(2);
      expect(h.registry.getMetrics().activeCount).assertEqual(1);
      // closed scope 在 create 替换时才移出注册表（close 幂等保留），重建后 closedCount 归零。
      expect(h.registry.getMetrics().closedCount).assertEqual(0);
      expect(h.registry.getMetrics().scopeCount).assertEqual(1);
    });

    it('create_invalidKey_rejected', 0, () => {
      const h: RegistryHarness = newRegistryHarness();
      const result: Result<AccountScope, AppError> = h.registry.create('bad/key');
      expect(result.ok).assertFalse();
      if (result.ok === false) {
        expect(result.error.kind).assertEqual('parameter');
      }
      expect(h.registry.getMetrics().scopeCount).assertEqual(0);
    });

    it('create_manifestWriteFailure_rollsBackScope', 0, () => {
      const h: RegistryHarness = newRegistryHarness();
      h.files.failNextWriteFlag = true;
      const result: Result<AccountScope, AppError> = h.registry.create('a');
      expect(result.ok).assertFalse();
      if (result.ok === false) {
        expect(result.error.kind).assertEqual('storage');
      }
      expect(h.registry.getMetrics().scopeCount).assertEqual(0);
      expect(h.bridge.subscriptionCount()).assertEqual(0);
    });

    it('activate_unknownKey_returnsErr', 0, () => {
      const h: RegistryHarness = newRegistryHarness();
      const result: Result<AccountScope, AppError> = h.registry.activate('ghost');
      expect(result.ok).assertFalse();
      if (result.ok === false) {
        expect(result.error.kind).assertEqual('parameter');
        if (result.error.kind === 'parameter') {
          expect(result.error.code).assertEqual('missing');
        }
      }
    });

    it('hibernate_persistsDisabledAndStopsSubscription', 0, () => {
      const files: FlakyFiles = new FlakyFiles();
      const first: RegistryHarness = newRegistryHarness(files);
      expectScope(first.registry.create('a'));
      expectScope(first.registry.create('b'));
      const b: AccountScope = expectScope(first.registry.hibernate('b'));
      expect(b.lifecycle).assertEqual('hibernating');
      expect(first.bridge.subscriptionCount()).assertEqual(1);

      const second: RegistryHarness = newRegistryHarness(files);
      const report: AccountRestoreReport = second.registry.restoreAll();
      expect(report.failures.length).assertEqual(0);
      expect(report.restored.length).assertEqual(2);
      const restoredB: AccountScope | null = second.registry.get('b');
      expect(restoredB !== null).assertTrue();
      if (restoredB !== null) {
        expect(restoredB.lifecycle).assertEqual('hibernating');
        expect(restoredB.descriptor.enabled).assertFalse();
      }
      expect(second.bridge.subscriptionCount()).assertEqual(1);
    });

    it('activateAfterHibernate_persistsEnabled', 0, () => {
      const files: FlakyFiles = new FlakyFiles();
      const first: RegistryHarness = newRegistryHarness(files);
      expectScope(first.registry.create('a'));
      expectScope(first.registry.hibernate('a'));
      const reactivated: AccountScope = expectScope(first.registry.activate('a'));
      expect(reactivated.lifecycle).assertEqual('active');

      const second: RegistryHarness = newRegistryHarness(files);
      const report: AccountRestoreReport = second.registry.restoreAll();
      expect(report.restored.length).assertEqual(1);
      const restored: AccountScope | null = second.registry.get('a');
      expect(restored !== null).assertTrue();
      if (restored !== null) {
        expect(restored.lifecycle).assertEqual('active');
      }
      expect(second.bridge.subscriptionCount()).assertEqual(1);
    });

    it('close_cancelsPendingExcludesFromListAndManifest', 0, async () => {
      const files: FlakyFiles = new FlakyFiles();
      const first: RegistryHarness = newRegistryHarness(files);
      const scope: AccountScope = expectScope(first.registry.create('a'));
      const requested: Result<TdPendingRequest, AppError> = scope.request('getOption');
      let pending: TdPendingRequest;
      if (requested.ok) {
        pending = requested.value;
      } else {
        expect(requested.ok).assertTrue();
        return;
      }

      const closed: AccountScope = expectScope(first.registry.close('a'));
      expect(closed.lifecycle).assertEqual('closed');
      expect(first.registry.list().length).assertEqual(0);
      const outcome: Result<TdWireObject, AppError> = await pending.promise;
      expect(outcome.ok).assertFalse();
      if (outcome.ok === false) {
        expect(isCancelledRequestError(outcome.error)).assertTrue();
      }

      const second: RegistryHarness = newRegistryHarness(files);
      const report: AccountRestoreReport = second.registry.restoreAll();
      expect(report.restored.length).assertEqual(0);
      expect(report.failures.length).assertEqual(0);
    });

    it('close_isIdempotent_atRegistryLevel', 0, () => {
      const h: RegistryHarness = newRegistryHarness();
      const scope: AccountScope = expectScope(h.registry.create('a'));
      const firstClose: AccountScope = expectScope(h.registry.close('a'));
      const secondClose: AccountScope = expectScope(h.registry.close('a'));
      expect(firstClose === scope).assertTrue();
      expect(secondClose === scope).assertTrue();
      expect(secondClose.lifecycle).assertEqual('closed');
      expect(h.registry.getMetrics().closedCount).assertEqual(1);
    });

    it('close_manifestRemoveFailure_keepsScopeTracked_retryable', 0, () => {
      const files: FlakyFiles = new FlakyFiles();
      const h: RegistryHarness = newRegistryHarness(files);
      expectScope(h.registry.create('a'));
      h.files.failNextWriteFlag = true;
      const failed: Result<AccountScope, AppError> = h.registry.close('a');
      expect(failed.ok).assertFalse();
      const tracked: AccountScope | null = h.registry.get('a');
      expect(tracked !== null).assertTrue();
      if (tracked !== null) {
        expect(tracked.lifecycle).assertEqual('closed');
      }
      const retried: AccountScope = expectScope(h.registry.close('a'));
      expect(retried.lifecycle).assertEqual('closed');
      // close 幂等保留 closed scope 在注册表中，直至被 create 替换。
      const retained: AccountScope | null = h.registry.get('a');
      expect(retained !== null).assertTrue();
      if (retained !== null) {
        expect(retained.lifecycle).assertEqual('closed');
      }
    });

    it('restoreAll_emptyManifest_restoresNothing', 0, () => {
      const h: RegistryHarness = newRegistryHarness();
      const report: AccountRestoreReport = h.registry.restoreAll();
      expect(report.restored.length).assertEqual(0);
      expect(report.failures.length).assertEqual(0);
    });

    it('restoreAll_recoversAccountsWithLifecycleState', 0, () => {
      const files: FlakyFiles = new FlakyFiles();
      const first: RegistryHarness = newRegistryHarness(files);
      const a: AccountScope = expectScope(first.registry.create('a'));
      expectScope(first.registry.create('b'));
      expectScope(first.registry.hibernate('b'));

      const second: RegistryHarness = newRegistryHarness(files);
      const report: AccountRestoreReport = second.registry.restoreAll();
      expect(report.failures.length).assertEqual(0);
      expect(report.restored.length).assertEqual(2);
      const restoredA: AccountScope | null = second.registry.get('a');
      const restoredB: AccountScope | null = second.registry.get('b');
      expect(restoredA !== null).assertTrue();
      expect(restoredB !== null).assertTrue();
      if (restoredA !== null && restoredB !== null) {
        expect(restoredA.accountId).assertEqual(a.accountId);
        expect(restoredA.lifecycle).assertEqual('active');
        expect(restoredB.lifecycle).assertEqual('hibernating');
      }
      expect(second.registry.getMetrics().activeCount).assertEqual(1);
      expect(second.registry.getMetrics().hibernatingCount).assertEqual(1);
    });

    it('restoreAll_singleClientFailure_isolatedPerAccount', 0, () => {
      const files: FlakyFiles = new FlakyFiles();
      const first: RegistryHarness = newRegistryHarness(files);
      expectScope(first.registry.create('r1'));
      expectScope(first.registry.create('r2'));
      expectScope(first.registry.create('r3'));

      const second: RegistryHarness = newRegistryHarness(files);
      second.bridge.failNextCreateClientFlag = true;
      const report: AccountRestoreReport = second.registry.restoreAll();
      expect(report.restored.length).assertEqual(2);
      expect(report.failures.length).assertEqual(1);
      expect(report.failures[0].accountKey).assertEqual('r1');
      expect(report.failures[0].error.kind).assertEqual('platform');
      expect(second.registry.get('r2') !== null).assertTrue();
      expect(second.registry.get('r3') !== null).assertTrue();
      expect(second.registry.get('r1') === null).assertTrue();
    });

    it('restoreAll_manifestReadFailure_reportsSingleFailure', 0, () => {
      const files: FlakyFiles = new FlakyFiles();
      const first: RegistryHarness = newRegistryHarness(files);
      expectScope(first.registry.create('a'));

      const second: RegistryHarness = newRegistryHarness(files);
      second.files.failNextReadFlag = true;
      const report: AccountRestoreReport = second.registry.restoreAll();
      expect(report.restored.length).assertEqual(0);
      expect(report.failures.length).assertEqual(1);
      expect(report.failures[0].accountKey).assertEqual('*');
    });

    it('restoreAll_corruptedManifest_reportsSingleFailure', 0, () => {
      const files: FlakyFiles = new FlakyFiles();
      files.writeText('/sandbox/files/accounts/registry.json', 'garbage{{{');
      const h: RegistryHarness = newRegistryHarness(files);
      const report: AccountRestoreReport = h.registry.restoreAll();
      expect(report.restored.length).assertEqual(0);
      expect(report.failures.length).assertEqual(1);
      if (report.failures.length === 1) {
        expect(report.failures[0].error.kind).assertEqual('storage');
      }
    });

    it('restoreAll_duplicateManagedKey_isolatedAsFailure', 0, () => {
      const files: FlakyFiles = new FlakyFiles();
      const first: RegistryHarness = newRegistryHarness(files);
      expectScope(first.registry.create('dup'));
      expectScope(first.registry.create('other'));

      const second: RegistryHarness = newRegistryHarness(files);
      expectScope(second.registry.create('dup'));
      const report: AccountRestoreReport = second.registry.restoreAll();
      expect(report.restored.length).assertEqual(1);
      expect(report.failures.length).assertEqual(1);
      expect(report.failures[0].accountKey).assertEqual('dup');
      expect(report.failures[0].error.kind).assertEqual('internal');
    });

    it('unknownClientIdEvent_countedAndReported', 0, () => {
      const h: RegistryHarness = newRegistryHarness();
      h.registry.start();
      h.bridge.deliverUpdate(999, 'updateNewMessage', tdWire('{}'));
      expect(h.registry.getMetrics().unknownClientIdEventCount).assertEqual(1);
      expect(h.unknownErrors.length).assertEqual(1);
      expect(h.unknownErrors[0].kind).assertEqual('internal');
    });

    it('knownClientIdEvent_notCounted', 0, () => {
      const h: RegistryHarness = newRegistryHarness();
      h.registry.start();
      const scope: AccountScope = expectScope(h.registry.create('a'));
      h.bridge.deliverUpdate(scope.clientId, 'updateNewMessage', tdWire('{}'));
      expect(h.registry.getMetrics().unknownClientIdEventCount).assertEqual(0);
      expect(h.unknownErrors.length).assertEqual(0);
    });

    it('eventIsolation_accountAEventsNeverReachAccountB', 0, () => {
      const h: RegistryHarness = newRegistryHarness();
      const a: AccountScope = expectScope(h.registry.create('a'));
      const b: AccountScope = expectScope(h.registry.create('b'));
      const receivedA: TdRoutedEvent[] = [];
      const receivedB: TdRoutedEvent[] = [];
      a.subscribeEvents((event: TdRoutedEvent): void => {
        receivedA.push(event);
      });
      b.subscribeEvents((event: TdRoutedEvent): void => {
        receivedB.push(event);
      });
      h.bridge.deliverUpdate(a.clientId, 'updateNewMessage', tdWire('{"chat_id":"1"}'));
      expect(receivedA.length).assertEqual(1);
      expect(receivedB.length).assertEqual(0);
      h.bridge.deliverUpdate(b.clientId, 'updateNewMessage', tdWire('{"chat_id":"2"}'));
      expect(receivedA.length).assertEqual(1);
      expect(receivedB.length).assertEqual(1);
      if (receivedB.length === 1) {
        const payload: TdWireObject = receivedB[0].payload;
        const chatId: string = String(payload['chat_id']);
        expect(chatId).assertEqual('2');
      }
    });

    it('registryStartStop_monitorSubscriptionIdempotent', 0, () => {
      const h: RegistryHarness = newRegistryHarness();
      h.registry.start();
      h.registry.start();
      expect(h.bridge.subscriptionCount()).assertEqual(1);
      expect(h.registry.started).assertTrue();
      h.registry.stop();
      h.registry.stop();
      expect(h.bridge.subscriptionCount()).assertEqual(0);
      expect(h.registry.started).assertFalse();
    });
  });
}

