/**
 * feature/settings — 网络代理模型（PROXY-101 / FEAT-P2-007 代理部分）。
 *
 * TDLib 侧是 `addedProxy`（id + `proxy` + is_enabled + comment），页面上是
 * Telegram 那种「一行一个代理 + 单选启用」。这里做两端都纯的映射：
 * - `proxyItemFromAdded`：把 TDLib 对象投影成页面行，识别不出代理类型时返回 null
 *   （宁可少一行，也不要用空壳冒充一个可用代理）；
 * - `proxyValueFromForm`：表单 → `proxy` 负载，类型分支与字段裁剪只此一处；
 * - `proxyFormError`：表单校验，返回 Lang key（不是成品文案），模型层零 Kit /
 *   零 Lang 依赖，单测可直接断言。
 */

import {
  AddedProxy,
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
  const value: ProxyValue = new ProxyValue();
  value.server = form.server.trim();
  value.port = proxyPortOf(form.portInput);
  if (form.kind === 'mtproto') {
    const mtproto: ProxyTypeMtproto = new ProxyTypeMtproto();
    mtproto.secret = form.secret.trim();
    value.type_ = mtproto;
    return value;
  }
  if (form.kind === 'http') {
    const http: ProxyTypeHttp = new ProxyTypeHttp();
    http.username = form.username.trim();
    http.password = form.password;
    // 开关名与 TDLib 字段同名同义（关闭 = 允许透明 TCP 转发），默认关。
    http.http_only = form.httpOnly;
    value.type_ = http;
    return value;
  }
  const socks5: ProxyTypeSocks5 = new ProxyTypeSocks5();
  socks5.username = form.username.trim();
  socks5.password = form.password;
  value.type_ = socks5;
  return value;
}
