/**
 * entry — 音频容器可信度嗅探（VOICE-101 缺陷修复）。
 *
 * 背景：语音消息的本地文件既可能来自真实录音，也可能来自降级占位。把
 * 「文件名后缀像音频、但内容不是对应容器」的文件交给 AVPlayer，会被
 * 解码器以 `5400106 CONTAINER_ERR` 拒掉，最终在 UI 上表现为一条裸错误。
 *
 * 所以在这里做一次「按扩展名校验容器魔数」的廉价预检，把不可解码的文件
 * 挡在播放器之外；录音侧同样用它来判断「录下来的东西能不能发出去」。
 *
 * 注意：这里只做容器**嗅探**，不做完整解码校验——目标是拦住明显不可能的
 * 文件（例如 45 字节的假 Ogg 头被塞进 .m4a），而不是替代解码器。
 */

import { fileIo } from '@kit.CoreFileKit';

/** 低于该字节数的文件不可能承载任何音频帧，直接判为不可播放。 */
export const MIN_PLAYABLE_AUDIO_BYTES: number = 256;

/** 嗅探结果。 */
export interface AudioProbe {
  /** 文件是否存在。 */
  readonly exists: boolean;
  /** 文件字节数（不存在时为 0）。 */
  readonly size: number;
  /** 小写扩展名，含点号；无扩展名时为空串。 */
  readonly extension: string;
  /** 实际嗅探到的容器类型。 */
  readonly container: string;
  /** 是否可以安全地交给解码器。 */
  readonly playable: boolean;
  /** 判定依据，用于日志与排障（不承载用户可见文案）。 */
  readonly reason: string;
}

const CONTAINER_MP4: string = 'mp4';
const CONTAINER_OGG: string = 'ogg';
const CONTAINER_MP3: string = 'mp3';
const CONTAINER_UNKNOWN: string = 'unknown';

/** 扩展名 → 期望容器。TDLib 的 VoiceNote 只认可这几类（见 FileManager.cpp fix_file_extension）。 */
function expectedContainerFor(extension: string): string {
  switch (extension) {
    case '.m4a':
    case '.mp4':
    case '.m4b':
      return CONTAINER_MP4;
    case '.ogg':
    case '.oga':
    case '.opus':
      return CONTAINER_OGG;
    case '.mp3':
    case '.mpeg3':
      return CONTAINER_MP3;
    default:
      return '';
  }
}

function extensionOf(path: string): string {
  const lastDot: number = path.lastIndexOf('.');
  const lastSlash: number = path.lastIndexOf('/');
  if (lastDot <= lastSlash || lastDot < 0) {
    return '';
  }
  return path.substring(lastDot).toLowerCase();
}

/** 读取文件头部若干字节；读不到时返回空数组。 */
function readHead(path: string, count: number): Uint8Array {
  let fd: number = -1;
  try {
    fd = fileIo.openSync(path, fileIo.OpenMode.READ_ONLY).fd;
    const buffer: ArrayBuffer = new ArrayBuffer(count);
    const readLen: number = fileIo.readSync(fd, buffer);
    if (readLen <= 0) {
      return new Uint8Array(0);
    }
    return new Uint8Array(buffer, 0, readLen);
  } catch (_e) {
    return new Uint8Array(0);
  } finally {
    if (fd >= 0) {
      try {
        fileIo.closeSync(fd);
      } catch (_ce) {
        // ignore
      }
    }
  }
}

/** MP4 系（ISOBMFF）：offset 4..7 必须是 `ftyp` box。 */
function isMp4(head: Uint8Array): boolean {
  if (head.length < 8) {
    return false;
  }
  return head[4] === 0x66 && head[5] === 0x74 && head[6] === 0x79 && head[7] === 0x70;
}

/** Ogg 系：offset 0..3 必须是 `OggS`。 */
function isOgg(head: Uint8Array): boolean {
  if (head.length < 4) {
    return false;
  }
  return head[0] === 0x4F && head[1] === 0x67 && head[2] === 0x67 && head[3] === 0x53;
}

/** MP3 系：`ID3` 标签头或 MPEG 帧同步字。 */
function isMp3(head: Uint8Array): boolean {
  if (head.length < 3) {
    return false;
  }
  if (head[0] === 0x49 && head[1] === 0x44 && head[2] === 0x33) {
    return true;
  }
  return head[0] === 0xFF && (head[1] & 0xE0) === 0xE0;
}

function detectContainer(head: Uint8Array): string {
  if (isMp4(head)) {
    return CONTAINER_MP4;
  }
  if (isOgg(head)) {
    return CONTAINER_OGG;
  }
  if (isMp3(head)) {
    return CONTAINER_MP3;
  }
  return CONTAINER_UNKNOWN;
}

/**
 * 嗅探本地音频文件是否可解码。
 *
 * 判定顺序：存在 → 体积下限 → 容器魔数与扩展名一致。任何一步不过，
 * `playable` 即为 false，并把 `reason` 说明是哪一步挂的。
 */
export function probeAudioFile(path: string): AudioProbe {
  const extension: string = extensionOf(path);

  let exists: boolean = false;
  try {
    exists = path.length > 0 && fileIo.accessSync(path);
  } catch (_e) {
    exists = false;
  }

  if (!exists) {
    return { exists: false, size: 0, extension: extension, container: CONTAINER_UNKNOWN, playable: false, reason: 'file_missing' };
  }

  let size: number = 0;
  try {
    size = fileIo.statSync(path).size;
  } catch (_e) {
    return { exists: true, size: 0, extension: extension, container: CONTAINER_UNKNOWN, playable: false, reason: 'stat_failed' };
  }

  if (size < MIN_PLAYABLE_AUDIO_BYTES) {
    return { exists: true, size: size, extension: extension, container: CONTAINER_UNKNOWN, playable: false, reason: 'too_small' };
  }

  const head: Uint8Array = readHead(path, 16);
  if (head.length === 0) {
    return { exists: true, size: size, extension: extension, container: CONTAINER_UNKNOWN, playable: false, reason: 'unreadable' };
  }

  const container: string = detectContainer(head);
  const expected: string = expectedContainerFor(extension);

  if (expected.length === 0) {
    // 扩展名不在已知集合内：只要有可识别的容器特征就放行，交给解码器裁决。
    const lenient: boolean = container !== CONTAINER_UNKNOWN;
    return {
      exists: true,
      size: size,
      extension: extension,
      container: container,
      playable: lenient,
      reason: lenient ? 'unknown_extension_but_known_container' : 'unknown_extension_and_container'
    };
  }

  if (container === CONTAINER_UNKNOWN) {
    return { exists: true, size: size, extension: extension, container: container, playable: false, reason: 'container_magic_unrecognized' };
  }

  if (container !== expected) {
    return { exists: true, size: size, extension: extension, container: container, playable: false, reason: 'extension_container_mismatch' };
  }

  return { exists: true, size: size, extension: extension, container: container, playable: true, reason: 'ok' };
}
