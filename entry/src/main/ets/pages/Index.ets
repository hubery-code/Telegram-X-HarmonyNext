/**
 * entry — Index 页面：真机授权流程 + 会话列表 + 会话消息页 + 设置页 + 搜索页
 * （SPIKE-001 + CHATLIST-003 + CHAT-001/CHAT-002 + INTEG-001 + INTEG-002）。
 *
 * EntryAbility.onCreate → bootstrap() → AuthCoordinator.start()
 * 本页面从 AppStorage 读取 BootstrapResult，订阅 AuthCoordinator 状态变化，
 * 将 intents 分发给 AuthCoordinator（真实 TDLib 请求）。
 * 授权到达 ready 后创建 ChatListCoordinator（core/domain ChatListProjection
 * + feature/chat_list MVI），渲染真实会话列表；点击会话经 onNavigateToChat
 * 回调创建 ChatCoordinator（MessageProjection + feature/chat MVI）并切换渲染
 * ChatPage，返回时销毁并切回会话列表；会话列表 header 齿轮经 onOpenSettings
 * 回调创建 SettingsCoordinator 并切换渲染 SettingsPage（返回时销毁）；授权
 * 离开 ready（登出/会话关闭）时销毁会话与设置协调器并回到登录页。
 *
 * MSG-106：转发目标选择器由本层渲染——entry 同时持有会话列表数据
 * （ChatListCoordinator 的 ChatListItem）与 ChatCoordinator，是唯一能组合
 * 两者的地方（feature/* 之间禁止互相依赖）。ChatCoordinator 经
 * onOpenForwardPicker 回调把待转发消息 id 交上来，本层把会话列表映射为
 * ForwardTarget[] 并覆盖渲染 ForwardPickerPage；选定目标后回灌
 * ForwardSelectedToChat 触发真正的 forwardMessages。
 *
 * INTEG-002：会话列表搜索入口 → SearchPage（SEARCH-101 模块此前不可达）。
 * 导航使用单一类型化事实源 EntryNavigationController（NAV-001 / P1-ARCH-003），
 * 彻底移除相互竞争的布尔标志与 nullable ID。返回栈保活、深链解析与序列化恢复
 * 均由类型化控制器负责。
 */

import { LightTheme } from '@tgx/core-design-system';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { AccountDescriptor, AccountScope } from '@tgx/core-account';
import { AppError, ManualClock, Result, SequentialIdGenerator } from '@tgx/core-common';
import { ReducerEnv } from '@tgx/feature-template';
import { AppRoute, ChatRoute, ChatInfoRoute, UserProfileRoute } from '@tgx/core-navigation';
import { EntryNavigationController } from '../navigation/EntryNavigationController';
import {
  AuthRootPage,
  AuthUiState,
  AuthIntent,
  AuthCoordinator,
  AuthCoordinatorDeps,
  TdlibParametersConfig
} from '@tgx/feature-auth';
import {
  ChatListPage,
  ChatListUiState,
  ChatListIntent,
  ChatListCoordinator,
  ChatListItem,
  DrawerState
} from '@tgx/feature-chat-list';
import {
  ChatPage,
  ChatUiState,
  ForwardTarget,
  ChatIntent,
  ChatCoordinator,
  BackToChatList,
  MessageItem,
  ComposerReplyMode,
  ForwardPickerPage,
  ForwardSelectedToChat
} from '@tgx/feature-chat';
import {
  SettingsPage,
  SettingsUiState,
  SettingsIntent,
  SettingsCoordinator,
  SwitchAccount,
  RequestAddAccount
} from '@tgx/feature-settings';
import {
  SearchPage,
  SearchUiState,
  SearchIntent,
  SearchChatMetadata,
  SearchCoordinator
} from '@tgx/feature-search';
import {
  ProfilePage,
  ProfileUiState,
  ProfileIntent,
  ProfileCoordinator,
  ChatProfilePage,
  ChatProfileUiState,
  ChatProfileIntent,
  ChatProfileCoordinator
} from '@tgx/feature-profile';
import {
  ContactsPage,
  ContactsUiState,
  ContactsIntent,
  ContactsCoordinator
} from '@tgx/feature-contact';
import {
  SelfProfilePage,
  SelfProfileUiState,
  SelfProfileIntent,
  SelfProfileCoordinator
} from '@tgx/feature-self';
import { formatFullName, getAvatarLetters } from '@tgx/core-domain';
import { GetMe, encodeGetMe, decodeUser, TdJsonRaw } from '@tgx/core-td-api-generated';
import type { TdPendingRequest, TdWireObject } from '@tgx/td-gateway';
import { ChatRegistry } from '@tgx/core-domain';
import { BootstrapResult } from '../Bootstrap';
import { ScopeAuthAdapter } from '../ScopeAuthAdapter';
import { TELEGRAM_CREDENTIALS } from '../config/AppCredentials';
import { Logger } from '@tgx/observability';
import { HarmonyClipboardAdapter } from '../platform/HarmonyClipboardAdapter';
import { HarmonyToastAdapter } from '../platform/HarmonyToastAdapter';
import { HarmonyMediaPickerAdapter } from '../platform/HarmonyMediaPickerAdapter';
import { createHarmonyLogger } from '../platform/HarmonyLogSink';

const T = LightTheme;
const DOMAIN: number = 0x0000;
const TAG: string = 'Index';

@Entry
@Component
struct Index {
  @State currentRoute: AppRoute = { name: 'auth' };
  @State uiState: AuthUiState = AuthUiState.initial();
  @State chatListUiState: ChatListUiState = ChatListUiState.initial();
  @State chatUiState: ChatUiState = ChatUiState.initial();
  @State settingsUiState: SettingsUiState = SettingsUiState.initial();
  /** MSG-106：转发目标选择器是否覆盖显示 + 本次候选目标。 */
  @State showForwardPicker: boolean = false;
  @State forwardTargets: ForwardTarget[] = [];
  /** INTEG-002：搜索页可观察状态。 */
  @State searchUiState: SearchUiState = SearchUiState.initial();
  @State bootstrapError: string | null = null;

  private readonly clipboardAdapter: HarmonyClipboardAdapter = new HarmonyClipboardAdapter();
  private readonly toastAdapter: HarmonyToastAdapter = new HarmonyToastAdapter();
  private readonly mediaPickerAdapter: HarmonyMediaPickerAdapter = new HarmonyMediaPickerAdapter();
  private readonly logger: Logger = createHarmonyLogger();
  private readonly navController: EntryNavigationController = new EntryNavigationController({ name: 'auth' });
  private unsubscribeNavFn: (() => void) | null = null;
  private activeChatId: number | null = null;
  /**
   * SEARCH-102：最近一次已请求过的「进会话并定位」目标（`chatId:messageId`）。
   * 路由订阅在每次栈变化都会回调，同一目标只需请求一次跳转，避免重复滚动。
   */
  private lastJumpRequest: string = '';

  private coordinator: AuthCoordinator | null = null;
  private unsubscribeFn: (() => void) | null = null;
  private chatListCoordinator: ChatListCoordinator | null = null;
  private unsubscribeChatListFn: (() => void) | null = null;
  private chatCoordinator: ChatCoordinator | null = null;
  private unsubscribeChatFn: (() => void) | null = null;
  private settingsCoordinator: SettingsCoordinator | null = null;
  private unsubscribeSettingsFn: (() => void) | null = null;
  private searchCoordinator: SearchCoordinator | null = null;
  private unsubscribeSearchFn: (() => void) | null = null;
  // PROFILE-101：用户资料页（群聊点头像进入）。
  @State profileUiState: ProfileUiState = ProfileUiState.initial();
  private profileCoordinator: ProfileCoordinator | null = null;
  private unsubscribeProfileFn: (() => void) | null = null;
  private activeProfileUserId: number = 0;
  // PROFILE-102：群组/频道资料页（点击群聊标题进入）。
  @State chatProfileUiState: ChatProfileUiState = ChatProfileUiState.initial();
  private chatProfileCoordinator: ChatProfileCoordinator | null = null;
  private activeChatProfileId: number = 0;
  // TGX 对齐集成：联系人 / 我的资料 / 抽屉账号头（DSH 主会话）。
  @State contactsUiState: ContactsUiState = ContactsUiState.initial();
  private contactsCoordinator: ContactsCoordinator | null = null;
  private unsubscribeContactsFn: (() => void) | null = null;
  @State selfProfileUiState: SelfProfileUiState = SelfProfileUiState.initial();
  private selfProfileCoordinator: SelfProfileCoordinator | null = null;
  private unsubscribeSelfFn: (() => void) | null = null;
  @State drawerAccountName: string = '';
  @State drawerAccountPhone: string = '';
  @State drawerAccountLetters: string = '';
  private drawerAccountLoaded: boolean = false;
  private accountScope: AccountScope | null = null;
  private bootstrapResult: BootstrapResult | null = null;
  private currentAccountKey: string = 'default';

  aboutToAppear(): void {
    const result: BootstrapResult | undefined = AppStorage.get<BootstrapResult>('bootstrapResult');
    if (result === undefined || result === null) {
      this.bootstrapError = 'Bootstrap failed — see logs';
      hilog.error(DOMAIN, TAG, 'bootstrapResult not found in AppStorage');
      return;
    }

    this.bootstrapResult = result;
    this.coordinator = result.coordinator;
    this.accountScope = result.scope;
    this.currentAccountKey = result.scope.accountKey;
    if (result.cacheDir !== undefined && result.cacheDir.length > 0) {
      this.mediaPickerAdapter.setCacheDir(result.cacheDir);
    }

    this.unsubscribeNavFn = this.navController.subscribe((route: AppRoute, prev: AppRoute | null) => {
      this.currentRoute = route;
      this.onRouteChanged(route, prev);
    });

    this.initAuthCoordinatorSubscription(result.scope);
    this.updateAvailableAccounts();
    this.fetchDrawerAccount();
  }

  aboutToDisappear(): void {
    if (this.unsubscribeNavFn !== null) {
      this.unsubscribeNavFn();
      this.unsubscribeNavFn = null;
    }
    this.closeChat();
    this.closeSettings();
    this.closeSearch();
    if (this.unsubscribeChatListFn !== null) {
      this.unsubscribeChatListFn();
      this.unsubscribeChatListFn = null;
    }
    if (this.chatListCoordinator !== null) {
      this.chatListCoordinator.destroy();
      this.chatListCoordinator = null;
    }
    if (this.unsubscribeFn !== null) {
      this.unsubscribeFn();
      this.unsubscribeFn = null;
    }
  }

  onBackPress(): boolean {
    if (this.currentRoute.name === 'chat') {
      // MSG-106：选择器打开时返回只关选择器，不退出会话页也不退出多选态。
      if (this.showForwardPicker) {
        this.closeForwardPicker();
        return true;
      }
      if (this.chatCoordinator !== null) {
        this.chatDispatch(new BackToChatList());
        return true;
      }
      return this.navController.pop();
    }
    return this.navController.pop();
  }

  private onRouteChanged(route: AppRoute, _prev: AppRoute | null): void {
    // 1. 关闭栈中已不存在的页面的协调器
    if (!this.navController.hasRoute('chat') && this.chatCoordinator !== null) {
      this.closeChat();
    }
    if (!this.navController.hasRoute('settings') && !this.navController.hasRoute('settingsSection') && this.settingsCoordinator !== null) {
      this.closeSettings();
    }
    if (!this.navController.hasRoute('search') && this.searchCoordinator !== null) {
      this.closeSearch();
    }
    if (!this.navController.hasRoute('userProfile') && this.profileCoordinator !== null) {
      this.closeProfile();
    }
    if (!this.navController.hasRoute('chatInfo') && this.chatProfileCoordinator !== null) {
      this.closeChatProfile();
    }
    if (!this.navController.hasRoute('contacts') && this.contactsCoordinator !== null) {
      this.closeContacts();
    }
    if (!this.navController.hasRoute('selfProfile') && this.selfProfileCoordinator !== null) {
      this.closeSelfProfile();
    }

    // 2. 根据当前栈顶路由，按需拉起对应协调器
    if (route.name === 'chat') {
      const chatRoute: ChatRoute = route as ChatRoute;
      // SEARCH-102：路由可携带目标消息 id（全局搜索结果 → 会话内定位）。
      const jumpTo: number = chatRoute.messageId !== undefined ? chatRoute.messageId : 0;
      if (this.chatCoordinator === null || this.activeChatId !== chatRoute.chatId) {
        this.openChat(chatRoute.chatId, this.resolveChatTitle(chatRoute.chatId), jumpTo);
      } else {
        this.requestChatJump(chatRoute.chatId, jumpTo);
      }
    } else if (route.name === 'userProfile') {
      const profileRoute: UserProfileRoute = route as UserProfileRoute;
      if (this.profileCoordinator === null || this.activeProfileUserId !== profileRoute.userId) {
        this.openProfile(profileRoute.userId);
      }
    } else if (route.name === 'chatInfo') {
      const chatInfoRoute: ChatInfoRoute = route as ChatInfoRoute;
      if (this.chatProfileCoordinator === null || this.activeChatProfileId !== chatInfoRoute.chatId) {
        this.openChatProfile(chatInfoRoute.chatId);
      }
    } else if (route.name === 'contacts') {
      if (this.contactsCoordinator === null) {
        this.openContacts();
      }
    } else if (route.name === 'selfProfile') {
      if (this.selfProfileCoordinator === null) {
        this.openSelfProfile();
      }
    } else if (route.name === 'settings' || route.name === 'settingsSection') {
      if (this.settingsCoordinator === null) {
        this.openSettings();
      }
    } else if (route.name === 'search') {
      if (this.searchCoordinator === null) {
        this.openSearch();
      }
    }
  }

  private dispatch(intent: AuthIntent): void {
    if (this.coordinator !== null) {
      this.coordinator.dispatch(intent);
    }
  }

  private chatListDispatch(intent: ChatListIntent): void {
    if (this.chatListCoordinator !== null) {
      this.chatListCoordinator.dispatch(intent);
    }
  }

  private chatDispatch(intent: ChatIntent): void {
    if (this.chatCoordinator !== null) {
      this.chatCoordinator.dispatch(intent);
    }
  }

  private settingsDispatch(intent: SettingsIntent): void {
    if (this.settingsCoordinator !== null) {
      this.settingsCoordinator.dispatch(intent);
    } else {
      if (intent.kind === 'switchAccount') {
        const switchIntent: SwitchAccount = intent as SwitchAccount;
        this.handleSwitchAccount(switchIntent.accountKey);
      } else if (intent.kind === 'requestAddAccount') {
        this.handleAddAccount();
      }
    }
  }

  /**
   * 授权离开 ready（登出/会话关闭）时的整体退场：
   * 销毁会话、设置与搜索协调器并回到登录页；再次 ready 时会话列表协调器重建。
   */
  private handleSessionEnded(): void {
    this.closeChat();
    this.closeSettings();
    this.closeSearch();
    if (this.unsubscribeChatListFn !== null) {
      this.unsubscribeChatListFn();
      this.unsubscribeChatListFn = null;
    }
    if (this.chatListCoordinator !== null) {
      this.chatListCoordinator.destroy();
      this.chatListCoordinator = null;
    }
    this.navController.replaceRoot({ name: 'auth' });
    hilog.info(DOMAIN, TAG, 'session ended, back to auth page');
  }

  /**
   * INTEG-002：打开搜索页。
   * SearchCoordinator 用 scope 构造 → 内部走 TdlibSearchQueryProvider（真实
   * TDLib SearchChats / SearchMessages）；search 无 start 生命周期，构造即用。
   * 协调器活到搜索页关闭为止——从结果进会话时**不销毁**，这样返回能落回结果。
   */
  private openSearch(): void {
    if (this.accountScope === null || this.searchCoordinator !== null) {
      return;
    }
    const coordinator: SearchCoordinator = new SearchCoordinator({
      scope: this.accountScope,
      onNavigateToChat: (chatId: number, messageId?: number) => {
        this.navigateToChatFromSearch(chatId, messageId);
      },
      // FIX-001：搜索结果只拿得到 chat_ids，标题/用户名要从会话列表的本地缓存取。
      // feature/search 不能依赖 feature/chat_list，所以由本层（装配层）注入查询。
      resolveChatMetadata: (chatId: number) => {
        return this.resolveSearchChatMetadata(chatId);
      },
      logger: this.logger
    });
    this.searchCoordinator = coordinator;
    this.unsubscribeSearchFn = coordinator.subscribe((uiState: SearchUiState) => {
      this.searchUiState = uiState;
    });
    hilog.info(DOMAIN, TAG, 'search coordinator started');
  }

  private closeSearch(): void {
    if (this.unsubscribeSearchFn !== null) {
      this.unsubscribeSearchFn();
      this.unsubscribeSearchFn = null;
    }
    if (this.searchCoordinator !== null) {
      this.searchCoordinator.destroy();
      this.searchCoordinator = null;
    }
  }

  /** PROFILE-101：打开用户资料页协调器（群聊头像点按进入）。 */
  private openProfile(userId: number): void {
    if (this.accountScope === null) {
      return;
    }
    this.closeProfile();
    const coordinator: ProfileCoordinator = new ProfileCoordinator(
      this.accountScope,
      userId,
      {
        logger: this.logger,
        onOpenChat: (chatId: number): void => {
          // 「发消息」：私聊压栈到资料页之上，返回仍落回资料页。
          this.navController.navigateTo({ name: 'chat', chatId: chatId });
        }
      }
    );
    this.profileCoordinator = coordinator;
    this.activeProfileUserId = userId;
    this.unsubscribeProfileFn = coordinator.subscribe((uiState: ProfileUiState): void => {
      this.profileUiState = uiState;
    });
    coordinator.start();
    hilog.info(DOMAIN, TAG, 'profile coordinator started for userId=%{public}s', `${userId}`);
  }

  private closeProfile(): void {
    if (this.unsubscribeProfileFn !== null) {
      this.unsubscribeProfileFn();
      this.unsubscribeProfileFn = null;
    }
    if (this.profileCoordinator !== null) {
      this.profileCoordinator.destroy();
      this.profileCoordinator = null;
    }
    this.activeProfileUserId = 0;
  }

  // PROFILE-102：群聊/频道资料页打开与关闭
  private openChatProfile(chatId: number): void {
    if (this.accountScope === null) {
      return;
    }
    this.closeChatProfile();
    const coordinator: ChatProfileCoordinator = new ChatProfileCoordinator(
      this.accountScope,
      new ChatRegistry(),
      this.clipboardAdapter,
      this.toastAdapter,
      this.logger,
      {
        onNavigateToUserProfile: (userId: number): void => {
          this.navController.navigateTo({ name: 'userProfile', userId: userId });
        },
        onNavigateBack: (): void => {
          this.navController.pop();
        }
      }
    );
    this.chatProfileCoordinator = coordinator;
    this.activeChatProfileId = chatId;
    coordinator.setOnStateChanged((uiState: ChatProfileUiState): void => {
      this.chatProfileUiState = uiState;
    });
    coordinator.start(chatId);
    hilog.info(DOMAIN, TAG, 'chat profile coordinator started for chatId=%{public}s', `${chatId}`);
  }

  private closeChatProfile(): void {
    if (this.chatProfileCoordinator !== null) {
      this.chatProfileCoordinator.destroy();
      this.chatProfileCoordinator = null;
    }
    this.activeChatProfileId = 0;
  }

  /** CONTACT-101：联系人页。 */
  private openContacts(): void {
    if (this.accountScope === null) {
      return;
    }
    this.closeContacts();
    const coordinator: ContactsCoordinator = new ContactsCoordinator(this.accountScope, {
      logger: this.logger,
      onOpenUserProfile: (userId: number): void => {
        this.navController.navigateTo({ name: 'userProfile', userId: userId });
      }
    });
    this.contactsCoordinator = coordinator;
    this.unsubscribeContactsFn = coordinator.subscribe((uiState: ContactsUiState): void => {
      this.contactsUiState = uiState;
    });
    coordinator.start();
    hilog.info(DOMAIN, TAG, 'contacts coordinator started');
  }

  private closeContacts(): void {
    if (this.unsubscribeContactsFn !== null) {
      this.unsubscribeContactsFn();
      this.unsubscribeContactsFn = null;
    }
    if (this.contactsCoordinator !== null) {
      this.contactsCoordinator.destroy();
      this.contactsCoordinator = null;
    }
  }

  /** SELF-101：我的资料页。 */
  private openSelfProfile(): void {
    if (this.accountScope === null) {
      return;
    }
    this.closeSelfProfile();
    const coordinator: SelfProfileCoordinator = new SelfProfileCoordinator(this.accountScope, {
      logger: this.logger
    });
    this.selfProfileCoordinator = coordinator;
    this.unsubscribeSelfFn = coordinator.subscribe((uiState: SelfProfileUiState): void => {
      this.selfProfileUiState = uiState;
    });
    coordinator.start();
    hilog.info(DOMAIN, TAG, 'self profile coordinator started');
  }

  private closeSelfProfile(): void {
    if (this.unsubscribeSelfFn !== null) {
      this.unsubscribeSelfFn();
      this.unsubscribeSelfFn = null;
    }
    if (this.selfProfileCoordinator !== null) {
      this.selfProfileCoordinator.destroy();
      this.selfProfileCoordinator = null;
    }
  }

  /** DRAWER-101：拉一次当前账号信息（getMe）注入抽屉头部；MVP 不含头像下载。 */
  private fetchDrawerAccount(): void {
    if (this.accountScope === null || this.drawerAccountLoaded) {
      return;
    }
    const req: GetMe = new GetMe();
    const res: Result<TdPendingRequest, AppError> =
      this.accountScope.request('getMe', encodeGetMe(req) as TdWireObject);
    if (res.ok) {
      res.value.promise.then((out: Result<TdWireObject, AppError>): void => {
        if (out.ok) {
          const me = decodeUser(out.value as TdJsonRaw);
          if (me !== null) {
            this.drawerAccountLoaded = true;
            this.drawerAccountName = formatFullName(me);
            this.drawerAccountPhone = me.phone_number !== null && me.phone_number !== undefined
              ? me.phone_number
              : '';
            this.drawerAccountLetters = getAvatarLetters(me);
          }
        }
      }).catch((): void => {
      });
    }
  }

  /**
   * 搜索结果 → 会话。通过 navController 压栈，保持 search 还在返回栈中。
   * SEARCH-102：消息类结果附带 messageId，经路由带给会话页做滚动定位
   * （会话列表/深链入口不带该字段，行为不变）。
   */
  private navigateToChatFromSearch(chatId: number, messageId?: number): void {
    hilog.info(DOMAIN, TAG, 'navigate from search chatId=%{public}s messageId=%{public}s',
      `${chatId}`, `${messageId !== undefined ? messageId : 0}`);
    if (messageId !== undefined && messageId > 0) {
      this.navController.navigateTo({ name: 'chat', chatId: chatId, messageId: messageId });
      return;
    }
    this.navController.navigateTo({ name: 'chat', chatId: chatId });
  }

  /**
   * SEARCH-102：请求把已打开的会话定位到目标消息。同一目标只请求一次
   * （路由订阅会在每次栈变化回调，重复请求会导致重复滚动）。
   */
  private requestChatJump(chatId: number, messageId: number): void {
    if (messageId <= 0 || this.chatCoordinator === null) {
      return;
    }
    const jumpKey: string = `${chatId}:${messageId}`;
    if (this.lastJumpRequest === jumpKey) {
      return;
    }
    this.lastJumpRequest = jumpKey;
    hilog.info(DOMAIN, TAG, 'chat jump requested chatId=%{public}s messageId=%{public}s',
      `${chatId}`, `${messageId}`);
    this.chatCoordinator.requestJumpToMessage(messageId);
  }

  /** 从会话列表数据里取标题（搜索结果只给 chatId）；未命中回退空串，ChatPage 会显示空标题。 */
  private chatTitleOf(chatId: number): string {
    const items: readonly ChatListItem[] = this.chatListUiState.items;
    for (let i = 0; i < items.length; i++) {
      if (items[i].chatId === chatId) {
        return items[i].title;
      }
    }
    return '';
  }

  /** 综合缓存与列表解析会话标题 */
  private resolveChatTitle(chatId: number): string {
    if (this.chatListCoordinator !== null) {
      const title: string | null = this.chatListCoordinator.getChatTitle(chatId);
      if (title !== null && title.length > 0) {
        return title;
      }
    }
    return this.chatTitleOf(chatId);
  }

  /**
   * FIX-001：搜索结果标题/用户名解析。
   * 优先用 ChatListCoordinator 的 ChatRegistry（TDLib 经 updateNewChat 推来的
   * 全量本地缓存，无网络往返）；会话列表协调器尚未建立时回退到已渲染的列表行
   * （至少覆盖当前一页）；都没有则返回 null，由 provider 退回 `Chat <id>` 占位。
   */
  private resolveSearchChatMetadata(chatId: number): SearchChatMetadata | null {
    if (this.chatListCoordinator !== null) {
      const title: string | null = this.chatListCoordinator.getChatTitle(chatId);
      if (title !== null) {
        // username 留空：本版 TDLib 的 Chat 无该字段，SearchPage 对空串不渲染 @行。
        return { title: title, username: '' };
      }
    }
    const fallbackTitle: string = this.chatTitleOf(chatId);
    if (fallbackTitle.length > 0) {
      return { title: fallbackTitle, username: '' };
    }
    return null;
  }

  private getAvailableAccounts(): string[] {
    if (this.bootstrapResult === null) {
      return [this.currentAccountKey];
    }
    const descriptors: AccountDescriptor[] = this.bootstrapResult.registry.list();
    const keys: string[] = [];
    for (let i = 0; i < descriptors.length; i++) {
      keys.push(descriptors[i].accountKey);
    }
    if (keys.indexOf(this.currentAccountKey) < 0) {
      keys.push(this.currentAccountKey);
    }
    return keys;
  }

  private updateAvailableAccounts(): void {
    const accounts: string[] = this.getAvailableAccounts();
    this.settingsUiState = this.settingsUiState.copyWith({
      availableAccounts: accounts,
      currentAccountKey: this.currentAccountKey
    });
    if (this.settingsCoordinator !== null) {
      this.settingsCoordinator.setAccounts(accounts, this.currentAccountKey);
    }
  }

  private initChatList(scope: AccountScope): void {
    if (this.chatListCoordinator !== null) {
      this.chatListCoordinator.destroy();
      this.chatListCoordinator = null;
    }
    if (this.unsubscribeChatListFn !== null) {
      this.unsubscribeChatListFn();
      this.unsubscribeChatListFn = null;
    }
    this.chatListCoordinator = new ChatListCoordinator(
      scope,
      undefined,
      (chatId: number, _chatTitle: string) => {
        this.navController.navigateTo({ name: 'chat', chatId: chatId });
      },
      this.logger
    );
    this.chatListCoordinator.start();
    this.unsubscribeChatListFn = this.chatListCoordinator.subscribe((uiState: ChatListUiState) => {
      this.chatListUiState = uiState;
    });
    hilog.info(DOMAIN, TAG, 'chat list coordinator started for scope %{public}s', scope.accountKey);
  }

  private initAuthCoordinatorSubscription(scope: AccountScope): void {
    if (this.coordinator === null) {
      return;
    }
    this.unsubscribeFn = this.coordinator.subscribe((state: AuthUiState) => {
      this.uiState = state;
      if (state.step === 'ready') {
        if (this.currentRoute.name === 'auth') {
          this.navController.replaceRoot({ name: 'home' });
        }
        if (this.chatListCoordinator === null) {
          this.initChatList(scope);
        }
      } else if (this.currentRoute.name !== 'auth') {
        // 授权离开 ready（登出/会话关闭）：销毁会话与设置协调器，回到登录页。
        this.handleSessionEnded();
      }
    });
  }

  private createAuthCoordinator(scope: AccountScope): AuthCoordinator {
    const authScope: ScopeAuthAdapter = new ScopeAuthAdapter(scope);
    const env: ReducerEnv = {
      clock: new ManualClock(1000, 500),
      ids: new SequentialIdGenerator('entry-')
    };
    const tdlibParams: TdlibParametersConfig = this.bootstrapResult?.tdlibParams !== undefined
      ? this.bootstrapResult.tdlibParams
      : {
          apiId: TELEGRAM_CREDENTIALS.apiId,
          apiHash: TELEGRAM_CREDENTIALS.apiHash,
          databaseDirectory: '',
          filesDirectory: '',
          systemLanguageCode: 'en',
          deviceModel: 'HarmonyOS NEXT',
          applicationVersion: '0.1.0',
          useTestDc: false
        };
    const deps: AuthCoordinatorDeps = {
      scope: authScope,
      env: env,
      tdlibParameters: tdlibParams,
      onNavigate: (_route: string) => {},
      logger: this.logger
    };
    return new AuthCoordinator(deps);
  }

  /**
   * ACC-101：多账号切换
   * 当用户在 Settings 中触发 SwitchAccount(key) 时：
   * 调用 this.bootstrapResult.registry.activate(key) 切换当前 AccountScope，
   * 重新初始化或切换当前会话列表和设置页，并更新路由。
   */
  private handleSwitchAccount(accountKey: string): void {
    if (this.bootstrapResult === null) {
      hilog.error(DOMAIN, TAG, 'cannot switch account: bootstrapResult is null');
      return;
    }
    if (accountKey === this.currentAccountKey) {
      hilog.info(DOMAIN, TAG, 'already on account: %{public}s', accountKey);
      return;
    }
    hilog.info(DOMAIN, TAG, 'switching account to: %{public}s', accountKey);

    const activateRes: Result<AccountScope, AppError> = this.bootstrapResult.registry.activate(accountKey);
    if (activateRes.ok === false) {
      hilog.error(DOMAIN, TAG, 'failed to activate account %{public}s: %{public}s',
        accountKey, activateRes.error.message);
      return;
    }

    const newScope: AccountScope = activateRes.value;

    // 1. 关闭/销毁当前活跃的各协调器
    this.closeChat();
    this.closeSettings();
    this.closeSearch();
    if (this.unsubscribeChatListFn !== null) {
      this.unsubscribeChatListFn();
      this.unsubscribeChatListFn = null;
    }
    if (this.chatListCoordinator !== null) {
      this.chatListCoordinator.destroy();
      this.chatListCoordinator = null;
    }
    if (this.unsubscribeFn !== null) {
      this.unsubscribeFn();
      this.unsubscribeFn = null;
    }
    if (this.coordinator !== null) {
      this.coordinator.destroy();
      this.coordinator = null;
    }

    // 2. 切换当前 AccountScope 与账号键
    this.accountScope = newScope;
    this.currentAccountKey = accountKey;
    this.updateAvailableAccounts();

    // 3. 为新 scope 重新初始化 AuthCoordinator 并启动
    this.coordinator = this.createAuthCoordinator(newScope);
    this.initAuthCoordinatorSubscription(newScope);
    this.coordinator.start();

    // 4. 根据新账号的授权状态更新路由与会话列表
    if (newScope.authorization.kind === 'ready') {
      this.navController.replaceRoot({ name: 'home' });
      this.initChatList(newScope);
    } else {
      this.navController.replaceRoot({ name: 'auth' });
    }
  }

  /**
   * ACC-101：添加账号入口
   * 当用户点击「添加账号 (Add Account)」时：
   * 调用 this.bootstrapResult.registry.create('account_' + Date.now()) 创建新 scope，
   * 切换至该新 scope，并将路由切到 auth 登录页引导用户输入手机号登录。
   */
  private handleAddAccount(): void {
    if (this.bootstrapResult === null) {
      hilog.error(DOMAIN, TAG, 'cannot add account: bootstrapResult is null');
      return;
    }
    const newKey: string = 'account_' + Date.now();
    hilog.info(DOMAIN, TAG, 'creating new account: %{public}s', newKey);

    const createRes: Result<AccountScope, AppError> = this.bootstrapResult.registry.create(newKey);
    if (createRes.ok === false) {
      hilog.error(DOMAIN, TAG, 'failed to create account %{public}s: %{public}s',
        newKey, createRes.error.message);
      return;
    }

    const newScope: AccountScope = createRes.value;

    // 1. 关闭/销毁当前活跃的各协调器
    this.closeChat();
    this.closeSettings();
    this.closeSearch();
    if (this.unsubscribeChatListFn !== null) {
      this.unsubscribeChatListFn();
      this.unsubscribeChatListFn = null;
    }
    if (this.chatListCoordinator !== null) {
      this.chatListCoordinator.destroy();
      this.chatListCoordinator = null;
    }
    if (this.unsubscribeFn !== null) {
      this.unsubscribeFn();
      this.unsubscribeFn = null;
    }
    if (this.coordinator !== null) {
      this.coordinator.destroy();
      this.coordinator = null;
    }

    // 2. 切换当前 AccountScope 与账号键
    this.accountScope = newScope;
    this.currentAccountKey = newKey;
    this.updateAvailableAccounts();

    // 3. 为新 scope 重新初始化 AuthCoordinator 并启动
    this.coordinator = this.createAuthCoordinator(newScope);
    this.initAuthCoordinatorSubscription(newScope);
    this.coordinator.start();

    // 4. 将路由切到 auth 登录页引导用户输入手机号登录
    this.navController.replaceRoot({ name: 'auth' });
  }

  private openSettings(): void {
    if (this.accountScope === null || this.settingsCoordinator !== null) {
      return;
    }
    const coordinator: SettingsCoordinator = new SettingsCoordinator(
      this.accountScope,
      undefined,
      undefined,
      () => {
        // logOut 请求已成功；关闭设置页回到导航栈
        this.navController.pop();
      },
      this.logger,
      (accountKey: string) => {
        this.handleSwitchAccount(accountKey);
      },
      () => {
        this.handleAddAccount();
      },
      this.currentAccountKey,
      this.getAvailableAccounts()
    );
    this.settingsCoordinator = coordinator;
    this.unsubscribeSettingsFn = coordinator.subscribe((uiState: SettingsUiState) => {
      this.settingsUiState = uiState;
    });
    coordinator.start();
    hilog.info(DOMAIN, TAG, 'settings coordinator started');
  }

  private closeSettings(): void {
    if (this.unsubscribeSettingsFn !== null) {
      this.unsubscribeSettingsFn();
      this.unsubscribeSettingsFn = null;
    }
    if (this.settingsCoordinator !== null) {
      this.settingsCoordinator.destroy();
      this.settingsCoordinator = null;
    }
  }

  private openChat(chatId: number, chatTitle: string, jumpToMessageId: number = 0): void {
    if (this.accountScope === null) {
      return;
    }
    this.closeChat();
    const coordinator: ChatCoordinator = new ChatCoordinator(
      this.accountScope,
      chatId,
      chatTitle,
      () => {
        this.navController.pop();
      },
      (messageIds: number[]) => {
        this.openForwardPicker(chatId, messageIds);
      },
      undefined,
      {
        clipboardPort: this.clipboardAdapter,
        toastPort: this.toastAdapter,
        mediaPickerPort: this.mediaPickerAdapter,
        logger: this.logger,
        // PROFILE-101：群聊点头像 → 压栈用户资料页。
        onOpenUserProfile: (userId: number): void => {
          this.navController.navigateTo({ name: 'userProfile', userId: userId });
        },
        // PROFILE-102：群聊/频道点击标题 → 压栈群组/频道资料页。
        onOpenChatProfile: (targetChatId: number): void => {
          this.navController.navigateTo({ name: 'chatInfo', chatId: targetChatId });
        }
      }
    );
    this.chatCoordinator = coordinator;
    this.activeChatId = chatId;
    this.unsubscribeChatFn = coordinator.subscribe((uiState: ChatUiState) => {
      this.chatUiState = uiState;
    });
    coordinator.start();
    hilog.info(DOMAIN, TAG, 'chat coordinator started for chatId=%{public}s', `${chatId}`);
    // SEARCH-102：从搜索结果进入且带目标消息时，等协调器就绪后请求定位
    // （目标未在首屏缓存时，协调器会排队到首屏加载完成再拉围绕历史）。
    this.requestChatJump(chatId, jumpToMessageId);
  }

  private closeChat(): void {
    this.closeForwardPicker();
    // SEARCH-102：会话关闭后清掉跳转去重键，重新进入同一会话仍可再次定位。
    this.lastJumpRequest = '';
    if (this.unsubscribeChatFn !== null) {
      this.unsubscribeChatFn();
      this.unsubscribeChatFn = null;
    }
    if (this.chatCoordinator !== null) {
      this.chatCoordinator.destroy();
      this.chatCoordinator = null;
    }
    this.activeChatId = null;
  }

  /**
   * MSG-106：把会话列表映射为转发候选目标并弹出选择器。
   * 映射在装配层完成——feature/chat 不认识 feature-chat-list 的 ChatListItem，
   * 只认自己的 ForwardTarget（ARCHITECTURE §2 规则 1）。
   */
  private openForwardPicker(fromChatId: number, messageIds: number[]): void {
    const items: readonly ChatListItem[] = this.chatListUiState.items;
    const targets: ForwardTarget[] = [];
    for (let i = 0; i < items.length; i++) {
      const item: ChatListItem = items[i];
      targets.push(new ForwardTarget(
        item.chatId,
        item.title,
        item.avatarColor,
        item.avatarLetter,
        item.chatId === fromChatId,
        item.avatarPath
      ));
    }
    this.forwardTargets = targets;
    this.showForwardPicker = true;
    hilog.info(DOMAIN, TAG, 'forward picker opened: %{public}d messages, %{public}d targets',
      messageIds.length, targets.length);
  }

  private closeForwardPicker(): void {
    this.showForwardPicker = false;
    this.forwardTargets = [];
  }

  /** 选定目标会话 → 回灌 ChatIntent 触发 forwardMessages。 */
  private pickForwardTarget(chatId: number, sendCopy: boolean): void {
    hilog.info(DOMAIN, TAG, 'forward target picked chatId=%{public}s copy=%{public}s',
      `${chatId}`, `${sendCopy}`);
    this.chatDispatch(new ForwardSelectedToChat(chatId, sendCopy));
    this.closeForwardPicker();
  }

  build() {
    Column() {
      if (this.bootstrapError !== null) {
        Column() {
          Text('Bootstrap Error')
            .fontSize(T.typography.title.fontSize)
            .fontWeight(T.typography.title.fontWeight)
            .fontColor(T.colors.destructive)
            .margin({ bottom: T.spacing.sm })

          Text(this.bootstrapError)
            .fontSize(T.typography.body.fontSize)
            .fontColor(T.colors.textSecondary)
        }
        .width('100%')
        .height('100%')
        .justifyContent(FlexAlign.Center)
        .alignItems(HorizontalAlign.Center)
        .backgroundColor(T.colors.background)
      } else if (this.currentRoute.name === 'chat') {
        Stack() {
          ChatPage({
            uiState: this.chatUiState,
            onDispatch: (intent: Object) => {
              this.chatDispatch(intent as ChatIntent);
            }
          })

          // MSG-106：转发目标选择器覆盖在会话页之上（顶栏 Cancel + Send as
          // copy 开关 + 目标会话列表）。
          if (this.showForwardPicker) {
            ForwardPickerPage({
              targets: this.forwardTargets,
              onPick: (chatId: number, sendCopy: boolean) => {
                this.pickForwardTarget(chatId, sendCopy);
              },
              onCancel: () => {
                this.closeForwardPicker();
              }
            })
          }
        }
        .width('100%')
        .height('100%')
      } else if (this.currentRoute.name === 'settings' || this.currentRoute.name === 'settingsSection') {
        SettingsPage({
          uiState: this.settingsUiState,
          onDispatch: (intent: SettingsIntent) => {
            this.settingsDispatch(intent);
          },
          onBack: () => {
            this.navController.pop();
          }
        })
      } else if (this.currentRoute.name === 'search') {
        // INTEG-002：搜索结果页。onDispatch 作为协调器缺席时的降级路径保留；
        // coordinator 非空时页面内部直调协调器（不会双发，见 SearchPage 注释）。
        SearchPage({
          uiState: this.searchUiState,
          coordinator: this.searchCoordinator,
          onDispatch: (intent: Object) => {
            if (this.searchCoordinator !== null) {
              this.searchCoordinator.dispatch(intent as SearchIntent);
            }
          },
          onNavigateToChat: (chatId: number, messageId?: number) => {
            this.navigateToChatFromSearch(chatId, messageId);
          }
        })
      } else if (this.currentRoute.name === 'userProfile') {
        ProfilePage({
          uiState: this.profileUiState,
          onDispatch: (intent: ProfileIntent) => {
            if (this.profileCoordinator !== null) {
              this.profileCoordinator.dispatch(intent);
            }
          },
          onBack: () => {
            this.navController.pop();
          }
        })
      } else if (this.currentRoute.name === 'contacts') {
        ContactsPage({
          uiState: this.contactsUiState,
          onDispatch: (intent: ContactsIntent) => {
            if (this.contactsCoordinator !== null) {
              this.contactsCoordinator.dispatch(intent);
            }
          },
          onBack: () => {
            this.navController.pop();
          },
          // 双路径防双开：只走 coordinator 的 onOpenUserProfile 回调，此 prop 恒 no-op。
          onOpenUserProfile: (): void => {
          }
        })
      } else if (this.currentRoute.name === 'selfProfile') {
        SelfProfilePage({
          uiState: this.selfProfileUiState,
          onDispatch: (intent: SelfProfileIntent) => {
            if (this.selfProfileCoordinator !== null) {
              this.selfProfileCoordinator.dispatch(intent);
            }
          },
          onBack: () => {
            this.navController.pop();
          }
        })
      } else if (this.currentRoute.name === 'chatInfo') {
        ChatProfilePage({
          uiState: this.chatProfileUiState,
          onDispatch: (intent: ChatProfileIntent) => {
            if (this.chatProfileCoordinator !== null) {
              this.chatProfileCoordinator.dispatch(intent);
            }
          },
          onBack: () => {
            this.navController.pop();
          }
        })
      } else if (this.currentRoute.name === 'home') {
        ChatListPage({
          uiState: this.chatListUiState,
          onDispatch: (intent: Object) => {
            this.chatListDispatch(intent as ChatListIntent);
          },
          onOpenSettings: () => {
            this.navController.navigateTo({ name: 'settings' });
          },
          onOpenSearch: () => {
            this.navController.navigateTo({ name: 'search' });
          },
          // DRAWER-101：抽屉（账号头 getMe 注入；菜单项路由；夜间模式/账号切换占位）。
          drawerState: new DrawerState(
            this.drawerAccountName,
            this.drawerAccountPhone,
            null,
            this.drawerAccountLetters,
            false
          ),
          onDrawerItem: (item: string): void => {
            if (item === 'settings') {
              this.navController.navigateTo({ name: 'settings' });
            } else if (item === 'contacts') {
              this.navController.navigateTo({ name: 'contacts' });
            } else {
              hilog.info(DOMAIN, TAG, 'drawer item placeholder: %{public}s', item);
            }
          },
          onDrawerNightModeChanged: (on: boolean): void => {
            hilog.info(DOMAIN, TAG, 'drawer night mode placeholder=%{public}s', `${on}`);
          },
          onDrawerSwitchAccount: (): void => {
            hilog.info(DOMAIN, TAG, 'drawer switch account placeholder');
          }
        })
      } else {
        AuthRootPage({
          uiState: this.uiState,
          onDispatch: (intent: Object) => {
            this.dispatch(intent as AuthIntent);
          }
        })
      }
    }
    .width('100%')
    .height('100%')
    .backgroundColor(T.colors.background)
  }
}
