/**
 * entry/src/main/ets/share/ShareIntake.ets — 系统分享接收入口（SHARE-EXT-101）。
 *
 * FEAT-P2-010 的另一半：其它应用经系统分享面板（或直接 startAbility）以
 * `ohos.want.action.sendData` / `ohos.want.action.sendMultipleData` 唤起本应用时，
 * 从 want 里取出文本（v1 只接文本；文件仅记录 uri 供后续扩展）。
 *
 * 与深链（DeepLinkQueue）同一套时序纪律：`EntryAbility.onCreate/onNewWant` 拿到
 * want 时页面未必 ready，先入进程级队列，等 Index 进过 home 再交付。三条纪律照搬：
 * 1. 去重只针对「还没交出去的部分」；
 * 2. 有上限并丢最旧；
 * 3. handler 抛异常不能卡住队列。
 *
 * 提取函数全部是**纯函数**（不 import 任何 Kit）：want 的真实形状有三种来源 ——
 * Share Kit 面板编码的 want（用 `systemShare.getSharedData(want)` 还原成记录组）、
 * 文本直接放 `want.uri` 的朴素 sendData、以及带 `ability.params.stream` 文件列表的
 * 形状。EntryAbility 只做薄薄的取数与映射，判定逻辑收在这里以便单测覆盖。
 */

/** 系统分享动作（wantConstant.ACTION_SEND_DATA / ACTION_SEND_MULTIPLE_DATA）。 */
export const ACTION_SEND_DATA: string = 'ohos.want.action.sendData';
export const ACTION_SEND_MULTIPLE_DATA: string = 'ohos.want.action.sendMultipleData';

/** 文件 uri 列表参数键（wantConstant.PARAMS_STREAM，值约定为 string[]）。 */
export const PARAM_STREAM: string = 'ability.params.stream';

/**
 * Share Kit `SharedRecord` 的本仓平替形状。
 *
 * 不直接 import `@kit.ShareKit` 的类型进测试：单测环境没有该 Kit 的桩，
 * EntryAbility 负责把真实记录映射成这个纯数据形状。
 */
export interface ShareRecordLike {
  /** 统一数据类型（`general.plain-text` / `general.hyperlink` / `general.image` …）。 */
  utd: string;
  title: string;
  /** 文本/链接类分享的内容主体。 */
  content: string;
  /** 文件类分享的 uri（文本分享为空）。 */
  uri: string;
}

/** 一次分享的规范化结果：文本（v1 的消费主体）+ 文件 uri 列表（仅记录）。 */
export class ReceivedShare {
  readonly text: string;
  readonly fileUris: string[];

  constructor(text: string, fileUris: string[]) {
    this.text = text;
    this.fileUris = fileUris;
  }

  /** 队列去重用的签名（只对未交付的积压生效）。 */
  signature(): string {
    return `${this.text}\u0001${this.fileUris.join('\u0002')}`;
  }
}

/** 该 want 是否是系统分享（sendData / sendMultipleData）。 */
export function isShareAction(action: string | undefined | null): boolean {
  if (action === undefined || action === null) {
    return false;
  }
  return action === ACTION_SEND_DATA || action === ACTION_SEND_MULTIPLE_DATA;
}

/**
 * Share Kit 记录组 → 文本。取**第一条非空 content**：
 * 分享面板可能同时带「链接 + 配文」多条记录，Telegram 侧它们本来就是一条消息的
 * 两部分，这里取第一条能代表分享主体的文本；纯文件分享（只有 uri）返回空串，
 * 由上层决定提示「没有可分享的文本」。
 */
export function shareTextFromRecords(records: ShareRecordLike[]): string {
  for (let i: number = 0; i < records.length; i++) {
    const content: string = records[i].content;
    if (content !== undefined && content !== null && content.trim().length > 0) {
      return content.trim();
    }
  }
  return '';
}

/**
 * 朴素 sendData want 的同步兜底提取（Share Kit 解析失败/不可用时）。
 *
 * 优先级：`want.uri`（发送方把文本直接当 data 放 uri）→ 分享摘要/标题/内容等
 * 已知参数键。全部缺席返回空串。只认**非空且非文件 uri** 的文本：
 * `file://`、`content://` 开头的 uri 是文件/媒体引用，不能当正文发出去。
 */
export function shareTextFromWantParts(uri: string, params: Record<string, Object> | undefined): string {
  const trimmedUri: string = uri !== undefined && uri !== null ? uri.trim() : '';
  if (trimmedUri.length > 0 && !trimmedUri.startsWith('file://') && !trimmedUri.startsWith('content://')) {
    return trimmedUri;
  }
  if (params === undefined || params === null) {
    return '';
  }
  const keys: string[] = ['ohos.extra.param.key.shareAbstract', 'ohos.extra.param.key.contentTitle', 'content', 'text'];
  for (let i: number = 0; i < keys.length; i++) {
    const value: Object | undefined = params[keys[i]];
    if (value !== undefined && value !== null && typeof value === 'string') {
      const text: string = value as string;
      if (text.trim().length > 0) {
        return text.trim();
      }
    }
  }
  return '';
}

/**
 * `ability.params.stream` → 文件 uri 列表。约定值是 string[]；单个字符串也收下
 * （部分发送方不放数组）。其余形状一律忽略，不猜。
 */
export function shareFileUrisFromParams(params: Record<string, Object> | undefined): string[] {
  const out: string[] = [];
  if (params === undefined || params === null) {
    return out;
  }
  const value: Object | undefined = params[PARAM_STREAM];
  if (value === undefined || value === null) {
    return out;
  }
  if (typeof value === 'string') {
    const single: string = value as string;
    if (single.length > 0) {
      out.push(single);
    }
    return out;
  }
  if (Array.isArray(value)) {
    const list: Object[] = value as Object[];
    for (let i: number = 0; i < list.length; i++) {
      const item: Object | undefined = list[i];
      if (item !== undefined && item !== null && typeof item === 'string') {
        const uri: string = item as string;
        if (uri.length > 0) {
          out.push(uri);
        }
      }
    }
  }
  return out;
}

export type ShareHandler = (share: ReceivedShare) => void;

/** 队列里最多攒几条；超出丢最旧（与 DEEP_LINK_MAX_PENDING 同一档位）。 */
export const SHARE_MAX_PENDING: number = 8;

export type ShareEnqueueResult = 'delivered' | 'queued' | 'duplicate' | 'empty';

export class ShareQueue {
  private readonly pending: ReceivedShare[] = [];
  private handler: ShareHandler | null = null;

  /** 装上消费者，并立刻把积压按入队顺序交付。返回本次交付条数。 */
  attach(handler: ShareHandler): number {
    this.handler = handler;
    const batch: ReceivedShare[] = this.pending.slice();
    this.pending.length = 0;
    for (let i: number = 0; i < batch.length; i++) {
      try {
        handler(batch[i]);
      } catch (e) {
        // 一条坏分享不能连带后面几条不交付。
        continue;
      }
    }
    return batch.length;
  }

  /** 卸下消费者（页面销毁/登出清栈时调用）。 */
  detach(): void {
    this.handler = null;
  }

  isAttached(): boolean {
    return this.handler !== null;
  }

  enqueue(share: ReceivedShare): ShareEnqueueResult {
    if (share === undefined || share === null) {
      return 'empty';
    }
    const text: string = share.text !== undefined && share.text !== null ? share.text : '';
    const fileUris: string[] = share.fileUris !== undefined && share.fileUris !== null ? share.fileUris : [];
    if (text.trim().length === 0 && fileUris.length === 0) {
      return 'empty';
    }
    const normalized: ReceivedShare = new ReceivedShare(text, fileUris);
    if (this.handler === null) {
      const signature: string = normalized.signature();
      for (let i: number = 0; i < this.pending.length; i++) {
        if (this.pending[i].signature() === signature) {
          return 'duplicate';
        }
      }
      this.pending.push(normalized);
      while (this.pending.length > SHARE_MAX_PENDING) {
        this.pending.shift();
      }
      return 'queued';
    }
    try {
      this.handler(normalized);
    } catch (e) {
      // 交付失败不入队重试：消费方（Index）已经把原因报出来了。
    }
    return 'delivered';
  }

  pendingCount(): number {
    return this.pending.length;
  }

  clear(): void {
    this.pending.length = 0;
  }
}

/**
 * 进程级分享队列。`EntryAbility`（收 want）与 `pages/Index`（弹目标选择器）
 * 是两个互不知晓的生命周期点，分享在它们之间交接，所以放一个单例。
 */
export const appShareQueue: ShareQueue = new ShareQueue();
