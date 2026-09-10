/**
 * core/domain — UserRegistry 单元测试（MSG-102）。
 *
 * 覆盖：
 * 1. 缓存存取与就地更新（putUser, getUser, in-place update）；
 * 2. UpdateUser 事件监听与回调机制（subscribeUser, Gateway updates）；
 * 3. UpdateUserStatus 事件响应与状态刷新；
 * 4. 格式化、首字母与色盘索引辅助函数（formatFullName, getAvatarLetters, getAvatarColorIndex, isOnline）；
 * 5. Subscription 契约与退订（isActive, unsubscribe 幂等, stop 生命周期）；
 * 6. requestUser TDLib 组包及响应结算。
 */

import { describe, it, expect } from '@ohos/hypium';
import {
  User,
  UserStatusOnline,
  UserStatusOffline,
  UserStatusRecently,
  encodeUser,
  encodeGetUser,
  encodeTdUserStatus,
  TdJsonRaw
} from '@tgx/core-td-api-generated';
import {
  AccountScope,
  buildAccountDirectories,
  createDescriptor,
  AccountDirectoryLayout
} from '@tgx/core-account';
import { FakeAppFiles, Subscription } from '@tgx/platform-ports';
import {
  TdNativeBridgeLike,
  TdNativeBridgeMetrics,
  TdNativeEvent,
  TdNativeEventSink,
  TdPendingRequest,
  TdWireObject,
  TdWireValue
} from '@tgx/td-gateway';
import { Result, AppError } from '@tgx/core-common';
import {
  UserRegistry,
  formatFullName,
  getAvatarLetters,
  getAvatarColorIndex,
  isOnline
} from '../../main/ets/user/UserRegistry';

interface SentBridgeRequest {
  readonly clientId: number;
  readonly utf8: string;
}

class TestNativeBridge implements TdNativeBridgeLike {
  version: string = '1.8.67-test';
  readonly sent: SentBridgeRequest[] = [];
  private readonly sinks: Map<number, TdNativeEventSink> = new Map();
  private nextSubId: number = 1;
  private nextSeq: number = 1;

  getVersion(): string {
    return this.version;
  }

  createClient(): number {
    return 1;
  }

  send(clientId: number, requestUtf8: string): void {
    const entry: SentBridgeRequest = { clientId: clientId, utf8: requestUtf8 };
    this.sent.push(entry);
  }

  execute(requestUtf8: string): string | null {
    return '{"@type":"ok"}';
  }

  subscribeUpdates(sink: TdNativeEventSink): number {
    const id: number = this.nextSubId;
    this.nextSubId += 1;
    this.sinks.set(id, sink);
    return id;
  }

  unsubscribe(subscriptionId: number): void {
    this.sinks.delete(subscriptionId);
  }

  getMetrics(): TdNativeBridgeMetrics {
    return {
      queueSize: 0,
      overflowWaitCount: 0,
      droppedCount: 0,
      eventsForwarded: 0,
      subscriptions: this.sinks.size,
      dispatcherRunning: true
    };
  }

  emitUpdate(clientId: number, type: string, fields: Record<string, TdWireValue>): void {
    const payload: TdWireObject = {};
    for (const key of Object.keys(fields)) {
      payload[key] = fields[key];
    }
    payload['@type'] = type;
    const seq: string = String(this.nextSeq);
    this.nextSeq += 1;

    const rawEvent: TdNativeEvent = {
      schemaVersion: 1,
      clientId: clientId,
      sequence: seq,
      payloadUtf8: JSON.stringify(payload),
      receivedAtMonotonicMs: 0
    };

    for (const id of Array.from(this.sinks.keys())) {
      const sink: TdNativeEventSink | undefined = this.sinks.get(id);
      if (sink !== undefined) {
        sink(rawEvent);
      }
    }
  }

  emitResponse(clientId: number, requestId: string, fields: Record<string, TdWireValue>): void {
    const payload: TdWireObject = {};
    for (const key of Object.keys(fields)) {
      payload[key] = fields[key];
    }
    const extra: TdWireObject = {};
    extra['requestId'] = requestId;
    payload['@extra'] = extra;

    const rawEvent: TdNativeEvent = {
      schemaVersion: 1,
      clientId: clientId,
      sequence: '0',
      payloadUtf8: JSON.stringify(payload),
      receivedAtMonotonicMs: 0
    };

    for (const id of Array.from(this.sinks.keys())) {
      const sink: TdNativeEventSink | undefined = this.sinks.get(id);
      if (sink !== undefined) {
        sink(rawEvent);
      }
    }
  }

  lastSentJson(): Record<string, TdWireValue> {
    const last: SentBridgeRequest = this.sent[this.sent.length - 1];
    return JSON.parse(last.utf8) as Record<string, TdWireValue>;
  }
}

function createScope(bridge: TestNativeBridge): AccountScope {
  const layoutRes: Result<AccountDirectoryLayout, AppError> = buildAccountDirectories('test_user_registry');
  if (layoutRes.ok === false) {
    throw new Error('Failed to build directories');
  }
  const scopeRes: Result<AccountScope, AppError> = AccountScope.open({
    bridge: bridge,
    files: new FakeAppFiles(),
    descriptor: createDescriptor('test_user_registry', 'acct_user_1', 0, true),
    directories: layoutRes.value,
    startActive: true
  });
  if (scopeRes.ok === false) {
    throw new Error('Failed to open AccountScope');
  }
  return scopeRes.value;
}

function createSampleUser(
  id: number,
  firstName: string = '',
  lastName: string = '',
  isOnlineUser: boolean = false
): User {
  const user: User = new User();
  user.id = id;
  user.first_name = firstName;
  user.last_name = lastName;
  if (isOnlineUser) {
    const status: UserStatusOnline = new UserStatusOnline();
    status.expires = 1700000000;
    user.status = status;
  } else {
    const status: UserStatusOffline = new UserStatusOffline();
    status.was_online = 1699990000;
    user.status = status;
  }
  return user;
}

function makeUserUpdateFields(userWire: TdWireObject): Record<string, TdWireValue> {
  const fields: Record<string, TdWireValue> = {};
  fields['user'] = userWire;
  return fields;
}

function makeUserStatusUpdateFields(userId: number, statusWire: TdWireObject | null): Record<string, TdWireValue> {
  const fields: Record<string, TdWireValue> = {};
  fields['user_id'] = userId;
  fields['status'] = statusWire;
  return fields;
}

export default function userRegistryTest(): void {
  describe('UserRegistry', (): void => {

    it('should store and retrieve users in cache', 0, (): void => {
      const bridge: TestNativeBridge = new TestNativeBridge();
      const scope: AccountScope = createScope(bridge);
      const registry: UserRegistry = new UserRegistry(scope);

      expect(registry.getUser(1001)).assertNull();

      const user: User = createSampleUser(1001, 'Alice', 'Smith', true);
      registry.putUser(user);

      const cached: User | null = registry.getUser(1001);
      expect(cached !== null).assertTrue();
      if (cached !== null) {
        expect(cached.id).assertEqual(1001);
        expect(cached.first_name).assertEqual('Alice');
        expect(cached.last_name).assertEqual('Smith');
        expect(registry.isOnline(cached)).assertTrue();
      }

      registry.stop();
    });

    it('should update existing user in-place on putUser', 0, (): void => {
      const bridge: TestNativeBridge = new TestNativeBridge();
      const scope: AccountScope = createScope(bridge);
      const registry: UserRegistry = new UserRegistry(scope);

      const user1: User = createSampleUser(2001, 'Bob', 'Dylan', false);
      registry.putUser(user1);

      const cachedRef: User | null = registry.getUser(2001);
      expect(cachedRef !== null).assertTrue();

      const user2: User = createSampleUser(2001, 'Robert', 'Zimmerman', true);
      registry.putUser(user2);

      const cachedAfter: User | null = registry.getUser(2001);
      // Ensure reference identity is preserved
      expect(cachedAfter === cachedRef).assertTrue();
      if (cachedAfter !== null) {
        expect(cachedAfter.first_name).assertEqual('Robert');
        expect(cachedAfter.last_name).assertEqual('Zimmerman');
        expect(registry.isOnline(cachedAfter)).assertTrue();
      }

      registry.stop();
    });

    it('should clear cache and listeners on clear', 0, (): void => {
      const bridge: TestNativeBridge = new TestNativeBridge();
      const scope: AccountScope = createScope(bridge);
      const registry: UserRegistry = new UserRegistry(scope);

      registry.putUser(createSampleUser(3001, 'Charlie', 'Brown'));
      expect(registry.getUser(3001) !== null).assertTrue();

      registry.clear();
      expect(registry.getUser(3001)).assertNull();

      registry.stop();
    });

    it('should handle UpdateUser from Gateway and notify subscribers', 0, (): void => {
      const bridge: TestNativeBridge = new TestNativeBridge();
      const scope: AccountScope = createScope(bridge);
      const registry: UserRegistry = new UserRegistry(scope);

      let callbackCount: number = 0;
      let notifiedUser: User | null = null;
      const sub: Subscription = registry.subscribeUser(4001, (u: User): void => {
        callbackCount += 1;
        notifiedUser = u;
      });

      expect(sub.isActive).assertTrue();

      const user: User = createSampleUser(4001, 'Diana', 'Prince', true);
      const wireUser: Record<string, TdWireValue> = encodeUser(user) as Record<string, TdWireValue>;

      bridge.emitUpdate(scope.clientId, 'updateUser', makeUserUpdateFields(wireUser as TdWireObject));

      expect(callbackCount).assertEqual(1);
      expect(notifiedUser !== null).assertTrue();
      if (notifiedUser !== null) {
        const nu: User = notifiedUser as User;
        expect(nu.id).assertEqual(4001);
        expect(nu.first_name).assertEqual('Diana');
        expect(nu.last_name).assertEqual('Prince');
        expect(registry.isOnline(nu)).assertTrue();
      }

      const cached: User | null = registry.getUser(4001);
      expect(cached !== null).assertTrue();
      if (cached !== null) {
        expect(cached.first_name).assertEqual('Diana');
      }

      sub.unsubscribe();
      registry.stop();
    });

    it('should handle UpdateUserStatus from Gateway and notify subscribers', 0, (): void => {
      const bridge: TestNativeBridge = new TestNativeBridge();
      const scope: AccountScope = createScope(bridge);
      const registry: UserRegistry = new UserRegistry(scope);

      const initialUser: User = createSampleUser(5001, 'Edward', 'Norton', false);
      registry.putUser(initialUser);
      expect(registry.isOnline(initialUser)).assertFalse();

      let callbackCount: number = 0;
      let notifiedUser: User | null = null;
      const sub: Subscription = registry.subscribeUser(5001, (u: User): void => {
        callbackCount += 1;
        notifiedUser = u;
      });

      const onlineStatus: UserStatusOnline = new UserStatusOnline();
      onlineStatus.expires = 1750000000;
      const wireStatus: Record<string, TdJsonRaw> = encodeTdUserStatus(onlineStatus);

      bridge.emitUpdate(scope.clientId, 'updateUserStatus', makeUserStatusUpdateFields(5001, wireStatus as TdWireObject));

      expect(callbackCount).assertEqual(1);
      expect(notifiedUser !== null).assertTrue();
      if (notifiedUser !== null) {
        const nu: User = notifiedUser as User;
        expect(nu.id).assertEqual(5001);
        expect(registry.isOnline(nu)).assertTrue();
      }

      const cached: User | null = registry.getUser(5001);
      expect(cached !== null).assertTrue();
      if (cached !== null) {
        expect(registry.isOnline(cached)).assertTrue();
      }

      sub.unsubscribe();
      registry.stop();
    });

    it('should not notify subscribers of different userIds', 0, (): void => {
      const bridge: TestNativeBridge = new TestNativeBridge();
      const scope: AccountScope = createScope(bridge);
      const registry: UserRegistry = new UserRegistry(scope);

      let callback6001: number = 0;
      let callback6002: number = 0;

      const sub1: Subscription = registry.subscribeUser(6001, (): void => {
        callback6001 += 1;
      });
      const sub2: Subscription = registry.subscribeUser(6002, (): void => {
        callback6002 += 1;
      });

      const user6001: User = createSampleUser(6001, 'Frank', 'Castle');
      bridge.emitUpdate(scope.clientId, 'updateUser', makeUserUpdateFields(encodeUser(user6001) as TdWireObject));

      expect(callback6001).assertEqual(1);
      expect(callback6002).assertEqual(0);

      sub1.unsubscribe();
      sub2.unsubscribe();
      registry.stop();
    });

    it('should support multiple listeners on the same userId', 0, (): void => {
      const bridge: TestNativeBridge = new TestNativeBridge();
      const scope: AccountScope = createScope(bridge);
      const registry: UserRegistry = new UserRegistry(scope);

      let l1Count: number = 0;
      let l2Count: number = 0;

      const sub1: Subscription = registry.subscribeUser(7001, (): void => {
        l1Count += 1;
      });
      const sub2: Subscription = registry.subscribeUser(7001, (): void => {
        l2Count += 1;
      });

      registry.putUser(createSampleUser(7001, 'Grace', 'Hopper'));

      expect(l1Count).assertEqual(1);
      expect(l2Count).assertEqual(1);

      sub1.unsubscribe();
      registry.putUser(createSampleUser(7001, 'Grace', 'Brewster Hopper'));

      expect(l1Count).assertEqual(1);
      expect(l2Count).assertEqual(2);

      sub2.unsubscribe();
      registry.stop();
    });

    it('should properly unsubscribe and handle idempotent unsubscribe', 0, (): void => {
      const bridge: TestNativeBridge = new TestNativeBridge();
      const scope: AccountScope = createScope(bridge);
      const registry: UserRegistry = new UserRegistry(scope);

      let callCount: number = 0;
      const sub: Subscription = registry.subscribeUser(8001, (): void => {
        callCount += 1;
      });

      expect(sub.isActive).assertTrue();
      registry.putUser(createSampleUser(8001, 'Hank', 'Pym'));
      expect(callCount).assertEqual(1);

      sub.unsubscribe();
      expect(sub.isActive).assertFalse();

      // Idempotent call
      sub.unsubscribe();
      expect(sub.isActive).assertFalse();

      registry.putUser(createSampleUser(8001, 'Henry', 'Pym'));
      expect(callCount).assertEqual(1);

      registry.stop();
    });

    it('should stop registry and clear listeners', 0, (): void => {
      const bridge: TestNativeBridge = new TestNativeBridge();
      const scope: AccountScope = createScope(bridge);
      const registry: UserRegistry = new UserRegistry(scope);

      let called: boolean = false;
      registry.subscribeUser(9001, (): void => {
        called = true;
      });

      registry.stop();

      const user: User = createSampleUser(9001, 'Iris', 'West');
      bridge.emitUpdate(scope.clientId, 'updateUser', makeUserUpdateFields(encodeUser(user) as TdWireObject));

      expect(called).assertFalse();
    });

    it('should correctly format full name with formatFullName', 0, (): void => {
      expect(formatFullName(null)).assertEqual('');

      const u1: User = new User();
      u1.first_name = 'John';
      u1.last_name = 'Doe';
      expect(formatFullName(u1)).assertEqual('John Doe');

      const u2: User = new User();
      u2.first_name = 'Alice';
      u2.last_name = '';
      expect(formatFullName(u2)).assertEqual('Alice');

      const u3: User = new User();
      u3.first_name = '';
      u3.last_name = 'Smith';
      expect(formatFullName(u3)).assertEqual('Smith');

      const u4: User = new User();
      u4.first_name = '   Bob   ';
      u4.last_name = '   Dylan   ';
      expect(formatFullName(u4)).assertEqual('Bob Dylan');

      const u5: User = new User();
      u5.first_name = '   ';
      u5.last_name = '   ';
      expect(formatFullName(u5)).assertEqual('');
    });

    it('should correctly extract avatar letters with getAvatarLetters', 0, (): void => {
      expect(getAvatarLetters(null)).assertEqual('');

      const u1: User = new User();
      u1.first_name = 'John';
      u1.last_name = 'Doe';
      expect(getAvatarLetters(u1)).assertEqual('JD');

      const u2: User = new User();
      u2.first_name = 'Telegram X';
      u2.last_name = '';
      expect(getAvatarLetters(u2)).assertEqual('TX');

      const u3: User = new User();
      u3.first_name = 'Alice';
      u3.last_name = '';
      expect(getAvatarLetters(u3)).assertEqual('A');

      const u4: User = new User();
      u4.first_name = '';
      u4.last_name = 'Smith';
      expect(getAvatarLetters(u4)).assertEqual('S');

      const u5: User = new User();
      u5.first_name = 'alice';
      u5.last_name = 'smith';
      expect(getAvatarLetters(u5)).assertEqual('AS');

      const u6: User = new User();
      u6.first_name = '';
      u6.last_name = 'Van Gogh';
      expect(getAvatarLetters(u6)).assertEqual('VG');

      const u7: User = new User();
      u7.first_name = '';
      u7.last_name = '';
      expect(getAvatarLetters(u7)).assertEqual('');

      const u8: User = new User();
      u8.first_name = '张';
      u8.last_name = '三';
      expect(getAvatarLetters(u8)).assertEqual('张三');
    });

    it('should deterministically compute avatar color index in 0..6', 0, (): void => {
      expect(getAvatarColorIndex(0)).assertEqual(0);
      expect(getAvatarColorIndex(1)).assertEqual(1);
      expect(getAvatarColorIndex(6)).assertEqual(6);
      expect(getAvatarColorIndex(7)).assertEqual(0);
      expect(getAvatarColorIndex(8)).assertEqual(1);
      expect(getAvatarColorIndex(13)).assertEqual(6);
      expect(getAvatarColorIndex(14)).assertEqual(0);

      // Negative id
      expect(getAvatarColorIndex(-5)).assertEqual(5);
      expect(getAvatarColorIndex(-7)).assertEqual(0);

      // Non-finite
      expect(getAvatarColorIndex(Number.NaN)).assertEqual(0);

      // Determinism
      const idx1: number = getAvatarColorIndex(1234567);
      const idx2: number = getAvatarColorIndex(1234567);
      expect(idx1).assertEqual(idx2);
      expect(idx1 >= 0 && idx1 <= 6).assertTrue();
    });

    it('should correctly determine online status with isOnline', 0, (): void => {
      expect(isOnline(null)).assertFalse();

      const u1: User = new User();
      u1.status = null;
      expect(isOnline(u1)).assertFalse();

      const u2: User = new User();
      u2.status = new UserStatusOffline();
      expect(isOnline(u2)).assertFalse();

      const u3: User = new User();
      u3.status = new UserStatusOnline();
      expect(isOnline(u3)).assertTrue();

      const u4: User = new User();
      u4.status = new UserStatusRecently();
      expect(isOnline(u4)).assertFalse();
    });

    it('should assemble requestUser request and resolve with decoded User', 0, async (): Promise<void> => {
      const bridge: TestNativeBridge = new TestNativeBridge();
      const scope: AccountScope = createScope(bridge);
      const registry: UserRegistry = new UserRegistry(scope);

      const res: Result<TdPendingRequest, AppError> = registry.requestUser(10001);
      expect(res.ok).assertTrue();

      const sent: Record<string, TdWireValue> = bridge.lastSentJson();
      expect(sent['@type']).assertEqual('getUser');
      expect(sent['user_id']).assertEqual(10001);

      if (res.ok) {
        const requestId: string = res.value.requestId;
        const responseUser: User = createSampleUser(10001, 'Tony', 'Stark', true);
        const wireUser: Record<string, TdWireValue> = encodeUser(responseUser) as Record<string, TdWireValue>;

        bridge.emitResponse(scope.clientId, requestId, wireUser);

        await res.value.promise;

        const cached: User | null = registry.getUser(10001);
        expect(cached !== null).assertTrue();
        if (cached !== null) {
          expect(cached.first_name).assertEqual('Tony');
          expect(cached.last_name).assertEqual('Stark');
          expect(registry.isOnline(cached)).assertTrue();
        }
      }

      registry.stop();
    });

  });
}
