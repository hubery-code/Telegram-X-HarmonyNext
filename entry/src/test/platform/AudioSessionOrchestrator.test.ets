/**
 * entry — 媒体会话编排器用例（AUDIO-BG-101）。
 *
 * 全部走 `FakeAudioSession` / `FakeContinuousTask`：会话服务与长时任务都是 Kit 能力，
 * 单测里拿不到，但「成对、幂等、有节流」这三条正是这套逻辑唯一的风险点，
 * 所以时钟也从外面灌进来，把 1s 节流写成确定的断言。
 */

import { describe, it, expect } from '@ohos/hypium';
import { AudioPlaybackMetadata } from '@tgx/platform-ports';
import { FakeAudioSession, FakeContinuousTask } from '@tgx/platform-ports';
import {
  audioTitleFromPath,
  AudioPlaybackController,
  AudioSessionOrchestrator
} from '../../main/ets/platform/AudioSessionOrchestrator';

class FakePlaybackController implements AudioPlaybackController {
  resumeCalls: number = 0;
  pauseCalls: number = 0;
  stopCalls: number = 0;
  seekCalls: number = 0;
  lastSeekMs: number = -1;

  resumeFromSession(): void {
    this.resumeCalls += 1;
  }

  pauseFromSession(): void {
    this.pauseCalls += 1;
  }

  stopFromSession(): void {
    this.stopCalls += 1;
  }

  seekFromSession(positionMs: number): void {
    this.seekCalls += 1;
    this.lastSeekMs = positionMs;
  }
}

/** 可变时钟：节流用例需要精确控制两次上报之间过了多少毫秒。 */
class TestClock {
  current: number = 1000;

  // 箭头字段：`orch` 拿到的是裸的 `() => number`，必须自己绑住 this。
  readonly nowMs: () => number = (): number => this.current;
}

function meta(assetId: string, title: string, durationMs: number): AudioPlaybackMetadata {
  return new AudioPlaybackMetadata(assetId, title, 'Performer', durationMs);
}

export default function audioSessionOrchestratorTest() {
  describe('AudioSessionOrchestrator', () => {

    it('first_play_activates_session_and_starts_task_once', 0, async () => {
      const session = new FakeAudioSession();
      const task = new FakeContinuousTask();
      const orch = new AudioSessionOrchestrator(session, task, new FakePlaybackController(),
        new TestClock().nowMs);

      await orch.onPlaybackStarted('/data/storage/el2/base/haps/entry/cache/12345.m4a',
        meta('12345', '', 30000));

      expect(session.activateCalls).assertEqual(1);
      expect(task.startCalls).assertEqual(1);
      expect(orch.isSessionReady()).assertTrue();
      // 标题空 → 从路径兜底出文件名（去掉扩展名），锁屏卡片不会是一片空白。
      const shown: AudioPlaybackMetadata | null = session.lastMetadata;
      expect(shown !== null).assertTrue();
      expect(shown === null ? '' : shown.title).assertEqual('12345');
      expect(shown === null ? 0 : shown.durationMs).assertEqual(30000);
    });

    it('second_play_reuses_session_and_only_swaps_metadata', 0, async () => {
      const session = new FakeAudioSession();
      const task = new FakeContinuousTask();
      const orch = new AudioSessionOrchestrator(session, task, new FakePlaybackController(),
        new TestClock().nowMs);

      await orch.onPlaybackStarted('/a/one.mp3', meta('1', 'One', 1000));
      await orch.onPlaybackStarted('/a/two.mp3', meta('2', 'Two', 2000));

      expect(session.activateCalls).assertEqual(1);
      expect(task.startCalls).assertEqual(1);
      expect(session.setMetadataCalls).assertEqual(2);
      const shown: AudioPlaybackMetadata | null = session.lastMetadata;
      expect(shown === null ? '' : shown.title).assertEqual('Two');
    });

    it('concurrent_plays_coalesce_into_single_activation', 0, async () => {
      const session = new FakeAudioSession();
      const orch = new AudioSessionOrchestrator(session, new FakeContinuousTask(),
        new FakePlaybackController(), new TestClock().nowMs);

      // 连点两行音频：activate 是异步的，不能建出两条会话。
      const concurrent: Promise<void>[] = [
        orch.onPlaybackStarted('/a/one.mp3', meta('1', 'One', 1000)),
        orch.onPlaybackStarted('/a/two.mp3', meta('2', 'Two', 2000))
      ];
      await Promise.all(concurrent);

      expect(session.activateCalls).assertEqual(1);
    });

    it('position_updates_are_throttled_to_one_second', 0, async () => {
      const session = new FakeAudioSession();
      const clock = new TestClock();
      const orch = new AudioSessionOrchestrator(session, new FakeContinuousTask(),
        new FakePlaybackController(), clock.nowMs);
      await orch.onPlaybackStarted('/a/one.mp3', meta('1', 'One', 60000));
      const afterStart: number = session.setPlaybackStateCalls;

      // AVPlayer 的 timeUpdate 约 200ms 一次，逐条转给会话会把 IPC 打满。
      clock.current += 200;
      await orch.onPlaybackStateChanged(true, 200, 60000);
      clock.current += 200;
      await orch.onPlaybackStateChanged(true, 400, 60000);
      expect(session.setPlaybackStateCalls).assertEqual(afterStart);

      clock.current += 700;
      await orch.onPlaybackStateChanged(true, 1100, 60000);
      expect(session.setPlaybackStateCalls).assertEqual(afterStart + 1);
      // 毫秒直接透传：AVSession 的 elapsedTime/duration 本身就是毫秒。
      expect(session.lastPositionMs).assertEqual(1100);
      expect(session.lastDurationMs).assertEqual(60000);
    });

    it('playback_state_flip_bypasses_throttle', 0, async () => {
      const session = new FakeAudioSession();
      const clock = new TestClock();
      const orch = new AudioSessionOrchestrator(session, new FakeContinuousTask(),
        new FakePlaybackController(), clock.nowMs);
      await orch.onPlaybackStarted('/a/one.mp3', meta('1', 'One', 60000));
      const afterStart: number = session.setPlaybackStateCalls;

      clock.current += 100;
      await orch.onPlaybackStateChanged(false, 500, 60000);

      expect(session.setPlaybackStateCalls).assertEqual(afterStart + 1);
      expect(session.lastPlaying).assertFalse();
    });

    it('duration_from_state_backfills_metadata_zero', 0, async () => {
      const session = new FakeAudioSession();
      const clock = new TestClock();
      const orch = new AudioSessionOrchestrator(session, new FakeContinuousTask(),
        new FakePlaybackController(), clock.nowMs);
      // 语音消息下载前拿不到时长，元数据先给 0，prepared 之后由状态回调补上。
      await orch.onPlaybackStarted('/a/voice.ogg', meta('7', '语音消息', 0));
      clock.current += 2000;
      await orch.onPlaybackStateChanged(true, 1000, 7000);
      expect(session.lastDurationMs).assertEqual(7000);
    });

    it('release_deactivates_session_and_stops_task', 0, async () => {
      const session = new FakeAudioSession();
      const task = new FakeContinuousTask();
      const orch = new AudioSessionOrchestrator(session, task, new FakePlaybackController(),
        new TestClock().nowMs);
      await orch.onPlaybackStarted('/a/one.mp3', meta('1', 'One', 1000));

      await orch.release();

      expect(session.deactivateCalls).assertEqual(1);
      expect(task.stopCalls).assertEqual(1);
      expect(orch.isSessionReady()).assertFalse();
      // 会话与任务成对释放后不能再上报进度，否则幽灵卡片会被重新点亮。
      await orch.onPlaybackStateChanged(true, 100, 1000);
      expect(session.setPlaybackStateCalls).assertEqual(0);
    });

    it('release_is_noop_when_session_never_started', 0, async () => {
      const session = new FakeAudioSession();
      const task = new FakeContinuousTask();
      const orch = new AudioSessionOrchestrator(session, task, new FakePlaybackController(),
        new TestClock().nowMs);

      await orch.release();

      expect(session.deactivateCalls).assertEqual(0);
      expect(task.stopCalls).assertEqual(0);
    });

    it('session_failure_keeps_playing_without_task_or_state', 0, async () => {
      const session = new FakeAudioSession();
      session.activateResult = false;
      const task = new FakeContinuousTask();
      const orch = new AudioSessionOrchestrator(session, task, new FakePlaybackController(),
        new TestClock().nowMs);

      await orch.onPlaybackStarted('/a/one.mp3', meta('1', 'One', 1000));
      await orch.onPlaybackStateChanged(true, 500, 1000);

      // 会话服务不可用（模拟器/低端机）时只丢锁屏控件，不申请长时任务也不报错。
      expect(session.setMetadataCalls).assertEqual(0);
      expect(task.startCalls).assertEqual(0);
      expect(session.setPlaybackStateCalls).assertEqual(0);
      expect(orch.isSessionReady()).assertFalse();
    });

    it('session_commands_route_to_controller', 0, async () => {
      const session = new FakeAudioSession();
      const controller = new FakePlaybackController();
      const orch = new AudioSessionOrchestrator(session, new FakeContinuousTask(), controller,
        new TestClock().nowMs);
      await orch.onPlaybackStarted('/a/one.mp3', meta('1', 'One', 1000));

      session.issuePause();
      session.issueSeek(15000);
      session.issuePlay();
      session.issueStop();

      expect(controller.pauseCalls).assertEqual(1);
      expect(controller.seekCalls).assertEqual(1);
      expect(controller.lastSeekMs).assertEqual(15000);
      expect(controller.resumeCalls).assertEqual(1);
      expect(controller.stopCalls).assertEqual(1);
    });

    it('play_command_is_dropped_without_active_asset', 0, async () => {
      const session = new FakeAudioSession();
      const controller = new FakePlaybackController();
      const orch = new AudioSessionOrchestrator(session, new FakeContinuousTask(), controller,
        new TestClock().nowMs);

      // 会话已经活起来但手上没内容（系统自己唤醒卡片后按 ▶）：不能把空 asset 播出去。
      await session.activate(orch);
      session.issuePlay();
      expect(controller.resumeCalls).assertEqual(0);

      await orch.onPlaybackStarted('/a/one.mp3', meta('1', 'One', 1000));
      session.issuePlay();
      expect(controller.resumeCalls).assertEqual(1);
    });

    it('title_falls_back_to_basename_without_stripping_dots_badly', 0, () => {
      expect(audioTitleFromPath('file:///data/cache/9988.mp3')).assertEqual('9988');
      expect(audioTitleFromPath('/data/cache/9988')).assertEqual('9988');
      expect(audioTitleFromPath('audio.m4a')).assertEqual('audio');
      // 点开头的文件名（隐藏文件）不能被削成空串。
      expect(audioTitleFromPath('/data/.hidden')).assertEqual('.hidden');
    });
  });
}
