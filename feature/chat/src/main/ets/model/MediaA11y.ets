/**
 * feature/chat — 媒体圆钮的无障碍槽位选择（A11Y-101）。
 *
 * 文档 / 语音 / 音频 / 视频气泡左侧那颗 44vp 圆钮是**同一个状态机的四种画法**：
 * 失败 → 重试发送，上传中 → 取消上传，下载中 → 取消下载，未下载 → 下载，
 * 已就绪 → 播放 / 暂停（文档没有播放，就绪态就是打开文件）。
 * 图标跟着状态换，无障碍标签也必须跟着换；写死成「播放」会让屏幕朗读在读到
 * 「取消下载」的按钮时播报「播放」。这条链路此前散落在四个 @Builder 的
 * `if/else` 里，各写一遍必然漂移，所以判据收在这一个纯函数里。
 *
 * 返回的是 `A11y.*` **槽位 key**（不是文案）：调用点写成
 * `.accessibilityText(a11y(mediaCircleA11ySlot(...)))`，翻译仍由 Lang 负责。
 */
import { A11y } from '@tgx/core-common';

export function mediaCircleA11ySlot(
  isFailed: boolean,
  isUploading: boolean,
  isDownloading: boolean,
  isDownloaded: boolean,
  isPlaying: boolean,
  playable: boolean
): string {
  if (isFailed) {
    return A11y.RETRY_SEND;
  }
  if (isUploading) {
    return A11y.CANCEL_UPLOAD;
  }
  if (isDownloading) {
    return A11y.CANCEL_DOWNLOAD;
  }
  if (!isDownloaded) {
    return A11y.DOWNLOAD;
  }
  if (!playable) {
    return A11y.OPEN_FILE;
  }
  return isPlaying ? A11y.PAUSE : A11y.PLAY;
}
