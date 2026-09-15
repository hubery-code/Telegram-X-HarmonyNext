/**
 * feature/chat — 文件消息发送、下载与取消状态跟踪单元测试（MEDIA-104 / FEAT-MEDIA-003）。
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
import { PickAndSendFile, RequestMediaDownload, CancelMediaDownload } from '../main/ets/contract/ChatIntent';

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
  const layoutRes: Result<AccountDirectoryLayout, AppError> = buildAccountDirectories('test_file_sending');
  if (layoutRes.ok === false) {
    throw new Error('Failed to build directories');
  }
  const scopeRes: Result<AccountScope, AppError> = AccountScope.open({
    bridge: bridge,
    files: new FakeAppFiles(),
    descriptor: createDescriptor('test_file_sending', 'acct_user_1', 0, true),
    directories: layoutRes.value,
    startActive: true
  });
  if (scopeRes.ok === false) {
    throw new Error('Failed to open AccountScope');
  }
  return scopeRes.value;
}

export default function chatFileSendingTest(): void {
  describe('ChatFileSendingTest', () => {

    it('pickAndSendFile picks file and dispatches SendMessage with InputMessageDocument', 0, async (): Promise<void> => {
      const bridge: TestNativeBridge = new TestNativeBridge();
      const scope: AccountScope = createScope(bridge);

      const fakePicker: FakeMediaPicker = new FakeMediaPicker();
      fakePicker.nextFilesToReturn = [{
        uri: 'file://docs/report.pdf',
        path: '/data/storage/el2/base/docs/report.pdf',
        name: 'report.pdf',
        size: 2048000,
        mimeType: 'application/pdf'
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

      coordinator.pickAndSendFile();

      // Wait a tick for async pickFile promise
      await new Promise<void>((resolve) => setTimeout(resolve, 50));

      expect(fakePicker.pickFileCalls).assertEqual(1);

      // Verify that sendMessage was dispatched over bridge with inputMessageDocument
      let foundSendMessage = false;
      for (let i = 0; i < bridge.sent.length; i++) {
        const req: Record<string, TdWireValue> = JSON.parse(bridge.sent[i].utf8) as Record<string, TdWireValue>;
        if (req['@type'] === 'sendMessage') {
          foundSendMessage = true;
          expect(req['chat_id']).assertEqual(42);
          const content = req['input_message_content'] as Record<string, TdWireValue>;
          expect(content['@type']).assertEqual('inputMessageDocument');
          const doc = content['document'] as Record<string, TdWireValue>;
          expect(doc['@type']).assertEqual('inputDocument');
          const file = doc['document'] as Record<string, TdWireValue>;
          expect(file['path']).assertEqual('/data/storage/el2/base/docs/report.pdf');
          break;
        }
      }
      expect(foundSendMessage).assertTrue();

      coordinator.destroy();
    });

    it('cancelMediaDownload calls cancelDownloadFile on fileRegistry', 0, (): void => {
      const bridge: TestNativeBridge = new TestNativeBridge();
      const scope: AccountScope = createScope(bridge);

      const coordinator: ChatCoordinator = new ChatCoordinator(
        scope,
        42,
        'Test Chat'
      );

      const res: Result<import('@tgx/td-gateway').TdPendingRequest, AppError> = coordinator.cancelMediaDownload(5005);
      expect(res.ok).assertTrue();

      const sent: Record<string, TdWireValue> = bridge.lastSentJson();
      expect(sent['@type']).assertEqual('cancelDownloadFile');
      expect(sent['file_id']).assertEqual(5005);

      coordinator.destroy();
    });

    it('dispatch CancelMediaDownload sends cancelDownloadFile to bridge', 0, (): void => {
      const bridge: TestNativeBridge = new TestNativeBridge();
      const scope: AccountScope = createScope(bridge);

      const coordinator: ChatCoordinator = new ChatCoordinator(
        scope,
        42,
        'Test Chat'
      );

      coordinator.dispatch(new CancelMediaDownload(5005));

      const sent: Record<string, TdWireValue> = bridge.lastSentJson();
      expect(sent['@type']).assertEqual('cancelDownloadFile');
      expect(sent['file_id']).assertEqual(5005);

      coordinator.destroy();
    });

    it('pickAndSendFile aborts cleanly when user cancels selection', 0, async (): Promise<void> => {
      const bridge: TestNativeBridge = new TestNativeBridge();
      const scope: AccountScope = createScope(bridge);

      const fakePicker: FakeMediaPicker = new FakeMediaPicker();
      fakePicker.nextFilesToReturn = []; // User cancelled / no file selected

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

      coordinator.dispatch(new PickAndSendFile());
      await new Promise<void>((resolve) => setTimeout(resolve, 50));

      expect(fakePicker.pickFileCalls).assertEqual(1);
      // No sendMessage should be dispatched
      for (let i = 0; i < bridge.sent.length; i++) {
        const req: Record<string, TdWireValue> = JSON.parse(bridge.sent[i].utf8) as Record<string, TdWireValue>;
        expect(req['@type'] !== 'sendMessage').assertTrue();
      }

      coordinator.destroy();
    });

  });
}
