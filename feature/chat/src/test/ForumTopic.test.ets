/**
 * feature/chat — 论坛话题纯函数单测（FORUM-101）
 *
 * 只测**纯函数**：游标推进、去重合并、就地打补丁。
 * 这些函数决定了「翻页会不会死循环」「置顶会不会跑位」「推送会不会插进半成品」，
 * 而它们全是纯的，所以能用最便宜的方式钉死；UI 层靠真机取证。
 */

import { describe, it, expect } from '@ohos/hypium';
import {
  ForumTopicItem,
  ForumTopicsState,
  EMPTY_FORUM_CURSOR,
  nextForumCursor,
  mergeForumTopics,
  patchForumTopic,
  forumTopicSortWeight
} from '../main/ets/model/ForumTopic';

// ArkTS 不允许把匿名对象字面量写成参数类型（报 10605040），
// 所以这里用带默认值的普通形参，而不是 TS 里常见的 `opts?: {...}`。
function makeTopic(id: number, pinned: boolean = false, unread: number = 0,
                   date: number = 0): ForumTopicItem {
  const item: ForumTopicItem = {
    topicId: id,
    name: `Topic ${id}`,
    iconEmojiId: '',
    iconColor: 0,
    unreadCount: unread,
    unreadMentionCount: 0,
    isPinned: pinned,
    isClosed: false,
    isGeneral: false,
    preview: '',
    lastMessageDate: date
  };
  return item;
}

export default function forumTopicTest(): void {
  describe('ForumTopicTest', () => {
    // ---------- nextForumCursor：翻页终止条件 ----------
    //
    // 这一组是本包最值得钉的地方：判错会导致两种极端 ——
    // ① 永远认为「还有更多」，滚到底就无限请求（用 0,0,0 反复拉第一页）；
    // ② 过早认为「没有了」，话题列表只显示第一页。
    it('nextForumCursor_stopsWhenPageNotFull', 0, () => {
      // 回包不足 limit ⇒ 没有更多，无论服务端给的 offset 是什么。
      const r = nextForumCursor(7, 20, 111, 222, 333);
      expect(r.hasMore).assertFalse();
      expect(r.cursor.offsetDate).assertEqual(0);
      expect(r.cursor.offsetMessageId).assertEqual(0);
      expect(r.cursor.offsetForumTopicId).assertEqual(0);
    });

    it('nextForumCursor_continuesWithServerOffsets', 0, () => {
      const r = nextForumCursor(20, 20, 1700000000, 987654, 42);
      expect(r.hasMore).assertTrue();
      expect(r.cursor.offsetDate).assertEqual(1700000000);
      expect(r.cursor.offsetMessageId).assertEqual(987654);
      expect(r.cursor.offsetForumTopicId).assertEqual(42);
    });

    it('nextForumCursor_fullPageButZeroOffsets_doesNotLoop', 0, () => {
      // 正好取满 + 服务端 offset 全 0：这是「刚好最后一页」的常见形态，
      // 必须判成没有更多；否则会拿 0,0,0 再请求一次同一页，形成死循环。
      const r = nextForumCursor(20, 20, 0, 0, 0);
      expect(r.hasMore).assertFalse();
    });

    it('nextForumCursor_emptyPageStops', 0, () => {
      const r = nextForumCursor(0, 20, 123, 456, 7);
      expect(r.hasMore).assertFalse();
    });

    // ---------- mergeForumTopics：去重 + 置顶分区 ----------
    it('mergeForumTopics_dedupesByTopicId', 0, () => {
      // 分页边界重发同一条是常态（TDLib 的 offset 是「最后一条」而非「下一条」）。
      const existing: ForumTopicItem[] = [makeTopic(1), makeTopic(2)];
      const incoming: ForumTopicItem[] = [makeTopic(2), makeTopic(3)];
      const merged = mergeForumTopics(existing, incoming);
      expect(merged.length).assertEqual(3);
      expect(merged[0].topicId).assertEqual(1);
      expect(merged[1].topicId).assertEqual(2);
      expect(merged[2].topicId).assertEqual(3);
    });

    it('mergeForumTopics_keepsPinnedFirstStably', 0, () => {
      const existing: ForumTopicItem[] = [makeTopic(1), makeTopic(2, true)];
      const incoming: ForumTopicItem[] = [makeTopic(3, true), makeTopic(4)];
      const merged = mergeForumTopics(existing, incoming);
      // 置顶的 2、3 在前（保持各自原相对顺序），其余 1、4 在后
      expect(merged[0].topicId).assertEqual(2);
      expect(merged[1].topicId).assertEqual(3);
      expect(merged[2].topicId).assertEqual(1);
      expect(merged[3].topicId).assertEqual(4);
    });

    it('mergeForumTopics_doesNotMutateInputs', 0, () => {
      const existing: ForumTopicItem[] = [makeTopic(1)];
      const incoming: ForumTopicItem[] = [makeTopic(2, true)];
      const merged = mergeForumTopics(existing, incoming);
      // 返回新数组，且原数组长度不变（reducer 依赖「无变化返回原引用」的约定，
      // 这里虽是新数组，但绝不能改动入参）
      expect(existing.length).assertEqual(1);
      expect(incoming.length).assertEqual(1);
      expect(merged.length).assertEqual(2);
    });

    // ---------- patchForumTopic ----------
    it('patchForumTopic_updatesMatchingOnly', 0, () => {
      const items: ForumTopicItem[] = [makeTopic(1), makeTopic(2), makeTopic(3)];
      const out = patchForumTopic(items, 2, (t: ForumTopicItem): ForumTopicItem => {
        // ArkTS 10605038：直接 `return { … }` 是无类型对象字面量，
        // 必须先落到一个有名字的类型上再返回。
        const renamed: ForumTopicItem = {
          topicId: t.topicId,
          name: 'Renamed',
          iconEmojiId: t.iconEmojiId,
          iconColor: t.iconColor,
          unreadCount: 9,
          unreadMentionCount: t.unreadMentionCount,
          isPinned: t.isPinned,
          isClosed: t.isClosed,
          isGeneral: t.isGeneral,
          preview: t.preview,
          lastMessageDate: t.lastMessageDate
        };
        return renamed;
      });
      expect(out.length).assertEqual(3);
      expect(out[0].name).assertEqual('Topic 1');
      expect(out[1].name).assertEqual('Renamed');
      expect(out[1].unreadCount).assertEqual(9);
      expect(out[2].name).assertEqual('Topic 3');
    });

    it('patchForumTopic_unknownIdIsNoOp', 0, () => {
      // 推送可能早于列表加载到达；找不到就原样返回，不插入半成品。
      const items: ForumTopicItem[] = [makeTopic(1)];
      const out = patchForumTopic(items, 999, (t: ForumTopicItem): ForumTopicItem => t);
      expect(out.length).assertEqual(1);
      expect(out[0].topicId).assertEqual(1);
    });

    // ---------- 排序权重 ----------
    it('forumTopicSortWeight_pinnedBeatsUnreadBeatsDate', 0, () => {
      const pinned = forumTopicSortWeight(makeTopic(1, true, 0, 1));
      const unread = forumTopicSortWeight(makeTopic(2, false, 5, 1));
      const plainNew = forumTopicSortWeight(makeTopic(3, false, 0, 999));
      expect(pinned > unread).assertTrue();
      expect(unread > plainNew).assertTrue();
    });

    // ---------- ForumTopicsState ----------
    it('forumTopicsState_initialIsEmptyAndLoading', 0, () => {
      const s: ForumTopicsState = ForumTopicsState.initial();
      expect(s.items.length).assertEqual(0);
      expect(s.hasMore).assertTrue();
      expect(s.isLoading).assertFalse();
      expect(s.errorMessage).assertEqual('');
      expect(s.cursor.offsetDate).assertEqual(EMPTY_FORUM_CURSOR.offsetDate);
    });

    it('forumTopicsState_copyWithKeepsUntouchedFields', 0, () => {
      const s: ForumTopicsState = ForumTopicsState.initial().copyWith({
        totalCount: 7,
        query: 'abc'
      });
      const s2: ForumTopicsState = s.copyWith({ isLoading: true });
      expect(s2.totalCount).assertEqual(7);
      expect(s2.query).assertEqual('abc');
      expect(s2.isLoading).assertTrue();
      // 关键：copyWith 返回新实例，不改原对象
      expect(s.isLoading).assertFalse();
    });
  });
}
