/**
 * feature/settings — 「自动媒体下载」子页的纯展示映射（AUTODL-101）。
 *
 * 策略本体在 `@tgx/core-domain`（设置页写、聊天页读），这里只负责把策略翻成行文案，
 * 且**只返回 i18n 键**，翻译交给页面（与 `ProxySettings.proxyKindLabel` 同一口径）。
 *
 * 行文案的三条规矩（照 Android TGX 的 Data and Storage）：
 * 1. 三个分区勾得完全一样 → 直接列媒体类型，用户不必点进去就知道现状；
 * 2. 一条都没勾 → 显「不自动下载」，而不是显一个空的类型列表；
 * 3. 分区之间有差异 → 显「按会话类型分别设置」，不假装能一行说清。
 */

import {
  AutoDownloadChatScope,
  AutoDownloadFlags,
  AutoDownloadMediaKind,
  AutoDownloadPolicy
} from '@tgx/core-domain';

/** 子页里的三个分区行；顺序即界面顺序（私聊 → 群组 → 频道）。 */
export const AUTO_DOWNLOAD_SCOPE_ORDER: AutoDownloadChatScope[] = ['private', 'group', 'channel'];

/** 面板里的媒体类型行；顺序即界面顺序（对齐 Android 对话框：照片/语音/视频便签/视频/文件/音乐/GIF）。 */
export const AUTO_DOWNLOAD_KIND_ORDER: AutoDownloadMediaKind[] = [
  'photo',
  'voice',
  'videoNote',
  'video',
  'file',
  'audio',
  'gif'
];

export function autoDownloadScopeLabelKey(scope: AutoDownloadChatScope): string {
  if (scope === 'private') {
    return 'Private Chats';
  }
  if (scope === 'channel') {
    return 'Channels';
  }
  return 'Group Chats';
}

export function autoDownloadKindLabelKey(kind: AutoDownloadMediaKind): string {
  switch (kind) {
    case 'photo':
      return 'Photos';
    case 'voice':
      return 'Voice message';
    case 'videoNote':
      return 'Video message';
    case 'video':
      return 'Videos';
    case 'file':
      return 'Files';
    case 'audio':
      return 'Music';
    case 'gif':
      return 'GIFs';
    default:
      return 'Photos';
  }
}

/**
 * 一个分区的副标题：媒体类型键列表；全空时返回单键 `Download nothing automatically`。
 * `singleOnly` 为 true 表示页面只需翻译 `singleKey`。
 */
export class AutoDownloadScopeSummary {
  readonly singleKey: string;
  readonly kindKeys: string[];

  constructor(singleKey: string, kindKeys: string[]) {
    this.singleKey = singleKey;
    this.kindKeys = kindKeys;
  }
}

export function autoDownloadScopeSummary(flags: AutoDownloadFlags | null): AutoDownloadScopeSummary {
  if (flags === null) {
    return new AutoDownloadScopeSummary('Loading...', []);
  }
  const kinds: AutoDownloadMediaKind[] = flags.enabledKinds();
  if (kinds.length === 0) {
    return new AutoDownloadScopeSummary('Download nothing automatically', []);
  }
  const keys: string[] = [];
  for (const kind of AUTO_DOWNLOAD_KIND_ORDER) {
    if (kinds.indexOf(kind) >= 0) {
      keys.push(autoDownloadKindLabelKey(kind));
    }
  }
  return new AutoDownloadScopeSummary('', keys);
}

/** 设置页「自动媒体下载」行的副标题。 */
export function autoDownloadRowSummary(policy: AutoDownloadPolicy | null): AutoDownloadScopeSummary {
  if (policy === null) {
    return new AutoDownloadScopeSummary('Loading...', []);
  }
  const scopes: AutoDownloadChatScope[] = AUTO_DOWNLOAD_SCOPE_ORDER;
  const first: AutoDownloadFlags = policy.flagsOf(scopes[0]);
  let same: boolean = true;
  for (const scope of scopes) {
    if (!policy.flagsOf(scope).equals(first)) {
      same = false;
      break;
    }
  }
  if (!same) {
    return new AutoDownloadScopeSummary('Varies by chat type', []);
  }
  return autoDownloadScopeSummary(first);
}

/** 面板里某一行的勾选态（纯查表，页面只把它交给 Checkbox）。 */
export function autoDownloadKindEnabled(flags: AutoDownloadFlags | null, kind: AutoDownloadMediaKind): boolean {
  return flags !== null && flags.of(kind);
}
