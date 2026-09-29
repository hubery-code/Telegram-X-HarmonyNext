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
 *
 * STICKER-RECENT-101 接上最近使用那半边：
 * - 开板问的是 `getRecentStickers` 且 `is_attached=false`（贴在照片上的那一串不是这一行），
 *   并且和盘、榜一样一次会话只问一次 —— 失败也算问过；
 * - 回包按 TDLib 给的顺序进 `uiState.recentStickers`，只为缩略图登记下载；
 * - 「清空」要把服务端那半边写回去（`clearRecentStickers`），写失败必须重读，
 *   否则屏上留下一个「看着清空了、下次打开又全在」的假象；
 * - `updateRecentStickers` 到货后这一行要自己活过来，但**没开过贴纸页签时不许后台重读**。
 *
 * STICKER-FETCH-102 守整包取数那条链（此前零覆盖，也正是第十五轮把配置问题误判成服务端问题的地方）：
 * - 本地已经见过这一包（盘/榜的 DTO 里有短名）时**第一条**请求是 `searchStickerSet`，
 *   且 `ignore_cache=false` —— true 会让 TDLib 跳过 `StickersManager.cpp:5005-5018` 那条
 *   零网络的缓存分支，量到的就不是 Android 一直在用的配置；
 * - 没见过短名的 id 才直接 `getStickerSet`，不先发一次注定失败的短名查询；
 * - 短名那条失败要按 id 兜底重发，两条**都**失败只记一次失败态（不能盖成两条错误）；
 * - 短名那条成功就出整包，此时 `getStickerSet` 一条都不许发。
 *
 * STICKER-BOARD-103 守已装盘的自愈那半边：
 * - 冷启动读到 0 行后，`updateInstalledStickerSets` 到货要重读并把真列表装上盘
 *   （此前这一路订阅不存在，空盘会一直空到本次会话结束）；
 * - 没开过贴纸页签不后台重读；`stickerTypeMask`/`stickerTypeCustomEmoji` 的推送不参与这一区。
 *
 * STICKER-BOARD-104 守那条订阅带来的副作用：装/卸一包同时有两条失效（reducer 那条 + TDLib
 * 推送那条），两条都要留、但不许并发读盘 —— 在途期间只登记「结算后补读一次」。
 *
 * STICKER-BOARD-105 守剩下那半边：设备实测两条失效并不总是同刻（推送先到、读盘先结算，
 * `changeStickerSet` 的 promise 隔 77~166 ms 才回），所以门塌不掉第二次读盘。这里钉住
 * 「权威那条已经读到 → 兜底省掉」，以及两条负向对照：订阅从未响过、权威那条读失败时，
 * 兜底都必须照旧发出。
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
import { ClearRecentStickers, InstallStickerSet, OpenStickerBoard, OpenStickerSet } from '../main/ets/contract/ChatIntent';
import { StickerBoardPack, StickerTrendingPack } from '../main/ets/model/StickerBoard';
import { StickerSetItem, StickerSetPreviewState } from '../main/ets/model/StickerSetPreviewState';

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

  /** 注入一条 push update（走 update 流，不带 @extra，因此不会被请求关联吃掉）。 */
  pushUpdate(payload: TdWireObject): void {
    this.emit(payload);
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

/**
 * 带数字码的错误包：整包取数的 406 分两个来源（服务端 `STICKERSET_INVALID` /
 * TDLib 本地重写的 `FROZEN_METHOD_INVALID`），只有 `code` 也能进用例才测得动分类链。
 */
function errorFieldsWith(code: number, message: string): Record<string, TdWireValue> {
  const error: Record<string, TdWireValue> = {};
  error['@type'] = 'error';
  error['code'] = code;
  error['message'] = message;
  return error;
}

/** `getStickerSet` / `searchStickerSet` 的成功回包是完整 `stickerSet`（不是 `stickerSetInfo`）。 */
function stickerSetFields(stickers: Record<string, TdWireValue>[]): Record<string, TdWireValue> {
  const fields: Record<string, TdWireValue> = {};
  fields['@type'] = 'stickerSet';
  fields['id'] = '21';
  fields['title'] = 'Pandamonium';
  fields['name'] = 'pandamonium_by_tgx';
  fields['thumbnail'] = thumbnailFields(900);
  fields['is_owned'] = false;
  fields['is_installed'] = true;
  fields['is_archived'] = false;
  fields['is_official'] = false;
  fields['sticker_type'] = stickerTypeRegularFields();
  fields['needs_repainting'] = false;
  fields['is_viewed'] = true;
  fields['stickers'] = stickers;
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

/** `getRecentStickers` 的回包是 `stickers`：只有 `stickers` 一个字段，没有 total_count。 */
function recentStickersFields(stickers: Record<string, TdWireValue>[]): Record<string, TdWireValue> {
  const fields: Record<string, TdWireValue> = {};
  fields['@type'] = 'stickers';
  fields['stickers'] = stickers;
  return fields;
}

function recentStickerFields(fileId: number, thumbId: number, emoji: string): Record<string, TdWireValue> {
  const sticker: Record<string, TdWireValue> = {};
  sticker['@type'] = 'sticker';
  sticker['set_id'] = '21';
  sticker['width'] = 512;
  sticker['height'] = 512;
  sticker['emoji'] = emoji;
  sticker['sticker'] = fileFields(fileId);
  sticker['thumbnail'] = thumbId > 0 ? thumbnailFields(thumbId) : null;
  return sticker;
}

function recentUpdateFields(isAttached: boolean, stickerIds: number[]): Record<string, TdWireValue> {
  const fields: Record<string, TdWireValue> = {};
  fields['@type'] = 'updateRecentStickers';
  fields['is_attached'] = isAttached;
  fields['sticker_ids'] = stickerIds;
  return fields;
}

/** `updateFavoriteStickers` 一个字段都不带：TDLib 只说「收藏变了」，列表得自己重读。 */
function favoriteUpdateFields(): Record<string, TdWireValue> {
  const fields: Record<string, TdWireValue> = {};
  fields['@type'] = 'updateFavoriteStickers';
  return fields;
}

/**
 * STICKER-BOARD-103：`updateInstalledStickerSets` 的推送体。
 * `sticker_set_ids` 只给 id，包名/封面还得回 `getInstalledStickerSets` 读 —— 所以这一路是「重读」而不是「直接用」。
 */
function installedUpdateFields(kind: string, stickerSetIds: string[]): Record<string, TdWireValue> {
  const type: Record<string, TdWireValue> = {};
  type['@type'] = kind;
  const fields: Record<string, TdWireValue> = {};
  fields['@type'] = 'updateInstalledStickerSets';
  fields['sticker_type'] = type;
  fields['sticker_set_ids'] = stickerSetIds;
  return fields;
}

/** 冷启动第一帧：TDLib 的缓存还没建好时 `getInstalledStickerSets` 合法的 0 行回包。 */
function emptyStickerSetsFields(): Record<string, TdWireValue> {
  const fields: Record<string, TdWireValue> = {};
  fields['@type'] = 'stickerSets';
  fields['total_count'] = 0;
  fields['sets'] = [];
  return fields;
}

/**
 * 把贴纸页签开到「已装盘读回来」的状态：只有走过这一步，协调器的 DTO 缓存里才有
 * setId 21 → `pandamonium_by_tgx` 这条短名，`openStickerSet` 才会走短名那条路。
 */
async function loadBoardWithKnownSet(bridge: TestNativeBridge, coordinator: ChatCoordinator): Promise<void> {
  coordinator.dispatch(new OpenStickerBoard());
  await settle();
  bridge.respondTo(lastRequestIdOfType(bridge, 'getInstalledStickerSets'), stickerSetsFields([
    coverFields(1001, 3001, '🐼')
  ]));
  await settle();
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
      // 开板那一条读盘先结算掉：STICKER-BOARD-104 之后，在途期间的失效不再并发第二条，
      // 这里要验的是「装完确实立刻重读」，不是门的合并（合并另有那一条用例）。
      bridge.respondTo(lastRequestIdOfType(bridge, 'getInstalledStickerSets'),
        stickerSetsFields([coverFields(1001, 3001, '🐼')]));
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

    it('boardInvalidation_whileReadInFlight_collapsesIntoOneTrailingRead', 0, async (): Promise<void> => {
      // STICKER-BOARD-104：装/卸一包同时到两条失效 —— reducer 在 `changeStickerSet` 成功
      // 那一路发一条，TDLib 紧接着推 `updateInstalledStickerSets`（它先于 promise 结算）。
      // 两条都要保留（订阅可能因网关能力缺失收不到，reducer 那条是兜底），但不许并发。
      const bridge: TestNativeBridge = new TestNativeBridge();
      const scope: AccountScope = createScope(bridge);
      const coordinator: ChatCoordinator = new ChatCoordinator(scope, 42, 'Test Chat');
      coordinator.start();

      const recorder: StateRecorder = new StateRecorder();
      const unsubscribe: () => void = coordinator.subscribe((state: ChatUiState): void => {
        recorder.seen.push(state);
      });

      coordinator.dispatch(new OpenStickerBoard());
      await settle();
      bridge.respondTo(lastRequestIdOfType(bridge, 'getInstalledStickerSets'),
        stickerSetsFields([coverFields(1001, 3001, '🐼')]));
      await settle();
      expect(countRequestsOfType(bridge, 'getInstalledStickerSets')).assertEqual(1);

      // 第一条推送让盘重读，并且**故意不回答**：此刻一条读盘正在途
      bridge.pushUpdate(installedUpdateFields('stickerTypeRegular', ['21']));
      await settle();
      const inFlight: string = lastRequestIdOfType(bridge, 'getInstalledStickerSets');
      expect(countRequestsOfType(bridge, 'getInstalledStickerSets')).assertEqual(2);

      // 再来两次失效：不许并发，只登记成「结算后补读一次」
      bridge.pushUpdate(installedUpdateFields('stickerTypeRegular', ['21', '24']));
      bridge.pushUpdate(installedUpdateFields('stickerTypeRegular', ['21', '24', '25']));
      await settle();
      expect(countRequestsOfType(bridge, 'getInstalledStickerSets')).assertEqual(2);

      // 在途那条结算 —— 补读必须跟上，否则屏上停在它读到的那份新列表（TDLib 的推送先于 promise）
      bridge.respondTo(inFlight, emptyStickerSetsFields());
      await settle();
      expect(countRequestsOfType(bridge, 'getInstalledStickerSets')).assertEqual(3);
      expect(recorder.last().stickerBoard.packs.length).assertEqual(0);

      bridge.respondTo(lastRequestIdOfType(bridge, 'getInstalledStickerSets'),
        stickerSetsFields([coverFields(2001, 4001, '🦊')]));
      await settle();
      expect(recorder.last().stickerBoard.packs.length).assertEqual(1);
      expect(recorder.last().stickerBoard.packs[0].covers[0].emoji).assertEqual('🦊');
      // 三次在途失效只换来「一条在途 + 一条补读」，没有第四次
      await settle();
      expect(countRequestsOfType(bridge, 'getInstalledStickerSets')).assertEqual(3);

      unsubscribe();
      coordinator.destroy();
    });

    it('boardInvalidation_afterAuthoritativeRead_skipsTheChangeFallback', 0, async (): Promise<void> => {
      // STICKER-BOARD-105：设备实测的顺序（`.hvigor/outputs/board104-check/`）—— 推送先到、
      // 权威那条读盘先结算，`changeStickerSet` 的 promise 隔 77~166 ms 才回来。到那一刻屏上
      // 已经是新列表，兜底那条读到的是同一份 —— 省掉；热门榜照旧读一次。
      const bridge: TestNativeBridge = new TestNativeBridge();
      const scope: AccountScope = createScope(bridge);
      const coordinator: ChatCoordinator = new ChatCoordinator(scope, 42, 'Test Chat');
      coordinator.start();

      const recorder: StateRecorder = new StateRecorder();
      const unsubscribe: () => void = coordinator.subscribe((state: ChatUiState): void => {
        recorder.seen.push(state);
      });

      coordinator.dispatch(new OpenStickerBoard());
      await settle();
      bridge.respondTo(lastRequestIdOfType(bridge, 'getInstalledStickerSets'),
        stickerSetsFields([coverFields(1001, 3001, '🐼')]));
      bridge.respondTo(lastRequestIdOfType(bridge, 'getTrendingStickerSets'), trendingSetsFields());
      await settle();
      expect(countRequestsOfType(bridge, 'getInstalledStickerSets')).assertEqual(1);

      coordinator.dispatch(new InstallStickerSet('51'));
      await settle();

      // 推送先响：权威那一条读盘发出并结算
      bridge.pushUpdate(installedUpdateFields('stickerTypeRegular', ['51']));
      await settle();
      expect(countRequestsOfType(bridge, 'getInstalledStickerSets')).assertEqual(2);
      bridge.respondTo(lastRequestIdOfType(bridge, 'getInstalledStickerSets'),
        stickerSetsFields([coverFields(1001, 3001, '🐼')]));
      await settle();

      // promise 随后才结算：兜底那条被省，榜仍要读
      bridge.respondTo(lastRequestIdOfType(bridge, 'changeStickerSet'), okFields());
      await settle();
      expect(countRequestsOfType(bridge, 'getInstalledStickerSets')).assertEqual(2);
      expect(countRequestsOfType(bridge, 'getTrendingStickerSets')).assertEqual(2);
      expect(recorder.last().stickerBoard.installingSetId).assertNull();
      expect(recorder.last().stickerBoard.trending[0].isInstalled).assertTrue();
      expect(recorder.last().stickerBoard.packs.length).assertEqual(1);

      unsubscribe();
      coordinator.destroy();
    });

    it('boardInvalidation_failedAuthoritativeRead_stillRunsTheFallback', 0, async (): Promise<void> => {
      // 负向对照：权威那条**读失败**时不能让兜底一起被省掉，否则屏上停在坏结果。
      const bridge: TestNativeBridge = new TestNativeBridge();
      const scope: AccountScope = createScope(bridge);
      const coordinator: ChatCoordinator = new ChatCoordinator(scope, 42, 'Test Chat');
      coordinator.start();

      const recorder: StateRecorder = new StateRecorder();
      const unsubscribe: () => void = coordinator.subscribe((state: ChatUiState): void => {
        recorder.seen.push(state);
      });

      coordinator.dispatch(new OpenStickerBoard());
      await settle();
      bridge.respondTo(lastRequestIdOfType(bridge, 'getInstalledStickerSets'),
        stickerSetsFields([coverFields(1001, 3001, '🐼')]));
      await settle();

      coordinator.dispatch(new InstallStickerSet('51'));
      await settle();
      bridge.pushUpdate(installedUpdateFields('stickerTypeRegular', ['51']));
      await settle();
      expect(countRequestsOfType(bridge, 'getInstalledStickerSets')).assertEqual(2);
      bridge.respondError(lastRequestIdOfType(bridge, 'getInstalledStickerSets'), 'REQUEST_TIMEOUT');
      await settle();
      // 失败不清包（上一次的内容比空白有用），但必须留下「这次没读到」的错误态
      expect(recorder.last().stickerBoard.errorMessage !== null).assertTrue();
      expect(recorder.last().stickerBoard.packs.length).assertEqual(1);

      bridge.respondTo(lastRequestIdOfType(bridge, 'changeStickerSet'), okFields());
      await settle();
      // 坏结算不算「覆盖」：兜底必须补上这一条
      expect(countRequestsOfType(bridge, 'getInstalledStickerSets')).assertEqual(3);
      bridge.respondTo(lastRequestIdOfType(bridge, 'getInstalledStickerSets'),
        stickerSetsFields([coverFields(1001, 3001, '🐼'), coverFields(2001, 4001, '🦊')]));
      await settle();
      expect(recorder.last().stickerBoard.errorMessage).assertNull();
      expect(recorder.last().stickerBoard.packs[0].covers.length).assertEqual(2);

      unsubscribe();
      coordinator.destroy();
    });

    // ---------- STICKER-RECENT-101：最近使用接 getRecentStickers ----------

    it('openStickerBoard_requestsNonAttachedRecentStickersOnce', 0, async (): Promise<void> => {
      const bridge: TestNativeBridge = new TestNativeBridge();
      const scope: AccountScope = createScope(bridge);
      const coordinator: ChatCoordinator = new ChatCoordinator(scope, 42, 'Test Chat');

      coordinator.dispatch(new OpenStickerBoard());
      coordinator.dispatch(new OpenStickerBoard());
      await settle();

      const reqs: Record<string, TdWireValue>[] = requestsOfType(bridge, 'getRecentStickers');
      expect(reqs.length).assertEqual(1);
      // TDLib 里最近使用有两串：贴在照片上的那一串（is_attached=true）不是板卡这一行
      expect(reqs[0]['is_attached'] === false).assertTrue();

      coordinator.destroy();
    });

    it('recentStickersResponse_populatesRow_andDownloadsThumbnailsOnly', 0, async (): Promise<void> => {
      const bridge: TestNativeBridge = new TestNativeBridge();
      const scope: AccountScope = createScope(bridge);
      const coordinator: ChatCoordinator = new ChatCoordinator(scope, 42, 'Test Chat');

      const recorder: StateRecorder = new StateRecorder();
      const unsubscribe: () => void = coordinator.subscribe((state: ChatUiState): void => {
        recorder.seen.push(state);
      });

      coordinator.dispatch(new OpenStickerBoard());
      await settle();
      const requestId: string = lastRequestIdOfType(bridge, 'getRecentStickers');
      expect(requestId.length > 0).assertTrue();
      bridge.respondTo(requestId, recentStickersFields([
        recentStickerFields(7001, 8001, '🐼'),
        recentStickerFields(7002, 8002, '🎋')
      ]));
      await settle();

      const items: readonly StickerSetItem[] = recorder.last().recentStickers;
      expect(items.length).assertEqual(2);
      // TDLib 已经按「最近」排好；这里二次排序就是把用户刚发的那颗挪走
      expect(items[0].fileId).assertEqual(7001);
      expect(items[1].fileId).assertEqual(7002);

      // 只登记缩略图：原图等真发送时 TDLib 自己取
      const downloads: Record<string, TdWireValue>[] = requestsOfType(bridge, 'downloadFile');
      expect(downloads.length).assertEqual(2);
      const ids: number[] = [];
      for (let i = 0; i < downloads.length; i++) {
        ids.push(Number(downloads[i]['file_id']));
      }
      expect(ids.indexOf(7001)).assertEqual(-1);
      expect(ids.indexOf(8001) >= 0).assertTrue();
      expect(ids.indexOf(8002) >= 0).assertTrue();

      unsubscribe();
      coordinator.destroy();
    });

    it('recentStickersFailure_isSilentAndNotRetriedOnNextOpen', 0, async (): Promise<void> => {
      const bridge: TestNativeBridge = new TestNativeBridge();
      const scope: AccountScope = createScope(bridge);
      const coordinator: ChatCoordinator = new ChatCoordinator(scope, 42, 'Test Chat');

      const recorder: StateRecorder = new StateRecorder();
      const unsubscribe: () => void = coordinator.subscribe((state: ChatUiState): void => {
        recorder.seen.push(state);
      });

      coordinator.dispatch(new OpenStickerBoard());
      await settle();
      bridge.respondError(lastRequestIdOfType(bridge, 'getRecentStickers'), 'REQUEST_TIMEOUT');
      await settle();

      const state: ChatUiState = recorder.last();
      // 没有最近使用就是没有：不显示那一行，也不占板卡的错误槽
      expect(state.recentStickers.length).assertEqual(0);
      expect(state.stickerBoard.errorMessage).assertNull();
      // 但这一路已经问过了：切走再切回来不该反复重试一个坏请求
      coordinator.dispatch(new OpenStickerBoard());
      await settle();
      expect(countRequestsOfType(bridge, 'getRecentStickers')).assertEqual(1);

      unsubscribe();
      coordinator.destroy();
    });

    it('updateRecentStickers_refetchesOnlyWhileTheBoardIsOpen', 0, async (): Promise<void> => {
      const bridge: TestNativeBridge = new TestNativeBridge();
      const scope: AccountScope = createScope(bridge);
      const coordinator: ChatCoordinator = new ChatCoordinator(scope, 42, 'Test Chat');
      // 订阅在 `start()` 里注册（和真机一样）：不 start 就没有 `updateRecentStickers` 这一路。
      coordinator.start();

      const unsubscribe: () => void = coordinator.subscribe((_state: ChatUiState): void => {});

      // 没开过贴纸页签：没人在看这一行，后台重读只是白打一次网络
      bridge.pushUpdate(recentUpdateFields(false, [7001]));
      await settle();
      expect(countRequestsOfType(bridge, 'getRecentStickers')).assertEqual(0);

      coordinator.dispatch(new OpenStickerBoard());
      await settle();
      expect(countRequestsOfType(bridge, 'getRecentStickers')).assertEqual(1);

      bridge.pushUpdate(recentUpdateFields(false, [7002]));
      await settle();
      // 一次推送一条重读，不做防抖合并也不能漏（Android 的 onRecentStickersUpdated 同理）
      expect(countRequestsOfType(bridge, 'getRecentStickers')).assertEqual(2);

      // 贴在照片上的那一串不是这一行，重读了等于白花一次请求
      bridge.pushUpdate(recentUpdateFields(true, [7003]));
      await settle();
      expect(countRequestsOfType(bridge, 'getRecentStickers')).assertEqual(2);

      unsubscribe();
      coordinator.destroy();
    });

    // ---------- STICKER-FAV-101：收藏接 getFavoriteStickers ----------

    it('openStickerBoard_requestsFavoriteStickersOnce', 0, async (): Promise<void> => {
      const bridge: TestNativeBridge = new TestNativeBridge();
      const scope: AccountScope = createScope(bridge);
      const coordinator: ChatCoordinator = new ChatCoordinator(scope, 42, 'Test Chat');

      coordinator.dispatch(new OpenStickerBoard());
      coordinator.dispatch(new OpenStickerBoard());
      await settle();

      // `getFavoriteStickers` 无参（TDLib 的收藏只有一串，不像最近使用还分 attached）
      expect(countRequestsOfType(bridge, 'getFavoriteStickers')).assertEqual(1);
      // 且它不与最近使用共用那一条请求：两行各自的数据源
      expect(countRequestsOfType(bridge, 'getRecentStickers')).assertEqual(1);

      coordinator.destroy();
    });

    it('favoriteStickersResponse_populatesRow_andDownloadsThumbnailsOnly', 0, async (): Promise<void> => {
      const bridge: TestNativeBridge = new TestNativeBridge();
      const scope: AccountScope = createScope(bridge);
      const coordinator: ChatCoordinator = new ChatCoordinator(scope, 42, 'Test Chat');

      const recorder: StateRecorder = new StateRecorder();
      const unsubscribe: () => void = coordinator.subscribe((state: ChatUiState): void => {
        recorder.seen.push(state);
      });

      coordinator.dispatch(new OpenStickerBoard());
      await settle();
      const requestId: string = lastRequestIdOfType(bridge, 'getFavoriteStickers');
      expect(requestId.length > 0).assertTrue();
      bridge.respondTo(requestId, recentStickersFields([
        recentStickerFields(9001, 9101, '🐼'),
        recentStickerFields(9002, 9102, '🎋')
      ]));
      await settle();

      const items: readonly StickerSetItem[] = recorder.last().favoriteStickers;
      expect(items.length).assertEqual(2);
      expect(items[0].fileId).assertEqual(9001);
      // 收藏到货不动最近使用那一行（两行各自记账，混灌就是把用户刚发的贴纸换掉）
      expect(recorder.last().recentStickers.length).assertEqual(0);

      const downloads: Record<string, TdWireValue>[] = requestsOfType(bridge, 'downloadFile');
      const ids: number[] = [];
      for (let i = 0; i < downloads.length; i++) {
        ids.push(Number(downloads[i]['file_id']));
      }
      // 只登记缩略图：原图等真发送时 TDLib 自己取
      expect(ids.indexOf(9001)).assertEqual(-1);
      expect(ids.indexOf(9101) >= 0).assertTrue();
      expect(ids.indexOf(9102) >= 0).assertTrue();

      unsubscribe();
      coordinator.destroy();
    });

    it('favoriteStickersFailure_isSilentAndNotRetriedOnNextOpen', 0, async (): Promise<void> => {
      const bridge: TestNativeBridge = new TestNativeBridge();
      const scope: AccountScope = createScope(bridge);
      const coordinator: ChatCoordinator = new ChatCoordinator(scope, 42, 'Test Chat');

      const recorder: StateRecorder = new StateRecorder();
      const unsubscribe: () => void = coordinator.subscribe((state: ChatUiState): void => {
        recorder.seen.push(state);
      });

      coordinator.dispatch(new OpenStickerBoard());
      await settle();
      bridge.respondError(lastRequestIdOfType(bridge, 'getFavoriteStickers'), 'REQUEST_TIMEOUT');
      await settle();

      const state: ChatUiState = recorder.last();
      // 没有收藏就是没有：不显示那一行，也不占板卡的错误槽
      expect(state.favoriteStickers.length).assertEqual(0);
      expect(state.stickerBoard.errorMessage).assertNull();
      coordinator.dispatch(new OpenStickerBoard());
      await settle();
      expect(countRequestsOfType(bridge, 'getFavoriteStickers')).assertEqual(1);

      unsubscribe();
      coordinator.destroy();
    });

    it('updateFavoriteStickers_refetchesOnlyOnceTheBoardHasAsked', 0, async (): Promise<void> => {
      const bridge: TestNativeBridge = new TestNativeBridge();
      const scope: AccountScope = createScope(bridge);
      const coordinator: ChatCoordinator = new ChatCoordinator(scope, 42, 'Test Chat');
      // 订阅在 `start()` 里注册（和真机一样）：不 start 就没有 `updateFavoriteStickers` 这一路。
      coordinator.start();

      const unsubscribe: () => void = coordinator.subscribe((_state: ChatUiState): void => {});

      // 没开过贴纸页签：没人在看这一行，后台重读只是白打一次网络
      bridge.pushUpdate(favoriteUpdateFields());
      await settle();
      expect(countRequestsOfType(bridge, 'getFavoriteStickers')).assertEqual(0);

      coordinator.dispatch(new OpenStickerBoard());
      await settle();
      expect(countRequestsOfType(bridge, 'getFavoriteStickers')).assertEqual(1);

      bridge.pushUpdate(favoriteUpdateFields());
      await settle();
      // 一次推送一条重读（Android 的 onFavoriteStickersUpdated 同理）
      expect(countRequestsOfType(bridge, 'getFavoriteStickers')).assertEqual(2);
      // 收藏的重读不该带动最近使用那条链
      expect(countRequestsOfType(bridge, 'getRecentStickers')).assertEqual(1);

      unsubscribe();
      coordinator.destroy();
    });

    it('updateInstalledStickerSets_healsAnEmptyColdStartBoardRead', 0, async (): Promise<void> => {
      const bridge: TestNativeBridge = new TestNativeBridge();
      const scope: AccountScope = createScope(bridge);
      const coordinator: ChatCoordinator = new ChatCoordinator(scope, 42, 'Test Chat');
      coordinator.start();

      const recorder: StateRecorder = new StateRecorder();
      const unsubscribe: () => void = coordinator.subscribe((state: ChatUiState): void => {
        recorder.seen.push(state);
      });

      // 冷启动第一帧：TDLib 读的是还没建好的缓存，回包是合法的 0 行
      coordinator.dispatch(new OpenStickerBoard());
      await settle();
      bridge.respondTo(lastRequestIdOfType(bridge, 'getInstalledStickerSets'), emptyStickerSetsFields());
      await settle();
      expect(recorder.last().stickerBoard.packs.length).assertEqual(0);

      // 缓存建好后 TDLib 推一条 updateInstalledStickerSets：空盘必须是「还能活」的中间帧，
      // 不能是本次会话的最终答案（模拟器实测同账号 3.4 秒内 rows=0 → rows=1）。
      bridge.pushUpdate(installedUpdateFields('stickerTypeRegular', ['21']));
      await settle();
      expect(countRequestsOfType(bridge, 'getInstalledStickerSets')).assertEqual(2);

      bridge.respondTo(lastRequestIdOfType(bridge, 'getInstalledStickerSets'),
        stickerSetsFields([coverFields(1001, 3001, '🐼')]));
      await settle();
      expect(recorder.last().stickerBoard.packs.length).assertEqual(1);

      unsubscribe();
      coordinator.destroy();
    });

    it('updateInstalledStickerSets_ignoresUnreadBoardAndOtherTypes', 0, async (): Promise<void> => {
      const bridge: TestNativeBridge = new TestNativeBridge();
      const scope: AccountScope = createScope(bridge);
      const coordinator: ChatCoordinator = new ChatCoordinator(scope, 42, 'Test Chat');
      coordinator.start();

      const unsubscribe: () => void = coordinator.subscribe((_state: ChatUiState): void => {});

      // 没开过贴纸页签：没人在看这一区，后台重读只是白打一次网络
      bridge.pushUpdate(installedUpdateFields('stickerTypeRegular', ['21']));
      await settle();
      expect(countRequestsOfType(bridge, 'getInstalledStickerSets')).assertEqual(0);

      coordinator.dispatch(new OpenStickerBoard());
      await settle();
      bridge.respondTo(lastRequestIdOfType(bridge, 'getInstalledStickerSets'),
        stickerSetsFields([coverFields(1001, 3001, '🐼')]));
      await settle();
      expect(countRequestsOfType(bridge, 'getInstalledStickerSets')).assertEqual(1);

      // mask / custom emoji 各有各的列表，跟我们这一区无关
      bridge.pushUpdate(installedUpdateFields('stickerTypeMask', ['22']));
      bridge.pushUpdate(installedUpdateFields('stickerTypeCustomEmoji', ['23']));
      await settle();
      expect(countRequestsOfType(bridge, 'getInstalledStickerSets')).assertEqual(1);

      bridge.pushUpdate(installedUpdateFields('stickerTypeRegular', ['21', '24']));
      await settle();
      expect(countRequestsOfType(bridge, 'getInstalledStickerSets')).assertEqual(2);

      unsubscribe();
      coordinator.destroy();
    });

    it('clearRecentStickers_writesToTdlib', 0, async (): Promise<void> => {
      const bridge: TestNativeBridge = new TestNativeBridge();
      const scope: AccountScope = createScope(bridge);
      const coordinator: ChatCoordinator = new ChatCoordinator(scope, 42, 'Test Chat');

      const recorder: StateRecorder = new StateRecorder();
      const unsubscribe: () => void = coordinator.subscribe((state: ChatUiState): void => {
        recorder.seen.push(state);
      });

      coordinator.dispatch(new OpenStickerBoard());
      await settle();
      bridge.respondTo(lastRequestIdOfType(bridge, 'getRecentStickers'), recentStickersFields([
        recentStickerFields(7001, 8001, '🐼')
      ]));
      await settle();
      expect(recorder.last().recentStickers.length).assertEqual(1);

      coordinator.dispatch(new ClearRecentStickers());
      await settle();

      // 本地那一行先撤，服务端那半边再写 —— 反过来会先闪一次旧列表
      expect(recorder.last().recentStickers.length).assertEqual(0);
      const clears: Record<string, TdWireValue>[] = requestsOfType(bridge, 'clearRecentStickers');
      expect(clears.length).assertEqual(1);
      expect(clears[0]['is_attached'] === false).assertTrue();

      const reads: number = countRequestsOfType(bridge, 'getRecentStickers');
      bridge.respondTo(lastRequestIdOfType(bridge, 'clearRecentStickers'), okFields());
      await settle();
      // 写成功就不必再读一次：屏上已经是空的那一行
      expect(countRequestsOfType(bridge, 'getRecentStickers')).assertEqual(reads);

      unsubscribe();
      coordinator.destroy();
    });

    it('clearRecentStickers_writeFailureRefetchesTheRealList', 0, async (): Promise<void> => {
      const bridge: TestNativeBridge = new TestNativeBridge();
      const scope: AccountScope = createScope(bridge);
      const coordinator: ChatCoordinator = new ChatCoordinator(scope, 42, 'Test Chat');

      const recorder: StateRecorder = new StateRecorder();
      const unsubscribe: () => void = coordinator.subscribe((state: ChatUiState): void => {
        recorder.seen.push(state);
      });

      coordinator.dispatch(new OpenStickerBoard());
      await settle();
      bridge.respondTo(lastRequestIdOfType(bridge, 'getRecentStickers'), recentStickersFields([
        recentStickerFields(7001, 8001, '🐼')
      ]));
      await settle();
      expect(countRequestsOfType(bridge, 'getRecentStickers')).assertEqual(1);

      coordinator.dispatch(new ClearRecentStickers());
      await settle();
      bridge.respondError(lastRequestIdOfType(bridge, 'clearRecentStickers'), 'REQUEST_TIMEOUT');
      await settle();

      // 写失败必须重读：否则留下「看着清空了、下次打开又全在」的假象
      expect(countRequestsOfType(bridge, 'getRecentStickers')).assertEqual(2);
      bridge.respondTo(lastRequestIdOfType(bridge, 'getRecentStickers'), recentStickersFields([
        recentStickerFields(7001, 8001, '🐼')
      ]));
      await settle();
      expect(recorder.last().recentStickers.length).assertEqual(1);

      unsubscribe();
      coordinator.destroy();
    });

    it('knownShortName_fetchesBySearchStickerSetWithCacheAllowed', 0, async (): Promise<void> => {
      const bridge: TestNativeBridge = new TestNativeBridge();
      const scope: AccountScope = createScope(bridge);
      const coordinator: ChatCoordinator = new ChatCoordinator(scope, 42, 'Test Chat');

      const recorder: StateRecorder = new StateRecorder();
      const unsubscribe: () => void = coordinator.subscribe((state: ChatUiState): void => {
        recorder.seen.push(state);
      });

      await loadBoardWithKnownSet(bridge, coordinator);

      coordinator.dispatch(new OpenStickerSet('21'));
      await settle();

      // 本地见过这一包的短名：第一条请求必须是 `searchStickerSet`，且不再补一条按 id 的查询。
      expect(countRequestsOfType(bridge, 'searchStickerSet')).assertEqual(1);
      expect(countRequestsOfType(bridge, 'getStickerSet')).assertEqual(0);
      const req: Record<string, TdWireValue> = requestsOfType(bridge, 'searchStickerSet')[0];
      expect(String(req['name'])).assertEqual('pandamonium_by_tgx');
      // ignore_cache=true 会让 TDLib 跳过 `StickersManager.cpp:5005-5018` 那条零网络的缓存分支 ——
      // 上一轮就是拿 true 实测，才把配置问题定案成了服务端否决。
      expect(req['ignore_cache'] as boolean).assertFalse();

      expect(recorder.last().stickerSetPreview?.isLoading).assertTrue();

      unsubscribe();
      coordinator.destroy();
    });

    it('unknownSetId_fetchesByIdOnly', 0, async (): Promise<void> => {
      const bridge: TestNativeBridge = new TestNativeBridge();
      const scope: AccountScope = createScope(bridge);
      const coordinator: ChatCoordinator = new ChatCoordinator(scope, 42, 'Test Chat');

      const recorder: StateRecorder = new StateRecorder();
      const unsubscribe: () => void = coordinator.subscribe((state: ChatUiState): void => {
        recorder.seen.push(state);
      });

      await loadBoardWithKnownSet(bridge, coordinator);

      // 消息气泡那种入口只有 set_id、本地没有短名：不能先发一条注定查不到名字的请求。
      coordinator.dispatch(new OpenStickerSet('99'));
      await settle();

      expect(countRequestsOfType(bridge, 'getStickerSet')).assertEqual(1);
      expect(countRequestsOfType(bridge, 'searchStickerSet')).assertEqual(0);
      expect(String(requestsOfType(bridge, 'getStickerSet')[0]['set_id'])).assertEqual('99');

      unsubscribe();
      coordinator.destroy();
    });

    it('shortNameFailure_fallsBackToIdAndFailsOnce', 0, async (): Promise<void> => {
      const bridge: TestNativeBridge = new TestNativeBridge();
      const scope: AccountScope = createScope(bridge);
      const coordinator: ChatCoordinator = new ChatCoordinator(scope, 42, 'Test Chat');

      const recorder: StateRecorder = new StateRecorder();
      const unsubscribe: () => void = coordinator.subscribe((state: ChatUiState): void => {
        recorder.seen.push(state);
      });

      await loadBoardWithKnownSet(bridge, coordinator);

      coordinator.dispatch(new OpenStickerSet('21'));
      await settle();
      // 短名这条失败（406 的真实服务端来源）：换 id 再问一次，此时还不算整包读失败。
      bridge.respondTo(lastRequestIdOfType(bridge, 'searchStickerSet'),
        errorFieldsWith(406, 'STICKERSET_INVALID'));
      await settle();
      expect(countRequestsOfType(bridge, 'getStickerSet')).assertEqual(1);
      expect(recorder.last().stickerSetPreview?.errorMessage).assertNull();

      bridge.respondTo(lastRequestIdOfType(bridge, 'getStickerSet'),
        errorFieldsWith(406, 'STICKERSET_INVALID'));
      await settle();

      // 两条都失败：请求各一条（不递归回短名），失败态只落一次。
      expect(countRequestsOfType(bridge, 'searchStickerSet')).assertEqual(1);
      expect(countRequestsOfType(bridge, 'getStickerSet')).assertEqual(1);
      let failedFrames: number = 0;
      for (let i = 0; i < recorder.seen.length; i++) {
        const preview: StickerSetPreviewState | null = recorder.seen[i].stickerSetPreview;
        if (preview !== null && preview.errorMessage !== null) {
          failedFrames += 1;
        }
      }
      expect(failedFrames).assertEqual(1);
      expect(recorder.last().stickerSetPreview?.isLoading).assertFalse();

      unsubscribe();
      coordinator.destroy();
    });

    it('shortNameSuccess_populatesPreviewWithoutById', 0, async (): Promise<void> => {
      const bridge: TestNativeBridge = new TestNativeBridge();
      const scope: AccountScope = createScope(bridge);
      const coordinator: ChatCoordinator = new ChatCoordinator(scope, 42, 'Test Chat');

      const recorder: StateRecorder = new StateRecorder();
      const unsubscribe: () => void = coordinator.subscribe((state: ChatUiState): void => {
        recorder.seen.push(state);
      });

      await loadBoardWithKnownSet(bridge, coordinator);

      coordinator.dispatch(new OpenStickerSet('21'));
      await settle();
      bridge.respondTo(lastRequestIdOfType(bridge, 'searchStickerSet'), stickerSetFields([
        coverFields(1001, 3001, '🐼'),
        coverFields(1002, 3002, '🎋')
      ]));
      await settle();

      const preview: StickerSetPreviewState | null = recorder.last().stickerSetPreview;
      expect(preview !== null).assertTrue();
      expect(preview?.setId).assertEqual('21');
      expect(preview?.title).assertEqual('Pandamonium');
      expect(preview?.isInstalled).assertTrue();
      expect(preview?.stickers.length).assertEqual(2);
      expect(preview?.isLoading).assertFalse();
      expect(preview?.errorMessage).assertNull();
      // 短名那条成功就出整包：兜底的 id 查询一条都不许发。
      expect(countRequestsOfType(bridge, 'getStickerSet')).assertEqual(0);

      unsubscribe();
      coordinator.destroy();
    });
  });
}
