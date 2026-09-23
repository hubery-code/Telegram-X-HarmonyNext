/**
 * feature/chat — 会话头部标题的落点单元测试（PROF-ENTRY-001）。
 *
 * 守住的行为：私聊/密聊头部点按进「用户资料页」，群与频道仍进「群资料页」。
 * 关键点是 userId 取自 getChat 回包的 `type_.user_id`，**不是**拿 chatId 顶替
 * （密聊的 chatId 与 user_id 是两个数），所以用例专门喂一条假 getChat 回包。
 */

import { describe, it, expect } from '@ohos/hypium';
import { AppError, Result } from '@tgx/core-common';
import { AccountScope, buildAccountDirectories, createDescriptor, AccountDirectoryLayout } from '@tgx/core-account';
import { FakeAppFiles } from '@tgx/platform-ports';
import {
  TdNativeBridgeLike,
  TdNativeBridgeMetrics,
  TdNativeEvent,
  TdNativeEventSink,
  TdWireObject,
  TdWireValue
} from '@tgx/td-gateway';
import { ChatCoordinator, ChatCoordinatorOptions } from '../main/ets/coordinator/ChatCoordinator';
import { OpenChatProfile } from '../main/ets/contract/ChatIntent';

class TestNativeBridge implements TdNativeBridgeLike {
  version: string = '1.8.67-test';
  readonly sent: string[] = [];
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
    this.sent.push(requestUtf8);
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

  /** 回一条带 @extra.requestId 的响应（走 RequestRegistry 关联，非 update 流）。 */
  respondTo(requestId: string, fields: Record<string, TdWireValue>): void {
    const extra: Record<string, TdWireValue> = {};
    extra['requestId'] = requestId;
    const payload: TdWireObject = {};
    for (const key of Object.keys(fields)) {
      payload[key] = fields[key];
    }
    payload['@extra'] = extra;
    const seq: string = String(this.nextSeq);
    this.nextSeq += 1;
    const rawEvent: TdNativeEvent = {
      schemaVersion: 1,
      clientId: 1,
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
}

function createScope(bridge: TestNativeBridge, name: string): AccountScope {
  const layoutRes: Result<AccountDirectoryLayout, AppError> = buildAccountDirectories(name);
  if (layoutRes.ok === false) {
    throw new Error('Failed to build directories');
  }
  const scopeRes: Result<AccountScope, AppError> = AccountScope.open({
    bridge: bridge,
    files: new FakeAppFiles(),
    descriptor: createDescriptor(name, 'acct_user_1', 0, true),
    directories: layoutRes.value,
    startActive: true
  });
  if (scopeRes.ok === false) {
    throw new Error('Failed to open AccountScope');
  }
  return scopeRes.value;
}

/** 取最近一条 getChat 请求的 @extra.requestId。 */
function lastGetChatRequestId(bridge: TestNativeBridge): string {
  for (let i = bridge.sent.length - 1; i >= 0; i--) {
    const req: Record<string, TdWireValue> = JSON.parse(bridge.sent[i]) as Record<string, TdWireValue>;
    if (req['@type'] === 'getChat') {
      const extra: Record<string, TdWireValue> | undefined =
        req['@extra'] as Record<string, TdWireValue> | undefined;
      return extra !== undefined && extra !== null ? String(extra['requestId']) : '';
    }
  }
  return '';
}

function chatResponse(chatId: number, chatType: Record<string, TdWireValue>): Record<string, TdWireValue> {
  const fields: Record<string, TdWireValue> = {};
  fields['@type'] = 'chat';
  fields['id'] = chatId;
  fields['title'] = 'Test';
  fields['type'] = chatType;
  return fields;
}

function privateType(userId: number): Record<string, TdWireValue> {
  const type: Record<string, TdWireValue> = {};
  type['@type'] = 'chatTypePrivate';
  type['user_id'] = userId;
  return type;
}

function supergroupType(isChannel: boolean): Record<string, TdWireValue> {
  const type: Record<string, TdWireValue> = {};
  type['@type'] = 'chatTypeSupergroup';
  type['supergroup_id'] = 777;
  type['is_channel'] = isChannel;
  return type;
}

function settle(): Promise<void> {
  return new Promise<void>((resolve: () => void): void => {
    setTimeout(resolve, 30);
  });
}

export default function privateChatHeaderProfileTest(): void {
  describe('PrivateChatHeaderProfileTest', () => {

    it('privateChatHeader_opensUserProfileWithPeerUserId', 0, async (): Promise<void> => {
      const bridge: TestNativeBridge = new TestNativeBridge();
      const scope: AccountScope = createScope(bridge, 'test_private_header');
      const profileCalls: number[] = [];
      const chatProfileCalls: number[] = [];
      const options: ChatCoordinatorOptions = {
        onOpenUserProfile: (userId: number): void => {
          profileCalls.push(userId);
        },
        onOpenChatProfile: (chatId: number): void => {
          chatProfileCalls.push(chatId);
        }
      };
      const coordinator: ChatCoordinator = new ChatCoordinator(
        scope, 609517172, 'be hu', undefined, undefined, undefined, options);
      coordinator.start();

      const requestId: string = lastGetChatRequestId(bridge);
      expect(requestId.length > 0).assertTrue();
      bridge.respondTo(requestId, chatResponse(609517172, privateType(609517172)));
      await settle();

      coordinator.dispatch(new OpenChatProfile(609517172));
      expect(profileCalls.length).assertEqual(1);
      expect(profileCalls[0]).assertEqual(609517172);
      expect(chatProfileCalls.length).assertEqual(0);

      coordinator.destroy();
    });

    it('groupChatHeader_stillOpensChatProfile', 0, async (): Promise<void> => {
      const bridge: TestNativeBridge = new TestNativeBridge();
      const scope: AccountScope = createScope(bridge, 'test_group_header');
      const profileCalls: number[] = [];
      const chatProfileCalls: number[] = [];
      const options: ChatCoordinatorOptions = {
        onOpenUserProfile: (userId: number): void => {
          profileCalls.push(userId);
        },
        onOpenChatProfile: (chatId: number): void => {
          chatProfileCalls.push(chatId);
        }
      };
      const coordinator: ChatCoordinator = new ChatCoordinator(
        scope, -1001785291444, 'El CLUB', undefined, undefined, undefined, options);
      coordinator.start();

      const requestId: string = lastGetChatRequestId(bridge);
      bridge.respondTo(requestId, chatResponse(-1001785291444, supergroupType(false)));
      await settle();

      coordinator.dispatch(new OpenChatProfile(-1001785291444));
      expect(chatProfileCalls.length).assertEqual(1);
      expect(chatProfileCalls[0]).assertEqual(-1001785291444);
      expect(profileCalls.length).assertEqual(0);

      coordinator.destroy();
    });

    /**
     * 边界：getChat 尚未回包（chatKind 未知）时点头部，仍落群资料页而不是崩、
     * 也不是拿 0 当 userId 跳去一个不存在的资料页。
     */
    it('headerBeforeChatKindResolved_fallsBackToChatProfile', 0, async (): Promise<void> => {
      const bridge: TestNativeBridge = new TestNativeBridge();
      const scope: AccountScope = createScope(bridge, 'test_header_unresolved');
      const profileCalls: number[] = [];
      const chatProfileCalls: number[] = [];
      const options: ChatCoordinatorOptions = {
        onOpenUserProfile: (userId: number): void => {
          profileCalls.push(userId);
        },
        onOpenChatProfile: (chatId: number): void => {
          chatProfileCalls.push(chatId);
        }
      };
      const coordinator: ChatCoordinator = new ChatCoordinator(
        scope, 609517172, 'be hu', undefined, undefined, undefined, options);
      coordinator.start();

      coordinator.dispatch(new OpenChatProfile(609517172));
      expect(chatProfileCalls.length).assertEqual(1);
      expect(profileCalls.length).assertEqual(0);
      await settle();

      coordinator.destroy();
    });
  });
}
