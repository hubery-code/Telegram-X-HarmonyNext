/**
 * feature/chat — 全屏媒体画廊项数据模型（MEDIA-103 / FEAT-MEDIA-006）。
 */

import { MediaAttachment } from './MediaAttachment';

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
