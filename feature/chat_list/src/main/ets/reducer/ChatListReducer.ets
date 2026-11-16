/**
 * feature/chat_list — 会话列表纯 Reducer（CHATLIST-002 + MSG-108）。
 *
 * 遵循计划 §5.11 / UI-003：
 * - 纯函数：(state, intent, env) -> ReducerResult<ChatListUiState, ChatListEffect>
 * - 禁止直接修改 state；无变化返回原引用 reduced(state)
 * - 禁止在 reducer 内做 I/O 或异步，加载请求只产出 FetchChatList 描述
 *
 * MSG-108 新增单会话操作流：
 * - chatActionRequested → 从当前行算菜单文案（isPinned / canMarkAsRead），
 *   行已不存在则忽略；
 * - toggleChatPinned → SetChatPinned(chatId, !menu.isPinned)；
 * - toggleChatMarkedUnread → SetChatReadState(chatId, markAsUnread = !canMarkAsRead)，
 *   即"菜单显示 Mark as read 时执行读、显示 Mark as unread 时执行标未读"；
 * - 两个动作都顺手收起菜单（点击即离场，不等异步回执）；
 * - onChatActionFailed → errorMessage 细条。
 *
 * DRAWER-101 新增抽屉流：
 * - drawerOpened → FetchDrawerAccount（accountUserId>0 后不再重复请求）；
 * - drawerItemClicked → 按 key 分流：contacts/settings 纯导航，saved 走
 *   OpenSavedMessages（createPrivateChat 解析自己的私聊），未落地项不产 effect；
 * - drawerAccountClicked → DrawerNavigate('selfProfile')。
 *
 * GROUP-CREATE-101 新增建群/建频道命名段：
 * - drawerItemClicked(newGroup/newChannel) → DrawerNavigate（成员多选与命名页
 *   的接力由装配层完成）；
 * - groupCreateStarted 初始化命名段状态；标题/简介输入只改状态；
 * - groupCreateSubmitRequested 本地校验标题（空/超 128 字 → 内联错误 key，
 *   不出请求；合法 → CreateBasicGroupChat / CreateSupergroupChat）；
 * - onGroupChatCreated 清流程态并复用 NavigateToChat 进新会话；
 * - onGroupCreateFailed 落通用错误 key 并复位 isSubmitting 允许重试。
 */

import { Reducer, ReducerEnv, ReducerResult, reduced } from '@tgx/feature-template';
import { GROUP_TITLE_MAX_LENGTH } from '@tgx/core-domain';
import { ChatListUiState, ChatActionMenuState } from '../contract/ChatListUiState';
import { DrawerItemKey, DrawerState, isDrawerAccountLoaded } from '../contract/DrawerState';
import { GroupCreateState } from '../contract/GroupCreateState';
import { ChatListItem } from '../model/ChatListItem';
import {
  ChatListIntent,
  ChatSelected,
  OnChatsLoaded,
  OnChatsLoadFailed,
  ChatActionRequested,
  OnChatActionFailed,
  SelectChatFolder,
  DrawerItemClicked,
  OnDrawerAccountLoaded,
  OnDrawerAvatarLoaded,
  DrawerNightModeSet,
  GroupCreateStarted,
  GroupCreateTitleChanged,
  GroupCreateDescriptionChanged,
  GroupCreateSubmitRequested,
  GroupCreateCancelled,
  OnGroupChatCreated,
  OnGroupCreateFailed
} from '../contract/ChatListIntent';
import {
  ChatListEffect,
  FetchChatList,
  NavigateToChat,
  ShowToast,
  SetChatArchived,
  SetChatPinned,
  SetChatReadState,
  FetchDrawerAccount,
  DrawerNavigate,
  OpenSavedMessages,
  CreateBasicGroupChat,
  CreateSupergroupChat
} from '../contract/ChatListEffect';

export const CHAT_LIST_PAGE_SIZE: number = 20;

// ---- GROUP-CREATE-101 内联错误文案 key（传 key 不传串；词条由装配侧词典提供）----

/** 标题为空（提交被本地拦截）。 */
export const GROUP_CREATE_TITLE_EMPTY_KEY: string = 'Title is required';
/** 标题超 128 字（提交被本地拦截）。 */
export const GROUP_CREATE_TITLE_TOO_LONG_KEY: string = 'Title is too long';
/** 创建请求失败（TDLib 请求级/响应级错误，细节进日志）。 */
export const GROUP_CREATE_FAILED_KEY: string = 'Failed to create group';

/**
 * 标题本地校验 → 内联错误 Lang key；合法返回 null。
 * 上限取 core/domain 的 GROUP_TITLE_MAX_LENGTH（与 GroupChatCreator 的
 * validateGroupTitle 同一条口径），页面经 this.t(key) 现取文案。
 */
export function groupCreateTitleErrorKey(title: string): string | null {
  const trimmed: string = title.trim();
  if (trimmed.length === 0) {
    return GROUP_CREATE_TITLE_EMPTY_KEY;
  }
  if (trimmed.length > GROUP_TITLE_MAX_LENGTH) {
    return GROUP_CREATE_TITLE_TOO_LONG_KEY;
  }
  return null;
}

/** 按 chatId 取当前行；不存在返回 null。 */
function findItem(state: ChatListUiState, chatId: number): ChatListItem | null {
  for (let i = 0; i < state.items.length; i++) {
    if (state.items[i].chatId === chatId) {
      return state.items[i];
    }
  }
  return null;
}

/**
 * 是否该显示 "Mark as read"（MSG-108）。
 * 对齐 Android `Tdlib.canMarkAsRead`：`unread_count > 0 || is_marked_as_unread`。
 * 纯函数导出供单测与 UI 复用。
 */
export function canMarkChatAsRead(item: ChatListItem): boolean {
  return item.unreadCount > 0 || item.isMarkedAsUnread;
}

export const chatListReducer: Reducer<ChatListUiState, ChatListIntent, ChatListEffect> = (
  state: ChatListUiState,
  intent: ChatListIntent,
  env: ReducerEnv
): ReducerResult<ChatListUiState, ChatListEffect> => {
  switch (intent.kind) {
    case 'loadChats':
    case 'refreshChats': {
      if (state.isLoading) {
        return reduced(state);
      }
      const nextState: ChatListUiState = state.copyWith({
        isLoading: true,
        errorMessage: null
      });
      const effects: ChatListEffect[] = [new FetchChatList(CHAT_LIST_PAGE_SIZE, state.listKind)];
      return reduced(nextState, effects);
    }

    case 'chatSelected': {
      const selectIntent: ChatSelected = intent as ChatSelected;
      const effects: ChatListEffect[] = [new NavigateToChat(selectIntent.chatId)];
      return reduced(state, effects);
    }

    case 'selectChatFolder': {
      const selectFolder: SelectChatFolder = intent as SelectChatFolder;
      if (state.selectedFolderId === selectFolder.folderId) {
        return reduced(state);
      }
      return reduced(state.copyWith({ selectedFolderId: selectFolder.folderId }));
    }

    case 'onChatsLoaded': {
      const loadedIntent: OnChatsLoaded = intent as OnChatsLoaded;
      const nextState: ChatListUiState = state.copyWith({
        items: loadedIntent.items,
        isLoading: false,
        errorMessage: null,
        archiveUnreadCount: loadedIntent.archiveUnreadCount,
        archiveChatCount: loadedIntent.archiveChatCount,
        folders: loadedIntent.folders
      });
      return reduced(nextState);
    }

    case 'onChatsLoadFailed': {
      const failedIntent: OnChatsLoadFailed = intent as OnChatsLoadFailed;
      const nextState: ChatListUiState = state.copyWith({
        isLoading: false,
        errorMessage: failedIntent.error.message
      });
      const effects: ChatListEffect[] = [new ShowToast(failedIntent.error.message)];
      return reduced(nextState, effects);
    }

    case 'openArchivedChats': {
      if (state.listKind === 'archive') {
        return reduced(state);
      }
      const nextState: ChatListUiState = state.copyWith({
        items: [],
        listKind: 'archive',
        isLoading: true,
        actionMenu: null,
        errorMessage: null
      });
      const effects: ChatListEffect[] = [new FetchChatList(CHAT_LIST_PAGE_SIZE, 'archive')];
      return reduced(nextState, effects);
    }

    case 'closeArchivedChats': {
      if (state.listKind === 'main') {
        return reduced(state);
      }
      const nextState: ChatListUiState = state.copyWith({
        items: [],
        listKind: 'main',
        isLoading: true,
        actionMenu: null,
        errorMessage: null
      });
      const effects: ChatListEffect[] = [new FetchChatList(CHAT_LIST_PAGE_SIZE, 'main')];
      return reduced(nextState, effects);
    }

    // ---- MSG-108 单会话操作 ----

    case 'chatActionRequested': {
      const requested: ChatActionRequested = intent as ChatActionRequested;
      const item: ChatListItem | null = findItem(state, requested.chatId);
      if (item === null) {
        return reduced(state);
      }
      const menu: ChatActionMenuState = new ChatActionMenuState(
        item.chatId,
        item.title,
        item.isPinned,
        canMarkChatAsRead(item),
        state.listKind === 'archive'
      );
      return reduced(state.copyWith({ actionMenu: menu }));
    }

    case 'toggleChatPinned': {
      const menu: ChatActionMenuState | null = state.actionMenu;
      if (menu === null) {
        return reduced(state);
      }
      // 菜单记录的是"当前"态，动作是取反。
      const effects: ChatListEffect[] = [new SetChatPinned(menu.chatId, !menu.isPinned)];
      return reduced(state.copyWith({ actionMenu: null, errorMessage: null }), effects);
    }

    case 'toggleChatMarkedUnread': {
      const menu: ChatActionMenuState | null = state.actionMenu;
      if (menu === null) {
        return reduced(state);
      }
      // canMarkAsRead=true（当前有未读/已标未读）→ 执行"标记已读"（markAsUnread=false）
      const markAsUnread: boolean = !menu.canMarkAsRead;
      const effects: ChatListEffect[] = [new SetChatReadState(menu.chatId, markAsUnread)];
      return reduced(state.copyWith({ actionMenu: null, errorMessage: null }), effects);
    }

    case 'toggleChatArchived': {
      const menu: ChatActionMenuState | null = state.actionMenu;
      if (menu === null) {
        return reduced(state);
      }
      const effects: ChatListEffect[] = [new SetChatArchived(menu.chatId, !menu.isArchived)];
      return reduced(state.copyWith({ actionMenu: null, errorMessage: null }), effects);
    }

    case 'dismissChatActionMenu': {
      if (state.actionMenu === null) {
        return reduced(state);
      }
      return reduced(state.copyWith({ actionMenu: null }));
    }

    case 'onChatActionFailed': {
      const failed: OnChatActionFailed = intent as OnChatActionFailed;
      const nextState: ChatListUiState = state.copyWith({
        errorMessage: failed.error.message
      });
      return reduced(nextState);
    }

    // ---- DRAWER-101 抽屉账号头 / 菜单项 ----

    case 'drawerAccountRequested': {
      // 幂等：账号头已回灌过就不再请求（≡ 反复开合、start() 预热共用一条路径）。
      if (isDrawerAccountLoaded(state.drawer)) {
        return reduced(state);
      }
      return reduced(state, [new FetchDrawerAccount()]);
    }

    case 'onDrawerAccountLoaded': {
      const loaded: OnDrawerAccountLoaded = intent as OnDrawerAccountLoaded;
      const drawer: DrawerState = state.drawer.copyWith({
        accountUserId: loaded.userId,
        accountName: loaded.name,
        accountPhone: loaded.phone,
        accountAvatarLetters: loaded.avatarLetters
      });
      return reduced(state.copyWith({ drawer: drawer }));
    }

    case 'onDrawerAvatarLoaded': {
      const avatar: OnDrawerAvatarLoaded = intent as OnDrawerAvatarLoaded;
      if (state.drawer.accountAvatarPath === avatar.avatarPath) {
        return reduced(state);
      }
      return reduced(state.copyWith({
        drawer: state.drawer.copyWith({ accountAvatarPath: avatar.avatarPath })
      }));
    }

    case 'drawerItemClicked': {
      const clicked: DrawerItemClicked = intent as DrawerItemClicked;
      const item: DrawerItemKey = clicked.item;
      if (item === 'newGroup') {
        // GROUP-CREATE-101：入口只发导航意图——成员多选与命名段的接力由装配层完成。
        return reduced(state, [new DrawerNavigate('newGroup')]);
      }
      if (item === 'newChannel') {
        return reduced(state, [new DrawerNavigate('newChannel')]);
      }
      if (item === 'contacts') {
        return reduced(state, [new DrawerNavigate('contacts')]);
      }
      if (item === 'settings') {
        return reduced(state, [new DrawerNavigate('settings')]);
      }
      if (item === 'saved') {
        return reduced(state, [new OpenSavedMessages()]);
      }
      // 'calls' / 'invite' / 'help'：TGX 侧对应页面尚未迁移，点击不产生副作用。
      return reduced(state);
    }

    case 'drawerAccountClicked': {
      return reduced(state, [new DrawerNavigate('selfProfile')]);
    }

    case 'drawerNightModeSet': {
      const set: DrawerNightModeSet = intent as DrawerNightModeSet;
      if (state.drawer.nightMode === set.on) {
        return reduced(state);
      }
      return reduced(state.copyWith({
        drawer: state.drawer.copyWith({ nightMode: set.on })
      }));
    }

    // ---- GROUP-CREATE-101 建群/建频道命名段 ----

    case 'groupCreateStarted': {
      const started: GroupCreateStarted = intent as GroupCreateStarted;
      // 重复进入（装配层重复派发）：以最新一次为准重开流程，不保留旧输入。
      return reduced(state.copyWith({
        groupCreate: new GroupCreateState(started.mode, started.memberUserIds)
      }));
    }

    case 'groupCreateTitleChanged': {
      const changed: GroupCreateTitleChanged = intent as GroupCreateTitleChanged;
      if (state.groupCreate === null) {
        return reduced(state);
      }
      // 输入即清错：错误条描述的是上一次提交，继续输入说明用户已在修正。
      return reduced(state.copyWith({
        groupCreate: state.groupCreate.copyWith({ title: changed.title, errorMessageKey: null })
      }));
    }

    case 'groupCreateDescriptionChanged': {
      const changed: GroupCreateDescriptionChanged = intent as GroupCreateDescriptionChanged;
      if (state.groupCreate === null) {
        return reduced(state);
      }
      return reduced(state.copyWith({
        groupCreate: state.groupCreate.copyWith({ description: changed.description })
      }));
    }

    case 'groupCreateSubmitRequested': {
      const current: GroupCreateState | null = state.groupCreate;
      if (current === null || current.isSubmitting) {
        return reduced(state);
      }
      // 本地先拦（与 core/domain validateGroupTitle 同一条口径）：标题空 /
      // 超 128 字只落内联错误 key，不出请求。
      const titleErrorKey: string | null = groupCreateTitleErrorKey(current.title);
      if (titleErrorKey !== null) {
        return reduced(state.copyWith({
          groupCreate: current.copyWith({ errorMessageKey: titleErrorKey })
        }));
      }
      // effect 带的是 trim 后原文：请求投影侧还会再校验一次（双保险）。
      const effects: ChatListEffect[] = current.mode === 'channel'
        ? [new CreateSupergroupChat(current.title.trim(), true, current.description.trim())]
        : [new CreateBasicGroupChat(current.title.trim(), current.memberUserIds)];
      return reduced(state.copyWith({
        groupCreate: current.copyWith({ isSubmitting: true, errorMessageKey: null })
      }), effects);
    }

    case 'groupCreateCancelled': {
      if (state.groupCreate === null) {
        return reduced(state);
      }
      return reduced(state.copyWith({ groupCreate: null }));
    }

    case 'onGroupChatCreated': {
      // 流程已不在途（用户在请求飞行中取消了命名页）→ 静默：群仍会建出来
      // 进列表，但不把已离开的用户拽进新会话（与 no-op 规范一致）。
      if (state.groupCreate === null) {
        return reduced(state);
      }
      const created: OnGroupChatCreated = intent as OnGroupChatCreated;
      // 成功即离场：清流程状态 + 进新会话（与列表点击同一条导航链路）。
      const effects: ChatListEffect[] = [new NavigateToChat(created.chatId)];
      return reduced(state.copyWith({ groupCreate: null }), effects);
    }

    case 'onGroupCreateFailed': {
      if (state.groupCreate === null) {
        return reduced(state);
      }
      // 通用错误 key（TDLib 细节进日志不进 UI）；isSubmitting 复位允许重试。
      return reduced(state.copyWith({
        groupCreate: state.groupCreate.copyWith({
          isSubmitting: false,
          errorMessageKey: GROUP_CREATE_FAILED_KEY
        })
      }));
    }
  }

  return reduced(state);
};
