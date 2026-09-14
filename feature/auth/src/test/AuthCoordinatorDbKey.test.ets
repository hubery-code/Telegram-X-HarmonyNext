import { describe, it, expect } from '@ohos/hypium';
import {
  AppError,
  AppErrors,
  ManualClock,
  Result,
  SequentialIdGenerator,
  ok,
  err
} from '@tgx/core-common';
import {
  AuthState,
  AuthorizationStateHolder
} from '@tgx/core-account';
import { ReducerEnv } from '@tgx/feature-template';
import { TdRoutedEvent, TdWireObject } from '@tgx/td-gateway';
import {
  AuthAccountScopeLike,
  AuthCoordinator,
  AuthSubscriptionLike,
  TdlibParametersConfig
} from '../main/ets/coordinator/AuthCoordinator';

function wireJson(json: string): TdWireObject {
  const parsed: Object = JSON.parse(json);
  return parsed as TdWireObject;
}

interface RecordedRequest {
  readonly method: string;
  readonly params?: TdWireObject;
}

class SimpleSubscription implements AuthSubscriptionLike {
  private readonly onUnsub: () => void;

  constructor(onUnsub: () => void) {
    this.onUnsub = onUnsub;
  }

  unsubscribe(): void {
    this.onUnsub();
  }
}

class TestRoutedEvent implements TdRoutedEvent {
  readonly clientId: number = 1;
  readonly sequence: string = '1';
  readonly type: string = 'updateAuthorizationState';
  readonly payload: TdWireObject;

  constructor(payload: TdWireObject) {
    this.payload = payload;
  }
}

class MockDbKeyScope implements AuthAccountScopeLike {
  readonly accountId: string = 'db-key-scope-test';
  readonly authorizationHolder: AuthorizationStateHolder = new AuthorizationStateHolder();
  readonly requests: RecordedRequest[] = [];
  readonly eventListeners: Array<(event: TdRoutedEvent) => void> = [];

  keyBase64Result: Result<string, AppError> = ok('bW9ja19lbmNyeXB0aW9uX2tleV8zMmJ5dGVzX2FzZGY=');
  simulateLegacyMigration: boolean = false;
  failBothKeyAndEmpty: boolean = false;

  get authorization(): AuthState {
    return this.authorizationHolder.current;
  }

  async getDatabaseEncryptionKeyBase64(): Promise<Result<string, AppError>> {
    return this.keyBase64Result;
  }

  request(method: string, params?: TdWireObject): Promise<Result<TdWireObject, AppError>> {
    this.requests.push({ method: method, params: params });

    if (method === 'setTdlibParameters') {
      const record: Record<string, Object> = params as Record<string, Object>;
      const key: string = (record['database_encryption_key'] as string) ?? '';

      if (this.failBothKeyAndEmpty) {
        return Promise.resolve(err(AppErrors.tdlib('unauthorized', 'Wrong database encryption key (401)', false)));
      }

      if (this.simulateLegacyMigration) {
        // 当传入非空 key 时报 401，传入空 key 时成功（模拟旧未加密库）
        if (key.length > 0) {
          return Promise.resolve(err(AppErrors.tdlib('unauthorized', 'Wrong database encryption key (401)', false)));
        } else {
          return Promise.resolve(ok(wireJson('{"@type":"ok"}')));
        }
      }
    }

    if (method === 'setDatabaseEncryptionKey') {
      return Promise.resolve(ok(wireJson('{"@type":"ok"}')));
    }

    return Promise.resolve(ok(wireJson('{"@type":"ok"}')));
  }

  subscribeEvents(listener: (event: TdRoutedEvent) => void): AuthSubscriptionLike {
    this.eventListeners.push(listener);
    return new SimpleSubscription(() => {
      const idx: number = this.eventListeners.indexOf(listener);
      if (idx >= 0) {
        this.eventListeners.splice(idx, 1);
      }
    });
  }

  emitWaitTdlibParameters(): void {
    const payload: TdWireObject = wireJson('{"@type":"updateAuthorizationState","authorization_state":{"@type":"authorizationStateWaitTdlibParameters"}}');
    const event: TdRoutedEvent = new TestRoutedEvent(payload);
    for (const l of this.eventListeners) {
      l(event);
    }
  }
}

function createCoordinator(scope: MockDbKeyScope): AuthCoordinator {
  const env: ReducerEnv = {
    clock: new ManualClock(1000, 500),
    ids: new SequentialIdGenerator('test-')
  };
  const config: TdlibParametersConfig = {
    apiId: 12345,
    apiHash: 'test_api_hash',
    databaseDirectory: '/data/user/0/db',
    filesDirectory: '/data/user/0/files',
    systemLanguageCode: 'en',
    deviceModel: 'Test Device',
    applicationVersion: '1.0.0',
    useTestDc: false
  };
  return new AuthCoordinator({
    scope: scope,
    env: env,
    tdlibParameters: config
  });
}

export default function authCoordinatorDbKeyTest() {
  describe('AuthCoordinatorDbKeyTest', () => {
    it('normalStart_injectsBase64EncryptionKeyIntoTdlibParameters', 0, async () => {
      const scope: MockDbKeyScope = new MockDbKeyScope();
      const coord: AuthCoordinator = createCoordinator(scope);
      coord.start();

      scope.emitWaitTdlibParameters();
      await new Promise<void>((resolve) => setTimeout(resolve, 20));

      expect(scope.requests.length).assertEqual(1);
      const req: RecordedRequest = scope.requests[0];
      expect(req.method).assertEqual('setTdlibParameters');

      const params: Record<string, Object> = req.params as Record<string, Object>;
      expect(params['database_encryption_key']).assertEqual('bW9ja19lbmNyeXB0aW9uX2tleV8zMmJ5dGVzX2FzZGY=');
      expect(params['api_id']).assertEqual(12345);

      coord.destroy();
    });

    it('legacyDatabase_detects401AndExecutesOnlineEncryptionMigration', 0, async () => {
      const scope: MockDbKeyScope = new MockDbKeyScope();
      scope.simulateLegacyMigration = true;

      const coord: AuthCoordinator = createCoordinator(scope);
      coord.start();

      scope.emitWaitTdlibParameters();
      await new Promise<void>((resolve) => setTimeout(resolve, 50));

      // 预期调用链：
      // 1. setTdlibParameters (带 key) -> 401 失败
      // 2. setTdlibParameters (空 key) -> 成功（探针确认是旧库）
      // 3. setDatabaseEncryptionKey (目标 key) -> 在线重加密迁移成功
      expect(scope.requests.length).assertEqual(3);

      expect(scope.requests[0].method).assertEqual('setTdlibParameters');
      const p0: Record<string, Object> = scope.requests[0].params as Record<string, Object>;
      expect(p0['database_encryption_key']).assertEqual('bW9ja19lbmNyeXB0aW9uX2tleV8zMmJ5dGVzX2FzZGY=');

      expect(scope.requests[1].method).assertEqual('setTdlibParameters');
      const p1: Record<string, Object> = scope.requests[1].params as Record<string, Object>;
      expect(p1['database_encryption_key']).assertEqual('');

      expect(scope.requests[2].method).assertEqual('setDatabaseEncryptionKey');
      const p2: Record<string, Object> = scope.requests[2].params as Record<string, Object>;
      expect(p2['new_encryption_key']).assertEqual('bW9ja19lbmNyeXB0aW9uX2tleV8zMmJ5dGVzX2FzZGY=');

      // 迁移成功，未触发 UI 错误
      expect(coord.state.errorMessage).assertEqual(null);

      coord.destroy();
    });

    it('wrongKey_bothKeyAndEmptyFail_dispatchesError', 0, async () => {
      const scope: MockDbKeyScope = new MockDbKeyScope();
      scope.failBothKeyAndEmpty = true;

      const coord: AuthCoordinator = createCoordinator(scope);
      coord.start();

      scope.emitWaitTdlibParameters();
      await new Promise<void>((resolve) => setTimeout(resolve, 50));

      // 尝试带 key 失败，尝试空 key 也失败，派发错误
      expect(scope.requests.length).assertEqual(2);
      expect(coord.state.errorMessage !== null).assertTrue();

      coord.destroy();
    });

    it('keyRetrievalLocked_dispatchesErrorGracefully', 0, async () => {
      const scope: MockDbKeyScope = new MockDbKeyScope();
      scope.keyBase64Result = err(AppErrors.platform(48151623, 'device is locked', true));

      const coord: AuthCoordinator = createCoordinator(scope);
      coord.start();

      scope.emitWaitTdlibParameters();
      await new Promise<void>((resolve) => setTimeout(resolve, 20));

      // 无法获取密钥，派发错误，未发出底层请求
      expect(scope.requests.length).assertEqual(0);
      expect(coord.state.errorMessage !== null).assertTrue();

      coord.destroy();
    });
  });
}
