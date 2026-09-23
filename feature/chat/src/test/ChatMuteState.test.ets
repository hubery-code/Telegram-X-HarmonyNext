/**
 * feature/chat — 会话静音态单元测试（SET-106 / FEAT-SET-003）。
 *
 * 守住的三条真实回归：
 * 1. 写请求不得把 int64（sound_id / story_sound_id）写成空串 —— TDLib 直接判 bad_request，
 *    MENU-101 首版的静音因此从未能生效；
 * 2. 静音写请求以回读快照为底本，只覆盖 mute_for，其余用户设置原样带回；
 * 3. 静音态必须由 updateChatNotificationSettings 回灌，且只认本会话的推送。
 */

import { describe, it, expect } from '@ohos/hypium';
import { ManualClock, SequentialIdGenerator, AppError, Result } from '@tgx/core-common';
import { ReducerEnv, ReducerResult } from '@tgx/feature-template';
import { AccountScope, buildAccountDirectories, createDescriptor, AccountDirectoryLayout } from '@tgx/core-account';
import { FakeAppFiles } from '@tgx/platform-ports';
import {
  ChatNotificationSettings
} from '@tgx/core-td-api-generated';
import {
  TdNativeBridgeLike,
  TdNativeBridgeMetrics,
  TdNativeEvent,
  TdNativeEventSink,
  TdWireObject,
  TdWireValue
} from '@tgx/td-gateway';
import { ChatCoordinator } from '../main/ets/coordinator/ChatCoordinator';
import { ChatMenuAction, OnChatMuteStateChanged } from '../main/ets/contract/ChatIntent';
import { ChatIntent } from '../main/ets/contract/ChatIntent';
import { ChatUiState } from '../main/ets/contract/ChatUiState';
import { ChatEffect } from '../main/ets/contract/ChatEffect';
import { chatReducer } from '../main/ets/reducer/ChatReducer';
import { CHAT_MUTE_FOREVER_SECONDS, isChatMuted, withChatMuteFor } from '../main/ets/model/ChatMute';

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

  emitUpdate(clientId: number, payload: TdWireObject): void {
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
  const layoutRes: Result<AccountDirectoryLayout, AppError> = buildAccountDirectories('test_chat_mute');
  if (layoutRes.ok === false) {
    throw new Error('Failed to build directories');
  }
  const scopeRes: Result<AccountScope, AppError> = AccountScope.open({
    bridge: bridge,
    files: new FakeAppFiles(),
    descriptor: createDescriptor('test_chat_mute', 'acct_user_1', 0, true),
    directories: layoutRes.value,
    startActive: true
  });
  if (scopeRes.ok === false) {
    throw new Error('Failed to open AccountScope');
  }
  return scopeRes.value;
}

function makeEnv(nowMillis: number = 1000, monotonicMillis: number = 500): ReducerEnv {
  return {
    clock: new ManualClock(nowMillis, monotonicMillis),
    ids: new SequentialIdGenerator('req-test-')
  };
}

function makeState(isMuted: boolean = false): ChatUiState {
  return new ChatUiState(42, 'chat', [], false, true, null, '', null, null)
    .copyWith({ isMuted: isMuted });
}

function settingsOf(muteFor: number, useDefaultMuteFor: boolean = false): ChatNotificationSettings {
  const settings: ChatNotificationSettings = new ChatNotificationSettings();
  settings.use_default_mute_for = useDefaultMuteFor;
  settings.mute_for = muteFor;
  settings.use_default_sound = true;
  settings.sound_id = '0';
  settings.use_default_show_preview = false;
  settings.show_preview = true;
  settings.use_default_mute_stories = true;
  settings.use_default_story_sound = true;
  settings.story_sound_id = '0';
  settings.use_default_show_story_poster = true;
  settings.use_default_disable_pinned_message_notifications = true;
  settings.use_default_disable_mention_notifications = true;
  return settings;
}

/** 取最近一条 setChatNotificationSettings 请求的 notification_settings 负载。 */
function lastMuteRequest(bridge: TestNativeBridge): Record<string, TdWireValue> | null {
  for (let i = bridge.sent.length - 1; i >= 0; i--) {
    const req: Record<string, TdWireValue> = JSON.parse(bridge.sent[i]) as Record<string, TdWireValue>;
    if (req['@type'] === 'setChatNotificationSettings') {
      return req;
    }
  }
  return null;
}

function updatePayload(chatId: number, settings: ChatNotificationSettings): TdWireObject {
  const payload: TdWireObject = {};
  payload['@type'] = 'updateChatNotificationSettings';
  payload['chat_id'] = chatId;
  const nested: Record<string, TdWireValue> = {};
  nested['@type'] = 'chatNotificationSettings';
  nested['use_default_mute_for'] = settings.use_default_mute_for;
  nested['mute_for'] = settings.mute_for;
  nested['use_default_sound'] = settings.use_default_sound;
  nested['sound_id'] = settings.sound_id;
  nested['use_default_show_preview'] = settings.use_default_show_preview;
  nested['show_preview'] = settings.show_preview;
  nested['use_default_mute_stories'] = settings.use_default_mute_stories;
  nested['mute_stories'] = settings.mute_stories;
  nested['use_default_story_sound'] = settings.use_default_story_sound;
  nested['story_sound_id'] = settings.story_sound_id;
  nested['use_default_show_story_poster'] = settings.use_default_show_story_poster;
  nested['show_story_poster'] = settings.show_story_poster;
  nested['use_default_disable_pinned_message_notifications'] =
    settings.use_default_disable_pinned_message_notifications;
  nested['disable_pinned_message_notifications'] = settings.disable_pinned_message_notifications;
  nested['use_default_disable_mention_notifications'] = settings.use_default_disable_mention_notifications;
  nested['disable_mention_notifications'] = settings.disable_mention_notifications;
  payload['notification_settings'] = nested;
  return payload;
}

function settle(): Promise<void> {
  return new Promise<void>((resolve: () => void): void => {
    setTimeout(resolve, 30);
  });
}

export default function chatMuteStateTest(): void {
  describe('ChatMuteStateTest', () => {

    it('isChatMuted_readsMuteForAndHonoursUseDefaultFlag', 0, () => {
      expect(isChatMuted(null)).assertFalse();
      expect(isChatMuted(settingsOf(0))).assertFalse();
      expect(isChatMuted(settingsOf(CHAT_MUTE_FOREVER_SECONDS))).assertTrue();
      expect(isChatMuted(settingsOf(3600, true))).assertFalse();
    });

    it('withChatMuteFor_keepsInt64SoundFieldsParseable', 0, () => {
      const muted: ChatNotificationSettings = withChatMuteFor(null, true);
      expect(muted.mute_for).assertEqual(CHAT_MUTE_FOREVER_SECONDS);
      expect(muted.use_default_mute_for).assertFalse();
      // 回归点：空串会让 TDLib 直接判 bad_request，int64 字段必须可解析。
      expect(muted.sound_id).assertEqual('0');
      expect(muted.story_sound_id).assertEqual('0');
    });

    it('withChatMuteFor_overridesOnlyMuteForOnSnapshot', 0, () => {
      const source: ChatNotificationSettings = settingsOf(0);
      source.use_default_show_preview = false;
      source.show_preview = false;
      source.disable_mention_notifications = true;
      const next: ChatNotificationSettings = withChatMuteFor(source, true);
      expect(next.mute_for).assertEqual(CHAT_MUTE_FOREVER_SECONDS);
      expect(next.show_preview).assertFalse();
      expect(next.disable_mention_notifications).assertTrue();
      const unmuted: ChatNotificationSettings = withChatMuteFor(source, false);
      expect(unmuted.mute_for).assertEqual(0);
      expect(unmuted.use_default_mute_for).assertFalse();
    });

    it('onChatMuteStateChanged_updatesMuteFlag', 0, () => {
      const result: ReducerResult<ChatUiState, ChatEffect> =
        chatReducer(makeState(false), new OnChatMuteStateChanged(true), makeEnv());
      expect(result.state.isMuted).assertTrue();
      expect(result.effects.length).assertEqual(0);
    });

    it('onChatMuteStateChanged_sameValue_isNoOpSameRef', 0, () => {
      const state: ChatUiState = makeState(true);
      const intent: ChatIntent = new OnChatMuteStateChanged(true);
      const result: ReducerResult<ChatUiState, ChatEffect> = chatReducer(state, intent, makeEnv());
      expect(result.state === state).assertTrue();
    });

    it('muteMenuAction_sendsForeverMuteWithParseableSoundId', 0, () => {
      const bridge: TestNativeBridge = new TestNativeBridge();
      const scope: AccountScope = createScope(bridge);
      const coordinator: ChatCoordinator = new ChatCoordinator(scope, 42, 'Test Chat');

      coordinator.dispatch(new ChatMenuAction('mute'));

      const req: Record<string, TdWireValue> | null = lastMuteRequest(bridge);
      expect(req === null).assertFalse();
      if (req === null) {
        coordinator.destroy();
        return;
      }
      expect(req['chat_id']).assertEqual(42);
      const settings: Record<string, TdWireValue> = req['notification_settings'] as Record<string, TdWireValue>;
      expect(settings['mute_for']).assertEqual(CHAT_MUTE_FOREVER_SECONDS);
      expect(settings['use_default_mute_for']).assertFalse();
      expect(settings['sound_id']).assertEqual('0');
      expect(settings['story_sound_id']).assertEqual('0');
      coordinator.destroy();
    });

    it('enableNotificationsMenuAction_sendsMuteForZero', 0, () => {
      const bridge: TestNativeBridge = new TestNativeBridge();
      const scope: AccountScope = createScope(bridge);
      const coordinator: ChatCoordinator = new ChatCoordinator(scope, 42, 'Test Chat');

      coordinator.dispatch(new ChatMenuAction('mute'));
      coordinator.dispatch(new ChatMenuAction('enable_notifications'));

      const req: Record<string, TdWireValue> | null = lastMuteRequest(bridge);
      expect(req === null).assertFalse();
      if (req === null) {
        coordinator.destroy();
        return;
      }
      const settings: Record<string, TdWireValue> = req['notification_settings'] as Record<string, TdWireValue>;
      expect(settings['mute_for']).assertEqual(0);
      coordinator.destroy();
    });

    it('updateChatNotificationSettings_flipsMuteState', 0, async (): Promise<void> => {
      const bridge: TestNativeBridge = new TestNativeBridge();
      const scope: AccountScope = createScope(bridge);
      const coordinator: ChatCoordinator = new ChatCoordinator(scope, 42, 'Test Chat');
      coordinator.start();
      expect(coordinator.state.isMuted).assertFalse();

      bridge.emitUpdate(1, updatePayload(42, settingsOf(CHAT_MUTE_FOREVER_SECONDS)));
      await settle();
      expect(coordinator.state.isMuted).assertTrue();

      bridge.emitUpdate(1, updatePayload(42, settingsOf(0)));
      await settle();
      expect(coordinator.state.isMuted).assertFalse();

      coordinator.destroy();
    });

    it('updateChatNotificationSettings_forOtherChatIsIgnored', 0, async (): Promise<void> => {
      const bridge: TestNativeBridge = new TestNativeBridge();
      const scope: AccountScope = createScope(bridge);
      const coordinator: ChatCoordinator = new ChatCoordinator(scope, 42, 'Test Chat');
      coordinator.start();

      bridge.emitUpdate(1, updatePayload(777, settingsOf(CHAT_MUTE_FOREVER_SECONDS)));
      await settle();
      expect(coordinator.state.isMuted).assertFalse();

      coordinator.destroy();
    });
  });
}
