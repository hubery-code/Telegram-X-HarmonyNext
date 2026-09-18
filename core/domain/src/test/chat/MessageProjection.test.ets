/**
 * core/domain — MessageProjection 单元测试（MSG-104）。
 *
 * 覆盖：
 * 1. start() 发 openChat + getChat，getChat 响应把 last_read_outbox_message_id
 *    灌为初始已读水位（修复"进入会话前已读仍显示单勾"）；
 * 2. updateChatReadOutbox 推进水位：只增不减、变化才 notify、其他 chatId 忽略；
 * 3. markMessagesRead / resendMessages 组包形状与空数组判错；
 * 4. MSG-106：forwardMessages 组包（chat_id/from_chat_id/send_copy）、
 *    空数组与超 100 条判错、message_ids 归一化为严格递增。
 */

import { describe, it, expect } from '@ohos/hypium';
import {
  Chat,
  encodeChat,
  Message,
  DraftMessage,
  DraftMessageContentText,
  FormattedText,
  InputMessageReplyToMessage,
  LinkPreviewOptions,
  UpdateChatDraftMessage,
  encodeUpdateChatDraftMessage
} from '@tgx/core-td-api-generated';
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

    // ---- MSG-106 转发（FEAT-COMP-004）----

    it('should assemble forwardMessages with source chat and copy flag', 0, (): void => {
      const bridge: TestNativeBridge = new TestNativeBridge();
      const scope: AccountScope = createScope(bridge);
      const projection: MessageProjection = new MessageProjection(42, scope);

      const res: Result<TdPendingRequest, AppError> = projection.forwardMessages(777, [10, 11], true);
      expect(res.ok).assertTrue();

      const sent: Record<string, TdWireValue> = bridge.lastSentJson();
      expect(sent['@type']).assertEqual('forwardMessages');
      // chat_id = 目标会话，from_chat_id = 当前投影的会话
      expect(sent['chat_id']).assertEqual(777);
      expect(sent['from_chat_id']).assertEqual(42);
      expect(sent['send_copy']).assertEqual(true);
      expect(sent['remove_caption']).assertEqual(false);
      // topic_id / options 显式 null（非论坛话题、默认发送选项）
      expect(sent['topic_id']).assertNull();
      expect(sent['options']).assertNull();
      const ids: number[] = sent['message_ids'] as number[];
      expect(ids.length).assertEqual(2);
      expect(ids[0]).assertEqual(10);
      expect(ids[1]).assertEqual(11);
    });

    it('should reject forwardMessages with empty ids', 0, (): void => {
      const bridge: TestNativeBridge = new TestNativeBridge();
      const scope: AccountScope = createScope(bridge);
      const projection: MessageProjection = new MessageProjection(42, scope);

      const res: Result<TdPendingRequest, AppError> = projection.forwardMessages(777, [], false);
      expect(res.ok).assertFalse();
      expect(bridge.sent.length).assertEqual(0);
    });

    it('should sort and dedupe forward message ids into strictly increasing order', 0, (): void => {
      const bridge: TestNativeBridge = new TestNativeBridge();
      const scope: AccountScope = createScope(bridge);
      const projection: MessageProjection = new MessageProjection(42, scope);

      // TDLib 要求 message_ids 严格递增：乱序 + 重复必须先归一化
      const res: Result<TdPendingRequest, AppError> =
        projection.forwardMessages(777, [30, 10, 30, 20], false);
      expect(res.ok).assertTrue();

      const sent: Record<string, TdWireValue> = bridge.lastSentJson();
      const ids: number[] = sent['message_ids'] as number[];
      expect(ids.length).assertEqual(3);
      expect(ids[0]).assertEqual(10);
      expect(ids[1]).assertEqual(20);
      expect(ids[2]).assertEqual(30);
    });

    it('should reject forwardMessages beyond the 100 message limit', 0, (): void => {
      const bridge: TestNativeBridge = new TestNativeBridge();
      const scope: AccountScope = createScope(bridge);
      const projection: MessageProjection = new MessageProjection(42, scope);

      const tooMany: number[] = [];
      for (let i = 1; i <= 101; i++) {
        tooMany.push(i);
      }
      const res: Result<TdPendingRequest, AppError> = projection.forwardMessages(777, tooMany, false);
      expect(res.ok).assertFalse();
      expect(bridge.sent.length).assertEqual(0);
    });

    it('should construct valid SendMessage with InputMessagePhoto', 0, (): void => {
      const bridge: TestNativeBridge = new TestNativeBridge();
      const scope: AccountScope = createScope(bridge);
      const projection: MessageProjection = new MessageProjection(42, scope);

      const res: Result<TdPendingRequest, AppError> = projection.sendPhotoMessage(
        '/data/storage/el2/base/photos/test.jpg',
        'Sunset photo',
        100,
        1920,
        1080
      );
      expect(res.ok).assertTrue();

      const sent: Record<string, TdWireValue> = bridge.lastSentJson();
      expect(sent['@type']).assertEqual('sendMessage');
      expect(sent['chat_id']).assertEqual(42);

      const replyTo = sent['reply_to'] as Record<string, TdWireValue>;
      expect(replyTo !== null && replyTo !== undefined).assertTrue();
      expect(replyTo['@type']).assertEqual('inputMessageReplyToMessage');
      expect(replyTo['message_id']).assertEqual(100);

      const content = sent['input_message_content'] as Record<string, TdWireValue>;
      expect(content['@type']).assertEqual('inputMessagePhoto');

      const photo = content['photo'] as Record<string, TdWireValue>;
      expect(photo['@type']).assertEqual('inputPhoto');
      expect(photo['width']).assertEqual(1920);
      expect(photo['height']).assertEqual(1080);

      const file = photo['photo'] as Record<string, TdWireValue>;
      expect(file['@type']).assertEqual('inputFileLocal');
      expect(file['path']).assertEqual('/data/storage/el2/base/photos/test.jpg');

      const caption = content['caption'] as Record<string, TdWireValue>;
      expect(caption !== null && caption !== undefined).assertTrue();
      expect(caption['text']).assertEqual('Sunset photo');
    });

    it('should reject sendPhotoMessage when localPath is empty', 0, (): void => {
      const bridge: TestNativeBridge = new TestNativeBridge();
      const scope: AccountScope = createScope(bridge);
      const projection: MessageProjection = new MessageProjection(42, scope);

      const res: Result<TdPendingRequest, AppError> = projection.sendPhotoMessage('   ', 'Caption');
      expect(res.ok).assertFalse();
      expect(bridge.sent.length).assertEqual(0);
    });

    it('should construct sendPhotoMessage with minimal arguments', 0, (): void => {
      const bridge: TestNativeBridge = new TestNativeBridge();
      const scope: AccountScope = createScope(bridge);
      const projection: MessageProjection = new MessageProjection(42, scope);

      const res: Result<TdPendingRequest, AppError> = projection.sendPhotoMessage('/data/img.png');
      expect(res.ok).assertTrue();

      const sent: Record<string, TdWireValue> = bridge.lastSentJson();
      expect(sent['@type']).assertEqual('sendMessage');
      expect(sent['reply_to']).assertNull();

      const content = sent['input_message_content'] as Record<string, TdWireValue>;
      expect(content['@type']).assertEqual('inputMessagePhoto');
      expect(content['caption']).assertNull();

      const photo = content['photo'] as Record<string, TdWireValue>;
      expect(photo['width']).assertEqual(0);
      expect(photo['height']).assertEqual(0);
      const file = photo['photo'] as Record<string, TdWireValue>;
      expect(file['path']).assertEqual('/data/img.png');
    });

    it('should assemble sendMessage with inputMessageDocument and reply_to', 0, (): void => {
      const bridge: TestNativeBridge = new TestNativeBridge();
      const scope: AccountScope = createScope(bridge);
      const projection: MessageProjection = new MessageProjection(42, scope);

      const res: Result<TdPendingRequest, AppError> = projection.sendDocumentMessage(
        '/data/storage/el2/base/docs/document.pdf',
        'Annual report',
        200
      );
      expect(res.ok).assertTrue();

      const sent: Record<string, TdWireValue> = bridge.lastSentJson();
      expect(sent['@type']).assertEqual('sendMessage');
      expect(sent['chat_id']).assertEqual(42);

      const replyTo = sent['reply_to'] as Record<string, TdWireValue>;
      expect(replyTo !== null && replyTo !== undefined).assertTrue();
      expect(replyTo['@type']).assertEqual('inputMessageReplyToMessage');
      expect(replyTo['message_id']).assertEqual(200);

      const content = sent['input_message_content'] as Record<string, TdWireValue>;
      expect(content['@type']).assertEqual('inputMessageDocument');

      const doc = content['document'] as Record<string, TdWireValue>;
      expect(doc['@type']).assertEqual('inputDocument');

      const file = doc['document'] as Record<string, TdWireValue>;
      expect(file['@type']).assertEqual('inputFileLocal');
      expect(file['path']).assertEqual('/data/storage/el2/base/docs/document.pdf');

      const caption = content['caption'] as Record<string, TdWireValue>;
      expect(caption !== null && caption !== undefined).assertTrue();
      expect(caption['text']).assertEqual('Annual report');
    });

    it('should reject sendDocumentMessage when localPath is empty', 0, (): void => {
      const bridge: TestNativeBridge = new TestNativeBridge();
      const scope: AccountScope = createScope(bridge);
      const projection: MessageProjection = new MessageProjection(42, scope);

      const res: Result<TdPendingRequest, AppError> = projection.sendDocumentMessage('   ', 'Caption');
      expect(res.ok).assertFalse();
      expect(bridge.sent.length).assertEqual(0);
    });

    it('should construct sendDocumentMessage with minimal arguments', 0, (): void => {
      const bridge: TestNativeBridge = new TestNativeBridge();
      const scope: AccountScope = createScope(bridge);
      const projection: MessageProjection = new MessageProjection(42, scope);

      const res: Result<TdPendingRequest, AppError> = projection.sendDocumentMessage('/data/file.zip');
      expect(res.ok).assertTrue();

      const sent: Record<string, TdWireValue> = bridge.lastSentJson();
      expect(sent['@type']).assertEqual('sendMessage');
      expect(sent['reply_to']).assertNull();

      const content = sent['input_message_content'] as Record<string, TdWireValue>;
      expect(content['@type']).assertEqual('inputMessageDocument');
      expect(content['caption']).assertNull();

      const doc = content['document'] as Record<string, TdWireValue>;
      const file = doc['document'] as Record<string, TdWireValue>;
      expect(file['path']).assertEqual('/data/file.zip');
    });

    it('should send setChatDraftMessage with formatted text and reply_to', 0, (): void => {
      const bridge: TestNativeBridge = new TestNativeBridge();
      const scope: AccountScope = createScope(bridge);
      const projection: MessageProjection = new MessageProjection(42, scope);

      const res: Result<TdPendingRequest, AppError> = projection.setChatDraftMessage('Draft text', 123);
      expect(res.ok).assertTrue();

      const sent: Record<string, TdWireValue> = bridge.lastSentJson();
      expect(sent['@type']).assertEqual('setChatDraftMessage');
      expect(sent['chat_id']).assertEqual(42);

      const draft = sent['draft_message'] as Record<string, TdWireValue>;
      expect(draft['@type']).assertEqual('draftMessage');

      const content = draft['content'] as Record<string, TdWireValue>;
      expect(content['@type']).assertEqual('draftMessageContentText');
      const textObj = content['text'] as Record<string, TdWireValue>;
      expect(textObj['text']).assertEqual('Draft text');

      const replyTo = draft['reply_to'] as Record<string, TdWireValue>;
      expect(replyTo['@type']).assertEqual('inputMessageReplyToMessage');
      expect(replyTo['message_id']).assertEqual(123);
    });

    it('should send setChatDraftMessage with null draft_message on clearChatDraftMessage', 0, (): void => {
      const bridge: TestNativeBridge = new TestNativeBridge();
      const scope: AccountScope = createScope(bridge);
      const projection: MessageProjection = new MessageProjection(42, scope);

      const res: Result<TdPendingRequest, AppError> = projection.clearChatDraftMessage();
      expect(res.ok).assertTrue();

      const sent: Record<string, TdWireValue> = bridge.lastSentJson();
      expect(sent['@type']).assertEqual('setChatDraftMessage');
      expect(sent['chat_id']).assertEqual(42);
      expect(sent['draft_message']).assertNull();
    });

    it('should seed initialDraft from getChat and update on updateChatDraftMessage', 0, async (): Promise<void> => {
      const bridge: TestNativeBridge = new TestNativeBridge();
      const scope: AccountScope = createScope(bridge);
      const projection: MessageProjection = new MessageProjection(42, scope);

      let loadedDraft: DraftMessage | null = null;
      projection.setOnDraftLoaded((draft: DraftMessage | null): void => {
        loadedDraft = draft;
      });

      projection.start();

      const getChatReq: Record<string, TdWireValue> | null = findSentRequest(bridge, 'getChat');
      expect(getChatReq !== null).assertTrue();
      if (getChatReq !== null) {
        const chat: Chat = new Chat();
        chat.id = 42;
        const draft: DraftMessage = new DraftMessage();
        const content: DraftMessageContentText = new DraftMessageContentText();
        const formatted: FormattedText = new FormattedText();
        formatted.text = 'Restored draft';
        content.text = formatted;
        draft.content = content;
        chat.draft_message = draft;

        bridge.emitResponse(scope.clientId, sentRequestId(getChatReq),
          encodeChat(chat) as Record<string, TdWireValue>);
        await flushAsync();

        expect(projection.getInitialDraft() !== null).assertTrue();
        expect(loadedDraft !== null).assertTrue();
        const loadedContent = loadedDraft!.content as DraftMessageContentText;
        expect(loadedContent.text!.text).assertEqual('Restored draft');
      }

      // 增量 updateChatDraftMessage 驱动
      const updateDraft: DraftMessage = new DraftMessage();
      const updatedContent: DraftMessageContentText = new DraftMessageContentText();
      const updatedFormatted: FormattedText = new FormattedText();
      updatedFormatted.text = 'Live draft update';
      updatedContent.text = updatedFormatted;
      updateDraft.content = updatedContent;

      const draftUpdate: UpdateChatDraftMessage = new UpdateChatDraftMessage();
      draftUpdate.chat_id = 42;
      draftUpdate.draft_message = updateDraft;

      bridge.emitUpdate(scope.clientId, 'updateChatDraftMessage',
        encodeUpdateChatDraftMessage(draftUpdate) as Record<string, TdWireValue>);

      expect(projection.getInitialDraft() !== null).assertTrue();
      const liveContent = projection.getInitialDraft()!.content as DraftMessageContentText;
      expect(liveContent.text!.text).assertEqual('Live draft update');

      projection.stop();
    });

    it('sendTextMessage_withLinkPreviewOptions_encodesOptionsInRequest', 0, async (): Promise<void> => {
      const bridge: TestNativeBridge = new TestNativeBridge();
      const scope: AccountScope = createScope(bridge);
      const projection: MessageProjection = new MessageProjection(42, scope);

      const options: LinkPreviewOptions = new LinkPreviewOptions();
      options.is_disabled = false;
      options.url = 'https://github.com';
      options.force_small_media = true;

      const result: Result<TdPendingRequest, AppError> =
        projection.sendTextMessage('Check this: https://github.com', 0, options);
      expect(result.ok).assertTrue();

      const sendReq: Record<string, TdWireValue> | null = findSentRequest(bridge, 'sendMessage');
      expect(sendReq !== null).assertTrue();
      if (sendReq !== null) {
        const content = sendReq['input_message_content'] as Record<string, TdWireValue>;
        expect(content['@type']).assertEqual('inputMessageText');
        const lpOptions = content['link_preview_options'] as Record<string, TdWireValue>;
        expect(lpOptions !== null && lpOptions !== undefined).assertTrue();
        expect(lpOptions['@type']).assertEqual('linkPreviewOptions');
        expect(lpOptions['url']).assertEqual('https://github.com');
        expect(lpOptions['force_small_media']).assertEqual(true);
      }
    });

    it('editMessageText_withLinkPreviewOptions_encodesOptionsInRequest', 0, async (): Promise<void> => {
      const bridge: TestNativeBridge = new TestNativeBridge();
      const scope: AccountScope = createScope(bridge);
      const projection: MessageProjection = new MessageProjection(42, scope);

      const options: LinkPreviewOptions = new LinkPreviewOptions();
      options.is_disabled = true;

      const result: Result<TdPendingRequest, AppError> =
        projection.editMessageText(1001, 'Edited text without preview', options);
      expect(result.ok).assertTrue();

      const editReq: Record<string, TdWireValue> | null = findSentRequest(bridge, 'editMessageText');
      expect(editReq !== null).assertTrue();
      if (editReq !== null) {
        const content = editReq['input_message_content'] as Record<string, TdWireValue>;
        expect(content['@type']).assertEqual('inputMessageText');
        const lpOptions = content['link_preview_options'] as Record<string, TdWireValue>;
        expect(lpOptions !== null && lpOptions !== undefined).assertTrue();
        expect(lpOptions['is_disabled']).assertEqual(true);
      }
    });

    // ---- SEARCH-102 聊天内搜索 ----

    it('searchMessages_withEmptyQuery_rejectsParameterWithoutRequest', 0, (): void => {
      const bridge: TestNativeBridge = new TestNativeBridge();
      const scope: AccountScope = createScope(bridge);
      const projection: MessageProjection = new MessageProjection(42, scope);

      const result: Result<TdPendingRequest, AppError> = projection.searchMessages('   ', 0, 30);
      expect(result.ok).assertFalse();
      expect(findSentRequest(bridge, 'searchChatMessages')).assertNull();
    });

    it('searchMessages_assemblesSearchChatMessagesForChat', 0, async (): Promise<void> => {
      const bridge: TestNativeBridge = new TestNativeBridge();
      const scope: AccountScope = createScope(bridge);
      const projection: MessageProjection = new MessageProjection(42, scope);

      const result: Result<TdPendingRequest, AppError> = projection.searchMessages('hello', 0, 30);
      expect(result.ok).assertTrue();

      const searchReq: Record<string, TdWireValue> | null = findSentRequest(bridge, 'searchChatMessages');
      expect(searchReq !== null).assertTrue();
      if (searchReq !== null) {
        expect(searchReq['chat_id']).assertEqual(42);
        expect(searchReq['query']).assertEqual('hello');
        expect(searchReq['from_message_id']).assertEqual(0);
        expect(searchReq['limit']).assertEqual(30);
        expect(searchReq['offset']).assertEqual(0);
      }
    });

    it('searchMessages_withFromMessageId_keepsPaginationCursor', 0, async (): Promise<void> => {
      const bridge: TestNativeBridge = new TestNativeBridge();
      const scope: AccountScope = createScope(bridge);
      const projection: MessageProjection = new MessageProjection(7, scope);

      const result: Result<TdPendingRequest, AppError> = projection.searchMessages('telegram', 9000, 50);
      expect(result.ok).assertTrue();

      const searchReq: Record<string, TdWireValue> | null = findSentRequest(bridge, 'searchChatMessages');
      expect(searchReq !== null).assertTrue();
      if (searchReq !== null) {
        expect(searchReq['chat_id']).assertEqual(7);
        expect(searchReq['from_message_id']).assertEqual(9000);
        expect(searchReq['limit']).assertEqual(50);
      }
    });

    it('loadHistoryAroundSendsGetChatHistoryAroundTarget', 0, async (): Promise<void> => {
      const bridge: TestNativeBridge = new TestNativeBridge();
      const scope: AccountScope = createScope(bridge);
      const projection: MessageProjection = new MessageProjection(42, scope);

      const result: Result<TdPendingRequest, AppError> | null =
        projection.loadHistoryAround(5000, 30);
      expect(result !== null).assertTrue();

      const historyReq: Record<string, TdWireValue> | null = findSentRequest(bridge, 'getChatHistory');
      expect(historyReq !== null).assertTrue();
      if (historyReq !== null) {
        expect(historyReq['chat_id']).assertEqual(42);
        expect(historyReq['from_message_id']).assertEqual(5000);
        // 负 offset：TDLib 返回目标消息及其邻近，limit=2*radius 保证目标居中。
        expect(historyReq['offset']).assertEqual(-30);
        expect(historyReq['limit']).assertEqual(60);
      }
    });

    it('loadHistoryAroundWhenLoadingReturnsNullWithoutRequest', 0, async (): Promise<void> => {
      const bridge: TestNativeBridge = new TestNativeBridge();
      const scope: AccountScope = createScope(bridge);
      const projection: MessageProjection = new MessageProjection(42, scope);

      // 先触发一次首屏历史加载（isLoading=true），再在同一时刻调 loadHistoryAround。
      projection.loadInitialMessages(20);
      const result: Result<TdPendingRequest, AppError> | null =
        projection.loadHistoryAround(6000, 30);
      expect(result === null).assertTrue();
    });

    it('getChatPinnedMessageSendsGetChatPinnedMessage', 0, async (): Promise<void> => {
      const bridge: TestNativeBridge = new TestNativeBridge();
      const scope: AccountScope = createScope(bridge);
      const projection: MessageProjection = new MessageProjection(42, scope);

      const result: Result<TdPendingRequest, AppError> = projection.getChatPinnedMessage();
      expect(result.ok).assertTrue();

      const pinnedReq: Record<string, TdWireValue> | null = findSentRequest(bridge, 'getChatPinnedMessage');
      expect(pinnedReq !== null).assertTrue();
      if (pinnedReq !== null) {
        expect(pinnedReq['chat_id']).assertEqual(42);
      }
    });

    it('joinChatSendsJoinChatRequest', 0, async (): Promise<void> => {
      const bridge: TestNativeBridge = new TestNativeBridge();
      const scope: AccountScope = createScope(bridge);
      const projection: MessageProjection = new MessageProjection(42, scope);

      const result: Result<TdPendingRequest, AppError> = projection.joinChat();
      expect(result.ok).assertTrue();

      const joinReq: Record<string, TdWireValue> | null = findSentRequest(bridge, 'joinChat');
      expect(joinReq !== null).assertTrue();
      if (joinReq !== null) {
        expect(joinReq['chat_id']).assertEqual(42);
      }
    });

    it('addMessageReactionSendsAddMessageReactionRequest', 0, async (): Promise<void> => {
      const bridge: TestNativeBridge = new TestNativeBridge();
      const scope: AccountScope = createScope(bridge);
      const projection: MessageProjection = new MessageProjection(42, scope);

      const result: Result<TdPendingRequest, AppError> = projection.addMessageReaction(1234, '🔥');
      expect(result.ok).assertTrue();

      const req: Record<string, TdWireValue> | null = findSentRequest(bridge, 'addMessageReaction');
      expect(req !== null).assertTrue();
      if (req !== null) {
        expect(req['chat_id']).assertEqual(42);
        expect(req['message_id']).assertEqual(1234);
        const rType = req['reaction_type'] as Record<string, TdWireValue>;
        expect(rType['@type']).assertEqual('reactionTypeEmoji');
        expect(rType['emoji']).assertEqual('🔥');
      }
    });

    it('removeMessageReactionSendsRemoveMessageReactionRequest', 0, async (): Promise<void> => {
      const bridge: TestNativeBridge = new TestNativeBridge();
      const scope: AccountScope = createScope(bridge);
      const projection: MessageProjection = new MessageProjection(42, scope);

      const result: Result<TdPendingRequest, AppError> = projection.removeMessageReaction(1234, '🔥');
      expect(result.ok).assertTrue();

      const req: Record<string, TdWireValue> | null = findSentRequest(bridge, 'removeMessageReaction');
      expect(req !== null).assertTrue();
      if (req !== null) {
        expect(req['chat_id']).assertEqual(42);
        expect(req['message_id']).assertEqual(1234);
        const rType = req['reaction_type'] as Record<string, TdWireValue>;
        expect(rType['@type']).assertEqual('reactionTypeEmoji');
        expect(rType['emoji']).assertEqual('🔥');
      }
    });

    // ---- MSG-108 置顶消息操作与监听 ----

    it('pinChatMessageSendsPinChatMessageRequest', 0, async (): Promise<void> => {
      const bridge: TestNativeBridge = new TestNativeBridge();
      const scope: AccountScope = createScope(bridge);
      const projection: MessageProjection = new MessageProjection(42, scope);

      const result: Result<TdPendingRequest, AppError> = projection.pinChatMessage(1234, true, false);
      expect(result.ok).assertTrue();

      const req: Record<string, TdWireValue> | null = findSentRequest(bridge, 'pinChatMessage');
      expect(req !== null).assertTrue();
      if (req !== null) {
        expect(req['chat_id']).assertEqual(42);
        expect(req['message_id']).assertEqual(1234);
        expect(req['disable_notification']).assertEqual(true);
        expect(req['only_for_self']).assertEqual(false);
      }
    });

    it('unpinChatMessageSendsUnpinChatMessageRequest', 0, async (): Promise<void> => {
      const bridge: TestNativeBridge = new TestNativeBridge();
      const scope: AccountScope = createScope(bridge);
      const projection: MessageProjection = new MessageProjection(42, scope);

      const result: Result<TdPendingRequest, AppError> = projection.unpinChatMessage(1234);
      expect(result.ok).assertTrue();

      const req: Record<string, TdWireValue> | null = findSentRequest(bridge, 'unpinChatMessage');
      expect(req !== null).assertTrue();
      if (req !== null) {
        expect(req['chat_id']).assertEqual(42);
        expect(req['message_id']).assertEqual(1234);
      }
    });

    it('unpinAllChatMessagesSendsUnpinAllChatMessagesRequest', 0, async (): Promise<void> => {
      const bridge: TestNativeBridge = new TestNativeBridge();
      const scope: AccountScope = createScope(bridge);
      const projection: MessageProjection = new MessageProjection(42, scope);

      const result: Result<TdPendingRequest, AppError> = projection.unpinAllChatMessages();
      expect(result.ok).assertTrue();

      const req: Record<string, TdWireValue> | null = findSentRequest(bridge, 'unpinAllChatMessages');
      expect(req !== null).assertTrue();
      if (req !== null) {
        expect(req['chat_id']).assertEqual(42);
      }
    });

    it('updateMessageIsPinnedUpdatesMessageAndNotifiesListener', 0, async (): Promise<void> => {
      const bridge: TestNativeBridge = new TestNativeBridge();
      const scope: AccountScope = createScope(bridge);
      const projection: MessageProjection = new MessageProjection(42, scope);

      projection.start();

      const msg: Message = new Message();
      msg.id = 1234;
      msg.chat_id = 42;
      msg.is_pinned = false;
      projection.addCachedMessage(msg);

      expect(projection.state.messages.length).assertEqual(1);
      expect(projection.state.messages[0].is_pinned).assertEqual(false);

      let notifiedMsgId: number = 0;
      let notifiedIsPinned: boolean = false;
      projection.setOnPinnedMessageChanged((msgId: number, isPinned: boolean): void => {
        notifiedMsgId = msgId;
        notifiedIsPinned = isPinned;
      });

      const pinUpdateFields: Record<string, TdWireValue> = {};
      pinUpdateFields['chat_id'] = 42;
      pinUpdateFields['message_id'] = 1234;
      pinUpdateFields['is_pinned'] = true;

      bridge.emitUpdate(scope.clientId, 'updateMessageIsPinned', pinUpdateFields);
      await flushAsync();

      expect(projection.state.messages[0].is_pinned).assertEqual(true);
      expect(notifiedMsgId).assertEqual(1234);
      expect(notifiedIsPinned).assertEqual(true);

      projection.stop();
    });

  });
}
