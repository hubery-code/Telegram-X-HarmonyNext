/**
 * feature/chat — 媒体下载去重与「清理缓存后可重下」单元测试（SET-104 / FEAT-SET-004）。
 *
 * 覆盖 ChatCoordinator.requestMediaDownload 的去重闩语义：
 * - 下载中保持闩住，投影每帧重复请求不得放大成 TDLib downloadFile 洪水；
 * - TDLib 把文件重置为未下载（optimizeStorage 清理本地缓存）后必须放行重新下载；
 * - 下载完成后同样放行（同一文件二次清理仍能重下）。
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
import { Result, AppError } from '@tgx/core-common';
import { ChatCoordinator } from '../main/ets/coordinator/ChatCoordinator';
import { RequestMediaDownload } from '../main/ets/contract/ChatIntent';

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
  const layoutRes: Result<AccountDirectoryLayout, AppError> = buildAccountDirectories('test_media_redownload');
  if (layoutRes.ok === false) {
    throw new Error('Failed to build directories');
  }
  const scopeRes: Result<AccountScope, AppError> = AccountScope.open({
    bridge: bridge,
    files: new FakeAppFiles(),
    descriptor: createDescriptor('test_media_redownload', 'acct_user_1', 0, true),
    directories: layoutRes.value,
    startActive: true
  });
  if (scopeRes.ok === false) {
    throw new Error('Failed to open AccountScope');
  }
  return scopeRes.value;
}

/** 构造一条 updateFile 负载：local 状态由入参决定（模拟下载中 / 已完成 / 清理后重置）。 */
function updateFilePayload(fileId: number, active: boolean, completed: boolean): Record<string, TdWireValue> {
  const local: Record<string, TdWireValue> = {};
  local['@type'] = 'localFile';
  local['path'] = completed ? '/data/local/tmp/' + fileId : '';
  local['can_be_downloaded'] = true;
  local['can_be_deleted'] = true;
  local['is_downloading_active'] = active;
  local['is_downloading_completed'] = completed;
  local['download_offset'] = 0;
  local['downloaded_prefix_size'] = 0;
  local['downloaded_size'] = completed ? 10000 : (active ? 4000 : 0);

  const remote: Record<string, TdWireValue> = {};
  remote['@type'] = 'remoteFile';
  remote['id'] = 'remote_' + fileId;
  remote['unique_id'] = 'unique_' + fileId;
  remote['is_uploading_active'] = false;
  remote['is_uploading_completed'] = true;
  remote['uploaded_size'] = 10000;

  const file: Record<string, TdWireValue> = {};
  file['@type'] = 'file';
  file['id'] = fileId;
  file['size'] = 10000;
  file['expected_size'] = 10000;
  file['local'] = local;
  file['remote'] = remote;

  const fields: Record<string, TdWireValue> = {};
  fields['file'] = file;
  return fields;
}

function downloadFileRequests(bridge: TestNativeBridge, fileId: number): number {
  let count: number = 0;
  for (let i = 0; i < bridge.sent.length; i++) {
    const req: Record<string, TdWireValue> = JSON.parse(bridge.sent[i].utf8) as Record<string, TdWireValue>;
    if (req['@type'] === 'downloadFile' && req['file_id'] === fileId) {
      count += 1;
    }
  }
  return count;
}

/** 取某 fileId 最近一条 downloadFile 请求的 @extra.requestId（用于回灌 TDLib 错误）。 */
function lastDownloadRequestId(bridge: TestNativeBridge, fileId: number): string {
  for (let i = bridge.sent.length - 1; i >= 0; i--) {
    const req: Record<string, TdWireValue> = JSON.parse(bridge.sent[i].utf8) as Record<string, TdWireValue>;
    if (req['@type'] === 'downloadFile' && req['file_id'] === fileId) {
      const extra: Record<string, TdWireValue> | undefined =
        req['@extra'] as Record<string, TdWireValue> | undefined;
      return extra !== undefined && extra !== null ? String(extra['requestId']) : '';
    }
  }
  return '';
}

function settle(): Promise<void> {
  return new Promise<void>((resolve: () => void): void => {
    setTimeout(resolve, 30);
  });
}

export default function mediaRedownloadTest(): void {
  describe('MediaRedownloadTest', () => {

    it('requestMediaDownload_sendsDownloadFileOnceAndDedupesWhileActive', 0, async (): Promise<void> => {
      const bridge: TestNativeBridge = new TestNativeBridge();
      const scope: AccountScope = createScope(bridge);
      const coordinator: ChatCoordinator = new ChatCoordinator(scope, 42, 'Test Chat');

      coordinator.dispatch(new RequestMediaDownload(777));
      expect(downloadFileRequests(bridge, 777)).assertEqual(1);

      bridge.emitUpdate(1, 'updateFile', updateFilePayload(777, true, false));
      await settle();

      // 下载中：重复请求必须被去重闩挡住，不能放大成 TDLib 请求。
      coordinator.dispatch(new RequestMediaDownload(777));
      expect(downloadFileRequests(bridge, 777)).assertEqual(1);

      coordinator.destroy();
    });

    it('requestMediaDownload_reissuesAfterCacheClearResetsLocalState', 0, async (): Promise<void> => {
      const bridge: TestNativeBridge = new TestNativeBridge();
      const scope: AccountScope = createScope(bridge);
      const coordinator: ChatCoordinator = new ChatCoordinator(scope, 42, 'Test Chat');

      coordinator.dispatch(new RequestMediaDownload(888));
      expect(downloadFileRequests(bridge, 888)).assertEqual(1);

      bridge.emitUpdate(1, 'updateFile', updateFilePayload(888, true, false));
      await settle();
      // SET-104：optimizeStorage 清理本地缓存后 TDLib 把文件重置为「未下载且未在下载」。
      bridge.emitUpdate(1, 'updateFile', updateFilePayload(888, false, false));
      await settle();

      coordinator.dispatch(new RequestMediaDownload(888));
      expect(downloadFileRequests(bridge, 888)).assertEqual(2);

      coordinator.destroy();
    });

    it('requestMediaDownload_releasesLatchOnCompletionThenAllowsRedownloadAfterClear', 0, async (): Promise<void> => {
      const bridge: TestNativeBridge = new TestNativeBridge();
      const scope: AccountScope = createScope(bridge);
      const coordinator: ChatCoordinator = new ChatCoordinator(scope, 42, 'Test Chat');

      coordinator.dispatch(new RequestMediaDownload(999));
      bridge.emitUpdate(1, 'updateFile', updateFilePayload(999, false, true));
      await settle();

      // 已下载：不重复请求。
      coordinator.dispatch(new RequestMediaDownload(999));
      expect(downloadFileRequests(bridge, 999)).assertEqual(1);

      // 清理缓存 → 重置为未下载 → 完成态释放过的闩不得再次挡住下载。
      bridge.emitUpdate(1, 'updateFile', updateFilePayload(999, false, false));
      await settle();
      coordinator.dispatch(new RequestMediaDownload(999));
      expect(downloadFileRequests(bridge, 999)).assertEqual(2);

      coordinator.destroy();
    });

    it('requestMediaDownload_ignoresAlreadyDownloadedFile', 0, async (): Promise<void> => {
      const bridge: TestNativeBridge = new TestNativeBridge();
      const scope: AccountScope = createScope(bridge);
      const coordinator: ChatCoordinator = new ChatCoordinator(scope, 42, 'Test Chat');

      bridge.emitUpdate(1, 'updateFile', updateFilePayload(666, false, true));
      await settle();

      coordinator.dispatch(new RequestMediaDownload(666));
      expect(downloadFileRequests(bridge, 666)).assertEqual(0);

      coordinator.destroy();
    });

    it('requestMediaDownload_errorResponseReleasesLatchForRetry', 0, async (): Promise<void> => {
      const bridge: TestNativeBridge = new TestNativeBridge();
      const scope: AccountScope = createScope(bridge);
      const coordinator: ChatCoordinator = new ChatCoordinator(scope, 42, 'Test Chat');

      coordinator.dispatch(new RequestMediaDownload(555));
      expect(downloadFileRequests(bridge, 555)).assertEqual(1);

      // TDLib 直接回错误（无 updateFile 跟进）：这是唯一的失败信号，
      // 必须自己放行去重闩，否则重试按钮在同一会话里永远点不动。
      const requestId: string = lastDownloadRequestId(bridge, 555);
      expect(requestId.length > 0).assertTrue();
      const extra: Record<string, TdWireValue> = {};
      extra['requestId'] = requestId;
      const fields: Record<string, TdWireValue> = {};
      fields['@extra'] = extra;
      fields['code'] = 404;
      fields['message'] = 'FILE_ID_INVALID';
      bridge.emitUpdate(1, 'error', fields);
      await settle();

      coordinator.dispatch(new RequestMediaDownload(555));
      expect(downloadFileRequests(bridge, 555)).assertEqual(2);

      coordinator.destroy();
    });
  });
}
