/**
 * core/navigation — RouteCodec：参数编解码与 deep link 解析（UI-002）。
 *
 * - parse(path)：path → 类型化 AppRoute；缺失必填、类型错误、越界、未知路由、
 *   未知参数一律返回 Err(AppError)，不抛异常；
 * - encode(route)：AppRoute → path（模板参数内联、可选参数进 query string）；
 * - parseDeepLink(uri, rules)：外部 URI → AppRoute，未知 scheme/host、非法参数
 *   安全拒绝（Err）。
 *
 * 编解码规则：所有参数值经 encodeURIComponent，path 中因此不会出现
 * '/'、'?'、'&'、'#'、换行等结构字符；解码前先校验百分号编码合法性，
 * 避免依赖 decodeURIComponent 的异常。
 */

import { AppErrors } from '@tgx/core-common';
import { ok, err } from '@tgx/core-common';
import type { Result, AppError } from '@tgx/core-common';
import {
  AppRoute,
  AuthRoute,
  ChatInfoRoute,
  UserProfileRoute,
  ContactsRoute,
  SelfProfileRoute,
  ChatRoute,
  HomeRoute,
  MediaViewerRoute,
  CommentsRoute,
  ParamSpec,
  ParamValue,
  RouteDefinition,
  RouteName,
  SearchRoute,
  SettingsRoute,
  SettingsSectionRoute
} from './Route';
import { RouteRegistry, templateMatches } from './RouteRegistry';

const INT_PATTERN: RegExp = /^-?[0-9]+$/;
const SCHEME_PATTERN: RegExp = /^[a-zA-Z][a-zA-Z0-9+.-]*$/;
/** 非法百分号编码：'%' 后不是两位十六进制。 */
const BAD_PERCENT_PATTERN: RegExp = /%(?![0-9A-Fa-f]{2})/;

export class RouteCodec {
  private readonly registry: RouteRegistry;

  constructor(registry: RouteRegistry) {
    this.registry = registry;
  }

  // ---------- parse ----------

  /**
   * path → 类型化 route。
   * path 形如 'chat/123' 或 'chat/123?threadId=5'，可有至多一个前导 '/'。
   */
  parse(path: string): Result<AppRoute, AppError> {
    const trimmed: string = path.startsWith('/') ? path.substring(1) : path;
    if (trimmed.length === 0) {
      return err(AppErrors.parameter('missing', 'path', 'empty path'));
    }
    const queryIdx: number = trimmed.indexOf('?');
    const pathPart: string = queryIdx < 0 ? trimmed : trimmed.substring(0, queryIdx);
    const queryPart: string = queryIdx < 0 ? '' : trimmed.substring(queryIdx + 1);

    if (pathPart.length === 0) {
      return err(AppErrors.parameter('missing', 'path', 'empty path segments'));
    }
    const segments: string[] = pathPart.split('/');
    for (let i: number = 0; i < segments.length; i++) {
      if (segments[i].length === 0) {
        return err(AppErrors.parameter('invalid', 'path', `empty path segment: ${path}`));
      }
    }

    const def: RouteDefinition | null = this.registry.findByPath(pathPart);
    if (def === null) {
      return err(AppErrors.parameter('invalid', 'route', `unknown route: ${pathPart}`));
    }

    const raw: Map<string, string> = new Map<string, string>();
    const extracted: Result<void, AppError> = extractTemplateParams(def.pathTemplate, segments, raw);
    if (extracted.ok === false) {
      return err(extracted.error);
    }

    const queryResult: Result<void, AppError> = parseQuery(queryPart, raw);
    if (queryResult.ok === false) {
      return err(queryResult.error);
    }

    const unknownParam: string | null = rejectUnknownParams(def, raw);
    if (unknownParam !== null) {
      return err(AppErrors.parameter('invalid', unknownParam, `unknown parameter for route ${def.name}: ${unknownParam}`));
    }

    return this.buildFromParams(def, raw);
  }

  // ---------- encode ----------

  /** route → path。路由值来自类型化对象，非法值（如 NaN）同样返回 Err。 */
  encode(route: AppRoute): Result<string, AppError> {
    const def: RouteDefinition | null = this.registry.find(route.name);
    if (def === null) {
      return err(AppErrors.internal('route.notRegistered', `route not registered: ${route.name}`));
    }
    const values: Map<string, ParamValue> = new Map<string, ParamValue>();
    const collected: Result<void, AppError> = collectRouteParams(route, values);
    if (collected.ok === false) {
      return err(collected.error);
    }

    const inTemplate: Map<string, boolean> = new Map<string, boolean>();
    const templateSegments: string[] = def.pathTemplate.split('/');
    const outSegments: string[] = [];
    for (let i: number = 0; i < templateSegments.length; i++) {
      const segment: string = templateSegments[i];
      if (segment.startsWith('{') && segment.endsWith('}')) {
        const paramName: string = segment.substring(1, segment.length - 1);
        inTemplate.set(paramName, true);
        const value: ParamValue | undefined = values.get(paramName);
        if (value === undefined) {
          return err(AppErrors.parameter('missing', paramName, `template parameter missing on route object: ${paramName}`));
        }
        outSegments.push(encodeURIComponent(stringifyValue(value)));
      } else {
        outSegments.push(segment);
      }
    }

    let out: string = outSegments.join('/');
    const queryParts: string[] = [];
    for (let i: number = 0; i < def.params.length; i++) {
      const paramName: string = def.params[i].name;
      if (inTemplate.get(paramName) === true) {
        continue;
      }
      const value: ParamValue | undefined = values.get(paramName);
      if (value !== undefined) {
        queryParts.push(`${encodeURIComponent(paramName)}=${encodeURIComponent(stringifyValue(value))}`);
      }
    }
    if (queryParts.length > 0) {
      out = `${out}?${queryParts.join('&')}`;
    }
    return ok(out);
  }

  // ---------- deep link ----------

  /**
   * 外部 URI → 类型化 route。
   * rules 为白名单规则（见 defaultDeepLinkRules）：scheme/host 不在表内、
   * path 与模板不匹配、映射后参数缺失或非法，均安全拒绝；
   * 未映射的 query 参数被忽略（外部 URI 常携带无关参数）。
   */
  parseDeepLink(uri: string, rules: DeepLinkRule[]): Result<AppRoute, AppError> {
    const schemeIdx: number = uri.indexOf(':');
    if (schemeIdx <= 0) {
      return err(AppErrors.parameter('invalid', 'deepLink', `missing URI scheme: ${uri}`));
    }
    const scheme: string = uri.substring(0, schemeIdx);
    if (!SCHEME_PATTERN.test(scheme)) {
      return err(AppErrors.parameter('invalid', 'scheme', `illegal URI scheme: ${scheme}`));
    }
    let rest: string = uri.substring(schemeIdx + 1);
    const fragmentIdx: number = rest.indexOf('#');
    if (fragmentIdx >= 0) {
      rest = rest.substring(0, fragmentIdx);
    }
    const queryIdx: number = rest.indexOf('?');
    const beforeQuery: string = queryIdx < 0 ? rest : rest.substring(0, queryIdx);
    const queryPart: string = queryIdx < 0 ? '' : rest.substring(queryIdx + 1);

    let host: string = '';
    let linkPath: string = '';
    if (beforeQuery.startsWith('//')) {
      const authorityAndPath: string = beforeQuery.substring(2);
      const slashIdx: number = authorityAndPath.indexOf('/');
      if (slashIdx < 0) {
        host = authorityAndPath.toLowerCase();
      } else {
        host = authorityAndPath.substring(0, slashIdx).toLowerCase();
        linkPath = authorityAndPath.substring(slashIdx + 1);
      }
    } else {
      linkPath = beforeQuery;
    }

    for (let i: number = 0; i < rules.length; i++) {
      const rule: DeepLinkRule = rules[i];
      if (rule.scheme !== scheme || rule.host !== host) {
        continue;
      }
      const pathSegments: string[] = linkPath.length === 0 ? [] : linkPath.split('/');
      let raw: Map<string, string> = new Map<string, string>();
      if (rule.pathTemplate !== undefined) {
        if (!templateMatches(rule.pathTemplate, pathSegments)) {
          continue;
        }
        const extracted: Result<void, AppError> = extractTemplateParams(rule.pathTemplate, pathSegments, raw);
        if (extracted.ok === false) {
          return err(extracted.error);
        }
      } else if (pathSegments.length > 0) {
        continue;
      }
      const mapped: Result<Map<string, string>, AppError> = mapQueryParams(rule, queryPart, raw);
      if (mapped.ok === false) {
        return err(mapped.error);
      }
      raw = mapped.value;
      const def: RouteDefinition | null = this.registry.find(rule.route);
      if (def === null) {
        return err(AppErrors.internal('route.notRegistered', `deep link rule points to unregistered route: ${rule.route}`));
      }
      return this.buildFromParams(def, raw);
    }
    return err(AppErrors.parameter('invalid', 'deepLink', `no deep link rule matches: ${scheme}://${host}/${linkPath}`));
  }

  // ---------- 参数校验 + 构造 ----------

  /** 校验原始字符串参数并按 schema 转成类型值，再构造 discriminated union 成员。 */
  buildFromParams(def: RouteDefinition, raw: Map<string, string>): Result<AppRoute, AppError> {
    const validated: Map<string, ParamValue> = new Map<string, ParamValue>();
    for (let i: number = 0; i < def.params.length; i++) {
      const spec: ParamSpec = def.params[i];
      const value: string | undefined = raw.get(spec.name);
      if (value === undefined) {
        if (spec.required) {
          return err(AppErrors.parameter('missing', spec.name, `missing required parameter: ${spec.name}`));
        }
        continue;
      }
      const converted: Result<ParamValue, AppError> = validateParam(spec, value);
      if (converted.ok === false) {
        return err(converted.error);
      }
      validated.set(spec.name, converted.value);
    }
    return buildRoute(def.name, validated);
  }
}

/** AppRoute 判别构造：新路由在此 switch 增加分支。 */
function buildRoute(name: RouteName, params: Map<string, ParamValue>): Result<AppRoute, AppError> {
  switch (name) {
    case 'home': {
      const route: HomeRoute = { name: 'home' };
      return ok(route);
    }
    case 'auth': {
      const route: AuthRoute = { name: 'auth' };
      return ok(route);
    }
    case 'chat': {
      const chatId: ParamValue | undefined = params.get('chatId');
      const threadId: ParamValue | undefined = params.get('threadId');
      const messageId: ParamValue | undefined = params.get('messageId');
      if (typeof chatId !== 'number') {
        return err(AppErrors.parameter('invalid', 'chatId', 'chatId must be int'));
      }
      if (threadId !== undefined && typeof threadId !== 'number') {
        return err(AppErrors.parameter('invalid', 'threadId', 'threadId must be int'));
      }
      // SEARCH-102：搜索结果携带的目标消息 id（可选，向后兼容既有 chat 路由）。
      if (messageId !== undefined && typeof messageId !== 'number') {
        return err(AppErrors.parameter('invalid', 'messageId', 'messageId must be int'));
      }
      if (threadId !== undefined || messageId !== undefined) {
        const route: ChatRoute = {
          name: 'chat',
          chatId: chatId,
          threadId: threadId as number | undefined,
          messageId: messageId as number | undefined
        };
        return ok(route);
      }
      const route: ChatRoute = { name: 'chat', chatId: chatId };
      return ok(route);
    }
    case 'chatInfo': {
      const chatId: ParamValue | undefined = params.get('chatId');
      if (typeof chatId !== 'number') {
        return err(AppErrors.parameter('invalid', 'chatId', 'chatId must be int'));
      }
      const route: ChatInfoRoute = { name: 'chatInfo', chatId: chatId };
      return ok(route);
    }
    case 'userProfile': {
      const userId: ParamValue | undefined = params.get('userId');
      if (typeof userId !== 'number') {
        return err(AppErrors.parameter('invalid', 'userId', 'userId must be int'));
      }
      const route: UserProfileRoute = { name: 'userProfile', userId: userId };
      return ok(route);
    }
    case 'contacts': {
      const route: ContactsRoute = { name: 'contacts' };
      return ok(route);
    }
    case 'selfProfile': {
      const route: SelfProfileRoute = { name: 'selfProfile' };
      return ok(route);
    }
    case 'settings': {
      const route: SettingsRoute = { name: 'settings' };
      return ok(route);
    }
    case 'settingsSection': {
      const section: ParamValue | undefined = params.get('section');
      if (typeof section !== 'string') {
        return err(AppErrors.parameter('invalid', 'section', 'section must be string'));
      }
      const route: SettingsSectionRoute = { name: 'settingsSection', section: section };
      return ok(route);
    }
    case 'search': {
      const query: ParamValue | undefined = params.get('query');
      if (query !== undefined) {
        if (typeof query !== 'string') {
          return err(AppErrors.parameter('invalid', 'query', 'query must be string'));
        }
        const route: SearchRoute = { name: 'search', query: query };
        return ok(route);
      }
      const route: SearchRoute = { name: 'search' };
      return ok(route);
    }
    case 'mediaViewer': {
      const chatId: ParamValue | undefined = params.get('chatId');
      const messageId: ParamValue | undefined = params.get('messageId');
      if (typeof chatId !== 'number') {
        return err(AppErrors.parameter('invalid', 'chatId', 'chatId must be int'));
      }
      if (typeof messageId !== 'number') {
        return err(AppErrors.parameter('invalid', 'messageId', 'messageId must be int'));
      }
      const route: MediaViewerRoute = { name: 'mediaViewer', chatId: chatId, messageId: messageId };
      return ok(route);
    }
    case 'comments': {
      const chatId: ParamValue | undefined = params.get('chatId');
      const messageId: ParamValue | undefined = params.get('messageId');
      if (typeof chatId !== 'number') {
        return err(AppErrors.parameter('invalid', 'chatId', 'chatId must be int'));
      }
      if (typeof messageId !== 'number') {
        return err(AppErrors.parameter('invalid', 'messageId', 'messageId must be int'));
      }
      const route: CommentsRoute = { name: 'comments', chatId: chatId, messageId: messageId };
      return ok(route);
    }
    default:
      return err(AppErrors.internal('route.unknownName', `no builder for route: ${name}`));
  }
}

function validateParam(spec: ParamSpec, raw: string): Result<ParamValue, AppError> {
  if (raw.length === 0) {
    return err(AppErrors.parameter('invalid', spec.name, `empty value for parameter: ${spec.name}`));
  }
  if (BAD_PERCENT_PATTERN.test(raw)) {
    return err(AppErrors.parameter('invalid', spec.name, `malformed percent-encoding in ${spec.name}`));
  }
  const decoded: string = decodeURIComponent(raw);
  switch (spec.type) {
    case 'int': {
      if (!INT_PATTERN.test(decoded)) {
        return err(AppErrors.parameter('invalid', spec.name, `not an integer: ${decoded}`));
      }
      const value: number = Number(decoded);
      if (!Number.isSafeInteger(value)) {
        return err(AppErrors.parameter('out_of_range', spec.name, `integer out of safe range: ${decoded}`));
      }
      if (spec.min !== undefined && value < spec.min) {
        return err(AppErrors.parameter('out_of_range', spec.name, `below min ${spec.min}: ${decoded}`));
      }
      if (spec.max !== undefined && value > spec.max) {
        return err(AppErrors.parameter('out_of_range', spec.name, `above max ${spec.max}: ${decoded}`));
      }
      return ok(value);
    }
    case 'boolean': {
      if (decoded === 'true') {
        return ok(true);
      }
      if (decoded === 'false') {
        return ok(false);
      }
      return err(AppErrors.parameter('invalid', spec.name, `not a boolean: ${decoded}`));
    }
    default: {
      if (spec.maxLength !== undefined && decoded.length > spec.maxLength) {
        return err(AppErrors.parameter('out_of_range', spec.name, `longer than maxLength ${spec.maxLength}`));
      }
      if (spec.pattern !== undefined && !spec.pattern.test(decoded)) {
        return err(AppErrors.parameter('invalid', spec.name, `pattern mismatch: ${decoded}`));
      }
      return ok(decoded);
    }
  }
}

/** route 对象的字段值收集到参数表（encode 用）。 */
function collectRouteParams(route: AppRoute, out: Map<string, ParamValue>): Result<void, AppError> {
  switch (route.name) {
    case 'home':
    case 'auth':
    case 'settings':
      return ok(undefined);
    case 'chat':
      out.set('chatId', route.chatId);
      if (route.threadId !== undefined) {
        out.set('threadId', route.threadId);
      }
      // SEARCH-102：带目标消息的会话路由（搜索结果跳转定位）编码为
      // chat/{id}?messageId=N，返回时仍可还原同一路由。
      if (route.messageId !== undefined) {
        out.set('messageId', route.messageId);
      }
      return ok(undefined);
    case 'chatInfo':
      out.set('chatId', route.chatId);
      return ok(undefined);
    case 'userProfile':
      out.set('userId', route.userId);
      return ok(undefined);
    case 'contacts':
    case 'selfProfile':
      return ok(undefined);
    case 'settingsSection':
      out.set('section', route.section);
      return ok(undefined);
    case 'search':
      if (route.query !== undefined) {
        out.set('query', route.query);
      }
      return ok(undefined);
    case 'mediaViewer':
      out.set('chatId', route.chatId);
      out.set('messageId', route.messageId);
      return ok(undefined);
    case 'comments':
      out.set('chatId', route.chatId);
      out.set('messageId', route.messageId);
      return ok(undefined);
    default:
      return err(AppErrors.internal('route.unknownName', 'no param collector for route (exhaustive switch miss)'));
  }
}

/** 从模板占位段提取（尚未解码的）参数。 */
function extractTemplateParams(
  template: string,
  pathSegments: string[],
  out: Map<string, string>
): Result<void, AppError> {
  const templateSegments: string[] = template.split('/');
  for (let i: number = 0; i < templateSegments.length; i++) {
    const t: string = templateSegments[i];
    if (t.startsWith('{') && t.endsWith('}')) {
      const paramName: string = t.substring(1, t.length - 1);
      const raw: string = pathSegments[i];
      if (BAD_PERCENT_PATTERN.test(raw)) {
        return err(AppErrors.parameter('invalid', paramName, `malformed percent-encoding in ${paramName}`));
      }
      out.set(paramName, decodeURIComponent(raw));
    }
  }
  return ok(undefined);
}

/** 解析 query string 并入 raw（重复 key 报错；query 值已解码）。 */
function parseQuery(queryPart: string, raw: Map<string, string>): Result<void, AppError> {
  if (queryPart.length === 0) {
    return ok(undefined);
  }
  const pairs: string[] = queryPart.split('&');
  for (let i: number = 0; i < pairs.length; i++) {
    const pair: string = pairs[i];
    if (pair.length === 0) {
      return err(AppErrors.parameter('invalid', 'query', `empty query pair: ${queryPart}`));
    }
    const eqIdx: number = pair.indexOf('=');
    if (eqIdx <= 0) {
      return err(AppErrors.parameter('invalid', 'query', `query pair missing '=': ${pair}`));
    }
    const key: string = pair.substring(0, eqIdx);
    const value: string = pair.substring(eqIdx + 1);
    if (BAD_PERCENT_PATTERN.test(key) || BAD_PERCENT_PATTERN.test(value)) {
      return err(AppErrors.parameter('invalid', key, `malformed percent-encoding in query: ${pair}`));
    }
    const decodedKey: string = decodeURIComponent(key);
    if (raw.has(decodedKey)) {
      return err(AppErrors.parameter('invalid', decodedKey, `duplicate parameter: ${decodedKey}`));
    }
    raw.set(decodedKey, decodeURIComponent(value));
  }
  return ok(undefined);
}

function rejectUnknownParams(def: RouteDefinition, raw: Map<string, string>): string | null {
  const known: Map<string, boolean> = new Map<string, boolean>();
  for (let i: number = 0; i < def.params.length; i++) {
    known.set(def.params[i].name, true);
  }
  for (const key of raw.keys()) {
    if (known.get(key) !== true) {
      return key;
    }
  }
  return null;
}

function stringifyValue(value: ParamValue): string {
  if (typeof value === 'boolean') {
    return value ? 'true' : 'false';
  }
  return `${value}`;
}

// ---------- deep link 规则 ----------

/** query 参数白名单映射：from（外部名）→ to（内部参数名）。 */
export interface DeepLinkParamMapping {
  readonly from: string;
  readonly to: string;
}

/** 外部 URI → 路由的白名单规则。 */
export interface DeepLinkRule {
  readonly scheme: string;
  /** 小写 host；'' 表示 URI 无 authority（如 'tg:settings?x=1'）。 */
  readonly host: string;
  /** host 之后的 path 模板（含 '{param}' 占位）；缺省表示不允许有 path。 */
  readonly pathTemplate?: string;
  readonly route: RouteName;
  readonly queryParams: DeepLinkParamMapping[];
}

/** 默认 deep link 映射表（示例级，feature 接入时可扩充/细化）。 */
export function defaultDeepLinkRules(): DeepLinkRule[] {
  return [
    {
      scheme: 'tg',
      host: 'chat',
      route: 'chat',
      queryParams: [
        { from: 'chatId', to: 'chatId' },
        { from: 'threadId', to: 'threadId' }
      ]
    },
    { scheme: 'tg', host: 'settings', route: 'settings', queryParams: [] },
    {
      scheme: 'tg',
      host: 'search',
      route: 'search',
      queryParams: [{ from: 'query', to: 'query' }]
    },
    {
      scheme: 'https',
      host: 't.me',
      pathTemplate: 'chat/{chatId}',
      route: 'chat',
      queryParams: [{ from: 'threadId', to: 'threadId' }]
    }
  ];
}

/** 按白名单映射 query 参数；未在表内的外部参数忽略。 */
function mapQueryParams(
  rule: DeepLinkRule,
  queryPart: string,
  raw: Map<string, string>
): Result<Map<string, string>, AppError> {
  if (queryPart.length === 0) {
    return ok(raw);
  }
  const pairs: string[] = queryPart.split('&');
  for (let i: number = 0; i < pairs.length; i++) {
    const pair: string = pairs[i];
    if (pair.length === 0) {
      continue;
    }
    const eqIdx: number = pair.indexOf('=');
    if (eqIdx <= 0) {
      continue;
    }
    const key: string = pair.substring(0, eqIdx);
    const value: string = pair.substring(eqIdx + 1);
    if (BAD_PERCENT_PATTERN.test(key) || BAD_PERCENT_PATTERN.test(value)) {
      return err(AppErrors.parameter('invalid', key, `malformed percent-encoding in query: ${pair}`));
    }
    const decodedKey: string = decodeURIComponent(key);
    const decodedValue: string = decodeURIComponent(value);
    for (let m: number = 0; m < rule.queryParams.length; m++) {
      if (rule.queryParams[m].from === decodedKey) {
        const internal: string = rule.queryParams[m].to;
        if (raw.has(internal)) {
          return err(AppErrors.parameter('invalid', internal, `duplicate parameter: ${internal}`));
        }
        raw.set(internal, decodedValue);
      }
    }
  }
  return ok(raw);
}
