/**
 * feature/chat — 消息多媒体附件数据模型（MEDIA-101 / MEDIA-105）。
 *
 * 承载图片（photo）、视频（video）、GIF 动图（animation）的渲染与下载状态：
 * - 尺寸与比例：width / height 保持原生比例并计算气泡卡片尺寸；
 * - 路径与状态：localPath / thumbnailPath / isDownloading / isDownloaded / progress；
 * - 图文说明：caption 与富文本 captionSpans。
 */

import { MessageTextSpan } from './MessageTextSpan';

export type MediaKind = 'none' | 'photo' | 'video' | 'animation' | 'document' | 'sticker';

export class MediaAttachment {
  readonly kind: MediaKind;
  readonly fileId: number;
  readonly localPath: string | null;
  readonly thumbnailPath: string | null;
  readonly width: number;
  readonly height: number;
  readonly duration: number; // 视频或 GIF 动图时长（秒），图片为 0
  readonly isDownloading: boolean;
  readonly isDownloaded: boolean;
  readonly progress: number; // 0..1
  readonly caption: string;
  readonly captionSpans: MessageTextSpan[];
  readonly hasSpoiler: boolean;
  readonly isUploading: boolean;
  readonly uploadProgress: number; // 0..1
  readonly fileName: string;
  readonly fileSize: number;
  readonly mimeType: string;

  constructor(
    kind: MediaKind,
    fileId: number,
    localPath: string | null = null,
    thumbnailPath: string | null = null,
    width: number = 0,
    height: number = 0,
    duration: number = 0,
    isDownloading: boolean = false,
    isDownloaded: boolean = false,
    progress: number = 0,
    caption: string = '',
    captionSpans: MessageTextSpan[] = [],
    hasSpoiler: boolean = false,
    isUploading: boolean = false,
    uploadProgress: number = 0,
    fileName: string = '',
    fileSize: number = 0,
    mimeType: string = ''
  ) {
    this.kind = kind;
    this.fileId = fileId;
    this.localPath = localPath;
    this.thumbnailPath = thumbnailPath;
    this.width = width;
    this.height = height;
    this.duration = duration;
    this.isDownloading = isDownloading;
    this.isDownloaded = isDownloaded;
    this.progress = progress;
    this.caption = caption;
    this.captionSpans = captionSpans;
    this.hasSpoiler = hasSpoiler;
    this.isUploading = isUploading;
    this.uploadProgress = uploadProgress;
    this.fileName = fileName;
    this.fileSize = fileSize;
    this.mimeType = mimeType;
  }

  copyWith(
    localPath?: string | null,
    thumbnailPath?: string | null,
    isDownloading?: boolean,
    isDownloaded?: boolean,
    progress?: number,
    isUploading?: boolean,
    uploadProgress?: number,
    fileName?: string,
    fileSize?: number,
    mimeType?: string
  ): MediaAttachment {
    return new MediaAttachment(
      this.kind,
      this.fileId,
      localPath !== undefined ? localPath : this.localPath,
      thumbnailPath !== undefined ? thumbnailPath : this.thumbnailPath,
      this.width,
      this.height,
      this.duration,
      isDownloading !== undefined ? isDownloading : this.isDownloading,
      isDownloaded !== undefined ? isDownloaded : this.isDownloaded,
      progress !== undefined ? progress : this.progress,
      this.caption,
      this.captionSpans,
      this.hasSpoiler,
      isUploading !== undefined ? isUploading : this.isUploading,
      uploadProgress !== undefined ? uploadProgress : this.uploadProgress,
      fileName !== undefined ? fileName : this.fileName,
      fileSize !== undefined ? fileSize : this.fileSize,
      mimeType !== undefined ? mimeType : this.mimeType
    );
  }
}

const KB: number = 1024;
const MB: number = 1024 * 1024;
const GB: number = 1024 * 1024 * 1024;

export function formatFileSize(bytes: number): string {
  if (!Number.isFinite(bytes) || bytes <= 0) {
    return '0 B';
  }
  if (bytes < KB) {
    return `${Math.round(bytes)} B`;
  }
  if (bytes < MB) {
    return `${(bytes / KB).toFixed(1)} KB`;
  }
  if (bytes < GB) {
    return `${(bytes / MB).toFixed(1)} MB`;
  }
  return `${(bytes / GB).toFixed(1)} GB`;
}
