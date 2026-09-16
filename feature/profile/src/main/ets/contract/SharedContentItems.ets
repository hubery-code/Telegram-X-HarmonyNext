/**
 * feature/profile — 资料页「共享内容」条目模型（PROFILE-103）。
 *
 * 四个 Tab（媒体/文件/链接/群组）的 UI 无关不可变条目，由 ProfileCoordinator
 * 从 searchChatMessages / getGroupsInCommon 的解码结果映射而来。
 */

/** 媒体 Tab 条目：fileId 用于下载回灌时定位；localPath 为空表示缩略图未就绪。 */
export class SharedMediaItem {
  readonly fileId: number;
  readonly localPath: string | null;
  /** true=照片，false=视频（缩略图来自 video.thumbnail）。 */
  readonly isPhoto: boolean;

  constructor(fileId: number, localPath: string | null, isPhoto: boolean) {
    this.fileId = fileId;
    this.localPath = localPath;
    this.isPhoto = isPhoto;
  }
}

/** 文件 Tab 条目：展示名 + 大小文案 + 日期文案 + 本地路径（可空）。 */
export class SharedFileItem {
  readonly fileName: string;
  readonly fileSizeText: string;
  readonly dateText: string;
  readonly localPath: string | null;

  constructor(fileName: string, fileSizeText: string, dateText: string, localPath: string | null) {
    this.fileName = fileName;
    this.fileSizeText = fileSizeText;
    this.dateText = dateText;
    this.localPath = localPath;
  }
}

/** 链接 Tab 条目：url 必有；站点名/描述缺省时为空串。 */
export class SharedLinkItem {
  readonly url: string;
  readonly siteName: string;
  readonly description: string;

  constructor(url: string, siteName: string, description: string) {
    this.url = url;
    this.siteName = siteName;
    this.description = description;
  }
}

/** 群组 Tab 条目：chatId 用于点击占位日志与后续跳转。 */
export class SharedGroupItem {
  readonly chatId: number;
  readonly title: string;
  readonly subtitle: string;

  constructor(chatId: number, title: string, subtitle: string) {
    this.chatId = chatId;
    this.title = title;
    this.subtitle = subtitle;
  }
}
