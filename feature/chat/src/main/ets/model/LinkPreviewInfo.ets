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
    isLargeMedia: boolean = false
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
