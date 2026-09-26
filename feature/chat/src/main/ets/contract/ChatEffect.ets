/**
 * feature/chat — 会话页副作用描述（CHAT-001 + CHAT-003 + CHAT-004）。
 *
 * Effect 是一次性副作用的描述，由 Coordinator 执行，reducer 严禁执行。
 *
 * CHAT-004 新增：FetchMessagePermissions（长按后拉 TDLib messageProperties
 * 权限位）、EditMessageText（编辑模式发送）、DeleteMessages（删除消息）；
 * SendTextMessage 扩展 replyToMessageId 支持回复。
 *
 * MSG-106 新增：OpenForwardPicker（请求装配层弹出会话选择器）、
 * ForwardMessages（转发到目标会话）。
 */

import { Effect } from '@tgx/feature-template';

export class FetchInitialMessages implements Effect {
  readonly kind: 'fetchInitialMessages' = 'fetchInitialMessages';
  readonly chatId: number;

  constructor(chatId: number) {
    this.chatId = chatId;
  }
}

export class FetchOlderMessages implements Effect {
  readonly kind: 'fetchOlderMessages' = 'fetchOlderMessages';
  readonly chatId: number;

  constructor(chatId: number) {
    this.chatId = chatId;
  }
}

export class SendTextMessage implements Effect {
  readonly kind: 'sendTextMessage' = 'sendTextMessage';
  readonly chatId: number;
  readonly text: string;
  /** 回复目标消息 id；0 = 非回复。 */
  readonly replyToMessageId: number;

  constructor(chatId: number, text: string, replyToMessageId: number = 0) {
    this.chatId = chatId;
    this.text = text;
    this.replyToMessageId = replyToMessageId;
  }
}

export class FetchMessagePermissions implements Effect {
  readonly kind: 'fetchMessagePermissions' = 'fetchMessagePermissions';
  readonly chatId: number;
  readonly messageId: number;

  constructor(chatId: number, messageId: number) {
    this.chatId = chatId;
    this.messageId = messageId;
  }
}

export class EditMessageText implements Effect {
  readonly kind: 'editMessageText' = 'editMessageText';
  readonly chatId: number;
  readonly messageId: number;
  readonly text: string;

  constructor(chatId: number, messageId: number, text: string) {
    this.chatId = chatId;
    this.messageId = messageId;
    this.text = text;
  }
}

export class DeleteMessages implements Effect {
  readonly kind: 'deleteMessages' = 'deleteMessages';
  readonly chatId: number;
  readonly messageIds: number[];
  /** true = 对所有人删除（revoke），false = 仅自己删除。 */
  readonly revoke: boolean;

  constructor(chatId: number, messageIds: number[], revoke: boolean) {
    this.chatId = chatId;
    this.messageIds = messageIds;
    this.revoke = revoke;
  }
}

export class NavigateBack implements Effect {
  readonly kind: 'navigateBack' = 'navigateBack';
}

/**
 * MSG-106：请求弹出会话选择器（转发目标）。选择器 UI 由装配层（entry）渲染
 * ——它同时持有会话列表数据与 ChatCoordinator，是本模块拿不到的组合
 * （feature/* 之间禁止互相依赖）。本 effect 只声明"要给这些消息挑个目标"。
 */
export class OpenForwardPicker implements Effect {
  readonly kind: 'openForwardPicker' = 'openForwardPicker';
  readonly fromChatId: number;
  /** 待转发的消息 id，升序无重复。 */
  readonly messageIds: number[];

  constructor(fromChatId: number, messageIds: number[]) {
    this.fromChatId = fromChatId;
    this.messageIds = messageIds;
  }
}

/** MSG-106：真正执行转发（forwardMessages）。 */
export class ForwardMessages implements Effect {
  readonly kind: 'forwardMessages' = 'forwardMessages';
  readonly fromChatId: number;
  readonly toChatId: number;
  /** 升序无重复（TDLib 要求严格递增）。 */
  readonly messageIds: number[];
  /** true = 以副本发送，隐藏原发送者。 */
  readonly sendCopy: boolean;
  readonly removeCaption: boolean;

  constructor(
    fromChatId: number,
    toChatId: number,
    messageIds: number[],
    sendCopy: boolean,
    removeCaption: boolean = false
  ) {
    this.fromChatId = fromChatId;
    this.toChatId = toChatId;
    this.messageIds = messageIds;
    this.sendCopy = sendCopy;
    this.removeCaption = removeCaption;
  }
}

/** MSG-104：已读上报（viewMessages），上报到 messageId（含）为止。 */
export class ReportMessagesRead implements Effect {
  readonly kind: 'reportMessagesRead' = 'reportMessagesRead';
  readonly chatId: number;
  readonly messageId: number;

  constructor(chatId: number, messageId: number) {
    this.chatId = chatId;
    this.messageId = messageId;
  }
}

/** MSG-104：重发发送失败的消息（resendMessages）。 */
export class ResendMessage implements Effect {
  readonly kind: 'resendMessage' = 'resendMessage';
  readonly chatId: number;
  readonly messageId: number;

  constructor(chatId: number, messageId: number) {
    this.chatId = chatId;
    this.messageId = messageId;
  }
}

/**
 * MSG-105：复制文本到系统剪贴板（pasteboard）并弹出轻提示。
 */
export class CopyTextToClipboard implements Effect {
  readonly kind: 'copyTextToClipboard' = 'copyTextToClipboard';
  readonly text: string;
  readonly toastMessage: string;

  constructor(text: string, toastMessage: string = '已复制到剪贴板') {
    this.text = text;
    this.toastMessage = toastMessage;
  }
}

/** MEDIA-102：调用媒体选择器选图并发送 */
export class PickAndSendPhotoEffect implements Effect {
  readonly kind: 'pickAndSendPhoto' = 'pickAndSendPhoto';
  readonly chatId: number;
  readonly replyToMessageId: number;
  readonly caption: string;

  constructor(chatId: number, replyToMessageId: number = 0, caption: string = '') {
    this.chatId = chatId;
    this.replyToMessageId = replyToMessageId;
    this.caption = caption;
  }
}

/** MEDIA-104：调用媒体选择器选文件并发送 */
export class PickAndSendFileEffect implements Effect {
  readonly kind: 'pickAndSendFile' = 'pickAndSendFile';
  readonly chatId: number;
  readonly replyToMessageId: number;
  readonly caption: string;

  constructor(chatId: number, replyToMessageId: number = 0, caption: string = '') {
    this.chatId = chatId;
    this.replyToMessageId = replyToMessageId;
    this.caption = caption;
  }
}

/** MEDIA-105：调用媒体选择器选视频并发送 */
export class PickAndSendVideoEffect implements Effect {
  readonly kind: 'pickAndSendVideo' = 'pickAndSendVideo';
  readonly chatId: number;
  readonly replyToMessageId: number;
  readonly caption: string;

  constructor(chatId: number, replyToMessageId: number = 0, caption: string = '') {
    this.chatId = chatId;
    this.replyToMessageId = replyToMessageId;
    this.caption = caption;
  }
}

/** FILE-103：取消媒体/文件下载副作用。 */
export class CancelMediaDownloadEffect implements Effect {
  readonly kind: 'cancelMediaDownload' = 'cancelMediaDownload';
  readonly fileId: number;

  constructor(fileId: number) {
    this.fileId = fileId;
  }
}

/** SEARCH-102：执行聊天内搜索（调用 projection.searchMessages，关键词非空）。 */
export class FetchChatSearch implements Effect {
  readonly kind: 'fetchChatSearch' = 'fetchChatSearch';
  readonly chatId: number;
  readonly query: string;
  readonly fromMessageId: number;

  constructor(chatId: number, query: string, fromMessageId: number = 0) {
    this.chatId = chatId;
    this.query = query;
    this.fromMessageId = fromMessageId;
  }
}

/** SEARCH-102：跳转定位到目标消息（调用 projection.loadHistoryAround 拉取历史后滚动）。 */
export class JumpToMessage implements Effect {
  readonly kind: 'jumpToMessage' = 'jumpToMessage';
  readonly messageId: number;

  constructor(messageId: number) {
    this.messageId = messageId;
  }
}

/** CHANNEL-101：调用 TDLib joinChat 加入频道。 */
export class JoinChannelEffect implements Effect {
  readonly kind: 'joinChannel' = 'joinChannel';
  readonly chatId: number;

  constructor(chatId: number) {
    this.chatId = chatId;
  }
}

/** CHANNEL-101：调用 TDLib addMessageReaction / removeMessageReaction 切换反应。 */
export class ToggleReactionEffect implements Effect {
  readonly kind: 'toggleReaction' = 'toggleReaction';
  readonly chatId: number;
  readonly messageId: number;
  readonly emoji: string;
  readonly isChosen: boolean;

  constructor(chatId: number, messageId: number, emoji: string, isChosen: boolean) {
    this.chatId = chatId;
    this.messageId = messageId;
    this.emoji = emoji;
    this.isChosen = isChosen;
  }
}

/** CHANNEL-101：打开消息评论（导航或日志）。 */
export class OpenCommentsEffect implements Effect {
  readonly kind: 'openComments' = 'openComments';
  readonly chatId: number;
  readonly messageId: number;

  constructor(chatId: number, messageId: number) {
    this.chatId = chatId;
    this.messageId = messageId;
  }
}

/** STICKER-PREVIEW-101：向 TDLib 请求贴纸包详情。 */
/** STICKER-BOARD-101：向 TDLib 取已安装贴纸包（getInstalledStickerSets, regular）。 */
export class FetchStickerBoard implements Effect {
  readonly kind: 'fetchStickerBoard' = 'fetchStickerBoard';
}

/** STICKER-BOARD-102：向 TDLib 取热门贴纸包（getTrendingStickerSets, regular）。 */
export class FetchTrendingStickerSets implements Effect {
  readonly kind: 'fetchTrendingStickerSets' = 'fetchTrendingStickerSets';
}

/** STICKER-RECENT-101：向 TDLib 取最近使用的贴纸（getRecentStickers, is_attached=false）。 */
export class FetchRecentStickers implements Effect {
  readonly kind: 'fetchRecentStickers' = 'fetchRecentStickers';
}

/**
 * STICKER-RECENT-101：把「清空最近使用」写回 TDLib（clearRecentStickers, is_attached=false）。
 * 本地列表由 reducer 立刻清空（Android 也是先撤 UI 再发请求），这一条只负责服务端那半边。
 */
export class ClearRecentStickersInTdlib implements Effect {
  readonly kind: 'clearRecentStickersInTdlib' = 'clearRecentStickersInTdlib';
}

export class FetchStickerSet implements Effect {
  readonly kind: 'fetchStickerSet' = 'fetchStickerSet';
  readonly setId: string;

  constructor(setId: string) {
    this.setId = setId;
  }
}

/** STICKER-PREVIEW-101：向 TDLib 请求安装/移除贴纸包。 */
export class ChangeStickerSetEffect implements Effect {
  readonly kind: 'changeStickerSetEffect' = 'changeStickerSetEffect';
  readonly setId: string;
  readonly isInstalled: boolean;

  constructor(setId: string, isInstalled: boolean) {
    this.setId = setId;
    this.isInstalled = isInstalled;
  }
}

/** STICKER-PREVIEW-101：向当前会话发送贴纸。 */
export class SendStickerMessage implements Effect {
  readonly kind: 'sendStickerMessage' = 'sendStickerMessage';
  readonly chatId: number;
  readonly fileId: number;
  readonly width: number;
  readonly height: number;
  readonly emoji: string;

  constructor(chatId: number, fileId: number, width: number, height: number, emoji: string) {
    this.chatId = chatId;
    this.fileId = fileId;
    this.width = width;
    this.height = height;
    this.emoji = emoji;
  }
}

/** GIF-101：向当前会话发送动图/Animation。 */
export class SendAnimationMessage implements Effect {
  readonly kind: 'sendAnimationMessage' = 'sendAnimationMessage';
  readonly chatId: number;
  readonly fileId: number;
  readonly width: number;
  readonly height: number;
  readonly caption: string;

  constructor(chatId: number, fileId: number, width: number, height: number, caption: string = '') {
    this.chatId = chatId;
    this.fileId = fileId;
    this.width = width;
    this.height = height;
    this.caption = caption;
  }
}

/** MSG-108：置顶消息（pinChatMessage）。 */
export class PinMessageEffect implements Effect {
  readonly kind: 'pinMessageEffect' = 'pinMessageEffect';
  readonly chatId: number;
  readonly messageId: number;
  readonly disableNotification: boolean;
  readonly onlyForSelf: boolean;

  constructor(chatId: number, messageId: number, disableNotification: boolean = false, onlyForSelf: boolean = false) {
    this.chatId = chatId;
    this.messageId = messageId;
    this.disableNotification = disableNotification;
    this.onlyForSelf = onlyForSelf;
  }
}

/** MSG-108：取消置顶消息（unpinChatMessage）。 */
export class UnpinMessageEffect implements Effect {
  readonly kind: 'unpinMessageEffect' = 'unpinMessageEffect';
  readonly chatId: number;
  readonly messageId: number;

  constructor(chatId: number, messageId: number) {
    this.chatId = chatId;
    this.messageId = messageId;
  }
}

/** VOICE-101：开始录音副作用。 */
export class StartVoiceRecordEffect implements Effect {
  readonly kind: 'startVoiceRecordEffect' = 'startVoiceRecordEffect';
  readonly chatId: number;

  constructor(chatId: number) {
    this.chatId = chatId;
  }
}

/** VOICE-101：停止录音并发送副作用。 */
export class StopAndSendVoiceRecordEffect implements Effect {
  readonly kind: 'stopAndSendVoiceRecordEffect' = 'stopAndSendVoiceRecordEffect';
  readonly chatId: number;
  readonly replyToMessageId: number;

  constructor(chatId: number, replyToMessageId: number = 0) {
    this.chatId = chatId;
    this.replyToMessageId = replyToMessageId;
  }
}

/** VOICE-101：取消录音副作用。 */
export class CancelVoiceRecordEffect implements Effect {
  readonly kind: 'cancelVoiceRecordEffect' = 'cancelVoiceRecordEffect';
  readonly chatId: number;

  constructor(chatId: number) {
    this.chatId = chatId;
  }
}

/** VOICE-101：播放语音消息副作用。 */
export class PlayVoiceNoteEffect implements Effect {
  readonly kind: 'playVoiceNoteEffect' = 'playVoiceNoteEffect';
  readonly chatId: number;
  readonly messageId: number;
  readonly fileId: number;
  readonly localPath: string | null;

  constructor(chatId: number, messageId: number, fileId: number, localPath: string | null = null) {
    this.chatId = chatId;
    this.messageId = messageId;
    this.fileId = fileId;
    this.localPath = localPath;
  }
}

/** VOICE-101：暂停语音播放副作用。 */
export class PauseVoiceNoteEffect implements Effect {
  readonly kind: 'pauseVoiceNoteEffect' = 'pauseVoiceNoteEffect';
  readonly chatId: number;
  readonly messageId: number;

  constructor(chatId: number, messageId: number) {
    this.chatId = chatId;
    this.messageId = messageId;
  }
}

export type ChatEffect =
  | FetchInitialMessages
  | FetchOlderMessages
  | SendTextMessage
  | FetchMessagePermissions
  | EditMessageText
  | DeleteMessages
  | NavigateBack
  | OpenForwardPicker
  | ForwardMessages
  | ReportMessagesRead
  | ResendMessage
  | CopyTextToClipboard
  | PickAndSendPhotoEffect
  | PickAndSendFileEffect
  | PickAndSendVideoEffect
  | CancelMediaDownloadEffect
  | FetchChatSearch
  | JumpToMessage
  | PinMessageEffect
  | UnpinMessageEffect
  | JoinChannelEffect
  | ToggleReactionEffect
  | OpenCommentsEffect
  | FetchStickerBoard
  | FetchTrendingStickerSets
  | FetchRecentStickers
  | ClearRecentStickersInTdlib
  | FetchStickerSet
  | ChangeStickerSetEffect
  | SendStickerMessage
  | SendAnimationMessage
  | StartVoiceRecordEffect
  | StopAndSendVoiceRecordEffect
  | CancelVoiceRecordEffect
  | PlayVoiceNoteEffect
  | PauseVoiceNoteEffect
  | SendPollEffect
  | SetPollAnswerEffect;


/** POLL-101：发送投票消息（messagePoll）。 */
export class SendPollEffect implements Effect {
  readonly kind: 'sendPoll' = 'sendPoll';
  readonly chatId: number;
  readonly question: string;
  readonly options: string[];
  readonly isAnonymous: boolean;
  readonly allowsMultiple: boolean;

  constructor(chatId: number, question: string, options: string[], isAnonymous: boolean, allowsMultiple: boolean) {
    this.chatId = chatId;
    this.question = question;
    this.options = options;
    this.isAnonymous = isAnonymous;
    this.allowsMultiple = allowsMultiple;
  }
}

/** POLL-101：提交投票（setPollAnswer；optionIds 为切换后的完整 0-based 选项集合）。 */
export class SetPollAnswerEffect implements Effect {
  readonly kind: 'setPollAnswer' = 'setPollAnswer';
  readonly chatId: number;
  readonly messageId: number;
  readonly optionIds: number[];

  constructor(chatId: number, messageId: number, optionIds: number[]) {
    this.chatId = chatId;
    this.messageId = messageId;
    this.optionIds = optionIds;
  }
}
