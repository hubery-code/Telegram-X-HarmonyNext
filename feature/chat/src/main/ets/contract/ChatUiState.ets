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
 *
 * MSG-106 新增：
 * - selectionMode/selectedMessageIds：多选转发选择态。selectionMode=true 时
 *   点击气泡改为切换选中而非触发其它动作；selectedMessageIds 恒升序无重复
 *   （TDLib forwardMessages 要求 message_ids 严格递增）；
 * - MessageActionMenuState.showForward：由 messageProperties.can_be_forwarded
 *   过滤，禁止转发的消息（如受保护内容）不出现 Forward 项。
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
 * - deleteRevoke 为删除时使用的 revoke 参数（= canBeDeletedForAllUsers）；
 * - showForward 仅 canBeForwarded（MSG-106）；
 * - showCopy 仅 canBeSaved 且消息含有非空文本（MSG-105）；
 * - showCopyLink 仅 canBeSaved 且消息含有可复制链接（MSG-105）。
 */
export class MessageActionMenuState {
  readonly messageId: number;
  readonly showReply: boolean;
  readonly showEdit: boolean;
  readonly showDelete: boolean;
  readonly deleteRevoke: boolean;
  readonly showForward: boolean;
  readonly showCopy: boolean;
  readonly showCopyLink: boolean;
  readonly linkUrlToCopy: string | null;

  constructor(
    messageId: number,
    showReply: boolean,
    showEdit: boolean,
    showDelete: boolean,
    deleteRevoke: boolean,
    showForward: boolean = false,
    showCopy: boolean = false,
    showCopyLink: boolean = false,
    linkUrlToCopy: string | null = null
  ) {
    this.messageId = messageId;
    this.showReply = showReply;
    this.showEdit = showEdit;
    this.showDelete = showDelete;
    this.deleteRevoke = deleteRevoke;
    this.showForward = showForward;
    this.showCopy = showCopy;
    this.showCopyLink = showCopyLink;
    this.linkUrlToCopy = linkUrlToCopy;
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
  readonly lastReadInboxMessageId?: number;
  readonly unreadCount?: number;
  readonly selectionMode?: boolean;
  readonly selectedMessageIds?: readonly number[];
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
  readonly lastReadInboxMessageId: number; // 0 表示无/未知
  readonly unreadCount: number; // 0 表示已全部读完
  /** MSG-106：多选转发选择态是否激活。 */
  readonly selectionMode: boolean;
  /** MSG-106：已选消息 id，恒升序无重复。 */
  readonly selectedMessageIds: readonly number[];

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
    viewerItems: MediaViewerItem[] = [],
    lastReadInboxMessageId: number = 0,
    unreadCount: number = 0,
    selectionMode: boolean = false,
    selectedMessageIds: readonly number[] = []
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
    this.lastReadInboxMessageId = lastReadInboxMessageId;
    this.unreadCount = unreadCount;
    this.selectionMode = selectionMode;
    this.selectedMessageIds = selectedMessageIds;
  }

  static initial(): ChatUiState {
    return new ChatUiState(0, '', [], false, true, null, '', null, null, -1, [], 0, 0, false, []);
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
      options.viewerItems !== undefined ? options.viewerItems : this.viewerItems,
      options.lastReadInboxMessageId !== undefined ? options.lastReadInboxMessageId : this.lastReadInboxMessageId,
      options.unreadCount !== undefined ? options.unreadCount : this.unreadCount,
      options.selectionMode !== undefined ? options.selectionMode : this.selectionMode,
      options.selectedMessageIds !== undefined ? options.selectedMessageIds : this.selectedMessageIds
    );
  }
}
