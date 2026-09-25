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
 * 3. **认得的 Telegram 链接一律不回落浏览器**。TDLib 明确回 `internalLinkTypeUnknownDeepLink`
 *    才是「不是我们的」，交给浏览器；其余判别式都**确实是** Telegram 链接 —— 丢进浏览器会得到
 *    一个登录墙，用户只会以为应用坏了。所以没实现的类型给 `unsupported`，让上层照 Android 的
 *    `InternalUrlUnsupported` 提示一句。连判别式都不在我们的解码表里（TDLib 比生成码新）时，
 *    `decodeTdInternalLinkType` 给 `TdUnknownObject`，判别式原样透传 —— 同样按 `unsupported`
 *    处理，不猜也不外溢。
 *    DEEPLINK-102 补上了四条：公开会话之外的**邀请 / 代理 / 消息 / bot 启动**。前两条要问用户，
 *    问的方式是一个注入的 `AppLinkPromptPort`（见 `AppLinkPrompt.ets`），**缺省实现一律拒绝** ——
 *    没接弹窗的装配路径最坏是链接点了没反应，不会替用户加入会话或切换代理。
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
  AddProxy,
  Chat,
  ChatTypeBasicGroup,
  ChatTypePrivate,
  CheckChatInviteLink,
  ChatInviteLinkInfo,
  ChatJoinResultSuccess,
  GetMessageLinkInfo,
  GetUser,
  GetInternalLinkType,
  InternalLinkTypeBotStart,
  InternalLinkTypeChatInvite,
  InternalLinkTypeMessage,
  InternalLinkTypeProxy,
  InternalLinkTypePublicChat,
  JoinChatByInviteLink,
  MessageLinkInfo,
  ProxyValue,
  SearchPublicChat,
  SendBotStartMessage,
  TdChatJoinResult,
  TdChatType,
  TdInternalLinkType,
  TdJsonRaw,
  TdUserType,
  decodeChat,
  decodeChatInviteLinkInfo,
  decodeMessageLinkInfo,
  decodeTdChatJoinResult,
  decodeTdInternalLinkType,
  decodeUser,
  encodeAddProxy,
  encodeCheckChatInviteLink,
  encodeGetInternalLinkType,
  encodeGetMessageLinkInfo,
  encodeGetUser,
  encodeJoinChatByInviteLink,
  encodeSearchPublicChat,
  encodeSendBotStartMessage
} from '@tgx/core-td-api-generated';
import { TdWireObject } from '@tgx/td-gateway';
import {
  AppLinkPromptPort,
  DECLINING_APP_LINK_PROMPT,
  InvitePromptData,
  ProxyPromptChoice,
  ProxyPromptData,
  proxyChoiceEnables
} from './AppLinkPrompt';

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
  /** 是 Telegram 链接，但本端这一步还没实现（贴纸包 / 语音聊天 …）。 */
  | 'unsupported'
  /** 弹窗问过了，用户说不 —— 什么都不做，也不提示。 */
  | 'cancelled'
  /** 动作做完了但没有页面可去（代理已存/已启用、加入申请已发出），`reason` 给文案键。 */
  | 'notified'
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
  /**
   * DEEPLINK-102：邀请/代理两条链接要问用户。缺省是「一律拒绝」，
   * 所以忘了接弹窗的装配路径最坏也只是链接点了没反应，不会替用户加入会话或切代理。
   */
  readonly prompt?: AppLinkPromptPort;
}

const TAG: string = 'AppLinkRouter';

export class AppLinkRouter {
  private readonly port: AppLinkTdPort;
  private readonly navigate: (route: AppRoute) => void;
  private readonly isReady: () => boolean;
  private readonly logger: Logger | null;
  private readonly codec: RouteCodec;
  private readonly rules: DeepLinkRule[];
  private readonly prompt: AppLinkPromptPort;
  /** 在途链接（归一化后）；TDLib 没有取消接口，只能自己挡住重复。 */
  private inFlight: string | null = null;

  constructor(port: AppLinkTdPort, options: AppLinkRouterOptions) {
    this.port = port;
    this.navigate = options.navigate;
    this.isReady = options.isReady !== undefined ? options.isReady : (): boolean => true;
    this.logger = options.logger !== undefined ? options.logger : null;
    this.codec = new RouteCodec(defaultRegistry());
    this.rules = options.rules !== undefined ? options.rules : defaultDeepLinkRules();
    this.prompt = options.prompt !== undefined ? options.prompt : DECLINING_APP_LINK_PROMPT;
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
      const out: AppLinkResult = await this.resolveInternalLinkType(normalized);
      return this.logTerminal(out);
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
    if (discriminator === 'internalLinkTypePublicChat') {
      return await this.openPublicChat(discriminator, linkType as InternalLinkTypePublicChat);
    }
    if (discriminator === 'internalLinkTypeChatInvite') {
      return await this.openChatInvite(discriminator, linkType as InternalLinkTypeChatInvite);
    }
    if (discriminator === 'internalLinkTypeProxy') {
      return await this.openProxyLink(discriminator, linkType as InternalLinkTypeProxy);
    }
    if (discriminator === 'internalLinkTypeMessage') {
      return await this.openMessageLink(discriminator, linkType as InternalLinkTypeMessage);
    }
    if (discriminator === 'internalLinkTypeBotStart') {
      return await this.openBotStart(discriminator, linkType as InternalLinkTypeBotStart);
    }
    // 认得判别式、但这一步还没实现（贴纸包 / 语音聊天 / 语言包 …）：提示，不外溢浏览器。
    return result('unsupported', discriminator, 0, discriminator);
  }

  /**
   * 每个「问出了链接类型却没成」的出口都留一行总结（DEEPLINK-102）。
   *
   * 各分支的 `stage=` 日志是分支自己给的，所以漏一条就变成「链接点了没反应、日志里也查不到」——
   * 设备取证时真的踩过。失败与不支持两类由这里兜底；导航成功那一类分支自己已经记了 chatId。
   */
  private logTerminal(out: AppLinkResult): AppLinkResult {
    if (out.outcome === 'failed' || out.outcome === 'unsupported') {
      this.log('warn', `outcome=${out.outcome} linkType=${out.linkType},reason=${out.reason}`);
    }
    return out;
  }

  /** `t.me/<username>` —— 公开会话（DEEPLINK-101）。 */
  private async openPublicChat(
    discriminator: string,
    linkType: InternalLinkTypePublicChat
  ): Promise<AppLinkResult> {
    const username: string = stripAtSign(linkType.chat_username);
    if (username.length === 0) {
      return result('failed', discriminator, 0, 'empty_username');
    }
    const chat: Chat | null = await this.fetchPublicChat(username);
    if (chat === null) {
      this.log('warn', `outcome=failed stage=search_public_chat,username_length=${username.length}`);
      return result('failed', discriminator, 0, 'chat_unresolved');
    }
    this.navigate(routeForChat(chat, linkType.open_profile));
    this.log('info', `outcome=routed chatId=${chat.id},openProfile=${linkType.open_profile}`);
    return result('routed', discriminator, chat.id, '');
  }

  /**
   * `t.me/+hash`、`t.me/joinchat/hash` —— 邀请链接（DEEPLINK-102）。
   *
   * 照 Android `TdlibUi.checkChatInviteLink`：先 `checkChatInviteLink` 拿会话信息，
   * **`chat_id` 非 0 说明本地库已经有这个会话（即已经是成员）**，那就直接进会话，
   * 不打扰用户；只有 `chat_id === 0` 才需要弹窗确认后再 `joinChatByInviteLink`。
   * 加入的结果是一个联合（`chatJoinResultSuccess` / `chatJoinResultRequestSent` / …），
   * 只有 success 才带 chatId 可导航，requestSent 只能提示一句「申请已发出」。
   */
  private async openChatInvite(
    discriminator: string,
    linkType: InternalLinkTypeChatInvite
  ): Promise<AppLinkResult> {
    const inviteLink: string = linkType.invite_link;
    if (inviteLink.length === 0) {
      return result('failed', discriminator, 0, 'empty_invite_link');
    }
    const check: CheckChatInviteLink = new CheckChatInviteLink();
    check.invite_link = inviteLink;
    const infoResponse: Result<TdWireObject, AppError> = await this.port.request(
      'checkChatInviteLink',
      encodeCheckChatInviteLink(check) as TdWireObject
    );
    if (infoResponse.err) {
      // 链接失效/被撤销时 TDLib 直接报错；这里不重复它的原因，也不记链接正文。
      this.log('warn', `outcome=failed stage=check_invite,kind=${infoResponse.error.kind}`);
      return result('failed', discriminator, 0, 'invite_check_failed');
    }
    const info = decodeChatInviteLinkInfo(infoResponse.getOrNull() as TdJsonRaw);
    if (info === null) {
      return result('failed', discriminator, 0, 'invite_check_undecodable');
    }
    if (info.chat_id !== 0) {
      this.navigate({ name: 'chat', chatId: info.chat_id });
      this.log('info', `outcome=routed chatId=${info.chat_id},stage=already_member`);
      return result('routed', discriminator, info.chat_id, '');
    }

    const accepted: boolean = await this.prompt.confirmInvite(invitePromptOf(info));
    if (!accepted) {
      this.log('info', 'outcome=cancelled stage=invite_confirm');
      return result('cancelled', discriminator, 0, 'invite_declined');
    }

    const join: JoinChatByInviteLink = new JoinChatByInviteLink();
    join.invite_link = inviteLink;
    const joinResponse: Result<TdWireObject, AppError> = await this.port.request(
      'joinChatByInviteLink',
      encodeJoinChatByInviteLink(join) as TdWireObject
    );
    if (joinResponse.err) {
      this.log('warn', `outcome=failed stage=join,kind=${joinResponse.error.kind}`);
      return result('failed', discriminator, 0, 'join_failed');
    }
    const joined: TdChatJoinResult | null = decodeTdChatJoinResult(joinResponse.getOrNull() as TdJsonRaw);
    const joinType: string = joined === null ? '' : joined.type;
    if (joinType === 'chatJoinResultSuccess') {
      const chatId: number = joined === null ? 0 : (joined as ChatJoinResultSuccess).chat_id;
      if (chatId !== 0) {
        this.navigate({ name: 'chat', chatId: chatId });
      }
      this.log('info', `outcome=routed chatId=${chatId},stage=joined`);
      return result('routed', discriminator, chatId, '');
    }
    if (joinType === 'chatJoinResultRequestSent') {
      // 这类链接只会发出申请，管理员批准前进不了会话。
      this.log('info', 'outcome=notified stage=request_sent');
      return result('notified', discriminator, 0, 'join_request_sent');
    }
    // declined / guardbot / 未来新增的分支：说不出会话，就老实报错。
    this.log('warn', `outcome=failed stage=join,reason=${joinType.length === 0 ? 'undecodable' : joinType}`);
    return result('failed', discriminator, 0, 'join_failed');
  }

  /**
   * `tg://proxy?...`、`t.me/proxy?...` —— 代理链接（DEEPLINK-102，结掉 PROXY-101 的遗留）。
   *
   * Android 是一个三选菜单（`openProxyAlert`：启用 / 稍后使用 / 取消），落到 TDLib 侧
   * 是**同一条** `addProxy`，只差 `enable` 这个 bool —— 所以「稍后使用」绝不可能顺手改路由。
   * 不自己发 `enableProxy`：PROXY-101 的口径是「单选态只有 TDLib 知道真相」，
   * addProxy(enable=true) 已经原子，代理页下次回读 `getProxies` 就会显出这一行。
   */
  private async openProxyLink(
    discriminator: string,
    linkType: InternalLinkTypeProxy
  ): Promise<AppLinkResult> {
    const proxy: ProxyValue | null = linkType.proxy;
    if (proxy === null || proxy.server.length === 0 || proxy.port <= 0) {
      // TDLib 明确回 null 表示「这个代理类型本端不支持」（Android 的 ProxyLinkUnsupported）。
      return result('unsupported', discriminator, 0, 'proxy_unsupported');
    }
    const choice: ProxyPromptChoice = await this.prompt.chooseProxy(proxyPromptOf(proxy));
    const enable: boolean | null = proxyChoiceEnables(choice);
    if (enable === null) {
      this.log('info', 'outcome=cancelled stage=proxy_choice');
      return result('cancelled', discriminator, 0, 'proxy_declined');
    }
    const request: AddProxy = new AddProxy();
    request.proxy = proxy;
    request.enable = enable;
    request.comment = '';
    const response: Result<TdWireObject, AppError> = await this.port.request(
      'addProxy',
      encodeAddProxy(request) as TdWireObject
    );
    if (response.err) {
      this.log('warn', `outcome=failed stage=add_proxy,kind=${response.error.kind}`);
      return result('failed', discriminator, 0, 'proxy_add_failed');
    }
    this.log('info', `outcome=notified stage=add_proxy,enable=${enable}`);
    return result('notified', discriminator, 0, enable ? 'proxy_enabled' : 'proxy_saved');
  }

  /**
   * `t.me/<channel>/<messageId>` —— 消息深链（DEEPLINK-102）。
   *
   * 本 TDLib 版本里没有 `internalLinkTypePost`，帖子链接同样回 `internalLinkTypeMessage`，
   * 统一交给 `getMessageLinkInfo` 解析（Android `InternalLinkTypeMessage` 分支同一句）。
   * 拿到 `chat_id` + `message_id` 后压 `chat` 路由 —— 该路由的 `messageId` 是 SEARCH-102
   * 就有的字段，会话页已经会滚动定位并高亮，这里不另造一条路径。
   */
  private async openMessageLink(
    discriminator: string,
    linkType: InternalLinkTypeMessage
  ): Promise<AppLinkResult> {
    const url: string = linkType.url;
    if (url.length === 0) {
      return result('failed', discriminator, 0, 'empty_message_url');
    }
    const request: GetMessageLinkInfo = new GetMessageLinkInfo();
    request.url = url;
    const response: Result<TdWireObject, AppError> = await this.port.request(
      'getMessageLinkInfo',
      encodeGetMessageLinkInfo(request) as TdWireObject
    );
    if (response.err) {
      this.log('warn', `outcome=failed stage=message_link,kind=${response.error.kind}`);
      return result('failed', discriminator, 0, 'message_link_failed');
    }
    const info: MessageLinkInfo | null = decodeMessageLinkInfo(response.getOrNull() as TdJsonRaw);
    if (info === null || info.chat_id === 0) {
      // `chat_id === 0` 是「这条公开链接指向的会话本地没有」——不猜 chatId、不建会话。
      return result('failed', discriminator, 0, 'message_link_unresolved');
    }
    const messageId: number = info.message === null ? 0 : info.message.id;
    this.navigate(
      messageId > 0
        ? { name: 'chat', chatId: info.chat_id, messageId: messageId }
        : { name: 'chat', chatId: info.chat_id }
    );
    this.log('info', `outcome=routed chatId=${info.chat_id},messageId=${messageId}`);
    return result('routed', discriminator, info.chat_id, '');
  }

  /**
   * `t.me/<bot>?start=x`、`tg://botstart?...` —— bot 深链（DEEPLINK-102）。
   *
   * 照 Android `startBot`：解析用户名 → **必须验明是 bot** 才进会话，
   * 否则一个冒充 bot 的用户名只是把一个普通用户拉进会话并（在 autostart 时）替用户
   * 发出一条消息。校验用 `getUser` 的 `userTypeBot`，与 `tdlib.isBotChat` 同一条依据。
   * `autostart` 由 TDLib 判定（它知道这个 bot 之前有没有被启动过），本端只照做。
   */
  private async openBotStart(
    discriminator: string,
    linkType: InternalLinkTypeBotStart
  ): Promise<AppLinkResult> {
    const username: string = stripAtSign(linkType.bot_username);
    if (username.length === 0) {
      return result('failed', discriminator, 0, 'empty_username');
    }
    const chat: Chat | null = await this.fetchPublicChat(username);
    if (chat === null) {
      return result('failed', discriminator, 0, 'bot_not_found');
    }
    const type: TdChatType | null = chat.type_;
    const typeKind: string = type === null ? '' : type.type;
    if (typeKind !== 'chatTypePrivate' && typeKind !== 'chatTypeSecret') {
      return result('failed', discriminator, 0, 'bot_not_found');
    }
    const userId: number = type === null ? 0 : (type as ChatTypePrivate).user_id;
    const isBot: boolean = await this.userIsBot(userId);
    if (!isBot) {
      this.log('warn', `outcome=failed stage=bot_check,chatId=${chat.id}`);
      return result('failed', discriminator, 0, 'bot_not_found');
    }
    this.navigate({ name: 'chat', chatId: chat.id });
    if (linkType.autostart && linkType.start_parameter.length > 0) {
      const send: SendBotStartMessage = new SendBotStartMessage();
      send.bot_user_id = userId;
      send.chat_id = chat.id;
      send.parameter = linkType.start_parameter;
      // 不等它：进会话已经成功，启动消息失败只在日志里留一条。
      const sent: Result<TdWireObject, AppError> = await this.port.request(
        'sendBotStartMessage',
        encodeSendBotStartMessage(send) as TdWireObject
      );
      if (sent.err) {
        this.log('warn', `outcome=routed stage=bot_start_send,kind=${sent.error.kind}`);
      }
    }
    this.log('info', `outcome=routed chatId=${chat.id},autostart=${linkType.autostart}`);
    return result('routed', discriminator, chat.id, '');
  }

  private async userIsBot(userId: number): Promise<boolean> {
    if (userId <= 0) {
      return false;
    }
    const request: GetUser = new GetUser();
    request.user_id = userId;
    const response: Result<TdWireObject, AppError> = await this.port.request(
      'getUser',
      encodeGetUser(request) as TdWireObject
    );
    if (response.err) {
      return false;
    }
    const user = decodeUser(response.getOrNull() as TdJsonRaw);
    if (user === null) {
      return false;
    }
    const type: TdUserType | null = user.type_;
    return type !== null && type.type === 'userTypeBot';
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
 * DEEPLINK-102：`chatInviteLinkInfo` → 弹窗视图模型。
 * 只挑能显示的四个标量：邀请哈希不进这里，简介为空就不渲染那一行。
 */
export function invitePromptOf(info: ChatInviteLinkInfo): InvitePromptData {
  const type = info.type_;
  const kind: string = type === null ? '' : type.type;
  return {
    title: info.title,
    description: info.description,
    memberCount: info.member_count,
    isChannel: kind === 'inviteLinkChatTypeChannel',
    createsJoinRequest: info.creates_join_request
  };
}

/**
 * DEEPLINK-102：`proxy` → 弹窗视图模型。
 * `type_` 的判别式剥掉 `proxyType` 前缀就是用户看得懂的种类名（socks5 / http / mtproto）；
 * 认不出来的种类留空串，弹窗照常显示地址，只是不多那句 mtproto 提示。
 */
export function proxyPromptOf(proxy: ProxyValue): ProxyPromptData {
  const type = proxy.type_;
  const discriminator: string = type === null ? '' : type.type;
  const kind: string = discriminator.startsWith('proxyType')
    ? discriminator.substring('proxyType'.length).toLowerCase()
    : '';
  return { server: proxy.server, port: proxy.port, kind: kind };
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
