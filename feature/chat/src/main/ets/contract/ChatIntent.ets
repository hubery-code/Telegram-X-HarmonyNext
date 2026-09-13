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
 */

import { Intent } from '@tgx/feature-template';
import { AppError } from '@tgx/core-common';
import { MessageItem } from '../model/MessageItem';

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

  constructor(
    messageId: number,
    canBeEdited: boolean,
    canBeDeletedOnlyForSelf: boolean,
    canBeDeletedForAllUsers: boolean,
    canBeForwarded: boolean = false
  ) {
    this.messageId = messageId;
    this.canBeEdited = canBeEdited;
    this.canBeDeletedOnlyForSelf = canBeDeletedOnlyForSelf;
    this.canBeDeletedForAllUsers = canBeDeletedForAllUsers;
    this.canBeForwarded = canBeForwarded;
  }
}

/** 菜单点选：回复 actionMenu.messageId 指定的消息。 */
export class ReplyToMessage implements Intent {
  readonly kind: 'replyToMessage' = 'replyToMessage';
}

/** 菜单点选：编辑 actionMenu.messageId 指定的消息。 */
export class EditMessage implements Intent {
  readonly kind: 'editMessage' = 'editMessage';
}

/** 菜单点选：删除 actionMenu.messageId 指定的消息（revoke 取菜单状态）。 */
export class DeleteMessage implements Intent {
  readonly kind: 'deleteMessage' = 'deleteMessage';
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

  constructor(messageId: number) {
    this.messageId = messageId;
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
  | RequestMediaDownload;
