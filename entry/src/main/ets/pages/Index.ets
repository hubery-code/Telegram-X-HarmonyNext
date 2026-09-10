/**
 * entry — Index 页面：真机授权流程 + 会话列表（SPIKE-001 + CHATLIST-003）。
 *
 * EntryAbility.onCreate → bootstrap() → AuthCoordinator.start()
 * 本页面从 AppStorage 读取 BootstrapResult，订阅 AuthCoordinator 状态变化，
 * 将 intents 分发给 AuthCoordinator（真实 TDLib 请求）。
 * 授权到达 ready 后创建 ChatListCoordinator（core/domain ChatListProjection
 * + feature/chat_list MVI），渲染真实会话列表。
 */

import { LightTheme } from '@tgx/core-design-system';
import { hilog } from '@kit.PerformanceAnalysisKit';
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
  @State bootstrapError: string | null = null;

  private coordinator: AuthCoordinator | null = null;
  private unsubscribeFn: (() => void) | null = null;
  private chatListCoordinator: ChatListCoordinator | null = null;
  private unsubscribeChatListFn: (() => void) | null = null;

  aboutToAppear(): void {
    const result: BootstrapResult | undefined = AppStorage.get<BootstrapResult>('bootstrapResult');
    if (result === undefined || result === null) {
      this.bootstrapError = 'Bootstrap failed — see logs';
      hilog.error(DOMAIN, TAG, 'bootstrapResult not found in AppStorage');
      return;
    }

    this.coordinator = result.coordinator;
    this.unsubscribeFn = this.coordinator.subscribe((state: AuthUiState) => {
      this.uiState = state;
      if (state.step === 'ready') {
        this.showChatList = true;
        if (this.chatListCoordinator === null) {
          this.chatListCoordinator = new ChatListCoordinator(result.scope);
          this.chatListCoordinator.start();
          this.unsubscribeChatListFn = this.chatListCoordinator.subscribe((uiState: ChatListUiState) => {
            this.chatListUiState = uiState;
          });
          hilog.info(DOMAIN, TAG, 'chat list coordinator started');
        }
      }
    });
  }

  aboutToDisappear(): void {
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
      } else if (this.showChatList) {
        ChatListPage({
          uiState: this.chatListUiState,
          onDispatch: (intent: Object) => {
            this.chatListDispatch(intent as ChatListIntent);
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
