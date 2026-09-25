/**
 * entry/src/main/ets/deeplink/AppLinkRouter.ets — Telegram 链接解析与路由（DEEPLINK-101）。
 *
 * 分工照 Android `TdlibUi`：`openUrl` 先 `openTelegramUrl`（内部就是
 * `TdApi.GetInternalLinkType` + 按 `InternalLinkType` 分发），问不出名堂才
 * `openExternalUrl` 落浏览器（`TdlibUi.java:3172-3182`、`:3483-3530`）。
 * **本端不自己写链接文法**：`t.me/durov` 到底是公开会话、邀请还是代理，
 * 只有 `getInternalLinkType` 说得准；这里只负责「拿到判别式之后往哪压栈」。
 *
 * 四条刻意的选择：
 * 1. **自有 `tg://` 规则优先**（ADR-005 的 `defaultDeepLinkRules`）。那是本应用自己
 *    声明的内部契约，命中即走，不花一次 IPC；`https://t.me/chat/{chatId}` 也在表里，
 *    代价是「用户名字面上叫 chat 且第二段是数字」会被判成内部会话 —— 由
 *    `internalRuleWinsBeforeTdlib` 用例钉住，将来要改得明确改。
 * 2. **非候选链接根本不去问 TDLib**（`isTelegramLinkCandidate` 只看 scheme 与 host）。
 *    聊天页每条气泡里都可能有链接，全部转发给 TDLib 就是每次点击一趟同步请求；
 *    白名单判错的后果只是「一条 Telegram 链接进了浏览器」，比 IPC 划算。
 * 3. **认得的 Telegram 链接一律不回落浏览器**。`internalLinkTypeChatInvite` /
 *    `internalLinkTypeProxy` / `internalLinkTypeMessage` 本端还没实现（PROXY/INVITE 另包），
 *    但它们**确实是** Telegram 链接 —— 丢进浏览器会得到一个登录墙，用户只会以为应用坏了。
 *    所以给 `unsupported` 让上层照 Android 的 `InternalUrlUnsupported` 提示一句。
 *    只有 TDLib 明确回 `internalLinkTypeUnknownDeepLink` 才是「不是我们的」，交给浏览器。
 *    连判别式都不在我们的解码表里（TDLib 比生成码新）时，`decodeTdInternalLinkType`
 *    给 `TdUnknownObject`，判别式原样透传 —— 同样按 `unsupported` 处理，不猜也不外溢。
 * 4. **日志里没有链接正文**。链接可以携带邀请哈希（等同凭证），与本仓既有的
 *    `openLink failed: no host context`（只记事件不记 URL）口径一致，只记判别式与 chatId。
 */

import { AppError, AppErrors, err, ok, Result } from '@tgx/core-common';
import { Logger } from '@tgx/observability';
import {
  AppRoute,
  DeepLinkRule,
  RouteCodec,
  defaultDeepLinkRules,
  defaultRegistry,
  isTelegramLinkCandidate,
  normalizeTelegramLink
} from '@tgx/core-navigation';
import {
  Chat,
  ChatTypeBasicGroup,
  ChatTypePrivate,
  GetInternalLinkType,
  InternalLinkTypePublicChat,
  SearchPublicChat,
  TdChatType,
  TdInternalLinkType,
  TdJsonRaw,
  decodeChat,
  decodeTdInternalLinkType,
  encodeGetInternalLinkType,
  encodeSearchPublicChat
} from '@tgx/core-td-api-generated';
import { TdWireObject } from '@tgx/td-gateway';

/** TDLib 请求端口；生产实现包 `AccountScope.request`，测试里给假应答。 */
export interface AppLinkTdPort {
  request(method: string, params: TdWireObject): Promise<Result<TdWireObject, AppError>>;
}

export type AppLinkOutcome =
  /** 解析成功并已压栈。 */
  'routed'
  /** 命中 ADR-005 自有规则（`tg://chat|settings|search`、`t.me/chat/{id}`）。 */
  | 'internal_route'
  /** TDLib 判定不是 Telegram 链接 → 上层回落浏览器。 */
  | 'external'
  /** 是 Telegram 链接，但本端这一步还没实现（邀请 / 代理 / 消息 …）。 */
  | 'unsupported'
  /** 空串或全空白。 */
  | 'empty'
  /** 账号还没就绪（auth 未完成），链接留在队列里。 */
  | 'not_ready'
  /** 同一条链接正在解析中（重复 want / 连点）。 */
  | 'in_flight'
  /** TDLib 报错或应答解不出来。 */
  | 'failed';

export interface AppLinkResult {
  readonly outcome: AppLinkOutcome;
  /** TDLib 返回的判别式（`internalLinkTypePublicChat` 等）；没问到为 `''`。 */
  readonly linkType: string;
  /** 已解析出的会话 id；没有为 0。 */
  readonly chatId: number;
  /** 可展示的原因键（`chatNotPublic` / `tdlib_error` / 具体 linkType）。 */
  readonly reason: string;
}

export interface AppLinkRouterOptions {
  /** 压栈回调 —— entry 是唯一的路由所有者，本类不持有导航栈。 */
  readonly navigate: (route: AppRoute) => void;
  /** 账号是否已可用（未登录时不解析，让队列留着）。缺省视为可用。 */
  readonly isReady?: () => boolean;
  readonly logger?: Logger;
  /** 自有规则表，测试可注入。 */
  readonly rules?: DeepLinkRule[];
}

const TAG: string = 'AppLinkRouter';

export class AppLinkRouter {
  private readonly port: AppLinkTdPort;
  private readonly navigate: (route: AppRoute) => void;
  private readonly isReady: () => boolean;
  private readonly logger: Logger | null;
  private readonly codec: RouteCodec;
  private readonly rules: DeepLinkRule[];
  /** 在途链接（归一化后）；TDLib 没有取消接口，只能自己挡住重复。 */
  private inFlight: string | null = null;

  constructor(port: AppLinkTdPort, options: AppLinkRouterOptions) {
    this.port = port;
    this.navigate = options.navigate;
    this.isReady = options.isReady !== undefined ? options.isReady : (): boolean => true;
    this.logger = options.logger !== undefined ? options.logger : null;
    this.codec = new RouteCodec(defaultRegistry());
    this.rules = options.rules !== undefined ? options.rules : defaultDeepLinkRules();
  }

  /** 一次只能有一条链接在解析（队列会按序重投）。 */
  isBusy(): boolean {
    return this.inFlight !== null;
  }

  async handle(uri: string): Promise<AppLinkResult> {
    const trimmed: string = uri.trim();
    if (trimmed.length === 0) {
      return result('empty', '', 0, '');
    }
    if (!this.isReady()) {
      return result('not_ready', '', 0, 'account_not_ready');
    }

    const internal: Result<AppRoute, AppError> = this.codec.parseDeepLink(trimmed, this.rules);
    if (internal.ok) {
      this.navigate(internal.value);
      this.log('info', `outcome=internal_route route=${internal.value.name}`);
      return result('internal_route', '', 0, '');
    }

    if (!isTelegramLinkCandidate(trimmed)) {
      return result('external', '', 0, 'not_telegram_link');
    }

    const normalized: string = normalizeTelegramLink(trimmed);
    if (this.inFlight === normalized) {
      return result('in_flight', '', 0, 'duplicate_in_flight');
    }
    this.inFlight = normalized;
    try {
      return await this.resolveInternalLinkType(normalized);
    } finally {
      this.inFlight = null;
    }
  }

  private async resolveInternalLinkType(link: string): Promise<AppLinkResult> {
    const request: GetInternalLinkType = new GetInternalLinkType();
    request.link = link;
    const typeResult: Result<TdWireObject, AppError> = await this.port.request(
      'getInternalLinkType',
      encodeGetInternalLinkType(request) as TdWireObject
    );
    if (typeResult.err) {
      this.log('warn', `outcome=failed stage=link_type,kind=${typeResult.error.kind}`);
      return result('failed', '', 0, 'link_type_error');
    }
    const linkType: TdInternalLinkType | null = decodeTdInternalLinkType(
      // 早退之后 ArkTS 不会把 typeResult 收窄成 Ok，只能走 getOrNull。
      typeResult.getOrNull() as TdJsonRaw
    );
    if (linkType === null) {
      this.log('warn', 'outcome=failed stage=link_type,reason=undecodable');
      return result('failed', '', 0, 'link_type_undecodable');
    }
    const discriminator: string = linkType.type;

    if (discriminator === 'internalLinkTypeUnknownDeepLink') {
      // TDLib 自己说「不是我们的链接」——这才是允许回落浏览器的唯一信号。
      return result('external', discriminator, 0, '');
    }
    if (discriminator !== 'internalLinkTypePublicChat') {
      return result('unsupported', discriminator, 0, discriminator);
    }

    const publicChat: InternalLinkTypePublicChat = linkType as InternalLinkTypePublicChat;
    const username: string = stripAtSign(publicChat.chat_username);
    if (username.length === 0) {
      return result('failed', discriminator, 0, 'empty_username');
    }
    const chat: Chat | null = await this.fetchPublicChat(username);
    if (chat === null) {
      this.log('warn', `outcome=failed stage=search_public_chat,username_length=${username.length}`);
      return result('failed', discriminator, 0, 'chat_unresolved');
    }
    this.navigate(routeForChat(chat, publicChat.open_profile));
    this.log('info', `outcome=routed chatId=${chat.id},openProfile=${publicChat.open_profile}`);
    return result('routed', discriminator, chat.id, '');
  }

  /**
   * `searchPublicChat` 是 TDLib 侧「按用户名取会话」的唯一入口，它会顺手把这个公开会话
   * 建进本地库 —— 与 Android 点一条公开链接后的行为一致。失败（`chatNotPublic`、超时）
   * 一律回落成 `chat_unresolved`，不猜、不用用户名去拼 chatId。
   */
  private async fetchPublicChat(username: string): Promise<Chat | null> {
    const request: SearchPublicChat = new SearchPublicChat();
    request.username = username;
    const response: Result<TdWireObject, AppError> = await this.port.request(
      'searchPublicChat',
      encodeSearchPublicChat(request) as TdWireObject
    );
    if (response.err) {
      return null;
    }
    return decodeChat(response.getOrNull() as TdJsonRaw);
  }

  private log(level: string, message: string): void {
    if (this.logger === null) {
      return;
    }
    if (level === 'warn') {
      this.logger.warn(TAG, message);
      return;
    }
    this.logger.info(TAG, message);
  }
}

/**
 * TDLib 的 `chat_username` 文档口径是「不含 @」，但 `open_profile` 一类的链接实际回包
 * 里带 @ 的情况见过；进来先剥掉，避免把 `@durov` 原样发给 `searchPublicChat` 拿
 * `chatNotPublic`。
 */
export function stripAtSign(raw: string): string {
  const trimmed: string = raw.trim();
  return trimmed.startsWith('@') ? trimmed.substring(1) : trimmed;
}

/**
 * `open_profile` 决定落在会话还是资料页（Android `openInternalLinkType` 里
 * `openChatProfile` 与 `openChat` 的分支）。本 TDLib 版本没有 `chatTypeChannel`
 * —— 频道是 `chatTypeSupergroup.is_channel`，所以群组/频道都落 `chatInfo`，
 * 私聊落 `userProfile`（它要的是 `chatTypePrivate.user_id`，不是 chatId）。
 */
export function routeForChat(chat: Chat, openProfile: boolean): AppRoute {
  if (!openProfile) {
    return { name: 'chat', chatId: chat.id };
  }
  const type: TdChatType | null = chat.type_;
  const typeKind: string = type === null ? '' : type.type;
  if (typeKind === 'chatTypePrivate' || typeKind === 'chatTypeSecret') {
    const userId: number = type === null ? 0 : (type as ChatTypePrivate).user_id;
    if (userId > 0) {
      return { name: 'userProfile', userId: userId };
    }
  }
  if (typeKind === 'chatTypeBasicGroup' || typeKind === 'chatTypeSupergroup') {
    return { name: 'chatInfo', chatId: chat.id };
  }
  return { name: 'chat', chatId: chat.id };
}

function result(outcome: AppLinkOutcome, linkType: string, chatId: number, reason: string): AppLinkResult {
  return { outcome: outcome, linkType: linkType, chatId: chatId, reason: reason };
}

/** 供 entry 复用的错误键（保持与 `AppErrors` 同一构造口径）。 */
export function appLinkInternalError(message: string): AppError {
  return AppErrors.internal('deeplink', message);
}
