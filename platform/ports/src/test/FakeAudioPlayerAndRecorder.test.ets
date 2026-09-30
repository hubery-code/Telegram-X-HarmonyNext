/**
 * platform/ports — FakeAudioPlayer 与 FakeAudioRecorder 单元测试（ARCH-001）。
 */

import { describe, it, expect } from '@ohos/hypium';
import { FakeAudioPlayer } from '../main/ets/fakes/FakeAudioPlayer';
import { FakeAudioRecorder } from '../main/ets/fakes/FakeAudioRecorder';

export default function fakeAudioPlayerAndRecorderTest() {
  describe('FakeAudioPlayerAndRecorderTest', () => {
    it('FakeAudioPlayer_playbackLifecycle_succeeds', 0, async () => {
      const player = new FakeAudioPlayer();
      player.setMockDuration(6000);
      expect(player.isPlaying()).assertFalse();
      expect(player.getDurationMs()).assertEqual(6000);
      expect(player.getCurrentPositionMs()).assertEqual(0);

      let lastProgressPos = -1;
      let completed = false;
      let stateChanges: boolean[] = [];

      await player.play(
        '/data/storage/el2/base/cache/voice.m4a',
        (pos, dur) => {
          lastProgressPos = pos;
        },
        () => {
          completed = true;
        },
        undefined,
        undefined,
        (isPlaying: boolean) => {
          stateChanges.push(isPlaying);
        }
      );

      expect(player.isPlaying()).assertTrue();
      expect(player.getCurrentUri()).assertEqual('/data/storage/el2/base/cache/voice.m4a');
      expect(lastProgressPos).assertEqual(0);
      expect(stateChanges.length).assertEqual(1);
      expect(stateChanges[0]).assertTrue();

      player.simulateProgress(2500);
      expect(player.getCurrentPositionMs()).assertEqual(2500);
      expect(lastProgressPos).assertEqual(2500);

      // AUDIO-PROGRESS-101: seek 应当立即回调 onProgressCallback 驱动内部进度
      await player.seek(4000);
      expect(player.getCurrentPositionMs()).assertEqual(4000);
      expect(lastProgressPos).assertEqual(4000);

      await player.pause();
      expect(player.isPlaying()).assertFalse();
      expect(stateChanges.length).assertEqual(2);
      expect(stateChanges[1]).assertFalse();

      await player.resume();
      expect(player.isPlaying()).assertTrue();
      expect(stateChanges.length).assertEqual(3);
      expect(stateChanges[2]).assertTrue();
      expect(lastProgressPos).assertEqual(4000);

      player.simulateComplete();
      expect(player.isPlaying()).assertFalse();
      expect(completed).assertTrue();
      expect(player.getCurrentPositionMs()).assertEqual(6000);
      expect(lastProgressPos).assertEqual(6000);
      expect(stateChanges.length).assertEqual(4);
      expect(stateChanges[3]).assertFalse();

      await player.stop();
      expect(player.isPlaying()).assertFalse();
      expect(player.getCurrentPositionMs()).assertEqual(0);
    });

    it('FakeAudioRecorder_recordLifecycle_succeeds', 0, async () => {
      const recorder = new FakeAudioRecorder();
      recorder.setMockDurationMs(4500);
      recorder.setMockWaveform([5, 10, 20, 30, 15]);

      expect(recorder.isRecording()).assertFalse();
      expect(recorder.getRecordDurationMs()).assertEqual(0);

      await recorder.startRecord('/data/storage/el2/base/cache/recorded_voice.m4a');
      expect(recorder.isRecording()).assertTrue();
      expect(recorder.getCurrentPath()).assertEqual('/data/storage/el2/base/cache/recorded_voice.m4a');

      const result = await recorder.stopRecord();
      expect(recorder.isRecording()).assertFalse();
      expect(result.filePath).assertEqual('/data/storage/el2/base/cache/recorded_voice.m4a');
      expect(result.durationMs).assertEqual(4500);
      expect(result.waveform.length).assertEqual(5);

      // Cancel test
      await recorder.startRecord('/data/storage/el2/base/cache/cancel_voice.m4a');
      expect(recorder.isRecording()).assertTrue();
      await recorder.cancelRecord();
      expect(recorder.isRecording()).assertFalse();
    });
  });
}
