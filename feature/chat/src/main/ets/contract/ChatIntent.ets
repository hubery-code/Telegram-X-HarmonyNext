/**
 * feature/chat — 会话页意图（CHAT-001 + CHAT-003 + CHAT-004）。
 *
 * 用户动作：LoadInitialMessages（首屏加载）、LoadOlderMessages（滚动到顶翻页）、
 * ComposerTextChanged（输入栏文本变化）、SendCurrentMessage（发送当前输入）、
 * BackToChatList（返回会话列表）；系统事件：OnMessagesLoaded /
 * OnMessagesLoadFailed / OnMessageSendFailed 把异步结果回灌 reducer。
 * 每个类带字面量 kind 判别属性。
 *
 * CHAT-004 新增消息动作流：
 * MessageActionRequested（长按气泡）→ FetchMessagePermissions →
 * OnMessageActionMenuLoaded（权限过滤后弹菜单）→ ReplyToMessage / EditMessage /
 * DeleteMessage（菜单点选）；CancelComposerMode / DismissMessageActionMenu 撤销；
 * OnMessageActionFailed 把权限拉取/编辑/删除的失败回灌 errorMessage。
 *
 * MSG-106 新增转发多选流：
 * ForwardMessagesRequested（菜单点选 Forward）→ 进入选择态 →
 * ToggleMessageSelection（点气泡增减）/ ExitMessageSelection（取消）→
 * ConfirmForwardSelection（顶栏 Forward 按钮，请装配层弹会话选择器）→
 * ForwardSelectedToChat（选择器里选中目标会话，带 sendCopy 隐藏来源）→
 * ForwardMessages effect → OnForwardCompleted（退出选择态）/
 * OnForwardFailed（保留选择态便于换目标重试）。
 *
 * MSG-109 新增头部信息区：
 * - OnHeaderSubtitleChanged / OnChatKindChanged：coordinator 计算结果回灌；
 * - OpenChatProfile：点击头部标题开会话资料（纯导航，default 透传）；
 * - ChatMenuAction：⋮ 菜单占位动作统一入口（纯日志，default 透传）。
 */

import { Intent } from '@tgx/feature-template';
import { PinnedMessageInfo } from '../model/PinnedMessageInfo';
import { AppError } from '@tgx/core-common';
import { MessageItem } from '../model/MessageItem';
import { ChatSearchResultItem } from '../model/ChatSearchResultItem';
import { ChatKind } from '../model/SenderInfo';
import { StickerSetPreviewState, StickerSetItem } from '../model/StickerSetPreviewState';
import { GifItem } from '../model/GifItem';

export class LoadInitialMessages implements Intent {
  readonly kind: 'loadInitialMessages' = 'loadInitialMessages';
}

export class LoadOlderMessages implements Intent {
  readonly kind: 'loadOlderMessages' = 'loadOlderMessages';
}

export class OnMessagesLoaded implements Intent {
  readonly kind: 'onMessagesLoaded' = 'onMessagesLoaded';
  readonly messages: readonly MessageItem[];
  readonly hasMoreOlder: boolean;
  readonly lastReadInboxMessageId: number;
  readonly unreadCount: number;

  constructor(
    messages: readonly MessageItem[],
    hasMoreOlder: boolean,
    lastReadInboxMessageId: number = 0,
    unreadCount: number = 0
  ) {
    this.messages = messages;
    this.hasMoreOlder = hasMoreOlder;
    this.lastReadInboxMessageId = lastReadInboxMessageId;
    this.unreadCount = unreadCount;
  }
}

export class OnMessagesLoadFailed implements Intent {
  readonly kind: 'onMessagesLoadFailed' = 'onMessagesLoadFailed';
  readonly error: AppError;

  constructor(error: AppError) {
    this.error = error;
  }
}

export class ComposerTextChanged implements Intent {
  readonly kind: 'composerTextChanged' = 'composerTextChanged';
  readonly text: string;

  constructor(text: string) {
    this.text = text;
  }
}

export class SendCurrentMessage implements Intent {
  readonly kind: 'sendCurrentMessage' = 'sendCurrentMessage';
}

export class OnMessageSendFailed implements Intent {
  readonly kind: 'onMessageSendFailed' = 'onMessageSendFailed';
  readonly error: AppError;

  constructor(error: AppError) {
    this.error = error;
  }
}

export class BackToChatList implements Intent {
  readonly kind: 'backToChatList' = 'backToChatList';
}

/** 长按气泡：请求该消息的操作菜单（先经 effect 拉 TDLib 权限位）。 */
export class MessageActionRequested implements Intent {
  readonly kind: 'messageActionRequested' = 'messageActionRequested';
  readonly messageId: number;

  constructor(messageId: number) {
    this.messageId = messageId;
  }
}

/** getMessageProperties 返回后的原始权限位（过滤在 reducer 内完成）。 */
export class OnMessageActionMenuLoaded implements Intent {
  readonly kind: 'onMessageActionMenuLoaded' = 'onMessageActionMenuLoaded';
  readonly messageId: number;
  readonly canBeEdited: boolean;
  readonly canBeDeletedOnlyForSelf: boolean;
  readonly canBeDeletedForAllUsers: boolean;
  /** MSG-106：can_be_forwarded，决定菜单是否出现 Forward。 */
  readonly canBeForwarded: boolean;
  /** MSG-105：can_be_saved，决定消息内容是否允许在本地保存/复制。 */
  readonly canBeSaved: boolean;
  /** MSG-108：can_be_pinned，决定菜单是否出现 Pin/Unpin。 */
  readonly canBePinned: boolean;
  /** MSG-108：is_pinned，消息当前是否已置顶。 */
  readonly isPinned: boolean;

  constructor(
    messageId: number,
    canBeEdited: boolean,
    canBeDeletedOnlyForSelf: boolean,
    canBeDeletedForAllUsers: boolean,
    canBeForwarded: boolean = false,
    canBeSaved: boolean = true,
    canBePinned: boolean = false,
    isPinned: boolean = false
  ) {
    this.messageId = messageId;
    this.canBeEdited = canBeEdited;
    this.canBeDeletedOnlyForSelf = canBeDeletedOnlyForSelf;
    this.canBeDeletedForAllUsers = canBeDeletedForAllUsers;
    this.canBeForwarded = canBeForwarded;
    this.canBeSaved = canBeSaved;
    this.canBePinned = canBePinned;
    this.isPinned = isPinned;
  }
}

/** 菜单点选：回复 actionMenu.messageId 指定的消息。 */
export class ReplyToMessage implements Intent {
  readonly kind: 'replyToMessage' = 'replyToMessage';
}

/** MSG-105：菜单点选：复制 actionMenu.messageId 指定的消息文本到系统剪贴板。 */
export class CopyMessageText implements Intent {
  readonly kind: 'copyMessageText' = 'copyMessageText';
}

/** MSG-105：菜单点选：复制 actionMenu.messageId 消息中的链接到系统剪贴板。 */
export class CopyMessageLink implements Intent {
  readonly kind: 'copyMessageLink' = 'copyMessageLink';
}

/** 菜单点选：编辑 actionMenu.messageId 指定的消息。 */
export class EditMessage implements Intent {
  readonly kind: 'editMessage' = 'editMessage';
}

/** 菜单点选：删除 actionMenu.messageId 指定的消息（revoke 取菜单状态）。 */
export class DeleteMessage implements Intent {
  readonly kind: 'deleteMessage' = 'deleteMessage';
}

/** MSG-108：菜单点选：置顶 actionMenu.messageId 指定的消息。 */
export class PinMessage implements Intent {
  readonly kind: 'pinMessage' = 'pinMessage';
  readonly disableNotification: boolean;
  readonly onlyForSelf: boolean;

  constructor(disableNotification: boolean = false, onlyForSelf: boolean = false) {
    this.disableNotification = disableNotification;
    this.onlyForSelf = onlyForSelf;
  }
}

/** MSG-108：菜单点选：取消置顶 actionMenu.messageId 指定的消息。 */
export class UnpinMessage implements Intent {
  readonly kind: 'unpinMessage' = 'unpinMessage';
}

/** 撤销输入栏的回复/编辑模式（编辑模式恢复进入前的草稿）。 */
export class CancelComposerMode implements Intent {
  readonly kind: 'cancelComposerMode' = 'cancelComposerMode';
}

/** 关闭操作菜单（点遮罩）。 */
export class DismissMessageActionMenu implements Intent {
  readonly kind: 'dismissMessageActionMenu' = 'dismissMessageActionMenu';
}

/** 权限拉取/编辑/删除请求失败，回灌 errorMessage。 */
export class OnMessageActionFailed implements Intent {
  readonly kind: 'onMessageActionFailed' = 'onMessageActionFailed';
  readonly error: AppError;

  constructor(error: AppError) {
    this.error = error;
  }
}

/**
 * MSG-106：菜单点选 Forward → 进入多选转发态，并以 actionMenu.messageId 预选中。
 * 仅当 actionMenu.showForward 为真时生效（reducer 内校验）。
 */
export class ForwardMessagesRequested implements Intent {
  readonly kind: 'forwardMessagesRequested' = 'forwardMessagesRequested';
}

/** MSG-106：点击气泡切换选中（仅选择态下生效）。 */
export class ToggleMessageSelection implements Intent {
  readonly kind: 'toggleMessageSelection' = 'toggleMessageSelection';
  readonly messageId: number;

  constructor(messageId: number) {
    this.messageId = messageId;
  }
}

/** MSG-106：取消多选转发态（顶栏 Cancel / 返回键）。 */
export class ExitMessageSelection implements Intent {
  readonly kind: 'exitMessageSelection' = 'exitMessageSelection';
}

/**
 * MSG-106：顶栏 Forward 按钮 → 产出 OpenForwardPicker effect，
 * 请装配层（entry）弹出目标会话选择器。选择集为空时不生效。
 */
export class ConfirmForwardSelection implements Intent {
  readonly kind: 'confirmForwardSelection' = 'confirmForwardSelection';
}

/**
 * MSG-106：在会话选择器里选定目标会话 → 产出 ForwardMessages effect。
 * sendCopy=true 即"以副本发送"（隐藏原发送者，Android R.string.SendAsCopy）。
 * 不改选择态：成功由 OnForwardCompleted 收尾，失败保留选择便于换目标重试。
 */
export class ForwardSelectedToChat implements Intent {
  readonly kind: 'forwardSelectedToChat' = 'forwardSelectedToChat';
  readonly toChatId: number;
  readonly sendCopy: boolean;

  constructor(toChatId: number, sendCopy: boolean) {
    this.toChatId = toChatId;
    this.sendCopy = sendCopy;
  }
}

/** MSG-106：转发请求成功 → 退出选择态并清空选择。 */
export class OnForwardCompleted implements Intent {
  readonly kind: 'onForwardCompleted' = 'onForwardCompleted';
  /** 实际转出的消息条数（TDLib 对不可转发的条目回 null）。 */
  readonly forwardedCount: number;

  constructor(forwardedCount: number) {
    this.forwardedCount = forwardedCount;
  }
}

/** MSG-106：转发请求失败 → 回灌 errorMessage，选择态保留。 */
export class OnForwardFailed implements Intent {
  readonly kind: 'onForwardFailed' = 'onForwardFailed';
  readonly error: AppError;

  constructor(error: AppError) {
    this.error = error;
  }
}

/** MSG-104：列表可视范围变化（onScrollIndex）；reducer 出 ReportMessagesRead。 */
export class OnVisibleRangeChanged implements Intent {
  readonly kind: 'onVisibleRangeChanged' = 'onVisibleRangeChanged';
  /** 当前最后可见消息在列表中的下标。 */
  readonly lastVisibleIndex: number;

  constructor(lastVisibleIndex: number) {
    this.lastVisibleIndex = lastVisibleIndex;
  }
}

/** MSG-104：点击发送失败的气泡 → 重发（reducer 出 ResendMessage）。 */
export class TapFailedMessage implements Intent {
  readonly kind: 'tapFailedMessage' = 'tapFailedMessage';
  readonly messageId: number;

  constructor(messageId: number) {
    this.messageId = messageId;
  }
}

/** MEDIA-103：点击多媒体气泡，打开全屏查看器。 */
export class OpenMediaViewer implements Intent {
  readonly kind: 'openMediaViewer' = 'openMediaViewer';
  readonly messageId: number;
  readonly targetFileId?: number;

  constructor(messageId: number, targetFileId?: number) {
    this.messageId = messageId;
    this.targetFileId = targetFileId;
  }
}

/** MEDIA-103：关闭全屏媒体查看器。 */
export class CloseMediaViewer implements Intent {
  readonly kind: 'closeMediaViewer' = 'closeMediaViewer';
}

/** MEDIA-103：全屏查看器左右翻页切换图片。 */
export class ChangeViewerIndex implements Intent {
  readonly kind: 'changeViewerIndex' = 'changeViewerIndex';
  readonly newIndex: number;

  constructor(newIndex: number) {
    this.newIndex = newIndex;
  }
}

/** 按需下载多媒体原文件或大图/视频。 */
export class RequestMediaDownload implements Intent {
  readonly kind: 'requestMediaDownload' = 'requestMediaDownload';
  readonly fileId: number;

  constructor(fileId: number) {
    this.fileId = fileId;
  }
}

/** MEDIA-102：调起相册选取图片并发送（附带当前输入栏草稿作为 caption 与回复引用）。 */
export class PickAndSendPhoto implements Intent {
  readonly kind: 'pickAndSendPhoto' = 'pickAndSendPhoto';
}

/** MEDIA-104：调起文件选择器选取通用文件并发送（附带当前输入栏草稿作为 caption 与回复引用）。 */
export class PickAndSendFile implements Intent {
  readonly kind: 'pickAndSendFile' = 'pickAndSendFile';
}

/** 取消正在上传或待发送的媒体消息并撤回 */
export class CancelMediaUpload implements Intent {
  readonly kind: 'cancelMediaUpload' = 'cancelMediaUpload';
  readonly messageId: number;

  constructor(messageId: number) {
    this.messageId = messageId;
  }
}

/** COMPOSER-101：恢复草稿（草稿文本与回复目标） */
export class RestoreDraft implements Intent {
  readonly kind: 'restoreDraft' = 'restoreDraft';
  readonly draftText: string;
  readonly replyToMessageId: number;

  constructor(draftText: string, replyToMessageId: number = 0) {
    this.draftText = draftText;
    this.replyToMessageId = replyToMessageId;
  }
}

/** COMPOSER-102：打开附件选择面板。 */
export class OpenAttachmentMenu implements Intent {
  readonly kind: 'openAttachmentMenu' = 'openAttachmentMenu';
}

/** COMPOSER-102：关闭附件选择面板。 */
export class CloseAttachmentMenu implements Intent {
  readonly kind: 'closeAttachmentMenu' = 'closeAttachmentMenu';
}

/** COMPOSER-102：切换附件选择面板显隐。 */
export class ToggleAttachmentMenu implements Intent {
  readonly kind: 'toggleAttachmentMenu' = 'toggleAttachmentMenu';
}

/** EMOJI-101：打开表情/贴纸面板。 */
export class OpenEmojiBoard implements Intent {
  readonly kind: 'openEmojiBoard' = 'openEmojiBoard';
}

/** EMOJI-101：关闭表情/贴纸面板。 */
export class CloseEmojiBoard implements Intent {
  readonly kind: 'closeEmojiBoard' = 'closeEmojiBoard';
}

/** EMOJI-101：切换表情/贴纸面板显隐。 */
export class ToggleEmojiBoard implements Intent {
  readonly kind: 'toggleEmojiBoard' = 'toggleEmojiBoard';
}

/** EMOJI-101：从表情面板插入单个 Emoji。 */
export class InsertEmoji implements Intent {
  readonly kind: 'insertEmoji' = 'insertEmoji';
  readonly emoji: string;

  constructor(emoji: string) {
    this.emoji = emoji;
  }
}

/** EMOJI-101：点击表情面板退格键删除末尾字符。 */
export class DeleteLastEmojiChar implements Intent {
  readonly kind: 'deleteLastEmojiChar' = 'deleteLastEmojiChar';
}

/** EMOJI-101：清空最近使用的表情列表。 */
export class ClearRecentEmojis implements Intent {
  readonly kind: 'clearRecentEmojis' = 'clearRecentEmojis';
}

/** FILE-103：取消媒体/文件下载。 */
export class CancelMediaDownload implements Intent {
  readonly kind: 'cancelMediaDownload' = 'cancelMediaDownload';
  readonly fileId: number;

  constructor(fileId: number) {
    this.fileId = fileId;
  }
}

/** FILE-103：重发发送失败的消息（从长按菜单或重试图标触发）。 */
export class ResendFailedMessage implements Intent {
  readonly kind: 'resendFailedMessage' = 'resendFailedMessage';
  readonly messageId: number;

  constructor(messageId: number) {
    this.messageId = messageId;
  }
}

/** SEARCH-102：展开聊天内搜索面板。 */
export class OpenChatSearch implements Intent {
  readonly kind: 'openChatSearch' = 'openChatSearch';
}

/** SEARCH-102：收起聊天内搜索面板并清空结果。 */
export class CloseChatSearch implements Intent {
  readonly kind: 'closeChatSearch' = 'closeChatSearch';
}

/** SEARCH-102：搜索关键词变化（受控输入，reducer 只更新文案并触发执行）。 */
export class ChatSearchQueryChanged implements Intent {
  readonly kind: 'chatSearchQueryChanged' = 'chatSearchQueryChanged';
  readonly query: string;

  constructor(query: string) {
    this.query = query;
  }
}

/** SEARCH-102：执行聊天内搜索（关键词非空时产生 FetchChatSearch effect）。 */
export class PerformChatSearch implements Intent {
  readonly kind: 'performChatSearch' = 'performChatSearch';
}

/** SEARCH-102：搜索完成，回灌命中结果列表。 */
export class OnChatSearchLoaded implements Intent {
  readonly kind: 'onChatSearchLoaded' = 'onChatSearchLoaded';
  readonly results: readonly ChatSearchResultItem[];

  constructor(results: readonly ChatSearchResultItem[]) {
    this.results = results;
  }
}

/** SEARCH-102：搜索失败，回灌错误信息。 */
export class OnChatSearchFailed implements Intent {
  readonly kind: 'onChatSearchFailed' = 'onChatSearchFailed';
  readonly error: AppError;

  constructor(error: AppError) {
    this.error = error;
  }
}

/** SEARCH-102：点击搜索结果，请求跳转定位到该消息（产生 JumpToMessage effect）。 */
export class JumpToSearchResult implements Intent {
  readonly kind: 'jumpToSearchResult' = 'jumpToSearchResult';
  readonly messageId: number;

  constructor(messageId: number) {
    this.messageId = messageId;
  }
}

/** SEARCH-102：围绕目标消息的历史已拉取完成，回灌待定位消息 id 供 UI 滚动。 */
export class OnJumpToMessageReady implements Intent {
  readonly kind: 'onJumpToMessageReady' = 'onJumpToMessageReady';
  readonly messageId: number;

  constructor(messageId: number) {
    this.messageId = messageId;
  }
}

/** SEARCH-102：UI 已完成跳转定位，清除待定位标记。 */
export class ClearJumpToMessage implements Intent {
  readonly kind: 'clearJumpToMessage' = 'clearJumpToMessage';
}

/**
 * PROFILE-101：群聊里点击发送者头像 → 打开该用户资料页。
 * 纯导航意图：reducer 不改状态（default 分支），由 coordinator 转给装配层路由。
 */
export class OpenUserProfile implements Intent {
  readonly kind: 'openUserProfile' = 'openUserProfile';
  readonly userId: number;

  constructor(userId: number) {
    this.userId = userId;
  }
}

/** MSG-109：coordinator 计算出的头部副标题回灌（私聊状态 / 群成员数）。 */
export class OnHeaderSubtitleChanged implements Intent {
  readonly kind: 'onHeaderSubtitleChanged' = 'onHeaderSubtitleChanged';
  readonly subtitle: string;

  constructor(subtitle: string) {
    this.subtitle = subtitle;
  }
}

/** MSG-109：getChat 解析出会话种类后回灌（驱动头部通话按钮与 ⋮ 菜单）。 */
export class OnChatKindChanged implements Intent {
  readonly kind: 'onChatKindChanged' = 'onChatKindChanged';
  readonly chatKind: ChatKind;

  constructor(chatKind: ChatKind) {
    this.chatKind = chatKind;
  }
}

/**
 * MSG-109：点击头部标题 → 打开会话资料页。
 * 纯导航意图：reducer 不改状态（default 分支），由 coordinator 转给装配层路由。
 */
export class OpenChatProfile implements Intent {
  readonly kind: 'openChatProfile' = 'openChatProfile';
  readonly chatId: number;

  constructor(chatId: number) {
    this.chatId = chatId;
  }
}

/**
 * MSG-109：头部 ⋮ 菜单占位动作统一入口（静音/清空历史/删除聊天/举报等）。
 * reducer 不改状态（default 分支），coordinator 只记日志，语义由后续泳道实现。
 */
export class ChatMenuAction implements Intent {
  readonly kind: 'chatMenuAction' = 'chatMenuAction';
  readonly action: string;

  constructor(action: string) {
    this.action = action;
  }
}

/** MSG-108：置顶消息加载回灌。 */
export class OnPinnedMessageLoaded implements Intent {
  readonly kind: 'onPinnedMessageLoaded' = 'onPinnedMessageLoaded';
  readonly pinnedMessage: PinnedMessageInfo | null;

  constructor(pinnedMessage: PinnedMessageInfo | null) {
    this.pinnedMessage = pinnedMessage;
  }
}

/** MSG-108：用户点击 ✕ 临时收起置顶横条。 */
export class DismissPinnedBar implements Intent {
  readonly kind: 'dismissPinnedBar' = 'dismissPinnedBar';
}

/** MSG-108：点击置顶横条，触发跳转至置顶消息并居中高亮。 */
export class JumpToPinnedMessage implements Intent {
  readonly kind: 'jumpToPinnedMessage' = 'jumpToPinnedMessage';
}

/** CHANNEL-101：用户点击底部"加入频道"按钮。 */
export class JoinChannel implements Intent {
  readonly kind: 'joinChannel' = 'joinChannel';
}

/** CHANNEL-101：频道成员状态变化回灌（true=已加入，false=未加入/已离开）。 */
export class OnChannelMemberStatusChanged implements Intent {
  readonly kind: 'onChannelMemberStatusChanged' = 'onChannelMemberStatusChanged';
  readonly isMember: boolean;

  constructor(isMember: boolean) {
    this.isMember = isMember;
  }
}

/** CHANNEL-101：用户点击消息评论入口（"N 条评论"）。 */
export class OpenMessageComments implements Intent {
  readonly kind: 'openMessageComments' = 'openMessageComments';
  readonly messageId: number;

  constructor(messageId: number) {
    this.messageId = messageId;
  }
}

/** CHANNEL-101：用户点击反应 chip 切换 reaction。 */
export class ToggleMessageReaction implements Intent {
  readonly kind: 'toggleMessageReaction' = 'toggleMessageReaction';
  readonly messageId: number;
  readonly emoji: string;

  constructor(messageId: number, emoji: string) {
    this.messageId = messageId;
    this.emoji = emoji;
  }
}

export type ChatIntent =
  | LoadInitialMessages
  | LoadOlderMessages
  | OnMessagesLoaded
  | OnMessagesLoadFailed
  | ComposerTextChanged
  | SendCurrentMessage
  | OnMessageSendFailed
  | BackToChatList
  | MessageActionRequested
  | OnMessageActionMenuLoaded
  | ReplyToMessage
  | CopyMessageText
  | CopyMessageLink
  | EditMessage
  | DeleteMessage
  | CancelComposerMode
  | DismissMessageActionMenu
  | OnMessageActionFailed
  | ForwardMessagesRequested
  | ToggleMessageSelection
  | ExitMessageSelection
  | ConfirmForwardSelection
  | ForwardSelectedToChat
  | OnForwardCompleted
  | OnForwardFailed
  | OnVisibleRangeChanged
  | TapFailedMessage
  | OpenMediaViewer
  | CloseMediaViewer
  | ChangeViewerIndex
  | RequestMediaDownload
  | PickAndSendPhoto
  | PickAndSendFile
  | CancelMediaUpload
  | RestoreDraft
  | OpenAttachmentMenu
  | CloseAttachmentMenu
  | ToggleAttachmentMenu
  | OpenEmojiBoard
  | CloseEmojiBoard
  | ToggleEmojiBoard
  | InsertEmoji
  | DeleteLastEmojiChar
  | ClearRecentEmojis
  | CancelMediaDownload
  | ResendFailedMessage
  | OpenChatSearch
  | CloseChatSearch
  | ChatSearchQueryChanged
  | PerformChatSearch
  | OnChatSearchLoaded
  | OnChatSearchFailed
  | JumpToSearchResult
  | OnJumpToMessageReady
  | ClearJumpToMessage
  | OpenUserProfile
  | OnHeaderSubtitleChanged
  | OnChatKindChanged
  | OpenChatProfile
  | ChatMenuAction
  | OnPinnedMessageLoaded
  | DismissPinnedBar
  | JumpToPinnedMessage
  | PinMessage
  | UnpinMessage
  | JoinChannel
  | OnChannelMemberStatusChanged
  | OpenMessageComments
  | ToggleMessageReaction
  | OpenStickerSet
  | OnStickerSetLoaded
  | OnStickerSetLoadFailed
  | CloseStickerSetPreview
  | InstallStickerSet
  | UninstallStickerSet
  | OnStickerSetChanged
  | OnStickerSetActionFailed
  | SendStickerFromPreview
  | SendSticker
  | ClearRecentStickers
  | SendGif
  | ClearRecentGifs
  | SearchGifs
  | OnStickerPreviewFileUpdated
  | StartVoiceRecord
  | StopAndSendVoiceRecord
  | CancelVoiceRecord
  | VoiceRecordTick
  | PlayVoiceNote
  | PauseVoiceNote
  | VoicePlaybackProgress
  | VoicePlaybackCompleted
  | VoicePlaybackFailed;

/** STICKER-PREVIEW-101：打开贴纸包预览弹窗。 */
export class OpenStickerSet implements Intent {
  readonly kind: 'openStickerSet' = 'openStickerSet';
  readonly setId: string;

  constructor(setId: string) {
    this.setId = setId;
  }
}

/** STICKER-PREVIEW-101：贴纸包详情加载成功。 */
export class OnStickerSetLoaded implements Intent {
  readonly kind: 'onStickerSetLoaded' = 'onStickerSetLoaded';
  readonly preview: StickerSetPreviewState;

  constructor(preview: StickerSetPreviewState) {
    this.preview = preview;
  }
}

/** STICKER-PREVIEW-101：贴纸包详情加载失败。 */
export class OnStickerSetLoadFailed implements Intent {
  readonly kind: 'onStickerSetLoadFailed' = 'onStickerSetLoadFailed';
  readonly setId: string;
  readonly error: string;

  constructor(setId: string, error: string) {
    this.setId = setId;
    this.error = error;
  }
}

/** STICKER-PREVIEW-101：关闭贴纸包详情预览弹窗。 */
export class CloseStickerSetPreview implements Intent {
  readonly kind: 'closeStickerSetPreview' = 'closeStickerSetPreview';
}

/** STICKER-PREVIEW-101：安装贴纸包。 */
export class InstallStickerSet implements Intent {
  readonly kind: 'installStickerSet' = 'installStickerSet';
  readonly setId: string;

  constructor(setId: string) {
    this.setId = setId;
  }
}

/** STICKER-PREVIEW-101：移除贴纸包。 */
export class UninstallStickerSet implements Intent {
  readonly kind: 'uninstallStickerSet' = 'uninstallStickerSet';
  readonly setId: string;

  constructor(setId: string) {
    this.setId = setId;
  }
}

/** STICKER-PREVIEW-101：贴纸包安装状态变更成功回灌。 */
export class OnStickerSetChanged implements Intent {
  readonly kind: 'onStickerSetChanged' = 'onStickerSetChanged';
  readonly setId: string;
  readonly isInstalled: boolean;

  constructor(setId: string, isInstalled: boolean) {
    this.setId = setId;
    this.isInstalled = isInstalled;
  }
}

/** STICKER-PREVIEW-101：贴纸包操作失败回灌。 */
export class OnStickerSetActionFailed implements Intent {
  readonly kind: 'onStickerSetActionFailed' = 'onStickerSetActionFailed';
  readonly setId: string;
  readonly error: string;

  constructor(setId: string, error: string) {
    this.setId = setId;
    this.error = error;
  }
}

/** STICKER-PREVIEW-101：从预览弹窗中直接点选发送贴纸。 */
export class SendStickerFromPreview implements Intent {
  readonly kind: 'sendStickerFromPreview' = 'sendStickerFromPreview';
  readonly item: StickerSetItem;

  constructor(item: StickerSetItem) {
    this.item = item;
  }
}

/** STICKER-101：从贴纸面板中点选发送贴纸。 */
export class SendSticker implements Intent {
  readonly kind: 'sendSticker' = 'sendSticker';
  readonly item: StickerSetItem;

  constructor(item: StickerSetItem) {
    this.item = item;
  }
}

/** STICKER-101：清空最近使用的贴纸列表。 */
export class ClearRecentStickers implements Intent {
  readonly kind: 'clearRecentStickers' = 'clearRecentStickers';
}

/** GIF-101：从动图面板中点选发送动图。 */
export class SendGif implements Intent {
  readonly kind: 'sendGif' = 'sendGif';
  readonly item: GifItem;

  constructor(item: GifItem) {
    this.item = item;
  }
}

/** GIF-101：清空最近使用的动图列表。 */
export class ClearRecentGifs implements Intent {
  readonly kind: 'clearRecentGifs' = 'clearRecentGifs';
}

/** GIF-101：搜索动图关键词。 */
export class SearchGifs implements Intent {
  readonly kind: 'searchGifs' = 'searchGifs';
  readonly query: string;

  constructor(query: string) {
    this.query = query;
  }
}

/** STICKER-PREVIEW-101：贴纸预览文件/缩略图下载完成刷新。 */
export class OnStickerPreviewFileUpdated implements Intent {
  readonly kind: 'onStickerPreviewFileUpdated' = 'onStickerPreviewFileUpdated';
  readonly fileId: number;
  readonly localPath: string;

  constructor(fileId: number, localPath: string) {
    this.fileId = fileId;
    this.localPath = localPath;
  }
}

/** VOICE-101：开始语音录制。 */
export class StartVoiceRecord implements Intent {
  readonly kind: 'startVoiceRecord' = 'startVoiceRecord';
}

/** VOICE-101：停止录音并发送语音消息。 */
export class StopAndSendVoiceRecord implements Intent {
  readonly kind: 'stopAndSendVoiceRecord' = 'stopAndSendVoiceRecord';
}

/** VOICE-101：取消录音并放弃。 */
export class CancelVoiceRecord implements Intent {
  readonly kind: 'cancelVoiceRecord' = 'cancelVoiceRecord';
}

/** VOICE-101：录制计时 Tick。 */
export class VoiceRecordTick implements Intent {
  readonly kind: 'voiceRecordTick' = 'voiceRecordTick';
  readonly durationSec: number;

  constructor(durationSec: number) {
    this.durationSec = durationSec;
  }
}

/** VOICE-101：播放语音消息。 */
export class PlayVoiceNote implements Intent {
  readonly kind: 'playVoiceNote' = 'playVoiceNote';
  readonly messageId: number;
  readonly fileId: number;
  readonly localPath: string | null;

  constructor(messageId: number, fileId: number, localPath: string | null = null) {
    this.messageId = messageId;
    this.fileId = fileId;
    this.localPath = localPath;
  }
}

/** VOICE-101：暂停语音播放。 */
export class PauseVoiceNote implements Intent {
  readonly kind: 'pauseVoiceNote' = 'pauseVoiceNote';
  readonly messageId: number;

  constructor(messageId: number) {
    this.messageId = messageId;
  }
}

/** VOICE-101：语音播放进度回灌。 */
export class VoicePlaybackProgress implements Intent {
  readonly kind: 'voicePlaybackProgress' = 'voicePlaybackProgress';
  readonly messageId: number;
  readonly currentMs: number;
  readonly totalMs: number;

  constructor(messageId: number, currentMs: number, totalMs: number) {
    this.messageId = messageId;
    this.currentMs = currentMs;
    this.totalMs = totalMs;
  }
}

/** VOICE-101：语音播放完成回灌。 */
export class VoicePlaybackCompleted implements Intent {
  readonly kind: 'voicePlaybackCompleted' = 'voicePlaybackCompleted';
  readonly messageId: number;

  constructor(messageId: number) {
    this.messageId = messageId;
  }
}

/** VOICE-101：语音播放失败回灌。 */
export class VoicePlaybackFailed implements Intent {
  readonly kind: 'voicePlaybackFailed' = 'voicePlaybackFailed';
  readonly messageId: number;
  readonly error: string;

  constructor(messageId: number, error: string) {
    this.messageId = messageId;
    this.error = error;
  }
}

