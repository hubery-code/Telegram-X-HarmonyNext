/**
 * feature/chat — 气泡内 Telegram 链接的递出（DEEPLINK-101）。
 *
 * 会话页不认识链接语义，也不认识路由：点链接只出一条 OpenAppLink 意图，
 * coordinator 原样把 URL 交给装配层注入的回调。用例守的是这条管道：
 * 有 URL 就递，空串不递（否则装配层会拿空串去问 TDLib）。
 */

import { describe, it, expect } from '@ohos/hypium';
import { AppError, Result } from '@tgx/core-common';
import { AccountScope, AccountDirectoryLayout, buildAccountDirectories, createDescriptor } from '@tgx/core-account';
import { FakeAppFiles } from '@tgx/platform-ports';
import {
  TdNativeBridgeLike,
  TdNativeBridgeMetrics,
  TdNativeEventSink
} from '@tgx/td-gateway';
import { ChatCoordinator, ChatCoordinatorOptions } from '../main/ets/coordinator/ChatCoordinator';
import { OpenAppLink } from '../main/ets/contract/ChatIntent';

class SilentBridge implements TdNativeBridgeLike {
  version: string = '1.8.67-test';

  getVersion(): string {
    return this.version;
  }

  createClient(): number {
    return 1;
  }

  send(clientId: number, requestUtf8: string): void {
  }

  execute(requestUtf8: string): string | null {
    return '{"@type":"ok"}';
  }

  subscribeUpdates(sink: TdNativeEventSink): number {
    return 1;
  }

  unsubscribe(subscriptionId: number): void {
  }

  getMetrics(): TdNativeBridgeMetrics {
    return {
      queueSize: 0,
      overflowWaitCount: 0,
      droppedCount: 0,
      eventsForwarded: 0,
      subscriptions: 0,
      dispatcherRunning: true
    };
  }
}

function createScope(bridge: SilentBridge, name: string): AccountScope {
  const layoutRes: Result<AccountDirectoryLayout, AppError> = buildAccountDirectories(name);
  if (layoutRes.ok === false) {
    throw new Error('Failed to build directories');
  }
  const scopeRes: Result<AccountScope, AppError> = AccountScope.open({
    bridge: bridge,
    files: new FakeAppFiles(),
    descriptor: createDescriptor(name, 'acct_user_1', 0, true),
    directories: layoutRes.value,
    startActive: true
  });
  if (scopeRes.ok === false) {
    throw new Error('Failed to open AccountScope');
  }
  return scopeRes.value;
}

export default function chatAppLinkDispatchTest(): void {
  describe('ChatAppLinkDispatchTest', () => {
    it('openAppLink_forwardsUrlToAssembler', 0, () => {
      const bridge: SilentBridge = new SilentBridge();
      const scope: AccountScope = createScope(bridge, 'test_app_link');
      const urls: string[] = [];
      const options: ChatCoordinatorOptions = {
        onOpenAppLink: (url: string): void => {
          urls.push(url);
        }
      };
      const coordinator: ChatCoordinator = new ChatCoordinator(
        scope, 7001, 'link chat', undefined, undefined, undefined, options);

      coordinator.dispatch(new OpenAppLink('https://t.me/durov'));
      expect(urls.join(',')).assertEqual('https://t.me/durov');

      // 同一条链接点两次是真想再去两趟，coordinator 不做去重（去重在路由器）。
      coordinator.dispatch(new OpenAppLink('https://t.me/durov'));
      expect(urls.length).assertEqual(2);

      // 空串不递：递过去只会让装配层白花一次 TDLib 请求。
      // 空白串归路由器判空（handle 里 trim），本层不重复判、也不认识链接语义。
      coordinator.dispatch(new OpenAppLink(''));
      expect(urls.length).assertEqual(2);

      coordinator.destroy();
    });

    it('openAppLink_withoutInjection_isNoOp', 0, () => {
      // 装配层忘了接线时点链接不该崩（缺省 no-op），与其余导航回调一致。
      const bridge: SilentBridge = new SilentBridge();
      const scope: AccountScope = createScope(bridge, 'test_app_link_noop');
      const coordinator: ChatCoordinator = new ChatCoordinator(scope, 7002, 'link chat');
      coordinator.dispatch(new OpenAppLink('https://t.me/durov'));
      coordinator.destroy();
      expect(true).assertTrue();
    });
  });
}
