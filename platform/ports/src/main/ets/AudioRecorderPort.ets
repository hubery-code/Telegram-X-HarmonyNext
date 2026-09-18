/**
 * Result returned upon successfully stopping a voice recording.
 */
export interface AudioRecordResult {
  filePath: string;
  durationMs: number;
  waveform: number[];
}

export interface AudioRecorderPort {
  /**
   * Start recording audio to the specified output file path.
   */
  startRecord(outputPath: string): Promise<void>;

  /**
   * Stop recording and return the result with file path, duration, and sampled waveform.
   */
  stopRecord(): Promise<AudioRecordResult>;

  /**
   * Cancel recording and discard the recorded file.
   */
  cancelRecord(): Promise<void>;

  /**
   * Returns whether recording is currently in progress.
   */
  isRecording(): boolean;

  /**
   * Get current recording duration in milliseconds.
   */
  getRecordDurationMs(): number;
}
