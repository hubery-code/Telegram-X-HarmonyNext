/**
 * feature/settings — 网络代理模型层单测（PROXY-101 / PROXY-102）。
 *
 * 覆盖五条链路：
 * 1. 展示投影：备注优先的标题、备注让位后的地址副标题、设置主页行副标题三态；
 * 2. 表单校验：端口边界、MTProto secret 的 hex 与偶数长度、失败 key 的字段顺序；
 * 3. TDLib 双向映射：addedProxy → 行（识别不了就丢弃而不是造假行），
 *    表单 → proxy 负载（三种类型的字段裁剪与 http_only 透传）；
 * 4. PROXY-102 探测纯函数：五个 ConnectionState 判别式、秒 → 毫秒与失败哨兵、
 *    探测表的不可变写入与剪枝、行 → PingProxy 负载（null 行即直连探测）、
 *    生效行判定，以及「连接态优先、探测值兜底」的行状态表；
 * 5. 状态文案的中文词条齐全（缺 key 会原样回显，测得出漏翻）；
 * 6. PROXY-103 失败原因：TDLib 原文 → 本端句子的分类表（只分类不转发）、
 *    日志用的数字码、原因表的不可变写入/擦除/剪枝，以及「只有那句『出错』才带原因」。
 */

import { describe, it, expect } from '@ohos/hypium';
import { AppError, AppErrors, Lang } from '@tgx/core-common';
import {
  AddedProxy,
  PingProxy,
  ProxyTypeHttp,
  ProxyTypeMtproto,
  ProxyTypeSocks5,
  ProxyValue,
  TdProxyType,
  TdUnknownObject
} from '@tgx/core-td-api-generated';
import {
  classifyProxyFailure,
  pingProxyRequestFromItem,
  PROXY_NEW_ID,
  PROXY_NONE_ID,
  PROXY_PING_FAILED,
  PROXY_PING_LOADING,
  PROXY_PING_SLOW_MS,
  PROXY_PING_TIMEOUT_KEY,
  PROXY_PING_TIMEOUT_MS,
  PROXY_PING_UNSET,
  ProxyForm,
  ProxyItem,
  ProxyKind,
  ProxyStatus,
  emptyProxyForm,
  isMtprotoSecretValid,
  isProxyFormValid,
  proxyAddress,
  proxyConnectionStateOfType,
  proxyEnabledCount,
  proxyEnabledItem,
  proxyFailureOf,
  proxyFailuresPrunedTo,
  proxyFailuresWith,
  proxyFormError,
  proxyFormFromItem,
  proxyFormHasCredentials,
  proxyItemFromAdded,
  proxyKindLabel,
  proxyPingMsOfSeconds,
  proxyPingOf,
  proxyPingSuffix,
  proxyPingsPrunedTo,
  proxyPingsWith,
  proxyPortOf,
  proxyRowIsEffective,
  proxyRowSummary,
  proxyStatusOf,
  proxyTdlibCodeOf,
  proxyTitle,
  proxyValueFromForm,
  proxyValueFromItem
} from '../main/ets/model/ProxySettings';

function item(
  id: number,
  kind: ProxyKind,
  server: string,
  port: number,
  comment: string,
  isEnabled: boolean
): ProxyItem {
  return new ProxyItem(id, kind, server, port, '', '', '', false, comment, isEnabled);
}

function form(
  kind: ProxyKind,
  server: string,
  portInput: string,
  secret: string
): ProxyForm {
  return new ProxyForm(PROXY_NEW_ID, kind, server, portInput, '', '', secret, false, '', true);
}

function addedWith(kind: ProxyKind, server: string, port: number): AddedProxy {
  const value: ProxyValue = new ProxyValue();
  value.server = server;
  value.port = port;
  if (kind === 'http') {
    const http: ProxyTypeHttp = new ProxyTypeHttp();
    http.username = 'u1';
    http.password = 'p1';
    http.http_only = true;
    value.type_ = http;
  } else if (kind === 'mtproto') {
    const mtproto: ProxyTypeMtproto = new ProxyTypeMtproto();
    mtproto.secret = 'aabbccdd';
    value.type_ = mtproto;
  } else {
    const socks5: ProxyTypeSocks5 = new ProxyTypeSocks5();
    socks5.username = 'su';
    socks5.password = 'sp';
    value.type_ = socks5;
  }
  const added: AddedProxy = new AddedProxy();
  added.id = 7;
  added.is_enabled = true;
  added.comment = 'home';
  added.proxy = value;
  return added;
}

export default function proxySettingsTest(): void {
  describe('ProxySettings', () => {
    it('sentinels_areNotRealIds', 0, () => {
      // 两个哨兵必须互不相同：0 是「不使用代理」行，-1 是新增表单。
      expect(PROXY_NONE_ID).assertEqual(0);
      expect(PROXY_NEW_ID).assertEqual(-1);
    });

    it('kindLabel_mapsThreeTypes', 0, () => {
      expect(proxyKindLabel('socks5')).assertEqual('SOCKS5');
      expect(proxyKindLabel('http')).assertEqual('HTTP');
      expect(proxyKindLabel('mtproto')).assertEqual('MTProto');
    });

    it('title_prefersCommentThenAddress', 0, () => {
      expect(proxyTitle(item(1, 'socks5', '1.2.3.4', 1080, '公司出口', false)))
        .assertEqual('公司出口');
      expect(proxyTitle(item(1, 'socks5', '1.2.3.4', 1080, '   ', false)))
        .assertEqual('1.2.3.4:1080');
      // 备注存在时，地址回补到副标题，二者信息不丢。
      expect(proxyAddress(item(1, 'http', 'proxy.example.com', 8080, '公司出口', false)))
        .assertEqual('proxy.example.com:8080');
    });

    it('rowSummary_threeStates', 0, () => {
      expect(proxyRowSummary([])).assertEqual('Tap to set up');
      expect(proxyRowSummary([item(1, 'socks5', 'a.com', 1080, '', false)]))
        .assertEqual('Proxy Disabled');
      expect(proxyRowSummary([
        item(1, 'socks5', 'a.com', 1080, '', false),
        item(2, 'mtproto', 'b.com', 443, '加速', true)
      ])).assertEqual('加速');
    });

    it('enabledHelpers', 0, () => {
      const items: ProxyItem[] = [
        item(1, 'socks5', 'a.com', 1080, '', false),
        item(2, 'socks5', 'b.com', 1080, '', true)
      ];
      expect(proxyEnabledCount(items)).assertEqual(1);
      expect(proxyEnabledCount([items[0]])).assertEqual(0);
      const enabled: ProxyItem | null = proxyEnabledItem(items);
      expect(enabled === null).assertFalse();
      if (enabled !== null) {
        expect(enabled.id).assertEqual(2);
      }
      expect(proxyEnabledItem([]) === null).assertTrue();
    });

    it('port_rejectsNonIntegerAndOutOfRange', 0, () => {
      expect(proxyPortOf('1080')).assertEqual(1080);
      expect(proxyPortOf(' 8080 ')).assertEqual(8080);
      expect(proxyPortOf('65535')).assertEqual(65535);
      expect(proxyPortOf('0')).assertEqual(0);
      expect(proxyPortOf('65536')).assertEqual(0);
      expect(proxyPortOf('123456')).assertEqual(0);
      expect(proxyPortOf('abc')).assertEqual(0);
      expect(proxyPortOf('10a')).assertEqual(0);
      expect(proxyPortOf('')).assertEqual(0);
    });

    it('mtprotoSecret_requiresEvenHex', 0, () => {
      expect(isMtprotoSecretValid('aabbccdd')).assertTrue();
      expect(isMtprotoSecretValid('AABB00')).assertTrue();
      expect(isMtprotoSecretValid('')).assertFalse();
      expect(isMtprotoSecretValid('aab')).assertFalse();
      expect(isMtprotoSecretValid('aagb')).assertFalse();
      expect(isMtprotoSecretValid('aa bb')).assertFalse();
    });

    it('formError_reportsTopmostFieldFirst', 0, () => {
      expect(proxyFormError(form('socks5', '', '1080', ''))).assertEqual('Server address required');
      expect(proxyFormError(form('socks5', 'a.com', '', ''))).assertEqual('Port must be 1-65535');
      expect(proxyFormError(form('mtproto', 'a.com', '443', 'zz')))
        .assertEqual('Secret must be hexadecimal');
      expect(proxyFormError(form('mtproto', 'a.com', '443', 'aabb'))).assertEqual('');
      // 凭据可选：socks5 不填账号密码也算合法。
      expect(isProxyFormValid(form('socks5', 'a.com', '1080', ''))).assertTrue();
      expect(isProxyFormValid(form('http', 'a.com', '0', ''))).assertFalse();
    });

    it('credentials_onlyForSocks5AndHttp', 0, () => {
      expect(proxyFormHasCredentials('socks5')).assertTrue();
      expect(proxyFormHasCredentials('http')).assertTrue();
      expect(proxyFormHasCredentials('mtproto')).assertFalse();
    });

    it('emptyForm_defaultsToSocks5EnabledOnSave', 0, () => {
      const f: ProxyForm = emptyProxyForm();
      expect(f.id).assertEqual(PROXY_NEW_ID);
      expect(f.kind).assertEqual('socks5');
      expect(f.enable).assertTrue();
      expect(f.server).assertEqual('');
      // 初始态一定不可提交，避免空表单直接写进 TDLib。
      expect(isProxyFormValid(f)).assertFalse();
    });

    it('formFromItem_roundTripsThroughValue', 0, () => {
      const source: ProxyItem = new ProxyItem(
        21, 'http', 'proxy.example.com', 8080, 'u2', 'p2', '', true, 'office', false
      );
      const f: ProxyForm = proxyFormFromItem(source);
      expect(f.id).assertEqual(21);
      expect(f.kind).assertEqual('http');
      expect(f.portInput).assertEqual('8080');
      expect(f.username).assertEqual('u2');
      expect(f.password).assertEqual('p2');
      expect(f.httpOnly).assertTrue();
      expect(f.enable).assertFalse();
      const value: ProxyValue = proxyValueFromForm(f);
      expect(value.server).assertEqual('proxy.example.com');
      expect(value.port).assertEqual(8080);
      const type: TdProxyType | null = value.type_;
      expect(type === null).assertFalse();
      if (type !== null) {
        expect(type.type).assertEqual('proxyTypeHttp');
        const http: ProxyTypeHttp = type as ProxyTypeHttp;
        expect(http.http_only).assertTrue();
        expect(http.username).assertEqual('u2');
      }
    });

    it('valueFromForm_cropsFieldsByKind', 0, () => {
      const socks: ProxyValue = proxyValueFromForm(
        new ProxyForm(PROXY_NEW_ID, 'socks5', '  a.com  ', '1080', ' su ', ' sp', 'zz', true, 'x', true)
      );
      expect(socks.server).assertEqual('a.com');
      expect(socks.port).assertEqual(1080);
      const s: ProxyTypeSocks5 = socks.type_ as ProxyTypeSocks5;
      expect(s.type).assertEqual('proxyTypeSocks5');
      expect(s.username).assertEqual('su');
      // 密码原样透传：两端空格可能是口令本身，trim 会把代理写成不可用。
      expect(s.password).assertEqual(' sp');

      // MTProto 忽略账号密码与 httpOnly，只带 secret。
      const mt: ProxyValue = proxyValueFromForm(
        new ProxyForm(PROXY_NEW_ID, 'mtproto', 'b.com', '443', 'ign', 'ored', ' aabb ', true, '', false)
      );
      const m: ProxyTypeMtproto = mt.type_ as ProxyTypeMtproto;
      expect(m.type).assertEqual('proxyTypeMtproto');
      expect(m.secret).assertEqual('aabb');

      // httpOnly 默认关：表单没勾就不该传 true。
      const http: ProxyValue = proxyValueFromForm(form('http', 'c.com', '3128', ''));
      expect((http.type_ as ProxyTypeHttp).http_only).assertFalse();
    });

    it('itemFromAdded_mapsAllThreeKinds', 0, () => {
      const socks: ProxyItem | null = proxyItemFromAdded(addedWith('socks5', 'a.com', 1080));
      expect(socks === null).assertFalse();
      if (socks !== null) {
        expect(socks.id).assertEqual(7);
        expect(socks.kind).assertEqual('socks5');
        expect(socks.username).assertEqual('su');
        expect(socks.secret).assertEqual('');
        expect(socks.httpOnly).assertFalse();
        expect(socks.isEnabled).assertTrue();
        expect(socks.comment).assertEqual('home');
      }
      const http: ProxyItem | null = proxyItemFromAdded(addedWith('http', 'b.com', 8080));
      if (http !== null) {
        expect(http.kind).assertEqual('http');
        expect(http.httpOnly).assertTrue();
        expect(http.username).assertEqual('u1');
      }
      const mt: ProxyItem | null = proxyItemFromAdded(addedWith('mtproto', 'c.com', 443));
      if (mt !== null) {
        expect(mt.kind).assertEqual('mtproto');
        expect(mt.secret).assertEqual('aabbccdd');
        expect(mt.username).assertEqual('');
      }
    });

    it('itemFromAdded_dropsUnusableRows', 0, () => {
      const noProxy: AddedProxy = new AddedProxy();
      noProxy.id = 1;
      expect(proxyItemFromAdded(noProxy) === null).assertTrue();

      const emptyServer: AddedProxy = addedWith('socks5', '', 1080);
      expect(proxyItemFromAdded(emptyServer) === null).assertTrue();

      const nullType: ProxyValue | null = addedWith('socks5', 'a.com', 1080).proxy;
      if (nullType !== null) {
        nullType.type_ = null;
        const noType: AddedProxy = new AddedProxy();
        noType.proxy = nullType;
        expect(proxyItemFromAdded(noType) === null).assertTrue();
      }

      // 未知 @type 解出的 TdUnknownObject 不能冒充一种代理类型。
      const unknownValue: ProxyValue | null = addedWith('socks5', 'a.com', 1080).proxy;
      if (unknownValue !== null) {
        unknownValue.type_ = new TdUnknownObject('proxyTypeSomethingNew', {});
        const unknownType: AddedProxy = new AddedProxy();
        unknownType.proxy = unknownValue;
        expect(proxyItemFromAdded(unknownType) === null).assertTrue();
      }
    });

    it('withEnabled_returnsSameInstanceWhenUnchanged', 0, () => {
      const base: ProxyItem = item(3, 'socks5', 'a.com', 1080, '', true);
      expect(base.withEnabled(true) === base).assertTrue();
      const off: ProxyItem = base.withEnabled(false);
      expect(off.isEnabled).assertFalse();
      expect(off.id).assertEqual(3);
      expect(off.server).assertEqual('a.com');
    });

    // ---- PROXY-102 探测与连接态 ----

    it('connectionState_mapsFiveWireTypes', 0, () => {
      expect(proxyConnectionStateOfType('connectionStateWaitingForNetwork'))
        .assertEqual('waiting_for_network');
      expect(proxyConnectionStateOfType('connectionStateConnectingToProxy'))
        .assertEqual('connecting_to_proxy');
      expect(proxyConnectionStateOfType('connectionStateConnecting')).assertEqual('connecting');
      expect(proxyConnectionStateOfType('connectionStateUpdating')).assertEqual('updating');
      expect(proxyConnectionStateOfType('connectionStateReady')).assertEqual('ready');
      // 以后 TDLib 加一档，也不能被硬编成当前五个里的某一个。
      expect(proxyConnectionStateOfType('connectionStateBrandNew')).assertEqual('unknown');
      expect(proxyConnectionStateOfType('')).assertEqual('unknown');
    });

    it('pingMs_roundsSecondsAndRejectsGarbage', 0, () => {
      expect(proxyPingMsOfSeconds(0.042)).assertEqual(42);
      expect(proxyPingMsOfSeconds(1.2345)).assertEqual(1235);
      expect(proxyPingMsOfSeconds(0)).assertEqual(PROXY_PING_FAILED);
      expect(proxyPingMsOfSeconds(-3)).assertEqual(PROXY_PING_FAILED);
      expect(proxyPingMsOfSeconds(Number.NaN)).assertEqual(PROXY_PING_FAILED);
      expect(proxyPingMsOfSeconds(Number.POSITIVE_INFINITY)).assertEqual(PROXY_PING_FAILED);
    });

    it('sentinels_areAllNegativeAndDistinct', 0, () => {
      // 三个哨兵都必须是负数：正数是真实延迟，0 不是合法值也不能被当成「没测过」。
      expect(PROXY_PING_UNSET).assertEqual(-1);
      expect(PROXY_PING_LOADING).assertEqual(-2);
      expect(PROXY_PING_FAILED).assertEqual(-3);
    });

    it('pingTable_isImmutableAndPrunesDeadRows', 0, () => {
      const empty: Map<number, number> = new Map();
      const first: Map<number, number> = proxyPingsWith(empty, 11, 42);
      expect(empty.size).assertEqual(0);
      expect(proxyPingOf(first, 11)).assertEqual(42);
      // 没测过的行读出 UNSET，而不是 undefined 或 0。
      expect(proxyPingOf(first, 12)).assertEqual(PROXY_PING_UNSET);

      const second: Map<number, number> = proxyPingsWith(first, PROXY_NONE_ID, PROXY_PING_FAILED);
      expect(first.size).assertEqual(1);
      expect(proxyPingOf(second, PROXY_NONE_ID)).assertEqual(PROXY_PING_FAILED);

      // 列表重建后：活着的行留住在途探测，删掉的行不留残值，0 恒在。
      const alive: ProxyItem[] = [item(11, 'socks5', 'a.com', 1080, '', false)];
      const pruned: Map<number, number> = proxyPingsPrunedTo(second, alive);
      expect(proxyPingOf(pruned, 11)).assertEqual(42);
      expect(proxyPingOf(pruned, PROXY_NONE_ID)).assertEqual(PROXY_PING_FAILED);
      expect(pruned.size).assertEqual(2);
    });

    it('pingRequest_rebuildsPayloadFromRowOrNullForDirect', 0, () => {
      const direct: PingProxy = pingProxyRequestFromItem(null);
      expect(direct.proxy === null).assertTrue();

      const socks5: ProxyItem = new ProxyItem(
        21, 'socks5', 'socks.example', 1080, 'user', 'pass', '', false, '', false
      );
      const socksValue: ProxyValue | null = pingProxyRequestFromItem(socks5).proxy;
      expect(socksValue !== null).assertTrue();
      if (socksValue !== null) {
        expect(socksValue.server).assertEqual('socks.example');
        expect(socksValue.port).assertEqual(1080);
        const parsed: ProxyTypeSocks5 = socksValue.type_ as ProxyTypeSocks5;
        expect(parsed.username).assertEqual('user');
        expect(parsed.password).assertEqual('pass');
      }

      // MTProto 的密钥在 type 里，不在请求上；http_only 只有 HTTP 才带。
      const mtproto: ProxyItem = new ProxyItem(
        22, 'mtproto', 'mt.example', 443, '', '', 'aabbccdd', false, '', false
      );
      const mtValue: ProxyValue | null = pingProxyRequestFromItem(mtproto).proxy;
      if (mtValue !== null) {
        expect((mtValue.type_ as ProxyTypeMtproto).secret).assertEqual('aabbccdd');
      }
      const http: ProxyItem = new ProxyItem(
        23, 'http', 'http.example', 8080, 'u', 'p', '', true, '', false
      );
      const httpValue: ProxyValue | null = pingProxyRequestFromItem(http).proxy;
      if (httpValue !== null) {
        expect((httpValue.type_ as ProxyTypeHttp).http_only).assertTrue();
      }
      // 行 → 负载与表单 → 负载共用一个构造器，两条路必须给出同一种类型。
      const fromForm: ProxyValue = proxyValueFromForm(
        new ProxyForm(PROXY_NEW_ID, 'http', 'http.example', '8080', 'u', 'p', '', true, '', true)
      );
      expect(fromForm.server).assertEqual('http.example');
      expect(proxyValueFromItem(http).port).assertEqual(fromForm.port);
    });

    it('rowIsEffective_onlyOneRouteCarriesTheConnection', 0, () => {
      const enabled: ProxyItem = item(31, 'socks5', 'a.com', 1080, '', true);
      const other: ProxyItem = item(32, 'socks5', 'b.com', 1080, '', false);
      expect(proxyRowIsEffective([enabled, other], enabled)).assertTrue();
      expect(proxyRowIsEffective([enabled, other], other)).assertFalse();
      // 「不使用代理」只有在没有代理启用时才是那条生效的路。
      expect(proxyRowIsEffective([enabled, other], null)).assertFalse();
      expect(proxyRowIsEffective([other], null)).assertTrue();
      expect(proxyRowIsEffective([], null)).assertTrue();
    });

    it('statusOf_effectiveRowFollowsConnection', 0, () => {
      const enabled: ProxyItem = item(41, 'mtproto', 'a.com', 443, '', true);
      expect(proxyStatusOf(enabled, 42, true, 'ready').key).assertEqual('Connected');
      expect(proxyStatusOf(enabled, 42, true, 'ready').pingMs).assertEqual(42);
      // 连上了但这次没测到延迟：照样说「已连接」，只是不编一个数字出来。
      expect(proxyStatusOf(enabled, PROXY_PING_UNSET, true, 'ready').pingMs)
        .assertEqual(PROXY_PING_UNSET);
      // 探测在途排在连接词之前，与 TGX 一致。
      expect(proxyStatusOf(enabled, PROXY_PING_LOADING, true, 'connecting').key)
        .assertEqual('Checking...');
      expect(proxyStatusOf(enabled, 12, true, 'waiting_for_network').key)
        .assertEqual('Waiting for network...');
      expect(proxyStatusOf(enabled, 12, true, 'updating').key).assertEqual('Updating...');
      expect(proxyStatusOf(enabled, 12, true, 'connecting_to_proxy').key)
        .assertEqual('Connecting...');
      // 连接态还没观察到（订阅是进页才建立的）时，探测就是唯一事实。
      expect(proxyStatusOf(enabled, 88, true, 'unknown').key).assertEqual('Connected');
      expect(proxyStatusOf(enabled, PROXY_PING_UNSET, true, 'unknown').key).assertEqual('');
    });

    it('statusOf_inactiveRowOnlyHasProbeResult', 0, () => {
      const idle: ProxyItem = item(42, 'socks5', 'a.com', 1080, '', false);
      expect(proxyStatusOf(idle, 30, false, 'ready').key).assertEqual('Available');
      expect(proxyStatusOf(idle, 30, false, 'ready').pingMs).assertEqual(30);
      expect(proxyStatusOf(idle, PROXY_PING_LOADING, false, 'waiting_for_network').key)
        .assertEqual('Checking...');
      expect(proxyStatusOf(idle, PROXY_PING_UNSET, false, 'updating').key).assertEqual('');
      // 生效行与非生效行对同一份探测结果给出不同的词。
      expect(proxyStatusOf(idle, PROXY_PING_FAILED, false, 'unknown').key).assertEqual('Error');
      expect(proxyStatusOf(item(43, 'socks5', 'a.com', 1, '', true), PROXY_PING_FAILED, true, 'unknown')
        .key).assertEqual('Error');
      // 「不使用代理」没有代理可怪，说的是直连。
      expect(proxyStatusOf(null, PROXY_PING_FAILED, false, 'unknown').key)
        .assertEqual('Problems detected');
      expect(proxyStatusOf(null, 15, false, 'unknown').key).assertEqual('Available');
    });

    it('pingSuffix_onlyForPositiveNumbers', 0, () => {
      expect(proxyPingSuffix(42)).assertEqual(' · 42 ms');
      expect(proxyPingSuffix(PROXY_PING_UNSET)).assertEqual('');
      expect(proxyPingSuffix(PROXY_PING_LOADING)).assertEqual('');
      expect(proxyPingSuffix(PROXY_PING_FAILED)).assertEqual('');
      expect(proxyPingSuffix(0)).assertEqual('');
    });

    it('status_isAValueObjectWithTwoFields', 0, () => {
      const status: ProxyStatus = new ProxyStatus('Connected', 7);
      expect(status.key).assertEqual('Connected');
      expect(status.pingMs).assertEqual(7);
      // 第三字段有默认值，所以四参数老写法仍然成立。
      expect(status.failureKey).assertEqual('');
      expect(new ProxyStatus('Error', -1, 'Connection refused').failureKey)
        .assertEqual('Connection refused');
    });

    it('classify_mapsKnownTdlibTextsToOwnSentence', 0, () => {
      // 分类而不是转发：Android 把 TDLib 原文印到行上，本端只给一句自己的话。
      expect(classifyProxyFailure(tdlib(400, '[Error 400] Connection timed out')))
        .assertEqual('Connection timed out');
      expect(classifyProxyFailure(tdlib(400, '[Error 400] connect failed: Connection refused')))
        .assertEqual('Connection refused');
      expect(classifyProxyFailure(tdlib(400, 'Failed to resolve "proxy.example.invalid": ...')))
        .assertEqual('Address not found');
      expect(classifyProxyFailure(tdlib(400, 'getaddrinfo: nodename nor servname provided')))
        .assertEqual('Address not found');
      expect(classifyProxyFailure(tdlib(400, 'Network is unreachable')))
        .assertEqual('Network unavailable');
      expect(classifyProxyFailure(tdlib(400, 'proxy handshake failed')))
        .assertEqual('Proxy handshake failed');
      expect(classifyProxyFailure(tdlib(400, 'Wrong secret: can not decrypt')))
        .assertEqual('Proxy settings rejected');
      // 认不出的原文只能给一句通用的 —— 绝不调头把 message 搬上来。
      expect(classifyProxyFailure(tdlib(400, 'some TDLib wording nobody mapped')))
        .assertEqual('Proxy error');
    });

    it('classify_prefersTheFirstMatchingBranch', 0, () => {
      // 一句话里同时有 timeout 与 refused 时，先说的是超时（更长的那个等待才是真相）。
      expect(classifyProxyFailure(tdlib(400, 'connect refused after timeout')))
        .assertEqual('Connection timed out');
    });

    it('classify_readsASlowFailureAsTimeout', 0, () => {
      // 模拟器实测：不可达地址 TDLib 约 9s 才回 400，且那句里不带 timeout 字样。
      // 慢到这份上就是超时，不必等它亲口承认 —— 否则这一行只会得到一句没信息量的「代理异常」。
      expect(classifyProxyFailure(tdlib(400, 'proxy connect failed'), PROXY_PING_SLOW_MS))
        .assertEqual('Connection timed out');
      expect(classifyProxyFailure(tdlib(400, 'proxy connect failed'), PROXY_PING_SLOW_MS - 1))
        .assertEqual('Proxy error');
      // DNS 失败实测 4s 回来，不能被这条线误伤成超时。
      expect(classifyProxyFailure(tdlib(400, 'Failed to resolve host'), 4000))
        .assertEqual('Address not found');
    });

    it('classify_fallsBackToErrorKind', 0, () => {      // 不是 tdlib 类：network 类错误没有原文可分类，但结论就是「没网」。
      expect(classifyProxyFailure(AppErrors.network('unreachable', 'network failed', true)))
        .assertEqual('Network unavailable');
      expect(classifyProxyFailure(AppErrors.internal('proxy_ping', 'boom')))
        .assertEqual('Proxy error');
    });

    it('tdlibCodeOf_readsTheCodeForLogsOnly', 0, () => {
      expect(proxyTdlibCodeOf(tdlib(400, 'Connection refused'))).assertEqual(400);
      expect(proxyTdlibCodeOf(tdlib(429, 'Too Many Requests'))).assertEqual(429);
      // 非 tdlib 类没有码；没有冒号的 cause 也不猜。
      expect(proxyTdlibCodeOf(AppErrors.network('timeout', 'network failed', true))).assertEqual(0);
      expect(proxyTdlibCodeOf(AppErrors.tdlib('unknown', 'x', true, undefined, 'no digits here')))
        .assertEqual(0);
      // 负数是 TDLib 内部码（-410），不当作可展示的诊断码。
      expect(proxyTdlibCodeOf(tdlib(-410, 'chat not found'))).assertEqual(0);
    });

    it('failureTable_readsWritesAndPrunes', 0, () => {
      let failures: Map<number, string> = new Map();
      expect(proxyFailureOf(failures, 41)).assertEqual('');
      failures = proxyFailuresWith(failures, 41, 'Connection refused');
      failures = proxyFailuresWith(failures, PROXY_NONE_ID, 'Address not found');
      expect(proxyFailureOf(failures, 41)).assertEqual('Connection refused');
      expect(proxyFailureOf(failures, PROXY_NONE_ID)).assertEqual('Address not found');
      // 不可变写入：原表不动。
      const before: Map<number, string> = failures;
      proxyFailuresWith(failures, 99, 'Proxy error');
      expect(before.size).assertEqual(2);
      // 成功探测后把原因擦掉（空串 = 删条目，不留 `41: ''`）。
      failures = proxyFailuresWith(failures, 41, '');
      expect(proxyFailureOf(failures, 41)).assertEqual('');
      expect(failures.has(41)).assertFalse();
      // 剪枝：删掉的行不再占位，「不使用代理」那一行永远留着。
      const alive: ProxyItem[] = [item(42, 'socks5', 'b.com', 1080, '', false)];
      const pruned: Map<number, string> = proxyFailuresPrunedTo(failures, alive);
      expect(proxyFailureOf(pruned, PROXY_NONE_ID)).assertEqual('Address not found');
      expect(pruned.has(41)).assertFalse();
    });

    it('statusOf_attachesFailureOnlyToTheErrorSentence', 0, () => {
      const dead: ProxyItem = item(41, 'socks5', 'a.com', 1080, '', true);
      // 生效行：连接态还在说话时不挂失败原因（那是上一次探测的旧账）。
      let status: ProxyStatus = proxyStatusOf(dead, PROXY_PING_FAILED, true, 'connecting', 'Connection refused');
      expect(status.key).assertEqual('Connecting...');
      expect(status.failureKey).assertEqual('');
      // 连接态说不出话（还没观察到）时，失败原因才跟着「Error」一起上屏。
      status = proxyStatusOf(dead, PROXY_PING_FAILED, true, 'unknown', 'Connection refused');
      expect(status.key).assertEqual('Error');
      expect(status.failureKey).assertEqual('Connection refused');
      // 非生效行只有探测结果可说，失败原因同样跟着走。
      const idleRow: ProxyItem = item(42, 'socks5', 'a.com', 1080, '', false);
      status = proxyStatusOf(idleRow, PROXY_PING_FAILED, false, 'ready', 'Address not found');
      expect(status.key).assertEqual('Error');
      expect(status.failureKey).assertEqual('Address not found');
      // 「不使用代理」那一行说的是直连。
      status = proxyStatusOf(null, PROXY_PING_FAILED, false, 'unknown', 'Network unavailable');
      expect(status.key).assertEqual('Problems detected');
      expect(status.failureKey).assertEqual('Network unavailable');
      // 成功与在途都不该带原因。
      expect(proxyStatusOf(idleRow, 30, false, 'unknown', 'Connection refused').failureKey).assertEqual('');
      expect(proxyStatusOf(idleRow, PROXY_PING_LOADING, false, 'unknown', 'Connection refused').failureKey)
        .assertEqual('');
    });

    it('pingTimeout_isABoundedWaitWithItsOwnSentence', 0, () => {
      // 兜底超时必须是有界的（太长等于没有，太短会误伤慢代理）。
      expect(PROXY_PING_TIMEOUT_MS >= 5000).assertTrue();
      expect(PROXY_PING_TIMEOUT_MS <= 30000).assertTrue();
      expect(PROXY_PING_TIMEOUT_KEY).assertEqual('Connection timed out');
    });

    it('statusKeys_allHaveChineseTranslations', 0, () => {
      // 缺 key 时 Lang 会原样返回 key，所以「翻出来的 != key」就是这句真的进过字典。
      const keys: string[] = [
        'Connected', 'Available', 'Checking...', 'Connecting...',
        'Waiting for network...', 'Updating...', 'Error', 'Problems detected',
        'Address not found', 'Connection refused', 'Connection timed out',
        'Network unavailable', 'Proxy handshake failed', 'Proxy settings rejected',
        'Proxy error'
      ];
      const lang: Lang = Lang.getInstance();
      const empty: (string | number)[] = [];
      for (let i = 0; i < keys.length; i++) {
        expect(lang.formatByKey(keys[i], 'zh', empty) !== keys[i]).assertTrue();
      }
    });
  });
}

function tdlib(code: number, text: string): AppError {
  return AppErrors.fromTdlibError(code, text);
}
