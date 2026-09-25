/**
 * core/domain — 自动媒体下载策略（AUTODL-101，FEAT-P2-007 下载策略半边）。
 *
 * 对齐 Android Telegram-X：策略按**会话类型**分区（私聊 / 群组 / 频道），每个分区内按
 * **媒体类型**勾选，持久化在按账号隔离的偏好键上
 * （`telegram/TdlibFilesManager.java` 的 `settings_autodownload`，三个字节域
 * private<<8 / groups<<16 / channels<<24，每字节是媒体位标记）。
 * 本端一个分区存一个数字掩码（见 `AutoDownloadPolicy.toStorageValues`），
 * 不再挤进一个 int —— 字节打包在 ArkTS 里只会让后面的调试变难。
 *
 * 默认值照 Android `loadSettings()` 的兜底：**照片 / 语音 / 动图 / 视频便签开，
 * 视频 / 文件 / 音乐关**。
 *
 * 下沉 core/domain 的原因：`feature/settings` 写这份策略、`feature/chat` 读它来放行下载，
 * 而 feature 之间禁止互引；一旦复制就会分叉（同 `chat/ChatMute.ets`、`chat/ChatSendRights.ets`）。
 *
 * 这里只有纯数据与纯函数：不碰 Kit、不碰 TDLib、不做网络判断。
 */

export type AutoDownloadMediaKind = 'photo' | 'voice' | 'videoNote' | 'video' | 'file' | 'audio' | 'gif';

/** 策略分区；对齐 `ChatKind`，但 `'unknown'` 不在这里表达（见 `autoDownloadScopeForChatKind`）。 */
export type AutoDownloadChatScope = 'private' | 'group' | 'channel';

/** 可自动下载的媒体类型；数组顺序同时是掩码位序，改动必须同步用例里的映射矩阵。 */
export const AUTO_DOWNLOAD_KINDS: AutoDownloadMediaKind[] = [
  'photo',
  'voice',
  'videoNote',
  'video',
  'file',
  'audio',
  'gif'
];

export const AUTO_DOWNLOAD_SCOPES: AutoDownloadChatScope[] = ['private', 'group', 'channel'];

/** 偏好存储键前缀；完整键 = 前缀 + 分区（按账号隔离由实现方决定，见 entry 的 store 适配器）。 */
export const AUTO_DOWNLOAD_STORAGE_PREFIX: string = 'autodownload_';

function kindBit(kind: AutoDownloadMediaKind): number {
  const index: number = AUTO_DOWNLOAD_KINDS.indexOf(kind);
  if (index < 0) {
    return 0;
  }
  return 1 << index;
}

/** 一个分区内的勾选集合。字段显式列举，便于 ArkUI 直接观察与表单绑定。 */
export class AutoDownloadFlags {
  photo: boolean;
  voice: boolean;
  videoNote: boolean;
  video: boolean;
  file: boolean;
  audio: boolean;
  gif: boolean;

  constructor(
    photo: boolean = false,
    voice: boolean = false,
    videoNote: boolean = false,
    video: boolean = false,
    file: boolean = false,
    audio: boolean = false,
    gif: boolean = false
  ) {
    this.photo = photo;
    this.voice = voice;
    this.videoNote = videoNote;
    this.video = video;
    this.file = file;
    this.audio = audio;
    this.gif = gif;
  }

  /** Android 的兜底默认：照片 / 语音 / 动图 / 视频便签开，其余关。 */
  static defaultFlags(): AutoDownloadFlags {
    return new AutoDownloadFlags(true, true, true, false, false, false, true);
  }

  static fromMask(mask: number): AutoDownloadFlags {
    const flags: AutoDownloadFlags = new AutoDownloadFlags();
    flags.photo = (mask & kindBit('photo')) !== 0;
    flags.voice = (mask & kindBit('voice')) !== 0;
    flags.videoNote = (mask & kindBit('videoNote')) !== 0;
    flags.video = (mask & kindBit('video')) !== 0;
    flags.file = (mask & kindBit('file')) !== 0;
    flags.audio = (mask & kindBit('audio')) !== 0;
    flags.gif = (mask & kindBit('gif')) !== 0;
    return flags;
  }

  of(kind: AutoDownloadMediaKind): boolean {
    switch (kind) {
      case 'photo':
        return this.photo;
      case 'voice':
        return this.voice;
      case 'videoNote':
        return this.videoNote;
      case 'video':
        return this.video;
      case 'file':
        return this.file;
      case 'audio':
        return this.audio;
      case 'gif':
        return this.gif;
      default:
        return false;
    }
  }

  with(kind: AutoDownloadMediaKind, enabled: boolean): AutoDownloadFlags {
    const next: AutoDownloadFlags = this.clone();
    switch (kind) {
      case 'photo':
        next.photo = enabled;
        break;
      case 'voice':
        next.voice = enabled;
        break;
      case 'videoNote':
        next.videoNote = enabled;
        break;
      case 'video':
        next.video = enabled;
        break;
      case 'file':
        next.file = enabled;
        break;
      case 'audio':
        next.audio = enabled;
        break;
      case 'gif':
        next.gif = enabled;
        break;
      default:
        break;
    }
    return next;
  }

  toMask(): number {
    let mask: number = 0;
    for (const kind of AUTO_DOWNLOAD_KINDS) {
      if (this.of(kind)) {
        mask |= kindBit(kind);
      }
    }
    return mask;
  }

  isEnabled(): boolean {
    return this.toMask() !== 0;
  }

  /** 按掩码位序列出已勾选项，供行副标题拼接（顺序稳定，不受 UI 影响）。 */
  enabledKinds(): AutoDownloadMediaKind[] {
    const kinds: AutoDownloadMediaKind[] = [];
    for (const kind of AUTO_DOWNLOAD_KINDS) {
      if (this.of(kind)) {
        kinds.push(kind);
      }
    }
    return kinds;
  }

  clone(): AutoDownloadFlags {
    return AutoDownloadFlags.fromMask(this.toMask());
  }

  equals(other: AutoDownloadFlags | null): boolean {
    if (other === null) {
      return false;
    }
    return this.toMask() === other.toMask();
  }
}

/** 三个分区的完整策略。存储只写掩码，读不到即回落默认。 */
export class AutoDownloadPolicy {
  privateFlags: AutoDownloadFlags;
  groupFlags: AutoDownloadFlags;
  channelFlags: AutoDownloadFlags;

  constructor(
    privateFlags: AutoDownloadFlags | null = null,
    groupFlags: AutoDownloadFlags | null = null,
    channelFlags: AutoDownloadFlags | null = null
  ) {
    this.privateFlags = privateFlags !== null ? privateFlags : AutoDownloadFlags.defaultFlags();
    this.groupFlags = groupFlags !== null ? groupFlags : AutoDownloadFlags.defaultFlags();
    this.channelFlags = channelFlags !== null ? channelFlags : AutoDownloadFlags.defaultFlags();
  }

  static defaultPolicy(): AutoDownloadPolicy {
    return new AutoDownloadPolicy();
  }

  flagsOf(scope: AutoDownloadChatScope): AutoDownloadFlags {
    if (scope === 'private') {
      return this.privateFlags;
    }
    if (scope === 'channel') {
      return this.channelFlags;
    }
    return this.groupFlags;
  }

  withFlags(scope: AutoDownloadChatScope, flags: AutoDownloadFlags): AutoDownloadPolicy {
    return new AutoDownloadPolicy(
      scope === 'private' ? flags : this.privateFlags,
      scope === 'group' ? flags : this.groupFlags,
      scope === 'channel' ? flags : this.channelFlags
    );
  }

  equals(other: AutoDownloadPolicy | null): boolean {
    if (other === null) {
      return false;
    }
    return this.privateFlags.equals(other.privateFlags)
      && this.groupFlags.equals(other.groupFlags)
      && this.channelFlags.equals(other.channelFlags);
  }

  toStorageValues(): number[] {
    return [this.privateFlags.toMask(), this.groupFlags.toMask(), this.channelFlags.toMask()];
  }

  static fromStorageValues(values: (number | null)[]): AutoDownloadPolicy {
    const readMask = (index: number): AutoDownloadFlags => {
      const value: number | null | undefined = values[index];
      if (value === null || value === undefined || !Number.isFinite(value) || value < 0) {
        return AutoDownloadFlags.defaultFlags();
      }
      return AutoDownloadFlags.fromMask(Math.floor(value));
    };
    return new AutoDownloadPolicy(readMask(0), readMask(1), readMask(2));
  }
}

/**
 * `ChatKind` → 策略分区。`'unknown'`（还没拿到 getChat）返回 null，
 * 调用方按「不拦」处理 —— 读不到会话类型不等于没有会话，
 * 一上来就把媒体挡在门外是更糟的错。
 */
export function autoDownloadScopeForChatKind(chatKind: string): AutoDownloadChatScope | null {
  if (chatKind === 'private') {
    return 'private';
  }
  if (chatKind === 'group') {
    return 'group';
  }
  if (chatKind === 'channel') {
    return 'channel';
  }
  return null;
}

/**
 * 下载门：只有明确勾过这一类媒体才自动下。出站消息不走这道门（见调用点注释）。
 *
 * 尺寸限制不在这里 —— AUTODL-101 曾在本模块写死过一条「视频/文件/音乐 10MB」的临时上限，
 * Android 并没有这个常量：尺寸上限是按网络类型配置的（`media/MediaDownloadLimits`），
 * 已由聊天页那道门按 Android 的顺序串起来。
 */
export function canAutoDownloadMedia(
  policy: AutoDownloadPolicy | null,
  chatKind: string,
  kind: AutoDownloadMediaKind
): boolean {
  if (policy === null) {
    return true;
  }
  const scope: AutoDownloadChatScope | null = autoDownloadScopeForChatKind(chatKind);
  if (scope === null) {
    return true;
  }
  return policy.flagsOf(scope).of(kind);
}

/** 策略读写面；实现方负责按账号隔离与落盘（entry 装配层）。 */
export interface AutoDownloadPolicyStore {
  /** 读取；读不到/失败返回 null，调用方回落默认且不写回。 */
  load(): AutoDownloadPolicy | null;

  /** 写入；返回是否成功（失败时 UI 保留原值并把错误提示出去）。 */
  save(policy: AutoDownloadPolicy): boolean;
}
