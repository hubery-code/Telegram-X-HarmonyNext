import { AudioRecorderPort, AudioRecordResult } from '../AudioRecorderPort';

export class FakeAudioRecorder implements AudioRecorderPort {
  private recording: boolean = false;
  private currentPath: string = '';
  private startTime: number = 0;
  private mockDurationMs: number = 3000;
  private mockWaveform: number[] = [2, 8, 14, 22, 30, 26, 18, 12, 6, 10, 16, 24, 28, 20, 15, 9, 4, 8, 16, 25, 31, 23, 17, 11, 7, 13, 19, 27];

  public async startRecord(outputPath: string): Promise<void> {
    this.recording = true;
    this.currentPath = outputPath;
    this.startTime = Date.now();
  }

  public async stopRecord(): Promise<AudioRecordResult> {
    this.recording = false;
    const duration = this.mockDurationMs > 0 ? this.mockDurationMs : Math.max(1000, Date.now() - this.startTime);
    return {
      filePath: this.currentPath,
      durationMs: duration,
      waveform: this.mockWaveform
    };
  }

  public async cancelRecord(): Promise<void> {
    this.recording = false;
    this.currentPath = '';
  }

  public isRecording(): boolean {
    return this.recording;
  }

  public getRecordDurationMs(): number {
    if (!this.recording) {
      return 0;
    }
    return Date.now() - this.startTime;
  }

  // Test helpers
  public setMockDurationMs(durationMs: number): void {
    this.mockDurationMs = durationMs;
  }

  public setMockWaveform(waveform: number[]): void {
    this.mockWaveform = waveform;
  }

  public getCurrentPath(): string {
    return this.currentPath;
  }
}
