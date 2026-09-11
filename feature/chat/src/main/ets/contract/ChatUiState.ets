/**
 * feature/chat — 会话页可观察状态（CHAT-001 + CHAT-003 + CHAT-004）。
 *
 * 遵循计划 §5.11 / UI-003：所有字段只读，不可变更新经 copyWith() 派生。
 * messages 按时间升序（最旧在前），渲染层倒置显示最新在底。
 * composerText 驱动底部输入栏（受控输入），发送后立即清空。
 *
 * CHAT-004 新增：
 * - composerMode：输入栏模式（回复/编辑），null=普通发送。编辑模式进入时把
 *   原草稿存进 draftBackup，取消或发出后恢复；
 * - actionMenu：长按气泡的操作菜单状态（已按权限过滤好可见项），null=不显示。
 */

import { UiState } from '@tgx/feature-template';
import { MessageItem } from '../model/MessageItem';
import { MediaViewerItem } from '../model/MediaViewerItem';

/** 输入栏模式：回复某条消息。 */
export class ComposerReplyMode {
  readonly kind: 'reply' = 'reply';
  readonly targetMessageId: number;
  /** 预览条标题（如 "Reply to Alice"）。 */
  readonly previewTitle: string;
  /** 预览条摘要（被回复消息正文截断）。 */
  readonly previewText: string;

  constructor(targetMessageId: number, previewTitle: string, previewText: string) {
    this.targetMessageId = targetMessageId;
    this.previewTitle = previewTitle;
    this.previewText = previewText;
  }
}

/** 输入栏模式：编辑某条消息。draftBackup 暂存进入编辑前的草稿，取消/发出后恢复。 */
export class ComposerEditMode {
  readonly kind: 'edit' = 'edit';
  readonly targetMessageId: number;
  /** 预览条摘要（被编辑消息的原文截断）。 */
  readonly previewText: string;
  readonly draftBackup: string;

  constructor(targetMessageId: number, previewText: string, draftBackup: string) {
    this.targetMessageId = targetMessageId;
    this.previewText = previewText;
    this.draftBackup = draftBackup;
  }
}

export type ComposerMode = ComposerReplyMode | ComposerEditMode;

/**
 * 长按气泡的操作菜单状态。可见项已在 reducer 内按权限过滤：
 * - showReply 恒 true（计划约定回复始终可用）；
 * - showEdit 仅自己发出的文本消息且 canBeEdited；
 * - showDelete 仅 canBeDeletedOnlyForSelf || canBeDeletedForAllUsers；
 * - deleteRevoke 为删除时使用的 revoke 参数（= canBeDeletedForAllUsers）。
 */
export class MessageActionMenuState {
  readonly messageId: number;
  readonly showReply: boolean;
  readonly showEdit: boolean;
  readonly showDelete: boolean;
  readonly deleteRevoke: boolean;

  constructor(
    messageId: number,
    showReply: boolean,
    showEdit: boolean,
    showDelete: boolean,
    deleteRevoke: boolean
  ) {
    this.messageId = messageId;
    this.showReply = showReply;
    this.showEdit = showEdit;
    this.showDelete = showDelete;
    this.deleteRevoke = deleteRevoke;
  }
}

export interface ChatUiStateOptions {
  readonly chatTitle?: string;
  readonly messages?: readonly MessageItem[];
  readonly isLoading?: boolean;
  readonly hasMoreOlder?: boolean;
  readonly errorMessage?: string | null;
  readonly composerText?: string;
  readonly composerMode?: ComposerMode | null;
  readonly actionMenu?: MessageActionMenuState | null;
  readonly activeViewerIndex?: number;
  readonly viewerItems?: MediaViewerItem[];
}

export class ChatUiState implements UiState {
  readonly chatId: number;
  readonly chatTitle: string;
  readonly messages: readonly MessageItem[];
  readonly isLoading: boolean;
  readonly hasMoreOlder: boolean;
  readonly errorMessage: string | null;
  readonly composerText: string;
  readonly composerMode: ComposerMode | null;
  readonly actionMenu: MessageActionMenuState | null;
  readonly activeViewerIndex: number; // -1 表示关闭，>= 0 表示当前画廊索引
  readonly viewerItems: MediaViewerItem[];

  constructor(
    chatId: number,
    chatTitle: string,
    messages: readonly MessageItem[],
    isLoading: boolean,
    hasMoreOlder: boolean,
    errorMessage: string | null,
    composerText: string,
    composerMode: ComposerMode | null,
    actionMenu: MessageActionMenuState | null,
    activeViewerIndex: number = -1,
    viewerItems: MediaViewerItem[] = []
  ) {
    this.chatId = chatId;
    this.chatTitle = chatTitle;
    this.messages = messages;
    this.isLoading = isLoading;
    this.hasMoreOlder = hasMoreOlder;
    this.errorMessage = errorMessage;
    this.composerText = composerText;
    this.composerMode = composerMode;
    this.actionMenu = actionMenu;
    this.activeViewerIndex = activeViewerIndex;
    this.viewerItems = viewerItems;
  }

  static initial(): ChatUiState {
    return new ChatUiState(0, '', [], false, true, null, '', null, null, -1, []);
  }

  copyWith(options: ChatUiStateOptions): ChatUiState {
    return new ChatUiState(
      this.chatId,
      options.chatTitle !== undefined ? options.chatTitle : this.chatTitle,
      options.messages !== undefined ? options.messages : this.messages,
      options.isLoading !== undefined ? options.isLoading : this.isLoading,
      options.hasMoreOlder !== undefined ? options.hasMoreOlder : this.hasMoreOlder,
      options.errorMessage !== undefined ? options.errorMessage : this.errorMessage,
      options.composerText !== undefined ? options.composerText : this.composerText,
      options.composerMode !== undefined ? options.composerMode : this.composerMode,
      options.actionMenu !== undefined ? options.actionMenu : this.actionMenu,
      options.activeViewerIndex !== undefined ? options.activeViewerIndex : this.activeViewerIndex,
      options.viewerItems !== undefined ? options.viewerItems : this.viewerItems
    );
  }
}
