/**
 * feature/chat — SEARCH-102：搜索结果 → 会话内定位（进会话跳转）单元测试。
 *
 * 回归点：从全局搜索结果进入会话时，目标消息往往还没进本地缓存，而首屏
 * getChatHistory 正在飞——投影此时会拒绝新的历史请求（loadHistoryAround 返回
 * null）。旧实现直接"放弃本次跳转"，于是点搜索结果进会话后停在最新消息处。
 * 修复后目标先排队，投影空闲（首屏回包）时自动补发围绕目标的历史请求。
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
  TdNativeEvent,
  TdNativeEventSink,
  TdWireObject,
  TdWireValue
} from '@tgx/td-gateway';
import { Result, AppError, ManualClock, SequentialIdGenerator } from '@tgx/core-common';
import { ReducerEnv } from '@tgx/feature-template';
import { ChatCoordinator } from '../main/ets/coordinator/ChatCoordinator';

const TEST_CHAT_ID: number = 42;
const TEST_TARGET_MESSAGE_ID: number = 5000;

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

  /** 模拟 TDLib 回包（带 @extra.requestId 即被网关识别为响应）。 */
  emitResponse(clientId: number, type: string, fields: Record<string, TdWireValue>): void {
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

  /** 已发出的 getChatHistory 请求（按发送顺序）。 */
  historyRequests(): Record<string, TdWireValue>[] {
    const out: Record<string, TdWireValue>[] = [];
    for (let i = 0; i < this.sent.length; i++) {
      const req: Record<string, TdWireValue> = JSON.parse(this.sent[i]) as Record<string, TdWireValue>;
      if (req['@type'] === 'getChatHistory') {
        out.push(req);
      }
    }
    return out;
  }
}

function createScope(bridge: TestNativeBridge): AccountScope {
  const layoutRes: Result<AccountDirectoryLayout, AppError> = buildAccountDirectories('test_search_jump');
  if (layoutRes.ok === false) {
    throw new Error('Failed to build directories');
  }
  const scopeRes: Result<AccountScope, AppError> = AccountScope.open({
    bridge: bridge,
    files: new FakeAppFiles(),
    descriptor: createDescriptor('test_search_jump', 'acct_user_1', 0, true),
    directories: layoutRes.value,
    startActive: true
  });
  if (scopeRes.ok === false) {
    throw new Error('Failed to open AccountScope');
  }
  return scopeRes.value;
}

function requestIdOf(request: Record<string, TdWireValue>): string {
  const extra: TdWireValue | undefined = request['@extra'];
  if (extra === undefined || extra === null || Array.isArray(extra) || typeof extra !== 'object') {
    return '';
  }
  const obj: TdWireObject = extra as TdWireObject;
  const id: TdWireValue | undefined = obj['requestId'];
  return typeof id === 'string' ? id : '';
}

function makeEnv(): ReducerEnv {
  return {
    clock: new ManualClock(1000, 500),
    ids: new SequentialIdGenerator('test-')
  };
}

function tick(millis: number = 60): Promise<void> {
  return new Promise<void>((resolve) => setTimeout(resolve, millis));
}

export default function chatSearchJumpTest(): void {
  describe('ChatSearchJumpTest', () => {

    it('requestJumpToMessage_queuesWhileInitialLoadInFlight', 0, async (): Promise<void> => {
      const bridge: TestNativeBridge = new TestNativeBridge();
      const scope: AccountScope = createScope(bridge);
      const coordinator: ChatCoordinator = new ChatCoordinator(
        scope, TEST_CHAT_ID, 'Test Chat', undefined, undefined, makeEnv()
      );

      coordinator.start();
      const initial: Record<string, TdWireValue>[] = bridge.historyRequests();
      expect(initial.length).assertEqual(1);
      expect(initial[0]['from_message_id']).assertEqual(0);
      const initialRequestId: string = requestIdOf(initial[0]);
      expect(initialRequestId.length > 0).assertTrue();

      // 目标未载入且首屏在飞：只排队，不得发请求也不得报错。
      coordinator.requestJumpToMessage(TEST_TARGET_MESSAGE_ID);
      expect(bridge.historyRequests().length).assertEqual(1);

      // 首屏回包 → 投影空闲 → 自动补发围绕目标的历史（负 offset，limit=2*radius）。
      const extra: TdWireObject = {};
      extra['requestId'] = initialRequestId;
      const emptyMessages: TdWireValue[] = [];
      const responseFields: Record<string, TdWireValue> = {};
      responseFields['total_count'] = 0;
      responseFields['messages'] = emptyMessages;
      responseFields['@extra'] = extra;
      bridge.emitResponse(scope.clientId, 'messages', responseFields);
      await tick();

      const requests: Record<string, TdWireValue>[] = bridge.historyRequests();
      expect(requests.length).assertEqual(2);
      expect(requests[1]['chat_id']).assertEqual(TEST_CHAT_ID);
      expect(requests[1]['from_message_id']).assertEqual(TEST_TARGET_MESSAGE_ID);
      expect(requests[1]['offset']).assertEqual(-30);
      expect(requests[1]['limit']).assertEqual(60);
      coordinator.destroy();
    });

    it('requestJumpToMessage_ignoresNonPositiveId', 0, (): void => {
      const bridge: TestNativeBridge = new TestNativeBridge();
      const scope: AccountScope = createScope(bridge);
      const coordinator: ChatCoordinator = new ChatCoordinator(
        scope, TEST_CHAT_ID, 'Test Chat', undefined, undefined, makeEnv()
      );

      coordinator.start();
      const before: number = bridge.historyRequests().length;
      coordinator.requestJumpToMessage(0);
      coordinator.requestJumpToMessage(-3);
      expect(bridge.historyRequests().length).assertEqual(before);
      coordinator.destroy();
    });

    it('requestJumpToMessage_afterDestroy_isIgnored', 0, (): void => {
      const bridge: TestNativeBridge = new TestNativeBridge();
      const scope: AccountScope = createScope(bridge);
      const coordinator: ChatCoordinator = new ChatCoordinator(
        scope, TEST_CHAT_ID, 'Test Chat', undefined, undefined, makeEnv()
      );

      coordinator.start();
      coordinator.destroy();
      const before: number = bridge.historyRequests().length;
      coordinator.requestJumpToMessage(TEST_TARGET_MESSAGE_ID);
      expect(bridge.historyRequests().length).assertEqual(before);
    });
  });
}
