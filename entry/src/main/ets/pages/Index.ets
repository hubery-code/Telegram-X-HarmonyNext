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

import { LightTheme, Theme, ThemeManager, parseChatFontSize, CHAT_FONT_SIZE_DEFAULT } from '@tgx/core-design-system';
import { saveChatFontSize } from '../store/SettingsStore';
import { PreferencesAutoDownloadPolicyStore } from '../store/AutoDownloadStore';
import { AppLockGate } from '../applock/AppLockGate';
import { appLockGate, appLockStore } from '../applock/AppLockWiring';
import { AppLockOverlay } from '../applock/AppLockOverlay';
import { PreferencesDataSaverStore } from '../store/DataSaverStore';
import { PreferencesDownloadLimitsStore } from '../store/DownloadLimitsStore';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { common } from '@kit.AbilityKit';
import { AccountDescriptor, AccountScope } from '@tgx/core-account';
import { AppError, Lang, ManualClock, Result, SequentialIdGenerator } from '@tgx/core-common';
import { ReducerEnv } from '@tgx/feature-template';
import { AppRoute, ChatRoute, ChatInfoRoute, UserProfileRoute, CommentsRoute, SettingsSectionRoute } from '@tgx/core-navigation';
import { EntryNavigationController } from '../navigation/EntryNavigationController';
import { AppLinkResult, AppLinkRouter } from '../deeplink/AppLinkRouter';
import {
  InvitePromptData,
  PromptCard,
  ProxyPromptChoice,
  ProxyPromptData,
  EMPTY_PROMPT_CARD,
  appLinkReasonKey,
  invitePromptCard,
  proxyPromptCard
} from '../deeplink/AppLinkPrompt';
import { AppLinkPromptLayer } from '../deeplink/AppLinkPromptView';
import { ScopeAppLinkPort } from '../deeplink/ScopeAppLinkPort';
import { appDeepLinkQueue } from '../deeplink/DeepLinkQueue';
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
  DrawerNavTarget
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
  ForwardSelectedToChat,
  CommentsPage,
  CommentsUiState,
  CommentsCoordinator
} from '@tgx/feature-chat';
import {
  SettingsPage,
  SettingsUiState,
  SettingsIntent,
  SettingsCoordinator,
  SwitchAccount,
  RequestAddAccount,
  settingsOverlayCloseIntent,
  SectionFocused
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
import type { TdPendingRequest, TdWireObject } from '@tgx/td-gateway';
import {
  AutoDownloadPolicy,
  ChatRegistry,
  dataSaverNetworkOfSnapshot,
  DataSaverNetworkType,
  DownloadLimitsByNetwork,
  isDataSaverActive
} from '@tgx/core-domain';
import { NetworkSnapshot } from '@tgx/platform-ports';
import { BootstrapResult } from '../Bootstrap';
import { ScopeAuthAdapter } from '../ScopeAuthAdapter';
import { TELEGRAM_CREDENTIALS } from '../config/AppCredentials';
import { Logger } from '@tgx/observability';
import { HarmonyClipboardAdapter } from '../platform/HarmonyClipboardAdapter';
import { HarmonyToastAdapter } from '../platform/HarmonyToastAdapter';
import { HarmonyMediaPickerAdapter } from '../platform/HarmonyMediaPickerAdapter';
import { HarmonyAudioPlayerAdapter } from '../platform/HarmonyAudioPlayerAdapter';
import { HarmonyAudioRecorderAdapter } from '../platform/HarmonyAudioRecorderAdapter';
import { HarmonyAVSessionAdapter } from '../platform/HarmonyAVSessionAdapter';
import { HarmonyContinuousTaskAdapter } from '../platform/HarmonyContinuousTaskAdapter';
import { createHarmonyLogger } from '../platform/HarmonyLogSink';

const DOMAIN: number = 0x0000;
const TAG: string = 'Index';

@Entry
@Component
struct Index {
  /**
   * FEAT-UI-001 全局深色主题适配：entry 作为装配层把 ThemeManager 的当前 Theme
   * 写入 AppStorage('activeTheme')，各页面以 @StorageProp 订阅同一对象引用。
   * 此前各页面写死 `const T = LightTheme`，主题切换后引用不变，导致抽屉夜间模式
   * 开关可以拨动但界面无任何变化。
   */
  @StorageProp('activeTheme') T: Theme = LightTheme;
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
  private readonly audioPlayerAdapter: HarmonyAudioPlayerAdapter = new HarmonyAudioPlayerAdapter();
  private readonly audioRecorderAdapter: HarmonyAudioRecorderAdapter = new HarmonyAudioRecorderAdapter();
  /**
   * AUDIO-BG-101：锁屏播控（AVSession）+ 后台长时任务。两者必须成对注入 ——
   * HarmonyOS 自 API 20 起，不带 AVSession 的 AUDIO_PLAYBACK 长时任务会被系统回收。
   */
  private readonly avSessionAdapter: HarmonyAVSessionAdapter = new HarmonyAVSessionAdapter();
  private readonly continuousTaskAdapter: HarmonyContinuousTaskAdapter = new HarmonyContinuousTaskAdapter();
  private cacheDir: string = '/data/storage/el2/base/cache';
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
  /** AUTODL-101：设置页写、聊天页读的同一份策略存储（进程内单例，带账号级缓存）。 */
  private autoDownloadStore: PreferencesAutoDownloadPolicyStore | null = null;
  private dataSaverStore: PreferencesDataSaverStore | null = null;
  /** AUTODL-103：按网络档的自动下载限制（第三套设置，同样按账号隔离）。 */
  private downloadLimitsStore: PreferencesDownloadLimitsStore | null = null;
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
  // CHANNEL-101：频道帖子评论页
  @State commentsUiState: CommentsUiState = {
    channelChatId: 0,
    channelPostId: 0,
    channelTitle: '评论',
    postText: '',
    postDate: '',
    commentsCount: 0,
    isLoading: true,
    isSending: false,
    comments: [],
    inputText: '',
    errorMessage: null
  };
  private commentsCoordinator: CommentsCoordinator | null = null;
  private unsubscribeCommentsFn: (() => void) | null = null;
  /**
   * SET-105 / FEAT-UI-002：聊天字号的落盘通道。
   *
   * 业务层（feature_settings 的 reducer）只把值写进 AppStorage，不碰 Kit；由 entry
   * 以装配层身份监听该键变化并落盘。`@StorageProp` + `@Watch` 是 ArkUI 里拿到
   * 「AppStorage 键变化」的标准方式。启动回灌在 EntryAbility 里完成（见
   * store/SettingsStore.ets），这里只负责用户改动后的写盘方向。
   */
  @StorageProp('chatFontSize') @Watch('onChatFontSizeChanged') chatFontSizeRaw: string =
    `${CHAT_FONT_SIZE_DEFAULT}`;
  private chatFontSizeReady: boolean = false;
  private unsubscribeThemeFn: (() => void) | null = null;
  private accountScope: AccountScope | null = null;
  private bootstrapResult: BootstrapResult | null = null;
  private currentAccountKey: string = 'default';
  /** DEEPLINK-101：链接解析器；只建一次，账号 scope 走提供者。 */
  private appLinkRouter: AppLinkRouter | null = null;
  /** DEEPLINK-101：冷启动 want 要等进过 home 才有人接，attach 只做一次。 */
  private appLinkAttached: boolean = false;
  /**
   * DEEPLINK-102：链接确认弹窗。卡片文案是 `@State`，而**决定它的那次 await 的续体**
   * 留在私有字段里 —— Promise 的 resolve 函数不是渲染状态，放进 `@State` 只会让 ArkUI
   * 白白深拷贝一个不可比较的闭包。
   */
  @State promptVisible: boolean = false;
  @State promptCard: PromptCard = EMPTY_PROMPT_CARD;
  private promptKind: string = 'invite';
  private pendingInvite: ((accepted: boolean) => void) | null = null;
  private pendingProxy: ((choice: ProxyPromptChoice) => void) | null = null;


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
      this.cacheDir = result.cacheDir;
      this.mediaPickerAdapter.setCacheDir(result.cacheDir);
    }

    // VOICE-101：录音适配器需要 AbilityContext 才能申请麦克风运行时权限、
    // 读取 rawfile 占位音频。字段初始化阶段拿不到 context，只能在这里注入。
    const hostContext = this.getUIContext().getHostContext();
    if (hostContext !== undefined) {
      this.audioRecorderAdapter.setAbilityContext(hostContext as common.UIAbilityContext);
      // AUDIO-BG-101：会话与长时任务同样要 UIAbilityContext（建会话、申请任务、点通知回到本应用）。
      const abilityContext = hostContext as common.UIAbilityContext;
      this.avSessionAdapter.setContext(abilityContext);
      this.continuousTaskAdapter.setContext(abilityContext);
      this.audioPlayerAdapter.attachAudioSession(this.avSessionAdapter, this.continuousTaskAdapter);
    } else {
      hilog.warn(DOMAIN, TAG, 'no host context; voice recording will fall back to placeholder clip');
    }

    // SET-105 / FEAT-UI-002：先把持久化的聊天字号灌进 ThemeManager，再取初始 Theme。
    // 顺序很关键——若先取 Theme 再设字号，首帧会以默认字号渲染并立刻被推一次多余的刷新。
    // 注意：该键在 AppStorage 里按**字符串**约定存放（entry 回灌与 feature_settings
    // 的 reducer 都写 `${size}`），统一交给 parseChatFontSize 做类型收敛。
    const savedChatFontSizeRaw: number | string | undefined | null = AppStorage.get<string>('chatFontSize');
    ThemeManager.getInstance().setChatFontSize(parseChatFontSize(savedChatFontSizeRaw));
    // 首帧读完初值后才允许落盘，避免启动回灌本身触发一次无意义的写。
    this.chatFontSizeReady = true;

    const initialTheme: Theme = ThemeManager.getInstance().getTheme();
    AppStorage.setOrCreate<Theme>('activeTheme', initialTheme);
    this.unsubscribeThemeFn = ThemeManager.getInstance().subscribe((theme: Theme): void => {
      AppStorage.setOrCreate<Theme>('activeTheme', theme);
    });

    this.unsubscribeNavFn = this.navController.subscribe((route: AppRoute, prev: AppRoute | null) => {
      this.currentRoute = route;
      this.onRouteChanged(route, prev);
    });

    this.initAuthCoordinatorSubscription(result.scope);
    this.updateAvailableAccounts();
    // DEEPLINK-101：状态恢复可能直接落在 home（没走过 onRouteChanged），补一次挂载判定。
    this.syncAppLinkHandler();
  }

  /**
   * SET-105：`chatFontSize` 变化 → 落盘。值是字符串（AppStorage 里的约定），
   * 数值收敛与档位吸附都交给 SettingsStore → clampChatFontSize。
   */
  private onChatFontSizeChanged(): void {
    if (!this.chatFontSizeReady) {
      return;
    }
    saveChatFontSize(this.chatFontSizeRaw);
  }

  aboutToDisappear(): void {
    // DEEPLINK-101：页面要销毁了，别让队列继续往已销毁的协调器里投链接。
    this.appLinkAttached = false;
    appDeepLinkQueue.detach();
    if (this.unsubscribeNavFn !== null) {
      this.unsubscribeNavFn();
      this.unsubscribeNavFn = null;
    }
    this.closeChat();
    this.closeSettings();
    this.closeSearch();
    this.closeComments();
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
    if (this.unsubscribeThemeFn !== null) {
      this.unsubscribeThemeFn();
      this.unsubscribeThemeFn = null;
    }
  }

  onBackPress(): boolean {
    // 应用锁生效时返回键必须被吞掉：遮罩盖住的不是某一页，而是整个应用，
    // 放行一次 pop 就等于绕过了 PIN（Android 侧同理 —— PasscodeView 是独立 window）。
    const lockGate: AppLockGate | null = appLockGate();
    if (lockGate !== null && lockGate.snapshot().stage !== 'unlocked') {
      return true;
    }
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
    if (this.currentRoute.name === 'settings' || this.currentRoute.name === 'settingsSection') {
      // SET-BACK-101：设置页的子页与弹层全是同一层 Stack 上的覆盖层，导航栈管不到，
      // 所以「先关最上层、关完才 pop」的层级只能由 feature/settings 自己定（那里才有
      // 渲染顺序这唯一真相）。隐私详情页尤其要紧：它的写回挂在关闭意图上，
      // 少了这一层判断，物理返回键会静默丢掉未提交的规则改动。
      const overlayIntent: SettingsIntent | null = settingsOverlayCloseIntent(this.settingsUiState);
      if (overlayIntent !== null) {
        this.settingsDispatch(overlayIntent);
        return true;
      }
      return this.navController.pop();
    }
    return this.navController.pop();
  }

  /**
   * DEEPLINK-101：装配链接解析器（懒建，只建一次）。
   *
   * scope 走**提供者**而不是构造时快照：切账号会换 scope，未登录时根本没有 scope，
   * 而两条入口（冷启动 want、气泡点击）都可能在任一时刻发生。
   * isReady 用「栈里有 home」判定：auth 阶段没有可用会话库，`searchPublicChat` 必然失败。
   */
  private ensureAppLinkRouter(): AppLinkRouter | null {
    if (this.appLinkRouter !== null) {
      return this.appLinkRouter;
    }
    if (this.accountScope === null) {
      return null;
    }
    this.appLinkRouter = new AppLinkRouter(
      new ScopeAppLinkPort((): AccountScope | null => this.accountScope),
      {
        navigate: (route: AppRoute): void => {
          this.navController.navigateTo(route);
        },
        isReady: (): boolean => this.navController.hasRoute('home'),
        prompt: {
          confirmInvite: (data: InvitePromptData): Promise<boolean> => this.askInvite(data),
          chooseProxy: (data: ProxyPromptData): Promise<ProxyPromptChoice> => this.askProxy(data)
        },
        logger: this.logger
      }
    );
    return this.appLinkRouter;
  }

  /** 翻译入口：弹窗构卡要的是当前语言的句子，而 Lang 是全局单例。 */
  private tr(key: string, ...args: (string | number)[]): string {
    const lang: Lang = Lang.getInstance();
    return args.length === 0 ? lang.getString(key) : lang.getString(key, ...args);
  }

  /**
   * DEEPLINK-102：邀请确认。路由器在这里 await，页面按下去才继续。
   *
   * 同一时刻只有一张卡（路由器自己有 inFlight 串行），所以旧的续体先按「拒绝」结算 ——
   * 宁可丢掉一条没人确认的链接，也不能让上一个 await 永远挂着。
   */
  private askInvite(data: InvitePromptData): Promise<boolean> {
    this.settlePrompt();
    return new Promise<boolean>((resolve: (accepted: boolean) => void): void => {
      this.pendingInvite = resolve;
      this.promptKind = 'invite';
      this.promptCard = invitePromptCard(data, (key: string, ...args: (string | number)[]): string => this.tr(key, ...args));
      this.promptVisible = true;
    });
  }

  private askProxy(data: ProxyPromptData): Promise<ProxyPromptChoice> {
    this.settlePrompt();
    return new Promise<ProxyPromptChoice>((resolve: (choice: ProxyPromptChoice) => void): void => {
      this.pendingProxy = resolve;
      this.promptKind = 'proxy';
      this.promptCard = proxyPromptCard(data, (key: string, ...args: (string | number)[]): string => this.tr(key, ...args));
      this.promptVisible = true;
    });
  }

  /** 收卡并把还挂着的 await 结算掉（未选 = 取消）。 */
  private settlePrompt(): void {
    this.promptVisible = false;
    if (this.pendingInvite !== null) {
      const resolve: (accepted: boolean) => void = this.pendingInvite;
      this.pendingInvite = null;
      resolve(false);
    }
    if (this.pendingProxy !== null) {
      const resolveChoice: (choice: ProxyPromptChoice) => void = this.pendingProxy;
      this.pendingProxy = null;
      resolveChoice('cancel');
    }
  }

  private onPromptPrimary(): void {
    if (this.promptKind === 'proxy') {
      this.settleWithChoice('enable');
      return;
    }
    this.settleWithAnswer(true);
  }

  private onPromptSecondary(): void {
    this.settleWithChoice('save');
  }

  private onPromptCancel(): void {
    if (this.promptKind === 'proxy') {
      this.settleWithChoice('cancel');
      return;
    }
    this.settleWithAnswer(false);
  }

  private settleWithAnswer(accepted: boolean): void {
    this.promptVisible = false;
    if (this.pendingInvite !== null) {
      const resolve: (accepted: boolean) => void = this.pendingInvite;
      this.pendingInvite = null;
      resolve(accepted);
    }
  }

  private settleWithChoice(choice: ProxyPromptChoice): void {
    this.promptVisible = false;
    if (this.pendingProxy !== null) {
      const resolve: (value: ProxyPromptChoice) => void = this.pendingProxy;
      this.pendingProxy = null;
      resolve(choice);
    }
  }

  /**
   * DEEPLINK-101：把一条链接交给解析器，并按结果决定去留。
   *
   * 冷启动时 want 比页面早到（`EntryAbility.onCreate` → `loadContent`），
   * 所以链接先进 `appDeepLinkQueue`，进过 home 才挂处理器把积压补投。
   */
  private dispatchAppLink(uri: string): void {
    this.resolveAppLink(uri);
  }

  private async resolveAppLink(uri: string): Promise<void> {
    const router: AppLinkRouter | null = this.ensureAppLinkRouter();
    if (router === null) {
      this.deferAppLink(uri, 'no router');
      return;
    }
    try {
      const res: AppLinkResult = await router.handle(uri);
      if (res.outcome === 'not_ready') {
        this.deferAppLink(uri, 'account not ready');
        return;
      }
      if (res.outcome === 'external') {
        // TDLib 判定不是 Telegram 链接（Android `internalLinkTypeUnknownDeepLink`）→ 浏览器。
        this.openInBrowser(uri);
        return;
      }
      if (res.outcome === 'cancelled') {
        // 用户在弹窗里说了不 —— 不打扰，日志由路由器记。
        return;
      }
      if (res.outcome === 'notified') {
        // 动作完成但没有页面可去（代理已存/已启用、加入申请已发出）。
        this.toastAdapter.showToast(this.tr(appLinkReasonKey(res.reason)));
        return;
      }
      if (res.outcome === 'unsupported') {
        // 是 Telegram 链接但本端这一步还没做（贴纸包/语音聊天…）；不丢进浏览器登录墙。
        this.toastAdapter.showToast(Lang.getInstance().getString('This link type is not supported yet'));
        return;
      }
      if (res.outcome === 'failed') {
        this.toastAdapter.showToast(Lang.getInstance().getString('Failed to open link'));
      }
    } catch (e) {
      // 只记事件，不记链接正文（可携带邀请哈希）。
      hilog.warn(DOMAIN, TAG, 'app link resolution threw');
    }
  }

  /** DEEPLINK-101：外部链接落浏览器（与 feature/chat 的气泡链接口径一致）。 */
  private openInBrowser(url: string): void {
    const hostContext = this.getUIContext().getHostContext();
    if (hostContext === undefined) {
      hilog.warn(DOMAIN, TAG, 'openInBrowser failed: no host context');
      return;
    }
    const context = hostContext as common.UIAbilityContext;
    context.openLink(url, { appLinkingOnly: false }).catch((e: Object) => {
      hilog.warn(DOMAIN, TAG, 'openInBrowser failed');
      this.toastAdapter.showToast(Lang.getInstance().getString('Failed to open link'));
    });
  }

  /**
   * 解析还来不及（未登录 / 没 scope）时的去路：**只有队列没有消费者时才回队**，
   * 否则 `enqueue` 会立刻回调本方法 —— 自喂死循环。
   * 有消费者却仍然 not_ready，说明链接是在登出清栈的间隙里进来的，丢掉并记一条原因。
   */
  private deferAppLink(uri: string, reason: string): void {
    if (!appDeepLinkQueue.isAttached()) {
      appDeepLinkQueue.enqueue(uri);
      return;
    }
    // 只记原因与长度，不记链接正文。
    hilog.warn(DOMAIN, TAG, 'app link dropped: %{public}s', reason);
  }

  /**
   * 处理器只在「栈里有 home」时挂上 —— 挂上就会立刻补投积压，而补投需要可用的
   * 会话库；登出清栈时反向卸掉，之后进来的链接重新排队，等下一次进 home 补投。
   */
  private syncAppLinkHandler(): void {
    const ready: boolean = this.navController.hasRoute('home');
    if (ready && !this.appLinkAttached) {
      this.appLinkAttached = true;
      const flushed: number = appDeepLinkQueue.attach((uri: string): void => {
        this.dispatchAppLink(uri);
      });
      if (flushed > 0) {
        hilog.info(DOMAIN, TAG, 'app link handler attached, flushed %{public}d queued link(s)', flushed);
      }
    } else if (!ready && this.appLinkAttached) {
      this.appLinkAttached = false;
      appDeepLinkQueue.detach();
    }
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
    if (!this.navController.hasRoute('comments') && this.commentsCoordinator !== null) {
      this.closeComments();
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
    } else if (route.name === 'comments') {
      const commentsRoute: CommentsRoute = route as CommentsRoute;
      if (this.commentsCoordinator === null ||
          this.commentsUiState.channelChatId !== commentsRoute.chatId ||
          this.commentsUiState.channelPostId !== commentsRoute.messageId) {
        this.openComments(commentsRoute.chatId, commentsRoute.messageId);
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
      // SELF-101：「我的资料」入口带 section 时直达对应分区/子页。
      if (route.name === 'settingsSection') {
        const sectionRoute: SettingsSectionRoute = route as SettingsSectionRoute;
        this.settingsDispatch(new SectionFocused(sectionRoute.section));
      }
    } else if (route.name === 'search') {
      if (this.searchCoordinator === null) {
        this.openSearch();
      }
    }

    // 3. DEEPLINK-101：链接处理器跟着「是否已进过 home」走。
    this.syncAppLinkHandler();
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
        toastPort: this.toastAdapter,
        audioPlayerPort: this.audioPlayerAdapter,
        onOpenChat: (chatId: number): void => {
          // 「发消息」：私聊压栈到资料页之上，返回仍落回资料页。
          // 密聊走同一条导航：secretChat.id 即 chat.id（type 为 chatTypeSecret）。
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
        },
        audioPlayerPort: this.audioPlayerAdapter
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

  // CHANNEL-101：频道帖子评论页打开与关闭
  private openComments(chatId: number, messageId: number): void {
    if (this.accountScope === null) {
      return;
    }
    this.closeComments();
    const coordinator: CommentsCoordinator = new CommentsCoordinator(
      this.accountScope,
      chatId,
      messageId,
      () => {
        this.navController.pop();
      }
    );
    this.commentsCoordinator = coordinator;
    this.unsubscribeCommentsFn = coordinator.subscribe((uiState: CommentsUiState) => {
      this.commentsUiState = uiState;
    });
    coordinator.start();
    hilog.info(DOMAIN, TAG, 'comments coordinator started for chatId=%{public}s postId=%{public}s', `${chatId}`, `${messageId}`);
  }

  private closeComments(): void {
    if (this.unsubscribeCommentsFn !== null) {
      this.unsubscribeCommentsFn();
      this.unsubscribeCommentsFn = null;
    }
    if (this.commentsCoordinator !== null) {
      this.commentsCoordinator.destroy();
      this.commentsCoordinator = null;
    }
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
      logger: this.logger,
      onOpenSettingsSection: (section: string): void => {
        this.navController.navigateTo({ name: 'settingsSection', section: section });
      }
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
      this.logger,
      (target: DrawerNavTarget) => {
        if (target === 'contacts') {
          this.navController.navigateTo({ name: 'contacts' });
        } else if (target === 'settings') {
          this.navController.navigateTo({ name: 'settings' });
        } else {
          this.navController.navigateTo({ name: 'selfProfile' });
        }
      }
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

  /**
   * AUTODL-101：懒建策略存储。accountKey 走闭包而不是构造参数，
   * 这样切换账号后存储自己会按新 key 重读一次，装配层不用管失效。
   */
  private getAutoDownloadStore(): PreferencesAutoDownloadPolicyStore {
    if (this.autoDownloadStore === null) {
      this.autoDownloadStore = new PreferencesAutoDownloadPolicyStore((): string => this.currentAccountKey);
    }
    return this.autoDownloadStore;
  }

  /** AUTODL-102：省流量设置存储，与策略存储同一份账号键。 */
  private getDataSaverStore(): PreferencesDataSaverStore {
    if (this.dataSaverStore === null) {
      this.dataSaverStore = new PreferencesDataSaverStore((): string => this.currentAccountKey);
    }
    return this.dataSaverStore;
  }

  /**
   * AUTODL-103：当前网络档。读 `LifecycleCoordinator.lastNetworkSnapshot` 的缓存
   * （它是全应用唯一的网络观察者），不在每条附件上同步问 Kit。
   * bootstrap 还没就绪时快照为 null → 档位 'none' → 按 Android 的 default 分支落移动那一档。
   */
  private currentNetworkType(): DataSaverNetworkType {
    const snapshot: NetworkSnapshot | null = this.bootstrapResult === null
      ? null
      : this.bootstrapResult.lifecycle.lastNetworkSnapshot;
    return dataSaverNetworkOfSnapshot(snapshot);
  }

  /** AUTODL-103：按网络档的自动下载限制存储，与策略 / 省流量同一份账号键。 */
  private getDownloadLimitsStore(): PreferencesDownloadLimitsStore {
    if (this.downloadLimitsStore === null) {
      this.downloadLimitsStore = new PreferencesDownloadLimitsStore((): string => this.currentAccountKey);
    }
    return this.downloadLimitsStore;
  }

  /**
   * AUTODL-102：此刻省流量是否生效 —— 聊天页下载门的第一句。
   *
   * 两个来源都读缓存，所以每条附件调用它都是常数开销：设置走 `DataSaverStore.current()`，
   * 网络走 `currentNetworkType()`。读不到网络时档位是 'none'，只有主开关能拦，
   * 这比「读不到网络就一律不放行」更符合用户预期：会话页都打开了，Wi-Fi 下不该不下图。
   */
  private isDataSaverActiveNow(): boolean {
    return isDataSaverActive(this.getDataSaverStore().current(), this.currentNetworkType());
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
    coordinator.setAutoDownloadStore(this.getAutoDownloadStore());
    coordinator.setDataSaverStore(this.getDataSaverStore());
    coordinator.setDownloadLimitsStore(this.getDownloadLimitsStore());
    // APPLOCK-101：PIN 存储来自 entry 装配的模块单例；没装上就传 null，
    // 协调器会如实回「写盘失败」而不是把界面点亮。必须在 start() 之前注入 ——
    // start() 会立刻发 loadPasscodeState 读盘。
    coordinator.setAppLockStore(appLockStore());
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
        audioPlayerPort: this.audioPlayerAdapter,
        audioRecorderPort: this.audioRecorderAdapter,
        cacheDir: this.cacheDir,
        logger: this.logger,
        // AUTODL-101：聊天页读同一份策略存储；用闭包而不是快照，设置页改完下一条即可生效。
        autoDownloadPolicyProvider: (): AutoDownloadPolicy | null => this.getAutoDownloadStore().current(),
        // AUTODL-102：省流量是压在策略上面的那一票否决（Android `canAutomaticallyDownload()` 的第一句）。
        // 网络状态读 LifecycleCoordinator 的缓存快照，不在每条附件上同步问 Kit。
        dataSaverActiveProvider: (): boolean => this.isDataSaverActiveNow(),
        // AUTODL-103：按当前网络档的尺寸上限与类型排除（Android 的第三层，压在分区勾选之前）。
        downloadLimitsProvider: (): DownloadLimitsByNetwork | null => this.getDownloadLimitsStore().current(),
        networkTypeProvider: (): DataSaverNetworkType => this.currentNetworkType(),
        // PROFILE-101：群聊点头像 → 压栈用户资料页。
        onOpenUserProfile: (userId: number): void => {
          this.navController.navigateTo({ name: 'userProfile', userId: userId });
        },
        // PROFILE-102：群聊/频道点击标题 → 压栈群组/频道资料页。
        onOpenChatProfile: (targetChatId: number): void => {
          this.navController.navigateTo({ name: 'chatInfo', chatId: targetChatId });
        },
        // CHANNEL-101：频道帖子底栏点击「评论」→ 压栈评论页。
        onOpenComments: (targetChatId: number, targetMessageId: number): void => {
          this.navController.navigateTo({ name: 'comments', chatId: targetChatId, messageId: targetMessageId });
        },
        // DEEPLINK-101：气泡里的 Telegram 链接 → 交装配层解析后应用内跳（不进浏览器）。
        onOpenAppLink: (url: string): void => {
          this.dispatchAppLink(url);
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
    this.audioPlayerAdapter.stop();
    this.audioRecorderAdapter.cancelRecord();
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
    // DEEPLINK-102：根节点从 Column 换成 Stack，是为了让弹窗覆盖在当前页之上而不占布局位。
    // Column 那一层保持原样（整屏一页 + 背景色），Stack 只负责叠一层。
    Stack() {
      Column() {
        if (this.bootstrapError !== null) {
          Column() {
            Text('Bootstrap Error')
              .fontSize(this.T.typography.title.fontSize)
              .fontWeight(this.T.typography.title.fontWeight)
              .fontColor(this.T.colors.destructive)
              .margin({ bottom: this.T.spacing.sm })

            Text(this.bootstrapError)
              .fontSize(this.T.typography.body.fontSize)
              .fontColor(this.T.colors.textSecondary)
          }
          .width('100%')
          .height('100%')
          .justifyContent(FlexAlign.Center)
          .alignItems(HorizontalAlign.Center)
          .backgroundColor(this.T.colors.background)
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
        } else if (this.currentRoute.name === 'comments') {
          CommentsPage({
            uiState: this.commentsUiState,
            coordinator: this.commentsCoordinator !== null ? this.commentsCoordinator : undefined,
            onBack: () => {
              this.navController.pop();
            }
          })
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
            },
            onBack: () => {
              this.navController.pop();
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
            onCompose: () => {
              this.navController.navigateTo({ name: 'contacts' });
            },
            // DRAWER-101：账号头（getMe + 头像）与菜单去向都由 chat_list 的
            // reducer/coordinator 决定；装配层只执行夜间模式切换与账号切换占位。
            onDrawerNightModeChanged: (on: boolean): void => {
              ThemeManager.getInstance().setPreference(on ? 'dark' : 'light');
              hilog.info(DOMAIN, TAG, 'drawer night mode changed: %{public}s', `${on}`);
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
      .backgroundColor(this.T.colors.background)
      // DEEPLINK-102：链接确认弹窗盖在当前页面之上 —— 深链可能落在任何一页，
      // 而这一层由 entry 持有（它是唯一的路由/装配所有者），feature 不知道它存在。
      if (this.promptVisible) {
        AppLinkPromptLayer({
          card: this.promptCard,
          onPrimary: (): void => {
            this.onPromptPrimary();
          },
          onSecondary: (): void => {
            this.onPromptSecondary();
          },
          onCancel: (): void => {
            this.onPromptCancel();
          }
        })
      }
      // APPLOCK-101：应用锁遮罩压在包括链接弹窗在内的一切之上 —— 它自己决定何时出现，
      // 未锁定时不渲染任何节点，所以这里无条件挂载。
      AppLockOverlay()
    }
    .width('100%')
    .height('100%')
  }
}
