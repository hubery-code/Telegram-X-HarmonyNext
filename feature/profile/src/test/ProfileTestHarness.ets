/**
 * feature/profile — 测试夹具：假的 TDLib 原生桥 + 共享内容 wire 报文。
 *
 * 用户资料页与群/频道资料页的共享内容走同一个 searcher + 同一套 wire 报文，
 * 两套 coordinator 端到端用例都要喂同一批 payload；这份夹具不抽出来，
 * 两个测试文件就会各自演化出一套「看起来一样」的报文构造器。
 */

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

export class TestNativeBridge implements TdNativeBridgeLike {
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

  /** 以 TDLib error 报文回绝一条请求：页面必须区分「拉失败」与「确实没有」。 */
  respondWithError(requestId: string, message: string): void {
    const fields: Record<string, TdWireValue> = {};
    fields['@type'] = 'error';
    fields['code'] = 400;
    fields['message'] = message;
    this.respondTo(requestId, fields);
  }

  /** 最近一条 @type 匹配的请求里的 @extra.requestId；没有则空串。 */
  lastRequestIdOf(type: string): string {
    for (let i = this.sent.length - 1; i >= 0; i--) {
      const req: Record<string, TdWireValue> = JSON.parse(this.sent[i]) as Record<string, TdWireValue>;
      if (req['@type'] === type) {
        const extra: Record<string, TdWireValue> | undefined =
          req['@extra'] as Record<string, TdWireValue> | undefined;
        return extra !== undefined && extra !== null ? String(extra['requestId']) : '';
      }
    }
    return '';
  }

  /** 最近一条 @type 匹配的请求报文（断言 filter / from_message_id 等入参用）。 */
  lastRequestOf(type: string): Record<string, TdWireValue> {
    for (let i = this.sent.length - 1; i >= 0; i--) {
      const req: Record<string, TdWireValue> = JSON.parse(this.sent[i]) as Record<string, TdWireValue>;
      if (req['@type'] === type) {
        return req;
      }
    }
    const empty: Record<string, TdWireValue> = {};
    return empty;
  }
}

export function createScope(bridge: TestNativeBridge, name: string): AccountScope {
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

export function privateChatResponse(chatId: number): Record<string, TdWireValue> {
  const type: Record<string, TdWireValue> = {};
  type['@type'] = 'chatTypePrivate';
  type['user_id'] = 4242;
  const fields: Record<string, TdWireValue> = {};
  fields['@type'] = 'chat';
  fields['id'] = chatId;
  fields['title'] = 'Peer';
  fields['type'] = type;
  return fields;
}

export function basicGroupChatResponse(chatId: number): Record<string, TdWireValue> {
  const type: Record<string, TdWireValue> = {};
  type['@type'] = 'chatTypeBasicGroup';
  type['basic_group_id'] = 900;
  const fields: Record<string, TdWireValue> = {};
  fields['@type'] = 'chat';
  fields['id'] = chatId;
  fields['type'] = type;
  fields['title'] = 'Harmony Dev Group';
  return fields;
}

export function supergroupChatResponse(chatId: number): Record<string, TdWireValue> {
  const type: Record<string, TdWireValue> = {};
  type['@type'] = 'chatTypeSupergroup';
  type['supergroup_id'] = 700;
  type['is_channel'] = false;
  const fields: Record<string, TdWireValue> = {};
  fields['@type'] = 'chat';
  fields['id'] = chatId;
  fields['type'] = type;
  fields['title'] = 'Supergroup';
  return fields;
}

export function fileValue(fileId: number): Record<string, TdWireValue> {
  const remote: Record<string, TdWireValue> = {};
  remote['@type'] = 'remoteFileId';
  remote['id'] = String(fileId);
  remote['is_upload_active_completed'] = true;
  remote['uploaded_size'] = 1024;
  remote['download_size'] = 1024;
  const local: Record<string, TdWireValue> = {};
  local['@type'] = 'localFile';
  local['is_downloaded_active'] = false;
  local['is_downloaded_completed'] = false;
  const fields: Record<string, TdWireValue> = {};
  fields['@type'] = 'file';
  fields['id'] = fileId;
  fields['size'] = 1024;
  fields['expected_remote_file_id'] = String(fileId);
  fields['remote'] = remote;
  fields['local'] = local;
  return fields;
}

export function photoSizeValue(fileId: number, width: number): Record<string, TdWireValue> {
  const size: Record<string, TdWireValue> = {};
  size['@type'] = 'photoSize';
  size['type'] = 'photoSizeLarge';
  size['photo'] = fileValue(fileId);
  size['width'] = width;
  size['height'] = width;
  return size;
}

export function photoMessage(messageId: number, sizes: Record<string, TdWireValue>[]): Record<string, TdWireValue> {
  const photo: Record<string, TdWireValue> = {};
  photo['@type'] = 'photo';
  photo['id'] = messageId * 10;
  photo['sizes'] = sizes;
  const content: Record<string, TdWireValue> = {};
  content['@type'] = 'messagePhoto';
  content['photo'] = photo;
  const msg: Record<string, TdWireValue> = {};
  msg['@type'] = 'message';
  msg['id'] = messageId;
  msg['chat_id'] = 4242;
  msg['date'] = 1700000000;
  msg['content'] = content;
  return msg;
}

export function videoMessageWithoutThumb(messageId: number): Record<string, TdWireValue> {
  const video: Record<string, TdWireValue> = {};
  video['@type'] = 'video';
  video['duration'] = 12;
  video['mime_type'] = 'video/mp4';
  video['video'] = fileValue(messageId * 100);
  video['thumbnail'] = null;
  const content: Record<string, TdWireValue> = {};
  content['@type'] = 'messageVideo';
  content['video'] = video;
  content['cover'] = null;
  const msg: Record<string, TdWireValue> = {};
  msg['@type'] = 'message';
  msg['id'] = messageId;
  msg['chat_id'] = 4242;
  msg['date'] = 1700000000;
  msg['content'] = content;
  return msg;
}

export function documentMessage(messageId: number, fileName: string): Record<string, TdWireValue> {
  const doc: Record<string, TdWireValue> = {};
  doc['@type'] = 'document';
  doc['file_name'] = fileName;
  doc['mime_type'] = 'application/pdf';
  doc['document'] = fileValue(messageId * 7);
  const content: Record<string, TdWireValue> = {};
  content['@type'] = 'messageDocument';
  content['document'] = doc;
  const msg: Record<string, TdWireValue> = {};
  msg['@type'] = 'message';
  msg['id'] = messageId;
  msg['chat_id'] = 4242;
  msg['date'] = 1700000000;
  msg['content'] = content;
  return msg;
}

export function foundMessages(messages: Record<string, TdWireValue>[], nextFromId: number): Record<string, TdWireValue> {
  const fields: Record<string, TdWireValue> = {};
  fields['@type'] = 'foundChatMessages';
  fields['total_count'] = messages.length;
  fields['messages'] = messages;
  fields['next_from_message_id'] = nextFromId;
  return fields;
}

export function settle(): Promise<void> {
  return new Promise<void>((resolve: () => void): void => {
    setTimeout(resolve, 30);
  });
}
