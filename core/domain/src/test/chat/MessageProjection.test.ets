/**
 * core/domain — MessageProjection 单元测试（MSG-104）。
 *
 * 覆盖：
 * 1. start() 发 openChat + getChat，getChat 响应把 last_read_outbox_message_id
 *    灌为初始已读水位（修复"进入会话前已读仍显示单勾"）；
 * 2. updateChatReadOutbox 推进水位：只增不减、变化才 notify、其他 chatId 忽略；
 * 3. markMessagesRead / resendMessages 组包形状与空数组判错。
 */

import { describe, it, expect } from '@ohos/hypium';
import { Chat, encodeChat } from '@tgx/core-td-api-generated';
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
  TdPendingRequest,
  TdWireObject,
  TdWireValue
} from '@tgx/td-gateway';
import { Result, AppError } from '@tgx/core-common';
import { MessageProjection } from '../../main/ets/chat/MessageProjection';

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
  const layoutRes: Result<AccountDirectoryLayout, AppError> = buildAccountDirectories('test_message_projection');
  if (layoutRes.ok === false) {
    throw new Error('Failed to build directories');
  }
  const scopeRes: Result<AccountScope, AppError> = AccountScope.open({
    bridge: bridge,
    files: new FakeAppFiles(),
    descriptor: createDescriptor('test_message_projection', 'acct_user_1', 0, true),
    directories: layoutRes.value,
    startActive: true
  });
  if (scopeRes.ok === false) {
    throw new Error('Failed to open AccountScope');
  }
  return scopeRes.value;
}

function findSentRequest(bridge: TestNativeBridge, type: string): Record<string, TdWireValue> | null {
  for (let i = 0; i < bridge.sent.length; i++) {
    const json: Record<string, TdWireValue> = JSON.parse(bridge.sent[i].utf8) as Record<string, TdWireValue>;
    if (json['@type'] === type) {
      return json;
    }
  }
  return null;
}

function sentRequestId(json: Record<string, TdWireValue>): string {
  const extra: Record<string, TdWireValue> = json['@extra'] as Record<string, TdWireValue>;
  return extra['requestId'] as string;
}

function flushAsync(): Promise<void> {
  return new Promise<void>((resolve: () => void): void => {
    setTimeout((): void => {
      resolve();
    }, 0);
  });
}

function makeReadOutboxFields(chatId: number, lastReadOutbox: number): Record<string, TdWireValue> {
  const fields: Record<string, TdWireValue> = {};
  fields['chat_id'] = chatId;
  fields['last_read_outbox_message_id'] = lastReadOutbox;
  return fields;
}

function makeReadInboxFields(chatId: number, lastReadInbox: number): Record<string, TdWireValue> {
  const fields: Record<string, TdWireValue> = {};
  fields['chat_id'] = chatId;
  fields['last_read_inbox_message_id'] = lastReadInbox;
  fields['unread_count'] = 0;
  return fields;
}

export default function messageProjectionTest(): void {
  describe('MessageProjection', (): void => {

    it('should seed lastReadOutboxMessageId from getChat response on start', 0, async (): Promise<void> => {
      const bridge: TestNativeBridge = new TestNativeBridge();
      const scope: AccountScope = createScope(bridge);
      const projection: MessageProjection = new MessageProjection(42, scope);

      projection.start();

      const openChatReq: Record<string, TdWireValue> | null = findSentRequest(bridge, 'openChat');
      expect(openChatReq !== null).assertTrue();
      const getChatReq: Record<string, TdWireValue> | null = findSentRequest(bridge, 'getChat');
      expect(getChatReq !== null).assertTrue();
      if (getChatReq !== null) {
        expect(getChatReq['chat_id']).assertEqual(42);

        const chat: Chat = new Chat();
        chat.id = 42;
        chat.last_read_outbox_message_id = 555;
        bridge.emitResponse(scope.clientId, sentRequestId(getChatReq),
          encodeChat(chat) as Record<string, TdWireValue>);
        await flushAsync();

        expect(projection.state.lastReadOutboxMessageId).assertEqual(555);
      }

      projection.stop();
    });

    it('should not seed watermark when getChat responds with a different chat', 0, async (): Promise<void> => {
      const bridge: TestNativeBridge = new TestNativeBridge();
      const scope: AccountScope = createScope(bridge);
      const projection: MessageProjection = new MessageProjection(42, scope);

      projection.start();

      const getChatReq: Record<string, TdWireValue> | null = findSentRequest(bridge, 'getChat');
      expect(getChatReq !== null).assertTrue();
      if (getChatReq !== null) {
        const chat: Chat = new Chat();
        chat.id = 999;
        chat.last_read_outbox_message_id = 555;
        bridge.emitResponse(scope.clientId, sentRequestId(getChatReq),
          encodeChat(chat) as Record<string, TdWireValue>);
        await flushAsync();

        expect(projection.state.lastReadOutboxMessageId).assertEqual(0);
      }

      projection.stop();
    });

    it('should advance watermark on updateChatReadOutbox monotonically', 0, (): void => {
      const bridge: TestNativeBridge = new TestNativeBridge();
      const scope: AccountScope = createScope(bridge);
      const projection: MessageProjection = new MessageProjection(42, scope);

      projection.start();

      let notifyCount: number = 0;
      projection.setOnStateChanged((): void => {
        notifyCount += 1;
      });

      bridge.emitUpdate(scope.clientId, 'updateChatReadOutbox', makeReadOutboxFields(42, 700));
      expect(projection.state.lastReadOutboxMessageId).assertEqual(700);
      expect(notifyCount).assertEqual(1);

      // 水位回退：忽略且不通知
      bridge.emitUpdate(scope.clientId, 'updateChatReadOutbox', makeReadOutboxFields(42, 300));
      expect(projection.state.lastReadOutboxMessageId).assertEqual(700);
      expect(notifyCount).assertEqual(1);

      // 相同水位：不重复通知
      bridge.emitUpdate(scope.clientId, 'updateChatReadOutbox', makeReadOutboxFields(42, 700));
      expect(notifyCount).assertEqual(1);

      // 其他 chatId：忽略
      bridge.emitUpdate(scope.clientId, 'updateChatReadOutbox', makeReadOutboxFields(999, 800));
      expect(projection.state.lastReadOutboxMessageId).assertEqual(700);
      expect(notifyCount).assertEqual(1);

      projection.stop();
    });

    it('should keep the higher watermark when getChat seed and updates race', 0, async (): Promise<void> => {
      const bridge: TestNativeBridge = new TestNativeBridge();
      const scope: AccountScope = createScope(bridge);
      const projection: MessageProjection = new MessageProjection(42, scope);

      projection.start();

      bridge.emitUpdate(scope.clientId, 'updateChatReadOutbox', makeReadOutboxFields(42, 900));
      expect(projection.state.lastReadOutboxMessageId).assertEqual(900);

      // getChat 快照滞后于已收到的推送：灌更低水位不得回退
      const getChatReq: Record<string, TdWireValue> | null = findSentRequest(bridge, 'getChat');
      expect(getChatReq !== null).assertTrue();
      if (getChatReq !== null) {
        const chat: Chat = new Chat();
        chat.id = 42;
        chat.last_read_outbox_message_id = 555;
        bridge.emitResponse(scope.clientId, sentRequestId(getChatReq),
          encodeChat(chat) as Record<string, TdWireValue>);
        await flushAsync();

        expect(projection.state.lastReadOutboxMessageId).assertEqual(900);
      }

      projection.stop();
    });

    it('should seed lastReadInboxMessageId from getChat and advance via updateChatReadInbox', 0, async (): Promise<void> => {
      const bridge: TestNativeBridge = new TestNativeBridge();
      const scope: AccountScope = createScope(bridge);
      const projection: MessageProjection = new MessageProjection(42, scope);

      let notifyCount: number = 0;
      projection.setOnStateChanged((): void => {
        notifyCount += 1;
      });

      projection.start();

      const getChatReq: Record<string, TdWireValue> | null = findSentRequest(bridge, 'getChat');
      expect(getChatReq !== null).assertTrue();
      if (getChatReq !== null) {
        const chat: Chat = new Chat();
        chat.id = 42;
        chat.last_read_inbox_message_id = 500;
        bridge.emitResponse(scope.clientId, sentRequestId(getChatReq),
          encodeChat(chat) as Record<string, TdWireValue>);
        await flushAsync();

        expect(projection.state.lastReadInboxMessageId).assertEqual(500);
      }

      // updateChatReadInbox 推进
      const fields600 = makeReadInboxFields(42, 600);
      fields600['unread_count'] = 3;
      bridge.emitUpdate(scope.clientId, 'updateChatReadInbox', fields600);
      expect(projection.state.lastReadInboxMessageId).assertEqual(600);
      expect(projection.state.unreadCount).assertEqual(3);

      // 低水位不回退
      bridge.emitUpdate(scope.clientId, 'updateChatReadInbox', makeReadInboxFields(42, 400));
      expect(projection.state.lastReadInboxMessageId).assertEqual(600);

      projection.stop();
    });

    it('should assemble markMessagesRead as viewMessages and reject empty ids', 0, (): void => {
      const bridge: TestNativeBridge = new TestNativeBridge();
      const scope: AccountScope = createScope(bridge);
      const projection: MessageProjection = new MessageProjection(42, scope);

      const emptyRes: Result<TdPendingRequest, AppError> = projection.markMessagesRead([]);
      expect(emptyRes.ok).assertFalse();
      expect(bridge.sent.length).assertEqual(0);

      const res: Result<TdPendingRequest, AppError> = projection.markMessagesRead([10, 20]);
      expect(res.ok).assertTrue();

      const sent: Record<string, TdWireValue> = bridge.lastSentJson();
      expect(sent['@type']).assertEqual('viewMessages');
      expect(sent['chat_id']).assertEqual(42);
      expect(sent['force_read']).assertEqual(false);
      const ids: number[] = sent['message_ids'] as number[];
      expect(ids.length).assertEqual(2);
      expect(ids[0]).assertEqual(10);
      expect(ids[1]).assertEqual(20);
    });

    it('should assemble resendMessages and reject empty ids', 0, (): void => {
      const bridge: TestNativeBridge = new TestNativeBridge();
      const scope: AccountScope = createScope(bridge);
      const projection: MessageProjection = new MessageProjection(42, scope);

      const emptyRes: Result<TdPendingRequest, AppError> = projection.resendMessages([]);
      expect(emptyRes.ok).assertFalse();
      expect(bridge.sent.length).assertEqual(0);

      const res: Result<TdPendingRequest, AppError> = projection.resendMessages([33]);
      expect(res.ok).assertTrue();

      const sent: Record<string, TdWireValue> = bridge.lastSentJson();
      expect(sent['@type']).assertEqual('resendMessages');
      expect(sent['chat_id']).assertEqual(42);
      const ids: number[] = sent['message_ids'] as number[];
      expect(ids.length).assertEqual(1);
      expect(ids[0]).assertEqual(33);
    });

  });
}
