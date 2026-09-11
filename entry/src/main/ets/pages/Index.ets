/**
 * entry — Index 页面：真机授权流程 + 会话列表 + 会话消息页 + 设置页
 * （SPIKE-001 + CHATLIST-003 + CHAT-001/CHAT-002 + INTEG-001）。
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
  ChatListCoordinator
} from '@tgx/feature-chat-list';
import {
  ChatPage,
  ChatUiState,
  ChatIntent,
  ChatCoordinator
} from '@tgx/feature-chat';
import {
  SettingsPage,
  SettingsUiState,
  SettingsIntent,
  SettingsCoordinator
} from '@tgx/feature-settings';
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
  @State bootstrapError: string | null = null;

  private coordinator: AuthCoordinator | null = null;
  private unsubscribeFn: (() => void) | null = null;
  private chatListCoordinator: ChatListCoordinator | null = null;
  private unsubscribeChatListFn: (() => void) | null = null;
  private chatCoordinator: ChatCoordinator | null = null;
  private unsubscribeChatFn: (() => void) | null = null;
  private settingsCoordinator: SettingsCoordinator | null = null;
  private unsubscribeSettingsFn: (() => void) | null = null;
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
   * 销毁会话与设置协调器并回到登录页；再次 ready 时会话列表协调器重建。
   */
  private handleSessionEnded(): void {
    this.closeChat();
    this.closeSettings();
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

  build() {
    Column() {
      if (this.bootstrapError !== null) {
        Column() {
          Text('Bootstrap Error')
            .fontSize(T.typography.title.fontSize)
            .fontWeight(T.typography.title.fontWeight)
            .fontColor(T.colors.error)
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
        ChatPage({
          uiState: this.chatUiState,
          onDispatch: (intent: Object) => {
            this.chatDispatch(intent as ChatIntent);
          }
        })
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
      } else if (this.showChatList) {
        ChatListPage({
          uiState: this.chatListUiState,
          onDispatch: (intent: Object) => {
            this.chatListDispatch(intent as ChatListIntent);
          },
          onOpenSettings: () => {
            this.openSettings();
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
