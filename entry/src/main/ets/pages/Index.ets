/**
 * entry — Index 页面：授权流程与（占位）会话列表路由（AUTH-001）。
 *
 * 未授权时渲染 AuthRootPage（手机号/验证码/2FA/注册）；
 * 授权完成后切换到占位会话列表。
 *
 * TODO（真机集成，需 SPIKE-001 确认后启用）：
 * - bootstrap() → scope.gatewayInstance.start() → 订阅 scope 事件流
 * - AuthCoordinator 驱动 authReducer + scope.authorizationHolder
 * - 当前用 fake AuthUiState.initial() 注入，页面可独立渲染
 * - 真机启动后取消下方 fake 标记，连接 AuthCoordinator
 */

import { LightTheme } from '@tgx/core-design-system';
import { ManualClock, SequentialIdGenerator } from '@tgx/core-common';
import { ReducerEnv } from '@tgx/feature-template';
import {
  AuthRootPage,
  AuthUiState,
  AuthIntent,
  authReducer,
  NavigateToRoute
} from '@tgx/feature-auth';

const T = LightTheme;

@Entry
@Component
struct Index {
  @State uiState: AuthUiState = AuthUiState.initial();
  @State showChatList: boolean = false;
  @State versionResult: string = '(未运行)';

  private env: ReducerEnv = {
    clock: new ManualClock(1000, 500),
    ids: new SequentialIdGenerator('entry-')
  };

  aboutToAppear(): void {
    // TODO(SPIKE-001): bootstrap() → scope → AuthCoordinator.start()
    // 当前用 fake AuthUiState.initial() 注入，页面可独立渲染
  }

  private dispatch(intent: AuthIntent): void {
    const result = authReducer(this.uiState, intent, this.env);
    this.uiState = result.state;

    // 处理 effects（本地简化版）
    if (result.effects !== undefined && result.effects.length > 0) {
      for (let i = 0; i < result.effects.length; i++) {
        const effect = result.effects[i];
        if (effect.kind === 'navigateToRoute') {
          const nav = effect as NavigateToRoute;
          if (nav.routeName === 'chat_list') {
            this.showChatList = true;
          }
        }
        // TODO(SPIKE-001): sendPhoneNumber / checkCode / checkPassword / registerUser
        // → scope.request(...) 经 AuthCoordinator 执行
      }
    }
  }

  build() {
    Column() {
      if (this.showChatList) {
        // 占位会话列表
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
