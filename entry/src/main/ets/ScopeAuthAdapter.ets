import { AppError, Result, err } from '@tgx/core-common';
import {
  AccountScope,
  AuthState,
  AuthorizationStateHolder
} from '@tgx/core-account';
import { TdPendingRequest, TdRoutedEvent, TdWireObject } from '@tgx/td-gateway';
import {
  AuthAccountScopeLike,
  AuthSubscriptionLike
} from '@tgx/feature-auth';

class EventSubscription implements AuthSubscriptionLike {
  private readonly scope: AccountScope;

  constructor(scope: AccountScope) {
    this.scope = scope;
  }

  unsubscribe(): void {
    this.scope.unsubscribeEvents();
  }
}

export class ScopeAuthAdapter implements AuthAccountScopeLike {
  private readonly scope: AccountScope;

  constructor(scope: AccountScope) {
    this.scope = scope;
  }

  get accountId(): string {
    return this.scope.accountId;
  }

  get authorization(): AuthState {
    return this.scope.authorization;
  }

  get authorizationHolder(): AuthorizationStateHolder {
    return this.scope.authorizationHolder;
  }

  request(method: string, params?: TdWireObject): Promise<Result<TdWireObject, AppError>> {
    const result: Result<TdPendingRequest, AppError> = this.scope.request(method, params);
    return result.fold(
      (pending: TdPendingRequest): Promise<Result<TdWireObject, AppError>> => pending.promise,
      (error: AppError): Promise<Result<TdWireObject, AppError>> => Promise.resolve(err<TdWireObject, AppError>(error))
    );
  }

  subscribeEvents(listener: (event: TdRoutedEvent) => void): AuthSubscriptionLike {
    this.scope.subscribeEvents(listener);
    return new EventSubscription(this.scope);
  }

  async getDatabaseEncryptionKeyBase64(): Promise<Result<string, AppError>> {
    return await this.scope.getDatabaseEncryptionKeyBase64();
  }
}
