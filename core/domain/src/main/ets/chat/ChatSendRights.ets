/**
 * core/domain — 会话发言权（TDLib chatPermissions）纯函数模型（CHAN-SEND-2）。
 *
 * TDLib 的 chatPermissions 有 18 位，其中 9 位是「能不能发某种内容」，其余是管理权
 * （改资料、邀请、置顶、匿名等），管理权不进本模型：本模块只服务输入栏与附件面板。
 *
 * 与 Android TGX 的对应关系（app/.../data/TD.java:316-334 的 checkRight 映射）：
 *   basic          -> RightId.SEND_BASIC_MESSAGES
 *   audios         -> RightId.SEND_AUDIO
 *   documents      -> RightId.SEND_DOCS
 *   photos         -> RightId.SEND_PHOTOS
 *   videos         -> RightId.SEND_VIDEOS
 *   videoNotes     -> RightId.SEND_VIDEO_NOTES
 *   voiceNotes     -> RightId.SEND_VOICE_NOTES
 *   polls          -> RightId.SEND_POLLS_OR_CHECKLISTS
 *   otherMessages  -> RightId.SEND_OTHER_MESSAGES（贴纸 / GIF / inline bot）
 *
 * 下沉原因：feature/chat 的输入栏与附件面板、feature/profile 的资料页要读同一份权限口径，
 * feature 之间不可互引；且 ArkTS 不能自动收窄，权限判定必须集中成一处纯函数才好测。
 */

import { ChatPermissions } from '@tgx/core-td-api-generated';

/** 九位发言权；构造默认全放开，未拿到 permissions 时用这一份（见 sendRightsFromPermissions）。 */
export class ChatSendRights {
  /** 文本、富文本、联系人、位置等基础消息 */
  readonly basic: boolean;
  /** 音乐文件 */
  readonly audios: boolean;
  /** 文件 */
  readonly documents: boolean;
  /** 图片 */
  readonly photos: boolean;
  /** 视频 */
  readonly videos: boolean;
  /** 圆形视频便签 */
  readonly videoNotes: boolean;
  /** 语音消息 */
  readonly voiceNotes: boolean;
  /** 投票与清单 */
  readonly polls: boolean;
  /** 贴纸、GIF、动画、骰子与 inline bot */
  readonly otherMessages: boolean;

  constructor(
    basic: boolean = true,
    audios: boolean = true,
    documents: boolean = true,
    photos: boolean = true,
    videos: boolean = true,
    videoNotes: boolean = true,
    voiceNotes: boolean = true,
    polls: boolean = true,
    otherMessages: boolean = true
  ) {
    this.basic = basic;
    this.audios = audios;
    this.documents = documents;
    this.photos = photos;
    this.videos = videos;
    this.videoNotes = videoNotes;
    this.voiceNotes = voiceNotes;
    this.polls = polls;
    this.otherMessages = otherMessages;
  }

  /** 逐位比较：reducer 靠它决定「值未变则不动状态引用」，否则每次推送都会整页重算。 */
  sameAs(other: ChatSendRights): boolean {
    return this.basic === other.basic &&
      this.audios === other.audios &&
      this.documents === other.documents &&
      this.photos === other.photos &&
      this.videos === other.videos &&
      this.videoNotes === other.videoNotes &&
      this.voiceNotes === other.voiceNotes &&
      this.polls === other.polls &&
      this.otherMessages === other.otherMessages;
  }
}

/**
 * TDLib permissions -> 发言权。
 * null（TDLib 没给）按「全放开」处理：读不到权限不等于没权限，收成静音条等于把人锁在输入栏外，
 * 真发不出去自有 TDLib 的错误条兜底（与 CHAN-SEND 首版口径一致）。
 */
export function sendRightsFromPermissions(permissions: ChatPermissions | null): ChatSendRights {
  if (permissions === null) {
    return new ChatSendRights();
  }
  return new ChatSendRights(
    permissions.can_send_basic_messages,
    permissions.can_send_audios,
    permissions.can_send_documents,
    permissions.can_send_photos,
    permissions.can_send_videos,
    permissions.can_send_video_notes,
    permissions.can_send_voice_notes,
    permissions.can_send_polls,
    permissions.can_send_other_messages
  );
}

// ---- 输入栏与各入口的可用性 ----

/** 是否还能发任何一种媒体（对齐 Android Tdlib.canSendSendSomeMedia）：全禁时附件入口没有意义。 */
export function canSendAnyMedia(rights: ChatSendRights): boolean {
  return rights.audios || rights.documents || rights.photos || rights.videos ||
    rights.videoNotes || rights.voiceNotes || rights.polls || rights.otherMessages;
}

/** 附件面板里的一个条目：key 决定图标 / 文案 / 分发动作，enabled 决定置灰与点击提示。 */
export class AttachmentEntry {
  readonly key: string;
  readonly enabled: boolean;

  constructor(key: string, enabled: boolean) {
    this.key = key;
    this.enabled = enabled;
  }
}

export const ATTACHMENT_GALLERY: string = 'gallery';
export const ATTACHMENT_VIDEO: string = 'video';
export const ATTACHMENT_FILE: string = 'file';
export const ATTACHMENT_POLL: string = 'poll';

/**
 * 附件面板条目：顺序即展示顺序，不可用的条目保持可见但置灰（Android 同样保留入口，
 * 点击时由 showRestriction 出「此群组不允许发送图片」之类的提示，见 MessagesController.java:10324）。
 */
export function buildAttachmentEntries(rights: ChatSendRights): AttachmentEntry[] {
  const out: AttachmentEntry[] = [
    new AttachmentEntry(ATTACHMENT_GALLERY, rights.photos),
    new AttachmentEntry(ATTACHMENT_VIDEO, rights.videos),
    new AttachmentEntry(ATTACHMENT_FILE, rights.documents),
    new AttachmentEntry(ATTACHMENT_POLL, rights.polls)
  ];
  return out;
}

/** 录音入口可用性：语音便签与视频便签任一放开即可录音（对齐 TD.checkRight 的两者同权）。 */
export function canRecordVoice(rights: ChatSendRights): boolean {
  return rights.voiceNotes || rights.videoNotes;
}

/**
 * 贴纸与 GIF：Android 里它们**不是附件面板的一格**，而是表情面板的页签；页签永远可点，
 * 否决发生在「选中要发出去的那一张」时（MessagesController.java:9230 sendSticker / :9238 sendAnimation）。
 * 所以这两个 key 只喂给 sendVetoLabel，不参与 buildAttachmentEntries。
 */
export const CONTENT_STICKER: string = 'sticker';
export const CONTENT_GIF: string = 'gif';

/** 内容类型 -> 该位的发言权；未知 key 放行（宁可发出去由 TDLib 报错，也不在本地误杀）。 */
export function canSendContent(rights: ChatSendRights, contentKey: string): boolean {
  switch (contentKey) {
    case ATTACHMENT_GALLERY:
      return rights.photos;
    case ATTACHMENT_VIDEO:
      return rights.videos;
    case ATTACHMENT_FILE:
      return rights.documents;
    case ATTACHMENT_POLL:
      return rights.polls;
    case CONTENT_STICKER:
    case CONTENT_GIF:
      return rights.otherMessages;
    default:
      return true;
  }
}

/** 发送时否决的统一入口：返回提示文案表示「不发」，'' 表示放行。 */
export function sendVetoLabel(rights: ChatSendRights, contentKey: string): string {
  return canSendContent(rights, contentKey) ? '' : restrictionSentence(contentKey);
}

/** 受限点击的提示文案；返回 '' 表示该条目其实可用，不该出提示。 */
export function attachmentRestrictionLabel(entry: AttachmentEntry): string {
  return entry.enabled ? '' : restrictionSentence(entry.key);
}

/** 六类受限内容共用一张文案表，避免同一语义在两处各写一遍。 */
function restrictionSentence(contentKey: string): string {
  switch (contentKey) {
    case ATTACHMENT_GALLERY:
      return '此会话不允许发送图片';
    case ATTACHMENT_VIDEO:
      return '此会话不允许发送视频';
    case ATTACHMENT_FILE:
      return '此会话不允许发送文件';
    case ATTACHMENT_POLL:
      return '此会话不允许发起投票';
    case CONTENT_STICKER:
      return '此会话不允许发送贴纸';
    case CONTENT_GIF:
      return '此会话不允许发送 GIF';
    default:
      return '此会话不允许发送该内容';
  }
}
