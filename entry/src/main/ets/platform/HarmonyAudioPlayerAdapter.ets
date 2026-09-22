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
 */

import { media } from '@kit.MediaKit';
import { fileIo } from '@kit.CoreFileKit';
import { hilog } from '@kit.PerformanceAnalysisKit';
import {
  AudioPlayerPort,
  AudioPlaybackProgressCallback,
  AudioPlaybackCompleteCallback,
  AudioPlaybackErrorCallback
} from '@tgx/platform-ports';
import { probeAudioFile, AudioProbe } from './AudioContainer';

const DOMAIN: number = 0x0000;
const TAG: string = 'HarmonyAudioPlayerAdapter';

/** 降级模拟播放的假定时长（真实时长不可用时的兜底）。 */
const SIMULATED_DURATION_MS: number = 5000;

export class HarmonyAudioPlayerAdapter implements AudioPlayerPort {
  private avPlayer: media.AVPlayer | null = null;
  private currentUri: string = '';
  private currentFd: number = -1;
  private playing: boolean = false;
  private durationMs: number = 0;
  private currentPositionMs: number = 0;

  private onProgressCallback?: AudioPlaybackProgressCallback;
  private onCompleteCallback?: AudioPlaybackCompleteCallback;
  private onErrorCallback?: AudioPlaybackErrorCallback;

  // 降级模拟定时器
  private fallbackTimer: number | undefined = undefined;

  async play(
    uriOrPath: string,
    onProgress?: AudioPlaybackProgressCallback,
    onComplete?: AudioPlaybackCompleteCallback,
    onError?: AudioPlaybackErrorCallback
  ): Promise<void> {
    await this.stop();

    this.currentUri = uriOrPath;
    this.onProgressCallback = onProgress;
    this.onCompleteCallback = onComplete;
    this.onErrorCallback = onError;
    this.playing = true;
    this.currentPositionMs = 0;

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
            await player.play();
          } catch (e) {
            hilog.error(DOMAIN, TAG, `player.play() failed: ${String(e)}`);
            this.degradeToSimulatedPlayback('play_failed');
          }
          break;
        case 'playing':
          this.playing = true;
          break;
        case 'paused':
          this.playing = false;
          break;
        case 'completed':
          this.playing = false;
          this.currentPositionMs = this.durationMs;
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
    const intervalMs: number = 200;
    this.fallbackTimer = setInterval(() => {
      if (!this.playing) {
        return;
      }
      this.currentPositionMs += intervalMs;
      if (this.onProgressCallback) {
        this.onProgressCallback(this.currentPositionMs, this.durationMs);
      }
      if (this.currentPositionMs >= this.durationMs) {
        this.stopFallback();
        this.playing = false;
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
    if (this.avPlayer) {
      try {
        await this.avPlayer.play();
      } catch (_e) {
        // ignore
      }
    }
  }

  async stop(): Promise<void> {
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
    if (this.avPlayer) {
      try {
        await this.avPlayer.seek(positionMs);
      } catch (_e) {
        // ignore
      }
    }
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
}
