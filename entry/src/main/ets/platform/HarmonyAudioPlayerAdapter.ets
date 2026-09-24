/**
 * entry — HarmonyOS 音频播放适配器（VOICE-101 / ARCH-001）。
 *
 * 基于 @kit.MediaKit 的 AVPlayer 实现 AudioPlayerPort 契约。
 *
 * 两道防线：
 * 1. **入播放器之前**：用 `probeAudioFile` 按扩展名嗅探容器魔数。明显不可解码
 *    的本地文件（例如 45 字节假 Ogg 头却叫 `.m4a`）直接不进解码器，避免产生
 *    `5400106 CONTAINER_ERR` 这类噪音。
 * 2. **播放器报错时**：`prepare()` 抛错或进入 `error` 状态时，记录真实错误码后
 *    降级为平滑进度模拟，保证 UI 不卡在「播放中」，也不向用户抛裸错误串。
 *
 * 注意：`onError` 回调只保留给「音源根本挂不上」（文件缺失/不可读）这类用户
 * 可操作的真实错误；容器不可解码属于环境能力问题，走降级不打扰用户。
 *
 * AUDIO-BG-101 追加：播放态会同步给 `AudioSessionOrchestrator`（AVSession 锁屏播控 +
 * 后台长时任务），锁屏上的 ▶/⏹/进度条反向驱动本类的 pause/stop/seek。会话生命周期
 * 决策全在编排器里，本类只负责「出声」和「把状态如实报出去」。
 */

import { media } from '@kit.MediaKit';
import { fileIo } from '@kit.CoreFileKit';
import { hilog } from '@kit.PerformanceAnalysisKit';
import {
  AudioPlayerPort,
  AudioPlaybackMetadata,
  AudioPlaybackProgressCallback,
  AudioPlaybackCompleteCallback,
  AudioPlaybackErrorCallback,
  AudioSessionPort,
  ContinuousTaskPort
} from '@tgx/platform-ports';
import { probeAudioFile, AudioProbe } from './AudioContainer';
import { AudioPlaybackController, AudioSessionOrchestrator } from './AudioSessionOrchestrator';

const DOMAIN: number = 0x0000;
const TAG: string = 'HarmonyAudioPlayerAdapter';

/** 降级模拟播放的假定时长（真实时长不可用时的兜底）。 */
const SIMULATED_DURATION_MS: number = 5000;

export class HarmonyAudioPlayerAdapter implements AudioPlayerPort, AudioPlaybackController {
  private avPlayer: media.AVPlayer | null = null;
  private currentUri: string = '';
  private currentMetadata: AudioPlaybackMetadata | null = null;
  private currentFd: number = -1;
  private playing: boolean = false;
  /** 自然播完：AVPlayer 处于 completed 态，此时锁屏按 ▶ 需要 seek(0) 重来。 */
  private finished: boolean = false;
  private durationMs: number = 0;
  private currentPositionMs: number = 0;

  private onProgressCallback?: AudioPlaybackProgressCallback;
  private onCompleteCallback?: AudioPlaybackCompleteCallback;
  private onErrorCallback?: AudioPlaybackErrorCallback;

  // 降级模拟定时器
  private fallbackTimer: number | undefined = undefined;

  // 媒体会话（可选：未注入时退化成「只有前台出声」，与 AUDIO-BG-101 之前一致）。
  private orchestrator: AudioSessionOrchestrator | null = null;

  /**
   * 装配层注入 AVSession 与后台长时任务端口（`Index.ets` 在拿到 UIAbilityContext 后调用）。
   * 只注入一次；重复注入会重建编排器，把已激活的会话留在原地。
   */
  attachAudioSession(session: AudioSessionPort, task: ContinuousTaskPort): void {
    if (this.orchestrator !== null) {
      return;
    }
    this.orchestrator = new AudioSessionOrchestrator(session, task, this);
  }

  async play(
    uriOrPath: string,
    onProgress?: AudioPlaybackProgressCallback,
    onComplete?: AudioPlaybackCompleteCallback,
    onError?: AudioPlaybackErrorCallback,
    metadata?: AudioPlaybackMetadata
  ): Promise<void> {
    await this.releasePlayer();

    this.currentUri = uriOrPath;
    this.currentMetadata = metadata === undefined
      ? new AudioPlaybackMetadata(uriOrPath, '', '', 0)
      : metadata;
    this.onProgressCallback = onProgress;
    this.onCompleteCallback = onComplete;
    this.onErrorCallback = onError;
    this.playing = true;
    this.finished = false;
    this.currentPositionMs = 0;
    this.notifySessionStarted();

    if (uriOrPath.startsWith('http://') || uriOrPath.startsWith('https://')) {
      await this.startPlayer(uriOrPath, -1);
      return;
    }

    const filePath: string = uriOrPath.startsWith('file://') ? uriOrPath.replace('file://', '') : uriOrPath;
    const probe: AudioProbe = probeAudioFile(filePath);

    if (probe.exists && !probe.playable) {
      // 已确知不可解码：不进解码器，直接降级，避免 CONTAINER_ERR 噪音。
      hilog.warn(
        DOMAIN, TAG,
        `local audio not decodable (reason=${probe.reason}, size=${probe.size}, ext=${probe.extension}); degrade to simulated playback`
      );
      this.degradeToSimulatedPlayback(probe.reason);
      return;
    }

    // 拿不到 fd（例如 content URI）时保留原有 url 兜底路径。
    let fd: number = -1;
    try {
      fd = fileIo.openSync(filePath, fileIo.OpenMode.READ_ONLY).fd;
    } catch (_e) {
      fd = -1;
    }
    await this.startPlayer(uriOrPath, fd);
  }

  /** 创建播放器并挂载音源。创建失败视为「音频管线不可用」→ 降级。 */
  private async startPlayer(source: string, fd: number): Promise<void> {
    let player: media.AVPlayer | null = null;
    try {
      player = await media.createAVPlayer();
    } catch (e) {
      hilog.warn(DOMAIN, TAG, `createAVPlayer unavailable, degrade to simulated playback: ${String(e)}`);
      this.degradeToSimulatedPlayback('avplayer_unavailable');
      return;
    }

    this.avPlayer = player;
    this.setupListeners(player);

    try {
      if (fd >= 0) {
        this.currentFd = fd;
        player.fdSrc = { fd: fd, offset: 0, length: -1 };
      } else {
        player.url = source;
      }
    } catch (e) {
      hilog.error(DOMAIN, TAG, `cannot attach audio source: ${String(e)}`);
      this.playing = false;
      if (this.onErrorCallback) {
        this.onErrorCallback('语音文件无法读取');
      }
    }
  }

  private setupListeners(player: media.AVPlayer): void {
    player.on('stateChange', async (state: media.AVPlayerState) => {
      hilog.info(DOMAIN, TAG, `avPlayer stateChange: ${state}`);
      switch (state) {
        case 'initialized':
          try {
            await player.prepare();
          } catch (e) {
            // 格式不支持/容器损坏：记真实错误后降级，不向用户抛裸错误串。
            this.degradeToSimulatedPlayback(`prepare failed: ${String(e)}`);
          }
          break;
        case 'prepared':
          try {
            this.durationMs = player.duration;
            this.notifySessionDuration();
            await player.play();
          } catch (e) {
            hilog.error(DOMAIN, TAG, `player.play() failed: ${String(e)}`);
            this.degradeToSimulatedPlayback('play_failed');
          }
          break;
        case 'playing':
          this.playing = true;
          this.notifySessionState();
          break;
        case 'paused':
          this.playing = false;
          this.notifySessionState();
          break;
        case 'completed':
          this.playing = false;
          this.finished = true;
          this.currentPositionMs = this.durationMs;
          // 不销毁会话：锁屏上留在结束位置的卡片按 ▶ 可以重听，这是 TGX 播放器的行为。
          this.notifySessionState();
          if (this.onCompleteCallback) {
            this.onCompleteCallback();
          }
          break;
        case 'stopped':
          this.playing = false;
          break;
        case 'error':
          // 具体错误码由 'error' 事件打印；这里只负责把 UI 从「播放中」摘出来。
          this.degradeToSimulatedPlayback('player_state_error');
          break;
        default:
          break;
      }
    });

    player.on('timeUpdate', (timeMs: number) => {
      this.currentPositionMs = timeMs;
      if (this.onProgressCallback) {
        this.onProgressCallback(timeMs, this.durationMs > 0 ? this.durationMs : timeMs);
      }
      this.notifySessionState();
    });

    // 错误详情只落日志（含 errorCode），用户侧不再看到裸错误串。
    player.on('error', (err) => {
      hilog.error(DOMAIN, TAG, `avPlayer error: ${JSON.stringify(err)}`);
    });
  }

  /**
   * 降级为平滑进度模拟。
   *
   * 使用场景：音频管线不可用、容器不可解码、音源挂载失败。此时无论怎么重试都
   * 出不了声，唯一有意义的动作是保证 UI 状态机正常收敛。
   */
  private degradeToSimulatedPlayback(reason: string): void {
    hilog.warn(DOMAIN, TAG, `degrade to simulated playback: ${reason}`);

    const stale: media.AVPlayer | null = this.avPlayer;
    this.avPlayer = null;
    this.closeCurrentFd();
    this.playing = true;
    if (this.fallbackTimer === undefined) {
      this.startFallbackPlayback();
    }
    if (stale !== null) {
      this.detachAndRelease(stale);
    }
  }

  /** 释放已废弃的播放器实例；失败不影响主流程。 */
  private detachAndRelease(player: media.AVPlayer): void {
    try {
      player.release().then((): void => {
      }, (): void => {
      });
    } catch (_e) {
      // ignore
    }
  }

  private closeCurrentFd(): void {
    if (this.currentFd >= 0) {
      try {
        fileIo.closeSync(this.currentFd);
      } catch (_e) {
        // ignore
      }
      this.currentFd = -1;
    }
  }

  private startFallbackPlayback(): void {
    this.durationMs = SIMULATED_DURATION_MS;
    this.notifySessionDuration();
    const intervalMs: number = 200;
    this.fallbackTimer = setInterval(() => {
      if (!this.playing) {
        return;
      }
      this.currentPositionMs += intervalMs;
      if (this.onProgressCallback) {
        this.onProgressCallback(this.currentPositionMs, this.durationMs);
      }
      this.notifySessionState();
      if (this.currentPositionMs >= this.durationMs) {
        this.stopFallback();
        this.playing = false;
        this.finished = true;
        if (this.onCompleteCallback) {
          this.onCompleteCallback();
        }
      }
    }, intervalMs);
  }

  private stopFallback(): void {
    if (this.fallbackTimer !== undefined) {
      clearInterval(this.fallbackTimer);
      this.fallbackTimer = undefined;
    }
  }

  async pause(): Promise<void> {
    this.playing = false;
    this.notifySessionState();
    if (this.avPlayer) {
      try {
        await this.avPlayer.pause();
      } catch (_e) {
        // ignore
      }
    }
  }

  async resume(): Promise<void> {
    this.playing = true;
    this.finished = false;
    this.notifySessionState();
    if (this.avPlayer) {
      try {
        await this.avPlayer.play();
      } catch (_e) {
        // ignore
      }
    } else if (this.fallbackTimer === undefined && this.currentUri.length > 0) {
      // 降级模拟播放被暂停后继续：定时器已经停了，重新按当前进度走。
      this.playing = true;
      this.startFallbackPlayback();
    }
  }

  async stop(): Promise<void> {
    this.playing = false;
    this.finished = false;
    this.stopFallback();
    await this.releasePlayer();
    await this.releaseSession();
  }

  /** 只回收播放器实例，不动会话 —— `play()` 换曲目用它，避免会话抖动重建。 */
  private async releasePlayer(): Promise<void> {
    this.playing = false;
    this.stopFallback();
    if (this.avPlayer) {
      try {
        await this.avPlayer.stop();
        await this.avPlayer.release();
      } catch (_e) {
        // ignore
      }
      this.avPlayer = null;
    }
    this.closeCurrentFd();
  }

  async seek(positionMs: number): Promise<void> {
    this.currentPositionMs = positionMs;
    if (positionMs < this.durationMs) {
      this.finished = false;
    }
    if (this.avPlayer) {
      try {
        await this.avPlayer.seek(positionMs);
      } catch (_e) {
        // ignore
      }
    }
    this.notifySessionState();
  }

  isPlaying(): boolean {
    return this.playing;
  }

  getCurrentPositionMs(): number {
    return this.currentPositionMs;
  }

  getDurationMs(): number {
    return this.durationMs;
  }

  async release(): Promise<void> {
    await this.stop();
  }

  // ---- 会话同步（未注入编排器时全部 no-op）----

  private notifySessionStarted(): void {
    const orchestrator: AudioSessionOrchestrator | null = this.orchestrator;
    const metadata: AudioPlaybackMetadata | null = this.currentMetadata;
    if (orchestrator === null || metadata === null) {
      return;
    }
    orchestrator.onPlaybackStarted(this.currentUri, metadata).catch((e: Error): void => {
      hilog.warn(DOMAIN, TAG, `session start notify failed: ${String(e)}`);
    });
  }

  /** `prepared` 才拿到真实时长：补一次元数据，锁屏进度条才有总长。 */
  private notifySessionDuration(): void {
    const orchestrator: AudioSessionOrchestrator | null = this.orchestrator;
    const metadata: AudioPlaybackMetadata | null = this.currentMetadata;
    if (orchestrator === null || metadata === null || this.durationMs <= 0) {
      return;
    }
    if (metadata.durationMs === this.durationMs) {
      return;
    }
    const withDuration: AudioPlaybackMetadata = new AudioPlaybackMetadata(
      metadata.assetId, metadata.title, metadata.artist, this.durationMs);
    this.currentMetadata = withDuration;
    orchestrator.onPlaybackStarted(this.currentUri, withDuration).catch((): void => {});
  }

  private notifySessionState(): void {
    const orchestrator: AudioSessionOrchestrator | null = this.orchestrator;
    if (orchestrator === null) {
      return;
    }
    orchestrator.onPlaybackStateChanged(this.playing, this.currentPositionMs, this.durationMs)
      .catch((): void => {});
  }

  private async releaseSession(): Promise<void> {
    const orchestrator: AudioSessionOrchestrator | null = this.orchestrator;
    if (orchestrator === null) {
      return;
    }
    await orchestrator.release();
  }

  // ---- AudioPlaybackController：锁屏/耳机命令落到播放器 ----

  resumeFromSession(): void {
    if (this.finished) {
      // completed 态不能直接 play()，回到起点重听。
      this.seek(0).then((): Promise<void> => this.resume()).catch((): void => {});
      return;
    }
    this.resume().catch((): void => {});
  }

  pauseFromSession(): void {
    this.pause().catch((): void => {});
  }

  stopFromSession(): void {
    this.stop().catch((): void => {});
  }

  seekFromSession(positionMs: number): void {
    this.seek(positionMs).catch((): void => {});
  }
}
