/**
 * entry — AccountSessionCoordinator：多账号会话协调器（FEAT-ACC-002 / FEAT-ACC-003）。
 *
 * 职责：
 * - 管理当前活跃的 AccountScope 与当前账号 accountKey；
 * - 从 AccountRegistry.list() 读取所有非 closed 账号并提供 availableAccounts 清单；
 * - 执行 switchAccount(key)：调用 registry.activate(key) 激活并切换活跃 scope；
 * - 执行 addAccount()：调用 registry.create('account_' + Date.now()) 创建新 scope 并切换；
 * - 纯领域逻辑协调器，0 Kit 依赖，便于全面单测。
 */

import { AppError, Result, ok } from '@tgx/core-common';
import { AccountDescriptor, AccountRegistry, AccountScope } from '@tgx/core-account';

export type ScopeChangeListener = (newScope: AccountScope, isNewAccount: boolean) => void;

export class AccountSessionCoordinator {
  private readonly registry: AccountRegistry;
  private currentScope: AccountScope;
  private currentAccountKey: string;
  private readonly listeners: ScopeChangeListener[] = [];

  constructor(registry: AccountRegistry, initialScope: AccountScope) {
    this.registry = registry;
    this.currentScope = initialScope;
    this.currentAccountKey = initialScope.accountKey;
  }

  getCurrentKey(): string {
    return this.currentAccountKey;
  }

  getActiveScope(): AccountScope {
    return this.currentScope;
  }

  getRegistry(): AccountRegistry {
    return this.registry;
  }

  getAvailableAccounts(): string[] {
    const descriptors: AccountDescriptor[] = this.registry.list();
    const keys: string[] = [];
    for (let i = 0; i < descriptors.length; i++) {
      keys.push(descriptors[i].accountKey);
    }
    if (keys.indexOf(this.currentAccountKey) < 0) {
      keys.push(this.currentAccountKey);
    }
    return keys;
  }

  subscribe(listener: ScopeChangeListener): () => void {
    this.listeners.push(listener);
    return (): void => {
      const idx = this.listeners.indexOf(listener);
      if (idx >= 0) {
        this.listeners.splice(idx, 1);
      }
    };
  }

  switchAccount(accountKey: string): Result<AccountScope, AppError> {
    if (accountKey === this.currentAccountKey) {
      return ok<AccountScope, AppError>(this.currentScope);
    }
    const result: Result<AccountScope, AppError> = this.registry.activate(accountKey);
    if (result.ok) {
      this.currentScope = result.value;
      this.currentAccountKey = accountKey;
      this.notifyListeners(result.value, false);
    }
    return result;
  }

  addAccount(keyPrefix: string = 'account_'): Result<AccountScope, AppError> {
    const newKey: string = keyPrefix + Date.now();
    const result: Result<AccountScope, AppError> = this.registry.create(newKey);
    if (result.ok) {
      this.currentScope = result.value;
      this.currentAccountKey = newKey;
      this.notifyListeners(result.value, true);
    }
    return result;
  }

  private notifyListeners(newScope: AccountScope, isNewAccount: boolean): void {
    for (let i = 0; i < this.listeners.length; i++) {
      this.listeners[i](newScope, isNewAccount);
    }
  }
}
