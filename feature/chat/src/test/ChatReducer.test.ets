import { describe, it, expect } from '@ohos/hypium';
import { ManualClock, SequentialIdGenerator, AppErrors } from '@tgx/core-common';
import { ReducerEnv, ReducerResult } from '@tgx/feature-template';
import {
  ChatUiState,
  ComposerEditMode,
  ComposerMode,
  ComposerReplyMode,
  MessageActionMenuState
} from '../main/ets/contract/ChatUiState';
import { MessageItem } from '../main/ets/model/MessageItem';
import {
  ChatIntent,
  ComposerTextChanged,
  SendCurrentMessage,
  OnMessageSendFailed,
  OnMessagesLoaded,
  BackToChatList,
  MessageActionRequested,
  OnMessageActionMenuLoaded,
  ReplyToMessage,
  CopyMessageText,
  CopyMessageLink,
  EditMessage,
  DeleteMessage,
  CancelComposerMode,
  DismissMessageActionMenu,
  OnMessageActionFailed,
  ForwardMessagesRequested,
  ToggleMessageSelection,
  ConfirmForwardSelection,
  ForwardSelectedToChat,
  OnForwardCompleted,
  OnForwardFailed,
  PickAndSendPhoto,
  PickAndSendFile,
  RestoreDraft,
  OpenAttachmentMenu,
  CloseAttachmentMenu,
  ToggleAttachmentMenu,
  CancelMediaDownload,
  ResendFailedMessage,
  OpenChatSearch,
  CloseChatSearch,
  ChatSearchQueryChanged,
  PerformChatSearch,
  OnChatSearchLoaded,
  OnChatSearchFailed,
  JumpToSearchResult,
  OnJumpToMessageReady,
  ClearJumpToMessage,
  OnHeaderSubtitleChanged,
  OnChatKindChanged,
  OpenChatProfile,
  ChatMenuAction
} from '../main/ets/contract/ChatIntent';
import {
  ChatEffect,
  SendTextMessage,
  FetchMessagePermissions,
  EditMessageText,
  DeleteMessages,
  NavigateBack,
  OpenForwardPicker,
  ForwardMessages,
  CopyTextToClipboard,
  PickAndSendPhotoEffect,
  CancelMediaDownloadEffect,
  ResendMessage,
  FetchChatSearch,
  JumpToMessage
} from '../main/ets/contract/ChatEffect';
import { ChatSearchResultItem } from '../main/ets/model/ChatSearchResultItem';
import { chatReducer, extractFirstLink } from '../main/ets/reducer/ChatReducer';
import { MessageTextSpan } from '../main/ets/model/MessageTextSpan';

function makeEnv(nowMillis: number = 1000, monotonicMillis: number = 500): ReducerEnv {
  const env: ReducerEnv = {
    clock: new ManualClock(nowMillis, monotonicMillis),
    ids: new SequentialIdGenerator('req-test-')
  };
  return env;
}

function makeState(composerText: string = '', errorMessage: string | null = null): ChatUiState {
  return new ChatUiState(42, 'chat', [], false, true, errorMessage, composerText, null, null);
}

function makeStateWith(
  messages: readonly MessageItem[],
  composerText: string = '',
  composerMode: ComposerMode | null = null,
  actionMenu: MessageActionMenuState | null = null
): ChatUiState {
  return new ChatUiState(42, 'chat', messages, false, true, null, composerText, composerMode, actionMenu);
}

function makeTextMessage(messageId: number, isOutgoing: boolean, text: string = 'hello'): MessageItem {
  return new MessageItem(messageId, text, 1000, isOutgoing, '', 'none', true, false, null, '');
}

/** 取菜单的 showForward（菜单为 null 时返回 false），避免非空断言。 */
function menuShowForward(state: ChatUiState): boolean {
  const menu: MessageActionMenuState | null = state.actionMenu;
  return menu !== null ? menu.showForward : false;
}

export default function chatReducerTest() {
  describe('ChatReducerTest', () => {
    it('composerTextChanged_updatesComposerText_andClearsError', 0, () => {
      const result: ReducerResult<ChatUiState, ChatEffect> =
        chatReducer(makeState('', 'send failed'), new ComposerTextChanged('hello'), makeEnv());
      expect(result.state.composerText).assertEqual('hello');
      expect(result.state.errorMessage).assertNull();
      expect(result.effects.length).assertEqual(0);
    });

    it('sendCurrentMessage_emptyText_isNoOpSameStateRef', 0, () => {
      const state: ChatUiState = makeState('   ');
      const result: ReducerResult<ChatUiState, ChatEffect> =
        chatReducer(state, new SendCurrentMessage(), makeEnv());
      expect(result.state === state).assertTrue();
      expect(result.effects.length).assertEqual(0);
    });

    it('sendCurrentMessage_withText_clearsComposerAndEmitsSendEffect', 0, () => {
      const state: ChatUiState = makeState('  hello world  ');
      const result: ReducerResult<ChatUiState, ChatEffect> =
        chatReducer(state, new SendCurrentMessage(), makeEnv());
      expect(result.state.composerText).assertEqual('');
      expect(result.effects.length).assertEqual(1);
      const effect: ChatEffect = result.effects[0];
      expect(effect.kind).assertEqual('sendTextMessage');
      const send: SendTextMessage = effect as SendTextMessage;
      expect(send.chatId).assertEqual(42);
      expect(send.text).assertEqual('hello world');
    });

    it('onMessageSendFailed_setsErrorMessage_keepsComposerCleared', 0, () => {
      const state: ChatUiState = makeState('');
      const result: ReducerResult<ChatUiState, ChatEffect> = chatReducer(
        state,
        new OnMessageSendFailed(AppErrors.tdlib('bad_request', 'TDLib rejected the request', false)),
        makeEnv()
      );
      expect(result.state.errorMessage).assertEqual('TDLib rejected the request');
      expect(result.state.composerText).assertEqual('');
      expect(result.effects.length).assertEqual(0);
    });

    it('messageActionRequested_emitsFetchMessagePermissions', 0, () => {
      const state: ChatUiState = makeStateWith([makeTextMessage(7, true)]);
      const result: ReducerResult<ChatUiState, ChatEffect> =
        chatReducer(state, new MessageActionRequested(7), makeEnv());
      expect(result.effects.length).assertEqual(1);
      const effect: ChatEffect = result.effects[0];
      expect(effect.kind).assertEqual('fetchMessagePermissions');
      const fetch: FetchMessagePermissions = effect as FetchMessagePermissions;
      expect(fetch.chatId).assertEqual(42);
      expect(fetch.messageId).assertEqual(7);
    });

    it('messageActionRequested_unknownMessage_isNoOp', 0, () => {
      const state: ChatUiState = makeStateWith([makeTextMessage(7, true)]);
      const result: ReducerResult<ChatUiState, ChatEffect> =
        chatReducer(state, new MessageActionRequested(999), makeEnv());
      expect(result.state === state).assertTrue();
      expect(result.effects.length).assertEqual(0);
    });

    it('onMessageActionMenuLoaded_outgoingTextWithEdit_showsAllActions', 0, () => {
      const state: ChatUiState = makeStateWith([makeTextMessage(7, true)]);
      const result: ReducerResult<ChatUiState, ChatEffect> =
        chatReducer(state, new OnMessageActionMenuLoaded(7, true, true, true), makeEnv());
      const menu: MessageActionMenuState = result.state.actionMenu as MessageActionMenuState;
      expect(menu.messageId).assertEqual(7);
      expect(menu.showReply).assertTrue();
      expect(menu.showEdit).assertTrue();
      expect(menu.showDelete).assertTrue();
      expect(menu.deleteRevoke).assertTrue();
    });

    it('onMessageActionMenuLoaded_incomingMessage_neverShowsEdit', 0, () => {
      const state: ChatUiState = makeStateWith([makeTextMessage(7, false)]);
      const result: ReducerResult<ChatUiState, ChatEffect> =
        chatReducer(state, new OnMessageActionMenuLoaded(7, true, true, false), makeEnv());
      const menu: MessageActionMenuState = result.state.actionMenu as MessageActionMenuState;
      expect(menu.showReply).assertTrue();
      expect(menu.showEdit).assertFalse();
      expect(menu.showDelete).assertTrue();
      expect(menu.deleteRevoke).assertFalse();
    });

    it('onMessageActionMenuLoaded_outgoingNonText_hidesEditEvenWhenAllowed', 0, () => {
      const photoMessage: MessageItem = new MessageItem(7, '[Photo]', 1000, true, '', 'none', false, false, null, '');
      const state: ChatUiState = makeStateWith([photoMessage]);
      const result: ReducerResult<ChatUiState, ChatEffect> =
        chatReducer(state, new OnMessageActionMenuLoaded(7, true, true, true), makeEnv());
      const menu: MessageActionMenuState = result.state.actionMenu as MessageActionMenuState;
      expect(menu.showEdit).assertFalse();
      expect(menu.showDelete).assertTrue();
    });

    it('onMessageActionMenuLoaded_noDeletePermission_hidesDelete', 0, () => {
      const state: ChatUiState = makeStateWith([makeTextMessage(7, true)]);
      const result: ReducerResult<ChatUiState, ChatEffect> =
        chatReducer(state, new OnMessageActionMenuLoaded(7, false, false, false), makeEnv());
      const menu: MessageActionMenuState = result.state.actionMenu as MessageActionMenuState;
      expect(menu.showReply).assertTrue();
      expect(menu.showEdit).assertFalse();
      expect(menu.showDelete).assertFalse();
    });

    it('onMessageActionMenuLoaded_textMessage_showsCopy', 0, () => {
      const state: ChatUiState = makeStateWith([makeTextMessage(7, true, 'Hello copy')]);
      const result: ReducerResult<ChatUiState, ChatEffect> =
        chatReducer(state, new OnMessageActionMenuLoaded(7, false, false, false, false, true), makeEnv());
      const menu: MessageActionMenuState = result.state.actionMenu as MessageActionMenuState;
      expect(menu.showCopy).assertTrue();
      expect(menu.showCopyLink).assertFalse();
      expect(menu.linkUrlToCopy).assertNull();
    });

    it('onMessageActionMenuLoaded_emptyTextMessage_hidesCopy', 0, () => {
      const state: ChatUiState = makeStateWith([makeTextMessage(7, true, '   ')]);
      const result: ReducerResult<ChatUiState, ChatEffect> =
        chatReducer(state, new OnMessageActionMenuLoaded(7, false, false, false, false, true), makeEnv());
      const menu: MessageActionMenuState = result.state.actionMenu as MessageActionMenuState;
      expect(menu.showCopy).assertFalse();
    });

    it('onMessageActionMenuLoaded_protectedMessage_hidesCopyAndCopyLink', 0, () => {
      const state: ChatUiState = makeStateWith([makeTextMessage(7, false, 'Protected https://example.com')]);
      const result: ReducerResult<ChatUiState, ChatEffect> =
        chatReducer(state, new OnMessageActionMenuLoaded(7, false, false, false, false, false), makeEnv());
      const menu: MessageActionMenuState = result.state.actionMenu as MessageActionMenuState;
      expect(menu.showCopy).assertFalse();
      expect(menu.showCopyLink).assertFalse();
    });

    it('onMessageActionMenuLoaded_messageWithSpanLink_showsCopyLink', 0, () => {
      const span: MessageTextSpan = new MessageTextSpan(
        'website', false, false, false, false, false, false, false, false, 'https://telegram.org'
      );
      const msg: MessageItem = new MessageItem(
        7, 'Visit website', 1000, false, '', 'none', true, false, null, '', [span]
      );
      const state: ChatUiState = makeStateWith([msg]);
      const result: ReducerResult<ChatUiState, ChatEffect> =
        chatReducer(state, new OnMessageActionMenuLoaded(7, false, false, false, false, true), makeEnv());
      const menu: MessageActionMenuState = result.state.actionMenu as MessageActionMenuState;
      expect(menu.showCopy).assertTrue();
      expect(menu.showCopyLink).assertTrue();
      expect(menu.linkUrlToCopy).assertEqual('https://telegram.org');
    });

    it('onMessageActionMenuLoaded_messageWithRawUrl_showsCopyLink', 0, () => {
      const state: ChatUiState = makeStateWith([makeTextMessage(7, false, 'check https://t.me/telegram')]);
      const result: ReducerResult<ChatUiState, ChatEffect> =
        chatReducer(state, new OnMessageActionMenuLoaded(7, false, false, false, false, true), makeEnv());
      const menu: MessageActionMenuState = result.state.actionMenu as MessageActionMenuState;
      expect(menu.showCopy).assertTrue();
      expect(menu.showCopyLink).assertTrue();
      expect(menu.linkUrlToCopy).assertEqual('https://t.me/telegram');
    });

    it('copyMessageText_validMessage_closesMenuAndEmitsCopyEffect', 0, () => {
      const menu: MessageActionMenuState = new MessageActionMenuState(
        7, true, false, false, false, false, true, false, null
      );
      const state: ChatUiState = makeStateWith([makeTextMessage(7, false, 'Copy me!')], '', null, menu);
      const result: ReducerResult<ChatUiState, ChatEffect> =
        chatReducer(state, new CopyMessageText(), makeEnv());
      expect(result.state.actionMenu).assertNull();
      expect(result.effects.length).assertEqual(1);
      const effect: CopyTextToClipboard = result.effects[0] as CopyTextToClipboard;
      expect(effect.kind).assertEqual('copyTextToClipboard');
      expect(effect.text).assertEqual('Copy me!');
      expect(effect.toastMessage).assertEqual('已复制到剪贴板');
    });

    it('copyMessageText_whenNotAllowed_doesNothing', 0, () => {
      const menu: MessageActionMenuState = new MessageActionMenuState(
        7, true, false, false, false, false, false, false, null
      );
      const state: ChatUiState = makeStateWith([makeTextMessage(7, false, 'No copy')], '', null, menu);
      const result: ReducerResult<ChatUiState, ChatEffect> =
        chatReducer(state, new CopyMessageText(), makeEnv());
      expect(result.state.actionMenu !== null).assertTrue();
      expect(result.effects.length).assertEqual(0);
    });

    it('copyMessageLink_validLink_closesMenuAndEmitsCopyEffect', 0, () => {
      const menu: MessageActionMenuState = new MessageActionMenuState(
        7, true, false, false, false, false, true, true, 'https://tgx.org'
      );
      const state: ChatUiState = makeStateWith([makeTextMessage(7, false, 'Visit https://tgx.org')], '', null, menu);
      const result: ReducerResult<ChatUiState, ChatEffect> =
        chatReducer(state, new CopyMessageLink(), makeEnv());
      expect(result.state.actionMenu).assertNull();
      expect(result.effects.length).assertEqual(1);
      const effect: CopyTextToClipboard = result.effects[0] as CopyTextToClipboard;
      expect(effect.kind).assertEqual('copyTextToClipboard');
      expect(effect.text).assertEqual('https://tgx.org');
      expect(effect.toastMessage).assertEqual('已复制链接');
    });

    it('replyToMessage_setsReplyMode_keepsComposerDraft', 0, () => {
      const menu: MessageActionMenuState = new MessageActionMenuState(7, true, false, false, false);
      const state: ChatUiState = makeStateWith([makeTextMessage(7, false, 'hi there')], 'draft', null, menu);
      const result: ReducerResult<ChatUiState, ChatEffect> =
        chatReducer(state, new ReplyToMessage(), makeEnv());
      const mode: ComposerReplyMode = result.state.composerMode as ComposerReplyMode;
      expect(mode.kind).assertEqual('reply');
      expect(mode.targetMessageId).assertEqual(7);
      expect(mode.previewText).assertEqual('hi there');
      expect(result.state.composerText).assertEqual('draft');
      expect(result.state.actionMenu).assertNull();
      expect(result.effects.length).assertEqual(0);
    });

    it('cancelComposerMode_reply_clearsMode_keepsText', 0, () => {
      const mode: ComposerReplyMode = new ComposerReplyMode(7, 'Alice', 'hi');
      const state: ChatUiState = makeStateWith([makeTextMessage(7, false)], 'draft', mode);
      const result: ReducerResult<ChatUiState, ChatEffect> =
        chatReducer(state, new CancelComposerMode(), makeEnv());
      expect(result.state.composerMode).assertNull();
      expect(result.state.composerText).assertEqual('draft');
      expect(result.effects.length).assertEqual(0);
    });

    it('editMessage_fillsComposerWithOriginal_stashesDraft', 0, () => {
      const menu: MessageActionMenuState = new MessageActionMenuState(7, true, true, true, true);
      const state: ChatUiState = makeStateWith([makeTextMessage(7, true, 'old text')], 'my draft', null, menu);
      const result: ReducerResult<ChatUiState, ChatEffect> =
        chatReducer(state, new EditMessage(), makeEnv());
      const mode: ComposerEditMode = result.state.composerMode as ComposerEditMode;
      expect(mode.kind).assertEqual('edit');
      expect(mode.targetMessageId).assertEqual(7);
      expect(mode.draftBackup).assertEqual('my draft');
      expect(result.state.composerText).assertEqual('old text');
      expect(result.state.actionMenu).assertNull();
    });

    it('cancelComposerMode_edit_restoresDraft', 0, () => {
      const mode: ComposerEditMode = new ComposerEditMode(7, 'old text', 'my draft');
      const state: ChatUiState = makeStateWith([makeTextMessage(7, true, 'old text')], 'edited text', mode);
      const result: ReducerResult<ChatUiState, ChatEffect> =
        chatReducer(state, new CancelComposerMode(), makeEnv());
      expect(result.state.composerMode).assertNull();
      expect(result.state.composerText).assertEqual('my draft');
      expect(result.effects.length).assertEqual(0);
    });

    it('sendCurrentMessage_editMode_emitsEditEffect_restoresDraft', 0, () => {
      const mode: ComposerEditMode = new ComposerEditMode(7, 'old text', 'my draft');
      const state: ChatUiState = makeStateWith([makeTextMessage(7, true, 'old text')], 'new text', mode);
      const result: ReducerResult<ChatUiState, ChatEffect> =
        chatReducer(state, new SendCurrentMessage(), makeEnv());
      expect(result.state.composerMode).assertNull();
      expect(result.state.composerText).assertEqual('my draft');
      expect(result.effects.length).assertEqual(1);
      const effect: ChatEffect = result.effects[0];
      expect(effect.kind).assertEqual('editMessageText');
      const edit: EditMessageText = effect as EditMessageText;
      expect(edit.chatId).assertEqual(42);
      expect(edit.messageId).assertEqual(7);
      expect(edit.text).assertEqual('new text');
    });

    it('sendCurrentMessage_replyMode_emitsSendWithReplyTo_clearsMode', 0, () => {
      const mode: ComposerReplyMode = new ComposerReplyMode(7, 'Alice', 'hi');
      const state: ChatUiState = makeStateWith([makeTextMessage(7, false)], 'reply text', mode);
      const result: ReducerResult<ChatUiState, ChatEffect> =
        chatReducer(state, new SendCurrentMessage(), makeEnv());
      expect(result.state.composerMode).assertNull();
      expect(result.state.composerText).assertEqual('');
      expect(result.effects.length).assertEqual(1);
      const effect: ChatEffect = result.effects[0];
      expect(effect.kind).assertEqual('sendTextMessage');
      const send: SendTextMessage = effect as SendTextMessage;
      expect(send.chatId).assertEqual(42);
      expect(send.text).assertEqual('reply text');
      expect(send.replyToMessageId).assertEqual(7);
    });

    it('deleteMessage_emitsDeleteWithRevoke_dismissesMenu', 0, () => {
      const menu: MessageActionMenuState = new MessageActionMenuState(7, true, false, true, true);
      const state: ChatUiState = makeStateWith([makeTextMessage(7, true)], '', null, menu);
      const result: ReducerResult<ChatUiState, ChatEffect> =
        chatReducer(state, new DeleteMessage(), makeEnv());
      expect(result.state.actionMenu).assertNull();
      expect(result.effects.length).assertEqual(1);
      const effect: ChatEffect = result.effects[0];
      expect(effect.kind).assertEqual('deleteMessages');
      const del: DeleteMessages = effect as DeleteMessages;
      expect(del.chatId).assertEqual(42);
      expect(del.messageIds.length).assertEqual(1);
      expect(del.messageIds[0]).assertEqual(7);
      expect(del.revoke).assertTrue();
    });

    it('deleteMessage_deleteTargetIsEditTarget_exitsComposerModeRestoringDraft', 0, () => {
      const mode: ComposerEditMode = new ComposerEditMode(7, 'old text', 'my draft');
      const menu: MessageActionMenuState = new MessageActionMenuState(7, true, true, true, false);
      const state: ChatUiState = makeStateWith([makeTextMessage(7, true, 'old text')], 'edited text', mode, menu);
      const result: ReducerResult<ChatUiState, ChatEffect> =
        chatReducer(state, new DeleteMessage(), makeEnv());
      expect(result.state.composerMode).assertNull();
      expect(result.state.composerText).assertEqual('my draft');
      expect(result.effects.length).assertEqual(1);
      expect(result.effects[0].kind).assertEqual('deleteMessages');
    });

    it('backToChatList_inComposerMode_cancelsModeFirst_thenNavigates', 0, () => {
      const mode: ComposerEditMode = new ComposerEditMode(7, 'old text', 'my draft');
      const state: ChatUiState = makeStateWith([makeTextMessage(7, true, 'old text')], 'edited text', mode);
      const first: ReducerResult<ChatUiState, ChatEffect> =
        chatReducer(state, new BackToChatList(), makeEnv());
      expect(first.state.composerMode).assertNull();
      expect(first.state.composerText).assertEqual('my draft');
      expect(first.effects.length).assertEqual(0);
      const second: ReducerResult<ChatUiState, ChatEffect> =
        chatReducer(first.state, new BackToChatList(), makeEnv());
      expect(second.effects.length).assertEqual(1);
      expect(second.effects[0].kind).assertEqual('navigateBack');
    });

    it('dismissMessageActionMenu_clearsMenu', 0, () => {
      const menu: MessageActionMenuState = new MessageActionMenuState(7, true, false, true, false);
      const state: ChatUiState = makeStateWith([makeTextMessage(7, false)], '', null, menu);
      const result: ReducerResult<ChatUiState, ChatEffect> =
        chatReducer(state, new DismissMessageActionMenu(), makeEnv());
      expect(result.state.actionMenu).assertNull();
      expect(result.effects.length).assertEqual(0);
    });

    it('onMessageActionFailed_setsErrorMessage', 0, () => {
      const state: ChatUiState = makeState('');
      const result: ReducerResult<ChatUiState, ChatEffect> = chatReducer(
        state,
        new OnMessageActionFailed(AppErrors.tdlib('bad_request', 'TDLib rejected the request', false)),
        makeEnv()
      );
      expect(result.state.errorMessage).assertEqual('TDLib rejected the request');
      expect(result.effects.length).assertEqual(0);
    });

    // ---- MSG-106 转发多选流（FEAT-COMP-004）----

    it('onMessageActionMenuLoaded_exposesForwardOnlyWhenCanBeForwarded', 0, () => {
      const messages: readonly MessageItem[] = [makeTextMessage(7, false)];
      const state: ChatUiState = makeStateWith(messages);

      const allowed: ReducerResult<ChatUiState, ChatEffect> = chatReducer(
        state,
        new OnMessageActionMenuLoaded(7, false, false, false, true),
        makeEnv()
      );
      expect(menuShowForward(allowed.state)).assertTrue();

      const denied: ReducerResult<ChatUiState, ChatEffect> = chatReducer(
        state,
        new OnMessageActionMenuLoaded(7, false, false, false, false),
        makeEnv()
      );
      expect(menuShowForward(denied.state)).assertFalse();
    });

    it('forwardMessagesRequested_entersSelectionModeWithPressedMessage', 0, () => {
      const messages: readonly MessageItem[] = [makeTextMessage(7, false), makeTextMessage(8, false)];
      const menu: MessageActionMenuState = new MessageActionMenuState(7, true, false, false, false, true);
      const state: ChatUiState = makeStateWith(messages, '', null, menu);

      const result: ReducerResult<ChatUiState, ChatEffect> =
        chatReducer(state, new ForwardMessagesRequested(), makeEnv());

      expect(result.state.selectionMode).assertTrue();
      expect(result.state.selectedMessageIds.length).assertEqual(1);
      expect(result.state.selectedMessageIds[0]).assertEqual(7);
      // 菜单关闭，且进入选择态本身不发请求
      expect(result.state.actionMenu).assertNull();
      expect(result.effects.length).assertEqual(0);
    });

    it('forwardMessagesRequested_isNoOpWhenForwardNotAllowed', 0, () => {
      const messages: readonly MessageItem[] = [makeTextMessage(7, false)];
      const menu: MessageActionMenuState = new MessageActionMenuState(7, true, false, false, false, false);
      const state: ChatUiState = makeStateWith(messages, '', null, menu);

      const result: ReducerResult<ChatUiState, ChatEffect> =
        chatReducer(state, new ForwardMessagesRequested(), makeEnv());

      expect(result.state === state).assertTrue();
      expect(result.state.selectionMode).assertFalse();
      expect(result.effects.length).assertEqual(0);
    });

    it('toggleMessageSelection_deselectingLastItemExitsSelectionMode', 0, () => {
      const messages: readonly MessageItem[] = [makeTextMessage(7, false)];
      const state: ChatUiState = new ChatUiState(
        42, 'chat', messages, false, true, null, '', null, null,
        -1, [], 0, 0, true, [7]
      );

      const result: ReducerResult<ChatUiState, ChatEffect> =
        chatReducer(state, new ToggleMessageSelection(7), makeEnv());

      expect(result.state.selectionMode).assertFalse();
      expect(result.state.selectedMessageIds.length).assertEqual(0);
      expect(result.effects.length).assertEqual(0);
    });

    it('toggleMessageSelection_isNoOpWhenNotInSelectionMode', 0, () => {
      const messages: readonly MessageItem[] = [makeTextMessage(7, false)];
      const state: ChatUiState = makeStateWith(messages);

      const result: ReducerResult<ChatUiState, ChatEffect> =
        chatReducer(state, new ToggleMessageSelection(7), makeEnv());

      expect(result.state === state).assertTrue();
      expect(result.effects.length).assertEqual(0);
    });

    it('confirmForwardSelection_emitsOpenForwardPickerWithSelection', 0, () => {
      const messages: readonly MessageItem[] = [makeTextMessage(7, false), makeTextMessage(9, false)];
      const state: ChatUiState = new ChatUiState(
        42, 'chat', messages, false, true, null, '', null, null,
        -1, [], 0, 0, true, [7, 9]
      );

      const result: ReducerResult<ChatUiState, ChatEffect> =
        chatReducer(state, new ConfirmForwardSelection(), makeEnv());

      expect(result.effects.length).assertEqual(1);
      expect(result.effects[0].kind).assertEqual('openForwardPicker');
      const effect: OpenForwardPicker = result.effects[0] as OpenForwardPicker;
      expect(effect.fromChatId).assertEqual(42);
      expect(effect.messageIds.length).assertEqual(2);
      expect(effect.messageIds[0]).assertEqual(7);
      expect(effect.messageIds[1]).assertEqual(9);
    });

    it('confirmForwardSelection_isNoOpWithEmptySelection', 0, () => {
      const state: ChatUiState = makeStateWith([]);

      const result: ReducerResult<ChatUiState, ChatEffect> =
        chatReducer(state, new ConfirmForwardSelection(), makeEnv());

      expect(result.state === state).assertTrue();
      expect(result.effects.length).assertEqual(0);
    });

    it('forwardSelectedToChat_emitsForwardMessagesKeepingSelectionUntilCompletion', 0, () => {
      const messages: readonly MessageItem[] = [makeTextMessage(7, false)];
      const state: ChatUiState = new ChatUiState(
        42, 'chat', messages, false, true, null, '', null, null,
        -1, [], 0, 0, true, [7]
      );

      const result: ReducerResult<ChatUiState, ChatEffect> =
        chatReducer(state, new ForwardSelectedToChat(777, true), makeEnv());

      expect(result.effects.length).assertEqual(1);
      expect(result.effects[0].kind).assertEqual('forwardMessages');
      const effect: ForwardMessages = result.effects[0] as ForwardMessages;
      expect(effect.fromChatId).assertEqual(42);
      expect(effect.toChatId).assertEqual(777);
      expect(effect.sendCopy).assertTrue();
      expect(effect.messageIds[0]).assertEqual(7);
      // 失败要能换目标重试：请求发出时不收起选择态
      expect(result.state.selectionMode).assertTrue();
    });

    it('onForwardCompleted_exitsSelectionModeAndClearsError', 0, () => {
      const messages: readonly MessageItem[] = [makeTextMessage(7, false)];
      const state: ChatUiState = new ChatUiState(
        42, 'chat', messages, false, true, 'previous failure', '', null, null,
        -1, [], 0, 0, true, [7]
      );

      const result: ReducerResult<ChatUiState, ChatEffect> =
        chatReducer(state, new OnForwardCompleted(1), makeEnv());

      expect(result.state.selectionMode).assertFalse();
      expect(result.state.selectedMessageIds.length).assertEqual(0);
      expect(result.state.errorMessage).assertNull();
    });

    it('onForwardFailed_setsErrorAndKeepsSelection', 0, () => {
      const messages: readonly MessageItem[] = [makeTextMessage(7, false)];
      const state: ChatUiState = new ChatUiState(
        42, 'chat', messages, false, true, null, '', null, null,
        -1, [], 0, 0, true, [7]
      );

      const result: ReducerResult<ChatUiState, ChatEffect> = chatReducer(
        state,
        new OnForwardFailed(AppErrors.tdlib('bad_request', 'Cannot forward this message', false)),
        makeEnv()
      );

      expect(result.state.errorMessage).assertEqual('Cannot forward this message');
      expect(result.state.selectionMode).assertTrue();
      expect(result.state.selectedMessageIds.length).assertEqual(1);
    });

    it('backToChatList_exitsSelectionModeBeforeNavigatingBack', 0, () => {
      const messages: readonly MessageItem[] = [makeTextMessage(7, false)];
      const state: ChatUiState = new ChatUiState(
        42, 'chat', messages, false, true, null, '', null, null,
        -1, [], 0, 0, true, [7]
      );

      const first: ReducerResult<ChatUiState, ChatEffect> =
        chatReducer(state, new BackToChatList(), makeEnv());
      expect(first.state.selectionMode).assertFalse();
      expect(first.state.selectedMessageIds.length).assertEqual(0);
      expect(first.effects.length).assertEqual(0);

      const second: ReducerResult<ChatUiState, ChatEffect> =
        chatReducer(first.state, new BackToChatList(), makeEnv());
      expect(second.effects.length).assertEqual(1);
      expect(second.effects[0].kind).assertEqual('navigateBack');
    });

    it('onMessagesLoaded_prunesSelectionOfVanishedMessages', 0, () => {
      const state: ChatUiState = new ChatUiState(
        42, 'chat', [makeTextMessage(7, false)], false, true, null, '', null, null,
        -1, [], 0, 0, true, [7, 8]
      );

      // 8 已被删除：选择集合收敛为 [7]，仍可继续转发
      const result: ReducerResult<ChatUiState, ChatEffect> = chatReducer(
        state,
        new OnMessagesLoaded([makeTextMessage(7, false)], true, 0, 0),
        makeEnv()
      );

      expect(result.state.selectionMode).assertTrue();
      expect(result.state.selectedMessageIds.length).assertEqual(1);
      expect(result.state.selectedMessageIds[0]).assertEqual(7);
    });

    it('onMessagesLoaded_exitsSelectionModeWhenEverySelectedMessageVanished', 0, () => {
      const state: ChatUiState = new ChatUiState(
        42, 'chat', [makeTextMessage(7, false)], false, true, null, '', null, null,
        -1, [], 0, 0, true, [7]
      );

      const result: ReducerResult<ChatUiState, ChatEffect> = chatReducer(
        state,
        new OnMessagesLoaded([], true, 0, 0),
        makeEnv()
      );

      expect(result.state.selectionMode).assertFalse();
      expect(result.state.selectedMessageIds.length).assertEqual(0);
    });

    it('extractFirstLink_prefersSpanLink_fallbacksToRawUrl', 0, () => {
      // 无链接
      const msgNoLink: MessageItem = makeTextMessage(1, false, 'hello world');
      expect(extractFirstLink(msgNoLink)).assertNull();

      // 正文包含裸链接
      const msgRaw: MessageItem = makeTextMessage(2, false, 'check https://example.com/test now');
      expect(extractFirstLink(msgRaw)).assertEqual('https://example.com/test');

      // 正文 www 开头
      const msgWww: MessageItem = makeTextMessage(3, false, 'visit www.example.org today');
      expect(extractFirstLink(msgWww)).assertEqual('www.example.org');

      // span 链接优先于文本匹配
      const span: MessageTextSpan = new MessageTextSpan(
        'click', false, false, false, false, false, false, false, false, 'https://span-link.com'
      );
      const msgSpan: MessageItem = new MessageItem(
        4, 'click here https://raw-link.com', 1000, false, '', 'none', true, false, null, '', [span]
      );
      expect(extractFirstLink(msgSpan)).assertEqual('https://span-link.com');
    });

    it('pickAndSendPhoto_emitsPickAndSendPhotoEffect_withComposerTextAsCaption', 0, () => {
      const state: ChatUiState = makeState('photo caption');
      const result: ReducerResult<ChatUiState, ChatEffect> = chatReducer(
        state,
        new PickAndSendPhoto(),
        makeEnv()
      );

      expect(result.effects.length).assertEqual(1);
      const effect: PickAndSendPhotoEffect = result.effects[0] as PickAndSendPhotoEffect;
      expect(effect.kind).assertEqual('pickAndSendPhoto');
      expect(effect.chatId).assertEqual(42);
      expect(effect.caption).assertEqual('photo caption');
      expect(effect.replyToMessageId).assertEqual(0);
    });

    it('pickAndSendPhoto_withReplyMode_includesReplyToMessageId', 0, () => {
      const replyMode: ComposerReplyMode = new ComposerReplyMode(123, 'sender', 'text');
      const state: ChatUiState = makeStateWith([], 'caption', replyMode);
      const result: ReducerResult<ChatUiState, ChatEffect> = chatReducer(
        state,
        new PickAndSendPhoto(),
        makeEnv()
      );

      expect(result.effects.length).assertEqual(1);
      const effect: PickAndSendPhotoEffect = result.effects[0] as PickAndSendPhotoEffect;
      expect(effect.kind).assertEqual('pickAndSendPhoto');
      expect(effect.replyToMessageId).assertEqual(123);
      expect(effect.caption).assertEqual('caption');
    });

    it('restoreDraft_restoresTextAndReplyMode_whenComposerEmpty', 0, () => {
      const msg: MessageItem = new MessageItem(
        501, 'reply target message', 1000, false, 'Alice', 'none', true, false, null, ''
      );
      const state: ChatUiState = makeStateWith([msg], '');

      const result: ReducerResult<ChatUiState, ChatEffect> = chatReducer(
        state,
        new RestoreDraft('draft content', 501),
        makeEnv()
      );

      expect(result.state.composerText).assertEqual('draft content');
      expect(result.state.composerMode !== null).assertTrue();
      const replyMode: ComposerReplyMode = result.state.composerMode as ComposerReplyMode;
      expect(replyMode.kind).assertEqual('reply');
      expect(replyMode.targetMessageId).assertEqual(501);
      expect(replyMode.previewTitle).assertEqual('Alice');
      expect(replyMode.previewText).assertEqual('reply target message');
    });

    it('restoreDraft_fallbackAuthor_whenReplyTargetNotInMemory', 0, () => {
      const state: ChatUiState = makeState('');

      const result: ReducerResult<ChatUiState, ChatEffect> = chatReducer(
        state,
        new RestoreDraft('draft without message', 999),
        makeEnv()
      );

      expect(result.state.composerText).assertEqual('draft without message');
      expect(result.state.composerMode !== null).assertTrue();
      const replyMode: ComposerReplyMode = result.state.composerMode as ComposerReplyMode;
      expect(replyMode.targetMessageId).assertEqual(999);
      expect(replyMode.previewTitle).assertEqual('Reply');
    });

    it('restoreDraft_doesNotOverwrite_whenComposerAlreadyHasText', 0, () => {
      const state: ChatUiState = makeState('existing typed text');

      const result: ReducerResult<ChatUiState, ChatEffect> = chatReducer(
        state,
        new RestoreDraft('stale draft', 0),
        makeEnv()
      );

      expect(result.state.composerText).assertEqual('existing typed text');
      expect(result.state.composerMode === null).assertTrue();
    });

    it('restoreDraft_resolvesAuthorAndSnippet_whenMessagesLoadedLater', 0, () => {
      const initial: ChatUiState = makeState('');
      const restoredResult: ReducerResult<ChatUiState, ChatEffect> = chatReducer(
        initial,
        new RestoreDraft('pending draft', 601),
        makeEnv()
      );

      const msg: MessageItem = new MessageItem(
        601, 'arrived text', 1000, false, 'Bob', 'none', true, false, null, ''
      );
      const loadedResult: ReducerResult<ChatUiState, ChatEffect> = chatReducer(
        restoredResult.state,
        new OnMessagesLoaded([msg], false),
        makeEnv()
      );

      expect(loadedResult.state.composerText).assertEqual('pending draft');
      expect(loadedResult.state.composerMode !== null).assertTrue();
      const replyMode: ComposerReplyMode = loadedResult.state.composerMode as ComposerReplyMode;
      expect(replyMode.targetMessageId).assertEqual(601);
      expect(replyMode.previewTitle).assertEqual('Bob');
      expect(replyMode.previewText).assertEqual('arrived text');
    });

    it('openAttachmentMenu_setsShowAttachmentMenuTrue', 0, () => {
      const initial: ChatUiState = makeState('');
      expect(initial.showAttachmentMenu).assertFalse();

      const result: ReducerResult<ChatUiState, ChatEffect> = chatReducer(
        initial,
        new OpenAttachmentMenu(),
        makeEnv()
      );

      expect(result.state.showAttachmentMenu).assertTrue();
      expect(result.effects.length).assertEqual(0);
    });

    it('closeAttachmentMenu_setsShowAttachmentMenuFalse', 0, () => {
      const initial: ChatUiState = makeState('').copyWith({ showAttachmentMenu: true });
      expect(initial.showAttachmentMenu).assertTrue();

      const result: ReducerResult<ChatUiState, ChatEffect> = chatReducer(
        initial,
        new CloseAttachmentMenu(),
        makeEnv()
      );

      expect(result.state.showAttachmentMenu).assertFalse();
      expect(result.effects.length).assertEqual(0);
    });

    it('toggleAttachmentMenu_togglesState', 0, () => {
      const initial: ChatUiState = makeState('');
      const opened: ReducerResult<ChatUiState, ChatEffect> = chatReducer(
        initial,
        new ToggleAttachmentMenu(),
        makeEnv()
      );
      expect(opened.state.showAttachmentMenu).assertTrue();

      const closed: ReducerResult<ChatUiState, ChatEffect> = chatReducer(
        opened.state,
        new ToggleAttachmentMenu(),
        makeEnv()
      );
      expect(closed.state.showAttachmentMenu).assertFalse();
    });

    it('pickAndSendPhoto_closesAttachmentMenu', 0, () => {
      const initial: ChatUiState = makeState('').copyWith({ showAttachmentMenu: true });
      const result: ReducerResult<ChatUiState, ChatEffect> = chatReducer(
        initial,
        new PickAndSendPhoto(),
        makeEnv()
      );

      expect(result.state.showAttachmentMenu).assertFalse();
      expect(result.effects.length).assertEqual(1);
      expect(result.effects[0].kind).assertEqual('pickAndSendPhoto');
    });

    it('pickAndSendFile_closesAttachmentMenu', 0, () => {
      const initial: ChatUiState = makeState('').copyWith({ showAttachmentMenu: true });
      const result: ReducerResult<ChatUiState, ChatEffect> = chatReducer(
        initial,
        new PickAndSendFile(),
        makeEnv()
      );

      expect(result.state.showAttachmentMenu).assertFalse();
      expect(result.effects.length).assertEqual(1);
      expect(result.effects[0].kind).assertEqual('pickAndSendFile');
    });

    it('backToChatList_closesAttachmentMenu_withoutNavigatingBack', 0, () => {
      const initial: ChatUiState = makeState('').copyWith({ showAttachmentMenu: true });
      const result: ReducerResult<ChatUiState, ChatEffect> = chatReducer(
        initial,
        new BackToChatList(),
        makeEnv()
      );

      expect(result.state.showAttachmentMenu).assertFalse();
      expect(result.effects.length).assertEqual(0);
    });

    it('cancelMediaDownload_emitsCancelMediaDownloadEffect', 0, () => {
      const initial: ChatUiState = makeState('');
      const result: ReducerResult<ChatUiState, ChatEffect> = chatReducer(
        initial,
        new CancelMediaDownload(505),
        makeEnv()
      );

      expect(result.effects.length).assertEqual(1);
      expect(result.effects[0].kind).assertEqual('cancelMediaDownload');
      const effect: CancelMediaDownloadEffect = result.effects[0] as CancelMediaDownloadEffect;
      expect(effect.fileId).assertEqual(505);
    });

    it('onMessageActionMenuLoaded_failedMessage_hasShowResendAndNoReply', 0, () => {
      const failedMsg: MessageItem = new MessageItem(
        77,
        'failed text',
        1000,
        true,
        'Me',
        'failed',
        true
      );
      const initial: ChatUiState = makeStateWith([failedMsg]);
      const result: ReducerResult<ChatUiState, ChatEffect> = chatReducer(
        initial,
        new OnMessageActionMenuLoaded(77, false, false, false, false, false),
        makeEnv()
      );

      expect(result.state.actionMenu !== null).assertTrue();
      const menu: MessageActionMenuState = result.state.actionMenu as MessageActionMenuState;
      expect(menu.showResend).assertTrue();
      expect(menu.showReply).assertFalse();
      expect(menu.showDelete).assertTrue();
    });

    it('resendFailedMessage_closesMenuAndEmitsResendMessage', 0, () => {
      const failedMsg: MessageItem = new MessageItem(
        77,
        'failed text',
        1000,
        true,
        'Me',
        'failed',
        true
      );
      const menuState: MessageActionMenuState = new MessageActionMenuState(
        77,
        false,
        false,
        true,
        true,
        false,
        false,
        false,
        null,
        true
      );
      const initial: ChatUiState = makeStateWith([failedMsg]).copyWith({
        actionMenu: menuState
      });

      const result: ReducerResult<ChatUiState, ChatEffect> = chatReducer(
        initial,
        new ResendFailedMessage(77),
        makeEnv()
      );

      expect(result.state.actionMenu === null).assertTrue();
      expect(result.effects.length).assertEqual(1);
      expect(result.effects[0].kind).assertEqual('resendMessage');
      const effect: ResendMessage = result.effects[0] as ResendMessage;
      expect(effect.messageId).assertEqual(77);
      expect(effect.chatId).assertEqual(initial.chatId);
    });

    it('resendFailedMessage_ignoresNonFailedMessage', 0, () => {
      const normalMsg: MessageItem = new MessageItem(
        88,
        'normal text',
        1000,
        true,
        'Me',
        'none',
        true
      );
      const initial: ChatUiState = makeStateWith([normalMsg]);
      const result: ReducerResult<ChatUiState, ChatEffect> = chatReducer(
        initial,
        new ResendFailedMessage(88),
        makeEnv()
      );

      expect(result.effects.length).assertEqual(0);
    });

    // ---- SEARCH-102 聊天内搜索 ----

    it('openChatSearch_expandsSearchPanelAndClearsState', 0, () => {
      const initial: ChatUiState = makeState('', null);
      const result: ReducerResult<ChatUiState, ChatEffect> = chatReducer(
        initial,
        new OpenChatSearch(),
        makeEnv()
      );

      expect(result.state.showSearch).assertTrue();
      expect(result.state.searchQuery).assertEqual('');
      expect(result.state.searchResults.length).assertEqual(0);
      expect(result.state.jumpToMessageId).assertEqual(0);
      expect(result.effects.length).assertEqual(0);
    });

    it('openChatSearch_whenAlreadyOpen_isNoOp', 0, () => {
      const opened: ChatUiState = makeState('', null).copyWith({ showSearch: true });
      const result: ReducerResult<ChatUiState, ChatEffect> = chatReducer(
        opened,
        new OpenChatSearch(),
        makeEnv()
      );
      expect(result.state === opened).assertTrue();
    });

    it('closeChatSearch_collapsesPanelAndResetsResults', 0, () => {
      const opened: ChatUiState = makeState('', null).copyWith({
        showSearch: true,
        searchQuery: 'hello',
        searchResults: [new ChatSearchResultItem(10, 'hello world', '10:30')],
        isSearching: true
      });
      const result: ReducerResult<ChatUiState, ChatEffect> = chatReducer(
        opened,
        new CloseChatSearch(),
        makeEnv()
      );

      expect(result.state.showSearch).assertFalse();
      expect(result.state.searchQuery).assertEqual('');
      expect(result.state.searchResults.length).assertEqual(0);
      expect(result.state.isSearching).assertFalse();
    });

    it('chatSearchQueryChanged_updatesQuery_only', 0, () => {
      const opened: ChatUiState = makeState('', null).copyWith({ showSearch: true });
      const result: ReducerResult<ChatUiState, ChatEffect> = chatReducer(
        opened,
        new ChatSearchQueryChanged('  telegram  '),
        makeEnv()
      );

      expect(result.state.searchQuery).assertEqual('  telegram  ');
      expect(result.effects.length).assertEqual(0);
    });

    it('performChatSearch_emptyQuery_isNoOp', 0, () => {
      const opened: ChatUiState = makeState('', null).copyWith({ showSearch: true, searchQuery: '   ' });
      const result: ReducerResult<ChatUiState, ChatEffect> = chatReducer(
        opened,
        new PerformChatSearch(),
        makeEnv()
      );

      expect(result.effects.length).assertEqual(0);
    });

    it('performChatSearch_withQuery_emitsFetchChatSearch', 0, () => {
      const opened: ChatUiState = makeState('', null).copyWith({
        showSearch: true,
        searchQuery: '  hello  '
      });
      const result: ReducerResult<ChatUiState, ChatEffect> = chatReducer(
        opened,
        new PerformChatSearch(),
        makeEnv()
      );

      expect(result.state.isSearching).assertTrue();
      expect(result.effects.length).assertEqual(1);
      expect(result.effects[0].kind).assertEqual('fetchChatSearch');
      const effect: FetchChatSearch = result.effects[0] as FetchChatSearch;
      expect(effect.chatId).assertEqual(42);
      expect(effect.query).assertEqual('hello');
    });

    it('performChatSearch_whenAlreadySearching_isNoOp', 0, () => {
      const opened: ChatUiState = makeState('', null).copyWith({
        showSearch: true,
        searchQuery: 'hello',
        isSearching: true
      });
      const result: ReducerResult<ChatUiState, ChatEffect> = chatReducer(
        opened,
        new PerformChatSearch(),
        makeEnv()
      );

      expect(result.effects.length).assertEqual(0);
    });

    it('onChatSearchLoaded_storesResultsAndStopsSearching', 0, () => {
      const opened: ChatUiState = makeState('', null).copyWith({
        showSearch: true,
        searchQuery: 'hello',
        isSearching: true
      });
      const results: ChatSearchResultItem[] = [
        new ChatSearchResultItem(10, 'hello world', '10:30', true),
        new ChatSearchResultItem(20, 'say hello back', '10:31', false)
      ];
      const result: ReducerResult<ChatUiState, ChatEffect> = chatReducer(
        opened,
        new OnChatSearchLoaded(results),
        makeEnv()
      );

      expect(result.state.isSearching).assertFalse();
      expect(result.state.searchResults.length).assertEqual(2);
      expect(result.state.searchResults[0].messageId).assertEqual(10);
      expect(result.state.searchResults[1].jumpable).assertFalse();
    });

    it('onChatSearchFailed_setsErrorMessageAndStopsSearching', 0, () => {
      const opened: ChatUiState = makeState('', null).copyWith({
        showSearch: true,
        searchQuery: 'hello',
        isSearching: true
      });
      const result: ReducerResult<ChatUiState, ChatEffect> = chatReducer(
        opened,
        new OnChatSearchFailed(AppErrors.parameter('invalid', 'query', 'search failed')),
        makeEnv()
      );

      expect(result.state.isSearching).assertFalse();
      expect(result.state.errorMessage).assertEqual('search failed');
    });

    it('jumpToSearchResult_emitsJumpToMessage_andClosesPanel', 0, () => {
      const opened: ChatUiState = makeState('', null).copyWith({
        showSearch: true,
        searchResults: [new ChatSearchResultItem(10, 'hello world', '10:30')]
      });
      const result: ReducerResult<ChatUiState, ChatEffect> = chatReducer(
        opened,
        new JumpToSearchResult(10),
        makeEnv()
      );

      expect(result.state.showSearch).assertFalse();
      expect(result.state.jumpToMessageId).assertEqual(10);
      expect(result.effects.length).assertEqual(1);
      expect(result.effects[0].kind).assertEqual('jumpToMessage');
      const jump: JumpToMessage = result.effects[0] as JumpToMessage;
      expect(jump.messageId).assertEqual(10);
    });

    it('jumpToSearchResult_invalidOrAlreadyJumping_isNoOp', 0, () => {
      const opened: ChatUiState = makeState('', null).copyWith({
        showSearch: true,
        jumpToMessageId: 5
      });
      const resultNoOp: ReducerResult<ChatUiState, ChatEffect> = chatReducer(
        opened,
        new JumpToSearchResult(0),
        makeEnv()
      );
      expect(resultNoOp.effects.length).assertEqual(0);

      const resultBusy: ReducerResult<ChatUiState, ChatEffect> = chatReducer(
        opened,
        new JumpToSearchResult(10),
        makeEnv()
      );
      expect(resultBusy.effects.length).assertEqual(0);
    });

    it('onJumpToMessageReady_marksTargetReady', 0, () => {
      const initial: ChatUiState = makeState('', null);
      const result: ReducerResult<ChatUiState, ChatEffect> = chatReducer(
        initial,
        new OnJumpToMessageReady(77),
        makeEnv()
      );
      expect(result.state.jumpToMessageId).assertEqual(77);
    });

    it('clearJumpToMessage_resetsTarget', 0, () => {
      const withTarget: ChatUiState = makeState('', null).copyWith({ jumpToMessageId: 77 });
      const result: ReducerResult<ChatUiState, ChatEffect> = chatReducer(
        withTarget,
        new ClearJumpToMessage(),
        makeEnv()
      );
      expect(result.state.jumpToMessageId).assertEqual(0);
    });

    // ---- MSG-109 头部信息区 ----

    it('onHeaderSubtitleChanged_updatesSubtitle', 0, () => {
      const state: ChatUiState = makeState('', null);
      const result: ReducerResult<ChatUiState, ChatEffect> = chatReducer(
        state,
        new OnHeaderSubtitleChanged('在线'),
        makeEnv()
      );
      expect(result.state.headerSubtitle).assertEqual('在线');
      expect(result.effects.length).assertEqual(0);
    });

    it('onHeaderSubtitleChanged_sameValue_isNoOpSameStateRef', 0, () => {
      const state: ChatUiState = makeState('', null).copyWith({ headerSubtitle: '在线' });
      const result: ReducerResult<ChatUiState, ChatEffect> = chatReducer(
        state,
        new OnHeaderSubtitleChanged('在线'),
        makeEnv()
      );
      expect(result.state === state).assertTrue();
      expect(result.effects.length).assertEqual(0);
    });

    it('onChatKindChanged_updatesChatKind', 0, () => {
      const state: ChatUiState = makeState('', null);
      const result: ReducerResult<ChatUiState, ChatEffect> = chatReducer(
        state,
        new OnChatKindChanged('group'),
        makeEnv()
      );
      expect(result.state.chatKind).assertEqual('group');
      expect(result.effects.length).assertEqual(0);
    });

    it('onChatKindChanged_sameValue_isNoOpSameStateRef', 0, () => {
      const state: ChatUiState = makeState('', null).copyWith({ chatKind: 'private' });
      const result: ReducerResult<ChatUiState, ChatEffect> = chatReducer(
        state,
        new OnChatKindChanged('private'),
        makeEnv()
      );
      expect(result.state === state).assertTrue();
      expect(result.effects.length).assertEqual(0);
    });

    it('openChatProfile_isPureNavigation_stateUnchanged_noEffects', 0, () => {
      const state: ChatUiState = makeState('', null);
      const result: ReducerResult<ChatUiState, ChatEffect> = chatReducer(
        state,
        new OpenChatProfile(42),
        makeEnv()
      );
      expect(result.state === state).assertTrue();
      expect(result.effects.length).assertEqual(0);
    });

    it('chatMenuAction_isPlaceholder_stateUnchanged_noEffects', 0, () => {
      const state: ChatUiState = makeState('', null);
      const result: ReducerResult<ChatUiState, ChatEffect> = chatReducer(
        state,
        new ChatMenuAction('mute'),
        makeEnv()
      );
      expect(result.state === state).assertTrue();
      expect(result.effects.length).assertEqual(0);
    });
  });
}
