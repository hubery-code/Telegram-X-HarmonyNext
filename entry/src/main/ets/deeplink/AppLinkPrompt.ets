/**
 * entry/src/main/ets/deeplink/AppLinkPrompt.ets — 链接确认弹窗的端口与视图模型（DEEPLINK-102）。
 *
 * 为什么弹窗要走一个端口、而不是让 `AppLinkRouter` 直接弹：路由器是纯逻辑，在 hypium 里跑，
 * 而确认框是 ArkUI 状态。Android 侧对应的两个 UI 触点是
 * `TdlibUi.openJoinDialog`（`ModernActionedLayout.showJoinDialog`）和
 * `TdlibUi.openProxyAlert`（一个三选项菜单），本端把它们收敛成两条回调：
 * 「要不要进这个会话」「要不要用这个代理」。别的链接类型不需要问人，也就不需要这个端口。
 *
 * 视图模型是**从 TDLib DTO 里挑出来的标量**，不是 DTO 本身：弹窗只该拿到能显示的东西，
 * 邀请哈希（等同凭证）留在路由器手里，不进 UI 状态、更不进日志。
 */

/** 代理链接弹窗的三个去路，与 Android `openProxyAlert` 的三个 option 一一对应。 */
export type ProxyPromptChoice = 'enable' | 'save' | 'cancel';

export interface InvitePromptData {
  readonly title: string;
  readonly description: string;
  readonly memberCount: number;
  /** 频道说「订阅者」，群组说「成员」（Android 同口径）。 */
  readonly isChannel: boolean;
  /** 为真时按钮是「申请加入」而不是「加入」——链接只会发出 join request。 */
  readonly createsJoinRequest: boolean;
}

export interface ProxyPromptData {
  readonly server: string;
  readonly port: number;
  /** `'socks5' | 'http' | 'mtproto'`；mtproto 要多提示一句（要带密钥）。 */
  readonly kind: string;
}

/**
 * 两条回调写成**函数属性**而不是方法签名：ArkTS 的 `arkts-no-untyped-obj-literals`
 * 不接受「带方法的接口」的对象字面量实现，而这里恰恰需要 entry 与测试各自用字面量注入。
 */
export interface AppLinkPromptPort {
  readonly confirmInvite: (data: InvitePromptData) => Promise<boolean>;
  readonly chooseProxy: (data: ProxyPromptData) => Promise<ProxyPromptChoice>;
}

/**
 * 没有接弹窗时的兜底：一律拒绝。
 * 宁可少做一步（用户没看到弹窗，链接什么也没发生，日志有 `prompt_declined`），
 * 也不能默认「替用户同意」——加入会话和切代理都是账号级动作。
 */
export const DECLINING_APP_LINK_PROMPT: AppLinkPromptPort = {
  confirmInvite: (_: InvitePromptData): Promise<boolean> => Promise.resolve(false),
  chooseProxy: (_: ProxyPromptData): Promise<ProxyPromptChoice> => Promise.resolve('cancel')
};

/**
 * 加入按钮的文案键。Android 在 `creates_join_request` 的链接上按的是
 * 「Send Request」而不是「Join」—— 点下去不会进会话，只是发申请。
 */
export function inviteActionLabelKey(data: InvitePromptData): string {
  return data.createsJoinRequest ? 'Request to Join' : 'Join';
}

/**
 * 人数副标题键；`memberCount <= 0` 时回空串，让弹窗只留简介那一行。
 * TDLib 对刚建的/隐私会话会给 0，写「0 位成员」是句假话。
 */
export function inviteCountLabelKey(data: InvitePromptData): string {
  if (data.memberCount <= 0) {
    return '';
  }
  return data.isChannel ? '{0} subscribers' : '{0} members';
}

/**
 * 代理地址那一行，照 Android `TdlibUi.newProxyDescription`（`server:port`，不带方括号也不带
 * scheme —— 那是代理配置的原样呈现）。密钥/用户名一律不进这里。
 */
export function proxyPromptAddress(data: ProxyPromptData): string {
  return `${data.server}:${data.port}`;
}

/** mtproto 代理要多一句提示：它除了地址还带一段密钥，用户应当知道这不是普通 SOCKS。 */
export function proxyNeedsMtprotoHint(data: ProxyPromptData): boolean {
  return data.kind === 'mtproto';
}

/**
 * 弹窗选完 → 该发哪一次写请求的 `enable`。
 * 单列出来是因为「启用」和「仅保存」在 TDLib 侧是**同一个** `addProxy`，只差一个 bool；
 * 把这条事实写在函数里，测试才能钉住「选了 save 绝不会 enable」。
 */
export function proxyChoiceEnables(choice: ProxyPromptChoice): boolean | null {
  if (choice === 'cancel') {
    return null;
  }
  return choice === 'enable';
}

/**
 * `AppLinkResult.reason` → 该对用户说的那句（DEEPLINK-102）。
 *
 * 路由器只给「结果键」，翻译留在装配层：这样 `notified` 这种「动作做完了但没有页面可去」
 * 的结果不会出现「哪都没去、也没句话」的第三种状态。认不出的键一律回兜底文案，
 * 而不是把内部键名印到用户脸上。
 */
export function appLinkReasonKey(reason: string): string {
  if (reason === 'join_request_sent') {
    return 'Join request sent';
  }
  if (reason === 'proxy_enabled') {
    return 'Proxy enabled';
  }
  if (reason === 'proxy_saved') {
    return 'Proxy saved for later use';
  }
  return 'Failed to open link';
}

/** 翻译函数（`Lang.getString` 的形状）。注入进来是为了让下面的构卡函数能脱离 Kit 单测。 */
export type TranslateFn = (key: string, ...args: (string | number)[]) => string;

/**
 * 弹窗卡片。只有已经翻译好的字符串和 `secondaryLabel === ''` 表示「没有第二动作」，
 * 视图层因此不认识「邀请」「代理」这些业务概念，也不会漏掉某个分支。
 */
export interface PromptCard {
  readonly title: string;
  readonly body: string;
  readonly footnote: string;
  readonly primaryLabel: string;
  readonly secondaryLabel: string;
  readonly cancelLabel: string;
}

export const EMPTY_PROMPT_CARD: PromptCard = {
  title: '',
  body: '',
  footnote: '',
  primaryLabel: '',
  secondaryLabel: '',
  cancelLabel: ''
};

/**
 * 邀请弹窗（Android `showJoinDialog` 的瘦身版）：标题是会话名，正文是简介，
 * 角标是人数，主按钮在「只会发申请」的链接上换成「申请加入」。
 */
export function invitePromptCard(data: InvitePromptData, t: TranslateFn): PromptCard {
  const countKey: string = inviteCountLabelKey(data);
  return {
    title: data.title,
    body: data.description,
    footnote: countKey.length === 0 ? '' : t(countKey, data.memberCount),
    primaryLabel: t(inviteActionLabelKey(data)),
    secondaryLabel: '',
    cancelLabel: t('Cancel')
  };
}

/**
 * 代理弹窗（Android `openProxyAlert`）：地址两行 + 一句「这会改你的代理配置」，
 * mtproto 再补一句它带密钥。第二动作「稍后使用」是这条链接独有的 —— 存下来但不切路由。
 */
export function proxyPromptCard(data: ProxyPromptData, t: TranslateFn): PromptCard {
  const hint: string = t('This will add a proxy server to your configuration.');
  return {
    title: t('Connect to This Proxy?'),
    body: `${t('Server')}: ${data.server}\n${t('Port')}: ${data.port}`,
    footnote: proxyNeedsMtprotoHint(data)
      ? `${hint} ${t('This proxy uses a secret, make sure you trust the link source.')}`
      : hint,
    primaryLabel: t('Enable'),
    secondaryLabel: t('Save for Later'),
    cancelLabel: t('Cancel')
  };
}
