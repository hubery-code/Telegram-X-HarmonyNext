/**
 * core/navigation — Telegram 链接判定（DEEPLINK-101 / FEAT-P2-010）。
 *
 * **解析交给 TDLib，本文件只做「值不值得去问」的判定**。
 * Android 侧 `TdlibUi.openUrl` 的链条是 `openTelegramUrl` → `TdApi.GetInternalLinkType`
 * → 按 `InternalLinkType` 分发，问不到（`internalLinkTypeUnknownDeepLink`）才
 * `openExternalUrl` 落到浏览器；它自己**不维护用户名/保留字表**，所以链接语义只有
 * 一个真值来源。本端照抄这个分工：`t.me/durov` 是公开会话还是别的东西，
 * 由 `getInternalLinkType` 说，而不是由这里猜 —— 这里的每一条规则只在
 * 「省一次 IPC」的意义上存在，规则错了最坏结果也只是多问一次 TDLib。
 *
 * 因此本文件刻意**不做**：用户名长度/字符集校验、`joinchat`/`proxy`/`+hash` 形态区分、
 * `/c/<id>` 内部 id 反解 —— 那些都在 `getInternalLinkType` 的答案里，重复一遍就是两套真相。
 */

/**
 * TGX `TdConstants.TME_HOSTS`（`vkryl/td/.../TdConstants.kt:52`）逐条照抄：
 * `t.me`、`tx.me`（大陆镜像）、`telegram.me`、`telegram.dog`。
 * `telegram.org` 在 TGX 是另一档 `TELEGRAM_HOSTS`，只在 `allowTelegraph` 时才认，
 * 那是 Telegraph 文章而不是深链，本端不收 —— 收了就会把一堆普通文章链接送去 TDLib 问一遍。
 */
export const TELEGRAM_LINK_HOSTS: readonly string[] = ['t.me', 'tx.me', 'telegram.me', 'telegram.dog'];

/** 自定义 scheme：`tg:` 是官方深链，`telegram:` 是老客户端遗留写法。 */
export const TELEGRAM_LINK_SCHEMES: readonly string[] = ['tg', 'telegram'];

/** 去协议裸链接（`t.me/durov`）补协议时用，与 Android `Strings.wrapHttps` 同义。 */
const HTTP_SCHEME: string = 'https';

/**
 * URI 的粗切分结果。**不是** URL 解析器：只拆到判定所需的四段，
 * 不做百分号解码、不校验端口、不处理 userinfo。
 */
export interface UriParts {
  /** 小写 scheme；无协议（`t.me/x`）时为 `''`。 */
  readonly scheme: string;
  /** 小写 authority（含端口原样）；无 authority 时为 `''`。 */
  readonly host: string;
  /** host 之后的 path（不含 `?`/`#`），可为 `''`。 */
  readonly path: string;
  /** `?` 之后、`#` 之前的原始 query；无则 `''`。 */
  readonly query: string;
}

/** 去掉端口与尾部点（`www.t.me.:443` → `www.t.me`）。 */
function normalizeHost(authority: string): string {
  const withoutPort: string = authority.split(':')[0];
  return withoutPort.endsWith('.') ? withoutPort.substring(0, withoutPort.length - 1) : withoutPort;
}

/** 粗切分 URI。`tg:settings`（无 `//`）落在 path 上，与 `RouteCodec.parseDeepLink` 口径一致。 */
export function splitUri(uri: string): UriParts {
  const trimmed: string = uri.trim();
  const schemeIdx: number = trimmed.indexOf(':');
  let scheme: string = '';
  let rest: string = trimmed;
  if (schemeIdx > 0 && /^[a-zA-Z][a-zA-Z0-9+.-]*$/.test(trimmed.substring(0, schemeIdx))) {
    scheme = trimmed.substring(0, schemeIdx).toLowerCase();
    rest = trimmed.substring(schemeIdx + 1);
  }
  let host: string = '';
  let pathAndQuery: string = rest;
  if (scheme === '' && !rest.startsWith('//')) {
    // 去协议裸链接 `t.me/durov`：第一段就是 authority，否则 host 恒为空、
    // isTelegramLinkCandidate 会把它判成「不是 Telegram 链接」。
    rest = `//${rest}`;
  }
  if (rest.startsWith('//')) {
    const authorityAndPath: string = rest.substring(2);
    const slashIdx: number = authorityAndPath.indexOf('/');
    if (slashIdx < 0) {
      host = authorityAndPath.toLowerCase();
      pathAndQuery = '';
    } else {
      host = authorityAndPath.substring(0, slashIdx).toLowerCase();
      pathAndQuery = authorityAndPath.substring(slashIdx + 1);
    }
  }
  const fragmentIdx: number = pathAndQuery.indexOf('#');
  const withoutFragment: string = fragmentIdx < 0 ? pathAndQuery : pathAndQuery.substring(0, fragmentIdx);
  const queryIdx: number = withoutFragment.indexOf('?');
  const path: string = queryIdx < 0 ? withoutFragment : withoutFragment.substring(0, queryIdx);
  const query: string = queryIdx < 0 ? '' : withoutFragment.substring(queryIdx + 1);
  return { scheme: scheme, host: normalizeHost(host), path: path, query: query };
}

function hostIsTelegram(host: string): boolean {
  for (let i: number = 0; i < TELEGRAM_LINK_HOSTS.length; i++) {
    const known: string = TELEGRAM_LINK_HOSTS[i];
    // `endsWith('.' + known)` 收的是 `username.t.me` 这类子域形态，
    // 与 Android `isKnownHost` 的 `host.endsWith("." + knownHost)` 同一条。
    if (host === known || host.endsWith(`.${known}`)) {
      return true;
    }
  }
  return false;
}

/**
 * 「这条链接值不值得去问 TDLib」。判据只有 scheme 与 host 两样，**不看 path**：
 * `t.me/s/durov`、`t.me/+abc`、`t.me/proxy?...` 都算候选，具体是会话、邀请还是代理，
 * 由 `getInternalLinkType` 回答。
 */
export function isTelegramLinkCandidate(uri: string): boolean {
  if (uri.trim().length === 0) {
    return false;
  }
  const parts: UriParts = splitUri(uri);
  if (parts.scheme === '') {
    // 裸 `t.me/x`：只有 host 落在已知集里才算，否则一句「durov」也会被判成链接。
    return hostIsTelegram(parts.host);
  }
  if (TELEGRAM_LINK_SCHEMES.indexOf(parts.scheme) >= 0) {
    return true;
  }
  if (parts.scheme === 'http' || parts.scheme === 'https') {
    return hostIsTelegram(parts.host);
  }
  return false;
}

/**
 * 送进 `getInternalLinkType` 前的两步归一：
 * 1. 裸链接补 `https://`（Android `Strings.wrapHttps`）；
 * 2. `username.t.me/path` 改写为 `t.me/username/path`
 * （Android `TdlibUi.preProcessTelegramUrl:3448-3477` —— TDLib 不认子域形态的公开链接，
 * 不改写就会得到 `unknownDeepLink`，于是这些链接在应用内悄悄失效）。
 *
 * 子域改写只在 host 确实是「已知 host 的**一层**子域」时进行：`www.t.me` 不是用户名，
 * 改写它反而造出 `t.me/www` 这么个假链接。
 */
export function normalizeTelegramLink(uri: string): string {
  const trimmed: string = uri.trim();
  if (trimmed.length === 0) {
    return trimmed;
  }
  const absolute: string = withScheme(trimmed);
  const parts: UriParts = splitUri(absolute);
  if (parts.scheme !== 'http' && parts.scheme !== 'https') {
    return absolute;
  }
  const rewritten: string | null = rewriteSubdomainAuthority(parts);
  if (rewritten === null) {
    return absolute;
  }
  const tail: string = parts.query.length === 0 ? '' : `?${parts.query}`;
  return `${parts.scheme}://${rewritten}${tail}`;
}

/** 无协议时补 `https://`；已有协议的原样返回。 */
function withScheme(uri: string): string {
  if (uri.indexOf('://') >= 0 || /^[a-zA-Z][a-zA-Z0-9+.-]*:/.test(uri)) {
    return uri;
  }
  return `${HTTP_SCHEME}://${uri}`;
}

/** `username.t.me/durov` → `t.me/username/durov`；不是子域形态则返回 null。 */
function rewriteSubdomainAuthority(parts: UriParts): string | null {
  const dotIdx: number = parts.host.indexOf('.');
  if (dotIdx <= 0) {
    return null;
  }
  const subdomain: string = parts.host.substring(0, dotIdx);
  const parent: string = parts.host.substring(dotIdx + 1);
  if (TELEGRAM_LINK_HOSTS.indexOf(parent) < 0) {
    return null;
  }
  // `www.t.me`、`m.t.me` 这类是站点别名而不是用户名，留给 TDLib 自己去判。
  if (subdomain === 'www' || subdomain === 'm') {
    return null;
  }
  const pathPart: string = parts.path === '' ? '' : `/${parts.path}`;
  return `${parent}/${subdomain}${pathPart}`;
}
