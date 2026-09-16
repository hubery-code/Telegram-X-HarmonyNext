import { describe, it, expect, beforeEach } from '@ohos/hypium';
import {
  ChatListProjection,
  chatListEquals,
  compareChatOrder,
  isChatPinnedInList
} from '../../main/ets/chatlist/ChatListProjection';
import { ChatRegistry } from '../../main/ets/chatlist/ChatRegistry';
import {
  Chat,
  ChatListMain,
  ChatListArchive,
  ChatPosition,
  ChatPhotoInfo,
  File,
  LocalFile,
  UpdateChatPhoto,
  UpdateChatTitle,
  UpdateChatDraftMessage,
  DraftMessage,
  DraftMessageContentText,
  FormattedText,
  encodeUpdateChatPhoto,
  encodeUpdateChatTitle,
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
  TdWireObject,
  TdWireValue
} from '@tgx/td-gateway';
import { Result, AppError } from '@tgx/core-common';

/** 造一个只带 positions 的 Chat（isChatPinnedInList 只读 positions）。 */
function makeChatWithPositions(id: number, positions: ChatPosition[]): Chat {
  const chat = new Chat();
  chat.id = id;
  chat.positions = positions;
  return chat;
}

/** 造一个位置。 */
function makePosition(list: ChatListMain | ChatListArchive, order: string, isPinned: boolean): ChatPosition {
  const pos = new ChatPosition();
  pos.list = list;
  pos.order = order;
  pos.is_pinned = isPinned;
  return pos;
}

export default function chatListProjectionTest() {
  describe('ChatListProjection', (): void => {
    
    it('compareChatOrder should sort correctly', 0, (): void => {
      // Order DESC, ID DESC
      // a is greater order, should return < 0 (i.e. -1)
      expect(compareChatOrder("10", 1, "5", 1)).assertEqual(-1);
      expect(compareChatOrder("5", 1, "10", 1)).assertEqual(1);
      
      // Same order, A has greater id -> A should be before B (-1)
      expect(compareChatOrder("5", 2, "5", 1)).assertEqual(-1);
      expect(compareChatOrder("5", 1, "5", 2)).assertEqual(1);
      
      // Exact same
      expect(compareChatOrder("5", 1, "5", 1)).assertEqual(0);
      
      // BigInt larger than number
      expect(compareChatOrder("9223372036854775807", 1, "9223372036854775806", 2)).assertEqual(-1);
    });

    it('chatListEquals works', 0, (): void => {
      const main1 = new ChatListMain();
      const main2 = new ChatListMain();
      const archive = new ChatListArchive();
      
      expect(chatListEquals(main1, main2)).assertTrue();
      expect(chatListEquals(main1, archive)).assertFalse();
      expect(chatListEquals(main1, null)).assertFalse();
    });

    // ---- MSG-108 置顶态判定（FEAT-CHAT-002）----

    it('isChatPinnedInList reads is_pinned from the matching list position', 0, (): void => {
      const main = new ChatListMain();
      const chat = makeChatWithPositions(7, [makePosition(main, '100', true)]);
      expect(isChatPinnedInList(chat, main)).assertTrue();
    });

    it('isChatPinnedInList returns false for an unpinned position', 0, (): void => {
      const main = new ChatListMain();
      const chat = makeChatWithPositions(7, [makePosition(main, '100', false)]);
      expect(isChatPinnedInList(chat, main)).assertFalse();
    });

    it('isChatPinnedInList ignores positions belonging to another list', 0, (): void => {
      // 只有归档区的置顶位置时，主列表查询必须为 false（不能跨列表误判）
      const main = new ChatListMain();
      const archive = new ChatListArchive();
      const chat = makeChatWithPositions(7, [makePosition(archive, '100', true)]);
      expect(isChatPinnedInList(chat, main)).assertFalse();
      expect(isChatPinnedInList(chat, archive)).assertTrue();
    });

    it('isChatPinnedInList returns false when the chat has no position at all', 0, (): void => {
      const main = new ChatListMain();
      const chat = makeChatWithPositions(7, []);
      expect(isChatPinnedInList(chat, main)).assertFalse();
    });

    it('isChatPinnedInList picks the right entry among several positions', 0, (): void => {
      const main = new ChatListMain();
      const archive = new ChatListArchive();
      const chat = makeChatWithPositions(7, [
        makePosition(archive, '500', true),
        makePosition(main, '100', false)
      ]);
      // 主列表这条未置顶；不能因为归档那条置顶就误判为已置顶
      expect(isChatPinnedInList(chat, main)).assertFalse();
      expect(isChatPinnedInList(chat, archive)).assertTrue();
    });

    it('updateChatPhoto updates chat.photo and notifies listener', 0, (): void => {
      const bridge = new TestNativeBridge();
      const scope = createScope(bridge);
      const registry = new ChatRegistry();
      const chat = makeChatWithPositions(101, [makePosition(new ChatListMain(), '100', false)]);
      registry.putChat(chat);
      const proj = new ChatListProjection(new ChatListMain(), registry, scope);
      let notified = false;
      proj.setOnStateChanged(() => {
        notified = true;
      });
      proj.start();

      const update: UpdateChatPhoto = new UpdateChatPhoto();
      update.chat_id = 101;
      const photoInfo: ChatPhotoInfo = new ChatPhotoInfo();
      const file: File = new File();
      file.id = 2001;
      file.size = 1024;
      file.expected_size = 1024;
      const local: LocalFile = new LocalFile();
      local.path = '/data/photo_2001.jpg';
      local.is_downloading_completed = true;
      file.local = local;
      photoInfo.small = file;
      update.photo = photoInfo;

      bridge.emitUpdate(1, 'updateChatPhoto', encodeUpdateChatPhoto(update) as Record<string, TdWireValue>);

      expect(notified).assertTrue();
      const updatedChat = registry.getChat(101);
      expect(updatedChat !== undefined).assertTrue();
      expect(updatedChat!.photo !== null).assertTrue();
      expect(updatedChat!.photo!.small !== null).assertTrue();
      expect(updatedChat!.photo!.small!.id).assertEqual(2001);
      proj.stop();
    });

    it('updateChatTitle updates chat.title and notifies listener', 0, (): void => {
      const bridge = new TestNativeBridge();
      const scope = createScope(bridge);
      const registry = new ChatRegistry();
      const chat = makeChatWithPositions(102, [makePosition(new ChatListMain(), '100', false)]);
      chat.title = 'Old Title';
      registry.putChat(chat);
      const proj = new ChatListProjection(new ChatListMain(), registry, scope);
      let notified = false;
      proj.setOnStateChanged(() => {
        notified = true;
      });
      proj.start();

      const titleUpdate: UpdateChatTitle = new UpdateChatTitle();
      titleUpdate.chat_id = 102;
      titleUpdate.title = 'New Group Title';

      bridge.emitUpdate(1, 'updateChatTitle', encodeUpdateChatTitle(titleUpdate) as Record<string, TdWireValue>);

      expect(notified).assertTrue();
      const updatedChat = registry.getChat(102);
      expect(updatedChat !== undefined).assertTrue();
      expect(updatedChat!.title).assertEqual('New Group Title');
      proj.stop();
    });

    it('updateChatDraftMessage updates chat.draft_message and reorders positions', 0, (): void => {
      const bridge = new TestNativeBridge();
      const scope = createScope(bridge);
      const registry = new ChatRegistry();
      const chat = makeChatWithPositions(103, [makePosition(new ChatListMain(), '100', false)]);
      registry.putChat(chat);
      const proj = new ChatListProjection(new ChatListMain(), registry, scope);
      let notified = false;
      proj.setOnStateChanged(() => {
        notified = true;
      });
      proj.start();

      const draftUpdate: UpdateChatDraftMessage = new UpdateChatDraftMessage();
      draftUpdate.chat_id = 103;
      const draft: DraftMessage = new DraftMessage();
      const textContent: DraftMessageContentText = new DraftMessageContentText();
      const formatted: FormattedText = new FormattedText();
      formatted.text = 'Unsent draft text';
      textContent.text = formatted;
      draft.content = textContent;
      draftUpdate.draft_message = draft;
      draftUpdate.positions = [makePosition(new ChatListMain(), '200', false)];

      bridge.emitUpdate(1, 'updateChatDraftMessage', encodeUpdateChatDraftMessage(draftUpdate) as Record<string, TdWireValue>);

      expect(notified).assertTrue();
      const updatedChat = registry.getChat(103);
      expect(updatedChat !== undefined).assertTrue();
      expect(updatedChat!.draft_message !== null).assertTrue();
      const content = updatedChat!.draft_message!.content as DraftMessageContentText;
      expect(content.text!.text).assertEqual('Unsent draft text');
      proj.stop();
    });

    it('moveChatToList sends addChatToList request with target list', 0, (): void => {
      const bridge = new TestNativeBridge();
      const scope = createScope(bridge);
      const registry = new ChatRegistry();
      const proj = new ChatListProjection(new ChatListMain(), registry, scope);

      const result = proj.moveChatToList(42, new ChatListArchive());
      expect(result.ok).assertTrue();
      expect(bridge.sent.length).assertEqual(1);
      const reqJson = JSON.parse(bridge.sent[0].utf8) as Record<string, Object>;
      expect(reqJson['@type']).assertEqual('addChatToList');
      expect(reqJson['chat_id']).assertEqual(42);
      const targetChatList = reqJson['chat_list'] as Record<string, Object>;
      expect(targetChatList['@type']).assertEqual('chatListArchive');
    });

  });
}

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
}

function createScope(bridge: TestNativeBridge): AccountScope {
  const layoutRes: Result<AccountDirectoryLayout, AppError> = buildAccountDirectories('test_chatlist_projection');
  if (layoutRes.ok === false) {
    throw new Error('Failed to build directories');
  }
  const scopeRes: Result<AccountScope, AppError> = AccountScope.open({
    bridge: bridge,
    files: new FakeAppFiles(),
    descriptor: createDescriptor('test_chatlist_projection', 'acct_user_1', 0, true),
    directories: layoutRes.value,
    startActive: true
  });
  if (scopeRes.ok === false) {
    throw new Error('Failed to open AccountScope');
  }
  return scopeRes.value;
}
