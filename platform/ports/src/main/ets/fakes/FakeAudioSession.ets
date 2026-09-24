/**
 * platform/ports — 媒体会话 / 长时任务的测试替身（AUDIO-BG-101）。
 *
 * 记录调用次数与最近一次入参，并提供 `issue*` 让用例模拟「用户在锁屏按了 ⏸」。
 */

import { AudioPlaybackMetadata } from '../AudioPlayerPort';
import {
  AudioSessionCommandHandler,
  AudioSessionPort,
  ContinuousTaskPort
} from '../AudioSessionPort';

export class FakeAudioSession implements AudioSessionPort {
  activateCalls: number = 0;
  setMetadataCalls: number = 0;
  setPlaybackStateCalls: number = 0;
  deactivateCalls: number = 0;
  lastMetadata: AudioPlaybackMetadata | null = null;
  lastPlaying: boolean = false;
  lastPositionMs: number = -1;
  lastDurationMs: number = -1;
  /** 预置成 false 可模拟「会话服务不可用」的设备。 */
  activateResult: boolean = true;

  private activated: boolean = false;
  private handler: AudioSessionCommandHandler | null = null;

  async activate(handler: AudioSessionCommandHandler): Promise<boolean> {
    this.activateCalls += 1;
    this.handler = handler;
    this.activated = this.activateResult;
    return this.activateResult;
  }

  async setMetadata(metadata: AudioPlaybackMetadata): Promise<void> {
    this.setMetadataCalls += 1;
    this.lastMetadata = metadata;
  }

  async setPlaybackState(playing: boolean, positionMs: number, durationMs: number): Promise<void> {
    this.setPlaybackStateCalls += 1;
    this.lastPlaying = playing;
    this.lastPositionMs = positionMs;
    this.lastDurationMs = durationMs;
  }

  async deactivate(): Promise<void> {
    this.deactivateCalls += 1;
    this.activated = false;
    this.handler = null;
  }

  isActivated(): boolean {
    return this.activated;
  }

  // ---- 用例侧：模拟系统下发的播控命令 ----

  private requireHandler(): AudioSessionCommandHandler {
    if (this.handler === null) {
      throw new Error('no session handler: session not activated');
    }
    return this.handler as AudioSessionCommandHandler;
  }

  issuePlay(): void {
    this.requireHandler().onPlay();
  }

  issuePause(): void {
    this.requireHandler().onPause();
  }

  issueStop(): void {
    this.requireHandler().onStop();
  }

  issueSeek(positionMs: number): void {
    this.requireHandler().onSeek(positionMs);
  }
}

export class FakeContinuousTask implements ContinuousTaskPort {
  startCalls: number = 0;
  stopCalls: number = 0;
  startResult: boolean = true;

  private running: boolean = false;

  async startAudioPlayback(): Promise<boolean> {
    this.startCalls += 1;
    this.running = this.startResult;
    return this.startResult;
  }

  async stopAudioPlayback(): Promise<void> {
    this.stopCalls += 1;
    this.running = false;
  }

  isRunning(): boolean {
    return this.running;
  }
}
