/**
 * feature/profile — 群组/频道资料页协调器（PROFILE-102）。
 *
 * 遵循 100% Kit-free 架构规范：
 * - 纯端口注入（ClipboardPort, ToastPort, Logger）；
 * - 协调 ChatRegistry, GroupRegistry, UserRegistry, FileRegistry；
 * - 聚合群详情与首屏成员列表（对标 Telegram-X ProfileController.Args(chat)）。
 */

import { AccountScope } from '@tgx/core-account';
import { AppError, Result, ManualClock, SequentialIdGenerator } from '@tgx/core-common';
import {
  ChatRegistry,
  GroupRegistry,
  UserRegistry,
  FileRegistry,
  formatFullName,
  getAvatarLetters,
  getAvatarColorIndex,
  isOnline,
  formatMemberRole
} from '@tgx/core-domain';
import {
  File,
  Chat,
  BasicGroupFullInfo,
  SupergroupFullInfo,
  ChatMember,
  ChatMembers,
  User,
  GetChat,
  encodeGetChat,
  decodeChat,
  TdJsonRaw,
  ChatTypeBasicGroup,
  ChatTypeSupergroup,
  MessageSenderUser
} from '@tgx/core-td-api-generated';
import { TdWireObject, TdPendingRequest } from '@tgx/td-gateway';
import { ClipboardPort, ToastPort, Subscription } from '@tgx/platform-ports';
import { Logger } from '@tgx/observability';
import { ReducerResult, ReducerEnv } from '@tgx/feature-template';
import { ChatProfileUiState, ChatMemberUiItem } from '../contract/ChatProfileUiState';
import {
  ChatProfileIntent,
  OpenChatProfile,
  OnChatLoaded,
  OnBasicGroupFullInfoLoaded,
  OnSupergroupFullInfoLoaded,
  OnChatMembersLoaded,
  OnChatAvatarLoaded,
  OnChatProfileError
} from '../contract/ChatProfileIntent';
import {
  ChatProfileEffect,
  FetchChatDetailsEffect,
  NavigateToUserProfileEffect,
  CopyInviteLinkEffect,
  NavigateBackEffect
} from '../contract/ChatProfileEffect';
import { chatProfileReducer } from '../reducer/ChatProfileReducer';

export interface ChatProfileCoordinatorOptions {
  readonly onNavigateToUserProfile?: (userId: number) => void;
  readonly onNavigateBack?: () => void;
}

export class ChatProfileCoordinator {
  private readonly scope: AccountScope;
  private readonly chatRegistry: ChatRegistry;
  private readonly groupRegistry: GroupRegistry;
  private readonly userRegistry: UserRegistry;
  private readonly fileRegistry: FileRegistry;
  private readonly clipboardPort: ClipboardPort;
  private readonly toastPort: ToastPort;
  private readonly logger: Logger;
  private readonly options: ChatProfileCoordinatorOptions;
  private readonly env: ReducerEnv;

  private state: ChatProfileUiState = ChatProfileUiState.initial();
  private onStateChangedListener: ((state: ChatProfileUiState) => void) | null = null;
  private activeChatId: number = 0;
  private subscriptions: Subscription[] = [];

  constructor(
    scope: AccountScope,
    chatRegistry: ChatRegistry,
    clipboardPort: ClipboardPort,
    toastPort: ToastPort,
    logger: Logger,
    options?: ChatProfileCoordinatorOptions,
    groupRegistry?: GroupRegistry,
    userRegistry?: UserRegistry,
    fileRegistry?: FileRegistry
  ) {
    this.scope = scope;
    this.chatRegistry = chatRegistry;
    this.clipboardPort = clipboardPort;
    this.toastPort = toastPort;
    this.logger = logger;
    this.options = options !== undefined ? options : {};
    this.groupRegistry = groupRegistry !== undefined ? groupRegistry : new GroupRegistry(scope);
    this.userRegistry = userRegistry !== undefined ? userRegistry : new UserRegistry(scope);
    this.fileRegistry = fileRegistry !== undefined ? fileRegistry : new FileRegistry(scope);
    this.env = {
      clock: new ManualClock(1000, 500),
      ids: new SequentialIdGenerator('chat-profile-')
    };
  }

  getState(): ChatProfileUiState {
    return this.state;
  }

  setOnStateChanged(listener: (state: ChatProfileUiState) => void): void {
    this.onStateChangedListener = listener;
  }

  start(chatId: number): void {
    this.activeChatId = chatId;
    this.dispatch(new OpenChatProfile(chatId));
  }

  destroy(): void {
    for (let i = 0; i < this.subscriptions.length; i++) {
      this.subscriptions[i].unsubscribe();
    }
    this.subscriptions = [];
    this.onStateChangedListener = null;
  }

  dispatch(intent: ChatProfileIntent): void {
    const res: ReducerResult<ChatProfileUiState, ChatProfileEffect> =
      chatProfileReducer(this.state, intent, this.env);
    this.state = res.state;
    if (this.onStateChangedListener !== null) {
      this.onStateChangedListener(this.state);
    }
    for (let i = 0; i < res.effects.length; i++) {
      this.executeEffect(res.effects[i]);
    }
  }

  private executeEffect(effect: ChatProfileEffect): void {
    switch (effect.type) {
      case 'fetchChatDetailsEffect': {
        const fetchEffect: FetchChatDetailsEffect = effect as FetchChatDetailsEffect;
        this.loadChatDetails(fetchEffect.chatId);
        break;
      }
      case 'navigateToUserProfileEffect': {
        const navEffect: NavigateToUserProfileEffect = effect as NavigateToUserProfileEffect;
        if (this.options.onNavigateToUserProfile) {
          this.options.onNavigateToUserProfile(navEffect.userId);
        }
        break;
      }
      case 'copyInviteLinkEffect': {
        const copyEffect: CopyInviteLinkEffect = effect as CopyInviteLinkEffect;
        this.clipboardPort.setPlainText(copyEffect.link);
        this.toastPort.showToast('Invite link copied');
        break;
      }
      case 'navigateBackEffect': {
        if (this.options.onNavigateBack) {
          this.options.onNavigateBack();
        }
        break;
      }
    }
  }

  private loadChatDetails(chatId: number): void {
    // 1. 获取 Chat 基础对象
    const cachedChat: Chat | undefined = this.chatRegistry.getChat(chatId);
    if (cachedChat !== undefined) {
      this.processChat(cachedChat);
      return;
    }

    const req: GetChat = new GetChat();
    req.chat_id = chatId;
    const res: Result<TdPendingRequest, AppError> = this.scope.request(
      'getChat',
      encodeGetChat(req) as TdWireObject
    );

    if (res.ok) {
      const self: ChatProfileCoordinator = this;
      res.value.promise.then((chatRes: Result<TdWireObject, AppError>): void => {
        if (chatRes.ok) {
          const chat: Chat | null = decodeChat(chatRes.value as TdJsonRaw);
          if (chat !== null) {
            self.chatRegistry.putChat(chat);
            self.processChat(chat);
          }
        }
        if (chatRes.err) {
          self.dispatch(new OnChatProfileError(chatRes.error));
        }
      }).catch((): void => {});
    }
  }

  private processChat(chat: Chat): void {
    this.dispatch(new OnChatLoaded(chat));

    // 处理群头像下载与展示
    if (chat.photo !== null && chat.photo.small !== null) {
      const fileId: number = chat.photo.small.id;
      const cachedPath: string | null = this.fileRegistry.getLocalPath(fileId);
      if (cachedPath !== null) {
        this.dispatch(new OnChatAvatarLoaded(cachedPath));
      } else {
        const self: ChatProfileCoordinator = this;
        const sub: Subscription = this.fileRegistry.subscribeFile(fileId, (f: File): void => {
          if (f.local !== null && f.local.is_downloading_completed && f.local.path.length > 0) {
            self.dispatch(new OnChatAvatarLoaded(f.local.path));
          }
        });
        this.subscriptions.push(sub);
        this.fileRegistry.downloadFile(fileId, 2);
      }
    }

    // 分流 BasicGroup 与 Supergroup
    if (chat.type_ !== null) {
      if (chat.type_.type === 'chatTypeBasicGroup') {
        const bgType: ChatTypeBasicGroup = chat.type_ as ChatTypeBasicGroup;
        this.loadBasicGroupDetails(bgType.basic_group_id);
      } else if (chat.type_.type === 'chatTypeSupergroup') {
        const sgType: ChatTypeSupergroup = chat.type_ as ChatTypeSupergroup;
        this.loadSupergroupDetails(sgType.supergroup_id, sgType.is_channel);
      }
    }
  }

  private loadBasicGroupDetails(basicGroupId: number): void {
    const cachedInfo: BasicGroupFullInfo | null =
      this.groupRegistry.getBasicGroupFullInfo(basicGroupId);
    if (cachedInfo !== null) {
      this.dispatch(new OnBasicGroupFullInfoLoaded(cachedInfo));
    }

    // 订阅详情变更
    const sub: Subscription = this.groupRegistry.subscribeBasicGroupFullInfo(
      basicGroupId,
      (info: BasicGroupFullInfo): void => {
        this.dispatch(new OnBasicGroupFullInfoLoaded(info));
      }
    );
    this.subscriptions.push(sub);

    // 请求最新详情
    this.groupRegistry.requestBasicGroupFullInfo(basicGroupId);
  }

  private loadSupergroupDetails(supergroupId: number, isChannel: boolean): void {
    const cachedInfo: SupergroupFullInfo | null =
      this.groupRegistry.getSupergroupFullInfo(supergroupId);
    if (cachedInfo !== null) {
      this.dispatch(new OnSupergroupFullInfoLoaded(cachedInfo));
    }

    // 订阅详情变更
    const sub: Subscription = this.groupRegistry.subscribeSupergroupFullInfo(
      supergroupId,
      (info: SupergroupFullInfo): void => {
        this.dispatch(new OnSupergroupFullInfoLoaded(info));
      }
    );
    this.subscriptions.push(sub);

    // 请求最新详情
    this.groupRegistry.requestSupergroupFullInfo(supergroupId);

    // 非频道群组请求首屏成员（频道成员不可见）
    if (!isChannel) {
      this.loadSupergroupMembers(supergroupId);
    }
  }

  private loadSupergroupMembers(supergroupId: number): void {
    const cachedMembers: ChatMember[] | null =
      this.groupRegistry.getSupergroupMembers(supergroupId);
    if (cachedMembers !== null && cachedMembers.length > 0) {
      this.processMembers(cachedMembers);
    }

    const self: ChatProfileCoordinator = this;
    const res: Result<TdPendingRequest, AppError> =
      this.groupRegistry.requestSupergroupMembers(supergroupId, 0, 50);
    if (res.ok) {
      res.value.promise.then((memRes: Result<TdWireObject, AppError>): void => {
        if (memRes.ok) {
          const freshMembers: ChatMember[] | null =
            self.groupRegistry.getSupergroupMembers(supergroupId);
          if (freshMembers !== null) {
            self.processMembers(freshMembers);
          }
        }
      }).catch((): void => {});
    }
  }

  private processMembers(members: ChatMember[]): void {
    const items: ChatMemberUiItem[] = [];

    for (let i = 0; i < members.length; i++) {
      const m: ChatMember = members[i];
      if (m.member_id && m.member_id.type === 'messageSenderUser') {
        const senderUser: MessageSenderUser = m.member_id as MessageSenderUser;
        const userId: number = senderUser.user_id;
        const user: User | null = this.userRegistry.getUser(userId);

        let fullName: string = '';
        let username: string = '';
        let letters: string = '';
        let colorIndex: number = getAvatarColorIndex(userId);
        let online: boolean = false;
        let statusText: string = '';
        let avatarPath: string | null = null;

        if (user !== null) {
          fullName = formatFullName(user);
          username = user.usernames ? user.usernames.active_usernames[0] || '' : '';
          letters = getAvatarLetters(user);
          online = isOnline(user);
          statusText = online ? 'online' : 'last seen recently';
          if (user.profile_photo && user.profile_photo.small) {
            avatarPath = this.fileRegistry.getLocalPath(user.profile_photo.small.id);
          }
        } else {
          fullName = `User #${userId}`;
          letters = 'U';
          this.userRegistry.requestUser(userId);
        }

        const role: string = formatMemberRole(m);
        items.push({
          userId: userId,
          fullName: fullName,
          username: username,
          avatarLetters: letters,
          avatarColorIndex: colorIndex,
          avatarPath: avatarPath,
          role: role,
          isOnline: online,
          statusText: statusText
        });
      }
    }

    this.dispatch(new OnChatMembersLoaded(items));
  }
}
