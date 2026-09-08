import { describe, it, expect } from '@ohos/hypium';
import { AppRoute, ChatRoute, SearchRoute } from '../main/ets/Route';
import { defaultRegistry } from '../main/ets/RouteRegistry';
import { RouteCodec, DeepLinkRule, defaultDeepLinkRules } from '../main/ets/RouteCodec';
import type { AppError } from '@tgx/core-common';
import { mustOk, mustErr, paramField, paramCode } from './TestSupport';

function codec(): RouteCodec {
  return new RouteCodec(defaultRegistry());
}

function roundTrip(route: AppRoute): void {
  const c: RouteCodec = codec();
  const path: string = mustOk(c.encode(route));
  const parsed: AppRoute = mustOk(c.parse(path));
  expect(JSON.stringify(parsed)).assertEqual(JSON.stringify(route));
  // 二次编码应产生完全相同的路径（编码确定性）。
  const path2: string = mustOk(c.encode(parsed));
  expect(path2).assertEqual(path);
}

export default function routeCodecTest() {
  describe('RouteCodecTest', () => {
    it('encodeParse_roundTrip_allBuiltinRoutes', 0, () => {
      roundTrip({ name: 'home' });
      roundTrip({ name: 'auth' });
      roundTrip({ name: 'chat', chatId: 123 });
      roundTrip({ name: 'chat', chatId: -1001234567890, threadId: 77 });
      roundTrip({ name: 'chatInfo', chatId: 555 });
      roundTrip({ name: 'settings' });
      roundTrip({ name: 'settingsSection', section: 'notifications' });
      roundTrip({ name: 'search' });
      roundTrip({ name: 'search', query: 'hello world&=?' });
      roundTrip({ name: 'mediaViewer', chatId: 1, messageId: 999 });
    });

    it('encode_optionalParamsGoToQueryString', 0, () => {
      const c: RouteCodec = codec();
      const path: string = mustOk(c.encode({ name: 'chat', chatId: 5, threadId: 7 }));
      expect(path).assertEqual('chat/5?threadId=7');
    });

    it('parse_acceptsLeadingSlash', 0, () => {
      const route: AppRoute = mustOk(codec().parse('/settings/general'));
      expect(route.name).assertEqual('settingsSection');
    });

    it('parse_missingPath_rejected', 0, () => {
      expect(mustErr(codec().parse('')).kind).assertEqual('parameter');
      expect(mustErr(codec().parse('/')).kind).assertEqual('parameter');
    });

    it('parse_unknownRoute_rejected', 0, () => {
      const error: AppError = mustErr(codec().parse('nope/1'));
      expect(error.kind).assertEqual('parameter');
      expect(paramField(error)).assertEqual('route');
    });

    it('parse_typeMismatchInt_rejected', 0, () => {
      const error: AppError = mustErr(codec().parse('chat/abc'));
      expect(error.kind).assertEqual('parameter');
      expect(paramCode(error)).assertEqual('invalid');
      expect(paramField(error)).assertEqual('chatId');
    });

    it('parse_intBelowMin_rejected', 0, () => {
      const error: AppError = mustErr(codec().parse('mediaViewer/1/0'));
      expect(paramCode(error)).assertEqual('out_of_range');
      expect(paramField(error)).assertEqual('messageId');
    });

    it('parse_intBeyondSafeRange_rejected', 0, () => {
      const error: AppError = mustErr(codec().parse('chat/9007199254740993'));
      expect(paramCode(error)).assertEqual('out_of_range');
    });

    it('parse_patternMismatch_rejected', 0, () => {
      const upper: AppError = mustErr(codec().parse('settings/General'));
      expect(paramField(upper)).assertEqual('section');
      const dash: AppError = mustErr(codec().parse('settings/gen-eral'));
      expect(paramField(dash)).assertEqual('section');
      const okRoute: AppRoute = mustOk(codec().parse('settings/notifications2_x'));
      expect(okRoute.name).assertEqual('settingsSection');
    });

    it('parse_unknownQueryParam_rejected', 0, () => {
      const error: AppError = mustErr(codec().parse('chat/5?bogus=1'));
      expect(paramField(error)).assertEqual('bogus');
    });

    it('parse_duplicateQueryParam_rejected', 0, () => {
      const error: AppError = mustErr(codec().parse('search?query=a&query=b'));
      expect(paramField(error)).assertEqual('query');
    });

    it('parse_malformedPercentEncoding_rejected', 0, () => {
      const inPath: AppError = mustErr(codec().parse('chat/12%3'));
      expect(paramField(inPath)).assertEqual('chatId');
      const inQuery: AppError = mustErr(codec().parse('search?query=%2'));
      expect(paramField(inQuery)).assertEqual('query');
    });

    it('parse_emptyPathSegment_rejected', 0, () => {
      expect(mustErr(codec().parse('chat//5')).kind).assertEqual('parameter');
    });

    it('deepLink_tgChat_resolved', 0, () => {
      const rules: DeepLinkRule[] = defaultDeepLinkRules();
      const route: AppRoute = mustOk(codec().parseDeepLink('tg://chat?chatId=123', rules));
      expect(JSON.stringify(route)).assertEqual(JSON.stringify({ name: 'chat', chatId: 123 } as ChatRoute));
    });

    it('deepLink_tgChatWithThreadAndJunkParams_resolved', 0, () => {
      const route: AppRoute = mustOk(
        codec().parseDeepLink('tg://chat?chatId=123&threadId=5&utm_source=x', defaultDeepLinkRules())
      );
      const chat: ChatRoute = route as ChatRoute;
      expect(chat.name).assertEqual('chat');
      expect(chat.chatId).assertEqual(123);
      expect(chat.threadId).assertEqual(5);
    });

    it('deepLink_missingRequiredParam_rejected', 0, () => {
      const error: AppError = mustErr(codec().parseDeepLink('tg://chat', defaultDeepLinkRules()));
      expect(paramCode(error)).assertEqual('missing');
      expect(paramField(error)).assertEqual('chatId');
    });

    it('deepLink_unknownSchemeAndHost_rejected', 0, () => {
      const scheme: AppError = mustErr(codec().parseDeepLink('evil://chat?chatId=1', defaultDeepLinkRules()));
      expect(paramField(scheme)).assertEqual('deepLink');
      const host: AppError = mustErr(codec().parseDeepLink('tg://nope?a=1', defaultDeepLinkRules()));
      expect(paramField(host)).assertEqual('deepLink');
    });

    it('deepLink_invalidMappedParam_rejected', 0, () => {
      const error: AppError = mustErr(codec().parseDeepLink('tg://chat?chatId=abc', defaultDeepLinkRules()));
      expect(error.kind).assertEqual('parameter');
      expect(paramField(error)).assertEqual('chatId');
    });

    it('deepLink_malformedUri_rejected', 0, () => {
      const noScheme: AppError = mustErr(codec().parseDeepLink('no-scheme-here', defaultDeepLinkRules()));
      expect(paramField(noScheme)).assertEqual('deepLink');
      const badPercent: AppError = mustErr(codec().parseDeepLink('tg://chat?chatId=%2', defaultDeepLinkRules()));
      expect(paramField(badPercent)).assertEqual('chatId');
    });

    it('deepLink_pathNotAllowedByRule_rejected', 0, () => {
      const error: AppError = mustErr(codec().parseDeepLink('tg://settings/extra?x=1', defaultDeepLinkRules()));
      expect(paramField(error)).assertEqual('deepLink');
    });

    it('deepLink_httpsTmeSample_resolved', 0, () => {
      const route: AppRoute = mustOk(
        codec().parseDeepLink('https://t.me/chat/42?threadId=9#frag', defaultDeepLinkRules())
      );
      const chat: ChatRoute = route as ChatRoute;
      expect(chat.chatId).assertEqual(42);
      expect(chat.threadId).assertEqual(9);
    });

    it('deepLink_tgSearch_resolved', 0, () => {
      const route: AppRoute = mustOk(codec().parseDeepLink('tg://search?query=hello%20world', defaultDeepLinkRules()));
      const search: SearchRoute = route as SearchRoute;
      expect(search.query).assertEqual('hello world');
    });
  });
}
