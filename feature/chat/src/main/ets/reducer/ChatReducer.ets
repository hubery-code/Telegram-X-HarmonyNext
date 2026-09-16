/**
 * feature/chat — 会话页纯 Reducer（CHAT-001 + CHAT-003 + CHAT-004）。
 *
 * 遵循计划 §5.11 / UI-003：
 * - 纯函数：(state, intent, env) -> ReducerResult<ChatUiState, ChatEffect>
 * - 禁止直接修改 state；无变化返回原引用 reduced(state)
 * - 禁止在 reducer 内做 I/O 或异步，加载请求只产出 Fetch* 描述
 *
 * CHAT-004 新增消息动作流：
 * - messageActionRequested → 只产出 FetchMessagePermissions（权限位由 TDLib
 *   getMessageProperties 离线计算）；
 * - onMessageActionMenuLoaded → 权限过滤（回复恒可；编辑仅己方文本消息且
 *   canBeEdited；删除需 canBeDeletedOnlyForSelf || canBeDeletedForAllUsers）
 *   生成 MessageActionMenuState；
 * - replyToMessage / editMessage 进入输入栏回复/编辑模式；编辑模式进入时把
 *   当前草稿存进 draftBackup，cancelComposerMode / backToChatList（返回键优先
 *   退出模式）取消时恢复；
 * - sendCurrentMessage 按模式分流：edit → EditMessageText（发出后恢复草稿），
 *   reply → SendTextMessage 带 replyToMessageId；
 * - deleteMessage → DeleteMessages(chatId, [id], revoke=canBeDeletedForAllUsers)；
 * - onMessageActionFailed → errorMessage 细条提示。
 *
 * MSG-106 新增转发多选流：
 * - forwardMessagesRequested → 进入选择态并预选中 actionMenu 的消息（需
 *   showForward，即 can_be_forwarded）；
 * - toggleMessageSelection → 增删选中；取消掉最后一条即自动退出选择态
 *   （Telegram X 行为）；
 * - forwardSelectedToChat → OpenForwardPicker 之前先产出选择器请求，选定后
 *   由 ForwardMessages effect 执行；成功 OnForwardCompleted 退出选择态，
 *   失败 OnForwardFailed 只提示、保留选择便于换目标重试；
 * - onMessagesLoaded 收敛选择集合（选中期间消息被删/撤回时剔除）；
 * - backToChatList 优先退出选择态（在操作菜单之后、输入栏模式之前）。
 *
 * MSG-109 头部信息区：
 * - onHeaderSubtitleChanged / onChatKindChanged：coordinator 计算结果回灌，
 *   值相同返回原引用；
 * - openChatProfile / chatMenuAction：纯导航/占位意图不改状态、无 effect
 *   （switch 无匹配分支，落到末尾 reduced(state) 透传）。
 */

import { Reducer, ReducerEnv, ReducerResult, reduced } from '@tgx/feature-template';
import {
  ChatUiState,
  ComposerEditMode,
  ComposerMode,
  ComposerReplyMode,
  MessageActionMenuState
} from '../contract/ChatUiState';
import { MessageItem } from '../model/MessageItem';
import { MediaViewerItem } from '../model/MediaViewerItem';
import { MediaAttachment } from '../model/MediaAttachment';
import {
  ChatIntent,
  OnMessagesLoaded,
  OnMessagesLoadFailed,
  ComposerTextChanged,
  OnMessageSendFailed,
  MessageActionRequested,
  OnMessageActionMenuLoaded,
  OnMessageActionFailed,
  CopyMessageText,
  CopyMessageLink,
  ForwardMessagesRequested,
  ToggleMessageSelection,
  ForwardSelectedToChat,
  OnForwardCompleted,
  OnForwardFailed,
  OnVisibleRangeChanged,
  TapFailedMessage,
  OpenMediaViewer,
  CloseMediaViewer,
  ChangeViewerIndex,
  CancelMediaUpload,
  RestoreDraft,
  CancelMediaDownload,
  ResendFailedMessage,
  ChatSearchQueryChanged,
  OnChatSearchLoaded,
  OnChatSearchFailed,
  JumpToSearchResult,
  OnJumpToMessageReady,
  OnHeaderSubtitleChanged,
  OnChatKindChanged
} from '../contract/ChatIntent';
import {
  ChatEffect,
  FetchInitialMessages,
  FetchOlderMessages,
  SendTextMessage,
  FetchMessagePermissions,
  EditMessageText,
  DeleteMessages,
  NavigateBack,
  OpenForwardPicker,
  ForwardMessages,
  ReportMessagesRead,
  ResendMessage,
  CopyTextToClipboard,
  PickAndSendPhotoEffect,
  PickAndSendFileEffect,
  CancelMediaDownloadEffect,
  FetchChatSearch,
  JumpToMessage
} from '../contract/ChatEffect';
import { incomingIdUpTo } from '../model/ReadReceipt';
import {
  clearSelection,
  isMessageSelected,
  retainExistingSelection,
  toggleMessageSelection
} from '../model/ForwardSelection';

/** 收集列表中所有可在大图画廊中展示的多媒体项。 */
export function buildViewerItems(messages: readonly MessageItem[]): MediaViewerItem[] {
  const list: MediaViewerItem[] = [];
  for (let i = 0; i < messages.length; i++) {
    const item: MessageItem = messages[i];
    const sender: string = item.isOutgoing ? 'You' : (item.senderName.length > 0 ? item.senderName : '');
    if (item.albumItems.length > 0) {
      for (let j = 0; j < item.albumItems.length; j++) {
        const media: MediaAttachment = item.albumItems[j];
        if (media.kind === 'photo' || media.kind === 'animation' || media.kind === 'video') {
          list.push(new MediaViewerItem(item.messageId, sender, item.timestampMs, media));
        }
      }
    } else if (item.media !== null && (item.media.kind === 'photo' || item.media.kind === 'animation' || item.media.kind === 'video')) {
      list.push(new MediaViewerItem(item.messageId, sender, item.timestampMs, item.media));
    }
  }
  return list;
}

/** 提取消息中第一个可复制的链接 URL（MSG-105）。 */
export function extractFirstLink(item: MessageItem): string | null {
  if (item.spans.length > 0) {
    for (let i = 0; i < item.spans.length; i++) {
      const span = item.spans[i];
      if (span.linkUrl !== null && span.linkUrl.length > 0) {
        return span.linkUrl;
      }
    }
  }
  // 兜底扫描文本中的 http:// 或 https:// 或 www.
  const text: string = item.text;
  const match: RegExpMatchArray | null = text.match(/https?:\/\/[^\s]+|www\.[^\s]+/);
  if (match !== null && match[0] !== undefined) {
    return match[0];
  }
  return null;
}

/** 菜单/预览条用的正文摘要：压成单行并截断。 */
export function messageSnippet(text: string, maxLength: number = 80): string {
  const oneLine: string = text.replace(/\n/g, ' ');
  if (oneLine.length <= maxLength) {
    return oneLine;
  }
  return `${oneLine.substring(0, maxLength)}…`;
}

function findMessage(state: ChatUiState, messageId: number): MessageItem | null {
  for (let i = 0; i < state.messages.length; i++) {
    if (state.messages[i].messageId === messageId) {
      return state.messages[i];
    }
  }
  return null;
}

/** 取消输入栏模式（若有）：编辑模式恢复草稿，回复模式不动草稿。无模式时返回原引用。 */
function cancelMode(state: ChatUiState): ChatUiState {
  const mode: ComposerMode | null = state.composerMode;
  if (mode === null) {
    return state;
  }
  if (mode.kind === 'edit') {
    const editMode: ComposerEditMode = mode as ComposerEditMode;
    return state.copyWith({
      composerMode: null,
      composerText: editMode.draftBackup
    });
  }
  return state.copyWith({ composerMode: null });
}

/** 回复预览条标题：己方消息 "You"，否则 senderName，缺省退化为会话名。 */
function replyAuthorLabel(state: ChatUiState, item: MessageItem): string {
  if (item.isOutgoing) {
    return 'You';
  }
  if (item.senderName.length > 0) {
    return item.senderName;
  }
  return state.chatTitle;
}

export const chatReducer: Reducer<ChatUiState, ChatIntent, ChatEffect> = (
  state: ChatUiState,
  intent: ChatIntent,
  env: ReducerEnv
): ReducerResult<ChatUiState, ChatEffect> => {
  switch (intent.kind) {
    case 'loadInitialMessages': {
      if (state.isLoading || state.messages.length > 0) {
        return reduced(state);
      }
      const nextState: ChatUiState = state.copyWith({
        isLoading: true,
        errorMessage: null
      });
      const effects: ChatEffect[] = [new FetchInitialMessages(state.chatId)];
      return reduced(nextState, effects);
    }

    case 'loadOlderMessages': {
      if (state.isLoading || !state.hasMoreOlder) {
        return reduced(state);
      }
      const nextState: ChatUiState = state.copyWith({
        isLoading: true,
        errorMessage: null
      });
      const effects: ChatEffect[] = [new FetchOlderMessages(state.chatId)];
      return reduced(nextState, effects);
    }

    case 'onMessagesLoaded': {
      const loadedIntent: OnMessagesLoaded = intent as OnMessagesLoaded;
      const viewerItems: MediaViewerItem[] = buildViewerItems(loadedIntent.messages);
      let activeIndex: number = state.activeViewerIndex;
      if (activeIndex >= viewerItems.length) {
        activeIndex = viewerItems.length > 0 ? viewerItems.length - 1 : -1;
      }
      // MSG-106：选择集合收敛——选中期间消息被删除/撤回时剔除失效 id；
      // 全部失效则连选择态一起退出（没有可转发的目标）。
      const pruned: readonly number[] = retainExistingSelection(
        state.selectedMessageIds,
        (messageId: number): boolean => {
          for (let i = 0; i < loadedIntent.messages.length; i++) {
            if (loadedIntent.messages[i].messageId === messageId) {
              return true;
            }
          }
          return false;
        }
      );
      const keepSelectionMode: boolean = state.selectionMode && pruned.length > 0;
      let composerMode: ComposerMode | null = state.composerMode;
      if (composerMode !== null && composerMode.kind === 'reply') {
        const replyMode: ComposerReplyMode = composerMode as ComposerReplyMode;
        if (replyMode.previewTitle === 'Reply' || replyMode.previewText.length === 0) {
          for (let i = 0; i < loadedIntent.messages.length; i++) {
            const msg: MessageItem = loadedIntent.messages[i];
            if (msg.messageId === replyMode.targetMessageId) {
              composerMode = new ComposerReplyMode(
                replyMode.targetMessageId,
                replyAuthorLabel(state, msg),
                messageSnippet(msg.text)
              );
              break;
            }
          }
        }
      }
      const nextState: ChatUiState = state.copyWith({
        messages: loadedIntent.messages,
        hasMoreOlder: loadedIntent.hasMoreOlder,
        isLoading: false,
        errorMessage: null,
        viewerItems: viewerItems,
        activeViewerIndex: activeIndex,
        lastReadInboxMessageId: loadedIntent.lastReadInboxMessageId > 0
          ? loadedIntent.lastReadInboxMessageId
          : state.lastReadInboxMessageId,
        unreadCount: loadedIntent.unreadCount,
        selectionMode: keepSelectionMode,
        selectedMessageIds: keepSelectionMode ? pruned : [],
        composerMode: composerMode
      });
      return reduced(nextState);
    }

    case 'onMessagesLoadFailed': {
      const failedIntent: OnMessagesLoadFailed = intent as OnMessagesLoadFailed;
      const nextState: ChatUiState = state.copyWith({
        isLoading: false,
        errorMessage: failedIntent.error.message
      });
      return reduced(nextState);
    }

    case 'composerTextChanged': {
      const changedIntent: ComposerTextChanged = intent as ComposerTextChanged;
      // 输入即清掉陈旧错误（发送失败/加载失败），不打断正在打的字。
      const nextState: ChatUiState = state.copyWith({
        composerText: changedIntent.text,
        errorMessage: null
      });
      return reduced(nextState);
    }

    case 'restoreDraft': {
      const draftIntent: RestoreDraft = intent as RestoreDraft;
      // 若草稿全为空则无需恢复
      if (draftIntent.draftText.length === 0 && draftIntent.replyToMessageId === 0) {
        return reduced(state);
      }
      // 只有在当前输入栏为空时才恢复，避免覆盖用户已输入的内容
      if (state.composerText.length > 0) {
        return reduced(state);
      }
      let mode: ComposerMode | null = state.composerMode;
      if (draftIntent.replyToMessageId > 0 && mode === null) {
        const item: MessageItem | null = findMessage(state, draftIntent.replyToMessageId);
        const author: string = item !== null ? replyAuthorLabel(state, item) : 'Reply';
        const snippet: string = item !== null ? messageSnippet(item.text) : '';
        mode = new ComposerReplyMode(draftIntent.replyToMessageId, author, snippet);
      }
      const nextState: ChatUiState = state.copyWith({
        composerText: draftIntent.draftText,
        composerMode: mode
      });
      return reduced(nextState);
    }

    case 'sendCurrentMessage': {
      // 空文本（trim 后）不发送。
      const text: string = state.composerText.trim();
      if (text.length === 0) {
        return reduced(state);
      }
      const mode: ComposerMode | null = state.composerMode;
      if (mode !== null && mode.kind === 'edit') {
        // 编辑模式：改调 editMessageText；发出后退出编辑并恢复进入前的草稿。
        const editMode: ComposerEditMode = mode as ComposerEditMode;
        const nextState: ChatUiState = state.copyWith({
          composerMode: null,
          composerText: editMode.draftBackup,
          errorMessage: null
        });
        const effects: ChatEffect[] = [new EditMessageText(state.chatId, editMode.targetMessageId, text)];
        return reduced(nextState, effects);
      }
      if (mode !== null && mode.kind === 'reply') {
        // 回复模式：sendMessage 带 reply_to；发出后清除回复态。
        const replyMode: ComposerReplyMode = mode as ComposerReplyMode;
        const nextState: ChatUiState = state.copyWith({
          composerMode: null,
          composerText: '',
          errorMessage: null
        });
        const effects: ChatEffect[] = [new SendTextMessage(state.chatId, text, replyMode.targetMessageId)];
        return reduced(nextState, effects);
      }
      // 普通发送：发送后立即清空输入栏（乐观清空，
      // 失败由 OnMessageSendFailed 回灌 errorMessage 提示，不回填文本）。
      const nextState: ChatUiState = state.copyWith({
        composerText: '',
        errorMessage: null
      });
      const effects: ChatEffect[] = [new SendTextMessage(state.chatId, text)];
      return reduced(nextState, effects);
    }

    case 'onMessageSendFailed': {
      const sendFailedIntent: OnMessageSendFailed = intent as OnMessageSendFailed;
      const nextState: ChatUiState = state.copyWith({
        errorMessage: sendFailedIntent.error.message
      });
      return reduced(nextState);
    }

    case 'pickAndSendPhoto': {
      let replyToMessageId: number = 0;
      if (state.composerMode !== null && state.composerMode.kind === 'reply') {
        replyToMessageId = (state.composerMode as ComposerReplyMode).targetMessageId;
      }
      const caption: string = state.composerText.trim();
      const effects: ChatEffect[] = [
        new PickAndSendPhotoEffect(state.chatId, replyToMessageId, caption)
      ];
      const nextState: ChatUiState = state.showAttachmentMenu ? state.copyWith({ showAttachmentMenu: false }) : state;
      return reduced(nextState, effects);
    }

    case 'pickAndSendFile': {
      let replyToMessageId: number = 0;
      if (state.composerMode !== null && state.composerMode.kind === 'reply') {
        replyToMessageId = (state.composerMode as ComposerReplyMode).targetMessageId;
      }
      const caption: string = state.composerText.trim();
      const effects: ChatEffect[] = [
        new PickAndSendFileEffect(state.chatId, replyToMessageId, caption)
      ];
      const nextState: ChatUiState = state.showAttachmentMenu ? state.copyWith({ showAttachmentMenu: false }) : state;
      return reduced(nextState, effects);
    }

    case 'openAttachmentMenu': {
      return reduced(state.copyWith({ showAttachmentMenu: true }));
    }

    case 'closeAttachmentMenu': {
      return reduced(state.copyWith({ showAttachmentMenu: false }));
    }

    case 'toggleAttachmentMenu': {
      return reduced(state.copyWith({ showAttachmentMenu: !state.showAttachmentMenu }));
    }

    case 'cancelMediaUpload': {
      const cancelIntent: CancelMediaUpload = intent as CancelMediaUpload;
      return reduced(state, [
        new DeleteMessages(state.chatId, [cancelIntent.messageId], true)
      ]);
    }

    case 'cancelMediaDownload': {
      // FILE-103：取消媒体/文件下载
      const cancelIntent: CancelMediaDownload = intent as CancelMediaDownload;
      return reduced(state, [new CancelMediaDownloadEffect(cancelIntent.fileId)]);
    }

    case 'backToChatList': {
      // COMPOSER-102：附件面板打开时，返回先关闭面板不离开页面。
      if (state.showAttachmentMenu) {
        return reduced(state.copyWith({ showAttachmentMenu: false }));
      }
      // 撤销路径：若全屏查看器打开，先关闭查看器不离开页面。
      if (state.activeViewerIndex >= 0) {
        return reduced(state.copyWith({ activeViewerIndex: -1 }));
      }
      // 气泡长按动作菜单打开时，返回先关闭菜单。
      if (state.actionMenu !== null) {
        return reduced(state.copyWith({ actionMenu: null }));
      }
      // MSG-106：多选转发态激活时，返回只退出选择态，不离开页面。
      if (state.selectionMode) {
        return reduced(state.copyWith({ selectionMode: false, selectedMessageIds: clearSelection() }));
      }
      // 回复/编辑模式激活时，返回先退出模式（编辑恢复草稿），不离开页面。
      if (state.composerMode !== null) {
        return reduced(cancelMode(state));
      }
      const effects: ChatEffect[] = [new NavigateBack()];
      return reduced(state, effects);
    }

    case 'messageActionRequested': {
      const requested: MessageActionRequested = intent as MessageActionRequested;
      // 消息已不在列表（刚被删除）→ 不拉权限。
      if (findMessage(state, requested.messageId) === null) {
        return reduced(state);
      }
      const effects: ChatEffect[] = [new FetchMessagePermissions(state.chatId, requested.messageId)];
      return reduced(state, effects);
    }

    case 'onMessageActionMenuLoaded': {
      const loaded: OnMessageActionMenuLoaded = intent as OnMessageActionMenuLoaded;
      const item: MessageItem | null = findMessage(state, loaded.messageId);
      if (item === null) {
        return reduced(state);
      }
      // 权限过滤：回复恒可（发送失败消息不可回复）；编辑仅己方文本消息且 canBeEdited；
      // 删除需 canBeDeletedOnlyForSelf || canBeDeletedForAllUsers（发送失败消息恒可删除撤销）；
      // revoke 取 canBeDeletedForAllUsers（可对所有人删则对所有人删，失败消息为本地撤销）；
      // MSG-106：转发需 canBeForwarded（发送失败消息不可转发）；
      // MSG-105：复制文本需 canBeSaved 且非空文本；复制链接需 canBeSaved 且存在链接；
      // FILE-103：失败消息展示 Resend 重发选项。
      const isFailed: boolean = item.sendState === 'failed';
      const showResend: boolean = isFailed;
      const showReply: boolean = !isFailed;
      const showEdit: boolean = !isFailed && item.isOutgoing && item.isTextMessage && loaded.canBeEdited;
      const showDelete: boolean = isFailed || loaded.canBeDeletedOnlyForSelf || loaded.canBeDeletedForAllUsers;
      const showCopy: boolean = !isFailed && loaded.canBeSaved && item.text.trim().length > 0;
      const firstLink: string | null = extractFirstLink(item);
      const showCopyLink: boolean = !isFailed && loaded.canBeSaved && firstLink !== null;
      const showForward: boolean = !isFailed && loaded.canBeForwarded;
      const menu: MessageActionMenuState = new MessageActionMenuState(
        loaded.messageId,
        showReply,
        showEdit,
        showDelete,
        isFailed ? true : loaded.canBeDeletedForAllUsers,
        showForward,
        showCopy,
        showCopyLink,
        firstLink,
        showResend
      );
      const nextState: ChatUiState = state.copyWith({ actionMenu: menu });
      return reduced(nextState);
    }

    case 'dismissMessageActionMenu': {
      if (state.actionMenu === null) {
        return reduced(state);
      }
      return reduced(state.copyWith({ actionMenu: null }));
    }

    case 'copyMessageText': {
      const menu: MessageActionMenuState | null = state.actionMenu;
      if (menu === null || !menu.showCopy) {
        return reduced(state);
      }
      const item: MessageItem | null = findMessage(state, menu.messageId);
      if (item === null || item.text.trim().length === 0) {
        return reduced(state.copyWith({ actionMenu: null }));
      }
      const nextState: ChatUiState = state.copyWith({ actionMenu: null });
      const effects: ChatEffect[] = [new CopyTextToClipboard(item.text, '已复制到剪贴板')];
      return reduced(nextState, effects);
    }

    case 'copyMessageLink': {
      const menu: MessageActionMenuState | null = state.actionMenu;
      if (menu === null || !menu.showCopyLink || menu.linkUrlToCopy === null) {
        return reduced(state);
      }
      const nextState: ChatUiState = state.copyWith({ actionMenu: null });
      const effects: ChatEffect[] = [new CopyTextToClipboard(menu.linkUrlToCopy, '已复制链接')];
      return reduced(nextState, effects);
    }

    case 'replyToMessage': {
      const menu: MessageActionMenuState | null = state.actionMenu;
      if (menu === null) {
        return reduced(state);
      }
      const item: MessageItem | null = findMessage(state, menu.messageId);
      if (item === null) {
        return reduced(state.copyWith({ actionMenu: null }));
      }
      const mode: ComposerReplyMode = new ComposerReplyMode(
        menu.messageId,
        replyAuthorLabel(state, item),
        messageSnippet(item.text)
      );
      const nextState: ChatUiState = state.copyWith({
        actionMenu: null,
        composerMode: mode
      });
      return reduced(nextState);
    }

    case 'editMessage': {
      const menu: MessageActionMenuState | null = state.actionMenu;
      if (menu === null || !menu.showEdit) {
        return reduced(state);
      }
      const item: MessageItem | null = findMessage(state, menu.messageId);
      if (item === null || !item.isOutgoing || !item.isTextMessage) {
        return reduced(state.copyWith({ actionMenu: null }));
      }
      // 进入编辑：暂存当前草稿，输入栏填入被编辑消息原文。
      const mode: ComposerEditMode = new ComposerEditMode(
        menu.messageId,
        messageSnippet(item.text),
        state.composerText
      );
      const nextState: ChatUiState = state.copyWith({
        actionMenu: null,
        composerMode: mode,
        composerText: item.text
      });
      return reduced(nextState);
    }

    case 'deleteMessage': {
      const menu: MessageActionMenuState | null = state.actionMenu;
      if (menu === null || !menu.showDelete) {
        return reduced(state);
      }
      let nextState: ChatUiState = state.copyWith({ actionMenu: null });
      // 删的正是回复/编辑目标 → 一并退出输入栏模式。
      const mode: ComposerMode | null = state.composerMode;
      if (mode !== null && mode.targetMessageId === menu.messageId) {
        nextState = cancelMode(nextState);
      }
      const targetItem: MessageItem | null = findMessage(state, menu.messageId);
      const idsToDelete: number[] = (targetItem !== null && targetItem.albumMessageIds.length > 0)
        ? targetItem.albumMessageIds
        : [menu.messageId];
      const effects: ChatEffect[] = [new DeleteMessages(state.chatId, idsToDelete, menu.deleteRevoke)];
      return reduced(nextState, effects);
    }

    case 'cancelComposerMode': {
      return reduced(cancelMode(state));
    }

    case 'onMessageActionFailed': {
      const failed: OnMessageActionFailed = intent as OnMessageActionFailed;
      const nextState: ChatUiState = state.copyWith({
        errorMessage: failed.error.message
      });
      return reduced(nextState);
    }

    // ---- MSG-106 转发多选流 ----

    case 'forwardMessagesRequested': {
      // 菜单点选 Forward：关闭菜单、进入选择态并预选中该条。
      // showForward 已在 onMessageActionMenuLoaded 内按 can_be_forwarded 过滤。
      const menu: MessageActionMenuState | null = state.actionMenu;
      if (menu === null || !menu.showForward) {
        return reduced(state);
      }
      const item: MessageItem | null = findMessage(state, menu.messageId);
      if (item === null) {
        return reduced(state.copyWith({ actionMenu: null }));
      }
      const nextState: ChatUiState = state.copyWith({
        actionMenu: null,
        selectionMode: true,
        selectedMessageIds: toggleMessageSelection([], menu.messageId),
        errorMessage: null
      });
      return reduced(nextState);
    }

    case 'toggleMessageSelection': {
      const toggle: ToggleMessageSelection = intent as ToggleMessageSelection;
      if (!state.selectionMode) {
        return reduced(state);
      }
      // 消息已不在列表（刚被删除）→ 忽略，选择集合不动。
      if (findMessage(state, toggle.messageId) === null) {
        return reduced(state);
      }
      const next: number[] = toggleMessageSelection(state.selectedMessageIds, toggle.messageId);
      // 取消掉最后一条 → 自动退出选择态（Telegram X 行为）。
      if (next.length === 0) {
        return reduced(state.copyWith({ selectionMode: false, selectedMessageIds: clearSelection() }));
      }
      return reduced(state.copyWith({ selectedMessageIds: next }));
    }

    case 'exitMessageSelection': {
      if (!state.selectionMode) {
        return reduced(state);
      }
      return reduced(state.copyWith({ selectionMode: false, selectedMessageIds: clearSelection() }));
    }

    case 'confirmForwardSelection': {
      // 顶栏 Forward：把"给这些消息挑目标"交给装配层（entry 持有会话列表数据）。
      if (!state.selectionMode || state.selectedMessageIds.length === 0) {
        return reduced(state);
      }
      const expandedIds: number[] = [];
      for (let i = 0; i < state.selectedMessageIds.length; i++) {
        const selId: number = state.selectedMessageIds[i];
        const msgItem: MessageItem | null = findMessage(state, selId);
        if (msgItem !== null && msgItem.albumMessageIds.length > 0) {
          for (let j = 0; j < msgItem.albumMessageIds.length; j++) {
            expandedIds.push(msgItem.albumMessageIds[j]);
          }
        } else {
          expandedIds.push(selId);
        }
      }
      const effects: ChatEffect[] = [
        new OpenForwardPicker(state.chatId, expandedIds)
      ];
      return reduced(state, effects);
    }

    case 'forwardSelectedToChat': {
      const pick: ForwardSelectedToChat = intent as ForwardSelectedToChat;
      if (!state.selectionMode || state.selectedMessageIds.length === 0) {
        return reduced(state);
      }
      if (pick.toChatId === 0) {
        return reduced(state);
      }
      const expandedIds: number[] = [];
      for (let i = 0; i < state.selectedMessageIds.length; i++) {
        const selId: number = state.selectedMessageIds[i];
        const msgItem: MessageItem | null = findMessage(state, selId);
        if (msgItem !== null && msgItem.albumMessageIds.length > 0) {
          for (let j = 0; j < msgItem.albumMessageIds.length; j++) {
            expandedIds.push(msgItem.albumMessageIds[j]);
          }
        } else {
          expandedIds.push(selId);
        }
      }
      // 选择态保留到 OnForwardCompleted：失败时用户可直接换目标重试。
      const effects: ChatEffect[] = [
        new ForwardMessages(state.chatId, pick.toChatId, expandedIds, pick.sendCopy)
      ];
      return reduced(state, effects);
    }

    case 'onForwardCompleted': {
      // 成功：收起选择态并清空选择（幂等——已退出时返回原引用）。
      if (!state.selectionMode && state.selectedMessageIds.length === 0) {
        return reduced(state);
      }
      const nextState: ChatUiState = state.copyWith({
        selectionMode: false,
        selectedMessageIds: clearSelection(),
        errorMessage: null
      });
      return reduced(nextState);
    }

    case 'onForwardFailed': {
      const failure: OnForwardFailed = intent as OnForwardFailed;
      // 保留选择态：换一个目标会话即可重试。
      const nextState: ChatUiState = state.copyWith({
        errorMessage: failure.error.message
      });
      return reduced(nextState);
    }

    case 'onVisibleRangeChanged': {
      // MSG-104：入屏即读。index → 该范围内最大 incoming 消息 id，出
      // ReportMessagesRead；无 incoming 不出 effect。节流（只增不减）在
      // coordinator 执行侧（ReadReportThrottle），reducer 保持无状态。
      const visible: OnVisibleRangeChanged = intent as OnVisibleRangeChanged;
      const targetId: number = incomingIdUpTo(state.messages, visible.lastVisibleIndex);
      if (targetId <= 0) {
        return reduced(state);
      }
      const effects: ChatEffect[] = [new ReportMessagesRead(state.chatId, targetId)];
      return reduced(state, effects);
    }

    case 'tapFailedMessage': {
      // MSG-104：点击失败气泡重发；非失败态/未知消息忽略。状态不变：
      // 结算由 updateMessageSendSucceeded/Failed 订阅驱动。
      const tapped: TapFailedMessage = intent as TapFailedMessage;
      const item: MessageItem | null = findMessage(state, tapped.messageId);
      if (item === null || item.sendState !== 'failed') {
        return reduced(state);
      }
      const effects: ChatEffect[] = [new ResendMessage(state.chatId, tapped.messageId)];
      return reduced(state, effects);
    }

    case 'resendFailedMessage': {
      // FILE-103：长按菜单或重试图标触发失败消息重发，收起菜单并派发 ResendMessage。
      const resendIntent: ResendFailedMessage = intent as ResendFailedMessage;
      const item: MessageItem | null = findMessage(state, resendIntent.messageId);
      if (item === null || item.sendState !== 'failed') {
        return reduced(state.copyWith({ actionMenu: null }));
      }
      const nextState: ChatUiState = state.copyWith({ actionMenu: null });
      const effects: ChatEffect[] = [new ResendMessage(state.chatId, resendIntent.messageId)];
      return reduced(nextState, effects);
    }

    case 'openMediaViewer': {
      const openIntent: OpenMediaViewer = intent as OpenMediaViewer;
      const viewerItems: MediaViewerItem[] = buildViewerItems(state.messages);
      let targetIndex: number = -1;
      for (let i = 0; i < viewerItems.length; i++) {
        if (viewerItems[i].messageId === openIntent.messageId) {
          if (openIntent.targetFileId !== undefined && openIntent.targetFileId > 0) {
            if (viewerItems[i].media.fileId === openIntent.targetFileId) {
              targetIndex = i;
              break;
            }
          } else {
            targetIndex = i;
            break;
          }
        }
      }
      if (targetIndex < 0) {
        return reduced(state);
      }
      const nextState: ChatUiState = state.copyWith({
        viewerItems: viewerItems,
        activeViewerIndex: targetIndex
      });
      return reduced(nextState);
    }

    case 'closeMediaViewer': {
      if (state.activeViewerIndex < 0) {
        return reduced(state);
      }
      return reduced(state.copyWith({ activeViewerIndex: -1 }));
    }

    case 'changeViewerIndex': {
      const changeIntent: ChangeViewerIndex = intent as ChangeViewerIndex;
      if (changeIntent.newIndex < 0 || changeIntent.newIndex >= state.viewerItems.length) {
        return reduced(state);
      }
      return reduced(state.copyWith({ activeViewerIndex: changeIntent.newIndex }));
    }

    // ---- SEARCH-102 聊天内搜索 ----
    case 'openChatSearch': {
      if (state.showSearch) {
        return reduced(state);
      }
      // 清空在途标记，展开搜索面板。
      return reduced(state.copyWith({
        showSearch: true,
        searchQuery: '',
        searchResults: [],
        isSearching: false,
        jumpToMessageId: 0
      }));
    }

    case 'closeChatSearch': {
      if (!state.showSearch) {
        return reduced(state);
      }
      return reduced(state.copyWith({
        showSearch: false,
        searchQuery: '',
        searchResults: [],
        isSearching: false,
        jumpToMessageId: 0
      }));
    }

    case 'chatSearchQueryChanged': {
      const queryIntent: ChatSearchQueryChanged = intent as ChatSearchQueryChanged;
      return reduced(state.copyWith({
        searchQuery: queryIntent.query,
        jumpToMessageId: 0
      }));
    }

    case 'performChatSearch': {
      const query: string = state.searchQuery.trim();
      if (query.length === 0 || state.isSearching) {
        return reduced(state);
      }
      const effects: ChatEffect[] = [new FetchChatSearch(state.chatId, query, 0)];
      return reduced(state.copyWith({ isSearching: true }), effects);
    }

    case 'onChatSearchLoaded': {
      const loadedIntent: OnChatSearchLoaded = intent as OnChatSearchLoaded;
      return reduced(state.copyWith({
        isSearching: false,
        searchResults: loadedIntent.results
      }));
    }

    case 'onChatSearchFailed': {
      const failedIntent: OnChatSearchFailed = intent as OnChatSearchFailed;
      return reduced(state.copyWith({
        isSearching: false,
        errorMessage: failedIntent.error.message
      }));
    }

    case 'jumpToSearchResult': {
      const jumpIntent: JumpToSearchResult = intent as JumpToSearchResult;
      if (jumpIntent.messageId <= 0 || state.jumpToMessageId !== 0) {
        return reduced(state);
      }
      const effects: ChatEffect[] = [new JumpToMessage(jumpIntent.messageId)];
      // 关闭搜索面板，发起历史围绕拉取。
      return reduced(state.copyWith({
        showSearch: false,
        jumpToMessageId: jumpIntent.messageId,
        searchResults: []
      }), effects);
    }

    case 'onJumpToMessageReady': {
      const readyIntent: OnJumpToMessageReady = intent as OnJumpToMessageReady;
      return reduced(state.copyWith({ jumpToMessageId: readyIntent.messageId }));
    }

    case 'clearJumpToMessage': {
      if (state.jumpToMessageId === 0) {
        return reduced(state);
      }
      return reduced(state.copyWith({ jumpToMessageId: 0 }));
    }

    // ---- MSG-109 头部信息区 ----

    case 'onHeaderSubtitleChanged': {
      // 副标题回灌：值相同不动状态，避免无关重渲。
      const subtitleIntent: OnHeaderSubtitleChanged = intent as OnHeaderSubtitleChanged;
      if (state.headerSubtitle === subtitleIntent.subtitle) {
        return reduced(state);
      }
      return reduced(state.copyWith({ headerSubtitle: subtitleIntent.subtitle }));
    }

    case 'onChatKindChanged': {
      // 会话种类回灌（驱动头部通话按钮与 ⋮ 菜单项）；值相同不动状态。
      const kindIntent: OnChatKindChanged = intent as OnChatKindChanged;
      if (state.chatKind === kindIntent.chatKind) {
        return reduced(state);
      }
      return reduced(state.copyWith({ chatKind: kindIntent.chatKind }));
    }

    // openChatProfile / chatMenuAction：纯导航/占位意图，reducer 原样透传
    // （落到 switch 后的 reduced(state)，状态引用不变、无 effect）。
  }

  return reduced(state);
};
