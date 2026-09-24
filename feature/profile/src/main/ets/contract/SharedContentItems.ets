/**
 * feature/profile — 资料页「共享内容」条目模型（PROFILE-103）。
 *
 * 内容型 Tab（媒体/文件/链接/音乐/语音）+ 共同群组的 UI 无关不可变条目，
 * 由 coordinator 从 searchChatMessages / getGroupsInCommon 的解码结果映射而来。
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

/**
 * 音乐 / 语音 Tab 条目（SHARED-AUDIO，对齐 TGX `SharedCommonController` 的行构成）：
 * - 音乐：title=`audio.title`（缺省回落到文件名），subtitle=表演者 + 时长；
 * - 语音：title=发送者昵称，subtitle=时长 + 发送时间。
 * `fileId`/`localPath` 与媒体 Tab 同一套下载回灌规则：路径没回来时点按先触发下载。
 */
export class SharedAudioItem {
  readonly fileId: number;
  readonly localPath: string | null;
  readonly title: string;
  /**
   * 表演者（AUDIO-BG-101 给锁屏播控卡片用）：音乐取 `audio.performer`，语音留空。
   * 行副标题里也有这段文字，但那是给人读的一整行，不能拿来当 artist 用。
   */
  readonly artist: string;
  readonly subtitle: string;
  /** 时长（秒）；0 表示源消息没给。仅用于日志与后续进度条。 */
  readonly duration: number;
  readonly date: number;

  constructor(fileId: number, localPath: string | null, title: string, artist: string,
    subtitle: string, duration: number = 0, date: number = 0) {
    this.fileId = fileId;
    this.localPath = localPath;
    this.title = title;
    this.artist = artist;
    this.subtitle = subtitle;
    this.duration = duration;
    this.date = date;
  }
}

export interface SharedContentRowsOptions {
  readonly media?: SharedMediaItem[];
  readonly files?: SharedFileItem[];
  readonly links?: SharedLinkItem[];
  readonly audios?: SharedAudioItem[];
  readonly voices?: SharedAudioItem[];
}

/**
 * 五个内容型 Tab 的条目集合。
 *
 * 回灌意图原本按位置传三个数组，加两个 Tab 就要五个参数、且调用方极易把顺序写反而
 * 编译器毫无察觉；换成一个集合对象后，coordinator 只需换掉自己那一段、其余透传。
 */
export class SharedContentRows {
  readonly media: SharedMediaItem[];
  readonly files: SharedFileItem[];
  readonly links: SharedLinkItem[];
  readonly audios: SharedAudioItem[];
  readonly voices: SharedAudioItem[];

  constructor(options: SharedContentRowsOptions = {}) {
    this.media = options.media ?? [];
    this.files = options.files ?? [];
    this.links = options.links ?? [];
    this.audios = options.audios ?? [];
    this.voices = options.voices ?? [];
  }
}
