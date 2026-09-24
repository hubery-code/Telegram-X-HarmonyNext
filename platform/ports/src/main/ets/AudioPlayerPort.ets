/**
 * Audio playback callback for progress updates.
 * @param currentMs Current playback position in milliseconds.
 * @param totalMs Total audio duration in milliseconds.
 */
export type AudioPlaybackProgressCallback = (currentMs: number, totalMs: number) => void;

/**
 * Audio playback callback when playback finishes.
 */
export type AudioPlaybackCompleteCallback = () => void;

/**
 * Audio playback callback when playback errors.
 */
export type AudioPlaybackErrorCallback = (errorMsg: string) => void;

/**
 * 一条音频的展示元数据（AUDIO-BG-101）。
 *
 * 锁屏/控制中心的播控卡片只有这几个字段可写，语义按 TGX 的 `MediaPlayer` 通知来：
 * `title` 是主标题（音乐曲名，没有曲名时是文件名去扩展名），`artist` 是副标题
 * （表演者，或语音消息的发送者/会话名），`assetId` 用来区分「换了一首歌」还是
 * 「同一首继续播」。
 */
export class AudioPlaybackMetadata {
  readonly assetId: string;
  readonly title: string;
  readonly artist: string;
  readonly durationMs: number;

  constructor(assetId: string, title: string, artist: string, durationMs: number) {
    this.assetId = assetId;
    this.title = title;
    this.artist = artist;
    this.durationMs = durationMs;
  }
}

export interface AudioPlayerPort {
  /**
   * Start or resume playing the audio file at the specified path/URI.
   *
   * `metadata` 可选：不传时装配层按文件名兜底出标题（见 `metadataForAudioSource`）。
   */
  play(
    uriOrPath: string,
    onProgress?: AudioPlaybackProgressCallback,
    onComplete?: AudioPlaybackCompleteCallback,
    onError?: AudioPlaybackErrorCallback,
    metadata?: AudioPlaybackMetadata
  ): Promise<void>;

  /**
   * Pause the currently playing audio.
   */
  pause(): Promise<void>;

  /**
   * Resume playback from the paused state.
   */
  resume(): Promise<void>;

  /**
   * Stop playback and reset player state.
   */
  stop(): Promise<void>;

  /**
   * Seek to position in milliseconds.
   */
  seek(positionMs: number): Promise<void>;

  /**
   * Returns whether audio is currently playing.
   */
  isPlaying(): boolean;

  /**
   * Get current playback position in milliseconds.
   */
  getCurrentPositionMs(): number;

  /**
   * Get duration in milliseconds.
   */
  getDurationMs(): number;

  /**
   * Release player resources.
   */
  release(): Promise<void>;
}
