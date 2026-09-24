/**
 * feature/chat — 全屏媒体画廊项数据模型（MEDIA-103 / FEAT-MEDIA-006）。
 */

import { MediaAttachment, MediaFullSource } from './MediaAttachment';
import { viewerNeedsPlayer } from './ViewerPlayback';

export class MediaViewerItem {
  readonly messageId: number;
  readonly senderName: string;
  readonly timestampMs: number;
  readonly media: MediaAttachment;

  constructor(
    messageId: number,
    senderName: string,
    timestampMs: number,
    media: MediaAttachment
  ) {
    this.messageId = messageId;
    this.senderName = senderName;
    this.timestampMs = timestampMs;
    this.media = media;
  }
}

/**
 * 画廊项的 ForEach key（MEDIA-VIEWER-101 / MEDIA-VIEWER-102）。
 *
 * 原先页面只按 messageId 做 key，两个问题一起踩到：
 * - 相册里多条媒体共用一个 messageId，key 直接撞车；
 * - 「大图档下载完成」属于原地变更，key 不变就不重渲，换源的时机就此丢掉 ——
 *   与 MSG-104 已读勾踩过的是同一个坑。
 * 所以签名里必须带上 kind / fileId / 两条本地路径 / 下载态 / 进度。
 *
 * MEDIA-VIEWER-102 再加一条：**播放器只在当前页存在，而「是不是当前页」也必须进键**。
 * 同一个坑的另一面 —— 翻页时 item 内容一点没变，key 不变就没人重渲，
 * 于是刚离开那一页的 `Video` 节点还活着继续出声。只给需要播放器的条目加这一位，
 * 照片页不因为翻页白白重建（重建 = 重新解码，会闪）。
 */
export function mediaViewerItemKey(item: MediaViewerItem, isActive: boolean): string {
  const m: MediaAttachment = item.media;
  const full: MediaFullSource | null = m.fullSource;
  const fullSig: string = full === null
    ? 'same'
    : `${full.fileId}|${full.localPath !== null ? full.localPath : ''}|${full.isDownloaded}`;
  const base: string = `${item.messageId}|${m.kind}|${m.fileId}` +
    `|${m.localPath !== null ? m.localPath : ''}|${m.thumbnailPath !== null ? m.thumbnailPath : ''}` +
    `|${m.isDownloaded}|${Math.round(m.progress * 100)}|${fullSig}`;
  if (!viewerNeedsPlayer(m)) {
    return base;
  }
  return `${base}|${isActive ? 'player' : 'poster'}`;
}
