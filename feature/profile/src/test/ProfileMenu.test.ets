/**
 * feature/profile — User Info ⋮ 头部菜单真实动作单元测试（PROFILE-103 收尾 / PROFILE-MENU）。
 *
 * 守住的行为：
 * 1. 「开启密聊」发 createNewSecretChat，回执 secretChat.id 直接交给装配层导航
 *    （密聊 id 同时就是 chat.id，不需要新路由）；失败只提示，不留假跳转。
 * 2. 屏蔽真值来自那一次 getChat 的 block_list：null 才是「未屏蔽」，读不到就退回
 *    「未读取」，菜单不能拿默认值冒充真值。
 * 3. 屏蔽写请求走 setMessageSenderBlockList（本 schema 无 blockUser）：
 *    屏蔽传 blockListMain，解除传 null；写成功后 getChat 复核，无乐观改写。
 * 4. updateChatBlockList 推送实时翻态，且只认本会话的 chat_id。
 * 5. 白名单外的 action 一律 no-op —— 菜单里不允许存在点了什么都不发生的入口。
 */

import { describe, it, expect } from '@ohos/hypium';
import { AppError, Result } from '@tgx/core-common';
import { AccountScope, buildAccountDirectories, createDescriptor, AccountDirectoryLayout } from '@tgx/core-account';
import { FakeAppFiles, ToastPort } from '@tgx/platform-ports';
import {
  TdNativeBridgeLike,
  TdNativeBridgeMetrics,
  TdNativeEvent,
  TdNativeEventSink,
  TdWireObject,
  TdWireValue
} from '@tgx/td-gateway';
import { ProfileCoordinator, ProfileCoordinatorOptions } from '../main/ets/coordinator/ProfileCoordinator';
import {
  OnProfileLoaded,
  ProfileMenuAction,
  PROFILE_MENU_SECRET_CHAT,
  PROFILE_MENU_TOGGLE_BLOCK
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

  respondTo(requestId: string, fields: Record<string, TdWireValue>): void {
    const payload: TdWireObject = this.clone(fields);
    const extra: Record<string, TdWireValue> = {};
    extra['requestId'] = requestId;
    payload['@extra'] = extra;
    this.deliver(payload);
  }

  respondWithError(requestId: string, message: string): void {
    const fields: Record<string, TdWireValue> = {};
    fields['@type'] = 'error';
    fields['code'] = 400;
    fields['message'] = message;
    this.respondTo(requestId, fields);
  }

  emitUpdate(payload: Record<string, TdWireValue>): void {
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

class RecordingToast implements ToastPort {
  readonly messages: string[] = [];

  showToast(message: string, durationMs?: number): void {
    this.messages.push(message);
  }
}

/** 一次用例的捕获器：导航落点 + 提示文案，避免用例间共享模块级状态。 */
class Capture {
  readonly openedChatIds: number[] = [];
  readonly toast: RecordingToast = new RecordingToast();
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

function lastRequestId(bridge: TestNativeBridge, type: string): string {
  const all: Record<string, TdWireValue>[] = requestsOfType(bridge, type);
  if (all.length === 0) {
    return '';
  }
  const extra: Record<string, TdWireValue> | undefined =
    all[all.length - 1]['@extra'] as Record<string, TdWireValue> | undefined;
  return extra !== undefined && extra !== null ? String(extra['requestId']) : '';
}

function notificationJson(): Record<string, TdWireValue> {
  const settings: Record<string, TdWireValue> = {};
  settings['@type'] = 'chatNotificationSettings';
  settings['use_default_mute_for'] = false;
  settings['mute_for'] = 0;
  settings['use_default_sound'] = true;
  settings['sound_id'] = '0';
  settings['use_default_show_preview'] = true;
  settings['use_default_mute_stories'] = true;
  settings['use_default_story_sound'] = true;
  settings['story_sound_id'] = '0';
  settings['use_default_show_story_poster'] = true;
  settings['use_default_disable_pinned_message_notifications'] = true;
  settings['use_default_disable_mention_notifications'] = true;
  return settings;
}

/** blockList 传 null 表示 chat 不在任何黑名单（TDLib 语义即「未屏蔽」）。 */
function chatJson(chatId: number, blockList: Record<string, TdWireValue> | null): Record<string, TdWireValue> {
  const type: Record<string, TdWireValue> = {};
  type['@type'] = 'chatTypePrivate';
  type['user_id'] = chatId;
  const fields: Record<string, TdWireValue> = {};
  fields['@type'] = 'chat';
  fields['id'] = chatId;
  fields['title'] = 'Peer';
  fields['type'] = type;
  fields['notification_settings'] = notificationJson();
  if (blockList !== null) {
    fields['block_list'] = blockList;
  }
  return fields;
}

function blockListMainJson(): Record<string, TdWireValue> {
  const fields: Record<string, TdWireValue> = {};
  fields['@type'] = 'blockListMain';
  return fields;
}

function secretChatJson(secretChatId: number, userId: number): Record<string, TdWireValue> {
  const state: Record<string, TdWireValue> = {};
  state['@type'] = 'secretChatStatePending';
  const fields: Record<string, TdWireValue> = {};
  fields['@type'] = 'secretChat';
  fields['id'] = secretChatId;
  fields['user_id'] = userId;
  fields['state'] = state;
  fields['is_outbound'] = true;
  fields['key_hash'] = '';
  fields['layer'] = 101;
  return fields;
}

function okJson(): Record<string, TdWireValue> {
  const fields: Record<string, TdWireValue> = {};
  fields['@type'] = 'ok';
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
const SECRET_CHAT_ID: number = 777;

/** 走完首屏（含那一次 getChat 回读），返回协调器与捕获到的导航/提示。 */
async function openProfile(
  bridge: TestNativeBridge,
  blockList: Record<string, TdWireValue> | null,
  capture: Capture
): Promise<ProfileCoordinator> {
  const scope: AccountScope = createScope(bridge, 'test_profile_menu');
  const options: ProfileCoordinatorOptions = {
    onOpenChat: (chatId: number): void => {
      capture.openedChatIds.push(chatId);
    },
    toastPort: capture.toast
  };
  const coordinator: ProfileCoordinator = new ProfileCoordinator(scope, PEER_ID, options);
  coordinator.dispatch(new OnProfileLoaded('Peer', '', '', '', 'P', 0));
  await settle();

  const createId: string = lastRequestId(bridge, 'createPrivateChat');
  expect(createId.length > 0).assertTrue();
  bridge.respondTo(createId, chatJson(PEER_ID, null));
  await settle();

  const searchId: string = lastRequestId(bridge, 'searchChatMessages');
  if (searchId.length > 0) {
    bridge.respondTo(searchId, emptyFound());
  }
  bridge.respondTo(lastRequestId(bridge, 'getChat'), chatJson(PEER_ID, blockList));
  await settle();
  return coordinator;
}

export default function profileMenuTest(): void {
  describe('ProfileMenuTest', () => {

    it('secretChat_createsAndNavigatesWithSecretChatId', 0, async (): Promise<void> => {
      const bridge: TestNativeBridge = new TestNativeBridge();
      const capture: Capture = new Capture();
      const coordinator: ProfileCoordinator = await openProfile(bridge, null, capture);

      coordinator.dispatch(new ProfileMenuAction(PROFILE_MENU_SECRET_CHAT));
      await settle();
      const creates: Record<string, TdWireValue>[] = requestsOfType(bridge, 'createNewSecretChat');
      expect(creates.length).assertEqual(1);
      expect(creates[0]['user_id']).assertEqual(PEER_ID);
      expect(capture.openedChatIds.length).assertEqual(0);

      bridge.respondTo(lastRequestId(bridge, 'createNewSecretChat'), secretChatJson(SECRET_CHAT_ID, PEER_ID));
      await settle();
      // 密聊 id 就是 chat.id（type 为 chatTypeSecret），复用同一条导航即可打开。
      expect(capture.openedChatIds.length).assertEqual(1);
      expect(capture.openedChatIds[0]).assertEqual(SECRET_CHAT_ID);
      expect(capture.toast.messages.length).assertEqual(0);
      coordinator.destroy();
    });

    it('secretChat_errorResponse_toastsWithoutNavigating', 0, async (): Promise<void> => {
      const bridge: TestNativeBridge = new TestNativeBridge();
      const capture: Capture = new Capture();
      const coordinator: ProfileCoordinator = await openProfile(bridge, null, capture);

      coordinator.dispatch(new ProfileMenuAction(PROFILE_MENU_SECRET_CHAT));
      await settle();
      bridge.respondWithError(lastRequestId(bridge, 'createNewSecretChat'), 'SECRET_CHAT_TOO_OLD');
      await settle();
      expect(capture.openedChatIds.length).assertEqual(0);
      expect(capture.toast.messages.length).assertEqual(1);
      coordinator.destroy();
    });

    it('block_beforeReadBack_isNoOp', 0, async (): Promise<void> => {
      const bridge: TestNativeBridge = new TestNativeBridge();
      const scope: AccountScope = createScope(bridge, 'test_profile_menu');
      const coordinator: ProfileCoordinator = new ProfileCoordinator(scope, PEER_ID);
      coordinator.dispatch(new ProfileMenuAction(PROFILE_MENU_TOGGLE_BLOCK));

      // 真值没读到就点，不能凭默认值把人写进黑名单。
      expect(requestsOfType(bridge, 'setMessageSenderBlockList').length).assertEqual(0);
      expect(coordinator.state.peerBlockUpdating).assertFalse();
      expect(coordinator.state.peerBlockReady).assertFalse();
      coordinator.destroy();
    });

    it('block_readBackFromGetChatBlockList', 0, async (): Promise<void> => {
      const bridge: TestNativeBridge = new TestNativeBridge();
      const capture: Capture = new Capture();
      const coordinator: ProfileCoordinator = await openProfile(bridge, blockListMainJson(), capture);

      expect(coordinator.state.peerBlockReady).assertTrue();
      expect(coordinator.state.peerBlocked).assertTrue();
      coordinator.destroy();
    });

    it('block_writesBlockListMainThenReReads', 0, async (): Promise<void> => {
      const bridge: TestNativeBridge = new TestNativeBridge();
      const capture: Capture = new Capture();
      const coordinator: ProfileCoordinator = await openProfile(bridge, null, capture);
      expect(coordinator.state.peerBlocked).assertFalse();

      coordinator.dispatch(new ProfileMenuAction(PROFILE_MENU_TOGGLE_BLOCK));
      const writes: Record<string, TdWireValue>[] = requestsOfType(bridge, 'setMessageSenderBlockList');
      expect(writes.length).assertEqual(1);
      const sender: Record<string, TdWireValue> = writes[0]['sender_id'] as Record<string, TdWireValue>;
      expect(String(sender['@type'])).assertEqual('messageSenderUser');
      expect(sender['user_id']).assertEqual(PEER_ID);
      const list: Record<string, TdWireValue> = writes[0]['block_list'] as Record<string, TdWireValue>;
      expect(String(list['@type'])).assertEqual('blockListMain');

      // 不做乐观改写：文案只跟 getChat 复核回来的真值翻。
      expect(coordinator.state.peerBlocked).assertFalse();
      expect(coordinator.state.peerBlockUpdating).assertTrue();

      const before: number = requestsOfType(bridge, 'getChat').length;
      bridge.respondTo(lastRequestId(bridge, 'setMessageSenderBlockList'), okJson());
      await settle();
      expect(requestsOfType(bridge, 'getChat').length).assertEqual(before + 1);
      expect(coordinator.state.peerBlocked).assertFalse();

      bridge.respondTo(lastRequestId(bridge, 'getChat'), chatJson(PEER_ID, blockListMainJson()));
      await settle();
      expect(coordinator.state.peerBlocked).assertTrue();
      expect(coordinator.state.peerBlockReady).assertTrue();
      expect(coordinator.state.peerBlockUpdating).assertFalse();
      coordinator.destroy();
    });

    it('unblock_sendsNullBlockList', 0, async (): Promise<void> => {
      const bridge: TestNativeBridge = new TestNativeBridge();
      const capture: Capture = new Capture();
      const coordinator: ProfileCoordinator = await openProfile(bridge, blockListMainJson(), capture);

      coordinator.dispatch(new ProfileMenuAction(PROFILE_MENU_TOGGLE_BLOCK));
      const writes: Record<string, TdWireValue>[] = requestsOfType(bridge, 'setMessageSenderBlockList');
      expect(writes.length).assertEqual(1);
      // 解除 = block_list 传 null（TDLib 明确语义），不是删字段。
      expect(writes[0]['block_list'] === null || writes[0]['block_list'] === undefined).assertTrue();

      bridge.respondTo(lastRequestId(bridge, 'setMessageSenderBlockList'), okJson());
      await settle();
      bridge.respondTo(lastRequestId(bridge, 'getChat'), chatJson(PEER_ID, null));
      await settle();
      expect(coordinator.state.peerBlocked).assertFalse();
      coordinator.destroy();
    });

    it('block_writeFailure_clearsUpdatingAndToasts', 0, async (): Promise<void> => {
      const bridge: TestNativeBridge = new TestNativeBridge();
      const capture: Capture = new Capture();
      const coordinator: ProfileCoordinator = await openProfile(bridge, null, capture);

      coordinator.dispatch(new ProfileMenuAction(PROFILE_MENU_TOGGLE_BLOCK));
      bridge.respondWithError(lastRequestId(bridge, 'setMessageSenderBlockList'), 'CHAT_ADMIN_REQUIRED');
      await settle();
      expect(coordinator.state.peerBlockUpdating).assertFalse();
      expect(coordinator.state.peerBlockReady).assertFalse();
      expect(capture.toast.messages.length).assertEqual(1);
      coordinator.destroy();
    });

    it('blockListUpdate_pushFlipsStateForThisChatOnly', 0, async (): Promise<void> => {
      const bridge: TestNativeBridge = new TestNativeBridge();
      const capture: Capture = new Capture();
      const coordinator: ProfileCoordinator = await openProfile(bridge, null, capture);

      const otherChat: Record<string, TdWireValue> = {};
      otherChat['@type'] = 'updateChatBlockList';
      otherChat['chat_id'] = 9999;
      otherChat['block_list'] = blockListMainJson();
      bridge.emitUpdate(otherChat);
      await settle();
      expect(coordinator.state.peerBlocked).assertFalse();

      const mine: Record<string, TdWireValue> = {};
      mine['@type'] = 'updateChatBlockList';
      mine['chat_id'] = PEER_ID;
      mine['block_list'] = blockListMainJson();
      bridge.emitUpdate(mine);
      await settle();
      expect(coordinator.state.peerBlocked).assertTrue();
      expect(coordinator.state.peerBlockReady).assertTrue();
      coordinator.destroy();
    });

    it('unknownAction_sendsNothing', 0, async (): Promise<void> => {
      const bridge: TestNativeBridge = new TestNativeBridge();
      const capture: Capture = new Capture();
      const coordinator: ProfileCoordinator = await openProfile(bridge, null, capture);
      const sentBefore: number = bridge.sent.length;

      coordinator.dispatch(new ProfileMenuAction('share_contact'));
      await settle();
      expect(bridge.sent.length).assertEqual(sentBefore);
      expect(capture.toast.messages.length).assertEqual(0);
      const state: ProfileUiState = coordinator.state;
      expect(state.peerBlockUpdating).assertFalse();
      coordinator.destroy();
    });
  });
}
