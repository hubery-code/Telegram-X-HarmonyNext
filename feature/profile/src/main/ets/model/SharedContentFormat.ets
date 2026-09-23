/**
 * feature/profile — 共享内容条目的纯格式化与解析（CHATPROF-SHARED）。
 *
 * 从 ProfileCoordinator（PROFILE-103 用户资料页共享内容四 Tab）里抽出来，让用户资料页
 * 与群/频道资料页的 coordinator 共用同一套解析规则：两处若各写一份，文件大小文案、
 * 缩略图选档、link_preview 兜底就会开始分叉，同一批消息在两个页面上长得不一样。
 *
 * Kit-free：只依赖 TDLib DTO 与本模块契约类型，可被 reducer/coordinator 直接 import。
 * 视图侧纯助手（头像调色板、字母头像首字符）同样收在这里，页面与共享内容分区组件共用一份色值。
 */

import {
  Message,
  TdMessageContent,
  MessageText,
  MessagePhoto,
  MessageDocument,
  MessageVideo,
  Photo,
  PhotoSize,
  File,
  LinkPreview,
  TdChatType,
  ChatTypeSupergroup
} from '@tgx/core-td-api-generated';
import { SharedFileItem, SharedLinkItem, SharedMediaItem } from '../contract/SharedContentItems';

/** 文件大小文案（与 feature/chat 的 formatFileSize 同规则，feature 间不可互引故本地实现）。 */
export function formatFileSizeText(bytes: number): string {
  if (!Number.isFinite(bytes) || bytes <= 0) {
    return '0 B';
  }
  const KB: number = 1024;
  const MB: number = 1024 * 1024;
  const GB: number = 1024 * 1024 * 1024;
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

function pad2(value: number): string {
  return value < 10 ? `0${value}` : `${value}`;
}

/** 共享内容条目日期。当天 HH:mm，跨天 dd.MM（与 feature/chat 搜索结果一致）。 */
export function formatSharedDate(unixSeconds: number): string {
  if (unixSeconds <= 0) {
    return '';
  }
  const date: Date = new Date(unixSeconds * 1000);
  const now: Date = new Date();
  const sameDay: boolean = date.getFullYear() === now.getFullYear() &&
    date.getMonth() === now.getMonth() &&
    date.getDate() === now.getDate();
  if (sameDay) {
    return `${pad2(date.getHours())}:${pad2(date.getMinutes())}`;
  }
  return `${pad2(date.getDate())}.${pad2(date.getMonth() + 1)}`;
}

/** 从文本中提取首个 http(s) URL；无则空串。 */
export function firstUrlInText(text: string): string {
  if (text.length === 0) {
    return '';
  }
  const match: RegExpMatchArray | null = text.match(/https?:\/\/[^\s"'<>()]+/i);
  if (match === null) {
    return '';
  }
  return match[0];
}

/** 宫格缩略图选尺寸：优先宽度 >=320 的最小档，否则最大档。 */
export function pickThumbPhotoSize(sizes: PhotoSize[]): PhotoSize | null {
  if (sizes.length === 0) {
    return null;
  }
  let chosen: PhotoSize = sizes[sizes.length - 1];
  for (let i = 0; i < sizes.length; i++) {
    const size: PhotoSize = sizes[i];
    if (size.photo === null) {
      continue;
    }
    if (size.width >= 320) {
      chosen = size;
      break;
    }
  }
  return chosen.photo !== null ? chosen : null;
}

/** 会话类型文案（共同群组副标题兜底）。 */
export function chatTypeLabel(type: TdChatType | null): string {
  if (type === null || type === undefined) {
    return '';
  }
  if (type.type === 'chatTypeSupergroup') {
    const supergroup: ChatTypeSupergroup = type as ChatTypeSupergroup;
    return supergroup.is_channel ? '频道' : '超级群组';
  }
  if (type.type === 'chatTypeBasicGroup') {
    return '群组';
  }
  if (type.type === 'chatTypePrivate') {
    return '私聊';
  }
  return '';
}

/** 消息内容摘要（共同群组副标题；与 feature/chat 的 messageContentText 同思路，本地实现）。 */
export function messageContentSummary(content: TdMessageContent | null): string {
  if (content === null) {
    return '';
  }
  switch (content.type) {
    case 'messageText': {
      const text: MessageText = content as MessageText;
      return text.text !== null ? text.text.text : '';
    }
    case 'messagePhoto':
      return '[照片]';
    case 'messageVideo':
      return '[视频]';
    case 'messageDocument':
      return '[文件]';
    case 'messageAudio':
      return '[音频]';
    case 'messageVoiceNote':
      return '[语音]';
    case 'messageSticker':
      return '[贴纸]';
    case 'messageAnimation':
      return '[GIF]';
    default:
      return '';
  }
}

/** messageDocument → SharedFileItem（大小/日期文案 + 本地路径可空）。 */
export function fileItemOf(msg: Message): SharedFileItem | null {
  const content: TdMessageContent | null = msg.content;
  if (content === null || content.type !== 'messageDocument') {
    return null;
  }
  const docMsg: MessageDocument = content as MessageDocument;
  if (docMsg.document === null) {
    return null;
  }
  const file: File | null = docMsg.document.document;
  const localPath: string | null =
    (file !== null && file.local !== null && file.local.path.length > 0) ? file.local.path : null;
  const sizeText: string = file !== null ? formatFileSizeText(file.size) : '';
  const name: string = docMsg.document.file_name.length > 0 ? docMsg.document.file_name : 'File';
  return new SharedFileItem(name, sizeText, formatSharedDate(msg.date), localPath);
}

/** messageText → SharedLinkItem：优先 link_preview 的 url/site_name/description，无则取文本中的 URL。 */
export function linkItemOf(content: TdMessageContent | null): SharedLinkItem | null {
  if (content === null || content.type !== 'messageText') {
    return null;
  }
  const text: MessageText = content as MessageText;
  const body: string = text.text !== null ? text.text.text : '';
  const preview: LinkPreview | null = text.link_preview;
  if (preview !== null && preview !== undefined && preview.url.length > 0) {
    const desc: string = preview.description !== null && preview.description !== undefined
      ? preview.description.text
      : '';
    return new SharedLinkItem(preview.url, preview.site_name, desc);
  }
  const url: string = firstUrlInText(body);
  if (url.length === 0) {
    return null;
  }
  return new SharedLinkItem(url, '', '');
}

/**
 * messagePhoto/messageVideo → 宫格条目。
 *
 * `localPathOf` 由调用方给出（各自用自己的 FileRegistry 查本地路径，顺带登记订阅），
 * 解析规则本身保持 Kit-free 可单测。缩略图未就绪时返回占位条目（fileId=0），
 * 保证「消息数 = 网格数」——否则翻页回来的条目会被静默丢掉，加载更多按钮也提前消失。
 */
export function sharedMediaItemOf(
  content: TdMessageContent | null,
  localPathOf: (fileId: number) => string | null
): SharedMediaItem | null {
  if (content === null) {
    return null;
  }
  if (content.type === 'messagePhoto') {
    const photo: MessagePhoto = content as MessagePhoto;
    if (photo.photo === null) {
      return null;
    }
    const size: PhotoSize | null = pickThumbPhotoSize(photo.photo.sizes);
    if (size === null || size.photo === null) {
      return new SharedMediaItem(0, null, true);
    }
    return sharedMediaItemOfFile(size.photo, true, localPathOf);
  }
  if (content.type === 'messageVideo') {
    const videoMsg: MessageVideo = content as MessageVideo;
    // 优先新版 cover（Photo），退回 video.thumbnail 的 JPEG 缩略图。
    if (videoMsg.cover !== null) {
      const coverSize: PhotoSize | null = pickThumbPhotoSize(videoMsg.cover.sizes);
      if (coverSize !== null && coverSize.photo !== null) {
        return sharedMediaItemOfFile(coverSize.photo, false, localPathOf);
      }
    }
    if (videoMsg.video !== null &&
      videoMsg.video.thumbnail !== null &&
      videoMsg.video.thumbnail.file !== null) {
      return sharedMediaItemOfFile(videoMsg.video.thumbnail.file, false, localPathOf);
    }
    return new SharedMediaItem(0, null, false);
  }
  return null;
}

function sharedMediaItemOfFile(
  file: File,
  isPhoto: boolean,
  localPathOf: (fileId: number) => string | null
): SharedMediaItem {
  return new SharedMediaItem(file.id, localPathOf(file.id), isPhoto);
}

/**
 * 缩略图落盘后把网格里对应的占位条目换成真图（原位、保序）。
 * 没有命中的条目返回 null —— 调用方据此决定是否回灌状态，避免每帧 updateFile 都刷一次页面。
 */
export function withSharedMediaPath(
  media: SharedMediaItem[],
  fileId: number,
  path: string
): SharedMediaItem[] | null {
  let touched: boolean = false;
  const updated: SharedMediaItem[] = [];
  for (let i = 0; i < media.length; i++) {
    const item: SharedMediaItem = media[i];
    if (item.fileId === fileId && (item.localPath === null || item.localPath.length === 0)) {
      updated.push(new SharedMediaItem(item.fileId, path, item.isPhoto));
      touched = true;
    } else {
      updated.push(item);
    }
  }
  return touched ? updated : null;
}

/** Telegram 经典头像调色板（0..6），与 feature/chat 的 AVATAR_PALETTE 同色值。 */
export const AVATAR_PALETTE: string[] = [
  '#FFCC5049', '#FFD67722', '#FF955CDB', '#FF40A920',
  '#FF309EBA', '#FF368AD1', '#FFC7508B'
];

/** 调色板取色：越界回到第一色，避免共享内容里出现无色块。 */
export function avatarColorOf(index: number): string {
  if (index < 0 || index >= AVATAR_PALETTE.length) {
    return AVATAR_PALETTE[0];
  }
  return AVATAR_PALETTE[index];
}

/** 字母头像首字符（按 code point 取，emoji / 生僻字不会被截成半个）。 */
export function avatarLetterOf(title: string): string {
  if (title.length === 0) {
    return '?';
  }
  const first: string = title.trim();
  if (first.length === 0) {
    return '?';
  }
  const codePoint: number | undefined = first.codePointAt(0);
  if (codePoint === undefined) {
    return '?';
  }
  return String.fromCodePoint(codePoint).toUpperCase();
}
