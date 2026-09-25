/**
 * entry/src/test/deeplink/AppLinkRouter.test.ets — 链接路由决策（DEEPLINK-101）。
 *
 * 假端口按 method 给定 @type 应答，覆盖「判别式 → 去哪」的全表：
 * 自有规则优先、非候选不进 TDLib、认得的 Telegram 链接不回落浏览器、
 * publicChat 的三种落点（会话 / 用户资料 / 会话资料）。
 */

import { describe, it, expect } from '@ohos/hypium';
import { AppError, AppErrors, ok, err, Result } from '@tgx/core-common';
import {
  AppRoute,
  ChatInfoRoute,
  ChatRoute,
  DeepLinkRule,
  UserProfileRoute
} from '@tgx/core-navigation';
import { TdWireObject, TdWireValue } from '@tgx/td-gateway';
import {
  Chat,
  ChatTypeBasicGroup,
  ChatTypePrivate,
  ChatTypeSupergroup
} from '@tgx/core-td-api-generated';
import {
  AppLinkResult,
  AppLinkRouter,
  AppLinkTdPort,
  routeForChat,
  stripAtSign
} from '../../main/ets/deeplink/AppLinkRouter';

function publicChatWire(username: string, openProfile: boolean): TdWireObject {
  const payload: TdWireObject = {};
  payload['@type'] = 'internalLinkTypePublicChat';
  payload['chat_username'] = username;
  payload['draft_text'] = '';
  payload['open_profile'] = openProfile;
  return payload;
}

function linkTypeWire(typeName: string): TdWireObject {
  const payload: TdWireObject = {};
  payload['@type'] = typeName;
  // 三种「认得但没实现」的链接各留一个字段，解码器不会因为缺字段而判成 undecodable。
  payload['invite_link'] = 'https://t.me/inv/abc';
  payload['url'] = 'https://t.me/c/1/2';
  payload['link'] = 'https://t.me/x';
  return payload;
}

function chatWire(chatId: number, type: TdWireValue): TdWireObject {
  const payload: TdWireObject = {};
  payload['@type'] = 'chat';
  payload['id'] = chatId;
  payload['type'] = type;
  payload['title'] = 'wired';
  return payload;
}

function privateTypeWire(userId: number): TdWireObject {
  const payload: TdWireObject = {};
  payload['@type'] = 'chatTypePrivate';
  payload['user_id'] = userId;
  return payload;
}

function supergroupTypeWire(isChannel: boolean): TdWireObject {
  const payload: TdWireObject = {};
  payload['@type'] = 'chatTypeSupergroup';
  payload['supergroup_id'] = 9;
  payload['is_channel'] = isChannel;
  return payload;
}

function testError(message: string): AppError {
  return AppErrors.unknown('test', message);
}

/** 按 method 回给定应答的假端口，并记录调用序列。 */
class FakeAppLinkPort implements AppLinkTdPort {
  readonly calls: string[] = [];
  /** 归一化后送进 getInternalLinkType 的链接（断言子域改写用）。 */
  readonly links: string[] = [];
  linkTypeResult: Result<TdWireObject, AppError> = err(testError('no canned link type'));
  chatResult: Result<TdWireObject, AppError> = err(testError('no canned chat'));
  gate: Promise<Result<TdWireObject, AppError>> | null = null;
  requestCount: number = 0;

  async request(method: string, params: TdWireObject): Promise<Result<TdWireObject, AppError>> {
    this.calls.push(method);
    this.requestCount++;
    if (method === 'getInternalLinkType') {
      const record: TdWireObject = params;
      const link: TdWireValue | undefined = record['link'];
      this.links.push(typeof link === 'string' ? link : '');
      if (this.gate !== null) {
        return await this.gate;
      }
      return this.linkTypeResult;
    }
    if (method === 'searchPublicChat') {
      return this.chatResult;
    }
    return err(testError(`unexpected method ${method}`));
  }

  callsOf(method: string): number {
    let count: number = 0;
    for (let i = 0; i < this.calls.length; i++) {
      if (this.calls[i] === method) {
        count++;
      }
    }
    return count;
  }
}

class NavRecorder {
  readonly routes: AppRoute[] = [];

  navigate(route: AppRoute): void {
    this.routes.push(route);
  }

  last(): AppRoute | null {
    return this.routes.length === 0 ? null : this.routes[this.routes.length - 1];
  }
}

function makeRouter(port: AppLinkTdPort, nav: NavRecorder, ready: boolean = true): AppLinkRouter {
  return new AppLinkRouter(port, {
    navigate: (route: AppRoute): void => {
      nav.navigate(route);
    },
    isReady: (): boolean => ready
  });
}

/** 空规则表：把「自有规则」与「TDLib 解析」两条路径隔开测。 */
function rules_none(): DeepLinkRule[] {
  return [];
}

export default function appLinkRouterTest() {
  describe('AppLinkRouterTest', () => {
    it('empty_and_not_ready_short_circuit', 0, async (): Promise<void> => {
      const port: FakeAppLinkPort = new FakeAppLinkPort();
      const nav: NavRecorder = new NavRecorder();
      const blank: AppLinkResult = await makeRouter(port, nav).handle('   ');
      expect(blank.outcome).assertEqual('empty');

      const locked: AppLinkResult = await makeRouter(port, nav, false).handle('https://t.me/durov');
      expect(locked.outcome).assertEqual('not_ready');
      expect(locked.reason).assertEqual('account_not_ready');
      // 两种情况都不该导航，也不该花 IPC。
      expect(nav.routes.length).assertEqual(0);
      expect(port.calls.length).assertEqual(0);
    });

    it('nonCandidate_neverReachesTdlib', 0, async (): Promise<void> => {
      const port: FakeAppLinkPort = new FakeAppLinkPort();
      const nav: NavRecorder = new NavRecorder();
      const res: AppLinkResult = await makeRouter(port, nav).handle('https://example.com/a');
      expect(res.outcome).assertEqual('external');
      expect(res.reason).assertEqual('not_telegram_link');
      expect(port.calls.length).assertEqual(0);
      expect(nav.routes.length).assertEqual(0);
    });

    it('internalRuleWinsBeforeTdlib', 0, async (): Promise<void> => {
      // 钉住 ADR-005 的既有契约：自有 tg:// 规则优先，不花一次 IPC。
      const port: FakeAppLinkPort = new FakeAppLinkPort();
      const nav: NavRecorder = new NavRecorder();
      const res: AppLinkResult = await makeRouter(port, nav).handle('tg://chat?chatId=42');
      expect(res.outcome).assertEqual('internal_route');
      expect(port.calls.length).assertEqual(0);
      const route: AppRoute | null = nav.last();
      expect(route !== null && route.name === 'chat').assertTrue();
      expect((route as ChatRoute).chatId).assertEqual(42);
    });

    it('tMeChatIdRule_swallowsUsernameChat', 0, async (): Promise<void> => {
      // 已知副作用：用户名字面上叫 `chat` 且第二段是数字时被自有规则吃掉，明确记账。
      const port: FakeAppLinkPort = new FakeAppLinkPort();
      const nav: NavRecorder = new NavRecorder();
      const res: AppLinkResult = await makeRouter(port, nav).handle('https://t.me/chat/7');
      expect(res.outcome).assertEqual('internal_route');
      expect(port.callsOf('getInternalLinkType')).assertEqual(0);
    });

    it('publicChat_routesToChat_andAsksTdlibOnceEach', 0, async (): Promise<void> => {
      const port: FakeAppLinkPort = new FakeAppLinkPort();
      port.linkTypeResult = ok(publicChatWire('durov', false));
      port.chatResult = ok(chatWire(101, privateTypeWire(5)));
      const nav: NavRecorder = new NavRecorder();
      const res: AppLinkResult = await makeRouter(port, nav).handle('https://t.me/durov');
      expect(res.outcome).assertEqual('routed');
      expect(res.chatId).assertEqual(101);
      expect(res.linkType).assertEqual('internalLinkTypePublicChat');
      const route: AppRoute | null = nav.last();
      expect(route !== null && route.name === 'chat').assertTrue();
      expect(port.calls.join(',')).assertEqual('getInternalLinkType,searchPublicChat');
    });

    it('publicChat_normalizesSubdomainBeforeTdlib', 0, async (): Promise<void> => {
      const port: FakeAppLinkPort = new FakeAppLinkPort();
      port.linkTypeResult = ok(publicChatWire('durov', false));
      port.chatResult = ok(chatWire(102, privateTypeWire(5)));
      const nav: NavRecorder = new NavRecorder();
      const res: AppLinkResult = await makeRouter(port, nav).handle('https://durov.t.me/1');
      expect(res.outcome).assertEqual('routed');
      // 送进 TDLib 的必须是改写后的形式，否则只会得到 unknownDeepLink。
      expect(port.links[0]).assertEqual('https://t.me/durov/1');
    });

    it('publicChat_openProfile_landsOnChatInfoForSupergroup', 0, async (): Promise<void> => {
      const port: FakeAppLinkPort = new FakeAppLinkPort();
      port.linkTypeResult = ok(publicChatWire('durov', true));
      port.chatResult = ok(chatWire(-1009, supergroupTypeWire(true)));
      const nav: NavRecorder = new NavRecorder();
      const res: AppLinkResult = await makeRouter(port, nav).handle('https://t.me/durov');
      expect(res.outcome).assertEqual('routed');
      const route: AppRoute | null = nav.last();
      expect(route !== null && route.name === 'chatInfo').assertTrue();
      expect((route as ChatInfoRoute).chatId).assertEqual(-1009);
    });

    it('routeForChat_mapsByOpenProfileAndChatType', 0, () => {
      const privType: ChatTypePrivate = new ChatTypePrivate();
      privType.user_id = 900;
      const priv: Chat = new Chat();
      priv.id = 7;
      priv.type_ = privType;
      // 私聊资料页要的是 user_id，不是 chatId（密聊两者不相等）。
      const privProfile: AppRoute = routeForChat(priv, true);
      expect(privProfile.name).assertEqual('userProfile');
      expect((privProfile as UserProfileRoute).userId).assertEqual(900);
      expect(routeForChat(priv, false).name).assertEqual('chat');

      const superType: ChatTypeSupergroup = new ChatTypeSupergroup();
      superType.is_channel = true;
      const super1: Chat = new Chat();
      super1.id = -1003;
      super1.type_ = superType;
      expect(routeForChat(super1, true).name).assertEqual('chatInfo');

      const basic: Chat = new Chat();
      basic.id = -2004;
      basic.type_ = new ChatTypeBasicGroup();
      expect(routeForChat(basic, true).name).assertEqual('chatInfo');
      // open_profile 为假时一律落会话，不看类型。
      expect(routeForChat(basic, false).name).assertEqual('chat');

      // type_ 为 null（老数据/未解码字段）时不猜，落会话。
      const unknown: Chat = new Chat();
      unknown.id = 55;
      unknown.type_ = null;
      expect(routeForChat(unknown, true).name).assertEqual('chat');
    });

    it('unknownDeepLink_isTheOnlyBrowserFallback', 0, async (): Promise<void> => {
      const port: FakeAppLinkPort = new FakeAppLinkPort();
      port.linkTypeResult = ok(linkTypeWire('internalLinkTypeUnknownDeepLink'));
      const nav: NavRecorder = new NavRecorder();
      const res: AppLinkResult = await makeRouter(port, nav).handle('https://t.me/somepage');
      expect(res.outcome).assertEqual('external');
      expect(res.linkType).assertEqual('internalLinkTypeUnknownDeepLink');
      expect(nav.routes.length).assertEqual(0);
    });

    it('recognizedButUnimplemented_neverEscapesToBrowser', 0, async (): Promise<void> => {
      const cases: string[] = ['internalLinkTypeChatInvite', 'internalLinkTypeProxy', 'internalLinkTypeMessage'];
      for (let i = 0; i < cases.length; i++) {
        const port: FakeAppLinkPort = new FakeAppLinkPort();
        port.linkTypeResult = ok(linkTypeWire(cases[i]));
        const nav: NavRecorder = new NavRecorder();
        const res: AppLinkResult = await makeRouter(port, nav).handle('https://t.me/anything');
        // 这些确实是 Telegram 链接，丢进浏览器只会得到登录墙 —— 必须由上层提示。
        expect(res.outcome).assertEqual('unsupported');
        expect(res.linkType).assertEqual(cases[i]);
        expect(res.reason).assertEqual(cases[i]);
        expect(nav.routes.length).assertEqual(0);
      }
    });

    it('tdlibError_and_foreignShape_failClosedWithoutNavigation', 0, async (): Promise<void> => {
      const port: FakeAppLinkPort = new FakeAppLinkPort();
      const nav: NavRecorder = new NavRecorder();
      port.linkTypeResult = err(testError('404 not found'));
      const failed: AppLinkResult = await makeRouter(port, nav).handle('https://t.me/durov');
      expect(failed.outcome).assertEqual('failed');
      expect(failed.reason).assertEqual('link_type_error');

      // @type 不是 InternalLinkType 家族成员（TDLib 比生成码新）：判别式原样透传，
      // 按「认得但没实现」处理 —— 提示，不外溢浏览器。
      port.linkTypeResult = ok(chatWire(1, privateTypeWire(2)));
      const foreign: AppLinkResult = await makeRouter(port, nav).handle('https://t.me/durov');
      expect(foreign.outcome).assertEqual('unsupported');
      expect(foreign.reason).assertEqual('chat');
      expect(nav.routes.length).assertEqual(0);
    });

    it('searchPublicChatFailure_doesNotGuessChatId', 0, async (): Promise<void> => {
      const port: FakeAppLinkPort = new FakeAppLinkPort();
      port.linkTypeResult = ok(publicChatWire('durov', false));
      port.chatResult = err(testError('chatNotPublic'));
      const nav: NavRecorder = new NavRecorder();
      const res: AppLinkResult = await makeRouter(port, nav).handle('https://t.me/durov');
      expect(res.outcome).assertEqual('failed');
      expect(res.reason).assertEqual('chat_unresolved');
      expect(nav.routes.length).assertEqual(0);
    });

    it('emptyUsername_failsBeforeSearchPublicChat', 0, async (): Promise<void> => {
      const port: FakeAppLinkPort = new FakeAppLinkPort();
      port.linkTypeResult = ok(publicChatWire('   ', false));
      const nav: NavRecorder = new NavRecorder();
      const res: AppLinkResult = await makeRouter(port, nav).handle('https://t.me/x');
      expect(res.outcome).assertEqual('failed');
      expect(res.reason).assertEqual('empty_username');
      expect(port.callsOf('searchPublicChat')).assertEqual(0);
    });

    it('username_leadingAtIsStripped', 0, () => {
      expect(stripAtSign('@durov')).assertEqual('durov');
      expect(stripAtSign(' durov ')).assertEqual('durov');
      expect(stripAtSign('')).assertEqual('');
      // 只剥一层，不裁剪正文。
      expect(stripAtSign('@@durov')).assertEqual('@durov');
    });

    it('sameLinkTwiceWhileInFlight_isDeduped', 0, async (): Promise<void> => {
      // 同一条链接并发的两次（重复 want / 连点）只问 TDLib 一次。
      let release: (value: Result<TdWireObject, AppError>) => void = () => {};
      const gate: Promise<Result<TdWireObject, AppError>> = new Promise(
        (resolve: (value: Result<TdWireObject, AppError>) => void): void => {
          release = resolve;
        }
      );
      const port: FakeAppLinkPort = new FakeAppLinkPort();
      port.gate = gate;
      const nav: NavRecorder = new NavRecorder();
      const router: AppLinkRouter = makeRouter(port, nav);
      const first: Promise<AppLinkResult> = router.handle('https://t.me/durov');
      const second: AppLinkResult = await router.handle('https://t.me/durov');
      expect(second.outcome).assertEqual('in_flight');
      expect(port.callsOf('getInternalLinkType')).assertEqual(1);
      expect(router.isBusy()).assertTrue();
      port.gate = null;
      port.linkTypeResult = ok(publicChatWire('durov', false));
      port.chatResult = ok(chatWire(201, privateTypeWire(5)));
      release(ok(publicChatWire('durov', false)));
      const res: AppLinkResult = await first;
      expect(res.outcome).assertEqual('routed');
      expect(router.isBusy()).assertFalse();
      // 在途结束后同一条链接可以再走一趟。
      const third: AppLinkResult = await router.handle('https://t.me/durov');
      expect(third.outcome).assertEqual('routed');
    });

    it('customRules_replacesDefaultTable', 0, async (): Promise<void> => {
      // rules 可注入：给定空表时，`tg://chat` 也不再走内部规则，而是当候选链接去问 TDLib。
      const port: FakeAppLinkPort = new FakeAppLinkPort();
      port.linkTypeResult = ok(linkTypeWire('internalLinkTypeUnknownDeepLink'));
      const nav: NavRecorder = new NavRecorder();
      const router: AppLinkRouter = new AppLinkRouter(port, {
        navigate: (route: AppRoute): void => {
          nav.navigate(route);
        },
        rules: rules_none()
      });
      const res: AppLinkResult = await router.handle('tg://chat?chatId=42');
      expect(res.outcome).assertEqual('external');
      expect(port.callsOf('getInternalLinkType')).assertEqual(1);
    });
  });
}
