/**
 * feature/chat — 群聊消息署名解析（MSG-102）。
 *
 * 纯函数层，与 UserRegistry/TDLib 请求解耦（lookup/request 由调用方注入）：
 * - chatKindOf：Chat.type_（TdChatType 判别联合）→ 会话种类；私聊/密聊 →
 *   'private'，BasicGroup 与非频道 Supergroup → 'group'，频道 → 'channel'，
 *   null/未知 → 'unknown'（保守不署名）；
 * - resolveSenderInfo：仅"收到的 + 群聊 + MessageSenderUser"的消息出署名；
 *   缓存未命中返回空署名并触发注入的 requestUser（防重集合由调用方维护）；
 * - NAME_PALETTE：7 色署名/头像调色板，色值与 feature/chat_list 的
 *   AVATAR_PALETTE（Telegram 经典头像占位色）保持一致；装饰性数据，
 *   不进 design token（design_system 无名字调色板 token）；
 * - avatarLettersForName：从署名取 1-2 位大写首字母供圆形头像使用。
 */

import {
  ChatTypeSupergroup,
  MessageSenderUser,
  TdChatType,
  TdMessageSender,
  User
} from '@tgx/core-td-api-generated';
import { formatFullName, getAvatarColorIndex } from '@tgx/core-domain';

/** 会话种类：署名只对 'group' 生效。 */
export type ChatKind = 'private' | 'group' | 'channel' | 'unknown';

/** 署名与头像解析结果；colorIndex -1 = 无署名/默认色。userId 0 = 无（头像不可进资料页）。 */
export class SenderInfo {
  readonly name: string;
  readonly colorIndex: number;
  readonly avatarPath: string | null;
  /** PROFILE-101：发送者用户 id；0 = 非用户发送者/未知（头像不可点进资料页）。 */
  readonly userId: number;

  constructor(name: string = '', colorIndex: number = -1, avatarPath: string | null = null, userId: number = 0) {
    this.name = name;
    this.colorIndex = colorIndex;
    this.avatarPath = avatarPath;
    this.userId = userId;
  }
}

export const EMPTY_SENDER_INFO: SenderInfo = new SenderInfo();

/** 注入的用户查询/请求面：由 ChatCoordinator 桥接 UserRegistry 与 FileRegistry。 */
export interface SenderInfoDeps {
  lookupUser: (userId: number) => User | null;
  requestUser: (userId: number) => void;
  lookupFilePath?: (fileId: number) => string | null;
  requestAvatarDownload?: (fileId: number) => void;
}

export function chatKindOf(chatType: TdChatType | null): ChatKind {
  if (chatType === null) {
    return 'unknown';
  }
  switch (chatType.type) {
    case 'chatTypePrivate':
    case 'chatTypeSecret':
      return 'private';
    case 'chatTypeBasicGroup':
      return 'group';
    case 'chatTypeSupergroup':
      return (chatType as ChatTypeSupergroup).is_channel ? 'channel' : 'group';
    default:
      return 'unknown';
  }
}

/**
 * 解析消息署名与头像：收到的群聊消息且 sender 是用户 → 命中缓存返回
 * {formatFullName, getAvatarColorIndex, avatarPath}；未命中返回空署名并触发 requestUser
 * （晚到的 User 经订阅回调刷新上屏）。自己的消息、私聊/频道、
 * MessageSenderChat（频道身份发帖）一律返回空署名。
 */
export function resolveSenderInfo(
  isOutgoing: boolean,
  chatKind: ChatKind,
  sender: TdMessageSender | null,
  deps: SenderInfoDeps
): SenderInfo {
  if (isOutgoing || chatKind !== 'group' || sender === null) {
    return EMPTY_SENDER_INFO;
  }
  if (sender.type !== 'messageSenderUser') {
    return EMPTY_SENDER_INFO;
  }
  const userId: number = (sender as MessageSenderUser).user_id;
  const user: User | null = deps.lookupUser(userId);
  if (user === null) {
    deps.requestUser(userId);
    return EMPTY_SENDER_INFO;
  }
  const name: string = formatFullName(user);
  if (name.length === 0) {
    return EMPTY_SENDER_INFO;
  }

  let avatarPath: string | null = null;
  if (
    user.profile_photo !== null &&
    user.profile_photo.small !== null
  ) {
    const fileId: number = user.profile_photo.small.id;
    if (deps.lookupFilePath) {
      avatarPath = deps.lookupFilePath(fileId);
    }
    if (avatarPath === null && deps.requestAvatarDownload) {
      deps.requestAvatarDownload(fileId);
    }
  }

  return new SenderInfo(name, getAvatarColorIndex(userId), avatarPath, userId);
}

/** Telegram 经典头像/署名调色板（'#AARRGGBB'），与 chat_list 的 AVATAR_PALETTE 同色值。 */
export const NAME_PALETTE: string[] = [
  '#FFCC5049', // red
  '#FFD67722', // orange
  '#FF955CDB', // violet
  '#FF40A920', // green
  '#FF309EBA', // cyan
  '#FF368AD1', // blue
  '#FFC7508B'  // pink
];

/** colorIndex（0..6）→ 调色板颜色；非法索引取模兜底。 */
export function nameColorForIndex(colorIndex: number): string {
  const size: number = NAME_PALETTE.length;
  const idx: number = ((colorIndex % size) + size) % size;
  return NAME_PALETTE[idx];
}

/** 提取字符串首字符（正确处理 Unicode 代理对）。 */
function extractFirstChar(str: string): string {
  if (str.length === 0) {
    return '';
  }
  const codePoint: number | undefined = str.codePointAt(0);
  if (codePoint === undefined) {
    return '';
  }
  return String.fromCodePoint(codePoint);
}

/** 从署名取头像首字母：两个词取两词首字母，单词取首字符，大写；空名回退 '?'。 */
export function avatarLettersForName(name: string): string {
  const trimmed: string = name.trim();
  if (trimmed.length === 0) {
    return '?';
  }
  const parts: string[] = trimmed.split(/\s+/).filter((p: string): boolean => p.length > 0);
  if (parts.length >= 2) {
    return (extractFirstChar(parts[0]) + extractFirstChar(parts[1])).toUpperCase();
  }
  return extractFirstChar(trimmed).toUpperCase();
}
