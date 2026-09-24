import {
  AudioPlayerPort,
  AudioPlaybackMetadata,
  AudioPlaybackProgressCallback,
  AudioPlaybackCompleteCallback,
  AudioPlaybackErrorCallback
} from '../AudioPlayerPort';

export class FakeAudioPlayer implements AudioPlayerPort {
  private playing: boolean = false;
  private currentUri: string = '';
  private currentMetadata: AudioPlaybackMetadata | null = null;
  private currentPosMs: number = 0;
  private totalDurationMs: number = 5000;
  private onProgressCallback?: AudioPlaybackProgressCallback;
  private onCompleteCallback?: AudioPlaybackCompleteCallback;
  private onErrorCallback?: AudioPlaybackErrorCallback;

  public async play(
    uriOrPath: string,
    onProgress?: AudioPlaybackProgressCallback,
    onComplete?: AudioPlaybackCompleteCallback,
    onError?: AudioPlaybackErrorCallback,
    metadata?: AudioPlaybackMetadata
  ): Promise<void> {
    this.currentUri = uriOrPath;
    this.currentMetadata = metadata === undefined ? null : metadata;
    this.playing = true;
    this.onProgressCallback = onProgress;
    this.onCompleteCallback = onComplete;
    this.onErrorCallback = onError;
    this.currentPosMs = 0;
    if (this.onProgressCallback) {
      this.onProgressCallback(0, this.totalDurationMs);
    }
  }

  public async pause(): Promise<void> {
    this.playing = false;
  }

  public async resume(): Promise<void> {
    this.playing = true;
  }

  public async stop(): Promise<void> {
    this.playing = false;
    this.currentPosMs = 0;
  }

  public async seek(positionMs: number): Promise<void> {
    this.currentPosMs = Math.max(0, Math.min(positionMs, this.totalDurationMs));
  }

  public isPlaying(): boolean {
    return this.playing;
  }

  public getCurrentPositionMs(): number {
    return this.currentPosMs;
  }

  public getDurationMs(): number {
    return this.totalDurationMs;
  }

  public async release(): Promise<void> {
    this.playing = false;
  }

  // Test helper methods
  public setMockDuration(durationMs: number): void {
    this.totalDurationMs = durationMs;
  }

  public simulateProgress(currentMs: number): void {
    this.currentPosMs = currentMs;
    if (this.onProgressCallback) {
      this.onProgressCallback(currentMs, this.totalDurationMs);
    }
  }

  public simulateComplete(): void {
    this.playing = false;
    this.currentPosMs = this.totalDurationMs;
    if (this.onCompleteCallback) {
      this.onCompleteCallback();
    }
  }

  public simulateError(errorMsg: string): void {
    this.playing = false;
    if (this.onErrorCallback) {
      this.onErrorCallback(errorMsg);
    }
  }

  public getCurrentUri(): string {
    return this.currentUri;
  }

  public getCurrentMetadata(): AudioPlaybackMetadata | null {
    return this.currentMetadata;
  }
}
