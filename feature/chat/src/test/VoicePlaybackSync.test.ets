/**
 * feature/chat — 音频与语音外部播控双向同步单测（AUDIO-BG-102）。
 */

import { describe, it, expect } from '@ohos/hypium';
import { AppError, Result } from '@tgx/core-common';
import { AccountScope, buildAccountDirectories, createDescriptor, AccountDirectoryLayout } from '@tgx/core-account';
import { FakeAppFiles, FakeAudioPlayer } from '@tgx/platform-ports';
import {
  TdNativeBridgeLike,
  TdNativeBridgeMetrics,
  TdNativeEventSink
} from '@tgx/td-gateway';
import { ChatHeaderCache } from '@tgx/core-domain';
import { ChatCoordinator } from '../main/ets/coordinator/ChatCoordinator';
import { ChatUiState } from '../main/ets/contract/ChatUiState';
import { PlayVoiceNote, SendGif, OpenStickerSet } from '../main/ets/contract/ChatIntent';
import { GifItem } from '../main/ets/model/GifItem';

class VoiceTestBridge implements TdNativeBridgeLike {
  version: string = '1.8.67-test';
  sent: string[] = [];
  getVersion(): string { return this.version; }
  createClient(): number { return 1; }
  send(_clientId: number, requestUtf8: string): void { this.sent.push(requestUtf8); }
  execute(_requestUtf8: string): string | null { return '{"@type":"ok"}'; }
  subscribeUpdates(_sink: TdNativeEventSink): number { return 1; }
  unsubscribe(_subscriptionId: number): void {}
  getMetrics(): TdNativeBridgeMetrics {
    return {
      queueSize: 0,
      overflowWaitCount: 0,
      droppedCount: 0,
      eventsForwarded: 0,
      subscriptions: 0,
      dispatcherRunning: true
    };
  }
}

function createScope(bridge: VoiceTestBridge, name: string): AccountScope {
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

function settle(): Promise<void> {
  return new Promise<void>((resolve: () => void): void => {
    setTimeout(resolve, 30);
  });
}

export default function voicePlaybackSyncTest(): void {
  describe('VoicePlaybackSync', () => {
    it('externalPauseAndResume_syncsPlayingStateTwoWay', 0, async (): Promise<void> => {
      const bridge: VoiceTestBridge = new VoiceTestBridge();
      const scope: AccountScope = createScope(bridge, 'test_voice_sync');
      const fakePlayer: FakeAudioPlayer = new FakeAudioPlayer();
      const coordinator: ChatCoordinator = new ChatCoordinator(
        scope, 1001, 'Test Chat', undefined, undefined, undefined, {
          audioPlayerPort: fakePlayer
        }
      );

      let currentState: ChatUiState = ChatUiState.initial();
      coordinator.subscribe((s: ChatUiState): void => {
        currentState = s;
      });

      // 触发播放语音 999
      coordinator.dispatch(new PlayVoiceNote(999, 1234, '/sandbox/voice-999.ogg'));
      await settle();

      expect(currentState.playingVoiceMessageId).assertEqual(999);
      expect(fakePlayer.isPlaying()).assertTrue();

      // 外部播控暂停（模拟 AVSession / 锁屏 / 耳机按键）
      await fakePlayer.pause();
      await settle();

      expect(currentState.playingVoiceMessageId).assertNull();
      expect(fakePlayer.isPlaying()).assertFalse();

      // 外部播控继续播放
      await fakePlayer.resume();
      await settle();

      expect(currentState.playingVoiceMessageId).assertEqual(999);
      expect(fakePlayer.isPlaying()).assertTrue();

      coordinator.destroy();
    });

    it('sendGif_withRealFileId_sendsInputMessageAnimation', 0, async (): Promise<void> => {
      const bridge: VoiceTestBridge = new VoiceTestBridge();
      const scope: AccountScope = createScope(bridge, 'test_send_animation');
      const coordinator: ChatCoordinator = new ChatCoordinator(
        scope, 1001, 'Test Chat'
      );

      const gif: GifItem = {
        id: 'gif-real-1',
        title: 'Dancing Dog',
        tag: '#funny',
        category: '😂 Funny',
        fileId: 8888,
        width: 320,
        height: 240,
        duration: 3,
        previewEmoji: '🐶'
      };

      coordinator.dispatch(new SendGif(gif));
      await settle();

      expect(bridge.sent.length).assertEqual(1);
      const req: Record<string, Object> = JSON.parse(bridge.sent[0]) as Record<string, Object>;
      expect(req['@type']).assertEqual('sendMessage');
      const content: Record<string, Object> = req['input_message_content'] as Record<string, Object>;
      expect(content['@type']).assertEqual('inputMessageAnimation');
      const anim: Record<string, Object> = content['animation'] as Record<string, Object>;
      const file: Record<string, Object> = anim['animation'] as Record<string, Object>;
      expect(file['id']).assertEqual(8888);

      coordinator.destroy();
    });

    it('chatHeaderKeepAlive_restoresCachedMemberCountAndOnlineCountOnReentry', 0, async (): Promise<void> => {
      const bridge: VoiceTestBridge = new VoiceTestBridge();
      const scope: AccountScope = createScope(bridge, 'test_chat_header_keepalive');

      ChatHeaderCache.put(scope.accountKey, 2001, {
        memberCount: 888,
        onlineMemberCount: 66,
        isChannel: false,
        chatKind: 'group',
        supergroupId: 501,
        basicGroupId: 0
      });

      const coordinator: ChatCoordinator = new ChatCoordinator(
        scope, 2001, 'Group Test'
      );
      coordinator.start();
      await settle();

      expect(coordinator.state.headerSubtitle.includes('888')).assertTrue();
      expect(coordinator.state.headerSubtitle.includes('66')).assertTrue();

      coordinator.destroy();
    });

    it('unknownStickerSet_doesNotRetryWithForceServer', 0, async (): Promise<void> => {
      const bridge: VoiceTestBridge = new VoiceTestBridge();
      const scope: AccountScope = createScope(bridge, 'test_unknown_sticker_set');
      const coordinator: ChatCoordinator = new ChatCoordinator(
        scope, 1001, 'Test Chat'
      );
      coordinator.start();
      await settle();

      coordinator.dispatch(new OpenStickerSet('completely_unknown_pack_123'));
      await settle();

      const firstReqs: string[] = bridge.sent.filter((s: string): boolean => s.includes('searchStickerSet'));
      expect(firstReqs.length).assertEqual(1);

      coordinator.destroy();
    });
  });
}
