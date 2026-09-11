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

  constructor(messages: readonly MessageItem[], hasMoreOlder: boolean) {
    this.messages = messages;
    this.hasMoreOlder = hasMoreOlder;
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

  constructor(
    messageId: number,
    canBeEdited: boolean,
    canBeDeletedOnlyForSelf: boolean,
    canBeDeletedForAllUsers: boolean
  ) {
    this.messageId = messageId;
    this.canBeEdited = canBeEdited;
    this.canBeDeletedOnlyForSelf = canBeDeletedOnlyForSelf;
    this.canBeDeletedForAllUsers = canBeDeletedForAllUsers;
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
  | OnVisibleRangeChanged
  | TapFailedMessage
  | OpenMediaViewer
  | CloseMediaViewer
  | ChangeViewerIndex;
