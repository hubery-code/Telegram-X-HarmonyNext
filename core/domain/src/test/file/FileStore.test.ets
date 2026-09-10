/**
 * core/domain — FileStore 单元测试（FILE-102）。
 *
 * 覆盖：
 * 1. 并发限制生效（maxConcurrentDownloads 控制活跃任务数，超额请求进入队列）；
 * 2. 优先级调度与 FIFO（高优先级优先执行，相同优先级按加入顺序执行）；
 * 3. 完成通知后自动拉起下一个排队任务（监听 FileRegistry.subscribeFile 推进队列）；
 * 4. pauseAll 和 resumeAll 全局挂起与恢复调度；
 * 5. 单任务 pause 与 resume 调度流转；
 * 6. cancel 移除排队或活跃任务，并自动补位；
 * 7. 断网 setNetworkAvailable(false) 挂起与恢复；
 * 8. 已下载文件直接标记 completed；
 * 9. 下载失败时槽位清理与后续任务拉起；
 * 10. 排队任务重新提升优先级后队列重排。
 */

import { describe, it, expect } from '@ohos/hypium';
import {
  File,
  LocalFile,
  RemoteFile
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
import { FileRegistry } from '../../main/ets/file/FileRegistry';
import { FileStore, FileDownloadTask, TaskStatus, FileDownloadStatus } from '../../main/ets/file/FileStore';

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
    const keys: string[] = Object.keys(fields);
    for (let i = 0; i < keys.length; i++) {
      const key: string = keys[i];
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

    const sinkKeys: number[] = [];
    this.sinks.forEach((_: TdNativeEventSink, key: number): void => {
      sinkKeys.push(key);
    });

    for (let i = 0; i < sinkKeys.length; i++) {
      const id: number = sinkKeys[i];
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
  const layoutRes: Result<AccountDirectoryLayout, AppError> = buildAccountDirectories('test_user_filestore');
  if (layoutRes.ok === false) {
    throw new Error('Failed to build directories');
  }
  const scopeRes: Result<AccountScope, AppError> = AccountScope.open({
    bridge: bridge,
    files: new FakeAppFiles(),
    descriptor: createDescriptor('test_user_filestore', 'acct_filestore_1', 0, true),
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

export default function fileStoreTest(): void {
  describe('FileStore', (): void => {

    it('should enforce concurrency limit (2 active, 2 queued)', 0, (): void => {
      const bridge: TestNativeBridge = new TestNativeBridge();
      const scope: AccountScope = createScope(bridge);
      const registry: FileRegistry = new FileRegistry(scope);
      const store: FileStore = new FileStore(registry, 2);

      store.enqueue(1);
      store.enqueue(2);
      store.enqueue(3);
      store.enqueue(4);

      expect(store.getActiveCount()).assertEqual(2);
      expect(store.getQueuedCount()).assertEqual(2);

      expect(store.getTaskStatus(1)).assertEqual('downloading');
      expect(store.getTaskStatus(2)).assertEqual('downloading');
      expect(store.getTaskStatus(3)).assertEqual('queued');
      expect(store.getTaskStatus(4)).assertEqual('queued');

      expect(bridge.sent.length).assertEqual(2);

      store.clear();
      registry.stop();
    });

    it('should schedule tasks based on priority (high priority jumps queue) and FIFO for same priority', 0, (): void => {
      const bridge: TestNativeBridge = new TestNativeBridge();
      const scope: AccountScope = createScope(bridge);
      const registry: FileRegistry = new FileRegistry(scope);
      const store: FileStore = new FileStore(registry, 1);

      // Task 10: priority 1 -> starts downloading immediately
      store.enqueue(10, 1);
      expect(store.getActiveCount()).assertEqual(1);
      expect(store.getTaskStatus(10)).assertEqual('downloading');

      // Task 20: priority 5 -> queued
      store.enqueue(20, 5);
      // Task 30: priority 10 -> queued (higher than 20, jumps ahead)
      store.enqueue(30, 10);
      // Task 40: priority 5 -> queued (same priority as 20, but behind 20 due to FIFO)
      store.enqueue(40, 5);

      expect(store.getQueuedCount()).assertEqual(3);

      // Complete task 10
      registry.putFile(createSampleFile(10, 1000, 1000, '/data/10', true));
      expect(store.getTaskStatus(10)).assertEqual('completed');

      // Task 30 (priority 10) must start next
      expect(store.getTaskStatus(30)).assertEqual('downloading');
      expect(store.getActiveCount()).assertEqual(1);
      expect(store.getQueuedCount()).assertEqual(2);

      // Complete task 30
      registry.putFile(createSampleFile(30, 1000, 1000, '/data/30', true));
      expect(store.getTaskStatus(30)).assertEqual('completed');

      // Task 20 (priority 5, joined before task 40) must start next
      expect(store.getTaskStatus(20)).assertEqual('downloading');

      // Complete task 20
      registry.putFile(createSampleFile(20, 1000, 1000, '/data/20', true));
      expect(store.getTaskStatus(20)).assertEqual('completed');

      // Task 40 (priority 5, joined after task 20) must start next
      expect(store.getTaskStatus(40)).assertEqual('downloading');

      // Complete task 40
      registry.putFile(createSampleFile(40, 1000, 1000, '/data/40', true));
      expect(store.getTaskStatus(40)).assertEqual('completed');
      expect(store.getActiveCount()).assertEqual(0);
      expect(store.getQueuedCount()).assertEqual(0);

      store.clear();
      registry.stop();
    });

    it('should automatically start next queued task when download completes', 0, (): void => {
      const bridge: TestNativeBridge = new TestNativeBridge();
      const scope: AccountScope = createScope(bridge);
      const registry: FileRegistry = new FileRegistry(scope);
      const store: FileStore = new FileStore(registry, 2);

      store.enqueue(101);
      store.enqueue(102);
      store.enqueue(103);

      expect(store.getActiveCount()).assertEqual(2);
      expect(store.getQueuedCount()).assertEqual(1);
      expect(store.getTaskStatus(101)).assertEqual('downloading');
      expect(store.getTaskStatus(102)).assertEqual('downloading');
      expect(store.getTaskStatus(103)).assertEqual('queued');

      // Complete file 101 via registry update
      registry.putFile(createSampleFile(101, 2000, 2000, '/data/101', true));

      expect(store.getTaskStatus(101)).assertEqual('completed');
      expect(store.getTaskStatus(103)).assertEqual('downloading');
      expect(store.getActiveCount()).assertEqual(2);
      expect(store.getQueuedCount()).assertEqual(0);

      store.clear();
      registry.stop();
    });

    it('should pauseAll and resumeAll properly', 0, (): void => {
      const bridge: TestNativeBridge = new TestNativeBridge();
      const scope: AccountScope = createScope(bridge);
      const registry: FileRegistry = new FileRegistry(scope);
      const store: FileStore = new FileStore(registry, 2);

      store.enqueue(1);
      store.enqueue(2);
      store.enqueue(3);
      store.enqueue(4);

      expect(store.getActiveCount()).assertEqual(2);
      expect(store.getQueuedCount()).assertEqual(2);

      store.pauseAll();

      expect(store.getActiveCount()).assertEqual(0);
      expect(store.getQueuedCount()).assertEqual(0);
      expect(store.getTaskStatus(1)).assertEqual('paused');
      expect(store.getTaskStatus(2)).assertEqual('paused');
      expect(store.getTaskStatus(3)).assertEqual('paused');
      expect(store.getTaskStatus(4)).assertEqual('paused');

      store.resumeAll();

      expect(store.getActiveCount()).assertEqual(2);
      expect(store.getQueuedCount()).assertEqual(2);
      expect(store.getTaskStatus(1)).assertEqual('downloading');
      expect(store.getTaskStatus(2)).assertEqual('downloading');
      expect(store.getTaskStatus(3)).assertEqual('queued');
      expect(store.getTaskStatus(4)).assertEqual('queued');

      store.clear();
      registry.stop();
    });

    it('should pause and resume a single task', 0, (): void => {
      const bridge: TestNativeBridge = new TestNativeBridge();
      const scope: AccountScope = createScope(bridge);
      const registry: FileRegistry = new FileRegistry(scope);
      const store: FileStore = new FileStore(registry, 1);

      store.enqueue(1);
      store.enqueue(2);

      expect(store.getTaskStatus(1)).assertEqual('downloading');
      expect(store.getTaskStatus(2)).assertEqual('queued');

      // Pause task 1: active slot freed, task 2 starts downloading
      store.pause(1);
      expect(store.getTaskStatus(1)).assertEqual('paused');
      expect(store.getTaskStatus(2)).assertEqual('downloading');
      expect(store.getActiveCount()).assertEqual(1);
      expect(store.getQueuedCount()).assertEqual(0);

      // Resume task 1: re-enters queue
      store.resume(1);
      expect(store.getTaskStatus(1)).assertEqual('queued');
      expect(store.getQueuedCount()).assertEqual(1);

      // Complete task 2 -> task 1 resumes downloading
      registry.putFile(createSampleFile(2, 500, 500, '/path/2', true));
      expect(store.getTaskStatus(2)).assertEqual('completed');
      expect(store.getTaskStatus(1)).assertEqual('downloading');

      store.clear();
      registry.stop();
    });

    it('should cancel downloading task and queued task', 0, (): void => {
      const bridge: TestNativeBridge = new TestNativeBridge();
      const scope: AccountScope = createScope(bridge);
      const registry: FileRegistry = new FileRegistry(scope);
      const store: FileStore = new FileStore(registry, 2);

      store.enqueue(1);
      store.enqueue(2);
      store.enqueue(3);

      expect(store.getActiveCount()).assertEqual(2);
      expect(store.getQueuedCount()).assertEqual(1);

      // Cancel queued task 3
      store.cancel(3);
      expect(store.getTaskStatus(3)).assertEqual('canceled');
      expect(store.getQueuedCount()).assertEqual(0);
      expect(store.getActiveCount()).assertEqual(2);

      // Cancel downloading task 1
      store.cancel(1);
      expect(store.getTaskStatus(1)).assertEqual('canceled');
      expect(store.getActiveCount()).assertEqual(1);
      expect(store.getTaskStatus(2)).assertEqual('downloading');

      // Check TDLib cancelDownloadFile was dispatched
      const lastJson: Record<string, TdWireValue> = bridge.lastSentJson();
      expect(lastJson['@type']).assertEqual('cancelDownloadFile');
      expect(lastJson['file_id']).assertEqual(1);

      store.clear();
      registry.stop();
    });

    it('should suspend tasks on network loss and resume when network is restored', 0, (): void => {
      const bridge: TestNativeBridge = new TestNativeBridge();
      const scope: AccountScope = createScope(bridge);
      const registry: FileRegistry = new FileRegistry(scope);
      const store: FileStore = new FileStore(registry, 2);

      store.enqueue(1);
      store.enqueue(2);
      store.enqueue(3);
      store.enqueue(4);

      expect(store.getActiveCount()).assertEqual(2);
      expect(store.getQueuedCount()).assertEqual(2);

      store.setNetworkAvailable(false);

      expect(store.isNetworkConnected()).assertFalse();
      expect(store.getActiveCount()).assertEqual(0);
      expect(store.getQueuedCount()).assertEqual(0);
      expect(store.getTaskStatus(1)).assertEqual('paused');
      expect(store.getTaskStatus(2)).assertEqual('paused');
      expect(store.getTaskStatus(3)).assertEqual('paused');
      expect(store.getTaskStatus(4)).assertEqual('paused');

      store.setNetworkAvailable(true);

      expect(store.isNetworkConnected()).assertTrue();
      expect(store.getActiveCount()).assertEqual(2);
      expect(store.getQueuedCount()).assertEqual(2);
      expect(store.getTaskStatus(1)).assertEqual('downloading');
      expect(store.getTaskStatus(2)).assertEqual('downloading');
      expect(store.getTaskStatus(3)).assertEqual('queued');
      expect(store.getTaskStatus(4)).assertEqual('queued');

      store.clear();
      registry.stop();
    });

    it('should mark already downloaded file as completed immediately', 0, (): void => {
      const bridge: TestNativeBridge = new TestNativeBridge();
      const scope: AccountScope = createScope(bridge);
      const registry: FileRegistry = new FileRegistry(scope);
      const store: FileStore = new FileStore(registry, 2);

      const downloadedFile: File = createSampleFile(99, 1024, 1024, '/cache/99.bin', true);
      registry.putFile(downloadedFile);

      store.enqueue(99);

      expect(store.getTaskStatus(99)).assertEqual('completed');
      expect(store.getActiveCount()).assertEqual(0);
      expect(store.getQueuedCount()).assertEqual(0);

      store.clear();
      registry.stop();
    });

    it('should handle download failure and pull next queued task', 0, (): void => {
      const bridge: TestNativeBridge = new TestNativeBridge();
      const scope: AccountScope = createScope(bridge);
      const registry: FileRegistry = new FileRegistry(scope);
      const store: FileStore = new FileStore(registry, 1);

      store.enqueue(1);
      store.enqueue(2);

      expect(store.getTaskStatus(1)).assertEqual('downloading');
      expect(store.getTaskStatus(2)).assertEqual('queued');

      // Emit failure for file 1 (can_be_downloaded = false)
      const failedFile: File = createSampleFile(1, 1000, 1000, '', false, false, 0);
      if (failedFile.local !== null) {
        failedFile.local.can_be_downloaded = false;
      }
      registry.putFile(failedFile);

      expect(store.getTaskStatus(1)).assertEqual('failed');
      expect(store.getTaskStatus(2)).assertEqual('downloading');
      expect(store.getActiveCount()).assertEqual(1);
      expect(store.getQueuedCount()).assertEqual(0);

      store.clear();
      registry.stop();
    });

    it('should update priority of queued task and reposition in queue', 0, (): void => {
      const bridge: TestNativeBridge = new TestNativeBridge();
      const scope: AccountScope = createScope(bridge);
      const registry: FileRegistry = new FileRegistry(scope);
      const store: FileStore = new FileStore(registry, 1);

      store.enqueue(1, 1); // downloading
      store.enqueue(2, 2); // queued, priority 2
      store.enqueue(3, 1); // queued, priority 1

      // Reprioritize task 3 to priority 10
      store.enqueue(3, 10);

      // Complete task 1
      registry.putFile(createSampleFile(1, 1000, 1000, '/data/1', true));
      expect(store.getTaskStatus(1)).assertEqual('completed');

      // Task 3 should start first because it was boosted to priority 10
      expect(store.getTaskStatus(3)).assertEqual('downloading');

      store.clear();
      registry.stop();
    });

    it('should support inspecting and dynamically adjusting maxConcurrentDownloads', 0, (): void => {
      const bridge: TestNativeBridge = new TestNativeBridge();
      const scope: AccountScope = createScope(bridge);
      const registry: FileRegistry = new FileRegistry(scope);
      const store: FileStore = new FileStore(registry, 1);

      expect(store.getMaxConcurrentDownloads()).assertEqual(1);

      store.enqueue(1);
      store.enqueue(2);

      expect(store.getActiveCount()).assertEqual(1);
      expect(store.getQueuedCount()).assertEqual(1);

      const task1: FileDownloadTask | null = store.getTask(1);
      expect(task1 !== null).assertTrue();
      if (task1 !== null) {
        expect(task1.fileId).assertEqual(1);
        expect(task1.status).assertEqual('downloading');
      }

      // Dynamically increase concurrency to 2 -> immediately schedules task 2
      store.setMaxConcurrentDownloads(2);
      expect(store.getMaxConcurrentDownloads()).assertEqual(2);
      expect(store.getActiveCount()).assertEqual(2);
      expect(store.getQueuedCount()).assertEqual(0);
      expect(store.getTaskStatus(2)).assertEqual('downloading');

      // Invalid concurrency is ignored
      store.setMaxConcurrentDownloads(0);
      expect(store.getMaxConcurrentDownloads()).assertEqual(2);

      store.clear();
      registry.stop();
    });

    it('should pause and resume a queued task directly', 0, (): void => {
      const bridge: TestNativeBridge = new TestNativeBridge();
      const scope: AccountScope = createScope(bridge);
      const registry: FileRegistry = new FileRegistry(scope);
      const store: FileStore = new FileStore(registry, 1);

      store.enqueue(1); // downloading
      store.enqueue(2); // queued

      // Pause queued task 2
      store.pause(2);
      expect(store.getTaskStatus(2)).assertEqual('paused');
      expect(store.getQueuedCount()).assertEqual(0);

      // Resume task 2 -> re-enters queue
      store.resume(2);
      expect(store.getTaskStatus(2)).assertEqual('queued');
      expect(store.getQueuedCount()).assertEqual(1);

      store.clear();
      registry.stop();
    });

  });
}
