/**
 * feature/chat — 消息多媒体附件数据模型（MEDIA-101 / MEDIA-105）。
 *
 * 承载图片（photo）、视频（video）、GIF 动图（animation）的渲染与下载状态：
 * - 尺寸与比例：width / height 保持原生比例并计算气泡卡片尺寸；
 * - 路径与状态：localPath / thumbnailPath / isDownloading / isDownloaded / progress；
 * - 图文说明：caption 与富文本 captionSpans。
 */

import { base64Decode, base64Encode } from '@tgx/core-common';
import { MessageTextSpan } from './MessageTextSpan';

export type MediaKind = 'none' | 'photo' | 'video' | 'animation' | 'document' | 'sticker' | 'voiceNote' | 'audio' | 'videoNote';

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
  readonly waveform: number[];
  readonly audioTitle: string;
  readonly audioPerformer: string;
  readonly isListened: boolean;
  readonly stickerSetId: string;

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
    mimeType: string = '',
    waveform: number[] = [],
    audioTitle: string = '',
    audioPerformer: string = '',
    isListened: boolean = false,
    stickerSetId: string = ''
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
    this.waveform = waveform;
    this.audioTitle = audioTitle;
    this.audioPerformer = audioPerformer;
    this.isListened = isListened;
    this.stickerSetId = stickerSetId;
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
    mimeType?: string,
    waveform?: number[],
    audioTitle?: string,
    audioPerformer?: string,
    isListened?: boolean,
    stickerSetId?: string
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
      mimeType !== undefined ? mimeType : this.mimeType,
      waveform !== undefined ? waveform : this.waveform,
      audioTitle !== undefined ? audioTitle : this.audioTitle,
      audioPerformer !== undefined ? audioPerformer : this.audioPerformer,
      isListened !== undefined ? isListened : this.isListened,
      stickerSetId !== undefined ? stickerSetId : this.stickerSetId
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

const DEFAULT_WAVEFORM: number[] = [
  3, 6, 10, 16, 22, 28, 20, 14, 8, 12, 18, 24, 30, 25, 18, 12,
  8, 15, 22, 26, 20, 14, 8, 5, 10, 16, 22, 18, 12, 8, 5, 3
];

/**
 * 解码 TDLib 5-bit 格式的波形数据。
 *
 * TDLib VoiceNote.waveform 是经 Base64 编码的字节串，
 * 内部按 5 bits 一个采样点连续打包：
 * - 总采样数: floor((bytes.length * 8) / 5)
 * - 每个采样值: 0..31
 */
export function decodeWaveform(waveformBase64: string): number[] {
  if (!waveformBase64 || waveformBase64.length === 0) {
    return [];
  }
  let bytes: Uint8Array;
  try {
    bytes = base64Decode(waveformBase64);
  } catch (_e) {
    return [];
  }
  if (bytes.length === 0) {
    return [];
  }
  const totalBits: number = bytes.length * 8;
  const sampleCount: number = Math.floor(totalBits / 5);
  const samples: number[] = [];
  for (let i = 0; i < sampleCount; i++) {
    const bitIndex: number = i * 5;
    const byteIndex: number = Math.floor(bitIndex / 8);
    const bitOffset: number = bitIndex % 8;
    let sample: number = (bytes[byteIndex] >> bitOffset) & 0x1F;
    if (bitOffset > 3 && byteIndex + 1 < bytes.length) {
      sample |= (bytes[byteIndex + 1] << (8 - bitOffset)) & 0x1F;
    }
    samples.push(sample);
  }
  return samples;
}

/**
 * 将原始采样归一化并降采样到指定的条数（默认 32 条），
 * 确保即使无波形数据或超长波形也能美观展示。
 */
export function normalizeWaveform(samples: number[], targetCount: number = 32): number[] {
  if (samples.length === 0) {
    const out: number[] = [];
    for (let i = 0; i < targetCount; i++) {
      out.push(DEFAULT_WAVEFORM[i % DEFAULT_WAVEFORM.length]);
    }
    return out;
  }
  const out: number[] = [];
  for (let i = 0; i < targetCount; i++) {
    const start: number = Math.floor((i * samples.length) / targetCount);
    const end: number = Math.max(start + 1, Math.floor(((i + 1) * samples.length) / targetCount));
    let maxVal: number = 0;
    for (let k = start; k < end && k < samples.length; k++) {
      if (samples[k] > maxVal) {
        maxVal = samples[k];
      }
    }
    out.push(maxVal);
  }
  return out;
}

/**
 * 将 5-bit 波形采样数组（0..31）编码为 TDLib 要求的 Base64 字符串。
 */
export function encodeWaveform(samples: number[]): string {
  if (!samples || samples.length === 0) {
    return '';
  }
  const totalBits: number = samples.length * 5;
  const byteLength: number = Math.ceil(totalBits / 8);
  const bytes: Uint8Array = new Uint8Array(byteLength);

  for (let i = 0; i < samples.length; i++) {
    const bitIndex: number = i * 5;
    const byteIndex: number = Math.floor(bitIndex / 8);
    const bitOffset: number = bitIndex % 8;
    const sample: number = Math.max(0, Math.min(31, Math.round(samples[i]))) & 0x1F;

    bytes[byteIndex] |= (sample << bitOffset) & 0xFF;
    if (bitOffset > 3 && byteIndex + 1 < bytes.length) {
      bytes[byteIndex + 1] |= (sample >> (8 - bitOffset)) & 0xFF;
    }
  }

  return base64Encode(bytes);
}
