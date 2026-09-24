/**
 * feature/profile — 群/频道资料页共享内容单元测试（CHATPROF-SHARED）。
 *
 * 守住的行为：
 * 1. 打开页面（chatId 已知）即拉默认媒体 Tab，且只拉一次；
 * 2. 切到已有内容的 Tab 不再发请求，切到空 Tab 才发；
 * 3. 加载中 / 加载更多中 / 已到底 时「加载更多」一律 no-op；
 * 4. 请求失败与「确实没有内容」分开：失败只标当前 Tab，且不清掉已到手的数据；
 * 5. 换会话（openChatProfile）必须清空上一个会话的网格，否则新群看到的是旧图；
 * 6. 协调器端到端：getChat → searchChatMessages(按 Tab 过滤) → 网格含真实条目与占位条目
 *    → 翻页追加，并且本页不需要 createPrivateChat（chatId 由入口给出）；
 * 7. SHARED-AUDIO：音乐/语音 Tab 各自用对过滤器、行文案与日期齐活；解析阶段一律
 *    不发起下载（一屏 20 条音频同时下是灾难），点按才下载并在落盘后续播。
 */

import { describe, it, expect } from '@ohos/hypium';
import { AccountScope } from '@tgx/core-account';
import { ChatRegistry } from '@tgx/core-domain';
import { AudioPlayerPort, FakeAudioPlayer, FakeClipboard, FakeToast } from '@tgx/platform-ports';
import { Logger, LogLevel, LogSink } from '@tgx/observability';
import { TdWireValue } from '@tgx/td-gateway';
import { ReducerEnv, ReducerResult } from '@tgx/feature-template';
import { ManualClock, SequentialIdGenerator } from '@tgx/core-common';
import {
  ChatProfileUiState,
  ChatProfileUiStateOptions
} from '../main/ets/contract/ChatProfileUiState';
import {
  SharedAudioItem,
  SharedContentRows,
  SharedFileItem,
  SharedLinkItem,
  SharedMediaItem
} from '../main/ets/contract/SharedContentItems';
import {
  ChatProfileIntent,
  OpenChatProfile,
  OnSharedTabSelected,
  LoadMoreSharedContent,
  OnSharedContentLoaded,
  OnSharedContentFailed,
  ToggleSharedAudio
} from '../main/ets/contract/ChatProfileIntent';
import { ChatProfileEffect } from '../main/ets/contract/ChatProfileEffect';
import { chatProfileReducer } from '../main/ets/reducer/ChatProfileReducer';
import {
  SHARED_TAB_AUDIO,
  SHARED_TAB_GROUPS,
  SHARED_TAB_VOICE
} from '../main/ets/model/SharedContentSearch';
import {
  ChatProfileCoordinator,
  ChatProfileCoordinatorOptions
} from '../main/ets/coordinator/ChatProfileCoordinator';
import {
  TestNativeBridge,
  audioMessage,
  basicGroupChatResponse,
  downloadedFileValue,
  supergroupChatResponse,
  createScope,
  documentMessage,
  foundMessages,
  photoMessage,
  photoSizeValue,
  settle,
  textUrlMessage,
  videoMessageWithoutThumb,
  voiceMessage
} from './ProfileTestHarness';

const CHAT_ID: number = 4242;

function makeEnv(): ReducerEnv {
  return {
    clock: new ManualClock(1000, 500),
    ids: new SequentialIdGenerator('test-chat-profile-shared-')
  };
}

function stateWith(options: ChatProfileUiStateOptions): ChatProfileUiState {
  return ChatProfileUiState.initial().copyWith(options);
}

function mediaOf(count: number): SharedMediaItem[] {
  const items: SharedMediaItem[] = [];
  for (let i = 0; i < count; i++) {
    items.push(new SharedMediaItem(i + 1, null, true));
  }
  return items;
}

function filesOf(count: number): SharedFileItem[] {
  const items: SharedFileItem[] = [];
  for (let i = 0; i < count; i++) {
    items.push(new SharedFileItem(`f${i}.pdf`, '1 KB', '2026-09-24', null));
  }
  return items;
}

function linksOf(count: number): SharedLinkItem[] {
  const items: SharedLinkItem[] = [];
  for (let i = 0; i < count; i++) {
    items.push(new SharedLinkItem(`https://example.com/${i}`, '', ''));
  }
  return items;
}

function reduce(intent: ChatProfileIntent, state: ChatProfileUiState): ReducerResult<ChatProfileUiState, ChatProfileEffect> {
  return chatProfileReducer(state, intent, makeEnv());
}

/** 起一个真实的 ChatProfileCoordinator（假桥 + 假端口），走完 start → getChat。 */
function openCoordinator(
  bridge: TestNativeBridge,
  options?: ChatProfileCoordinatorOptions
): ChatProfileCoordinator {
  const scope: AccountScope = createScope(bridge, 'test_chat_profile_shared');
  const sink: LogSink = (_level: LogLevel, _line: string): void => {};
  return new ChatProfileCoordinator(
    scope,
    new ChatRegistry(),
    new FakeClipboard(),
    new FakeToast(),
    new Logger('error', sink),
    options
  );
}

export default function chatProfileSharedContentTest(): void {
  describe('ChatProfileSharedContentTest', (): void => {

    it('openChatProfile_clearsPreviousChatSharedMedia', 0, (): void => {
      const state: ChatProfileUiState = stateWith({
        chatId: 111,
        sharedMedia: mediaOf(4),
        sharedFiles: filesOf(2),
        sharedLinks: linksOf(1),
        sharedInitialRequested: true,
        sharedHasMore: false
      });

      const res: ReducerResult<ChatProfileUiState, ChatProfileEffect> =
        reduce(new OpenChatProfile(222), state);

      expect(res.state.sharedMedia.length).assertEqual(0);
      expect(res.state.sharedFiles.length).assertEqual(0);
      expect(res.state.sharedLinks.length).assertEqual(0);
      expect(res.state.sharedInitialRequested).assertFalse();
      expect(res.state.activeSharedTab).assertEqual(0);
      expect(res.effects[0].type).assertEqual('fetchChatDetailsEffect');
    });

    it('onSharedTabSelected_withContent_switchesWithoutRequest', 0, (): void => {
      const state: ChatProfileUiState = stateWith({
        chatId: CHAT_ID,
        sharedFiles: filesOf(3),
        activeSharedTab: 0
      });

      const res: ReducerResult<ChatProfileUiState, ChatProfileEffect> =
        reduce(new OnSharedTabSelected(1), state);

      expect(res.state.activeSharedTab).assertEqual(1);
      expect(res.state.sharedLoading).assertFalse();
      expect(res.effects.length).assertEqual(0);
    });

    it('onSharedTabSelected_emptyTab_requestsOnce', 0, (): void => {
      const state: ChatProfileUiState = stateWith({ chatId: CHAT_ID, activeSharedTab: 0 });

      const res: ReducerResult<ChatProfileUiState, ChatProfileEffect> =
        reduce(new OnSharedTabSelected(2), state);

      expect(res.state.sharedLoading).assertTrue();
      expect(res.effects.length).assertEqual(1);
      expect(res.effects[0].type).assertEqual('fetchSharedContentEffect');
    });

    it('onSharedTabSelected_rejectsGroupsTabIndex', 0, (): void => {
      // 本页五个内容 Tab（媒体/文件/链接/音乐/语音）：群组是私聊概念，越界索引必须 no-op。
      const state: ChatProfileUiState = stateWith({ chatId: CHAT_ID });

      const res: ReducerResult<ChatProfileUiState, ChatProfileEffect> =
        reduce(new OnSharedTabSelected(SHARED_TAB_GROUPS), state);

      expect(res.effects.length).assertEqual(0);
      expect(res.state.activeSharedTab).assertEqual(0);
    });

    it('loadMoreSharedContent_guardedWhileInFlightOrExhausted', 0, (): void => {
      const loading: ChatProfileUiState = stateWith({ chatId: CHAT_ID, sharedLoading: true });
      expect(reduce(new LoadMoreSharedContent(0), loading).effects.length).assertEqual(0);

      const loadingMore: ChatProfileUiState = stateWith({ chatId: CHAT_ID, sharedLoadingMore: true });
      expect(reduce(new LoadMoreSharedContent(0), loadingMore).effects.length).assertEqual(0);

      const exhausted: ChatProfileUiState = stateWith({ chatId: CHAT_ID, sharedHasMore: false });
      expect(reduce(new LoadMoreSharedContent(0), exhausted).effects.length).assertEqual(0);

      const idle: ChatProfileUiState = stateWith({ chatId: CHAT_ID });
      const res: ReducerResult<ChatProfileUiState, ChatProfileEffect> =
        reduce(new LoadMoreSharedContent(0), idle);
      expect(res.state.sharedLoadingMore).assertTrue();
      expect(res.effects[0].type).assertEqual('fetchMoreSharedContentEffect');
    });

    it('onSharedContentLoaded_clearsFailureAndTakesHasMore', 0, (): void => {
      const state: ChatProfileUiState = stateWith({
        chatId: CHAT_ID,
        sharedLoading: true,
        sharedLoadFailed: true
      });

      const res: ReducerResult<ChatProfileUiState, ChatProfileEffect> =
        reduce(new OnSharedContentLoaded(0, new SharedContentRows({ media: mediaOf(2) }), true), state);

      expect(res.state.sharedMedia.length).assertEqual(2);
      expect(res.state.sharedLoading).assertFalse();
      expect(res.state.sharedLoadFailed).assertFalse();
      expect(res.state.sharedHasMore).assertTrue();
    });

    it('onSharedContentFailed_onlyMarksActiveTab', 0, (): void => {
      const state: ChatProfileUiState = stateWith({
        chatId: CHAT_ID,
        activeSharedTab: 1,
        sharedLoading: true,
        sharedMedia: mediaOf(3)
      });

      const stale: ReducerResult<ChatProfileUiState, ChatProfileEffect> =
        reduce(new OnSharedContentFailed(0), state);
      expect(stale.state.sharedLoadFailed).assertFalse();
      expect(stale.state.sharedLoading).assertTrue();

      const current: ReducerResult<ChatProfileUiState, ChatProfileEffect> =
        reduce(new OnSharedContentFailed(1), state);
      expect(current.state.sharedLoadFailed).assertTrue();
      expect(current.state.sharedLoading).assertFalse();
      // 失败只影响当前 Tab，不能把已经到手的其它 Tab 数据一起清掉。
      expect(current.state.sharedMedia.length).assertEqual(3);
    });

    it('coordinator_firstPage_mapsRealAndPlaceholderTiles', 0, async (): Promise<void> => {
      const bridge: TestNativeBridge = new TestNativeBridge();
      const coordinator: ChatProfileCoordinator = openCoordinator(bridge);
      coordinator.start(CHAT_ID);

      const getId: string = bridge.lastRequestIdOf('getChat');
      expect(getId.length > 0).assertTrue();
      // 共享内容不再走 createPrivateChat：本页的 chatId 由入口直接给出。
      expect(bridge.lastRequestIdOf('createPrivateChat').length).assertEqual(0);

      bridge.respondTo(getId, basicGroupChatResponse(CHAT_ID));
      await settle();

      const searchId: string = bridge.lastRequestIdOf('searchChatMessages');
      expect(searchId.length > 0).assertTrue();
      const sizes: Record<string, TdWireValue>[] = [photoSizeValue(9001, 640)];
      bridge.respondTo(searchId, foundMessages(
        [photoMessage(101, sizes), videoMessageWithoutThumb(202)], 0));
      await settle();

      const state: ChatProfileUiState = coordinator.getState();
      expect(state.sharedMedia.length).assertEqual(2);
      expect(state.sharedMedia[0].fileId).assertEqual(9001);
      expect(state.sharedMedia[1].fileId).assertEqual(0);
      expect(state.sharedMedia[1].isPhoto).assertFalse();
      expect(state.sharedLoading).assertFalse();
      expect(state.sharedHasMore).assertFalse();
      coordinator.destroy();
    });

    it('coordinator_negativeSupergroupChatId_stillSearches', 0, async (): Promise<void> => {
      // 真机证据：超级群组/频道的 chat.id 是负数（-100… 规范 id）。
      // 早期实现按「chatId > 0 才有效」把关，结果群资料页共享内容永远「加载失败」。
      const negChatId: number = -1001948393032;
      const bridge: TestNativeBridge = new TestNativeBridge();
      const coordinator: ChatProfileCoordinator = openCoordinator(bridge);
      coordinator.start(negChatId);

      bridge.respondTo(bridge.lastRequestIdOf('getChat'), supergroupChatResponse(negChatId));
      await settle();

      const searchId: string = bridge.lastRequestIdOf('searchChatMessages');
      expect(searchId.length > 0).assertTrue();
      expect(coordinator.getState().chatId).assertEqual(negChatId);
      bridge.respondTo(searchId, foundMessages([photoMessage(101, [])], 0));
      await settle();

      const state: ChatProfileUiState = coordinator.getState();
      expect(state.sharedMedia.length).assertEqual(1);
      expect(state.sharedLoadFailed).assertFalse();
      coordinator.destroy();
    });

    it('coordinator_tabSwitch_usesDocumentFilterAndAppendsNextPage', 0, async (): Promise<void> => {
      const bridge: TestNativeBridge = new TestNativeBridge();
      const coordinator: ChatProfileCoordinator = openCoordinator(bridge);
      coordinator.start(CHAT_ID);

      bridge.respondTo(bridge.lastRequestIdOf('getChat'), basicGroupChatResponse(CHAT_ID));
      await settle();
      const sizes: Record<string, TdWireValue>[] = [photoSizeValue(9001, 640)];
      bridge.respondTo(bridge.lastRequestIdOf('searchChatMessages'),
        foundMessages([photoMessage(101, sizes)], 58720256));
      await settle();
      expect(coordinator.getState().sharedHasMore).assertTrue();

      coordinator.dispatch(new OnSharedTabSelected(1));
      await settle();
      const docSearch: Record<string, TdWireValue> = bridge.lastRequestOf('searchChatMessages');
      const filter: Record<string, TdWireValue> =
        docSearch['filter'] as Record<string, TdWireValue>;
      expect(filter['@type']).assertEqual('searchMessagesFilterDocument');

      const page2: Record<string, TdWireValue>[] = [documentMessage(303, 'spec.pdf')];
      bridge.respondTo(bridge.lastRequestIdOf('searchChatMessages'), foundMessages(page2, 0));
      await settle();

      const state: ChatProfileUiState = coordinator.getState();
      expect(state.sharedFiles.length).assertEqual(1);
      expect(state.sharedFiles[0].fileName).assertEqual('spec.pdf');
      // 媒体数组不受文件页影响。
      expect(state.sharedMedia.length).assertEqual(1);
      expect(state.sharedHasMore).assertFalse();
      coordinator.destroy();
    });

    it('coordinator_itemsCarryMessageDateForDateSections', 0, async (): Promise<void> => {
      // 分组头吃的是条目日期，而日期挂在 Message 上、不在 content 上：
      // 解析器原先只收 content，日期整条链路丢失，分段永远只剩一段。
      const bridge: TestNativeBridge = new TestNativeBridge();
      const coordinator: ChatProfileCoordinator = openCoordinator(bridge);
      coordinator.start(CHAT_ID);
      bridge.respondTo(bridge.lastRequestIdOf('getChat'), basicGroupChatResponse(CHAT_ID));
      await settle();
      const sizesA: Record<string, TdWireValue>[] = [photoSizeValue(9001, 640)];
      const sizesB: Record<string, TdWireValue>[] = [photoSizeValue(9002, 640)];
      bridge.respondTo(bridge.lastRequestIdOf('searchChatMessages'), foundMessages(
        [photoMessage(101, sizesA, 1758633600), photoMessage(102, sizesB, 1756000000)], 0));
      await settle();

      const state: ChatProfileUiState = coordinator.getState();
      expect(state.sharedMedia.length).assertEqual(2);
      expect(state.sharedMedia[0].date).assertEqual(1758633600);
      expect(state.sharedMedia[1].date).assertEqual(1756000000);

      coordinator.dispatch(new OnSharedTabSelected(1));
      await settle();
      bridge.respondTo(bridge.lastRequestIdOf('searchChatMessages'),
        foundMessages([documentMessage(303, 'spec.pdf', 1756000000)], 0));
      await settle();
      expect(coordinator.getState().sharedFiles[0].date).assertEqual(1756000000);

      coordinator.dispatch(new OnSharedTabSelected(2));
      await settle();
      bridge.respondTo(bridge.lastRequestIdOf('searchChatMessages'),
        foundMessages([textUrlMessage(404, 'https://example.com/a', 1758633600)], 0));
      await settle();
      expect(coordinator.getState().sharedLinks[0].date).assertEqual(1758633600);
      coordinator.destroy();
    });

    it('coordinator_errorResponse_marksFailureWithoutLosingItems', 0, async (): Promise<void> => {
      const bridge: TestNativeBridge = new TestNativeBridge();
      const coordinator: ChatProfileCoordinator = openCoordinator(bridge);
      coordinator.start(CHAT_ID);

      bridge.respondTo(bridge.lastRequestIdOf('getChat'), basicGroupChatResponse(CHAT_ID));
      await settle();
      const sizes: Record<string, TdWireValue>[] = [photoSizeValue(9001, 640)];
      bridge.respondTo(bridge.lastRequestIdOf('searchChatMessages'),
        foundMessages([photoMessage(101, sizes)], 58720256));
      await settle();

      coordinator.dispatch(new LoadMoreSharedContent(0));
      bridge.respondWithError(bridge.lastRequestIdOf('searchChatMessages'), 'REQUEST_TOO_LONG');
      await settle();

      const state: ChatProfileUiState = coordinator.getState();
      expect(state.sharedLoadFailed).assertTrue();
      expect(state.sharedLoadingMore).assertFalse();
      expect(state.sharedMedia.length).assertEqual(1);
      coordinator.destroy();
    });

    it('coordinator_audioTab_mapsRowsWithoutBulkDownload', 0, async (): Promise<void> => {
      const bridge: TestNativeBridge = new TestNativeBridge();
      const coordinator: ChatProfileCoordinator = openCoordinator(bridge);
      coordinator.start(CHAT_ID);
      bridge.respondTo(bridge.lastRequestIdOf('getChat'), basicGroupChatResponse(CHAT_ID));
      await settle();
      const sizes: Record<string, TdWireValue>[] = [photoSizeValue(9001, 640)];
      bridge.respondTo(bridge.lastRequestIdOf('searchChatMessages'),
        foundMessages([photoMessage(101, sizes)], 0));
      await settle();

      coordinator.dispatch(new OnSharedTabSelected(SHARED_TAB_AUDIO));
      await settle();
      const req: Record<string, TdWireValue> = bridge.lastRequestOf('searchChatMessages');
      const filter: Record<string, TdWireValue> = req['filter'] as Record<string, TdWireValue>;
      expect(filter['@type']).assertEqual('searchMessagesFilterAudio');

      const downloadsBefore: number = bridge.countRequests('downloadFile');
      bridge.respondTo(bridge.lastRequestIdOf('searchChatMessages'), foundMessages(
        [audioMessage(501, 'Moon River', 'Andy Williams', 1758633600),
          audioMessage(502, '', '', 1756000000)], 0));
      await settle();

      const rows: SharedAudioItem[] = coordinator.getState().sharedAudios;
      expect(rows.length).assertEqual(2);
      expect(rows[0].fileId).assertEqual(501 * 11);
      expect(rows[0].title).assertEqual('Moon River');
      expect(rows[0].subtitle).assertEqual('Andy Williams - Moon River');
      expect(rows[0].duration).assertEqual(214);
      expect(rows[0].date).assertEqual(1758633600);
      // 没有 title：标题回落「文件名去扩展名」，副标题回落文件大小（TD.getTitle/getSubtitle）。
      expect(rows[1].title).assertEqual('502');
      expect(rows[1].subtitle).assertEqual('1.0 KB');
      // 其它媒体行不受影响。
      expect(coordinator.getState().sharedMedia.length).assertEqual(1);
      // 解析阶段一条下载都不发：早期版本用带订阅的 localPathOf，翻个 Tab 就同时下 20 个音频。
      expect(bridge.countRequests('downloadFile')).assertEqual(downloadsBefore);
      expect(bridge.countDownloadRequestsFor(501 * 11)).assertEqual(0);
      coordinator.destroy();
    });

    it('coordinator_voiceTab_mapsRowsWithSenderFallbackChain', 0, async (): Promise<void> => {
      const bridge: TestNativeBridge = new TestNativeBridge();
      const coordinator: ChatProfileCoordinator = openCoordinator(bridge);
      coordinator.start(CHAT_ID);
      bridge.respondTo(bridge.lastRequestIdOf('getChat'), basicGroupChatResponse(CHAT_ID));
      await settle();

      coordinator.dispatch(new OnSharedTabSelected(SHARED_TAB_VOICE));
      await settle();
      const req: Record<string, TdWireValue> = bridge.lastRequestOf('searchChatMessages');
      const filter: Record<string, TdWireValue> = req['filter'] as Record<string, TdWireValue>;
      expect(filter['@type']).assertEqual('searchMessagesFilterVoiceNote');

      bridge.respondTo(bridge.lastRequestIdOf('searchChatMessages'),
        foundMessages([voiceMessage(601, 777, 7, 1758633600)], 0));
      await settle();

      const rows: SharedAudioItem[] = coordinator.getState().sharedVoices;
      expect(rows.length).assertEqual(1);
      expect(rows[0].fileId).assertEqual(601 * 13);
      // 成员昵称还没进缓存 → 空串，由组件回落到「语音消息」；不印裸 user id。
      expect(rows[0].title).assertEqual('');
      expect(rows[0].subtitle).assertEqual('0:07 · 1.0 KB');
      expect(rows[0].date).assertEqual(1758633600);
      // 语音行不会串到音乐数组里。
      expect(coordinator.getState().sharedAudios.length).assertEqual(0);
      coordinator.destroy();
    });

    it('coordinator_tapAudio_downloadsThenBackfillsPathAndResumesPlay', 0, async (): Promise<void> => {
      const bridge: TestNativeBridge = new TestNativeBridge();
      const player: AudioPlayerPort = new FakeAudioPlayer();
      const coordinator: ChatProfileCoordinator = openCoordinator(bridge, { audioPlayerPort: player });
      coordinator.start(CHAT_ID);
      bridge.respondTo(bridge.lastRequestIdOf('getChat'), basicGroupChatResponse(CHAT_ID));
      await settle();
      coordinator.dispatch(new OnSharedTabSelected(SHARED_TAB_AUDIO));
      await settle();
      bridge.respondTo(bridge.lastRequestIdOf('searchChatMessages'),
        foundMessages([audioMessage(501, 'Moon River', 'Andy Williams')], 0));
      await settle();

      const fileId: number = 501 * 11;
      coordinator.dispatch(new ToggleSharedAudio(fileId));
      await settle();

      const playing: ChatProfileUiState = coordinator.getState();
      expect(playing.sharedPlayingFileId).assertEqual(fileId);
      expect(playing.sharedAudios[0].localPath).assertNull();
      // 音频没落盘：点按才发起下载，此时还没外放。
      expect(bridge.countDownloadRequestsFor(fileId)).assertEqual(1);
      expect((player as FakeAudioPlayer).getCurrentUri()).assertEqual('');

      const path: string = '/sandbox/files/audio-501.mp3';
      const update: Record<string, TdWireValue> = {};
      update['file'] = downloadedFileValue(fileId, path);
      bridge.emitUpdate('updateFile', update);
      await settle();

      const done: ChatProfileUiState = coordinator.getState();
      expect(done.sharedAudios[0].localPath).assertEqual(path);
      expect(done.sharedPlayingFileId).assertEqual(fileId);
      // 落盘后续播：等待中的 fileId 由 onSharedFileReady 兑现。
      expect((player as FakeAudioPlayer).getCurrentUri()).assertEqual(path);
      expect((player as FakeAudioPlayer).isPlaying()).assertTrue();

      coordinator.dispatch(new ToggleSharedAudio(fileId));
      await settle();
      expect(coordinator.getState().sharedPlayingFileId).assertEqual(0);
      expect((player as FakeAudioPlayer).isPlaying()).assertFalse();
      coordinator.destroy();
    });
  });
}
