/**
 * feature/chat_list — 会话列表 Reducer 单测（MSG-108）。
 *
 * 覆盖：
 * 1. chatActionRequested：菜单文案（Pin/Unpin、Mark as read/unread）的判定；
 * 2. toggleChatPinned：目标态取反 + 收起菜单；
 * 3. toggleChatMarkedUnread：canMarkAsRead 为真时执行"读"、为假时执行"标未读"；
 * 4. dismissChatActionMenu / onChatActionFailed / 无菜单时的 no-op；
 * 5. canMarkChatAsRead 纯函数边界。
 */

import { describe, it, expect } from '@ohos/hypium';
import { ManualClock, SequentialIdGenerator, AppErrors } from '@tgx/core-common';
import { ReducerEnv, ReducerResult } from '@tgx/feature-template';
import { ChatListUiState, ChatActionMenuState } from '../main/ets/contract/ChatListUiState';
import { ChatListItem } from '../main/ets/model/ChatListItem';
import {
  ChatListIntent,
  ChatActionRequested,
  ToggleChatPinned,
  ToggleChatMarkedUnread,
  ToggleChatArchived,
  OpenArchivedChats,
  CloseArchivedChats,
  DismissChatActionMenu,
  OnChatActionFailed,
  OnChatsLoaded
} from '../main/ets/contract/ChatListIntent';
import {
  ChatListEffect,
  FetchChatList,
  SetChatPinned,
  SetChatReadState,
  SetChatArchived
} from '../main/ets/contract/ChatListEffect';
import { chatListReducer, canMarkChatAsRead } from '../main/ets/reducer/ChatListReducer';

function makeEnv(): ReducerEnv {
  const env: ReducerEnv = {
    clock: new ManualClock(1000, 500),
    ids: new SequentialIdGenerator('chat-list-test-')
  };
  return env;
}

function makeItem(
  chatId: number,
  unreadCount: number = 0,
  isPinned: boolean = false,
  isMarkedAsUnread: boolean = false
): ChatListItem {
  return new ChatListItem(
    chatId,
    `chat-${chatId}`,
    'preview',
    1000,
    unreadCount,
    '#FF000000',
    'C',
    isPinned,
    isMarkedAsUnread
  );
}

function makeState(items: readonly ChatListItem[], menu: ChatActionMenuState | null = null): ChatListUiState {
  return new ChatListUiState(items, false, null, menu);
}

export default function chatListReducerTest() {
  describe('ChatListReducerMsg108Test', () => {
    it('canMarkChatAsRead_matchesAndroidRule', 0, () => {
      // Android Tdlib.canMarkAsRead: unread_count > 0 || is_marked_as_unread
      expect(canMarkChatAsRead(makeItem(1, 3, false, false))).assertTrue();
      expect(canMarkChatAsRead(makeItem(1, 0, false, true))).assertTrue();
      expect(canMarkChatAsRead(makeItem(1, 0, false, false))).assertFalse();
      // 置顶与否不影响已读判定
      expect(canMarkChatAsRead(makeItem(1, 0, true, false))).assertFalse();
    });

    it('chatListItem_preservesAvatarPath', 0, () => {
      const itemWithAvatar = new ChatListItem(1, 'Test', 'msg', 1000, 0, '#FF0000', 'T', false, false, '/data/avatars/1.jpg');
      expect(itemWithAvatar.avatarPath).assertEqual('/data/avatars/1.jpg');

      const itemWithoutAvatar = new ChatListItem(2, 'Test 2', 'msg', 1000, 0, '#FF0000', 'T');
      expect(itemWithoutAvatar.avatarPath).assertNull();
    });

    it('chatActionRequested_opensMenuWithCurrentPinAndReadState', 0, () => {
      const state: ChatListUiState = makeState([makeItem(7, 3, true, false)]);
      const result: ReducerResult<ChatListUiState, ChatListEffect> =
        chatListReducer(state, new ChatActionRequested(7), makeEnv());

      const menu: ChatActionMenuState | null = result.state.actionMenu;
      expect(menu !== null).assertTrue();
      if (menu !== null) {
        expect(menu.chatId).assertEqual(7);
        expect(menu.isPinned).assertTrue();
        expect(menu.canMarkAsRead).assertTrue();
      }
      expect(result.effects.length).assertEqual(0);
    });

    it('chatActionRequested_unreadZeroUnmarked_offersMarkAsUnread', 0, () => {
      const state: ChatListUiState = makeState([makeItem(7, 0, false, false)]);
      const result: ReducerResult<ChatListUiState, ChatListEffect> =
        chatListReducer(state, new ChatActionRequested(7), makeEnv());

      const menu: ChatActionMenuState | null = result.state.actionMenu;
      expect(menu !== null).assertTrue();
      if (menu !== null) {
        expect(menu.canMarkAsRead).assertFalse();
      }
    });

    it('chatActionRequested_markedAsUnread_offersMarkAsRead', 0, () => {
      const state: ChatListUiState = makeState([makeItem(7, 0, false, true)]);
      const result: ReducerResult<ChatListUiState, ChatListEffect> =
        chatListReducer(state, new ChatActionRequested(7), makeEnv());

      const menu: ChatActionMenuState | null = result.state.actionMenu;
      expect(menu !== null).assertTrue();
      if (menu !== null) {
        expect(menu.canMarkAsRead).assertTrue();
      }
    });

    it('chatActionRequested_unknownChat_isNoOpSameRef', 0, () => {
      const state: ChatListUiState = makeState([makeItem(7)]);
      const result: ReducerResult<ChatListUiState, ChatListEffect> =
        chatListReducer(state, new ChatActionRequested(999), makeEnv());

      expect(result.state === state).assertTrue();
      expect(result.state.actionMenu).assertNull();
    });

    it('toggleChatPinned_invertsStateAndClosesMenu', 0, () => {
      const menu: ChatActionMenuState = new ChatActionMenuState(7, 'chat-7', false, false);
      const state: ChatListUiState = makeState([makeItem(7)], menu);

      const result: ReducerResult<ChatListUiState, ChatListEffect> =
        chatListReducer(state, new ToggleChatPinned(), makeEnv());

      expect(result.effects.length).assertEqual(1);
      expect(result.effects[0].kind).assertEqual('setChatPinned');
      const effect: SetChatPinned = result.effects[0] as SetChatPinned;
      expect(effect.chatId).assertEqual(7);
      expect(effect.isPinned).assertTrue();
      expect(result.state.actionMenu).assertNull();
    });

    it('toggleChatPinned_whenPinned_emitsUnpin', 0, () => {
      const menu: ChatActionMenuState = new ChatActionMenuState(7, 'chat-7', true, false);
      const state: ChatListUiState = makeState([makeItem(7, 0, true)], menu);

      const result: ReducerResult<ChatListUiState, ChatListEffect> =
        chatListReducer(state, new ToggleChatPinned(), makeEnv());

      const effect: SetChatPinned = result.effects[0] as SetChatPinned;
      expect(effect.isPinned).assertFalse();
    });

    it('toggleChatPinned_withoutMenu_isNoOp', 0, () => {
      const state: ChatListUiState = makeState([makeItem(7)]);
      const result: ReducerResult<ChatListUiState, ChatListEffect> =
        chatListReducer(state, new ToggleChatPinned(), makeEnv());

      expect(result.state === state).assertTrue();
      expect(result.effects.length).assertEqual(0);
    });

    it('toggleChatMarkedUnread_whenCanMarkRead_emitsMarkAsRead', 0, () => {
      // 有未读 → 菜单显示 "Mark as read" → markAsUnread=false
      const menu: ChatActionMenuState = new ChatActionMenuState(7, 'chat-7', false, true);
      const state: ChatListUiState = makeState([makeItem(7, 5)], menu);

      const result: ReducerResult<ChatListUiState, ChatListEffect> =
        chatListReducer(state, new ToggleChatMarkedUnread(), makeEnv());

      expect(result.effects.length).assertEqual(1);
      expect(result.effects[0].kind).assertEqual('setChatReadState');
      const effect: SetChatReadState = result.effects[0] as SetChatReadState;
      expect(effect.chatId).assertEqual(7);
      expect(effect.markAsUnread).assertFalse();
      expect(result.state.actionMenu).assertNull();
    });

    it('toggleChatMarkedUnread_whenCannotMarkRead_emitsMarkAsUnread', 0, () => {
      // 无未读且未标未读 → 菜单显示 "Mark as unread" → markAsUnread=true
      const menu: ChatActionMenuState = new ChatActionMenuState(7, 'chat-7', false, false);
      const state: ChatListUiState = makeState([makeItem(7, 0)], menu);

      const result: ReducerResult<ChatListUiState, ChatListEffect> =
        chatListReducer(state, new ToggleChatMarkedUnread(), makeEnv());

      const effect: SetChatReadState = result.effects[0] as SetChatReadState;
      expect(effect.markAsUnread).assertTrue();
    });

    it('dismissChatActionMenu_clearsMenu', 0, () => {
      const menu: ChatActionMenuState = new ChatActionMenuState(7, 'chat-7', false, false);
      const state: ChatListUiState = makeState([makeItem(7)], menu);

      const result: ReducerResult<ChatListUiState, ChatListEffect> =
        chatListReducer(state, new DismissChatActionMenu(), makeEnv());

      expect(result.state.actionMenu).assertNull();
      expect(result.effects.length).assertEqual(0);
    });

    it('dismissChatActionMenu_withoutMenu_isNoOpSameRef', 0, () => {
      const state: ChatListUiState = makeState([makeItem(7)]);
      const result: ReducerResult<ChatListUiState, ChatListEffect> =
        chatListReducer(state, new DismissChatActionMenu(), makeEnv());

      expect(result.state === state).assertTrue();
    });

    it('onChatActionFailed_setsErrorMessage', 0, () => {
      const state: ChatListUiState = makeState([makeItem(7)]);
      const result: ReducerResult<ChatListUiState, ChatListEffect> = chatListReducer(
        state,
        new OnChatActionFailed(AppErrors.tdlib('bad_request', 'Chat is not in the list', false)),
        makeEnv()
      );

      expect(result.state.errorMessage).assertEqual('Chat is not in the list');
      expect(result.effects.length).assertEqual(0);
    });

    it('existingFlow_stillWorksAfterExtension', 0, () => {
      // 回归：既有 OnChatsLoaded 仍只更新 items，不动菜单
      const menu: ChatActionMenuState = new ChatActionMenuState(7, 'chat-7', false, false);
      const state: ChatListUiState = makeState([makeItem(7)], menu);
      const loaded: ReducerResult<ChatListUiState, ChatListEffect> = chatListReducer(
        state,
        new OnChatsLoaded([makeItem(8)]),
        makeEnv()
      );
      expect(loaded.state.items.length).assertEqual(1);
      expect(loaded.state.items[0].chatId).assertEqual(8);
    });

    it('openArchivedChats_switchesToArchiveAndEmitsFetch', 0, () => {
      const state: ChatListUiState = makeState([makeItem(1)]);
      const result: ReducerResult<ChatListUiState, ChatListEffect> = chatListReducer(
        state,
        new OpenArchivedChats(),
        makeEnv()
      );

      expect(result.state.listKind).assertEqual('archive');
      expect(result.state.items.length).assertEqual(0);
      expect(result.state.isLoading).assertTrue();
      expect(result.effects.length).assertEqual(1);
      expect(result.effects[0].kind).assertEqual('fetchChatList');
      const fetchEffect: FetchChatList = result.effects[0] as FetchChatList;
      expect(fetchEffect.listKind).assertEqual('archive');

      // 已在 archive 时再发 openArchivedChats 为 no-op
      const noOpResult: ReducerResult<ChatListUiState, ChatListEffect> = chatListReducer(
        result.state,
        new OpenArchivedChats(),
        makeEnv()
      );
      expect(noOpResult.state === result.state).assertTrue();
      expect(noOpResult.effects.length).assertEqual(0);
    });

    it('closeArchivedChats_switchesToMainAndEmitsFetch', 0, () => {
      const archiveState: ChatListUiState = new ChatListUiState([makeItem(9)], false, null, null, 'archive', 0);
      const result: ReducerResult<ChatListUiState, ChatListEffect> = chatListReducer(
        archiveState,
        new CloseArchivedChats(),
        makeEnv()
      );

      expect(result.state.listKind).assertEqual('main');
      expect(result.state.items.length).assertEqual(0);
      expect(result.state.isLoading).assertTrue();
      expect(result.effects.length).assertEqual(1);
      expect(result.effects[0].kind).assertEqual('fetchChatList');
      const fetchEffect: FetchChatList = result.effects[0] as FetchChatList;
      expect(fetchEffect.listKind).assertEqual('main');

      // 已在 main 时再发 closeArchivedChats 为 no-op
      const noOpResult: ReducerResult<ChatListUiState, ChatListEffect> = chatListReducer(
        result.state,
        new CloseArchivedChats(),
        makeEnv()
      );
      expect(noOpResult.state === result.state).assertTrue();
      expect(noOpResult.effects.length).assertEqual(0);
    });

    it('toggleChatArchived_inMainList_emitsArchive', 0, () => {
      const menu: ChatActionMenuState = new ChatActionMenuState(7, 'chat-7', false, false, false);
      const state: ChatListUiState = makeState([makeItem(7)], menu);

      const result: ReducerResult<ChatListUiState, ChatListEffect> = chatListReducer(
        state,
        new ToggleChatArchived(),
        makeEnv()
      );

      expect(result.effects.length).assertEqual(1);
      expect(result.effects[0].kind).assertEqual('setChatArchived');
      const effect: SetChatArchived = result.effects[0] as SetChatArchived;
      expect(effect.chatId).assertEqual(7);
      expect(effect.archived).assertTrue();
      expect(result.state.actionMenu).assertNull();
    });

    it('toggleChatArchived_inArchiveList_emitsUnarchive', 0, () => {
      const menu: ChatActionMenuState = new ChatActionMenuState(7, 'chat-7', false, false, true);
      const state: ChatListUiState = new ChatListUiState([makeItem(7)], false, null, menu, 'archive');

      const result: ReducerResult<ChatListUiState, ChatListEffect> = chatListReducer(
        state,
        new ToggleChatArchived(),
        makeEnv()
      );

      expect(result.effects.length).assertEqual(1);
      expect(result.effects[0].kind).assertEqual('setChatArchived');
      const effect: SetChatArchived = result.effects[0] as SetChatArchived;
      expect(effect.chatId).assertEqual(7);
      expect(effect.archived).assertFalse();
      expect(result.state.actionMenu).assertNull();
    });

    it('chatActionRequested_inArchiveList_setsIsArchivedTrue', 0, () => {
      const state: ChatListUiState = new ChatListUiState([makeItem(7)], false, null, null, 'archive');
      const result: ReducerResult<ChatListUiState, ChatListEffect> = chatListReducer(
        state,
        new ChatActionRequested(7),
        makeEnv()
      );

      expect(result.state.actionMenu !== null).assertTrue();
      if (result.state.actionMenu !== null) {
        expect(result.state.actionMenu.isArchived).assertTrue();
      }
    });

    it('onChatsLoaded_carriesArchiveStats', 0, () => {
      const state: ChatListUiState = makeState([]);
      const loaded: ReducerResult<ChatListUiState, ChatListEffect> = chatListReducer(
        state,
        new OnChatsLoaded([makeItem(8)], 12, 3),
        makeEnv()
      );

      expect(loaded.state.archiveUnreadCount).assertEqual(12);
      expect(loaded.state.archiveChatCount).assertEqual(3);
    });
  });
}
