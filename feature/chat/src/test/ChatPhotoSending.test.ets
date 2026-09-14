/**
 * feature/chat — 图片发送与上传状态跟踪单元测试（MEDIA-102 / FEAT-MEDIA-001）。
 */

import { describe, it, expect } from '@ohos/hypium';
import {
  AccountScope,
  buildAccountDirectories,
  createDescriptor,
  AccountDirectoryLayout
} from '@tgx/core-account';
import {
  FakeAppFiles,
  FakeMediaPicker,
  PickedMedia
} from '@tgx/platform-ports';
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
import { PickAndSendPhoto } from '../main/ets/contract/ChatIntent';

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

  lastSentJson(): Record<string, TdWireValue> {
    const last: SentBridgeRequest = this.sent[this.sent.length - 1];
    return JSON.parse(last.utf8) as Record<string, TdWireValue>;
  }
}

function createScope(bridge: TestNativeBridge): AccountScope {
  const layoutRes: Result<AccountDirectoryLayout, AppError> = buildAccountDirectories('test_photo_sending');
  if (layoutRes.ok === false) {
    throw new Error('Failed to build directories');
  }
  const scopeRes: Result<AccountScope, AppError> = AccountScope.open({
    bridge: bridge,
    files: new FakeAppFiles(),
    descriptor: createDescriptor('test_photo_sending', 'acct_user_1', 0, true),
    directories: layoutRes.value,
    startActive: true
  });
  if (scopeRes.ok === false) {
    throw new Error('Failed to open AccountScope');
  }
  return scopeRes.value;
}

export default function chatPhotoSendingTest(): void {
  describe('ChatPhotoSendingTest', () => {

    it('pickAndSendPhoto picks image and dispatches SendMessage with InputMessagePhoto', 0, async (): Promise<void> => {
      const bridge: TestNativeBridge = new TestNativeBridge();
      const scope: AccountScope = createScope(bridge);

      const fakePicker: FakeMediaPicker = new FakeMediaPicker();
      fakePicker.nextPhotosToReturn = [{
        uri: 'file://media/Photo/123.jpg',
        path: '/data/storage/el2/base/photos/123.jpg'
      }];

      const env: ReducerEnv = {
        clock: new ManualClock(1000, 500),
        ids: new SequentialIdGenerator('test-')
      };

      const coordinator: ChatCoordinator = new ChatCoordinator(
        scope,
        42,
        'Test Chat',
        undefined,
        undefined,
        env,
        {
          mediaPickerPort: fakePicker
        }
      );

      coordinator.pickAndSendPhoto();

      // Wait a tick for async pickPhoto promise
      await new Promise<void>((resolve) => setTimeout(resolve, 50));

      expect(fakePicker.pickPhotoCalls).assertEqual(1);

      // Verify that sendMessage was dispatched over bridge
      let foundSendMessage = false;
      for (let i = 0; i < bridge.sent.length; i++) {
        const req: Record<string, TdWireValue> = JSON.parse(bridge.sent[i].utf8) as Record<string, TdWireValue>;
        if (req['@type'] === 'sendMessage') {
          foundSendMessage = true;
          expect(req['chat_id']).assertEqual(42);
          const content = req['input_message_content'] as Record<string, TdWireValue>;
          expect(content['@type']).assertEqual('inputMessagePhoto');
          const photo = content['photo'] as Record<string, TdWireValue>;
          expect(photo['@type']).assertEqual('inputPhoto');
          const file = photo['photo'] as Record<string, TdWireValue>;
          expect(file['path']).assertEqual('/data/storage/el2/base/photos/123.jpg');
          break;
        }
      }
      expect(foundSendMessage).assertTrue();

      coordinator.destroy();
    });

    it('cancelMediaUpload calls deleteMessages with revoke=true', 0, (): void => {
      const bridge: TestNativeBridge = new TestNativeBridge();
      const scope: AccountScope = createScope(bridge);

      const coordinator: ChatCoordinator = new ChatCoordinator(
        scope,
        42,
        'Test Chat'
      );

      const res: Result<import('@tgx/td-gateway').TdPendingRequest, AppError> = coordinator.cancelMediaUpload(999);
      expect(res.ok).assertTrue();

      const sent: Record<string, TdWireValue> = bridge.lastSentJson();
      expect(sent['@type']).assertEqual('deleteMessages');
      expect(sent['chat_id']).assertEqual(42);
      expect(sent['revoke']).assertEqual(true);
      const ids: number[] = sent['message_ids'] as number[];
      expect(ids.length).assertEqual(1);
      expect(ids[0]).assertEqual(999);

      coordinator.destroy();
    });

    it('pickAndSendPhoto aborts cleanly when user cancels selection', 0, async (): Promise<void> => {
      const bridge: TestNativeBridge = new TestNativeBridge();
      const scope: AccountScope = createScope(bridge);

      const fakePicker: FakeMediaPicker = new FakeMediaPicker();
      fakePicker.nextPhotosToReturn = []; // User cancelled / no photo selected

      const coordinator: ChatCoordinator = new ChatCoordinator(
        scope,
        42,
        'Test Chat',
        undefined,
        undefined,
        undefined,
        {
          mediaPickerPort: fakePicker
        }
      );

      coordinator.dispatch(new PickAndSendPhoto());
      await new Promise<void>((resolve) => setTimeout(resolve, 50));

      expect(fakePicker.pickPhotoCalls).assertEqual(1);
      // No sendMessage should be dispatched
      for (let i = 0; i < bridge.sent.length; i++) {
        const req: Record<string, TdWireValue> = JSON.parse(bridge.sent[i].utf8) as Record<string, TdWireValue>;
        expect(req['@type'] !== 'sendMessage').assertTrue();
      }

      coordinator.destroy();
    });

  });
}
