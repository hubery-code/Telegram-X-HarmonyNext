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

export interface AudioPlayerPort {
  /**
   * Start or resume playing the audio file at the specified path/URI.
   */
  play(
    uriOrPath: string,
    onProgress?: AudioPlaybackProgressCallback,
    onComplete?: AudioPlaybackCompleteCallback,
    onError?: AudioPlaybackErrorCallback
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
