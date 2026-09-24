/**
 * entry — HarmonyOS AVSession 适配（AUDIO-BG-101）。
 *
 * 只做「会话」这一件事：建会话、挂播控命令、写元数据与播放态、销毁。
 * 生命周期决策（何时建、何时收、进度上报频率）在 `AudioSessionOrchestrator`，这里不重复。
 *
 * 命令可用性由「注册了哪些监听」决定（AVSession 文档：注册该监听即表示应用支持该指令），
 * 所以这里注册的四种就是锁屏卡片上会出现的按钮：▶/⏸、⏹、进度条拖动。
 * 没有队列概念（一条一条点播，不支持上一首/下一首），故不注册 playNext/playPrevious，
 * 锁屏上也就不会画出按不动的跳曲按钮。
 */

import { avSession } from '@kit.AVSessionKit';
import { common } from '@kit.AbilityKit';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { AudioPlaybackMetadata } from '@tgx/platform-ports';
import {
  AudioSessionCommandHandler,
  AudioSessionPort
} from '@tgx/platform-ports';

const DOMAIN: number = 0x0000;
const TAG: string = 'HarmonyAVSessionAdapter';

export class HarmonyAVSessionAdapter implements AudioSessionPort {
  private context: common.UIAbilityContext | null = null;
  private session: avSession.AVSession | null = null;

  /** 与 `HarmonyAudioRecorderAdapter` 同法：页面侧拿到 UIAbilityContext 后注入。 */
  setContext(context: common.UIAbilityContext): void {
    this.context = context;
  }

  async activate(handler: AudioSessionCommandHandler): Promise<boolean> {
    if (this.session !== null) {
      return true;
    }
    const ctx: common.UIAbilityContext | null = this.context;
    if (ctx === null) {
      hilog.warn(DOMAIN, TAG, 'activate skipped: no UIAbilityContext injected');
      return false;
    }
    try {
      const session: avSession.AVSession = await avSession.createAVSession(ctx, 'tgx_audio', 'audio');
      session.on('play', (): void => {
        handler.onPlay();
      });
      session.on('pause', (): void => {
        handler.onPause();
      });
      session.on('stop', (): void => {
        handler.onStop();
      });
      session.on('seek', (timeMs: number): void => {
        handler.onSeek(timeMs);
      });
      await session.activate();
      this.session = session;
      hilog.info(DOMAIN, TAG, `AVSession activated: sessionId=${session.sessionId}`);
      return true;
    } catch (e) {
      // 会话服务不可用（模拟器/低端设备/系统限制）不能影响出声，只丢锁屏控件。
      hilog.warn(DOMAIN, TAG, `createAVSession failed, no lock-screen controls: ${String(e)}`);
      return false;
    }
  }

  async setMetadata(metadata: AudioPlaybackMetadata): Promise<void> {
    const session: avSession.AVSession | null = this.session;
    if (session === null) {
      return;
    }
    const avMeta: avSession.AVMetadata = {
      assetId: metadata.assetId,
      title: metadata.title,
      duration: metadata.durationMs
    };
    if (metadata.artist.length > 0) {
      avMeta.artist = metadata.artist;
    }
    try {
      await session.setAVMetadata(avMeta);
    } catch (e) {
      hilog.warn(DOMAIN, TAG, `setAVMetadata failed: ${String(e)}`);
    }
  }

  async setPlaybackState(playing: boolean, positionMs: number, durationMs: number): Promise<void> {
    const session: avSession.AVSession | null = this.session;
    if (session === null) {
      return;
    }
    const state: avSession.AVPlaybackState = {
      state: playing ? avSession.PlaybackState.PLAYBACK_STATE_PLAY : avSession.PlaybackState.PLAYBACK_STATE_PAUSE,
      position: {
        elapsedTime: positionMs,
        // updateTime 是「记录 elapsedTime 时的系统时间」，系统据此外推进度条。
        updateTime: Date.now()
      }
    };
    if (durationMs > 0) {
      state.duration = durationMs;
    }
    try {
      await session.setAVPlaybackState(state);
    } catch (e) {
      hilog.warn(DOMAIN, TAG, `setAVPlaybackState failed: ${String(e)}`);
    }
  }

  async deactivate(): Promise<void> {
    const session: avSession.AVSession | null = this.session;
    this.session = null;
    if (session === null) {
      return;
    }
    try {
      await session.deactivate();
    } catch (e) {
      hilog.warn(DOMAIN, TAG, `deactivate failed: ${String(e)}`);
    }
    try {
      await session.destroy();
    } catch (e) {
      hilog.warn(DOMAIN, TAG, `destroy failed: ${String(e)}`);
    }
    hilog.info(DOMAIN, TAG, 'AVSession deactivated and destroyed');
  }

  isActivated(): boolean {
    return this.session !== null;
  }
}
