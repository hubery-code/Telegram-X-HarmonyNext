/**
 * entry — MultiAccountFlow.test.ets：多账号切换与添加流程单元测试（FEAT-ACC-002 / FEAT-ACC-003）。
 */

import { describe, it, expect } from '@ohos/hypium';
import { ManualClock, Result, AppError } from '@tgx/core-common';
import {
  AccountRegistry,
  AccountRegistryOptions,
  AccountRestoreReport,
  AccountScope
} from '@tgx/core-account';
import { FakeAppFiles } from '@tgx/platform-ports';
import { FakeAccountBridge } from '../lifecycle/FakeAccountBridge';
import { AccountSessionCoordinator } from '../../main/ets/account/AccountSessionCoordinator';

class MultiAccountHarness {
  readonly bridge: FakeAccountBridge;
  readonly files: FakeAppFiles;
  readonly clock: ManualClock;
  readonly registry: AccountRegistry;

  constructor(bridge: FakeAccountBridge, files: FakeAppFiles, clock: ManualClock, registry: AccountRegistry) {
    this.bridge = bridge;
    this.files = files;
    this.clock = clock;
    this.registry = registry;
  }
}

function createHarness(files?: FakeAppFiles): MultiAccountHarness {
  const bridge: FakeAccountBridge = new FakeAccountBridge();
  const sharedFiles: FakeAppFiles = files !== undefined ? files : new FakeAppFiles();
  const clock: ManualClock = new ManualClock(1000, 100);

  const options: AccountRegistryOptions = {
    bridge: bridge,
    files: sharedFiles,
    clock: clock
  };
  const registry: AccountRegistry = new AccountRegistry(options);
  registry.start();

  return new MultiAccountHarness(bridge, sharedFiles, clock, registry);
}

function expectScope(result: Result<AccountScope, AppError>): AccountScope {
  if (result.ok) {
    return result.value;
  }
  expect(result.ok).assertTrue();
  throw new Error('unreachable: expected ok result');
}

export default function multiAccountFlowTest(): void {
  describe('MultiAccountFlow', () => {

    it('initializes with primary account in availableAccounts', 0, () => {
      const h: MultiAccountHarness = createHarness();
      const primaryScope: AccountScope = expectScope(h.registry.create('default'));

      const session: AccountSessionCoordinator = new AccountSessionCoordinator(h.registry, primaryScope);
      expect(session.getCurrentKey()).assertEqual('default');
      expect(session.getActiveScope() === primaryScope).assertTrue();

      const accounts: string[] = session.getAvailableAccounts();
      expect(accounts.length).assertEqual(1);
      expect(accounts[0]).assertEqual('default');
    });

    it('addAccount creates new scope, switches to it, and notifies listener', 0, () => {
      const h: MultiAccountHarness = createHarness();
      const primaryScope: AccountScope = expectScope(h.registry.create('default'));
      const session: AccountSessionCoordinator = new AccountSessionCoordinator(h.registry, primaryScope);

      let notifiedScope: AccountScope | null = null;
      let notifiedIsNew: boolean = false;
      session.subscribe((newScope: AccountScope, isNew: boolean): void => {
        notifiedScope = newScope;
        notifiedIsNew = isNew;
      });

      const addRes: Result<AccountScope, AppError> = session.addAccount('account_test_');
      expect(addRes.ok).assertTrue();

      const newScope: AccountScope = expectScope(addRes);
      expect(newScope.accountKey.startsWith('account_test_')).assertTrue();
      expect(session.getCurrentKey()).assertEqual(newScope.accountKey);
      expect(session.getActiveScope() === newScope).assertTrue();

      expect(notifiedScope === newScope).assertTrue();
      expect(notifiedIsNew).assertTrue();

      const accounts: string[] = session.getAvailableAccounts();
      expect(accounts.length).assertEqual(2);
      expect(accounts.indexOf('default') >= 0).assertTrue();
      expect(accounts.indexOf(newScope.accountKey) >= 0).assertTrue();
    });

    it('switchAccount switches active scope and notifies listener with isNew=false', 0, () => {
      const h: MultiAccountHarness = createHarness();
      const primaryScope: AccountScope = expectScope(h.registry.create('default'));
      const session: AccountSessionCoordinator = new AccountSessionCoordinator(h.registry, primaryScope);

      const secondScope: AccountScope = expectScope(session.addAccount('account_second_'));
      const secondKey: string = secondScope.accountKey;
      expect(session.getCurrentKey()).assertEqual(secondKey);

      let notifiedScope: AccountScope | null = null;
      let notifiedIsNew: boolean = true;
      session.subscribe((newScope: AccountScope, isNew: boolean): void => {
        notifiedScope = newScope;
        notifiedIsNew = isNew;
      });

      const switchRes: Result<AccountScope, AppError> = session.switchAccount('default');
      expect(switchRes.ok).assertTrue();
      expect(session.getCurrentKey()).assertEqual('default');
      expect(session.getActiveScope().accountKey).assertEqual('default');
      expect(notifiedScope !== null && (notifiedScope as AccountScope).accountKey === 'default').assertTrue();
      expect(notifiedIsNew).assertFalse();
    });

    it('switchAccount to current account is an idempotent no-op', 0, () => {
      const h: MultiAccountHarness = createHarness();
      const primaryScope: AccountScope = expectScope(h.registry.create('default'));
      const session: AccountSessionCoordinator = new AccountSessionCoordinator(h.registry, primaryScope);

      let callCount: number = 0;
      session.subscribe((): void => {
        callCount++;
      });

      const switchRes: Result<AccountScope, AppError> = session.switchAccount('default');
      expect(switchRes.ok).assertTrue();
      const switchedScope: AccountScope = expectScope(switchRes);
      expect(switchedScope === primaryScope).assertTrue();
      expect(callCount).assertEqual(0);
    });

    it('switchAccount to non-existent account fails cleanly with error', 0, () => {
      const h: MultiAccountHarness = createHarness();
      const primaryScope: AccountScope = expectScope(h.registry.create('default'));
      const session: AccountSessionCoordinator = new AccountSessionCoordinator(h.registry, primaryScope);

      const switchRes: Result<AccountScope, AppError> = session.switchAccount('non_existent_key');
      expect(switchRes.ok).assertFalse();
      expect(session.getCurrentKey()).assertEqual('default');
      expect(session.getActiveScope() === primaryScope).assertTrue();
    });

    it('multiple accounts can be created and switched between sequentially', 0, () => {
      const h: MultiAccountHarness = createHarness();
      const primaryScope: AccountScope = expectScope(h.registry.create('default'));
      const session: AccountSessionCoordinator = new AccountSessionCoordinator(h.registry, primaryScope);

      const acc1: AccountScope = expectScope(session.addAccount('acc1_'));
      const acc2: AccountScope = expectScope(session.addAccount('acc2_'));

      const accounts: string[] = session.getAvailableAccounts();
      expect(accounts.length).assertEqual(3);

      // Switch to acc1
      expectScope(session.switchAccount(acc1.accountKey));
      expect(session.getCurrentKey()).assertEqual(acc1.accountKey);

      // Switch to default
      expectScope(session.switchAccount('default'));
      expect(session.getCurrentKey()).assertEqual('default');

      // Switch to acc2
      expectScope(session.switchAccount(acc2.accountKey));
      expect(session.getCurrentKey()).assertEqual(acc2.accountKey);
    });

    it('cold start with multiple restored accounts lists all accounts correctly', 0, () => {
      const sharedFiles: FakeAppFiles = new FakeAppFiles();
      const first: MultiAccountHarness = createHarness(sharedFiles);
      expectScope(first.registry.create('user_work'));
      expectScope(first.registry.create('user_personal'));
      expectScope(first.registry.hibernate('user_personal'));

      // Simulate app restart with a fresh harness sharing the same files
      const second: MultiAccountHarness = createHarness(sharedFiles);
      const report: AccountRestoreReport = second.registry.restoreAll();
      expect(report.restored.length).assertEqual(2);
      expect(report.failures.length).assertEqual(0);

      const primaryScope: AccountScope | null = second.registry.get('user_work');
      expect(primaryScope !== null).assertTrue();

      const session: AccountSessionCoordinator = new AccountSessionCoordinator(second.registry, primaryScope as AccountScope);
      expect(session.getCurrentKey()).assertEqual('user_work');

      const accounts: string[] = session.getAvailableAccounts();
      expect(accounts.length).assertEqual(2);
      expect(accounts.indexOf('user_work') >= 0).assertTrue();
      expect(accounts.indexOf('user_personal') >= 0).assertTrue();

      // Switch to hibernating account
      const switchRes: Result<AccountScope, AppError> = session.switchAccount('user_personal');
      expect(switchRes.ok).assertTrue();
      expect(session.getCurrentKey()).assertEqual('user_personal');
      expect(session.getActiveScope().accountKey).assertEqual('user_personal');
      expect(session.getActiveScope().lifecycle).assertEqual('active');
    });

    it('unsubscribe removes listener from session coordinator', 0, () => {
      const h: MultiAccountHarness = createHarness();
      const primaryScope: AccountScope = expectScope(h.registry.create('default'));
      const session: AccountSessionCoordinator = new AccountSessionCoordinator(h.registry, primaryScope);
      const secondScope: AccountScope = expectScope(session.addAccount('second_'));

      let callCount: number = 0;
      const unsub: () => void = session.subscribe((): void => {
        callCount++;
      });

      expectScope(session.switchAccount('default'));
      expect(callCount).assertEqual(1);

      unsub();
      expectScope(session.switchAccount(secondScope.accountKey));
      expect(callCount).assertEqual(1);
    });

  });
}
