/**
 * feature/profile — User Info 通知行真实态单元测试（PROFILE-103 收尾 / PROFILE-NOTIF）。
 *
 * 守住的行为：
 * 1. 通知行文案来自 getChat.notification_settings 的真值，不是写死的「开启」；
 *    TDLib 没给设置时退回「未知」，而不是猜一个「未静音」。
 * 2. 首屏共享内容与通知两路数据共用一条 createPrivateChat（在途排队，不多发往返）。
 * 3. 点击只发反向写请求，且以回读快照为底本 —— int64 的 sound_id 必须原样带回，
 *    写空串会被 TDLib 直接判 bad_request（MENU-101 首版因此从未生效）。
 * 4. 写成功前不改文案（无乐观更新），写完后 getChat 复核真值。
 * 5. updateChatNotificationSettings 推送实时翻态，且只认本会话的 chat_id。
 */

import { describe, it, expect } from '@ohos/hypium';
import { AppError, Result } from '@tgx/core-common';
import { AccountScope, buildAccountDirectories, createDescriptor, AccountDirectoryLayout } from '@tgx/core-account';
import { FakeAppFiles } from '@tgx/platform-ports';
import { CHAT_MUTE_FOREVER_SECONDS } from '@tgx/core-domain';
import {
  TdNativeBridgeLike,
  TdNativeBridgeMetrics,
  TdNativeEvent,
  TdNativeEventSink,
  TdWireObject,
  TdWireValue
} from '@tgx/td-gateway';
import { ProfileCoordinator } from '../main/ets/coordinator/ProfileCoordinator';
import {
  OnProfileLoaded,
  NotificationRowTapped
} from '../main/ets/contract/ProfileIntent';
import { ProfileUiState } from '../main/ets/contract/ProfileUiState';

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

  /** 按 requestId 回一个响应（走 @extra.requestId 唤醒 pending 请求）。 */
  respondTo(requestId: string, fields: Record<string, TdWireValue>): void {
    const payload: TdWireObject = this.clone(fields);
    const extra: Record<string, TdWireValue> = {};
    extra['requestId'] = requestId;
    payload['@extra'] = extra;
    this.deliver(payload);
  }

  /** 推一条不带 @extra 的更新，模拟对端/其它客户端改动。 */
  emitUpdate(clientId: number, payload: Record<string, TdWireValue>): void {
    this.deliver(this.clone(payload));
  }

  private clone(fields: Record<string, TdWireValue>): TdWireObject {
    const payload: TdWireObject = {};
    for (const key of Object.keys(fields)) {
      payload[key] = fields[key];
    }
    return payload;
  }

  private deliver(payload: TdWireObject): void {
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
}

function createScope(bridge: TestNativeBridge, name: string): AccountScope {
  const layoutRes: Result<AccountDirectoryLayout, AppError> = buildAccountDirectories(name);
  if (layoutRes.ok === false) {
    throw new Error('Failed to build directories');
  }
  const scopeRes: Result<AccountScope, AppError> = AccountScope.open({
    bridge: bridge,
    files: new FakeAppFiles(),
    descriptor: createDescriptor(name, 'acct_user_1', 0, true),
    directories: layoutRes.value,
    startActive: true
  });
  if (scopeRes.ok === false) {
    throw new Error('Failed to open AccountScope');
  }
  return scopeRes.value;
}

function requestsOfType(bridge: TestNativeBridge, type: string): Record<string, TdWireValue>[] {
  const out: Record<string, TdWireValue>[] = [];
  for (let i = 0; i < bridge.sent.length; i++) {
    const req: Record<string, TdWireValue> = JSON.parse(bridge.sent[i]) as Record<string, TdWireValue>;
    if (req['@type'] === type) {
      out.push(req);
    }
  }
  return out;
}

/** 最近一条 @type 匹配请求的 @extra.requestId。 */
function lastRequestId(bridge: TestNativeBridge, type: string): string {
  const all: Record<string, TdWireValue>[] = requestsOfType(bridge, type);
  if (all.length === 0) {
    return '';
  }
  const extra: Record<string, TdWireValue> | undefined =
    all[all.length - 1]['@extra'] as Record<string, TdWireValue> | undefined;
  return extra !== undefined && extra !== null ? String(extra['requestId']) : '';
}

function notificationJson(muteFor: number, soundId: string, useDefaultSound: boolean): Record<string, TdWireValue> {
  const settings: Record<string, TdWireValue> = {};
  settings['@type'] = 'chatNotificationSettings';
  settings['use_default_mute_for'] = false;
  settings['mute_for'] = muteFor;
  settings['use_default_sound'] = useDefaultSound;
  settings['sound_id'] = soundId;
  settings['use_default_show_preview'] = true;
  settings['use_default_mute_stories'] = true;
  settings['use_default_story_sound'] = true;
  settings['story_sound_id'] = '0';
  settings['use_default_show_story_poster'] = true;
  settings['use_default_disable_pinned_message_notifications'] = true;
  settings['use_default_disable_mention_notifications'] = true;
  return settings;
}

function chatJson(chatId: number, notification: Record<string, TdWireValue> | null): Record<string, TdWireValue> {
  const type: Record<string, TdWireValue> = {};
  type['@type'] = 'chatTypePrivate';
  type['user_id'] = chatId;
  const fields: Record<string, TdWireValue> = {};
  fields['@type'] = 'chat';
  fields['id'] = chatId;
  fields['title'] = 'Peer';
  fields['type'] = type;
  if (notification !== null) {
    fields['notification_settings'] = notification;
  }
  return fields;
}

function okJson(): Record<string, TdWireValue> {
  const fields: Record<string, TdWireValue> = {};
  fields['@type'] = 'ok';
  return fields;
}

function updateJson(chatId: number, notification: Record<string, TdWireValue>): Record<string, TdWireValue> {
  const fields: Record<string, TdWireValue> = {};
  fields['@type'] = 'updateChatNotificationSettings';
  fields['chat_id'] = chatId;
  fields['notification_settings'] = notification;
  return fields;
}

function emptyFound(): Record<string, TdWireValue> {
  const fields: Record<string, TdWireValue> = {};
  fields['@type'] = 'foundChatMessages';
  fields['total_count'] = 0;
  fields['messages'] = [];
  fields['next_from_message_id'] = 0;
  return fields;
}

function settle(): Promise<void> {
  return new Promise<void>((resolve: () => void): void => {
    setTimeout(resolve, 30);
  });
}

const PEER_ID: number = 4242;

/**
 * 走完首屏：OnProfileLoaded → 唯一一条 createPrivateChat 回包 →
 * 共享内容与通知两路各自的请求发出 → getChat 喂入给定设置。
 * notification 传 null 表示 TDLib 没给 notification_settings。
 */
async function openWithNotification(
  bridge: TestNativeBridge,
  notification: Record<string, TdWireValue> | null
): Promise<ProfileCoordinator> {
  const scope: AccountScope = createScope(bridge, 'test_profile_notification');
  const coordinator: ProfileCoordinator = new ProfileCoordinator(scope, PEER_ID);
  coordinator.dispatch(new OnProfileLoaded('Peer', '', '', '', 'P', 0));
  await settle();

  const createId: string = lastRequestId(bridge, 'createPrivateChat');
  expect(createId.length > 0).assertTrue();
  const type: Record<string, TdWireValue> = {};
  type['@type'] = 'chatTypePrivate';
  type['user_id'] = PEER_ID;
  const peer: Record<string, TdWireValue> = {};
  peer['@type'] = 'chat';
  peer['id'] = PEER_ID;
  peer['title'] = 'Peer';
  peer['type'] = type;
  bridge.respondTo(createId, peer);
  await settle();

  const searchId: string = lastRequestId(bridge, 'searchChatMessages');
  if (searchId.length > 0) {
    bridge.respondTo(searchId, emptyFound());
  }
  const getChatId: string = lastRequestId(bridge, 'getChat');
  expect(getChatId.length > 0).assertTrue();
  bridge.respondTo(getChatId, chatJson(PEER_ID, notification));
  await settle();
  return coordinator;
}

export default function profileNotificationTest(): void {
  describe('ProfileNotificationTest', () => {

    it('firstScreen_sharesOneCreatePrivateChat', 0, async (): Promise<void> => {
      const bridge: TestNativeBridge = new TestNativeBridge();
      const coordinator: ProfileCoordinator = await openWithNotification(
        bridge, notificationJson(0, '0', true));

      // 共享内容 + 通知两路数据都挂在私聊 chatId 上，但只允许一次建会话往返。
      expect(requestsOfType(bridge, 'createPrivateChat').length).assertEqual(1);
      expect(requestsOfType(bridge, 'searchChatMessages').length > 0).assertTrue();
      expect(requestsOfType(bridge, 'getChat').length > 0).assertTrue();
      coordinator.destroy();
    });

    it('readBack_setsRealMutedState', 0, async (): Promise<void> => {
      const bridge: TestNativeBridge = new TestNativeBridge();
      const coordinator: ProfileCoordinator = await openWithNotification(
        bridge, notificationJson(CHAT_MUTE_FOREVER_SECONDS, '0', true));

      const state: ProfileUiState = coordinator.state;
      expect(state.notificationReady).assertTrue();
      expect(state.notificationMuted).assertTrue();
      expect(state.notificationUpdating).assertFalse();
      coordinator.destroy();
    });

    it('readBack_unmuted_showsEnabled', 0, async (): Promise<void> => {
      const bridge: TestNativeBridge = new TestNativeBridge();
      const coordinator: ProfileCoordinator = await openWithNotification(
        bridge, notificationJson(0, '0', true));

      expect(coordinator.state.notificationReady).assertTrue();
      expect(coordinator.state.notificationMuted).assertFalse();
      coordinator.destroy();
    });

    it('readBack_missingSettings_staysUnknown', 0, async (): Promise<void> => {
      const bridge: TestNativeBridge = new TestNativeBridge();
      const coordinator: ProfileCoordinator = await openWithNotification(bridge, null);

      // 没读到设置就不表态：页面退回「—」，而不是硬写一个「开启」。
      expect(coordinator.state.notificationReady).assertFalse();
      expect(coordinator.state.notificationMuted).assertFalse();
      coordinator.destroy();
    });

    it('tap_sendsOppositeOnSnapshotWithoutOptimisticLabel', 0, async (): Promise<void> => {
      const bridge: TestNativeBridge = new TestNativeBridge();
      // 底本用非默认 sound_id：写请求必须原样带回，不能被编码成 ''。
      const coordinator: ProfileCoordinator = await openWithNotification(
        bridge, notificationJson(0, '12345', false));

      coordinator.dispatch(new NotificationRowTapped());
      const state: ProfileUiState = coordinator.state;
      expect(state.notificationUpdating).assertTrue();
      expect(state.notificationMuted).assertFalse();

      const writes: Record<string, TdWireValue>[] = requestsOfType(bridge, 'setChatNotificationSettings');
      expect(writes.length).assertEqual(1);
      expect(writes[0]['chat_id']).assertEqual(PEER_ID);
      const written: Record<string, TdWireValue> =
        writes[0]['notification_settings'] as Record<string, TdWireValue>;
      expect(written['mute_for']).assertEqual(CHAT_MUTE_FOREVER_SECONDS);
      expect(written['use_default_mute_for']).assertFalse();
      expect(String(written['sound_id'])).assertEqual('12345');
      expect(written['use_default_sound']).assertFalse();

      // 写成功后由 getChat 复核，文案才跟着回读翻过去。
      bridge.respondTo(lastRequestId(bridge, 'setChatNotificationSettings'), okJson());
      await settle();
      expect(coordinator.state.notificationMuted).assertFalse();
      expect(coordinator.state.notificationUpdating).assertTrue();

      bridge.respondTo(lastRequestId(bridge, 'getChat'),
        chatJson(PEER_ID, notificationJson(CHAT_MUTE_FOREVER_SECONDS, '12345', false)));
      await settle();
      expect(coordinator.state.notificationMuted).assertTrue();
      expect(coordinator.state.notificationUpdating).assertFalse();
      coordinator.destroy();
    });

    it('updatePush_flipsStateForThisChatOnly', 0, async (): Promise<void> => {
      const bridge: TestNativeBridge = new TestNativeBridge();
      const coordinator: ProfileCoordinator = await openWithNotification(
        bridge, notificationJson(0, '0', true));

      bridge.emitUpdate(1, updateJson(9999, notificationJson(CHAT_MUTE_FOREVER_SECONDS, '0', true)));
      await settle();
      expect(coordinator.state.notificationMuted).assertFalse();

      bridge.emitUpdate(1, updateJson(PEER_ID, notificationJson(CHAT_MUTE_FOREVER_SECONDS, '0', true)));
      await settle();
      expect(coordinator.state.notificationMuted).assertTrue();
      expect(coordinator.state.notificationReady).assertTrue();
      coordinator.destroy();
    });

    it('tap_beforeReadBack_isNoOp', 0, async (): Promise<void> => {
      const bridge: TestNativeBridge = new TestNativeBridge();
      const scope: AccountScope = createScope(bridge, 'test_profile_notification');
      const coordinator: ProfileCoordinator = new ProfileCoordinator(scope, PEER_ID);
      coordinator.dispatch(new OnProfileLoaded('Peer', '', '', '', 'P', 0));
      coordinator.dispatch(new NotificationRowTapped());

      // 真值都没读到就点，不能凭默认值反着写一次。
      expect(requestsOfType(bridge, 'setChatNotificationSettings').length).assertEqual(0);
      expect(coordinator.state.notificationUpdating).assertFalse();
      coordinator.destroy();
    });
  });
}
