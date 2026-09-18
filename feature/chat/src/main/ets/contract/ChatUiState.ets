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
 *
 * MSG-109 新增：
 * - headerSubtitle：头部副标题（私聊在线状态 / 群成员数；空串=不显示），
 *   由 coordinator 计算后经 OnHeaderSubtitleChanged 回灌；
 * - chatKind：会话种类（private/group/channel/unknown），getChat 解析后由
 *   OnChatKindChanged 回灌，驱动头部通话按钮与 ⋮ 菜单项。
 */

import { UiState } from '@tgx/feature-template';
import { MessageItem } from '../model/MessageItem';
import { MediaViewerItem } from '../model/MediaViewerItem';
import { ChatSearchResultItem } from '../model/ChatSearchResultItem';
import { ChatKind } from '../model/SenderInfo';
import { PinnedMessageInfo } from '../model/PinnedMessageInfo';
import { StickerSetPreviewState } from '../model/StickerSetPreviewState';

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
  readonly showResend: boolean;
  /** MSG-108：是否允许置顶/取消置顶（messageProperties.can_be_pinned）。 */
  readonly showPin: boolean;
  /** MSG-108：消息当前是否已置顶（Message.is_pinned）。 */
  readonly isPinned: boolean;

  constructor(
    messageId: number,
    showReply: boolean,
    showEdit: boolean,
    showDelete: boolean,
    deleteRevoke: boolean,
    showForward: boolean = false,
    showCopy: boolean = false,
    showCopyLink: boolean = false,
    linkUrlToCopy: string | null = null,
    showResend: boolean = false,
    showPin: boolean = false,
    isPinned: boolean = false
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
    this.showResend = showResend;
    this.showPin = showPin;
    this.isPinned = isPinned;
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
  readonly showAttachmentMenu?: boolean;
  /** SEARCH-102：聊天内搜索面板是否展开。 */
  readonly showSearch?: boolean;
  /** SEARCH-102：搜索关键词。 */
  readonly searchQuery?: string;
  /** SEARCH-102：搜索命中结果列表。 */
  readonly searchResults?: readonly ChatSearchResultItem[];
  /** SEARCH-102：搜索请求是否在途。 */
  readonly isSearching?: boolean;
  /** SEARCH-102：待跳转定位的消息 id（0=无；loadHistoryAround 完成后回灌）。 */
  readonly jumpToMessageId?: number;
  /** MSG-109：头部副标题（私聊在线状态 / 群成员数等；空串=不显示）。 */
  readonly headerSubtitle?: string;
  /** MSG-109：会话种类（驱动头部通话按钮与 ⋮ 菜单项）。 */
  readonly chatKind?: ChatKind;
  /** MSG-108：当前会话置顶消息摘要（null=无置顶消息）。 */
  readonly pinnedMessage?: PinnedMessageInfo | null;
  /** MSG-108：置顶消息横条可见性（用户点击 ✕ 可临时收起）。 */
  readonly showPinnedBar?: boolean;
  /** CHANNEL-101：是否已加入频道（未加入频道时底栏显示"加入频道"按钮）。 */
  readonly isChannelMember?: boolean;
  /** EMOJI-101：表情/贴纸面板是否展开。 */
  readonly showEmojiBoard?: boolean;
  /** STICKER-PREVIEW-101：贴纸包详情预览状态（null=不显示弹窗）。 */
  readonly stickerSetPreview?: StickerSetPreviewState | null;
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
  /** COMPOSER-102：附件选择面板是否展示。 */
  readonly showAttachmentMenu: boolean;
  /** SEARCH-102：聊天内搜索面板是否展开。 */
  readonly showSearch: boolean;
  /** SEARCH-102：搜索关键词。 */
  readonly searchQuery: string;
  /** SEARCH-102：搜索命中结果列表。 */
  readonly searchResults: readonly ChatSearchResultItem[];
  /** SEARCH-102：搜索请求是否在途。 */
  readonly isSearching: boolean;
  /** SEARCH-102：待跳转定位的消息 id（0=无；loadHistoryAround 完成后回灌）。 */
  readonly jumpToMessageId: number;
  /** MSG-109：头部副标题（私聊在线状态 / 群成员数等；空串=不显示）。 */
  readonly headerSubtitle: string;
  /** MSG-109：会话种类（驱动头部通话按钮与 ⋮ 菜单项）。 */
  readonly chatKind: ChatKind;
  /** MSG-108：当前会话置顶消息摘要（null=无置顶消息）。 */
  readonly pinnedMessage: PinnedMessageInfo | null;
  /** MSG-108：置顶消息横条可见性（用户点击 ✕ 可临时收起）。 */
  readonly showPinnedBar: boolean;
  /** CHANNEL-101：是否已加入频道（未加入频道时底栏显示"加入频道"按钮）。 */
  readonly isChannelMember: boolean;
  /** EMOJI-101：表情/贴纸面板是否展开。 */
  readonly showEmojiBoard: boolean;
  /** STICKER-PREVIEW-101：贴纸包详情预览状态（null=不显示弹窗）。 */
  readonly stickerSetPreview: StickerSetPreviewState | null;

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
    selectedMessageIds: readonly number[] = [],
    showAttachmentMenu: boolean = false,
    showSearch: boolean = false,
    searchQuery: string = '',
    searchResults: readonly ChatSearchResultItem[] = [],
    isSearching: boolean = false,
    jumpToMessageId: number = 0,
    headerSubtitle: string = '',
    chatKind: ChatKind = 'unknown',
    pinnedMessage: PinnedMessageInfo | null = null,
    showPinnedBar: boolean = false,
    isChannelMember: boolean = true,
    showEmojiBoard: boolean = false,
    stickerSetPreview: StickerSetPreviewState | null = null
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
    this.showAttachmentMenu = showAttachmentMenu;
    this.showSearch = showSearch;
    this.searchQuery = searchQuery;
    this.searchResults = searchResults;
    this.isSearching = isSearching;
    this.jumpToMessageId = jumpToMessageId;
    this.headerSubtitle = headerSubtitle;
    this.chatKind = chatKind;
    this.pinnedMessage = pinnedMessage;
    this.showPinnedBar = showPinnedBar;
    this.isChannelMember = isChannelMember;
    this.showEmojiBoard = showEmojiBoard;
    this.stickerSetPreview = stickerSetPreview;
  }

  static initial(): ChatUiState {
    return new ChatUiState(0, '', [], false, true, null, '', null, null, -1, [], 0, 0, false, [], false, false, '', [], false, 0, '', 'unknown', null, false, true, false, null);
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
      options.selectedMessageIds !== undefined ? options.selectedMessageIds : this.selectedMessageIds,
      options.showAttachmentMenu !== undefined ? options.showAttachmentMenu : this.showAttachmentMenu,
      options.showSearch !== undefined ? options.showSearch : this.showSearch,
      options.searchQuery !== undefined ? options.searchQuery : this.searchQuery,
      options.searchResults !== undefined ? options.searchResults : this.searchResults,
      options.isSearching !== undefined ? options.isSearching : this.isSearching,
      options.jumpToMessageId !== undefined ? options.jumpToMessageId : this.jumpToMessageId,
      options.headerSubtitle !== undefined ? options.headerSubtitle : this.headerSubtitle,
      options.chatKind !== undefined ? options.chatKind : this.chatKind,
      options.pinnedMessage !== undefined ? options.pinnedMessage : this.pinnedMessage,
      options.showPinnedBar !== undefined ? options.showPinnedBar : this.showPinnedBar,
      options.isChannelMember !== undefined ? options.isChannelMember : this.isChannelMember,
      options.showEmojiBoard !== undefined ? options.showEmojiBoard : this.showEmojiBoard,
      options.stickerSetPreview !== undefined ? options.stickerSetPreview : this.stickerSetPreview
    );
  }
}
