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
  OnForwardFailed
} from '../main/ets/contract/ChatIntent';
import {
  ChatEffect,
  SendTextMessage,
  FetchMessagePermissions,
  EditMessageText,
  DeleteMessages,
  NavigateBack,
  OpenForwardPicker,
  ForwardMessages
} from '../main/ets/contract/ChatEffect';
import { chatReducer } from '../main/ets/reducer/ChatReducer';

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
  });
}
