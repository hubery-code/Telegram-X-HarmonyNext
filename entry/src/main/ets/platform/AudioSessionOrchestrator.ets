/**
 * entry — 媒体会话编排器（AUDIO-BG-101）。
 *
 * Kit-free：只依赖 `@tgx/platform-ports` 的 `AudioSessionPort` / `ContinuousTaskPort`，
 * 所以「什么时候建会话、什么时候申请长时任务、进度上报要多少频率」这套状态机可以在
 * 单测里跑，不需要真起 AVPlayer 或系统会话服务。
 *
 * 这套状态机真正要守住的三件事：
 * 1. **成对**：会话和长时任务同生同灭。HarmonyOS 自 API 20 起，`AUDIO_PLAYBACK` 长时任务
 *    不接 AVSession 会被系统回收，所以两者必须一起申请；页面 destroy 时若只释放其一，
 *    锁屏会留下点不动的幽灵卡片（或进程被冻结导致退后台断音）。
 * 2. **幂等**：连点两行音频、暂停后续播、`stop()` 之后再 `release()`，都不能重复建会话、
 *    重复申请任务，也不能把已释放的会话又点亮。
 * 3. **有节流的进度上报**：AVPlayer 每 ~200ms 回调一次 `timeUpdate`，逐条转给会话会把主线程
 *    和 IPC 打满。播放态变化立刻上报，位置按 1s 节流。
 */

import { AudioPlaybackMetadata } from '@tgx/platform-ports';
import {
  AudioSessionCommandHandler,
  AudioSessionPort,
  ContinuousTaskPort
} from '@tgx/platform-ports';

/**
 * 按文件名兜底出标题（SHARED-AUDIO 的 `audioTitleOf` 走的是 TDLib 里的元数据，
 * 而会话可能在只有本地路径时被点亮：下载完成后直接播放、聊天里的语音消息等）。
 * 例：`/data/.../cache/12345.m4a` → `12345`；无扩展名或点是首字符时原样给回。
 */
export function audioTitleFromPath(uriOrPath: string): string {
  const path: string = uriOrPath.startsWith('file://') ? uriOrPath.substring(7) : uriOrPath;
  const slash: number = path.lastIndexOf('/');
  const name: string = slash >= 0 ? path.substring(slash + 1) : path;
  const dot: number = name.lastIndexOf('.');
  return dot > 0 ? name.substring(0, dot) : name;
}

/** 播放器侧被会话驱动的四个动作；由 `HarmonyAudioPlayerAdapter` 实现。 */
export interface AudioPlaybackController {
  resumeFromSession(): void;

  pauseFromSession(): void;

  stopFromSession(): void;

  seekFromSession(positionMs: number): void;
}

/** 两次位置上报的最小间隔（毫秒）。 */
const POSITION_PUSH_INTERVAL_MS: number = 1000;

export class AudioSessionOrchestrator implements AudioSessionCommandHandler {
  private readonly session: AudioSessionPort;
  private readonly task: ContinuousTaskPort;
  private readonly controller: AudioPlaybackController;
  private readonly nowMs: () => number;

  /** 正在放的内容；会话命令（如锁屏 ▶）需要知道当前有没有内容可放。 */
  private activeAssetId: string = '';
  private sessionReady: boolean = false;
  /** 合并并发的 activate（activate 是异步的，两次连点不能建两条会话）。 */
  private activating: Promise<boolean> | null = null;
  private lastPlayingPushed: boolean = false;
  private lastPushAtMs: number = 0;
  private lastDurationMs: number = 0;

  constructor(
    session: AudioSessionPort,
    task: ContinuousTaskPort,
    controller: AudioPlaybackController,
    nowMs?: () => number
  ) {
    this.session = session;
    this.task = task;
    this.controller = controller;
    this.nowMs = nowMs ?? ((): number => Date.now());
  }

  /**
   * 播放已经开始（或换了一首）。负责把会话点亮并同步元数据。
   *
   * @param uriOrPath 音源路径，用于标题兜底。
   */
  onPlaybackStarted(uriOrPath: string, metadata: AudioPlaybackMetadata): Promise<void> {
    this.activeAssetId = metadata.assetId;
    this.lastDurationMs = metadata.durationMs;
    return this.ensureSession().then((ready: boolean): Promise<void> => {
      if (!ready) {
        return Promise.resolve();
      }
      const title: string = metadata.title.length > 0 ? metadata.title : audioTitleFromPath(uriOrPath);
      const shown: AudioPlaybackMetadata =
        new AudioPlaybackMetadata(metadata.assetId, title, metadata.artist, metadata.durationMs);
      this.lastPlayingPushed = true;
      this.lastPushAtMs = this.nowMs();
      return this.session.setMetadata(shown).then((): void => {
        // 长时任务在会话可用后才申请：没有会话的任务会被系统当场回收，白拿权限。
        if (!this.task.isRunning()) {
          this.task.startAudioPlayback().catch((): void => {});
        }
      });
    });
  }

  /** 播放态变化（含进度）。 */
  onPlaybackStateChanged(playing: boolean, positionMs: number, durationMs: number): Promise<void> {
    if (!this.sessionReady || this.activeAssetId.length === 0) {
      return Promise.resolve();
    }
    if (durationMs > 0) {
      this.lastDurationMs = durationMs;
    }
    const now: number = this.nowMs();
    const forced: boolean = playing !== this.lastPlayingPushed;
    if (!forced && now - this.lastPushAtMs < POSITION_PUSH_INTERVAL_MS) {
      return Promise.resolve();
    }
    this.lastPlayingPushed = playing;
    this.lastPushAtMs = now;
    // AVSession 的 elapsedTime/duration 一律按毫秒计（见 @ohos.multimedia.avsession 的
    // PlaybackPosition / AVMetadata.duration 注释），不要自作主张换算。
    return this.session.setPlaybackState(playing, positionMs, this.lastDurationMs);
  }

  /** 播放结束、被停掉或页面销毁：会话与长时任务一起收。 */
  release(): Promise<void> {
    const wasReady: boolean = this.sessionReady;
    this.activeAssetId = '';
    this.sessionReady = false;
    this.activating = null;
    this.lastPlayingPushed = false;
    this.lastPushAtMs = 0;
    if (!wasReady) {
      return Promise.resolve();
    }
    return this.session.deactivate().then((): Promise<void> => this.task.stopAudioPlayback());
  }

  isSessionReady(): boolean {
    return this.sessionReady;
  }

  private ensureSession(): Promise<boolean> {
    if (this.sessionReady) {
      return Promise.resolve(true);
    }
    if (this.activating !== null) {
      return this.activating;
    }
    const pending: Promise<boolean> = this.session.activate(this).then((ok: boolean): boolean => {
      this.sessionReady = ok;
      return ok;
    }).catch((): boolean => false);
    this.activating = pending;
    return pending;
  }

  // ---- AudioSessionCommandHandler：锁屏/耳机/控制中心下发的命令 ----

  onPlay(): void {
    if (this.activeAssetId.length === 0) {
      return;
    }
    this.controller.resumeFromSession();
  }

  onPause(): void {
    this.controller.pauseFromSession();
  }

  onStop(): void {
    this.controller.stopFromSession();
  }

  onSeek(positionMs: number): void {
    this.controller.seekFromSession(positionMs);
  }
}
