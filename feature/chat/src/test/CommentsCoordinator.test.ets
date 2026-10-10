/**
 * feature/chat — CommentsCoordinator 单元测试（CHANNEL-101）。
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
import { Lang, Result, AppError, LanguagePreference } from '@tgx/core-common';
import { CommentsCoordinator, CommentsUiState } from '../main/ets/coordinator/CommentsCoordinator';

const TEST_CHANNEL_ID: number = 1001;
const TEST_POST_ID: number = 2002;

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

  send(clientId: number, requestUtf8: string): void {
    this.sent.push(requestUtf8);
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

  requestsOfType(type: string): Record<string, TdWireValue>[] {
    const out: Record<string, TdWireValue>[] = [];
    for (let i = 0; i < this.sent.length; i++) {
      const req: Record<string, TdWireValue> = JSON.parse(this.sent[i]) as Record<string, TdWireValue>;
      if (req['@type'] === type) {
        out.push(req);
      }
    }
    return out;
  }
}

function createScope(bridge: TestNativeBridge): AccountScope {
  const layoutRes: Result<AccountDirectoryLayout, AppError> = buildAccountDirectories('test_comments');
  if (layoutRes.ok === false) {
    throw new Error('Failed to build directories');
  }
  const scopeRes: Result<AccountScope, AppError> = AccountScope.open({
    bridge: bridge,
    files: new FakeAppFiles(),
    descriptor: createDescriptor('test_comments', 'acct_user_1', 0, true),
    directories: layoutRes.value,
    startActive: true
  });
  if (scopeRes.ok === false) {
    throw new Error('Failed to open AccountScope');
  }
  return scopeRes.value;
}

export default function commentsCoordinatorTest(): void {
  describe('CommentsCoordinatorTest', () => {

    it('initialState_hasCorrectDefaults', 0, (): void => {
      const bridge: TestNativeBridge = new TestNativeBridge();
      const scope: AccountScope = createScope(bridge);
      const coordinator: CommentsCoordinator = new CommentsCoordinator(scope, TEST_CHANNEL_ID, TEST_POST_ID);

      const state: CommentsUiState = coordinator.getState();
      expect(state.channelChatId).assertEqual(TEST_CHANNEL_ID);
      expect(state.channelPostId).assertEqual(TEST_POST_ID);
      expect(state.isLoading).assertTrue();
      expect(state.comments.length).assertEqual(0);
      expect(state.inputText).assertEqual('');

      coordinator.destroy();
    });

    it('start_sendsGetChatGetMessageAndGetMessageThread', 0, (): void => {
      const bridge: TestNativeBridge = new TestNativeBridge();
      const scope: AccountScope = createScope(bridge);
      const coordinator: CommentsCoordinator = new CommentsCoordinator(scope, TEST_CHANNEL_ID, TEST_POST_ID);

      coordinator.start();

      const chatReqs: Record<string, TdWireValue>[] = bridge.requestsOfType('getChat');
      expect(chatReqs.length).assertEqual(1);
      expect(chatReqs[0]['chat_id']).assertEqual(TEST_CHANNEL_ID);

      const msgReqs: Record<string, TdWireValue>[] = bridge.requestsOfType('getMessage');
      expect(msgReqs.length).assertEqual(1);
      expect(msgReqs[0]['chat_id']).assertEqual(TEST_CHANNEL_ID);
      expect(msgReqs[0]['message_id']).assertEqual(TEST_POST_ID);

      const threadReqs: Record<string, TdWireValue>[] = bridge.requestsOfType('getMessageThread');
      expect(threadReqs.length).assertEqual(1);
      expect(threadReqs[0]['chat_id']).assertEqual(TEST_CHANNEL_ID);
      expect(threadReqs[0]['message_id']).assertEqual(TEST_POST_ID);

      coordinator.destroy();
    });

    it('setInputText_updatesStateAndNotifiesSubscriber', 0, (): void => {
      const bridge: TestNativeBridge = new TestNativeBridge();
      const scope: AccountScope = createScope(bridge);
      const coordinator: CommentsCoordinator = new CommentsCoordinator(scope, TEST_CHANNEL_ID, TEST_POST_ID);

      let lastInput: string = '';
      const unsub: () => void = coordinator.subscribe((st: CommentsUiState): void => {
        lastInput = st.inputText;
      });

      coordinator.setInputText('Hello comment');
      expect(lastInput).assertEqual('Hello comment');
      expect(coordinator.getState().inputText).assertEqual('Hello comment');

      unsub();
      coordinator.destroy();
    });

    it('sendComment_optimisticallyAppendsItemAndSendsRequest', 0, (): void => {
      const bridge: TestNativeBridge = new TestNativeBridge();
      const scope: AccountScope = createScope(bridge);
      const coordinator: CommentsCoordinator = new CommentsCoordinator(scope, TEST_CHANNEL_ID, TEST_POST_ID);

      coordinator.setInputText('Test comment content');
      coordinator.sendComment();

      // State should have optimistic item
      const state: CommentsUiState = coordinator.getState();
      expect(state.comments.length).assertEqual(1);
      expect(state.comments[0].text).assertEqual('Test comment content');
      expect(state.comments[0].isSending).assertTrue();
      expect(state.inputText).assertEqual('');

      // A sendMessage request should have been dispatched
      const sendReqs: Record<string, TdWireValue>[] = bridge.requestsOfType('sendMessage');
      expect(sendReqs.length).assertEqual(1);

      coordinator.destroy();
    });

    /**
     * I18N-HOTSWITCH-102 不变量①：`buildState()` 是纯投影 —— 同一原始输入
     * 投两次必须逐字相同（不然语言重投的「同值即返回」会漏掉真实变化，
     * 反过来重投不幂等则每次 tick 都会有假刷新）。
     */
    it('sameSourceTwice_producesIdenticalProjection', 0, (): void => {
      const bridge: TestNativeBridge = new TestNativeBridge();
      const scope: AccountScope = createScope(bridge);
      const coordinator: CommentsCoordinator = new CommentsCoordinator(scope, TEST_CHANNEL_ID, TEST_POST_ID);

      coordinator.setInputText('Deterministic');
      const first: CommentsUiState = coordinator.getState();
      coordinator.setInputText('Deterministic');
      const second: CommentsUiState = coordinator.getState();

      expect(JSON.stringify(second)).assertEqual(JSON.stringify(first));

      coordinator.destroy();
    });

    /**
     * I18N-HOTSWITCH-102 不变量②：语言位变化后，协调器**只做本地重投影** ——
     * 称谓/兜底标题换词，TDLib 请求一条不多发。订阅在 `start()` 里挂上。
     */
    it('languageChange_reprojectsLocallyWithoutNewRequests', 0, (): void => {
      const bridge: TestNativeBridge = new TestNativeBridge();
      const scope: AccountScope = createScope(bridge);
      const coordinator: CommentsCoordinator = new CommentsCoordinator(scope, TEST_CHANNEL_ID, TEST_POST_ID);
      const lang: Lang = Lang.getInstance();
      const originalPreference: LanguagePreference = lang.getPreference();

      coordinator.start();
      coordinator.setInputText('A comment');
      coordinator.sendComment();
      const requestsBefore: number = bridge.sent.length;
      expect(coordinator.getState().comments[0].senderName).assertEqual('Me');

      try {
        lang.setLanguage('zh');
        const state: CommentsUiState = coordinator.getState();
        expect(state.comments[0].senderName).assertEqual('我');
        expect(state.channelTitle).assertEqual('频道帖子');
        expect(bridge.sent.length).assertEqual(requestsBefore);
      } finally {
        lang.setLanguage(originalPreference);
        coordinator.destroy();
      }
    });

    it('destroy_preventsSubscribersFromReceivingUpdates', 0, (): void => {
      const bridge: TestNativeBridge = new TestNativeBridge();
      const scope: AccountScope = createScope(bridge);
      const coordinator: CommentsCoordinator = new CommentsCoordinator(scope, TEST_CHANNEL_ID, TEST_POST_ID);

      let notifyCount: number = 0;
      coordinator.subscribe((): void => {
        notifyCount += 1;
      });
      // Initial subscription notifies once
      expect(notifyCount).assertEqual(1);

      coordinator.destroy();
      coordinator.setInputText('after destroy');
      expect(notifyCount).assertEqual(1);
    });
  });
}
