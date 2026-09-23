/**
 * feature/profile — 共享媒体「不丢条目」单元测试（PROFILE-103 收尾缺陷）。
 *
 * 守住的行为：媒体 Tab 的每一条照片/视频消息都必须在网格里出现一座。
 * 真机证据曾暴露：分页第二页回了 2 条消息，因为缩略图 size 尚未缓存
 * （`photo.sizes` 为空 / video 无 cover 无 thumbnail），旧映射直接返回 null，
 * 条目被静默丢掉 → 网格永远少格子，且翻页回来的数据无法复现。
 * 现在必须落成占位条目（fileId=0, localPath=null），由 ProfilePage 的占位瓦片渲染。
 */

import { describe, it, expect } from '@ohos/hypium';
import { AppError, Result } from '@tgx/core-common';
import { AccountScope, buildAccountDirectories, createDescriptor, AccountDirectoryLayout } from '@tgx/core-account';
import { FakeAppFiles } from '@tgx/platform-ports';
import {
  TdNativeBridgeLike,
  TdNativeBridgeMetrics,
  TdNativeEvent,
  TdNativeEventSink,
  TdWireObject,
  TdWireValue
} from '@tgx/td-gateway';
import { ProfileCoordinator } from '../main/ets/coordinator/ProfileCoordinator';
import { OnProfileLoaded, LoadMoreSharedContent } from '../main/ets/contract/ProfileIntent';
import { SharedMediaItem } from '../main/ets/contract/SharedContentItems';

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
    const extra: Record<string, TdWireValue> = {};
    extra['requestId'] = requestId;
    const payload: TdWireObject = {};
    for (const key of Object.keys(fields)) {
      payload[key] = fields[key];
    }
    payload['@extra'] = extra;
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

/** 取最近一条 @type 匹配的请求里的 @extra.requestId。 */
function lastRequestId(bridge: TestNativeBridge, type: string): string {
  for (let i = bridge.sent.length - 1; i >= 0; i--) {
    const req: Record<string, TdWireValue> = JSON.parse(bridge.sent[i]) as Record<string, TdWireValue>;
    if (req['@type'] === type) {
      const extra: Record<string, TdWireValue> | undefined =
        req['@extra'] as Record<string, TdWireValue> | undefined;
      return extra !== undefined && extra !== null ? String(extra['requestId']) : '';
    }
  }
  return '';
}

function privateChatResponse(chatId: number): Record<string, TdWireValue> {
  const type: Record<string, TdWireValue> = {};
  type['@type'] = 'chatTypePrivate';
  type['user_id'] = 4242;
  const fields: Record<string, TdWireValue> = {};
  fields['@type'] = 'chat';
  fields['id'] = chatId;
  fields['title'] = 'Peer';
  fields['type'] = type;
  return fields;
}

function fileValue(fileId: number): Record<string, TdWireValue> {
  const remote: Record<string, TdWireValue> = {};
  remote['@type'] = 'remoteFileId';
  remote['id'] = String(fileId);
  remote['is_upload_active_completed'] = true;
  remote['uploaded_size'] = 1024;
  remote['download_size'] = 1024;
  const local: Record<string, TdWireValue> = {};
  local['@type'] = 'localFile';
  local['is_downloaded_active'] = false;
  local['is_downloaded_completed'] = false;
  const fields: Record<string, TdWireValue> = {};
  fields['@type'] = 'file';
  fields['id'] = fileId;
  fields['size'] = 1024;
  fields['expected_remote_file_id'] = String(fileId);
  fields['remote'] = remote;
  fields['local'] = local;
  return fields;
}

function photoSizeValue(fileId: number, width: number): Record<string, TdWireValue> {
  const size: Record<string, TdWireValue> = {};
  size['@type'] = 'photoSize';
  size['type'] = 'photoSizeLarge';
  size['photo'] = fileValue(fileId);
  size['width'] = width;
  size['height'] = width;
  return size;
}

function photoMessage(messageId: number, sizes: Record<string, TdWireValue>[]): Record<string, TdWireValue> {
  const photo: Record<string, TdWireValue> = {};
  photo['@type'] = 'photo';
  photo['id'] = messageId * 10;
  photo['sizes'] = sizes;
  const content: Record<string, TdWireValue> = {};
  content['@type'] = 'messagePhoto';
  content['photo'] = photo;
  const msg: Record<string, TdWireValue> = {};
  msg['@type'] = 'message';
  msg['id'] = messageId;
  msg['chat_id'] = 4242;
  msg['date'] = 1700000000;
  msg['content'] = content;
  return msg;
}

function videoMessageWithoutThumb(messageId: number): Record<string, TdWireValue> {
  const video: Record<string, TdWireValue> = {};
  video['@type'] = 'video';
  video['duration'] = 12;
  video['mime_type'] = 'video/mp4';
  video['video'] = fileValue(messageId * 100);
  video['thumbnail'] = null;
  const content: Record<string, TdWireValue> = {};
  content['@type'] = 'messageVideo';
  content['video'] = video;
  content['cover'] = null;
  const msg: Record<string, TdWireValue> = {};
  msg['@type'] = 'message';
  msg['id'] = messageId;
  msg['chat_id'] = 4242;
  msg['date'] = 1700000000;
  msg['content'] = content;
  return msg;
}

function foundMessages(messages: Record<string, TdWireValue>[], nextFromId: number): Record<string, TdWireValue> {
  const fields: Record<string, TdWireValue> = {};
  fields['@type'] = 'foundChatMessages';
  fields['total_count'] = messages.length;
  fields['messages'] = messages;
  fields['next_from_message_id'] = nextFromId;
  return fields;
}

function settle(): Promise<void> {
  return new Promise<void>((resolve: () => void): void => {
    setTimeout(resolve, 30);
  });
}

/** 走完「首屏 → createPrivateChat → searchChatMessages」链路，喂入给定的一页消息。 */
async function openWithPage(
  bridge: TestNativeBridge,
  messages: Record<string, TdWireValue>[],
  nextFromId: number
): Promise<ProfileCoordinator> {
  const scope: AccountScope = createScope(bridge, 'test_shared_media_placeholder');
  const coordinator: ProfileCoordinator = new ProfileCoordinator(scope, 4242);
  coordinator.dispatch(new OnProfileLoaded('Peer', '', '', '', 'P', 0));

  const createId: string = lastRequestId(bridge, 'createPrivateChat');
  expect(createId.length > 0).assertTrue();
  bridge.respondTo(createId, privateChatResponse(4242));
  await settle();

  const searchId: string = lastRequestId(bridge, 'searchChatMessages');
  expect(searchId.length > 0).assertTrue();
  bridge.respondTo(searchId, foundMessages(messages, nextFromId));
  await settle();
  return coordinator;
}

function expectPlaceholder(item: SharedMediaItem, isPhoto: boolean): void {
  expect(item.fileId).assertEqual(0);
  expect(item.localPath === null).assertTrue();
  expect(item.isPhoto).assertEqual(isPhoto);
}

export default function sharedMediaPlaceholderTest(): void {
  describe('SharedMediaPlaceholderTest', () => {

    it('photoWithoutCachedSizes_keepsPlaceholderTile', 0, async (): Promise<void> => {
      const bridge: TestNativeBridge = new TestNativeBridge();
      const coordinator: ProfileCoordinator = await openWithPage(
        bridge, [photoMessage(101, [])], 0);

      // sizes 未缓存时也必须留下一座占位瓦片，不能静默丢消息。
      expect(coordinator.state.sharedMedia.length).assertEqual(1);
      expectPlaceholder(coordinator.state.sharedMedia[0], true);
      coordinator.destroy();
    });

    it('videoWithoutCoverOrThumbnail_keepsPlaceholderTile', 0, async (): Promise<void> => {
      const bridge: TestNativeBridge = new TestNativeBridge();
      const coordinator: ProfileCoordinator = await openWithPage(
        bridge, [videoMessageWithoutThumb(202)], 0);

      expect(coordinator.state.sharedMedia.length).assertEqual(1);
      expectPlaceholder(coordinator.state.sharedMedia[0], false);
      coordinator.destroy();
    });

    it('loadMorePageWithUnresolvedThumbs_appendsPlaceholders', 0, async (): Promise<void> => {
      const bridge: TestNativeBridge = new TestNativeBridge();
      const firstSize: Record<string, TdWireValue>[] = [photoSizeValue(9001, 640)];
      const coordinator: ProfileCoordinator = await openWithPage(
        bridge, [photoMessage(303, firstSize)], 58720256);

      expect(coordinator.state.sharedMedia.length).assertEqual(1);
      expect(coordinator.state.sharedMedia[0].fileId).assertEqual(9001);
      expect(coordinator.state.sharedHasMore).assertTrue();

      coordinator.dispatch(new LoadMoreSharedContent(0));
      const searchId: string = lastRequestId(bridge, 'searchChatMessages');
      expect(searchId.length > 0).assertTrue();
      // 第二页：一条缩略图未缓存的照片 + 一条无封面的视频。
      bridge.respondTo(searchId, foundMessages([photoMessage(404, []), videoMessageWithoutThumb(505)], 0));
      await settle();

      expect(coordinator.state.sharedMedia.length).assertEqual(3);
      expectPlaceholder(coordinator.state.sharedMedia[1], true);
      expectPlaceholder(coordinator.state.sharedMedia[2], false);
      expect(coordinator.state.sharedHasMore).assertFalse();
      coordinator.destroy();
    });
  });
}
