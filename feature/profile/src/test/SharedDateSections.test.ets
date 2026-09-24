/**
 * feature/profile — 共享内容日期分组单元测试（CHATPROF-DATE）。
 *
 * 守住的行为：媒体/文件/链接三个 Tab 的条目要按 Android `SharedBaseController` 的
 * `needDateSectionSplitting` 规则切段 —— 首条必给头，7 天内按天（今天/昨天/星期X），
 * 上一个自然周归「上周」，再往前按自然月切（`TD.shouldSplitDatesByMonth`）。
 * 全部用本地时区构造时间戳，避免用例在不同 tz 的机器上漂移。
 */

import { describe, expect, it } from '@ohos/hypium';
import { SharedMediaItem } from '../main/ets/contract/SharedContentItems';
import {
  formatSharedDateHeader,
  SharedDateSpan,
  sharedDateAnchorKey,
  sharedDateSectionKey,
  splitSharedDateSpans,
  withSharedMediaPath
} from '../main/ets/model/SharedContentFormat';

/** 参照时刻：2026-09-24（周四）12:00 本地时间。 */
const NOW_MS: number = new Date(2026, 8, 24, 12, 0, 0).getTime();

/** 本地时区的某天某小时 → unix 秒（避开 UTC/本地混算导致的日期漂移）。 */
function at(y: number, month: number, day: number, hour: number = 12): number {
  return new Date(y, month - 1, day, hour, 0, 0).getTime() / 1000;
}

export default function sharedDateSectionsTest(): void {
  describe('SharedDateSectionsTest', () => {

    it('todayAndYesterday_getTheirOwnAnchor', 0, () => {
      expect(sharedDateAnchorKey(at(2026, 9, 24), NOW_MS)).assertEqual(1);
      expect(formatSharedDateHeader(at(2026, 9, 24), NOW_MS)).assertEqual('今天');
      expect(sharedDateAnchorKey(at(2026, 9, 23), NOW_MS)).assertEqual(2);
      expect(formatSharedDateHeader(at(2026, 9, 23), NOW_MS)).assertEqual('昨天');
    });

    it('withinSevenDays_groupsPerWeekday', 0, () => {
      // 09-22 周二、09-21 周一：仍在滚动 7 天内 → 每天一段，头是星期全名。
      expect(sharedDateAnchorKey(at(2026, 9, 22), NOW_MS)).assertEqual(3 + 2);
      expect(formatSharedDateHeader(at(2026, 9, 22), NOW_MS)).assertEqual('星期二');
      expect(sharedDateAnchorKey(at(2026, 9, 21), NOW_MS)).assertEqual(3 + 1);
      expect(formatSharedDateHeader(at(2026, 9, 21), NOW_MS)).assertEqual('星期一');
      // 相邻两天的分组键必须不同，否则两段会被并成一段。
      expect(sharedDateSectionKey(at(2026, 9, 22), NOW_MS) ===
        sharedDateSectionKey(at(2026, 9, 21), NOW_MS)).assertFalse();
    });

    it('sundayThatStartsCurrentWeek_countsAsPastWeek', 0, () => {
      // 周日为一周起点：本周日是 09-20，它是 4 天前，但 Android 的
      // `isPastWeek` 第二条（今天非周日 & 目标是周日）把它算作上周。
      expect(sharedDateAnchorKey(at(2026, 9, 20), NOW_MS)).assertEqual(11);
      expect(formatSharedDateHeader(at(2026, 9, 20), NOW_MS)).assertEqual('上周');
    });

    it('previousCalendarWeek_mergesIntoOneLastWeekSection', 0, () => {
      // 上周三 09-16 与上周日 09-13 同属上一个自然周 → 同一个键、同一段。
      expect(sharedDateAnchorKey(at(2026, 9, 16), NOW_MS)).assertEqual(11);
      expect(sharedDateAnchorKey(at(2026, 9, 13), NOW_MS)).assertEqual(11);
      expect(sharedDateSectionKey(at(2026, 9, 16), NOW_MS)).assertEqual(
        sharedDateSectionKey(at(2026, 9, 13), NOW_MS));
      // 再往前一周（09-09）就不是「上周」了，落到按月分组。
      expect(sharedDateAnchorKey(at(2026, 9, 9), NOW_MS)).assertEqual(0);
      expect(formatSharedDateHeader(at(2026, 9, 9), NOW_MS)).assertEqual('2026年9月');
    });

    it('olderThanWeek_splitsByMonthNotByDay', 0, () => {
      expect(sharedDateSectionKey(at(2026, 9, 9), NOW_MS)).assertEqual(
        sharedDateSectionKey(at(2026, 9, 2), NOW_MS));
      expect(sharedDateSectionKey(at(2026, 8, 31), NOW_MS) ===
        sharedDateSectionKey(at(2026, 9, 1), NOW_MS)).assertFalse();
      expect(formatSharedDateHeader(at(2026, 8, 31), NOW_MS)).assertEqual('2026年8月');
    });

    it('yearBoundary_splitsMonths', 0, () => {
      expect(formatSharedDateHeader(at(2026, 1, 1), NOW_MS)).assertEqual('2026年1月');
      expect(formatSharedDateHeader(at(2025, 12, 31), NOW_MS)).assertEqual('2025年12月');
      expect(sharedDateSectionKey(at(2026, 1, 1), NOW_MS) ===
        sharedDateSectionKey(at(2025, 12, 31), NOW_MS)).assertFalse();
    });

    it('spans_coverEveryItemExactlyOnceAndStartWithHeader', 0, () => {
      const dates: number[] = [
        at(2026, 9, 24), at(2026, 9, 24),   // 今天 ×2
        at(2026, 9, 23),                     // 昨天
        at(2026, 8, 31), at(2026, 8, 30),    // 2026年8月
        at(2026, 7, 15)                      // 2026年7月
      ];
      const spans: SharedDateSpan[] = splitSharedDateSpans(dates, NOW_MS);
      expect(spans.length).assertEqual(4);
      expect(spans[0].header).assertEqual('今天');
      expect(spans[0].start).assertEqual(0);
      expect(spans[0].end).assertEqual(2);
      expect(spans[1].header).assertEqual('昨天');
      expect(spans[1].start).assertEqual(2);
      expect(spans[1].end).assertEqual(3);
      expect(spans[2].header).assertEqual('2026年8月');
      expect(spans[2].end).assertEqual(5);
      expect(spans[3].header).assertEqual('2026年7月');
      expect(spans[3].start).assertEqual(5);
      expect(spans[3].end).assertEqual(6);
    });

    it('emptyList_noSpans', 0, () => {
      expect(splitSharedDateSpans([], NOW_MS).length).assertEqual(0);
    });

    it('missingDate_mergesIntoOneHeaderlessSection', 0, () => {
      // 源消息没给日期（date=0）时不能瞎猜月份：并成一段、不出头。
      const spans: SharedDateSpan[] = splitSharedDateSpans([0, 0], NOW_MS);
      expect(spans.length).assertEqual(1);
      expect(spans[0].header).assertEqual('');
      expect(sharedDateAnchorKey(0, NOW_MS)).assertEqual(-1);
      expect(formatSharedDateHeader(0, NOW_MS)).assertEqual('');
    });

    it('thumbBackfill_keepsDateSoSectionsDoNotMove', 0, () => {
      // 缩略图回灌只换 localPath，日期必须原样带过去 —— 否则分组头会跳位。
      const media: SharedMediaItem[] = [
        new SharedMediaItem(0, null, true, at(2026, 8, 5)),
        new SharedMediaItem(700, null, false, at(2026, 7, 5))
      ];
      const updated: SharedMediaItem[] | null = withSharedMediaPath(media, 0, '/data/thumb.jpg');
      expect(updated !== null).assertTrue();
      if (updated !== null) {
        expect(updated[0].localPath).assertEqual('/data/thumb.jpg');
        expect(updated[0].date).assertEqual(at(2026, 8, 5));
        expect(updated[1].date).assertEqual(at(2026, 7, 5));
      }
    });
  });
}
