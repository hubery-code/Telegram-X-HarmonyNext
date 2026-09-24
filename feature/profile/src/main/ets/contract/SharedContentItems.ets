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
  /** 消息时间（unix 秒），CHATPROF-DATE 的日期分组依据；0 表示源消息没给日期。 */
  readonly date: number;

  constructor(fileId: number, localPath: string | null, isPhoto: boolean, date: number = 0) {
    this.fileId = fileId;
    this.localPath = localPath;
    this.isPhoto = isPhoto;
    this.date = date;
  }
}

/** 文件 Tab 条目：展示名 + 大小文案 + 日期文案 + 本地路径（可空）。 */
export class SharedFileItem {
  readonly fileName: string;
  readonly fileSizeText: string;
  readonly dateText: string;
  readonly localPath: string | null;
  readonly date: number;

  constructor(fileName: string, fileSizeText: string, dateText: string, localPath: string | null,
    date: number = 0) {
    this.fileName = fileName;
    this.fileSizeText = fileSizeText;
    this.dateText = dateText;
    this.localPath = localPath;
    this.date = date;
  }
}

/** 链接 Tab 条目：url 必有；站点名/描述缺省时为空串。 */
export class SharedLinkItem {
  readonly url: string;
  readonly siteName: string;
  readonly description: string;
  readonly date: number;

  constructor(url: string, siteName: string, description: string, date: number = 0) {
    this.url = url;
    this.siteName = siteName;
    this.description = description;
    this.date = date;
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
