/**
 * entry — HarmonyOS 音频后台长时任务适配（AUDIO-BG-101）。
 *
 * 为什么必须和 AVSession 一起上：官方文档明确 `MODE_AUDIO_PLAYBACK` 若不接 AVSession，
 * 系统会回收该长时任务（`SYSTEM_CANCEL_AUDIO_PLAYBACK_NOT_USE_AVSESSION`），
 * 于是「退后台继续播」又回到断音。所以两者成对申请：通知栏那张播控卡片由 AVSession 负责，
 * 长时任务只负责保活。
 */

import { backgroundTaskManager } from '@kit.BackgroundTasksKit';
import { common, wantAgent } from '@kit.AbilityKit';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { ContinuousTaskPort } from '@tgx/platform-ports';

const DOMAIN: number = 0x0000;
const TAG: string = 'HarmonyContinuousTaskAdapter';

export class HarmonyContinuousTaskAdapter implements ContinuousTaskPort {
  private context: common.UIAbilityContext | null = null;
  private taskId: number = -1;

  setContext(context: common.UIAbilityContext): void {
    this.context = context;
  }

  async startAudioPlayback(): Promise<boolean> {
    if (this.taskId >= 0) {
      return true;
    }
    const ctx: common.UIAbilityContext | null = this.context;
    if (ctx === null) {
      hilog.warn(DOMAIN, TAG, 'start skipped: no UIAbilityContext injected');
      return false;
    }
    try {
      const info: wantAgent.WantAgentInfo = {
        wants: [{
          bundleName: ctx.abilityInfo.bundleName,
          abilityName: ctx.abilityInfo.name
        }],
        operationType: wantAgent.OperationType.START_ABILITY,
        requestCode: 0,
        wantAgentFlags: [wantAgent.WantAgentFlags.UPDATE_PRESENT_FLAG]
      };
      const agent: object = await wantAgent.getWantAgent(info);
      const request: backgroundTaskManager.ContinuousTaskRequest =
        new backgroundTaskManager.ContinuousTaskRequest();
      request.backgroundTaskModes = [backgroundTaskManager.BackgroundTaskMode.MODE_AUDIO_PLAYBACK];
      // 主/子类型必须按官方对照表配对：MODE_AUDIO_PLAYBACK 只接受 SUBMODE_NORMAL_NOTIFICATION。
      // SUBMODE_AVSESSION_AUDIO_PLAYBACK 挂在 MODE_AV_PLAYBACK_AND_RECORD(12) 下，
      // 两者错配会直接 9800005（模拟器实测）。会话照常接入 —— 接入后通知栏由
      // AVSession 出播控卡片，长时任务这里只负责保活，不会再叠一条普通通知。
      request.backgroundTaskSubmodes =
        [backgroundTaskManager.BackgroundTaskSubmode.SUBMODE_NORMAL_NOTIFICATION];
      request.wantAgent = agent;
      const notification: backgroundTaskManager.ContinuousTaskNotification =
        await backgroundTaskManager.startBackgroundRunning(ctx, request);
      this.taskId = notification.continuousTaskId === undefined ? -1 : notification.continuousTaskId;
      hilog.info(DOMAIN, TAG, `continuous task started: taskId=${this.taskId}`);
      return true;
    } catch (e) {
      hilog.warn(DOMAIN, TAG, `startBackgroundRunning failed: ${String(e)}`);
      return false;
    }
  }

  async stopAudioPlayback(): Promise<void> {
    const ctx: common.UIAbilityContext | null = this.context;
    const id: number = this.taskId;
    this.taskId = -1;
    if (ctx === null || id < 0) {
      return;
    }
    try {
      await backgroundTaskManager.stopBackgroundRunning(ctx, id);
      hilog.info(DOMAIN, TAG, `continuous task stopped: taskId=${id}`);
    } catch (e) {
      hilog.warn(DOMAIN, TAG, `stopBackgroundRunning failed: ${String(e)}`);
    }
  }

  isRunning(): boolean {
    return this.taskId >= 0;
  }
}
