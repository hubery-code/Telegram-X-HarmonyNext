/**
 * core/domain — FileRegistry 单元测试（FILE-101）。
 *
 * 覆盖：
 * 1. 缓存存取与就地更新（putFile, getFile, in-place update）；
 * 2. UpdateFile 事件监听与回调机制（subscribeFile, Gateway updates）；
 * 3. Subscription 契约与退订（isActive, unsubscribe 幂等, stop 生命周期）；
 * 4. 路径与下载进度解析（isDownloaded, getLocalPath, getDownloadProgress）；
 * 5. downloadFile 与 cancelDownloadFile TDLib 组包及响应结算。
 */

import { describe, it, expect } from '@ohos/hypium';
import {
  File,
  LocalFile,
  RemoteFile,
  encodeFile
} from '@tgx/core-td-api-generated';
import {
  AccountScope,
  buildAccountDirectories,
  createDescriptor,
  AccountDirectoryLayout
} from '@tgx/core-account';
import { FakeAppFiles, Subscription } from '@tgx/platform-ports';
import {
  TdNativeBridgeLike,
  TdNativeBridgeMetrics,
  TdNativeEvent,
  TdNativeEventSink,
  TdWireObject,
  TdWireValue
} from '@tgx/td-gateway';
import { Result, AppError } from '@tgx/core-common';
import { FileRegistry } from '../../main/ets/file/FileRegistry';

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
  const layoutRes: Result<AccountDirectoryLayout, AppError> = buildAccountDirectories('test_user_file');
  if (layoutRes.ok === false) {
    throw new Error('Failed to build directories');
  }
  const scopeRes: Result<AccountScope, AppError> = AccountScope.open({
    bridge: bridge,
    files: new FakeAppFiles(),
    descriptor: createDescriptor('test_user_file', 'acct_file_1', 0, true),
    directories: layoutRes.value,
    startActive: true
  });
  if (scopeRes.ok === false) {
    throw new Error('Failed to open AccountScope');
  }
  return scopeRes.value;
}

function createSampleFile(
  id: number,
  size: number = 1000,
  expectedSize: number = 1000,
  path: string = '',
  isCompleted: boolean = false,
  isActive: boolean = false,
  downloadedSize: number = 0
): File {
  const file: File = new File();
  file.id = id;
  file.size = size;
  file.expected_size = expectedSize;
  const local: LocalFile = new LocalFile();
  local.path = path;
  local.can_be_downloaded = true;
  local.can_be_deleted = false;
  local.is_downloading_active = isActive;
  local.is_downloading_completed = isCompleted;
  local.download_offset = 0;
  local.downloaded_prefix_size = downloadedSize;
  local.downloaded_size = downloadedSize;
  file.local = local;
  return file;
}

function makeFileUpdateFields(fileWire: TdWireObject): Record<string, TdWireValue> {
  const fields: Record<string, TdWireValue> = {};
  fields['file'] = fileWire;
  return fields;
}

export default function fileRegistryTest(): void {
  describe('FileRegistry', (): void => {

    it('should store and retrieve files in cache', 0, (): void => {
      const bridge: TestNativeBridge = new TestNativeBridge();
      const scope: AccountScope = createScope(bridge);
      const registry: FileRegistry = new FileRegistry(scope);

      expect(registry.getFile(101)).assertNull();

      const file: File = createSampleFile(101, 2048, 2048, '', false, true, 512);
      registry.putFile(file);

      const cached: File | null = registry.getFile(101);
      expect(cached !== null).assertTrue();
      if (cached !== null) {
        expect(cached.id).assertEqual(101);
        expect(cached.size).assertEqual(2048);
        expect(cached.local !== null).assertTrue();
        if (cached.local !== null) {
          expect(cached.local.downloaded_size).assertEqual(512);
          expect(cached.local.is_downloading_active).assertTrue();
        }
      }

      registry.stop();
    });

    it('should update existing file in-place on putFile', 0, (): void => {
      const bridge: TestNativeBridge = new TestNativeBridge();
      const scope: AccountScope = createScope(bridge);
      const registry: FileRegistry = new FileRegistry(scope);

      const file1: File = createSampleFile(201, 1000, 1000, '', false, true, 200);
      registry.putFile(file1);

      const cachedRef: File | null = registry.getFile(201);
      expect(cachedRef !== null).assertTrue();

      const file2: File = createSampleFile(201, 1000, 1000, '/path/doc.pdf', true, false, 1000);
      registry.putFile(file2);

      const cachedAfter: File | null = registry.getFile(201);
      expect(cachedAfter === cachedRef).assertTrue();
      if (cachedAfter !== null && cachedAfter.local !== null) {
        expect(cachedAfter.local.path).assertEqual('/path/doc.pdf');
        expect(cachedAfter.local.is_downloading_completed).assertTrue();
        expect(cachedAfter.local.is_downloading_active).assertFalse();
        expect(cachedAfter.local.downloaded_size).assertEqual(1000);
      }

      registry.stop();
    });

    it('should handle UpdateFile from Gateway and notify subscribers', 0, (): void => {
      const bridge: TestNativeBridge = new TestNativeBridge();
      const scope: AccountScope = createScope(bridge);
      const registry: FileRegistry = new FileRegistry(scope);

      const initial: File = createSampleFile(301, 5000, 5000, '', false, true, 1000);
      registry.putFile(initial);

      let callbackCount: number = 0;
      let notifiedFile: File | null = null;
      const sub: Subscription = registry.subscribeFile(301, (f: File): void => {
        callbackCount += 1;
        notifiedFile = f;
      });

      expect(sub.isActive).assertTrue();

      const updatedFile: File = createSampleFile(301, 5000, 5000, '/data/downloads/301.bin', true, false, 5000);
      const wireFile: Record<string, TdWireValue> = encodeFile(updatedFile) as Record<string, TdWireValue>;

      bridge.emitUpdate(scope.clientId, 'updateFile', makeFileUpdateFields(wireFile as TdWireObject));

      expect(callbackCount).assertEqual(1);
      expect(notifiedFile !== null).assertTrue();
      if (notifiedFile !== null) {
        const nf: File = notifiedFile as File;
        expect(nf.id).assertEqual(301);
        if (nf.local !== null) {
          expect(nf.local.path).assertEqual('/data/downloads/301.bin');
          expect(nf.local.is_downloading_completed).assertTrue();
          expect(nf.local.downloaded_size).assertEqual(5000);
        }
      }

      const cached: File | null = registry.getFile(301);
      expect(cached === initial).assertTrue();
      if (cached !== null && cached.local !== null) {
        expect(cached.local.path).assertEqual('/data/downloads/301.bin');
        expect(cached.local.is_downloading_completed).assertTrue();
      }

      sub.unsubscribe();
      registry.stop();
    });

    it('should not notify subscribers of different fileIds', 0, (): void => {
      const bridge: TestNativeBridge = new TestNativeBridge();
      const scope: AccountScope = createScope(bridge);
      const registry: FileRegistry = new FileRegistry(scope);

      let callback302: number = 0;
      let callback303: number = 0;

      const sub1: Subscription = registry.subscribeFile(302, (): void => {
        callback302 += 1;
      });
      const sub2: Subscription = registry.subscribeFile(303, (): void => {
        callback303 += 1;
      });

      const file302: File = createSampleFile(302, 100, 100, '', false, true, 50);
      bridge.emitUpdate(scope.clientId, 'updateFile', makeFileUpdateFields(encodeFile(file302) as TdWireObject));

      expect(callback302).assertEqual(1);
      expect(callback303).assertEqual(0);

      sub1.unsubscribe();
      sub2.unsubscribe();
      registry.stop();
    });

    it('should support multiple listeners on the same fileId', 0, (): void => {
      const bridge: TestNativeBridge = new TestNativeBridge();
      const scope: AccountScope = createScope(bridge);
      const registry: FileRegistry = new FileRegistry(scope);

      let listener1Called: boolean = false;
      let listener2Called: boolean = false;

      const sub1: Subscription = registry.subscribeFile(401, (): void => {
        listener1Called = true;
      });
      const sub2: Subscription = registry.subscribeFile(401, (): void => {
        listener2Called = true;
      });

      registry.putFile(createSampleFile(401, 200, 200));

      expect(listener1Called).assertTrue();
      expect(listener2Called).assertTrue();

      sub1.unsubscribe();
      sub2.unsubscribe();
      registry.stop();
    });

    it('should properly unsubscribe and handle idempotent unsubscribe', 0, (): void => {
      const bridge: TestNativeBridge = new TestNativeBridge();
      const scope: AccountScope = createScope(bridge);
      const registry: FileRegistry = new FileRegistry(scope);

      let callCount: number = 0;
      const sub: Subscription = registry.subscribeFile(501, (): void => {
        callCount += 1;
      });

      expect(sub.isActive).assertTrue();
      registry.putFile(createSampleFile(501, 100, 100));
      expect(callCount).assertEqual(1);

      sub.unsubscribe();
      expect(sub.isActive).assertFalse();

      // Idempotent call
      sub.unsubscribe();
      expect(sub.isActive).assertFalse();

      // Further update does not trigger listener
      registry.putFile(createSampleFile(501, 200, 200));
      expect(callCount).assertEqual(1);

      registry.stop();
    });

    it('should stop registry and clear listeners', 0, (): void => {
      const bridge: TestNativeBridge = new TestNativeBridge();
      const scope: AccountScope = createScope(bridge);
      const registry: FileRegistry = new FileRegistry(scope);

      let called: boolean = false;
      registry.subscribeFile(601, (): void => {
        called = true;
      });

      registry.stop();

      const f: File = createSampleFile(601, 300, 300);
      bridge.emitUpdate(scope.clientId, 'updateFile', makeFileUpdateFields(encodeFile(f) as TdWireObject));

      expect(called).assertFalse();
    });

    it('should correctly determine isDownloaded status', 0, (): void => {
      const bridge: TestNativeBridge = new TestNativeBridge();
      const scope: AccountScope = createScope(bridge);
      const registry: FileRegistry = new FileRegistry(scope);

      expect(registry.isDownloaded(701)).assertFalse();

      const notDownloaded: File = createSampleFile(701, 1000, 1000, '', false, true, 500);
      registry.putFile(notDownloaded);
      expect(registry.isDownloaded(701)).assertFalse();

      const downloaded: File = createSampleFile(701, 1000, 1000, '/local/path', true, false, 1000);
      registry.putFile(downloaded);
      expect(registry.isDownloaded(701)).assertTrue();

      const noLocal: File = new File();
      noLocal.id = 702;
      registry.putFile(noLocal);
      expect(registry.isDownloaded(702)).assertFalse();

      registry.stop();
    });

    it('should correctly parse getLocalPath', 0, (): void => {
      const bridge: TestNativeBridge = new TestNativeBridge();
      const scope: AccountScope = createScope(bridge);
      const registry: FileRegistry = new FileRegistry(scope);

      expect(registry.getLocalPath(801)).assertNull();

      const emptyPath: File = createSampleFile(801, 1000, 1000, '');
      registry.putFile(emptyPath);
      expect(registry.getLocalPath(801)).assertNull();

      const validPath: File = createSampleFile(801, 1000, 1000, '/storage/media/801.jpg');
      registry.putFile(validPath);
      expect(registry.getLocalPath(801)).assertEqual('/storage/media/801.jpg');

      registry.stop();
    });

    it('should correctly calculate getDownloadProgress', 0, (): void => {
      const bridge: TestNativeBridge = new TestNativeBridge();
      const scope: AccountScope = createScope(bridge);
      const registry: FileRegistry = new FileRegistry(scope);

      // Unknown file
      expect(registry.getDownloadProgress(901)).assertEqual(0.0);

      // Completed file gives 1.0 immediately
      const completed: File = createSampleFile(901, 1000, 1000, '/p', true, false, 500);
      registry.putFile(completed);
      expect(registry.getDownloadProgress(901)).assertEqual(1.0);

      // 50% progress by size
      const half: File = createSampleFile(902, 1000, 1000, '', false, true, 500);
      registry.putFile(half);
      expect(registry.getDownloadProgress(902)).assertEqual(0.5);

      // Progress by expected_size when size is 0
      const byExpected: File = createSampleFile(903, 0, 2000, '', false, true, 500);
      registry.putFile(byExpected);
      expect(registry.getDownloadProgress(903)).assertEqual(0.25);

      // 0 downloaded
      const zero: File = createSampleFile(904, 1000, 1000, '', false, false, 0);
      registry.putFile(zero);
      expect(registry.getDownloadProgress(904)).assertEqual(0.0);

      // Clamped when downloaded exceeds total size
      const overflow: File = createSampleFile(905, 1000, 1000, '', false, true, 1500);
      registry.putFile(overflow);
      expect(registry.getDownloadProgress(905)).assertEqual(1.0);

      // Total size is 0
      const unknownSize: File = createSampleFile(906, 0, 0, '', false, true, 100);
      registry.putFile(unknownSize);
      expect(registry.getDownloadProgress(906)).assertEqual(0.0);

      registry.stop();
    });

    it('should assemble downloadFile request with default and custom arguments', 0, (): void => {
      const bridge: TestNativeBridge = new TestNativeBridge();
      const scope: AccountScope = createScope(bridge);
      const registry: FileRegistry = new FileRegistry(scope);

      // 1. Default arguments
      const res1: Result<import('@tgx/td-gateway').TdPendingRequest, AppError> = registry.downloadFile(1001);
      expect(res1.ok).assertTrue();

      const sent1: Record<string, TdWireValue> = bridge.lastSentJson();
      expect(sent1['@type']).assertEqual('downloadFile');
      expect(sent1['file_id']).assertEqual(1001);
      expect(sent1['priority']).assertEqual(1);
      expect(sent1['offset']).assertEqual(0);
      expect(sent1['limit']).assertEqual(0);
      expect(sent1['synchronous']).assertEqual(false);

      // 2. Custom arguments
      const res2: Result<import('@tgx/td-gateway').TdPendingRequest, AppError> =
        registry.downloadFile(1002, 16, 512, 10240, true);
      expect(res2.ok).assertTrue();

      const sent2: Record<string, TdWireValue> = bridge.lastSentJson();
      expect(sent2['@type']).assertEqual('downloadFile');
      expect(sent2['file_id']).assertEqual(1002);
      expect(sent2['priority']).assertEqual(16);
      expect(sent2['offset']).assertEqual(512);
      expect(sent2['limit']).assertEqual(10240);
      expect(sent2['synchronous']).assertEqual(true);

      registry.stop();
    });

    it('should update cache when downloadFile promise resolves with File', 0, async (): Promise<void> => {
      const bridge: TestNativeBridge = new TestNativeBridge();
      const scope: AccountScope = createScope(bridge);
      const registry: FileRegistry = new FileRegistry(scope);

      const res: Result<import('@tgx/td-gateway').TdPendingRequest, AppError> = registry.downloadFile(1003);
      expect(res.ok).assertTrue();
      if (res.ok) {
        const requestId: string = res.value.requestId;
        const responseFile: File = createSampleFile(1003, 8000, 8000, '', false, true, 100);
        const wireFile: Record<string, TdWireValue> = encodeFile(responseFile) as Record<string, TdWireValue>;

        bridge.emitResponse(scope.clientId, requestId, wireFile);

        await res.value.promise;

        const cached: File | null = registry.getFile(1003);
        expect(cached !== null).assertTrue();
        if (cached !== null && cached.local !== null) {
          expect(cached.local.is_downloading_active).assertTrue();
          expect(cached.local.downloaded_size).assertEqual(100);
        }
      }

      registry.stop();
    });

    it('should assemble cancelDownloadFile request with default and custom arguments', 0, (): void => {
      const bridge: TestNativeBridge = new TestNativeBridge();
      const scope: AccountScope = createScope(bridge);
      const registry: FileRegistry = new FileRegistry(scope);

      // 1. Default arguments
      const res1: Result<import('@tgx/td-gateway').TdPendingRequest, AppError> = registry.cancelDownloadFile(2001);
      expect(res1.ok).assertTrue();

      const sent1: Record<string, TdWireValue> = bridge.lastSentJson();
      expect(sent1['@type']).assertEqual('cancelDownloadFile');
      expect(sent1['file_id']).assertEqual(2001);
      expect(sent1['only_if_pending']).assertEqual(false);

      // 2. onlyIfPending = true
      const res2: Result<import('@tgx/td-gateway').TdPendingRequest, AppError> =
        registry.cancelDownloadFile(2002, true);
      expect(res2.ok).assertTrue();

      const sent2: Record<string, TdWireValue> = bridge.lastSentJson();
      expect(sent2['@type']).assertEqual('cancelDownloadFile');
      expect(sent2['file_id']).assertEqual(2002);
      expect(sent2['only_if_pending']).assertEqual(true);

      registry.stop();
    });

    it('should correctly report isUploading, isUploaded, and getUploadProgress', 0, (): void => {
      const bridge: TestNativeBridge = new TestNativeBridge();
      const scope: AccountScope = createScope(bridge);
      const registry: FileRegistry = new FileRegistry(scope);

      // 1. Unknown file
      expect(registry.isUploading(999)).assertFalse();
      expect(registry.isUploaded(999)).assertFalse();
      expect(registry.getUploadProgress(999)).assertEqual(0.0);

      // 2. Active upload file
      const uploadingFile: File = new File();
      uploadingFile.id = 5001;
      uploadingFile.size = 1000;
      uploadingFile.remote = new RemoteFile();
      uploadingFile.remote.is_uploading_active = true;
      uploadingFile.remote.is_uploading_completed = false;
      uploadingFile.remote.uploaded_size = 400;

      registry.putFile(uploadingFile);
      expect(registry.isUploading(5001)).assertTrue();
      expect(registry.isUploaded(5001)).assertFalse();
      expect(registry.getUploadProgress(5001)).assertEqual(0.4);

      // 3. Completed upload file
      const completedFile: File = new File();
      completedFile.id = 5002;
      completedFile.size = 1000;
      completedFile.remote = new RemoteFile();
      completedFile.remote.is_uploading_active = false;
      completedFile.remote.is_uploading_completed = true;
      completedFile.remote.uploaded_size = 1000;

      registry.putFile(completedFile);
      expect(registry.isUploading(5002)).assertFalse();
      expect(registry.isUploaded(5002)).assertTrue();
      expect(registry.getUploadProgress(5002)).assertEqual(1.0);

      registry.stop();
    });

  });
}
