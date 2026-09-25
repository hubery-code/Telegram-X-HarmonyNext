/**
 * feature/settings — 网络代理模型（PROXY-101 / FEAT-P2-007 代理部分，
 * PROXY-102 补连通性探测与连接态）。
 *
 * TDLib 侧是 `addedProxy`（id + `proxy` + is_enabled + comment），页面上是
 * Telegram 那种「一行一个代理 + 单选启用」。这里做两端都纯的映射：
 * - `proxyItemFromAdded`：把 TDLib 对象投影成页面行，识别不出代理类型时返回 null
 *   （宁可少一行，也不要用空壳冒充一个可用代理）；
 * - `proxyValueFromForm`：表单 → `proxy` 负载，类型分支与字段裁剪只此一处；
 * - `proxyFormError`：表单校验，返回 Lang key（不是成品文案），模型层零 Kit /
 *   零 Lang 依赖，单测可直接断言。
 *
 * 探测部分同样只留纯逻辑：`proxyStatusOf` 给的是 Lang key，延迟单独成尾巴；
 * `proxyRowConnection` 负责「只有当前生效的那条路才配拿连接态」这条门。
 */

import {
  AddedProxy,
  PingProxy,
  ProxyTypeHttp,
  ProxyTypeMtproto,
  ProxyTypeSocks5,
  ProxyValue,
  TdProxyType
} from '@tgx/core-td-api-generated';

export type ProxyKind = 'socks5' | 'http' | 'mtproto';

/** 「不使用代理」这一行的哨兵 id；TDLib 分配的真实 id 恒为正数。 */
export const PROXY_NONE_ID: number = 0;
/** 新增表单的 id 占位：TDLib 还没分配，写回走 addProxy。 */
export const PROXY_NEW_ID: number = -1;

/** 列表里的一行：既是展示投影，也是编辑回填的数据源。 */
export class ProxyItem {
  readonly id: number;
  readonly kind: ProxyKind;
  readonly server: string;
  readonly port: number;
  readonly username: string;
  readonly password: string;
  readonly secret: string;
  readonly httpOnly: boolean;
  readonly comment: string;
  readonly isEnabled: boolean;

  constructor(
    id: number,
    kind: ProxyKind,
    server: string,
    port: number,
    username: string,
    password: string,
    secret: string,
    httpOnly: boolean,
    comment: string,
    isEnabled: boolean
  ) {
    this.id = id;
    this.kind = kind;
    this.server = server;
    this.port = port;
    this.username = username;
    this.password = password;
    this.secret = secret;
    this.httpOnly = httpOnly;
    this.comment = comment;
    this.isEnabled = isEnabled;
  }

  withEnabled(isEnabled: boolean): ProxyItem {
    if (this.isEnabled === isEnabled) {
      return this;
    }
    return new ProxyItem(
      this.id, this.kind, this.server, this.port, this.username,
      this.password, this.secret, this.httpOnly, this.comment, isEnabled
    );
  }
}

/** 添加/编辑表单的当前值；`portInput` 保留输入框原文，不把非法值偷偷当 0。 */
export class ProxyForm {
  /** `PROXY_NEW_ID` 表示新增，其余为被编辑行的 TDLib id。 */
  readonly id: number;
  readonly kind: ProxyKind;
  readonly server: string;
  readonly portInput: string;
  readonly username: string;
  readonly password: string;
  readonly secret: string;
  readonly httpOnly: boolean;
  readonly comment: string;
  readonly enable: boolean;

  constructor(
    id: number,
    kind: ProxyKind,
    server: string,
    portInput: string,
    username: string,
    password: string,
    secret: string,
    httpOnly: boolean,
    comment: string,
    enable: boolean
  ) {
    this.id = id;
    this.kind = kind;
    this.server = server;
    this.portInput = portInput;
    this.username = username;
    this.password = password;
    this.secret = secret;
    this.httpOnly = httpOnly;
    this.comment = comment;
    this.enable = enable;
  }
}

/** 编辑回填：一行 → 表单初值。 */
export function proxyFormFromItem(item: ProxyItem): ProxyForm {
  return new ProxyForm(
    item.id, item.kind, item.server, String(item.port), item.username,
    item.password, item.secret, item.httpOnly, item.comment, item.isEnabled
  );
}

/** 新增初值：TGX 的默认档是 SOCKS5，且默认「保存后立即启用」。 */
export function emptyProxyForm(): ProxyForm {
  return new ProxyForm(PROXY_NEW_ID, 'socks5', '', '', '', '', '', false, '', true);
}

export function proxyKindLabel(kind: ProxyKind): string {
  if (kind === 'http') {
    return 'HTTP';
  }
  if (kind === 'mtproto') {
    return 'MTProto';
  }
  return 'SOCKS5';
}

/**
 * 行标题：用户写过备注就用备注，否则直接给「地址:端口」。
 * 类型名留给副标题，标题里再重复一遍只会在窄屏上把地址挤成省略号。
 */
export function proxyTitle(item: ProxyItem): string {
  const comment: string = item.comment.trim();
  if (comment.length > 0) {
    return comment;
  }
  return proxyAddress(item);
}

/** 行副标题：备注让位后把「地址 + 端口」补回来。 */
export function proxyAddress(item: ProxyItem): string {
  return `${item.server}:${item.port}`;
}

export function proxyEnabledItem(items: readonly ProxyItem[]): ProxyItem | null {
  for (let i = 0; i < items.length; i++) {
    if (items[i].isEnabled) {
      return items[i];
    }
  }
  return null;
}

/** 启用的代理条数；TDLib 保证至多一条，日志里非 1 即异常信号。 */
export function proxyEnabledCount(items: readonly ProxyItem[]): number {
  let count: number = 0;
  for (let i = 0; i < items.length; i++) {
    if (items[i].isEnabled) {
      count = count + 1;
    }
  }
  return count;
}

/**
 * 设置主页「代理」行的副标题（TGX `SettingsDataController` 同规则）：
 * 一个都没有 → 「点按设置」；有但没启用 → 「已停用」；否则直接显示启用的那个。
 */
export function proxyRowSummary(items: readonly ProxyItem[]): string {
  if (items.length === 0) {
    return 'Tap to set up';
  }
  const enabled: ProxyItem | null = proxyEnabledItem(items);
  if (enabled === null) {
    return 'Proxy Disabled';
  }
  return proxyTitle(enabled);
}

/** 解析端口输入；非整数或越界返回 0（0 不是合法端口，可当失败值用）。 */
export function proxyPortOf(portInput: string): number {
  const raw: string = portInput.trim();
  if (raw.length === 0 || raw.length > 5) {
    return 0;
  }
  for (let i = 0; i < raw.length; i++) {
    if (raw.charAt(i) < '0' || raw.charAt(i) > '9') {
      return 0;
    }
  }
  const port: number = Number(raw);
  if (port < 1 || port > 65535) {
    return 0;
  }
  return port;
}

/** MTProto 的 secret 是十六进制编码的字节串：只能出现 hex 字符，且长度为偶数。 */
export function isMtprotoSecretValid(secret: string): boolean {
  const raw: string = secret.trim();
  if (raw.length === 0 || raw.length % 2 !== 0) {
    return false;
  }
  const hex: string = '0123456789abcdefABCDEF';
  for (let i = 0; i < raw.length; i++) {
    if (hex.indexOf(raw.charAt(i)) === -1) {
      return false;
    }
  }
  return true;
}

/**
 * 表单首个校验失败的 Lang key；'' 表示可以提交。
 * 顺序与页面上字段的上下顺序一致，用户先看到最靠上的那个错误。
 */
export function proxyFormError(form: ProxyForm): string {
  if (form.server.trim().length === 0) {
    return 'Server address required';
  }
  if (proxyPortOf(form.portInput) === 0) {
    return 'Port must be 1-65535';
  }
  if (form.kind === 'mtproto' && !isMtprotoSecretValid(form.secret)) {
    return 'Secret must be hexadecimal';
  }
  return '';
}

export function isProxyFormValid(form: ProxyForm): boolean {
  return proxyFormError(form) === '';
}

/** SOCKS5 / HTTP 才有账号密码；MTProto 只有 secret。 */
export function proxyFormHasCredentials(kind: ProxyKind): boolean {
  return kind === 'socks5' || kind === 'http';
}

function proxyKindOfType(type: string): ProxyKind | null {
  if (type === 'proxyTypeSocks5') {
    return 'socks5';
  }
  if (type === 'proxyTypeHttp') {
    return 'http';
  }
  if (type === 'proxyTypeMtproto') {
    return 'mtproto';
  }
  return null;
}

/** TDLib `addedProxy` → 页面行；类型或地址缺失时返回 null。 */
export function proxyItemFromAdded(added: AddedProxy): ProxyItem | null {
  const value: ProxyValue | null = added.proxy;
  if (value === null || value.server.length === 0) {
    return null;
  }
  const proxyType: TdProxyType | null = value.type_;
  if (proxyType === null) {
    return null;
  }
  const kind: ProxyKind | null = proxyKindOfType(proxyType.type);
  if (kind === null) {
    return null;
  }
  let username: string = '';
  let password: string = '';
  let secret: string = '';
  let httpOnly: boolean = false;
  if (kind === 'socks5') {
    const socks5: ProxyTypeSocks5 = proxyType as ProxyTypeSocks5;
    username = socks5.username;
    password = socks5.password;
  } else if (kind === 'http') {
    const http: ProxyTypeHttp = proxyType as ProxyTypeHttp;
    username = http.username;
    password = http.password;
    httpOnly = http.http_only;
  } else {
    secret = (proxyType as ProxyTypeMtproto).secret;
  }
  return new ProxyItem(
    added.id, kind, value.server, value.port, username, password,
    secret, httpOnly, added.comment, added.is_enabled
  );
}

/** 表单 → TDLib `proxy` 负载；调用方需先过 `isProxyFormValid`。 */
export function proxyValueFromForm(form: ProxyForm): ProxyValue {
  return proxyValueOf(
    form.kind, form.server.trim(), proxyPortOf(form.portInput),
    form.username.trim(), form.password, form.secret.trim(), form.httpOnly
  );
}

/**
 * 列表行 → TDLib `proxy` 负载：`pingProxy` 收的是代理对象而不是 id，所以探测要能
 * 从已读到的行把负载还原出来。与表单共用一个构造器，类型分支只此一处。
 */
export function proxyValueFromItem(item: ProxyItem): ProxyValue {
  return proxyValueOf(
    item.kind, item.server, item.port,
    item.username, item.password, item.secret, item.httpOnly
  );
}

function proxyValueOf(
  kind: ProxyKind,
  server: string,
  port: number,
  username: string,
  password: string,
  secret: string,
  httpOnly: boolean
): ProxyValue {
  const value: ProxyValue = new ProxyValue();
  value.server = server;
  value.port = port;
  if (kind === 'mtproto') {
    const mtproto: ProxyTypeMtproto = new ProxyTypeMtproto();
    mtproto.secret = secret;
    value.type_ = mtproto;
    return value;
  }
  if (kind === 'http') {
    const http: ProxyTypeHttp = new ProxyTypeHttp();
    http.username = username;
    http.password = password;
    // 开关名与 TDLib 字段同名同义（关闭 = 允许透明 TCP 转发），默认关。
    http.http_only = httpOnly;
    value.type_ = http;
    return value;
  }
  const socks5: ProxyTypeSocks5 = new ProxyTypeSocks5();
  socks5.username = username;
  socks5.password = password;
  value.type_ = socks5;
  return value;
}

// ---- PROXY-102 连通性探测与连接态 ----

/** 还没探测过。 */
export const PROXY_PING_UNSET: number = -1;
/** 探测在途；页面上这一行显示「Checking…」。 */
export const PROXY_PING_LOADING: number = -2;
/** 探测失败（TDLib 回了错误，或延迟不是正数）。 */
export const PROXY_PING_FAILED: number = -3;

/**
 * TDLib `updateConnectionState` 的五个档，外加一个「这一行不归连接态管」的哨兵。
 * 用字符串而不是数字：与 `ProxyKind` 同风格，单测里断言的是能读出来的词。
 */
export type ProxyConnectionState =
  'unknown' | 'waiting_for_network' | 'connecting_to_proxy' | 'connecting' | 'updating' | 'ready';

/** 连接态 `@type` → 页面档；认不出的按 'unknown'（宁可少一句话，也不编一个状态出来）。 */
export function proxyConnectionStateOfType(type: string): ProxyConnectionState {
  if (type === 'connectionStateWaitingForNetwork') {
    return 'waiting_for_network';
  }
  if (type === 'connectionStateConnectingToProxy') {
    return 'connecting_to_proxy';
  }
  if (type === 'connectionStateConnecting') {
    return 'connecting';
  }
  if (type === 'connectionStateUpdating') {
    return 'updating';
  }
  if (type === 'connectionStateReady') {
    return 'ready';
  }
  return 'unknown';
}

/** `Seconds` → 毫秒（TGX 同规则 `Math.round(seconds * 1000)`）；非正数或不是有限数都算失败。 */
export function proxyPingMsOfSeconds(seconds: number): number {
  if (!Number.isFinite(seconds) || seconds <= 0) {
    return PROXY_PING_FAILED;
  }
  return Math.round(seconds * 1000);
}

/**
 * 这一行是不是「正在承载流量」的那条路。TDLib 只有一条连接，`updateConnectionState`
 * 说的是它，不是每一行：代理开着的时候，「不使用代理」那一行的直连探测再快也不是连接态。
 * `item === null` 即「不使用代理」行。
 */
export function proxyRowIsEffective(items: readonly ProxyItem[], item: ProxyItem | null): boolean {
  if (item === null) {
    return proxyEnabledItem(items) === null;
  }
  return item.isEnabled;
}

/** 一行状态：`key` 是 Lang key，'' 表示这句不说；`pingMs` 只在带延迟时有值。 */
export class ProxyStatus {
  readonly key: string;
  readonly pingMs: number;

  constructor(key: string, pingMs: number) {
    this.key = key;
    this.pingMs = pingMs;
  }
}

/**
 * 行状态文案（TGX `SettingsProxyController.getState()` 同规则，去掉本端没有的分支）。
 * 生效行以连接态为主，顺序照 Android：连上了 → Connected；探测在途 → Checking…；
 * 然后是三个进行中的连接档；连接态一句话都说不出来时（'unknown'）才退回探测结果。
 * 非生效行只有探测结果可说：通了是 Available，不通是 Error —— 而「不使用代理」那一行
 * 说 Problems detected，因为它没有代理可怪。
 *
 * 没建模的两项：错误详情（Android 的 `Error (code: message)` 要展示 TDLib 错误原文）、
 * 多路比较出来的「best」徽标（那是自动切路的事）。
 */
export function proxyStatusOf(
  item: ProxyItem | null,
  pingMs: number,
  effective: boolean,
  connection: ProxyConnectionState
): ProxyStatus {
  const failedKey: string = item === null ? 'Problems detected' : 'Error';
  if (effective) {
    if (connection === 'ready') {
      return new ProxyStatus('Connected', pingMs > 0 ? pingMs : PROXY_PING_UNSET);
    }
    if (pingMs === PROXY_PING_LOADING) {
      return new ProxyStatus('Checking...', PROXY_PING_UNSET);
    }
    if (connection === 'waiting_for_network') {
      return new ProxyStatus('Waiting for network...', PROXY_PING_UNSET);
    }
    if (connection === 'updating') {
      return new ProxyStatus('Updating...', PROXY_PING_UNSET);
    }
    if (connection === 'connecting' || connection === 'connecting_to_proxy') {
      return new ProxyStatus('Connecting...', PROXY_PING_UNSET);
    }
    if (pingMs === PROXY_PING_FAILED) {
      return new ProxyStatus(failedKey, PROXY_PING_UNSET);
    }
    if (pingMs > 0) {
      return new ProxyStatus('Connected', pingMs);
    }
    return new ProxyStatus('', PROXY_PING_UNSET);
  }
  if (pingMs === PROXY_PING_LOADING) {
    return new ProxyStatus('Checking...', PROXY_PING_UNSET);
  }
  if (pingMs === PROXY_PING_FAILED) {
    return new ProxyStatus(failedKey, PROXY_PING_UNSET);
  }
  if (pingMs > 0) {
    return new ProxyStatus('Available', pingMs);
  }
  return new ProxyStatus('', PROXY_PING_UNSET);
}

/** 延迟尾巴；数字不进句子，免得翻译时词序被绑死。 */
export function proxyPingSuffix(pingMs: number): string {
  if (pingMs <= 0) {
    return '';
  }
  return ` · ${pingMs} ms`;
}

/** 读出某一行当前的探测结果；没测过就是 UNSET（页面据此决定这一行说什么）。 */
export function proxyPingOf(pings: Map<number, number>, proxyId: number): number {
  const value: number | undefined = pings.get(proxyId);
  return value === undefined ? PROXY_PING_UNSET : value;
}

/** 写入某一行的探测结果；恒返回新 Map，状态不可变。 */
export function proxyPingsWith(pings: Map<number, number>, proxyId: number, pingMs: number): Map<number, number> {
  const next: Map<number, number> = new Map();
  pings.forEach((value: number, key: number): void => {
    next.set(key, value);
  });
  next.set(proxyId, pingMs);
  return next;
}

/**
 * 列表重建后留下的探测结果：删掉已经不存在的行，保住「不使用代理」那一行（0）。
 * 保住还在的那些是重点 —— 每写一次代理都要回读列表，探测在途时不能被这次重建抹掉。
 */
export function proxyPingsPrunedTo(pings: Map<number, number>, items: readonly ProxyItem[]): Map<number, number> {
  const alive: Set<number> = new Set();
  alive.add(PROXY_NONE_ID);
  for (let i = 0; i < items.length; i++) {
    alive.add(items[i].id);
  }
  const next: Map<number, number> = new Map();
  pings.forEach((value: number, key: number): void => {
    if (alive.has(key)) {
      next.set(key, value);
    }
  });
  return next;
}

/**
 * 探测请求负载。`item === null` 是「不使用代理」行 —— 按 TDLib 语义发空 proxy，
 * 即「绕过代理直连测一次」，因此这一行在没有配任何代理时也可证。
 */
export function pingProxyRequestFromItem(item: ProxyItem | null): PingProxy {
  const request: PingProxy = new PingProxy();
  if (item !== null) {
    request.proxy = proxyValueFromItem(item);
  }
  return request;
}
