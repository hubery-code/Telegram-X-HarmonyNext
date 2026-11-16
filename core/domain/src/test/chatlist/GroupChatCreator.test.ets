/**
 * core/domain — GroupChatCreator 单元测试（GROUP-CREATE-101）。
 *
 * 覆盖（对齐 MessageProjection.test 里 FORUM104_* 的「lastSentRequest 断言
 * 编码后 JSON 字段」写法）：
 * 1. createBasicGroup 组包形状：title trim、user_ids 原样携带（可空）、
 *    message_auto_delete_time 默认 0；
 * 2. createSupergroup 组包形状：is_channel/is_forum 标志位、description trim；
 * 3. 本地校验：标题空白 / 超 128 字拒发（请求不出桥）；
 * 4. 边界：恰 128 字放行。
 */

import { describe, it, expect } from '@ohos/hypium';
import {
  AccountScope,
  buildAccountDirectories,
  createDescriptor,
  AccountDirectoryLayout
} from '@tgx/core-account';
import { FakeAppFiles } from '@tgx/platform-ports';
import {
  TdNativeBridgeLike,
  TdNativeBridgeMetrics,
  TdNativeEventSink,
  TdPendingRequest,
  TdWireValue
} from '@tgx/td-gateway';
import { Result, AppError } from '@tgx/core-common';
import {
  GroupChatCreator,
  validateGroupTitle,
  GROUP_TITLE_MAX_LENGTH
} from '../../main/ets/chatlist/GroupChatCreator';

interface SentBridgeRequest {
  readonly clientId: number;
  readonly utf8: string;
}

class TestNativeBridge implements TdNativeBridgeLike {
  version: string = '1.8.67-test';
  readonly sent: SentBridgeRequest[] = [];
  private readonly sinks: Map<number, TdNativeEventSink> = new Map();
  private nextSubId: number = 1;

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
}

function createScope(bridge: TestNativeBridge): AccountScope {
  const layoutRes: Result<AccountDirectoryLayout, AppError> = buildAccountDirectories('test_group_chat_creator');
  if (layoutRes.ok === false) {
    throw new Error('Failed to build directories');
  }
  const scopeRes: Result<AccountScope, AppError> = AccountScope.open({
    bridge: bridge,
    files: new FakeAppFiles(),
    descriptor: createDescriptor('test_group_chat_creator', 'acct_user_1', 0, true),
    directories: layoutRes.value,
    startActive: true
  });
  if (scopeRes.ok === false) {
    throw new Error('Failed to open AccountScope');
  }
  return scopeRes.value;
}

/** 取已发请求的**最后一条**指定类型（同一类型多次发送时，第一条会截住旧请求）。 */
function lastSentRequest(bridge: TestNativeBridge, type: string): Record<string, TdWireValue> | null {
  for (let i = bridge.sent.length - 1; i >= 0; i--) {
    const json: Record<string, TdWireValue> = JSON.parse(bridge.sent[i].utf8) as Record<string, TdWireValue>;
    if (json['@type'] === type) {
      return json;
    }
  }
  return null;
}

export default function groupChatCreatorTest(): void {
  describe('GroupChatCreatorTest', () => {

    it('GROUPCREATE_validateGroupTitleEmptyAndOverlongRejected', 0, (): void => {
      expect(validateGroupTitle('   ') !== null).assertTrue();
      expect(validateGroupTitle('') !== null).assertTrue();
      const overlong: string = 'a'.repeat(GROUP_TITLE_MAX_LENGTH + 1);
      expect(validateGroupTitle(overlong) !== null).assertTrue();
      expect(validateGroupTitle('  Ok  ') === null).assertTrue();
    });

    it('GROUPCREATE_basicGroupSendsTrimmedTitleAndUserIds', 0, (): void => {
      const bridge: TestNativeBridge = new TestNativeBridge();
      const scope: AccountScope = createScope(bridge);
      const creator: GroupChatCreator = new GroupChatCreator(scope);

      const result: Result<TdPendingRequest, AppError> =
        creator.createBasicGroup('  Test Group  ', [101, 202]);
      expect(result.ok).assertTrue();

      const req: Record<string, TdWireValue> | null = lastSentRequest(bridge, 'createNewBasicGroupChat');
      expect(req !== null).assertTrue();
      if (req !== null) {
        expect(req['title']).assertEqual('Test Group');
        const userIds: TdWireValue[] = req['user_ids'] as TdWireValue[];
        expect(userIds.length).assertEqual(2);
        expect(userIds[0]).assertEqual(101);
        expect(userIds[1]).assertEqual(202);
        // 本端 v1 不开自动删除：缺省 0
        expect(req['message_auto_delete_time']).assertEqual(0);
      }
      scope.close();
    });

    it('GROUPCREATE_basicGroupAllowsEmptyUserIds', 0, (): void => {
      const bridge: TestNativeBridge = new TestNativeBridge();
      const scope: AccountScope = createScope(bridge);
      const creator: GroupChatCreator = new GroupChatCreator(scope);

      const result: Result<TdPendingRequest, AppError> = creator.createBasicGroup('Empty Group', []);
      expect(result.ok).assertTrue();

      const req: Record<string, TdWireValue> | null = lastSentRequest(bridge, 'createNewBasicGroupChat');
      expect(req !== null).assertTrue();
      if (req !== null) {
        const userIds: TdWireValue[] = req['user_ids'] as TdWireValue[];
        expect(userIds.length).assertEqual(0);
      }
      scope.close();
    });

    it('GROUPCREATE_basicGroupRejectsInvalidTitleWithoutSending', 0, (): void => {
      const bridge: TestNativeBridge = new TestNativeBridge();
      const scope: AccountScope = createScope(bridge);
      const creator: GroupChatCreator = new GroupChatCreator(scope);

      const empty: Result<TdPendingRequest, AppError> = creator.createBasicGroup('   ', [1]);
      expect(empty.err).assertTrue();

      const overlong: string = 'b'.repeat(GROUP_TITLE_MAX_LENGTH + 1);
      const long: Result<TdPendingRequest, AppError> = creator.createBasicGroup(overlong, [1]);
      expect(long.err).assertTrue();

      // 本端先拦：请求根本不出桥
      expect(lastSentRequest(bridge, 'createNewBasicGroupChat')).assertNull();
      scope.close();
    });

    it('GROUPCREATE_titleAt128BoundaryIsAccepted', 0, (): void => {
      const bridge: TestNativeBridge = new TestNativeBridge();
      const scope: AccountScope = createScope(bridge);
      const creator: GroupChatCreator = new GroupChatCreator(scope);

      const boundary: string = 'c'.repeat(GROUP_TITLE_MAX_LENGTH);
      const result: Result<TdPendingRequest, AppError> = creator.createBasicGroup(boundary, []);
      expect(result.ok).assertTrue();
      scope.close();
    });

    it('GROUPCREATE_supergroupChannelFlagAndDescription', 0, (): void => {
      const bridge: TestNativeBridge = new TestNativeBridge();
      const scope: AccountScope = createScope(bridge);
      const creator: GroupChatCreator = new GroupChatCreator(scope);

      const result: Result<TdPendingRequest, AppError> =
        creator.createSupergroup('  My Channel  ', true, '  About us  ');
      expect(result.ok).assertTrue();

      const req: Record<string, TdWireValue> | null = lastSentRequest(bridge, 'createNewSupergroupChat');
      expect(req !== null).assertTrue();
      if (req !== null) {
        expect(req['title']).assertEqual('My Channel');
        expect(req['is_channel']).assertEqual(true);
        // 本端 v1 不建论坛群
        expect(req['is_forum']).assertEqual(false);
        expect(req['description']).assertEqual('About us');
        // 非地理位置群：location 恒 null
        expect(req['location'] === null).assertTrue();
      }
      scope.close();
    });

    it('GROUPCREATE_supergroupGroupModeSendsChannelFalse', 0, (): void => {
      const bridge: TestNativeBridge = new TestNativeBridge();
      const scope: AccountScope = createScope(bridge);
      const creator: GroupChatCreator = new GroupChatCreator(scope);

      const result: Result<TdPendingRequest, AppError> = creator.createSupergroup('Super Group', false);
      expect(result.ok).assertTrue();

      const req: Record<string, TdWireValue> | null = lastSentRequest(bridge, 'createNewSupergroupChat');
      expect(req !== null).assertTrue();
      if (req !== null) {
        expect(req['is_channel']).assertEqual(false);
        // description 缺省空串（TDLib 侧无简介）
        expect(req['description']).assertEqual('');
      }
      scope.close();
    });
  });
}
