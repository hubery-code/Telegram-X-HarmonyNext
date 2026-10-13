/**
 * feature/chat — 名片消息（messageContact）单元测试（CONTACT-MSG-101）。
 *
 * 验证：
 * 1. ContactCard 构造与字段存储；
 * 2. formatContactFullName 优雅全名计算（含回退电话号码）；
 * 3. MessageItem.contact 默认值、构造注入与 withContact 不可变派生；
 * 4. ChatCoordinator 将 TDLib messageContact 映射为 ContactCard 与 MessageItem.contact。
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
import { ChatUiState } from '../main/ets/contract/ChatUiState';
import { ContactCard, formatContactFullName } from '../main/ets/model/ContactCard';
import { MessageItem } from '../main/ets/model/MessageItem';

const TEST_CHAT_ID: number = 77;

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

  send(_clientId: number, requestUtf8: string): void {
    this.sent.push(requestUtf8);
  }

  execute(_requestUtf8: string): string | null {
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
  const layoutRes: Result<AccountDirectoryLayout, AppError> = buildAccountDirectories('test_contact_msg');
  if (layoutRes.ok === false) {
    throw new Error('Failed to build directories');
  }
  const scopeRes: Result<AccountScope, AppError> = AccountScope.open({
    bridge: bridge,
    files: new FakeAppFiles(),
    descriptor: createDescriptor('test_contact_msg', 'acct_user_1', 0, true),
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

export default function contactMessageTest(): void {
  describe('ContactMessageTest', () => {

    it('formatContactFullName_formatsNamesCorrectly', 0, (): void => {
      // 姓名前后空格去除与拼接
      expect(formatContactFullName('Alice', 'Smith')).assertEqual('Alice Smith');
      expect(formatContactFullName('  Alice  ', '  Smith  ')).assertEqual('Alice Smith');
      // 仅有名字
      expect(formatContactFullName('Alice', '')).assertEqual('Alice');
      expect(formatContactFullName('Alice', '   ')).assertEqual('Alice');
      // 仅有姓氏
      expect(formatContactFullName('', 'Smith')).assertEqual('Smith');
      // 均为空时回退电话号码
      expect(formatContactFullName('', '', '+1234567890')).assertEqual('+1234567890');
      expect(formatContactFullName('   ', '   ', '  +1234567890  ')).assertEqual('+1234567890');
      // 全部为空返回空字符串
      expect(formatContactFullName('', '', '')).assertEqual('');
    });

    it('contactCard_constructor_setsPropertiesAndCalculatesFullName', 0, (): void => {
      const card: ContactCard = new ContactCard(
        'John',
        'Doe',
        '',
        '+8613800000000',
        'BEGIN:VCARD\nFN:John Doe\nEND:VCARD',
        9999
      );

      expect(card.firstName).assertEqual('John');
      expect(card.lastName).assertEqual('Doe');
      expect(card.fullName).assertEqual('John Doe');
      expect(card.phoneNumber).assertEqual('+8613800000000');
      expect(card.vcard).assertEqual('BEGIN:VCARD\nFN:John Doe\nEND:VCARD');
      expect(card.userId).assertEqual(9999);
    });

    it('messageItem_withContact_preservesFieldsAndUpdatesContact', 0, (): void => {
      const cardA: ContactCard = new ContactCard('Alice', 'Wong', 'Alice Wong', '+111', '', 100);
      const cardB: ContactCard = new ContactCard('Bob', 'Lee', 'Bob Lee', '+222', '', 200);

      const item: MessageItem = new MessageItem(
        101,
        '',
        1700000000000,
        false,
        'Sender',
        'none',
        false,
        false,
        null,
        '',
        [],
        -1,
        false,
        null,
        '',
        -1,
        null,
        false,
        false,
        '',
        false,
        null,
        [],
        [],
        null,
        0,
        false,
        [],
        0,
        false,
        null,
        cardA
      );

      expect(item.contact !== null).assertTrue();
      expect(item.contact!.fullName).assertEqual('Alice Wong');

      const updated: MessageItem = item.withContact(cardB);
      expect(updated.messageId).assertEqual(101);
      expect(updated.contact !== null).assertTrue();
      expect(updated.contact!.fullName).assertEqual('Bob Lee');

      const cleared: MessageItem = updated.withContact(null);
      expect(cleared.contact).assertNull();
    });

    it('chatCoordinator_mapsMessageContactToContactCardAndItem', 0, async (): Promise<void> => {
      const bridge: TestNativeBridge = new TestNativeBridge();
      const scope: AccountScope = createScope(bridge);
      const coordinator: ChatCoordinator = new ChatCoordinator(
        scope, TEST_CHAT_ID, 'Contact Chat', undefined, undefined, makeEnv()
      );

      coordinator.start();
      const historyReqs: Record<string, TdWireValue>[] = bridge.historyRequests();
      expect(historyReqs.length >= 1).assertTrue();
      const initialReqId: string = requestIdOf(historyReqs[0]);

      // 构造 messageContact 回包
      const contactObj: Record<string, TdWireValue> = {};
      contactObj['@type'] = 'contact';
      contactObj['first_name'] = 'Charlie';
      contactObj['last_name'] = 'Brown';
      contactObj['phone_number'] = '+15551234567';
      contactObj['vcard'] = 'BEGIN:VCARD\nFN:Charlie Brown\nEND:VCARD';
      contactObj['user_id'] = 4567;

      const contentObj: Record<string, TdWireValue> = {};
      contentObj['@type'] = 'messageContact';
      contentObj['contact'] = contactObj;

      const msgObj: Record<string, TdWireValue> = {};
      msgObj['@type'] = 'message';
      msgObj['id'] = 7001;
      msgObj['chat_id'] = TEST_CHAT_ID;
      msgObj['date'] = 1700000000;
      msgObj['is_outgoing'] = false;
      msgObj['can_be_edited'] = false;
      msgObj['can_be_forwarded'] = true;
      msgObj['can_be_saved'] = true;
      msgObj['can_be_deleted_only_for_self'] = false;
      msgObj['can_be_deleted_for_all_users'] = false;
      msgObj['can_get_added_reactions'] = false;
      msgObj['can_get_statistics'] = false;
      msgObj['can_get_message_thread'] = false;
      msgObj['can_get_viewers'] = false;
      msgObj['can_get_media_timestamp_links'] = false;
      msgObj['can_report_reactions'] = false;
      msgObj['has_timestamped_media'] = false;
      msgObj['is_channel_post'] = false;
      msgObj['is_topic_message'] = false;
      msgObj['contains_unread_mention'] = false;
      msgObj['date_and_time_format'] = 0;
      msgObj['edit_date'] = 0;
      msgObj['reply_to'] = null;
      const senderUser: Record<string, TdWireValue> = {};
      senderUser['@type'] = 'messageSenderUser';
      senderUser['user_id'] = 123;
      msgObj['sender_id'] = senderUser;
      msgObj['content'] = contentObj;

      const extra: TdWireObject = {};
      extra['requestId'] = initialReqId;
      const responseFields: Record<string, TdWireValue> = {};
      responseFields['total_count'] = 1;
      responseFields['messages'] = [msgObj];
      responseFields['@extra'] = extra;

      let latestState: ChatUiState = ChatUiState.initial();
      coordinator.subscribe((s: ChatUiState): void => {
        latestState = s;
      });

      bridge.emitResponse(scope.clientId, 'messages', responseFields);
      await tick();

      // 验证消息列表已解析出 ContactCard
      const item: MessageItem | undefined = latestState.messages.find((m: MessageItem) => m.messageId === 7001);
      expect(item !== undefined).assertTrue();
      expect(item!.contact !== null).assertTrue();
      expect(item!.contact!.firstName).assertEqual('Charlie');
      expect(item!.contact!.lastName).assertEqual('Brown');
      expect(item!.contact!.fullName).assertEqual('Charlie Brown');
      expect(item!.contact!.phoneNumber).assertEqual('+15551234567');
      expect(item!.contact!.vcard).assertEqual('BEGIN:VCARD\nFN:Charlie Brown\nEND:VCARD');
      expect(item!.contact!.userId).assertEqual(4567);
      expect(item!.text).assertEqual('');

      coordinator.destroy();
    });

  });
}
