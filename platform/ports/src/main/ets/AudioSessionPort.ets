/**
 * platform/ports — 媒体会话与后台长时任务契约（AUDIO-BG-101）。
 *
 * 为什么需要它：HarmonyOS 自 API 20 起，`AUDIO_PLAYBACK` 长时任务若**不接 AVSession**，
 * 系统会直接回收该任务（错误码 `SYSTEM_CANCEL_AUDIO_PLAYBACK_NOT_USE_AVSESSION`），
 * 退到后台/锁屏就断音。所以「后台继续播」是一个动作的两半：AVSession（锁屏与控制中心的
 * 播控卡片 + 系统通知）+ 长时任务（进程保活），两者必须同生同灭。
 *
 * 这里只放契约与纯类型：编排逻辑在 `entry/platform/AudioSessionOrchestrator`，
 * Kit 调用在 `entry/platform/Harmony*Adapter`，因此本文件 Kit-free、可单测。
 */

import { AudioPlaybackMetadata } from './AudioPlayerPort';

/**
 * 会话侧命令回调：用户在锁屏/耳机/控制中心按下的键，由会话转给播放器。
 * 播放器实现在 entry 侧，会话实现只负责把系统命令递出来，不反向依赖播放。
 */
export interface AudioSessionCommandHandler {
  onPlay(): void;

  onPause(): void;

  onStop(): void;

  onSeek(positionMs: number): void;
}

/** AVSession 的抽象：一条「正在播放」的媒体会话。 */
export interface AudioSessionPort {
  /**
   * 建立并激活会话。实现应幂等：已激活时直接返回成功。
   *
   * @returns 是否可用。失败时调用方继续本地播放，只是没有锁屏控件 —— 不能因为
   *          会话建不起来就不出声（模拟器/低端设备上会话服务可能不可用）。
   */
  activate(handler: AudioSessionCommandHandler): Promise<boolean>;

  /** 切换曲目（换标题/表演者/时长），不重新建会话。 */
  setMetadata(metadata: AudioPlaybackMetadata): Promise<void>;

  /** 上报播放态与进度，驱动锁屏上的进度条与 ▶/⏸ 图标。 */
  setPlaybackState(playing: boolean, positionMs: number, durationMs: number): Promise<void>;

  /** 停用并销毁会话；必须与 `activate` 成对，否则退出页面后锁屏会留下幽灵卡片。 */
  deactivate(): Promise<void>;

  isActivated(): boolean;
}

/** 后台长时任务（continuous task）抽象。 */
export interface ContinuousTaskPort {
  /** 申请音频播放长时任务；实现应幂等。@returns 是否申请成功。 */
  startAudioPlayback(): Promise<boolean>;

  /** 释放长时任务；未申请过时为 no-op。 */
  stopAudioPlayback(): Promise<void>;

  isRunning(): boolean;
}
