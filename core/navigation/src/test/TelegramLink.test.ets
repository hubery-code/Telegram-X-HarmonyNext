/**
 * core/navigation — TelegramLink 判定单测（DEEPLINK-101）。
 *
 * 这一层的用例钉的是「值不值得去问 TDLib」，不是链接语义：
 * 候选判定只看 scheme + host 白名单，归一只做补协议与子域改写两件事。
 */

import { describe, it, expect } from '@ohos/hypium';
import {
  TELEGRAM_LINK_HOSTS,
  UriParts,
  isTelegramLinkCandidate,
  normalizeTelegramLink,
  splitUri
} from '../main/ets/TelegramLink';

export default function telegramLinkTest() {
  describe('TelegramLinkTest', () => {
    it('hostAllowlist_matchesTdConstantsTmeHosts', 0, () => {
      // TGX TdConstants.TME_HOSTS 逐条对照，多一条少一条都算漂移。
      expect(TELEGRAM_LINK_HOSTS.join(',')).assertEqual('t.me,tx.me,telegram.me,telegram.dog');
      expect(isTelegramLinkCandidate('https://t.me/durov')).assertTrue();
      expect(isTelegramLinkCandidate('https://tx.me/durov')).assertTrue();
      expect(isTelegramLinkCandidate('https://telegram.me/durov')).assertTrue();
      expect(isTelegramLinkCandidate('https://telegram.dog/durov')).assertTrue();
    });

    it('nonTelegramHostsRejected', 0, () => {
      expect(isTelegramLinkCandidate('https://example.com/durov')).assertFalse();
      expect(isTelegramLinkCandidate('https://telegram.org/blog')).assertFalse();
      // 后缀伪造：不能因为 endsWith 判断放行相似域。
      expect(isTelegramLinkCandidate('https://nott.me/durov')).assertFalse();
      expect(isTelegramLinkCandidate('https://evil.com/t.me/durov')).assertFalse();
      expect(isTelegramLinkCandidate('https://xt.me/durov')).assertFalse();
      expect(isTelegramLinkCandidate('mailto:a@b.com')).assertFalse();
      expect(isTelegramLinkCandidate('')).assertFalse();
      expect(isTelegramLinkCandidate('   ')).assertFalse();
      expect(isTelegramLinkCandidate('durov')).assertFalse();
    });

    it('bareAndSubdomainFormsAreCandidates', 0, () => {
      expect(isTelegramLinkCandidate('t.me/durov')).assertTrue();
      expect(isTelegramLinkCandidate('t.me')).assertTrue();
      // username.t.me 是 TGX `isKnownHost` 的 endsWith 分支，算候选。
      expect(isTelegramLinkCandidate('https://durov.t.me/')).assertTrue();
      expect(isTelegramLinkCandidate('http://t.me/durov')).assertTrue();
    });

    it('tgSchemesWithoutAuthorityAreCandidates', 0, () => {
      expect(isTelegramLinkCandidate('tg://resolve?domain=durov')).assertTrue();
      // `tg:settings` 这种无 `//` 的遗留写法同样算（是否命中自有规则由 RouteCodec 判）。
      expect(isTelegramLinkCandidate('tg:settings')).assertTrue();
      expect(isTelegramLinkCandidate('telegram://t.me/durov')).assertTrue();
      // 其它自定义协议不归我们管。
      expect(isTelegramLinkCandidate('whatsapp://send?text=hi')).assertFalse();
    });

    it('splitUri_coversAuthorityPathQueryFragment', 0, () => {
      const parts: UriParts = splitUri('HTTPS://T.ME.:443/s/durov?a=1&b=2#frag');
      expect(parts.scheme).assertEqual('https');
      // 端口与尾部点在归一 host 时一起去掉。
      expect(parts.host).assertEqual('t.me');
      expect(parts.path).assertEqual('s/durov');
      expect(parts.query).assertEqual('a=1&b=2');

      const noScheme: UriParts = splitUri('t.me/durov');
      expect(noScheme.scheme).assertEqual('');
      expect(noScheme.host).assertEqual('t.me');
      expect(noScheme.path).assertEqual('durov');

      const bare: UriParts = splitUri('t.me');
      expect(bare.host).assertEqual('t.me');
      expect(bare.path).assertEqual('');

      // `tg:settings` 落在 path 上，与 RouteCodec.parseDeepLink 的口径一致。
      const tgNoSlash: UriParts = splitUri('tg:settings');
      expect(tgNoSlash.scheme).assertEqual('tg');
      expect(tgNoSlash.host).assertEqual('');
      expect(tgNoSlash.path).assertEqual('settings');
    });

    it('normalize_addsSchemeAndKeepsTelegramMeaning', 0, () => {
      expect(normalizeTelegramLink('t.me/durov')).assertEqual('https://t.me/durov');
      // 已带协议的 https 链接原样（去空白）返回。
      expect(normalizeTelegramLink('  https://t.me/durov ')).assertEqual('https://t.me/durov');
      // tg:// 深链不能被抓成 https。
      expect(normalizeTelegramLink('tg://resolve?domain=durov')).assertEqual('tg://resolve?domain=durov');
    });

    it('normalize_rewritesUsernameSubdomain', 0, () => {
      // Android preProcessTelegramUrl：TDLib 不认子域形态的公开链接。
      expect(normalizeTelegramLink('https://durov.t.me/1')).assertEqual('https://t.me/durov/1');
      // 改写保留原子域（TGX 的 preProcessTelegramUrl 只把用户名挪到 path 上）。
      expect(normalizeTelegramLink('durov.telegram.me')).assertEqual('https://telegram.me/durov');
      // query 必须留在改写后的链接上（代理链接靠它）。
      expect(normalizeTelegramLink('https://u.t.me/proxy?server=1.2.3.4&port=80'))
        .assertEqual('https://t.me/u/proxy?server=1.2.3.4&port=80');
    });

    it('normalize_leavesSiteAliasesAndPlainHostsAlone', 0, () => {
      // www/m 是站点别名，改写成 t.me/www 反而造出假用户名。
      expect(normalizeTelegramLink('https://www.t.me/durov')).assertEqual('https://www.t.me/durov');
      expect(normalizeTelegramLink('https://m.t.me/durov')).assertEqual('https://m.t.me/durov');
      // 多层子域不改（只认「已知 host 的一层子域」）。
      expect(normalizeTelegramLink('https://a.b.t.me/x')).assertEqual('https://a.b.t.me/x');
      // 非 Telegram host 一律原样。
      expect(normalizeTelegramLink('https://example.com/x')).assertEqual('https://example.com/x');
    });
  });
}
