/**
 * Result returned upon successfully stopping a voice recording.
 */
export interface AudioRecordResult {
  filePath: string;
  durationMs: number;
  waveform: number[];
  /**
   * 产物是否为「可直接播放的合法音频容器」。
   *
   * - `true`（或省略，向后兼容）：`filePath` 指向的文件能被解码器正常打开。
   * - `false`：录音链路彻底不可用（硬件采集与占位容器均失败），此时
   *   `filePath` 指向的文件不可播放。调用方**不得**把它当作语音消息发出去——
   *   否则消息一旦落地就无法播放，用户侧表现为"点了没反应/报格式错误"。
   */
  readonly playable?: boolean;
}

/**
 * 麦克风运行时权限被拒时，`startRecord` 抛出该标识的错误。
 *
 * 放在端口层是为了让 feature 层在不依赖 entry 实现的前提下识别这一情形，
 * 从而给出「需要麦克风权限」这类可操作提示，而不是笼统的失败文案。
 */
export const ERR_MIC_PERMISSION_DENIED: string = 'voice_recording_microphone_denied';

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
