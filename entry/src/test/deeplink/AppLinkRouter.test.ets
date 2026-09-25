/**
 * entry/src/test/deeplink/AppLinkRouter.test.ets — 链接路由决策（DEEPLINK-101）。
 *
 * 假端口按 method 给定 @type 应答，覆盖「判别式 → 去哪」的全表：
 * 自有规则优先、非候选不进 TDLib、认得的 Telegram 链接不回落浏览器、
 * publicChat 的三种落点（会话 / 用户资料 / 会话资料）。
 */

import { describe, it, expect } from '@ohos/hypium';
import { AppError, AppErrors, ok, err, Result } from '@tgx/core-common';
import { Logger, LogLevel } from '@tgx/observability';
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
  ChatInviteLinkInfo,
  ChatTypeBasicGroup,
  ChatTypePrivate,
  ChatTypeSupergroup,
  ProxyValue,
  TdJsonRaw,
  decodeChatInviteLinkInfo,
  decodeProxyValue
} from '@tgx/core-td-api-generated';
import {
  AppLinkResult,
  AppLinkRouter,
  AppLinkTdPort,
  invitePromptOf,
  proxyPromptOf,
  routeForChat,
  stripAtSign
} from '../../main/ets/deeplink/AppLinkRouter';
import {
  AppLinkPromptPort,
  InvitePromptData,
  ProxyPromptChoice,
  ProxyPromptData
} from '../../main/ets/deeplink/AppLinkPrompt';

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

/** TDLib 写请求的空应答（`Ok` 对象）。 */
function okWire(): TdWireObject {
  const payload: TdWireObject = {};
  payload['@type'] = 'ok';
  return payload;
}

function chatWire(chatId: number, type: TdWireValue): TdWireObject {  const payload: TdWireObject = {};
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

/** `chatInviteLinkInfo`：`chatId` 为 0 表示「本地还没有这个会话」，也就是要问用户。 */
function inviteInfoWire(
  chatId: number,
  memberCount: number,
  isChannel: boolean,
  createsJoinRequest: boolean
): TdWireObject {
  const type: TdWireObject = {};
  type['@type'] = isChannel ? 'inviteLinkChatTypeChannel' : 'inviteLinkChatTypeBasicGroup';
  const payload: TdWireObject = {};
  payload['@type'] = 'chatInviteLinkInfo';
  payload['chat_id'] = chatId;
  payload['type'] = type;
  payload['title'] = 'Qoder Test Group';
  payload['description'] = 'for link routing test';
  payload['member_count'] = memberCount;
  payload['creates_join_request'] = createsJoinRequest;
  payload['is_public'] = false;
  return payload;
}

function joinResultWire(typeName: string, chatId: number): TdWireObject {
  const payload: TdWireObject = {};
  payload['@type'] = typeName;
  payload['chat_id'] = chatId;
  return payload;
}

/** `internalLinkTypeProxy`；`server` 传空串即模拟 TDLib 回「不支持的代理类型」。 */
function proxyLinkWire(server: string, port: number, typeName: string): TdWireObject {
  const payload: TdWireObject = {};
  payload['@type'] = 'internalLinkTypeProxy';
  if (server.length > 0) {
    const proxyType: TdWireObject = {};
    proxyType['@type'] = typeName;
    const proxy: TdWireObject = {};
    proxy['@type'] = 'proxy';
    proxy['server'] = server;
    proxy['port'] = port;
    proxy['type'] = proxyType;
    payload['proxy'] = proxy;
  }
  return payload;
}

function messageLinkWire(chatId: number, messageId: number): TdWireObject {
  const payload: TdWireObject = {};
  payload['@type'] = 'messageLinkInfo';
  payload['is_public'] = true;
  payload['chat_id'] = chatId;
  if (messageId > 0) {
    const message: TdWireObject = {};
    message['@type'] = 'message';
    message['id'] = messageId;
    message['chat_id'] = chatId;
    payload['message'] = message;
  }
  return payload;
}

function botStartWire(botUsername: string, parameter: string, autostart: boolean): TdWireObject {
  const payload: TdWireObject = {};
  payload['@type'] = 'internalLinkTypeBotStart';
  payload['bot_username'] = botUsername;
  payload['start_parameter'] = parameter;
  payload['autostart'] = autostart;
  return payload;
}

function userWire(userId: number, isBot: boolean): TdWireObject {
  const type: TdWireObject = {};
  type['@type'] = isBot ? 'userTypeBot' : 'userTypeRegular';
  const payload: TdWireObject = {};
  payload['@type'] = 'user';
  payload['id'] = userId;
  payload['first_name'] = isBot ? 'TestBot' : 'Test';
  payload['type'] = type;
  return payload;
}

function wireString(params: TdWireObject, key: string): string {
  const record: TdWireObject = params;
  const value: TdWireValue | undefined = record[key];
  return typeof value === 'string' ? value : '';
}

function wireNumber(params: TdWireObject, key: string): number {
  const record: TdWireObject = params;
  const value: TdWireValue | undefined = record[key];
  return typeof value === 'number' ? value : 0;
}

function wireBool(params: TdWireObject, key: string): boolean {
  const record: TdWireObject = params;
  const value: TdWireValue | undefined = record[key];
  return value === true;
}

function testError(message: string): AppError {
  return AppErrors.unknown('test', message);
}

/** 按 method 回给定应答的假端口，并记录调用序列与各次入参。 */
class FakeAppLinkPort implements AppLinkTdPort {
  readonly calls: string[] = [];
  /** 归一化后送进 getInternalLinkType 的链接（断言子域改写用）。 */
  readonly links: string[] = [];
  /** 每次请求的入参，与 calls 同序 —— 断言 `addProxy.enable` 这类写语义。 */
  readonly sentParams: TdWireObject[] = [];
  linkTypeResult: Result<TdWireObject, AppError> = err(testError('no canned link type'));
  chatResult: Result<TdWireObject, AppError> = err(testError('no canned chat'));
  inviteResult: Result<TdWireObject, AppError> = err(testError('no canned invite info'));
  joinResult: Result<TdWireObject, AppError> = err(testError('no canned join result'));
  messageLinkResult: Result<TdWireObject, AppError> = err(testError('no canned message link'));
  proxyWriteResult: Result<TdWireObject, AppError> = ok(okWire());
  userResult: Result<TdWireObject, AppError> = err(testError('no canned user'));
  gate: Promise<Result<TdWireObject, AppError>> | null = null;
  requestCount: number = 0;

  async request(method: string, params: TdWireObject): Promise<Result<TdWireObject, AppError>> {
    this.calls.push(method);
    this.sentParams.push(params);
    this.requestCount++;
    if (method === 'getInternalLinkType') {
      const link: TdWireValue | undefined = params['link'];
      this.links.push(typeof link === 'string' ? link : '');
      if (this.gate !== null) {
        return await this.gate;
      }
      return this.linkTypeResult;
    }
    if (method === 'searchPublicChat') {
      return this.chatResult;
    }
    if (method === 'checkChatInviteLink') {
      return this.inviteResult;
    }
    if (method === 'joinChatByInviteLink') {
      return this.joinResult;
    }
    if (method === 'getMessageLinkInfo') {
      return this.messageLinkResult;
    }
    if (method === 'getUser') {
      return this.userResult;
    }
    if (method === 'addProxy') {
      // TDLib 的 addProxy 回 `ok`；这里只关心「有没有发出去、enable 是什么」。
      return this.proxyWriteResult;
    }
    return err(testError(`unexpected method ${method}`));
  }

  /** 某次请求的入参（按 method 的第 n 次调用取）。 */
  paramsOf(method: string, occurrence: number = 0): TdWireObject {
    let seen: number = 0;
    for (let i = 0; i < this.calls.length; i++) {
      if (this.calls[i] === method) {
        if (seen === occurrence) {
          return this.sentParams[i];
        }
        seen++;
      }
    }
    const empty: TdWireObject = {};
    return empty;
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

/** 记录「弹窗问了什么、用户答了什么」的假端口。 */
class PromptRecorder {
  readonly invites: InvitePromptData[] = [];
  readonly proxies: ProxyPromptData[] = [];
  inviteAnswer: boolean = false;
  proxyAnswer: ProxyPromptChoice = 'cancel';

  asPort(): AppLinkPromptPort {
    return {
      confirmInvite: (data: InvitePromptData): Promise<boolean> => {
        this.invites.push(data);
        return Promise.resolve(this.inviteAnswer);
      },
      chooseProxy: (data: ProxyPromptData): Promise<ProxyPromptChoice> => {
        this.proxies.push(data);
        return Promise.resolve(this.proxyAnswer);
      }
    };
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

function makeRouter(
  port: AppLinkTdPort,
  nav: NavRecorder,
  ready: boolean = true,
  prompt: AppLinkPromptPort | null = null
): AppLinkRouter {
  if (prompt === null) {
    // 不传 prompt：测「装配忘了接弹窗」时的缺省行为（一律拒绝）。
    return new AppLinkRouter(port, {
      navigate: (route: AppRoute): void => {
        nav.navigate(route);
      },
      isReady: (): boolean => ready
    });
  }
  return new AppLinkRouter(port, {
    navigate: (route: AppRoute): void => {
      nav.navigate(route);
    },
    isReady: (): boolean => ready,
    prompt: prompt
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
      // DEEPLINK-102 之后仍没实现的类型（邀请/代理/消息/bot 都已经接上了）。
      const cases: string[] = ['internalLinkTypeStickerSet', 'internalLinkTypeLanguagePack', 'internalLinkTypeGroupCall'];
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

    // ---------- DEEPLINK-102：邀请 ----------

    it('invite_alreadyInChat_routesWithoutAsking', 0, async (): Promise<void> => {
      // chat_id 非 0 = 本地已有该会话（已是成员），直接进，不打扰用户（Android 同口径）。
      const port: FakeAppLinkPort = new FakeAppLinkPort();
      port.linkTypeResult = ok(linkTypeWire('internalLinkTypeChatInvite'));
      port.inviteResult = ok(inviteInfoWire(-10077, 12, true, false));
      const prompt: PromptRecorder = new PromptRecorder();
      prompt.inviteAnswer = false;
      const nav: NavRecorder = new NavRecorder();
      const res: AppLinkResult = await makeRouter(port, nav, true, prompt.asPort())
        .handle('https://t.me/+abcHash');
      expect(res.outcome).assertEqual('routed');
      expect(res.chatId).assertEqual(-10077);
      expect(prompt.invites.length).assertEqual(0);
      expect(port.calls.join(',')).assertEqual('getInternalLinkType,checkChatInviteLink');
      const route: AppRoute | null = nav.last();
      expect(route !== null && route.name === 'chat').assertTrue();
      expect((route as ChatRoute).chatId).assertEqual(-10077);
    });

    it('invite_accepted_joinsAndRoutes', 0, async (): Promise<void> => {
      const port: FakeAppLinkPort = new FakeAppLinkPort();
      port.linkTypeResult = ok(linkTypeWire('internalLinkTypeChatInvite'));
      port.inviteResult = ok(inviteInfoWire(0, 12, false, false));
      port.joinResult = ok(joinResultWire('chatJoinResultSuccess', -2055));
      const prompt: PromptRecorder = new PromptRecorder();
      prompt.inviteAnswer = true;
      const nav: NavRecorder = new NavRecorder();
      const res: AppLinkResult = await makeRouter(port, nav, true, prompt.asPort())
        .handle('https://t.me/+abcHash');
      expect(res.outcome).assertEqual('routed');
      expect(res.chatId).assertEqual(-2055);
      expect(prompt.invites.length).assertEqual(1);
      expect(port.calls.join(',')).assertEqual('getInternalLinkType,checkChatInviteLink,joinChatByInviteLink');
      // join 用的是 TDLib 给的 invite_link，而不是用户点开的原始串。
      expect(wireString(port.paramsOf('joinChatByInviteLink'), 'invite_link'))
        .assertEqual('https://t.me/inv/abc');
    });

    it('invite_declined_writesNothing', 0, async (): Promise<void> => {
      const port: FakeAppLinkPort = new FakeAppLinkPort();
      port.linkTypeResult = ok(linkTypeWire('internalLinkTypeChatInvite'));
      port.inviteResult = ok(inviteInfoWire(0, 12, false, false));
      const prompt: PromptRecorder = new PromptRecorder();
      prompt.inviteAnswer = false;
      const nav: NavRecorder = new NavRecorder();
      const res: AppLinkResult = await makeRouter(port, nav, true, prompt.asPort())
        .handle('https://t.me/+abcHash');
      expect(res.outcome).assertEqual('cancelled');
      expect(res.reason).assertEqual('invite_declined');
      expect(port.callsOf('joinChatByInviteLink')).assertEqual(0);
      expect(nav.routes.length).assertEqual(0);
    });

    it('invite_withoutPromptPort_declinesByDefault', 0, async (): Promise<void> => {
      // 缺省端口必须「拒绝」：装配漏接弹窗的最坏结果是链接点了没反应，而不是替用户加入会话。
      const port: FakeAppLinkPort = new FakeAppLinkPort();
      port.linkTypeResult = ok(linkTypeWire('internalLinkTypeChatInvite'));
      port.inviteResult = ok(inviteInfoWire(0, 12, false, false));
      const nav: NavRecorder = new NavRecorder();
      const res: AppLinkResult = await makeRouter(port, nav).handle('https://t.me/+abcHash');
      expect(res.outcome).assertEqual('cancelled');
      expect(port.callsOf('joinChatByInviteLink')).assertEqual(0);
      expect(nav.routes.length).assertEqual(0);
    });

    it('invite_createsJoinRequest_notifiesWithoutNavigation', 0, async (): Promise<void> => {
      const port: FakeAppLinkPort = new FakeAppLinkPort();
      port.linkTypeResult = ok(linkTypeWire('internalLinkTypeChatInvite'));
      port.inviteResult = ok(inviteInfoWire(0, 0, true, true));
      port.joinResult = ok(joinResultWire('chatJoinResultRequestSent', 0));
      const prompt: PromptRecorder = new PromptRecorder();
      prompt.inviteAnswer = true;
      const nav: NavRecorder = new NavRecorder();
      const res: AppLinkResult = await makeRouter(port, nav, true, prompt.asPort())
        .handle('https://t.me/+abcHash');
      // 申请制链接批准前进不了会话：没有页面可去，只能提示一句。
      expect(res.outcome).assertEqual('notified');
      expect(res.reason).assertEqual('join_request_sent');
      expect(nav.routes.length).assertEqual(0);
      // creates_join_request 的链接，按钮文案是「申请加入」而不是「加入」。
      expect(prompt.invites[0].createsJoinRequest).assertTrue();
    });

    it('invite_checkFailure_failsClosed', 0, async (): Promise<void> => {
      const port: FakeAppLinkPort = new FakeAppLinkPort();
      port.linkTypeResult = ok(linkTypeWire('internalLinkTypeChatInvite'));
      port.inviteResult = err(testError('INVITE_LINK_REVOKED'));
      const prompt: PromptRecorder = new PromptRecorder();
      prompt.inviteAnswer = true;
      const nav: NavRecorder = new NavRecorder();
      const res: AppLinkResult = await makeRouter(port, nav, true, prompt.asPort())
        .handle('https://t.me/+abcHash');
      expect(res.outcome).assertEqual('failed');
      expect(res.reason).assertEqual('invite_check_failed');
      // 校验都没过，弹窗根本不该出现。
      expect(prompt.invites.length).assertEqual(0);
      expect(port.callsOf('joinChatByInviteLink')).assertEqual(0);
    });

    it('invitePromptOf_keepsOnlyDisplayableScalars', 0, () => {
      const info = decodeChatInviteLinkInfo(inviteInfoWire(0, 1234, true, false) as TdJsonRaw);
      expect(info !== null).assertTrue();
      const data: InvitePromptData = invitePromptOf(info as ChatInviteLinkInfo);
      expect(data.title).assertEqual('Qoder Test Group');
      expect(data.memberCount).assertEqual(1234);
      expect(data.isChannel).assertTrue();
      expect(data.createsJoinRequest).assertFalse();
      // 视图模型里没有哈希的位置：InvitePromptData 只有这四个字段。
      expect(data.description).assertEqual('for link routing test');
    });

    // ---------- DEEPLINK-102：代理 ----------

    it('proxy_enable_sendsOneAddProxyWithEnableTrue', 0, async (): Promise<void> => {
      const port: FakeAppLinkPort = new FakeAppLinkPort();
      port.linkTypeResult = ok(proxyLinkWire('1.2.3.4', 8443, 'proxyTypeSocks5'));
      const prompt: PromptRecorder = new PromptRecorder();
      prompt.proxyAnswer = 'enable';
      const nav: NavRecorder = new NavRecorder();
      const res: AppLinkResult = await makeRouter(port, nav, true, prompt.asPort())
        .handle('https://t.me/proxy?server=1.2.3.4&port=8443');
      expect(res.outcome).assertEqual('notified');
      expect(res.reason).assertEqual('proxy_enabled');
      expect(port.calls.join(',')).assertEqual('getInternalLinkType,addProxy');
      expect(wireBool(port.paramsOf('addProxy'), 'enable')).assertTrue();
      // 代理是账号级动作，不压栈。
      expect(nav.routes.length).assertEqual(0);
    });

    it('proxy_save_sendsSameAddProxyWithEnableFalse', 0, async (): Promise<void> => {
      // 「稍后使用」与「启用」是同一条 addProxy，只差 enable —— 也不许补一次 enableProxy。
      const port: FakeAppLinkPort = new FakeAppLinkPort();
      port.linkTypeResult = ok(proxyLinkWire('1.2.3.4', 8443, 'proxyTypeSocks5'));
      const prompt: PromptRecorder = new PromptRecorder();
      prompt.proxyAnswer = 'save';
      const nav: NavRecorder = new NavRecorder();
      const res: AppLinkResult = await makeRouter(port, nav, true, prompt.asPort())
        .handle('https://t.me/proxy?server=1.2.3.4&port=8443');
      expect(res.outcome).assertEqual('notified');
      expect(res.reason).assertEqual('proxy_saved');
      expect(port.callsOf('addProxy')).assertEqual(1);
      expect(port.callsOf('enableProxy')).assertEqual(0);
      expect(wireBool(port.paramsOf('addProxy'), 'enable')).assertFalse();
      expect(nav.routes.length).assertEqual(0);
    });

    it('proxy_cancel_writesNothing', 0, async (): Promise<void> => {
      const port: FakeAppLinkPort = new FakeAppLinkPort();
      port.linkTypeResult = ok(proxyLinkWire('1.2.3.4', 8443, 'proxyTypeSocks5'));
      const prompt: PromptRecorder = new PromptRecorder();
      prompt.proxyAnswer = 'cancel';
      const nav: NavRecorder = new NavRecorder();
      const res: AppLinkResult = await makeRouter(port, nav, true, prompt.asPort())
        .handle('https://t.me/proxy?server=1.2.3.4&port=8443');
      expect(res.outcome).assertEqual('cancelled');
      expect(res.reason).assertEqual('proxy_declined');
      expect(port.callsOf('addProxy')).assertEqual(0);
    });

    it('proxy_withoutPromptPort_writesNothing', 0, async (): Promise<void> => {
      const port: FakeAppLinkPort = new FakeAppLinkPort();
      port.linkTypeResult = ok(proxyLinkWire('1.2.3.4', 8443, 'proxyTypeSocks5'));
      const nav: NavRecorder = new NavRecorder();
      const res: AppLinkResult = await makeRouter(port, nav)
        .handle('https://t.me/proxy?server=1.2.3.4&port=8443');
      expect(res.outcome).assertEqual('cancelled');
      expect(port.callsOf('addProxy')).assertEqual(0);
    });

    it('proxy_unsupportedType_reportsUnsupportedAndNeverAsks', 0, async (): Promise<void> => {
      // TDLib 回 proxy:null 表示这个代理类型不支持（Android 的 ProxyLinkUnsupported）。
      const port: FakeAppLinkPort = new FakeAppLinkPort();
      port.linkTypeResult = ok(proxyLinkWire('', 0, 'proxyTypeSocks5'));
      const prompt: PromptRecorder = new PromptRecorder();
      prompt.proxyAnswer = 'enable';
      const nav: NavRecorder = new NavRecorder();
      const res: AppLinkResult = await makeRouter(port, nav, true, prompt.asPort())
        .handle('https://t.me/proxy?server=1.2.3.4&port=8443');
      expect(res.outcome).assertEqual('unsupported');
      expect(res.reason).assertEqual('proxy_unsupported');
      expect(prompt.proxies.length).assertEqual(0);
      expect(port.callsOf('addProxy')).assertEqual(0);
    });

    it('proxyPromptOf_stripsProxyTypePrefix', 0, () => {
      const wired: TdWireObject = {};
      wired['@type'] = 'proxy';
      wired['server'] = 'proxy.example.com';
      wired['port'] = 8443;
      const proxyType: TdWireObject = {};
      proxyType['@type'] = 'proxyTypeMtproto';
      wired['type'] = proxyType;
      const proxy = decodeProxyValue(wired as TdJsonRaw);
      expect(proxy !== null).assertTrue();
      const data: ProxyPromptData = proxyPromptOf(proxy as ProxyValue);
      expect(data.server).assertEqual('proxy.example.com');
      expect(data.port).assertEqual(8443);
      expect(data.kind).assertEqual('mtproto');
    });

    // ---------- DEEPLINK-102：消息深链 ----------

    it('message_link_routesWithTargetMessage', 0, async (): Promise<void> => {
      const port: FakeAppLinkPort = new FakeAppLinkPort();
      port.linkTypeResult = ok(linkTypeWire('internalLinkTypeMessage'));
      port.messageLinkResult = ok(messageLinkWire(-10042, 777));
      const nav: NavRecorder = new NavRecorder();
      const res: AppLinkResult = await makeRouter(port, nav).handle('https://t.me/durov/777');
      expect(res.outcome).assertEqual('routed');
      expect(res.chatId).assertEqual(-10042);
      const route: AppRoute | null = nav.last();
      expect(route !== null && route.name === 'chat').assertTrue();
      // messageId 复用 SEARCH-102 的字段：会话页已经会滚动定位并高亮。
      expect((route as ChatRoute).messageId).assertEqual(777);
    });

    it('message_link_withoutMessage_routesChatOnly', 0, async (): Promise<void> => {
      const port: FakeAppLinkPort = new FakeAppLinkPort();
      port.linkTypeResult = ok(linkTypeWire('internalLinkTypeMessage'));
      port.messageLinkResult = ok(messageLinkWire(-10042, 0));
      const nav: NavRecorder = new NavRecorder();
      const res: AppLinkResult = await makeRouter(port, nav).handle('https://t.me/durov/777');
      expect(res.outcome).assertEqual('routed');
      const route: AppRoute | null = nav.last();
      expect((route as ChatRoute).messageId === undefined).assertTrue();
    });

    it('message_link_unresolvedChat_failsWithoutGuessing', 0, async (): Promise<void> => {
      const port: FakeAppLinkPort = new FakeAppLinkPort();
      port.linkTypeResult = ok(linkTypeWire('internalLinkTypeMessage'));
      port.messageLinkResult = ok(messageLinkWire(0, 0));
      const nav: NavRecorder = new NavRecorder();
      const res: AppLinkResult = await makeRouter(port, nav).handle('https://t.me/durov/777');
      expect(res.outcome).assertEqual('failed');
      expect(res.reason).assertEqual('message_link_unresolved');
      expect(nav.routes.length).assertEqual(0);
    });

    // ---------- DEEPLINK-102：bot 启动 ----------

    it('botStart_rejectsNonBotUsername', 0, async (): Promise<void> => {
      // 一个冒充 bot 的用户名不该把普通用户拉进会话，更不该替他发出 start 消息。
      const port: FakeAppLinkPort = new FakeAppLinkPort();
      port.linkTypeResult = ok(botStartWire('SomePerson', 'deepvalue', true));
      port.chatResult = ok(chatWire(301, privateTypeWire(77)));
      port.userResult = ok(userWire(77, false));
      const nav: NavRecorder = new NavRecorder();
      const res: AppLinkResult = await makeRouter(port, nav).handle('https://t.me/SomePerson?start=deepvalue');
      expect(res.outcome).assertEqual('failed');
      expect(res.reason).assertEqual('bot_not_found');
      expect(nav.routes.length).assertEqual(0);
      expect(port.callsOf('sendBotStartMessage')).assertEqual(0);
    });

    it('botStart_verifiedBot_routesAndSendsParameter', 0, async (): Promise<void> => {
      const port: FakeAppLinkPort = new FakeAppLinkPort();
      port.linkTypeResult = ok(botStartWire('TestBot', 'deepvalue', true));
      port.chatResult = ok(chatWire(302, privateTypeWire(78)));
      port.userResult = ok(userWire(78, true));
      const nav: NavRecorder = new NavRecorder();
      const res: AppLinkResult = await makeRouter(port, nav).handle('https://t.me/TestBot?start=deepvalue');
      expect(res.outcome).assertEqual('routed');
      expect(res.chatId).assertEqual(302);
      expect(port.calls.join(',')).assertEqual(
        'getInternalLinkType,searchPublicChat,getUser,sendBotStartMessage'
      );
      const sent: TdWireObject = port.paramsOf('sendBotStartMessage');
      expect(wireNumber(sent, 'bot_user_id')).assertEqual(78);
      expect(wireNumber(sent, 'chat_id')).assertEqual(302);
      expect(wireString(sent, 'parameter')).assertEqual('deepvalue');
    });

    it('botStart_withoutStartParameter_neverSends', 0, async (): Promise<void> => {
      // start_parameter 为空时发出去的是「/start」——TDLib 没让 autostart，就不该有这条消息。
      const port: FakeAppLinkPort = new FakeAppLinkPort();
      port.linkTypeResult = ok(botStartWire('TestBot', '', false));
      port.chatResult = ok(chatWire(303, privateTypeWire(79)));
      port.userResult = ok(userWire(79, true));
      const nav: NavRecorder = new NavRecorder();
      const res: AppLinkResult = await makeRouter(port, nav).handle('https://t.me/TestBot');
      expect(res.outcome).assertEqual('routed');
      expect(port.callsOf('sendBotStartMessage')).assertEqual(0);
    });

    it('botStart_rejectsNonPrivateChat', 0, async (): Promise<void> => {
      // 用户名指向的是群/频道时不是 bot 会话，不猜。
      const port: FakeAppLinkPort = new FakeAppLinkPort();
      port.linkTypeResult = ok(botStartWire('SomeChannel', 'x', true));
      port.chatResult = ok(chatWire(-10044, supergroupTypeWire(true)));
      const nav: NavRecorder = new NavRecorder();
      const res: AppLinkResult = await makeRouter(port, nav).handle('https://t.me/SomeChannel?start=x');
      expect(res.outcome).assertEqual('failed');
      expect(res.reason).assertEqual('bot_not_found');
      expect(port.callsOf('getUser')).assertEqual(0);
      expect(nav.routes.length).assertEqual(0);
    });

    it('failedOutcome_alwaysLeavesASummaryLine', 0, async (): Promise<void> => {
      // 设备取证踩过的坑：某个分支忘了记日志，链接点了没反应、日志里也查不到。
      // 兜底行由 handle() 统一给，所以任何一条 failed 都要留下一行 outcome=failed。
      const lines: string[] = [];
      const sink: Logger = new Logger('info', (_: LogLevel, line: string): void => {
        lines.push(line);
      });
      const port: FakeAppLinkPort = new FakeAppLinkPort();
      port.linkTypeResult = ok(botStartWire('GhostBot', '', false));
      port.chatResult = err(testError('CHAT_NOT_FOUND'));
      const nav: NavRecorder = new NavRecorder();
      const router: AppLinkRouter = new AppLinkRouter(port, {
        navigate: (route: AppRoute): void => {
          nav.navigate(route);
        },
        logger: sink
      });
      const res: AppLinkResult = await router.handle('https://t.me/GhostBot?start=x');
      expect(res.outcome).assertEqual('failed');
      let found: boolean = false;
      for (let i = 0; i < lines.length; i++) {
        if (lines[i].indexOf('outcome=failed') >= 0 && lines[i].indexOf('reason=bot_not_found') >= 0) {
          found = true;
        }
      }
      expect(found).assertTrue();
    });

    it('logLines_neverContainLinkBodies', 0, async (): Promise<void> => {
      // 邀请哈希等同凭证：日志里只能出现事件与 chatId。
      const lines: string[] = [];
      const sink: Logger = new Logger('info', (_: LogLevel, line: string): void => {
        lines.push(line);
      });
      const port: FakeAppLinkPort = new FakeAppLinkPort();
      port.linkTypeResult = ok(linkTypeWire('internalLinkTypeChatInvite'));
      port.inviteResult = ok(inviteInfoWire(-10099, 3, false, false));
      const nav: NavRecorder = new NavRecorder();
      const router: AppLinkRouter = new AppLinkRouter(port, {
        navigate: (route: AppRoute): void => {
          nav.navigate(route);
        },
        logger: sink
      });
      await router.handle('https://t.me/+SECRETInviteHash');
      let joined: string = '';
      for (let i = 0; i < lines.length; i++) {
        joined = `${joined}\n${lines[i]}`;
      }
      // 真记了一行，且那行里没有链接正文。
      expect(joined.length > 0).assertTrue();
      expect(joined.indexOf('outcome=') >= 0).assertTrue();
      expect(joined.indexOf('SECRETInviteHash')).assertEqual(-1);
    });
  });
}
