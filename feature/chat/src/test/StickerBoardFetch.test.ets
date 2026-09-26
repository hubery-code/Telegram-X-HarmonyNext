/**
 * feature/chat — 贴纸板取数链路的协调器接线测试（STICKER-BOARD-101）。
 *
 * 纯函数那半边由 StickerBoard.test.ets 守；这里只守「板卡真的接上 TDLib」：
 * - 开板发的是 `getInstalledStickerSets` 且 `sticker_type` 是 regular（吃 stickerTypeMask 会
 *   把整页变成表情包，且这个请求在 reducer 里已经去重，所以这里连点两次只允许一条请求）；
 * - 回包要真的落到 `uiState.stickerBoard.packs`，并只为缩略图登记下载（不是贴纸整图）；
 * - 请求失败要有错误态，且**不会**被记成「已加载」—— 否则这个会话里贴纸页签就永远空着。
 *
 * STICKER-BOARD-102 又接上热门区那半边：
 * - 开板同时问一次 `getTrendingStickerSets`（regular、offset 0、limit 6），且去重同理由；
 * - 榜单回包真的落到 `stickerBoard.trending`，一包只登记那一张封面；
 * - 榜单失败**不占** `errorMessage`（那个槽说的是自己的包读不到），也不动已装盘；
 * - 从热门行装包：`changeStickerSet` 只发一条、在途有 `installingSetId`、成功后立刻重读盘与榜。
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
import { ChatUiState } from '../main/ets/contract/ChatUiState';
import { InstallStickerSet, OpenStickerBoard } from '../main/ets/contract/ChatIntent';
import { StickerBoardPack, StickerTrendingPack } from '../main/ets/model/StickerBoard';

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
    this.sent.push({ clientId: clientId, utf8: requestUtf8 });
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

  private emit(payload: TdWireObject): void {
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

  /** 回一条带 @extra.requestId 的响应（走 RequestRegistry 关联，非 update 流）。 */
  respondTo(requestId: string, fields: Record<string, TdWireValue>): void {
    const extra: Record<string, TdWireValue> = {};
    extra['requestId'] = requestId;
    const payload: TdWireObject = {};
    for (const key of Object.keys(fields)) {
      payload[key] = fields[key];
    }
    payload['@extra'] = extra;
    this.emit(payload);
  }

  respondError(requestId: string, message: string): void {
    this.respondTo(requestId, errorFields(message));
  }
}

function errorFields(message: string): Record<string, TdWireValue> {
  const error: Record<string, TdWireValue> = {};
  error['@type'] = 'error';
  error['code'] = 400;
  error['message'] = message;
  return error;
}

/** changeStickerSet 的回包是 `ok`：只要不是 error，协调器就按成功走。 */
function okFields(): Record<string, TdWireValue> {
  const fields: Record<string, TdWireValue> = {};
  fields['@type'] = 'ok';
  return fields;
}

function createScope(bridge: TestNativeBridge): AccountScope {
  const layoutRes: Result<AccountDirectoryLayout, AppError> = buildAccountDirectories('test_sticker_board');
  if (layoutRes.ok === false) {
    throw new Error('Failed to build directories');
  }
  const scopeRes: Result<AccountScope, AppError> = AccountScope.open({
    bridge: bridge,
    files: new FakeAppFiles(),
    descriptor: createDescriptor('test_sticker_board', 'acct_user_1', 0, true),
    directories: layoutRes.value,
    startActive: true
  });
  if (scopeRes.ok === false) {
    throw new Error('Failed to open AccountScope');
  }
  return scopeRes.value;
}

function settle(): Promise<void> {
  return new Promise<void>((resolve) => setTimeout(resolve, 30));
}

/** 状态订阅记录：取最后一帧，类型上不需要处理「一帧都没有」的空态。 */
class StateRecorder {
  readonly seen: ChatUiState[] = [];

  last(): ChatUiState {
    return this.seen[this.seen.length - 1];
  }
}

function requestsOfType(bridge: TestNativeBridge, type: string): Record<string, TdWireValue>[] {
  const matched: Record<string, TdWireValue>[] = [];
  for (let i = 0; i < bridge.sent.length; i++) {
    const req: Record<string, TdWireValue> = JSON.parse(bridge.sent[i].utf8) as Record<string, TdWireValue>;
    if (req['@type'] === type) {
      matched.push(req);
    }
  }
  return matched;
}

function lastRequestIdOfType(bridge: TestNativeBridge, type: string): string {
  const matched: Record<string, TdWireValue>[] = requestsOfType(bridge, type);
  if (matched.length === 0) {
    return '';
  }
  const extra: Record<string, TdWireValue> | undefined =
    matched[matched.length - 1]['@extra'] as Record<string, TdWireValue> | undefined;
  return extra !== undefined && extra !== null ? String(extra['requestId']) : '';
}

function countRequestsOfType(bridge: TestNativeBridge, type: string): number {
  return requestsOfType(bridge, type).length;
}

function fileFields(fileId: number): Record<string, TdWireValue> {
  const local: Record<string, TdWireValue> = {};
  local['@type'] = 'localFile';
  local['path'] = '';
  local['can_be_downloaded'] = true;
  local['can_be_deleted'] = false;
  local['is_downloading_active'] = false;
  local['is_downloading_completed'] = false;
  local['download_offset'] = 0;
  local['downloaded_prefix_size'] = 0;
  local['downloaded_size'] = 0;

  const file: Record<string, TdWireValue> = {};
  file['@type'] = 'file';
  file['id'] = fileId;
  file['size'] = 1024;
  file['expected_size'] = 1024;
  file['local'] = local;
  return file;
}

function thumbnailFields(fileId: number): Record<string, TdWireValue> {
  const thumb: Record<string, TdWireValue> = {};
  thumb['@type'] = 'thumbnail';
  thumb['file'] = fileFields(fileId);
  return thumb;
}

function coverFields(fileId: number, thumbId: number, emoji: string): Record<string, TdWireValue> {
  const cover: Record<string, TdWireValue> = {};
  cover['@type'] = 'sticker';
  cover['set_id'] = '21';
  cover['width'] = 512;
  cover['height'] = 512;
  cover['emoji'] = emoji;
  cover['sticker'] = fileFields(fileId);
  cover['thumbnail'] = thumbId > 0 ? thumbnailFields(thumbId) : null;
  return cover;
}

function stickerSetsFields(covers: Record<string, TdWireValue>[]): Record<string, TdWireValue> {
  const info: Record<string, TdWireValue> = {};
  info['@type'] = 'stickerSetInfo';
  info['id'] = '21';
  info['title'] = 'Pandamonium';
  info['name'] = 'pandamonium_by_tgx';
  info['thumbnail'] = thumbnailFields(900);
  info['is_installed'] = true;
  info['is_archived'] = false;
  info['sticker_type'] = stickerTypeRegularFields();
  info['size'] = covers.length + 7;
  info['covers'] = covers;

  const fields: Record<string, TdWireValue> = {};
  fields['@type'] = 'stickerSets';
  fields['total_count'] = 1;
  fields['sets'] = [info];
  return fields;
}

function stickerTypeRegularFields(): Record<string, TdWireValue> {
  const type: Record<string, TdWireValue> = {};
  type['@type'] = 'stickerTypeRegular';
  return type;
}

function trendingCoverFields(setId: string, fileId: number, thumbId: number): Record<string, TdWireValue> {
  const cover: Record<string, TdWireValue> = {};
  cover['@type'] = 'sticker';
  cover['set_id'] = setId;
  cover['width'] = 512;
  cover['height'] = 512;
  cover['emoji'] = '🐼';
  cover['sticker'] = fileFields(fileId);
  cover['thumbnail'] = thumbId > 0 ? thumbnailFields(thumbId) : null;
  return cover;
}

/** 一榜两包：第一包带包级缩略图，第二包只有封面缩略图（走取值兜底那条路）。 */
function trendingSetsFields(): Record<string, TdWireValue> {
  const withPackThumb: Record<string, TdWireValue> = {};
  withPackThumb['@type'] = 'stickerSetInfo';
  withPackThumb['id'] = '51';
  withPackThumb['title'] = 'Trending Cats';
  withPackThumb['name'] = 'trending_cats';
  withPackThumb['thumbnail'] = thumbnailFields(4500);
  withPackThumb['is_installed'] = false;
  withPackThumb['is_archived'] = false;
  withPackThumb['sticker_type'] = stickerTypeRegularFields();
  withPackThumb['size'] = 37;
  withPackThumb['covers'] = [trendingCoverFields('51', 1501, 3501)];

  const coverOnly: Record<string, TdWireValue> = {};
  coverOnly['@type'] = 'stickerSetInfo';
  coverOnly['id'] = '52';
  coverOnly['title'] = 'Trending Dogs';
  coverOnly['name'] = 'trending_dogs';
  coverOnly['thumbnail'] = null;
  coverOnly['is_installed'] = true;
  coverOnly['is_archived'] = false;
  coverOnly['sticker_type'] = stickerTypeRegularFields();
  coverOnly['size'] = 12;
  coverOnly['covers'] = [trendingCoverFields('52', 1502, 3502)];

  const fields: Record<string, TdWireValue> = {};
  fields['@type'] = 'trendingStickerSets';
  fields['total_count'] = 2;
  fields['sets'] = [withPackThumb, coverOnly];
  fields['is_premium'] = false;
  return fields;
}

export default function stickerBoardFetchTest(): void {
  describe('StickerBoardFetchTest', () => {

    it('openStickerBoard_requestsRegularInstalledSetsOnce', 0, async (): Promise<void> => {
      const bridge: TestNativeBridge = new TestNativeBridge();
      const scope: AccountScope = createScope(bridge);
      const coordinator: ChatCoordinator = new ChatCoordinator(scope, 42, 'Test Chat');

      // 页签反复进出：reducer 在 isLoading 时不再发 effect，这里再证明一次请求侧也只有一条。
      coordinator.dispatch(new OpenStickerBoard());
      coordinator.dispatch(new OpenStickerBoard());
      await settle();

      const reqs: Record<string, TdWireValue>[] = requestsOfType(bridge, 'getInstalledStickerSets');
      expect(reqs.length).assertEqual(1);
      const stickerType = reqs[0]['sticker_type'] as Record<string, TdWireValue>;
      expect(stickerType['@type']).assertEqual('stickerTypeRegular');

      coordinator.destroy();
    });

    it('installedSetsResponse_populatesBoardAndDownloadsThumbnailsOnly', 0, async (): Promise<void> => {
      const bridge: TestNativeBridge = new TestNativeBridge();
      const scope: AccountScope = createScope(bridge);
      const coordinator: ChatCoordinator = new ChatCoordinator(scope, 42, 'Test Chat');

      const recorder: StateRecorder = new StateRecorder();
      const unsubscribe: () => void = coordinator.subscribe((state: ChatUiState): void => {
        recorder.seen.push(state);
      });

      coordinator.dispatch(new OpenStickerBoard());
      await settle();
      const requestId: string = lastRequestIdOfType(bridge, 'getInstalledStickerSets');
      expect(requestId.length > 0).assertTrue();
      bridge.respondTo(requestId, stickerSetsFields([
        coverFields(1001, 3001, '🐼'),
        coverFields(1002, 3002, '🎋')
      ]));
      await settle();

      const state: ChatUiState = recorder.last();
      const packs: StickerBoardPack[] = state.stickerBoard.packs;
      expect(packs.length).assertEqual(1);
      expect(packs[0].setId).assertEqual('21');
      expect(packs[0].title).assertEqual('Pandamonium');
      expect(packs[0].covers.length).assertEqual(2);
      // covers 只是前 5 张，size 更大时必须标出整包还有内容（界面上的「查看其余 N 张」吃这个差值）。
      expect(packs[0].hasMore).assertTrue();
      expect(packs[0].totalSize).assertEqual(9);
      expect(state.stickerBoard.isLoaded).assertTrue();
      expect(state.stickerBoard.isLoading).assertFalse();
      expect(state.stickerBoard.errorMessage).assertNull();

      // 装盘只登记缩略图：包 thumbnail(900) + 两张封面 thumbnail(3001/3002)；
      // 贴纸整图（1001/1002）点了要发才下，不能在这一步放出去。
      expect(countRequestsOfType(bridge, 'downloadFile')).assertEqual(3);
      expect(countRequestsOfType(bridge, 'getInstalledStickerSets')).assertEqual(1);

      unsubscribe();
      coordinator.destroy();
    });

    it('failedRequest_setsErrorAndRefetchesOnNextOpen', 0, async (): Promise<void> => {
      const bridge: TestNativeBridge = new TestNativeBridge();
      const scope: AccountScope = createScope(bridge);
      const coordinator: ChatCoordinator = new ChatCoordinator(scope, 42, 'Test Chat');

      const recorder: StateRecorder = new StateRecorder();
      const unsubscribe: () => void = coordinator.subscribe((state: ChatUiState): void => {
        recorder.seen.push(state);
      });

      coordinator.dispatch(new OpenStickerBoard());
      await settle();
      const requestId: string = lastRequestIdOfType(bridge, 'getInstalledStickerSets');
      expect(requestId.length > 0).assertTrue();
      bridge.respondError(requestId, 'REQUEST_TIMEOUT');
      await settle();

      const state: ChatUiState = recorder.last();
      expect(state.stickerBoard.isLoading).assertFalse();
      // 错误原文只进状态给界面看「这次没读到」，不是「没有贴纸包」；空包 + 错误才是失败态。
      expect(state.stickerBoard.errorMessage !== null).assertTrue();
      expect(state.stickerBoard.packs.length).assertEqual(0);
      // 关键：失败不能标成已加载，否则本次会话再也进不了贴纸页签。
      expect(state.stickerBoard.isLoaded).assertFalse();

      coordinator.dispatch(new OpenStickerBoard());
      await settle();
      expect(countRequestsOfType(bridge, 'getInstalledStickerSets')).assertEqual(2);

      unsubscribe();
      coordinator.destroy();
    });

    // ---------- STICKER-BOARD-102：热门区与装包 ----------

    it('openStickerBoard_requestsRegularTrendingSetsOnce', 0, async (): Promise<void> => {
      const bridge: TestNativeBridge = new TestNativeBridge();
      const scope: AccountScope = createScope(bridge);
      const coordinator: ChatCoordinator = new ChatCoordinator(scope, 42, 'Test Chat');

      coordinator.dispatch(new OpenStickerBoard());
      coordinator.dispatch(new OpenStickerBoard());
      await settle();

      const reqs: Record<string, TdWireValue>[] = requestsOfType(bridge, 'getTrendingStickerSets');
      expect(reqs.length).assertEqual(1);
      // sticker_type 是必填，且三个类型各一张榜：取错类型等于把热门区变成表情包
      const stickerType = reqs[0]['sticker_type'] as Record<string, TdWireValue>;
      expect(stickerType['@type']).assertEqual('stickerTypeRegular');
      expect(reqs[0]['offset']).assertEqual(0);
      expect(reqs[0]['limit']).assertEqual(6);

      coordinator.destroy();
    });

    it('trendingResponse_populatesRows_andRegistersOneCoverPerRow', 0, async (): Promise<void> => {
      const bridge: TestNativeBridge = new TestNativeBridge();
      const scope: AccountScope = createScope(bridge);
      const coordinator: ChatCoordinator = new ChatCoordinator(scope, 42, 'Test Chat');

      const recorder: StateRecorder = new StateRecorder();
      const unsubscribe: () => void = coordinator.subscribe((state: ChatUiState): void => {
        recorder.seen.push(state);
      });

      coordinator.dispatch(new OpenStickerBoard());
      await settle();
      const requestId: string = lastRequestIdOfType(bridge, 'getTrendingStickerSets');
      expect(requestId.length > 0).assertTrue();
      bridge.respondTo(requestId, trendingSetsFields());
      await settle();

      const rows: StickerTrendingPack[] = recorder.last().stickerBoard.trending;
      expect(rows.length).assertEqual(2);
      expect(rows[0].setId).assertEqual('51');
      expect(rows[0].title).assertEqual('Trending Cats');
      expect(rows[0].totalSize).assertEqual(37);
      expect(rows[0].isInstalled).assertFalse();
      expect(rows[1].isInstalled).assertTrue();

      // 一包只登记那一张封面（4500 是包缩略图、3502 是第二包唯一的封面缩略图）；
      // 整图 1501/1502 不属于这一步。
      expect(countRequestsOfType(bridge, 'downloadFile')).assertEqual(2);
      const downloads: Record<string, TdWireValue>[] = requestsOfType(bridge, 'downloadFile');
      const ids: number[] = [];
      for (let i = 0; i < downloads.length; i++) {
        ids.push(Number(downloads[i]['file_id']));
      }
      expect(ids.indexOf(1501)).assertEqual(-1);
      expect(ids.indexOf(1502)).assertEqual(-1);
      expect(ids.indexOf(4500) >= 0).assertTrue();
      expect(ids.indexOf(3502) >= 0).assertTrue();

      unsubscribe();
      coordinator.destroy();
    });

    it('trendingFailure_leavesTheBoardAlone', 0, async (): Promise<void> => {
      const bridge: TestNativeBridge = new TestNativeBridge();
      const scope: AccountScope = createScope(bridge);
      const coordinator: ChatCoordinator = new ChatCoordinator(scope, 42, 'Test Chat');

      const recorder: StateRecorder = new StateRecorder();
      const unsubscribe: () => void = coordinator.subscribe((state: ChatUiState): void => {
        recorder.seen.push(state);
      });

      coordinator.dispatch(new OpenStickerBoard());
      await settle();
      bridge.respondTo(lastRequestIdOfType(bridge, 'getInstalledStickerSets'), stickerSetsFields([
        coverFields(1001, 3001, '🐼')
      ]));
      await settle();
      bridge.respondError(lastRequestIdOfType(bridge, 'getTrendingStickerSets'), 'REQUEST_TIMEOUT');
      await settle();

      const state: ChatUiState = recorder.last();
      // 榜单是装饰性入口：它失败不能写成「你的贴纸包读不到」，也不能清掉已装的盘
      expect(state.stickerBoard.errorMessage).assertNull();
      expect(state.stickerBoard.trending.length).assertEqual(0);
      expect(state.stickerBoard.packs.length).assertEqual(1);
      expect(state.stickerBoard.isLoaded).assertTrue();
      // 失败也算问过：切走再切回来不该反复重试一个坏请求
      expect(state.stickerBoard.trendingRequested).assertTrue();

      unsubscribe();
      coordinator.destroy();
    });

    it('installFromTrendingRow_writesChangeStickerSet_andRefetchesBoard', 0, async (): Promise<void> => {
      const bridge: TestNativeBridge = new TestNativeBridge();
      const scope: AccountScope = createScope(bridge);
      const coordinator: ChatCoordinator = new ChatCoordinator(scope, 42, 'Test Chat');

      const recorder: StateRecorder = new StateRecorder();
      const unsubscribe: () => void = coordinator.subscribe((state: ChatUiState): void => {
        recorder.seen.push(state);
      });

      coordinator.dispatch(new OpenStickerBoard());
      await settle();
      bridge.respondTo(lastRequestIdOfType(bridge, 'getTrendingStickerSets'), trendingSetsFields());
      await settle();
      expect(recorder.last().stickerBoard.trending[0].isInstalled).assertFalse();

      const before: number = countRequestsOfType(bridge, 'getInstalledStickerSets');
      coordinator.dispatch(new InstallStickerSet('51'));
      await settle();

      const changes: Record<string, TdWireValue>[] = requestsOfType(bridge, 'changeStickerSet');
      expect(changes.length).assertEqual(1);
      expect(changes[0]['set_id']).assertEqual('51');
      expect(changes[0]['is_installed']).assertTrue();
      // 请求还在途：那一行只能显示「在途」，不能提前替 TDLib 宣布装好了
      expect(recorder.last().stickerBoard.installingSetId).assertEqual('51');

      bridge.respondTo(lastRequestIdOfType(bridge, 'changeStickerSet'), okFields());
      await settle();

      const after: ChatUiState = recorder.last();
      expect(after.stickerBoard.installingSetId).assertNull();
      expect(after.stickerBoard.trending[0].isInstalled).assertTrue();
      // 装成功后立刻重读盘与榜 —— 新装的包不用等用户切走再切回来
      expect(countRequestsOfType(bridge, 'getInstalledStickerSets')).assertEqual(before + 1);
      expect(countRequestsOfType(bridge, 'getTrendingStickerSets')).assertEqual(2);

      unsubscribe();
      coordinator.destroy();
    });
  });
}
