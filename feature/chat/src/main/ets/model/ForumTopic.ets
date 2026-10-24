/**
 * feature/chat — 论坛话题（Forum Topic）的视图模型与纯函数（FORUM-101）
 *
 * 100% Kit-free 纯 ArkTS：这一层只做「TDLib 结构 → 渲染所需字段」的投影，
 * 不碰任何 UI 或系统能力，因此可被 reducer 与单测直接引用。
 *
 * ## 为什么单独放一个 model 文件而不是塞进 ChatUiState
 *
 * 话题列表是一个**独立于消息流的分页集合**（自带 offset 三元组、
 * 自带未读/置顶/关闭态），把它摊进 `ChatUiState` 会让那个已经有 50+ 字段的
 * state 更难读；而它又必须参与 reducer 的纯函数更新，不能放页面里。
 * 折中是：状态挂在 `ChatUiState.forumTopics`（一个可选子状态），
 * 结构与投影逻辑都收在本文件。
 */

/**
 * 话题行在界面上需要的字段。
 *
 * 刻意只留渲染要用的：`order`（排序键）、`last_read_*`（已读边界）、
 * `draft_message`、`notification_settings` 都不进视图模型 ——
 * 前两个是服务端排序/同步用的内部值，后两个是各自独立功能的输入，
 * 塞进来只会让「这一行显示什么」变得难以回答。
 */
export interface ForumTopicItem {
  /** TDLib 的 `forum_topic_id`；打开话题时原样回传。 */
  topicId: number;
  /** 话题名；General 话题的 `is_name_implicit` 为真时名字是服务端给的占位，仍照常显示。 */
  name: string;
  /** 话题图标：TDLib 用 `ForumTopicIcon` 的 `color` + `custom_emoji_id`。 */
  iconEmojiId: string;
  /** 图标底色（ARGB 整数，TDLib `forumTopicIcon.color`）。0 表示没有图标。 */
  iconColor: number;
  /** 未读消息数（0 表示已读完）。 */
  unreadCount: number;
  /** 未读 @/回复数；>0 时界面上要额外标一个「@」。 */
  unreadMentionCount: number;
  /** 是否置顶。 */
  isPinned: boolean;
  /** 是否已关闭（关闭后只有管理员/创建者能发言）。 */
  isClosed: boolean;
  /** 是否 General 话题（TDLib 保证每个 forum 超级群有且仅有一个）。 */
  isGeneral: boolean;
  /** 最后一条消息的文本预览；空串表示没有可显示的内容。 */
  preview: string;
  /** 最后一条消息的时间戳（秒）；0 表示未知。 */
  lastMessageDate: number;
}

/**
 * 话题列表的分页游标 —— TDLib 的 `getForumTopics` 用三元组而非单一 offset。
 *
 * 写成 class 而不是 interface：ArkTS 不允许用无类型对象字面量给
 * interface 赋值（报 10605038），所以游标必须能被 `new` 出来。
 */
export class ForumTopicsCursor {
  readonly offsetDate: number;
  readonly offsetMessageId: number;
  readonly offsetForumTopicId: number;

  constructor(offsetDate: number = 0, offsetMessageId: number = 0, offsetForumTopicId: number = 0) {
    this.offsetDate = offsetDate;
    this.offsetMessageId = offsetMessageId;
    this.offsetForumTopicId = offsetForumTopicId;
  }
}

/** 空游标 = 第一次请求（TDLib 要求三个字段都传 0）。 */
export const EMPTY_FORUM_CURSOR: ForumTopicsCursor = new ForumTopicsCursor();

/**
 * 话题列表子状态。
 *
 * `hasMore` 的判据是「这次回包的条数 == 请求的 limit」——
 * TDLib 的 `ForumTopics.next_offset_*` 全为 0 时表示没有下一页，
 * 但它在「刚好取满最后一页」时也会给 0，所以两个条件都要看
 * （见 `nextForumCursor` 的注释）。
 */
/**
 * `ForumTopicsState.copyWith` 的可选项。
 *
 * 必须是**有名字的 interface**：ArkTS 禁止把匿名对象字面量写成类型标注
 * （`copyWith(options: { items?: … })` 报 10605040），但允许把对象字面量
 * 赋给一个已声明的 interface —— 本仓 `ChatUiStateOptions` 就是同一写法。
 */
export interface ForumTopicsStateOptions {
  readonly items?: ForumTopicItem[];
  readonly cursor?: ForumTopicsCursor;
  readonly totalCount?: number;
  readonly hasMore?: boolean;
  readonly isLoading?: boolean;
  readonly errorMessage?: string;
  readonly query?: string;
}

export class ForumTopicsState {
  readonly items: ForumTopicItem[];
  readonly cursor: ForumTopicsCursor;
  readonly totalCount: number;
  readonly hasMore: boolean;
  readonly isLoading: boolean;
  /** 非空表示这一页读失败；界面显示重试行，不清空已有条目。 */
  readonly errorMessage: string;
  /** 搜索关键词（TDLib `getForumTopics.query` 是服务端过滤）。 */
  readonly query: string;

  constructor(
    items: ForumTopicItem[] = [],
    cursor: ForumTopicsCursor = EMPTY_FORUM_CURSOR,
    totalCount: number = 0,
    hasMore: boolean = true,
    isLoading: boolean = false,
    errorMessage: string = '',
    query: string = ''
  ) {
    this.items = items;
    this.cursor = cursor;
    this.totalCount = totalCount;
    this.hasMore = hasMore;
    this.isLoading = isLoading;
    this.errorMessage = errorMessage;
    this.query = query;
  }

  static initial(): ForumTopicsState {
    return new ForumTopicsState();
  }

  copyWith(options: ForumTopicsStateOptions): ForumTopicsState {
    return new ForumTopicsState(
      options.items !== undefined ? options.items : this.items,
      options.cursor !== undefined ? options.cursor : this.cursor,
      options.totalCount !== undefined ? options.totalCount : this.totalCount,
      options.hasMore !== undefined ? options.hasMore : this.hasMore,
      options.isLoading !== undefined ? options.isLoading : this.isLoading,
      options.errorMessage !== undefined ? options.errorMessage : this.errorMessage,
      options.query !== undefined ? options.query : this.query
    );
  }
}

/**
 * 由这次回包算出下一页游标。
 *
 * 为什么不能只看 `next_offset_*`：TDLib 在「刚好取满最后一页、后面确实没有了」
 * 的情况下同样会把三个 offset 给成 0，与「还有下一页但服务端没算出来」无法区分。
 * 所以判据是：**回包条数 < 请求 limit ⇒ 没有更多**；否则用服务端给的 offset，
 * 若 offset 全 0 也视为没有更多（避免用 0,0,0 反复请求同一页造成死循环）。
 */
/**
 * 游标推进的结果。
 *
 * 为什么要单独一个 class：ArkTS 禁止两件事 ——
 * ① 把匿名对象字面量写成类型标注（`): { cursor: …; hasMore: … }` 报 10605040）；
 * ② 返回无显式类型的对象字面量（报 10605038）。
 * TypeScript 里这两种写法都很自然，在 ArkTS 里必须落到一个有名字的类型上。
 */
export class ForumCursorStep {
  readonly cursor: ForumTopicsCursor;
  readonly hasMore: boolean;

  constructor(cursor: ForumTopicsCursor, hasMore: boolean) {
    this.cursor = cursor;
    this.hasMore = hasMore;
  }
}

export function nextForumCursor(
  received: number,
  limit: number,
  offsetDate: number,
  offsetMessageId: number,
  offsetForumTopicId: number
): ForumCursorStep {
  if (received < limit) {
    return new ForumCursorStep(EMPTY_FORUM_CURSOR, false);
  }
  if (offsetDate === 0 && offsetMessageId === 0 && offsetForumTopicId === 0) {
    return new ForumCursorStep(EMPTY_FORUM_CURSOR, false);
  }
  return new ForumCursorStep(
    new ForumTopicsCursor(offsetDate, offsetMessageId, offsetForumTopicId),
    true
  );
}

/**
 * 合并一页新条目到已有列表。
 *
 * 按 `topicId` 去重（服务端分页边界可能重发同一条），
 * 并保持「置顶在前、其余按服务端顺序」——
 * 服务端已经按 `order` 降序给了，所以这里只在**置顶**这一维上重排，
 * 不重新发明排序规则。
 */
export function mergeForumTopics(
  existing: ForumTopicItem[],
  incoming: ForumTopicItem[]
): ForumTopicItem[] {
  const seen: Set<number> = new Set<number>();
  const merged: ForumTopicItem[] = [];
  for (let i = 0; i < existing.length; i++) {
    if (!seen.has(existing[i].topicId)) {
      seen.add(existing[i].topicId);
      merged.push(existing[i]);
    }
  }
  for (let i = 0; i < incoming.length; i++) {
    if (!seen.has(incoming[i].topicId)) {
      seen.add(incoming[i].topicId);
      merged.push(incoming[i]);
    }
  }
  // 稳定分区：置顶的保持相对顺序在前，非置顶的保持相对顺序在后。
  const pinned: ForumTopicItem[] = [];
  const rest: ForumTopicItem[] = [];
  for (let i = 0; i < merged.length; i++) {
    if (merged[i].isPinned) {
      pinned.push(merged[i]);
    } else {
      rest.push(merged[i]);
    }
  }
  return pinned.concat(rest);
}

/**
 * 就地更新某一条话题（收到 `updateForumTopic` / `updateForumTopicInfo` 时用）。
 * 找不到就原样返回 —— 推送可能早于列表加载，丢弃比插入一条半成品更好。
 */
export function patchForumTopic(
  items: ForumTopicItem[],
  topicId: number,
  patch: (item: ForumTopicItem) => ForumTopicItem
): ForumTopicItem[] {
  const out: ForumTopicItem[] = [];
  for (let i = 0; i < items.length; i++) {
    out.push(items[i].topicId === topicId ? patch(items[i]) : items[i]);
  }
  return out;
}

/**
 * 排序键：置顶优先，其次未读优先，再按最后消息时间倒序。
 *
 * 这条规则只用于**本地即时反馈**（例如刚把某话题标为已读），
 * 真正的顺序以服务端 `order` 为准 —— 所以它是个纯展示辅助，
 * 不参与分页游标的计算。
 */
export function forumTopicSortWeight(item: ForumTopicItem): number {
  let w: number = 0;
  if (item.isPinned) {
    w += 1000000;
  }
  if (item.unreadCount > 0) {
    w += 100000;
  }
  return w + item.lastMessageDate;
}
