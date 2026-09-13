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
 * 导航优先级 chat > settings > search > chatList > auth。
 * **从搜索结果打开会话时故意不清 showSearch**：build() 里 chat 分支优先级更高，
 * 所以进会话后返回会自然落回搜索结果（保留查询与结果，对齐 Telegram X），
 * 因此 searchCoordinator 也必须活到搜索页真正关闭为止，不能在 openChat 里销毁。
 */

import { LightTheme } from '@tgx/core-design-system';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { AccountScope } from '@tgx/core-account';
import {
  AuthRootPage,
  AuthUiState,
  AuthIntent,
  AuthCoordinator
} from '@tgx/feature-auth';
import {
  ChatListPage,
  ChatListUiState,
  ChatListIntent,
  ChatListItem,
  ChatListCoordinator
} from '@tgx/feature-chat-list';
import {
  ChatPage,
  ChatUiState,
  ChatIntent,
  BackToChatList,
  ChatCoordinator,
  ForwardPickerPage,
  ForwardTarget,
  ForwardSelectedToChat
} from '@tgx/feature-chat';
import {
  SettingsPage,
  SettingsUiState,
  SettingsIntent,
  SettingsCoordinator
} from '@tgx/feature-settings';
import {
  SearchPage,
  SearchUiState,
  SearchIntent,
  SearchCoordinator
} from '@tgx/feature-search';
import { BootstrapResult } from '../Bootstrap';

const T = LightTheme;
const DOMAIN: number = 0x0000;
const TAG: string = 'Index';

@Entry
@Component
struct Index {
  @State uiState: AuthUiState = AuthUiState.initial();
  @State showChatList: boolean = false;
  @State chatListUiState: ChatListUiState = ChatListUiState.initial();
  @State currentChatId: number | null = null;
  @State chatUiState: ChatUiState = ChatUiState.initial();
  @State showSettings: boolean = false;
  @State settingsUiState: SettingsUiState = SettingsUiState.initial();
  /** MSG-106：转发目标选择器是否覆盖显示 + 本次候选目标。 */
  @State showForwardPicker: boolean = false;
  @State forwardTargets: ForwardTarget[] = [];
  /** INTEG-002：搜索页是否显示 + 其可观察状态。 */
  @State showSearch: boolean = false;
  @State searchUiState: SearchUiState = SearchUiState.initial();
  @State bootstrapError: string | null = null;

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
  private accountScope: AccountScope | null = null;

  aboutToAppear(): void {
    const result: BootstrapResult | undefined = AppStorage.get<BootstrapResult>('bootstrapResult');
    if (result === undefined || result === null) {
      this.bootstrapError = 'Bootstrap failed — see logs';
      hilog.error(DOMAIN, TAG, 'bootstrapResult not found in AppStorage');
      return;
    }

    this.coordinator = result.coordinator;
    this.accountScope = result.scope;
    this.unsubscribeFn = this.coordinator.subscribe((state: AuthUiState) => {
      this.uiState = state;
      if (state.step === 'ready') {
        this.showChatList = true;
        if (this.chatListCoordinator === null) {
          this.chatListCoordinator = new ChatListCoordinator(result.scope, undefined,
            (chatId: number, chatTitle: string) => {
              this.openChat(chatId, chatTitle);
            });
          this.chatListCoordinator.start();
          this.unsubscribeChatListFn = this.chatListCoordinator.subscribe((uiState: ChatListUiState) => {
            this.chatListUiState = uiState;
          });
          hilog.info(DOMAIN, TAG, 'chat list coordinator started');
        }
      } else if (this.showChatList) {
        // 授权离开 ready（登出/会话关闭）：销毁会话与设置协调器，回到登录页。
        this.handleSessionEnded();
      }
    });
  }

  aboutToDisappear(): void {
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
    if (this.currentChatId !== null) {
      // MSG-106：选择器打开时返回只关选择器，不退出会话页也不退出多选态。
      if (this.showForwardPicker) {
        this.closeForwardPicker();
        return true;
      }
      // INTEG-002：从搜索结果进来的会话，返回后 showSearch 仍为 true，
      // 于是自然落回搜索结果（查询与结果都还在）。
      this.chatDispatch(new BackToChatList());
      return true;
    }
    if (this.showSettings) {
      this.closeSettings();
      return true;
    }
    // INTEG-002：搜索页返回 → 关搜索回会话列表。
    if (this.showSearch) {
      this.closeSearch();
      return true;
    }
    return false;
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
    this.showChatList = false;
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
      }
    });
    this.searchCoordinator = coordinator;
    this.unsubscribeSearchFn = coordinator.subscribe((uiState: SearchUiState) => {
      this.searchUiState = uiState;
    });
    this.showSearch = true;
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
    this.showSearch = false;
  }

  /**
   * 搜索结果 → 会话。故意不清 showSearch：build() 里 chat 优先级高于 search，
   * 所以进会话后按返回会自然回到搜索结果。
   * messageId 目前只记录不改行为——把会话滚到指定消息需要"围绕该消息拉历史"
   * 的能力（现有 ChatPage.scrollToMessageId 只对已加载消息有效），属 SEARCH-102
   * 「聊天内搜索 + 结果跳转定位」范围。
   */
  private navigateToChatFromSearch(chatId: number, messageId?: number): void {
    hilog.info(DOMAIN, TAG, 'navigate from search chatId=%{public}s messageId=%{public}s',
      `${chatId}`, `${messageId !== undefined ? messageId : 0}`);
    const title: string = this.chatTitleOf(chatId);
    this.openChat(chatId, title);
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

  private openSettings(): void {
    if (this.accountScope === null || this.settingsCoordinator !== null) {
      return;
    }
    const coordinator: SettingsCoordinator = new SettingsCoordinator(
      this.accountScope,
      undefined,
      undefined,
      () => {
        // logOut 请求已成功；TDLib 授权状态更新（loggingOut → waitPhone）随后经
        // AuthCoordinator 订阅驱动 handleSessionEnded 完成整体退场，这里先关闭设置页。
        this.closeSettings();
      }
    );
    this.settingsCoordinator = coordinator;
    this.unsubscribeSettingsFn = coordinator.subscribe((uiState: SettingsUiState) => {
      this.settingsUiState = uiState;
    });
    coordinator.start();
    this.showSettings = true;
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
    this.showSettings = false;
  }

  private openChat(chatId: number, chatTitle: string): void {
    if (this.accountScope === null) {
      return;
    }
    this.closeChat();
    const coordinator: ChatCoordinator = new ChatCoordinator(
      this.accountScope,
      chatId,
      chatTitle,
      () => {
        this.closeChat();
      },
      (messageIds: number[]) => {
        this.openForwardPicker(chatId, messageIds);
      }
    );
    this.chatCoordinator = coordinator;
    this.unsubscribeChatFn = coordinator.subscribe((uiState: ChatUiState) => {
      this.chatUiState = uiState;
    });
    coordinator.start();
    this.currentChatId = chatId;
    hilog.info(DOMAIN, TAG, 'chat coordinator started for chatId=%{public}s', `${chatId}`);
  }

  private closeChat(): void {
    this.closeForwardPicker();
    if (this.unsubscribeChatFn !== null) {
      this.unsubscribeChatFn();
      this.unsubscribeChatFn = null;
    }
    if (this.chatCoordinator !== null) {
      this.chatCoordinator.destroy();
      this.chatCoordinator = null;
    }
    this.currentChatId = null;
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
        item.chatId === fromChatId
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
      } else if (this.currentChatId !== null) {
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
      } else if (this.showSettings) {
        SettingsPage({
          uiState: this.settingsUiState,
          onDispatch: (intent: SettingsIntent) => {
            this.settingsDispatch(intent);
          },
          onBack: () => {
            this.closeSettings();
          }
        })
      } else if (this.showSearch) {
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
      } else if (this.showChatList) {
        ChatListPage({
          uiState: this.chatListUiState,
          onDispatch: (intent: Object) => {
            this.chatListDispatch(intent as ChatListIntent);
          },
          onOpenSettings: () => {
            this.openSettings();
          },
          onOpenSearch: () => {
            this.openSearch();
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
