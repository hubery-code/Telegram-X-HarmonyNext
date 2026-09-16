/**
 * core/navigation — 强类型路由契约（UI-002）。
 *
 * 与迁移实施计划 §5.11 对齐：导航使用 typed route，参数必须可序列化、可恢复；
 * 非法参数在解析层（RouteCodec）被拒绝，以 Result<AppRoute, AppError> 返回错误，
 * 不做异常控制流。
 *
 * 路由命名规范：
 * - route name 用小驼峰（'chat'、'chatInfo'、'settingsSection'），即 discriminated
 *   union 的判别字段取值，全工程唯一；
 * - 内部 path 模板用同名小驼峰段 + `{param}` 占位（'chat/{chatId}'），
 *   path 不带前导 '/'（展示层拼接规则由 entry 决定）；
 * - 参数名小驼峰；可选参数不进模板，parse/encode 时走 query string
 *   （'search?query=abc'）。
 *
 * 加新路由的步骤（细节见 README）：
 * 1. 在下方 AppRoute union 增加接口（name 用新的字面量）；
 * 2. 在 ROUTE_DEFINITIONS 增加 RouteDefinition（pathTemplate + 参数 schema）；
 * 3. 在 RouteCodec.buildRoute 的 switch 增加构造分支；
 * 4. 如需外部 deep link，在 defaultDeepLinkRules 增加规则。
 */

/** 参数值只允许三种可序列化标量。 */
export type ParamValue = string | number | boolean;

export type ParamType = 'string' | 'int' | 'boolean';

/**
 * 单个参数的 schema：名称、类型、必填/可选、可选校验规则。
 * - int：十进制整数字符串解析，必须在 Number.isSafeInteger 范围内
 *   （TDLib int53 数据安全往返），可配 min/max；
 * - string：可配 maxLength / pattern；
 * - boolean：仅接受 'true' / 'false'。
 */
export interface ParamSpec {
  readonly name: string;
  readonly type: ParamType;
  readonly required: boolean;
  readonly min?: number;
  readonly max?: number;
  readonly maxLength?: number;
  readonly pattern?: RegExp;
}

/** 路由定义：route name ↔ path 模板 ↔ 参数 schema。 */
export interface RouteDefinition {
  readonly name: RouteName;
  readonly pathTemplate: string;
  readonly params: ParamSpec[];
}

/** 所有已定义路由名（字面量联合，新增路由时同步扩充）。 */
export type RouteName =
  'home'
  | 'auth'
  | 'chat'
  | 'chatInfo'
  | 'settings'
  | 'settingsSection'
  | 'search'
  | 'mediaViewer';

export interface HomeRoute {
  readonly name: 'home';
}

export interface AuthRoute {
  readonly name: 'auth';
}

export interface ChatRoute {
  readonly name: 'chat';
  /** TDLib chat id；频道为负数（如 -100xxxxxxxxxx），仍在 safe integer 范围内。 */
  readonly chatId: number;
  /** 论坛话题（forum topic）id，可选。 */
  readonly threadId?: number;
  /**
   * SEARCH-102：进入会话后需要定位到的目标消息 id，可选。
   * 全局搜索结果（消息命中）经此字段把 messageId 交给会话页做滚动定位；
   * 普通入口（会话列表、深链）不带该字段。
   */
  readonly messageId?: number;
}

export interface ChatInfoRoute {
  readonly name: 'chatInfo';
  readonly chatId: number;
}

export interface SettingsRoute {
  readonly name: 'settings';
}

export interface SettingsSectionRoute {
  readonly name: 'settingsSection';
  /** 小节标识，如 'general'、'notifications'。 */
  readonly section: string;
}

export interface SearchRoute {
  readonly name: 'search';
  readonly query?: string;
}

export interface MediaViewerRoute {
  readonly name: 'mediaViewer';
  readonly chatId: number;
  readonly messageId: number;
}

/** 强类型路由：discriminated union，判别字段为 name。 */
export type AppRoute =
  HomeRoute
  | AuthRoute
  | ChatRoute
  | ChatInfoRoute
  | SettingsRoute
  | SettingsSectionRoute
  | SearchRoute
  | MediaViewerRoute;

/** settingsSection 的 section 标识格式。 */
export const SECTION_PATTERN: RegExp = /^[a-z][a-zA-Z0-9_]*$/;

interface MutableParamSpec {
  name: string;
  type: ParamType;
  required: boolean;
  min?: number;
  max?: number;
  maxLength?: number;
  pattern?: RegExp;
}

function spec(
  name: string,
  type: ParamType,
  required: boolean,
  min?: number,
  max?: number,
  maxLength?: number,
  pattern?: RegExp
): ParamSpec {
  const mutable: MutableParamSpec = { name: name, type: type, required: required };
  if (min !== undefined) {
    mutable.min = min;
  }
  if (max !== undefined) {
    mutable.max = max;
  }
  if (maxLength !== undefined) {
    mutable.maxLength = maxLength;
  }
  if (pattern !== undefined) {
    mutable.pattern = pattern;
  }
  return mutable as ParamSpec;
}

/** 内置路由定义表。新路由在此追加。 */
export const ROUTE_DEFINITIONS: RouteDefinition[] = [
  { name: 'home', pathTemplate: 'home', params: [] },
  { name: 'auth', pathTemplate: 'auth', params: [] },
  {
    name: 'chat',
    pathTemplate: 'chat/{chatId}',
    params: [
      spec('chatId', 'int', true),
      spec('threadId', 'int', false, 1),
      // SEARCH-102：搜索结果携带的目标消息 id（可选，用于进会话后滚动定位）。
      spec('messageId', 'int', false, 1)
    ]
  },
  {
    name: 'chatInfo',
    pathTemplate: 'chatInfo/{chatId}',
    params: [spec('chatId', 'int', true)]
  },
  { name: 'settings', pathTemplate: 'settings', params: [] },
  {
    name: 'settingsSection',
    pathTemplate: 'settings/{section}',
    params: [spec('section', 'string', true, undefined, undefined, 64, SECTION_PATTERN)]
  },
  {
    name: 'search',
    pathTemplate: 'search',
    params: [spec('query', 'string', false, undefined, undefined, 256)]
  },
  {
    name: 'mediaViewer',
    pathTemplate: 'mediaViewer/{chatId}/{messageId}',
    params: [
      spec('chatId', 'int', true),
      spec('messageId', 'int', true, 1)
    ]
  }
];
