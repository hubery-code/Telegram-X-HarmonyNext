/**
 * feature/chat — 消息链接预览模型（MSG-107 / FEAT-COMP-002）。
 *
 * 纯 ArkTS 不可变数据模型，对应 TDLib LinkPreview。
 * 包含站点名、标题、描述、原链接、缩略图本地物理路径与大图标志。
 */

export class LinkPreviewInfo {
  readonly url: string;
  readonly displayUrl: string;
  readonly siteName: string;
  readonly title: string;
  readonly description: string;
  readonly author: string;
  readonly showAboveText: boolean;
  readonly thumbnailPath: string | null;
  readonly fileId: number;
  readonly isPhoto: boolean;
  readonly isLargeMedia: boolean;
  readonly showMediaAboveDescription: boolean;
  readonly mediaWidth: number;
  readonly mediaHeight: number;

  constructor(
    url: string = '',
    displayUrl: string = '',
    siteName: string = '',
    title: string = '',
    description: string = '',
    author: string = '',
    showAboveText: boolean = false,
    thumbnailPath: string | null = null,
    fileId: number = 0,
    isPhoto: boolean = false,
    isLargeMedia: boolean = false,
    showMediaAboveDescription: boolean = false,
    mediaWidth: number = 0,
    mediaHeight: number = 0
  ) {
    this.url = url;
    this.displayUrl = displayUrl;
    this.siteName = siteName;
    this.title = title;
    this.description = description;
    this.author = author;
    this.showAboveText = showAboveText;
    this.thumbnailPath = thumbnailPath;
    this.fileId = fileId;
    this.isPhoto = isPhoto;
    this.isLargeMedia = isLargeMedia;
    this.showMediaAboveDescription = showMediaAboveDescription;
    this.mediaWidth = mediaWidth;
    this.mediaHeight = mediaHeight;
  }

  get aspectRatio(): number {
    if (this.mediaWidth > 0 && this.mediaHeight > 0) {
      const ratio: number = this.mediaWidth / this.mediaHeight;
      if (ratio < 0.5) {
        return 0.5;
      }
      if (ratio > 2.5) {
        return 2.5;
      }
      return ratio;
    }
    return 1.777;
  }

  hasContent(): boolean {
    return this.url.length > 0 &&
      (this.siteName.length > 0 ||
       this.title.length > 0 ||
       this.description.length > 0 ||
       this.thumbnailPath !== null ||
       this.fileId > 0);
  }
}
