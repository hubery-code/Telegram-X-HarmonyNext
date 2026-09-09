/**
 * entry — Index 页面：真机授权流程 + 会话列表占位（SPIKE-001）。
 *
 * EntryAbility.onCreate → bootstrap() → AuthCoordinator.start()
 * 本页面从 AppStorage 读取 BootstrapResult，订阅 AuthCoordinator 状态变化，
 * 将 intents 分发给 AuthCoordinator（真实 TDLib 请求）。
 */

import { LightTheme } from '@tgx/core-design-system';
import { hilog } from '@kit.PerformanceAnalysisKit';
import {
  AuthRootPage,
  AuthUiState,
  AuthIntent,
  AuthCoordinator
} from '@tgx/feature-auth';
import { BootstrapResult } from '../Bootstrap';

const T = LightTheme;
const DOMAIN: number = 0x0000;
const TAG: string = 'Index';

@Entry
@Component
struct Index {
  @State uiState: AuthUiState = AuthUiState.initial();
  @State showChatList: boolean = false;
  @State bootstrapError: string | null = null;

  private coordinator: AuthCoordinator | null = null;
  private unsubscribeFn: (() => void) | null = null;

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
      }
    });
  }

  aboutToDisappear(): void {
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
        Column() {
          Text('Telegram X')
            .fontSize(T.typography.largeTitle.fontSize)
            .fontWeight(T.typography.largeTitle.fontWeight)
            .fontColor(T.colors.textPrimary)
            .margin({ top: T.spacing.huge, bottom: T.spacing.sm })

          Text('Chat list placeholder')
            .fontSize(T.typography.body.fontSize)
            .fontColor(T.colors.textSecondary)
        }
        .width('100%')
        .height('100%')
        .justifyContent(FlexAlign.Center)
        .alignItems(HorizontalAlign.Center)
        .backgroundColor(T.colors.background)
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
