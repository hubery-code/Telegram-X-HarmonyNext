/**
 * core/common — 日期形态单测（I18N-DATE-101 / FEAT-UI-003）。
 *
 * 覆盖：
 * 1. 两种语言的月份/星期/年月日排布（`Sep 21` vs `9月21日`）；
 * 2. 「当年不写年份、跨年才补」这条判据（旧实现无条件带 4 位年份）；
 * 3. 聊天页日期头的长月份名档（含跨年仍不缩写）；
 * 4. 会话列表三档（当天→时间、一周内→星期、更早→日期）；
 * 5. 周岁边界（生日未到减一、负数夹 0）与生日行的括号形/去年份退化；
 * 6. 越界月份与星期下标退化成数字而不是抛错；
 * 7. **跨语言不串味**：英文界面不得出中文日期，中文界面不得出英文月名。
 */

import { describe, it, expect } from '@ohos/hypium';
import {
  ageOf,
  DateParts,
  datePartsFrom,
  daysBetween,
  formatAgeLabel,
  formatBirthday,
  formatDateCompact,
  formatDateHeader,
  formatDateTimeCompact,
  formatListTimestamp,
  formatMonthDay,
  formatMonthDayLong,
  formatMonthDayYear,
  formatMonthYear,
  formatTimeOfDay,
  formatWeekdayShort,
  isSameDayParts,
  startOfDayMs
} from '../main/ets/DateFormat';
import { SupportedLanguage } from '../main/ets/Lang';

const LANGUAGES: SupportedLanguage[] = ['en', 'zh'];

/** 2026-09-21 是**周一**（weekday=1），设备实测那天的会话列表正好落在这条上。 */
const MON: number = new Date(2026, 8, 21, 14, 30, 0).getTime();

/** `DateParts` 的第 4 个槽位是**星期**而不是小时，这里固定给 0（周日）并保持时刻可读。 */
function parts(year: number, month: number, day: number, hour: number = 0, minute: number = 0): DateParts {
  return new DateParts(year, month, day, 0, hour, minute);
}

export default function dateFormatTest(): void {
  describe('DateFormatTest', () => {
    it('monthDay_shapesPerLanguage', 0, () => {
      const p: DateParts = parts(2026, 9, 21);
      expect(formatMonthDay('en', p)).assertEqual('Sep 21');
      expect(formatMonthDay('zh', p)).assertEqual('9月21日');
      expect(formatMonthDayLong('en', p)).assertEqual('September 21');
      expect(formatMonthDayLong('zh', p)).assertEqual('9月21日');
      expect(formatMonthDayYear('en', p)).assertEqual('Sep 21, 2026');
      expect(formatMonthDayYear('zh', p)).assertEqual('2026年9月21日');
      expect(formatMonthYear('en', p)).assertEqual('September 2026');
      expect(formatMonthYear('zh', p)).assertEqual('2026年9月');
    });

    it('compactYearOnlyWhenCrossYear', 0, () => {
      const now: DateParts = datePartsFrom(MON);
      const sameYear: DateParts = parts(2026, 1, 5);
      const otherYear: DateParts = parts(2025, 1, 5);
      expect(formatDateCompact('en', sameYear, now)).assertEqual('Jan 5');
      expect(formatDateCompact('en', otherYear, now)).assertEqual('Jan 5, 2025');
      expect(formatDateCompact('zh', sameYear, now)).assertEqual('1月5日');
      expect(formatDateCompact('zh', otherYear, now)).assertEqual('2025年1月5日');
    });

    it('dateHeader_usesLongMonthNameInBothTiers', 0, () => {
      const now: DateParts = datePartsFrom(MON);
      expect(formatDateHeader('en', parts(2026, 9, 21), now)).assertEqual('September 21');
      expect(formatDateHeader('en', parts(2025, 9, 15), now)).assertEqual('September 15, 2025');
      expect(formatDateHeader('zh', parts(2026, 9, 21), now)).assertEqual('9月21日');
      expect(formatDateHeader('zh', parts(2025, 9, 15), now)).assertEqual('2025年9月15日');
    });

    it('dateTimeCompact_joinsDateAndTimePerLanguage', 0, () => {
      const now: DateParts = datePartsFrom(MON);
      expect(formatDateTimeCompact('en', datePartsFrom(MON), now, '24h')).assertEqual('Sep 21 at 14:30');
      expect(formatDateTimeCompact('zh', datePartsFrom(MON), now, '24h')).assertEqual('9月21日 14:30');
      // 跨年时英文日期自带逗号，靠 `at` 而不是再加一个逗号。
      expect(formatDateTimeCompact('en', parts(2020, 5, 15, 6, 0), now, '24h')).assertEqual('May 15, 2020 at 06:00');
      // 12 小时制档：日期部分不变，只有时刻换形。
      expect(formatDateTimeCompact('en', datePartsFrom(MON), now, '12h')).assertEqual('Sep 21 at 2:30 PM');
      expect(formatDateTimeCompact('zh', datePartsFrom(MON), now, '12h')).assertEqual('9月21日 下午2:30');
    });

    it('timeOfDay_padsToTwoDigits', 0, () => {
      expect(formatTimeOfDay(new DateParts(2026, 9, 21, 1, 9, 5), 'en', '24h')).assertEqual('09:05');
      expect(formatTimeOfDay(new DateParts(2026, 9, 21, 1, 23, 59), 'en', '24h')).assertEqual('23:59');
      expect(formatTimeOfDay(new DateParts(2026, 9, 21, 1, 0, 0), 'en', '24h')).assertEqual('00:00');
    });

    it('timeOfDay_clockGears', 0, () => {
      // 0 点与 12 点是 12 小时制的两个边界：都显示 12，靠上下午标记区分（不是 0，也不是 24）。
      expect(formatTimeOfDay(new DateParts(2026, 9, 21, 1, 0, 30), 'en', '12h')).assertEqual('12:30 AM');
      expect(formatTimeOfDay(new DateParts(2026, 9, 21, 1, 12, 5), 'en', '12h')).assertEqual('12:05 PM');
      expect(formatTimeOfDay(new DateParts(2026, 9, 21, 1, 13, 0), 'en', '12h')).assertEqual('1:00 PM');
      expect(formatTimeOfDay(new DateParts(2026, 9, 21, 1, 23, 59), 'en', '12h')).assertEqual('11:59 PM');
      // 小时数不补零（`2:30` 而不是 `02:30`），分钟始终补零。
      expect(formatTimeOfDay(new DateParts(2026, 9, 21, 1, 9, 5), 'en', '12h')).assertEqual('9:05 AM');
      // 中文档：上下午是前缀，且不带空格。
      expect(formatTimeOfDay(new DateParts(2026, 9, 21, 1, 0, 30), 'zh', '12h')).assertEqual('上午12:30');
      expect(formatTimeOfDay(new DateParts(2026, 9, 21, 1, 12, 5), 'zh', '12h')).assertEqual('下午12:05');
      expect(formatTimeOfDay(new DateParts(2026, 9, 21, 1, 13, 0), 'zh', '12h')).assertEqual('下午1:00');
      // 24 小时制下两语言同形（zh 不额外加「点」）。
      expect(formatTimeOfDay(new DateParts(2026, 9, 21, 1, 14, 30), 'zh', '24h')).assertEqual('14:30');
    });

    it('weekdayShort_indexesFromSunday', 0, () => {
      expect(formatWeekdayShort('en', 0)).assertEqual('Sun');
      expect(formatWeekdayShort('en', 1)).assertEqual('Mon');
      expect(formatWeekdayShort('zh', 0)).assertEqual('周日');
      expect(formatWeekdayShort('zh', 3)).assertEqual('周三');
      // 越界下标退化成数字：这里抛错会让整行会话渲染失败。
      expect(formatWeekdayShort('en', 7)).assertEqual('7');
      expect(formatWeekdayShort('zh', -1)).assertEqual('-1');
    });

    it('listTimestamp_threeTiers', 0, () => {
      const nowMs: number = MON;
      const sameDay: number = new Date(2026, 8, 21, 9, 5, 0).getTime();
      const yesterday: number = new Date(2026, 8, 20, 22, 0, 0).getTime();
      const sixDaysAgo: number = new Date(2026, 8, 15, 8, 0, 0).getTime();
      const sevenDaysAgo: number = new Date(2026, 8, 14, 8, 0, 0).getTime();
      const lastYear: number = new Date(2025, 0, 15, 8, 0, 0).getTime();

      expect(formatListTimestamp('en', sameDay, nowMs, '24h')).assertEqual('09:05');
      expect(formatListTimestamp('zh', sameDay, nowMs, '24h')).assertEqual('09:05');
      // 当天那一档是唯一受时制影响的；星期与日期两档不受影响。
      expect(formatListTimestamp('en', sameDay, nowMs, '12h')).assertEqual('9:05 AM');
      expect(formatListTimestamp('zh', sameDay, nowMs, '12h')).assertEqual('上午9:05');
      expect(formatListTimestamp('en', yesterday, nowMs, '12h')).assertEqual('Sun');
      expect(formatListTimestamp('zh', yesterday, nowMs, '12h')).assertEqual('周日');
      expect(formatListTimestamp('en', yesterday, nowMs, '24h')).assertEqual('Sun');
      expect(formatListTimestamp('zh', yesterday, nowMs, '24h')).assertEqual('周日');
      expect(formatListTimestamp('en', sixDaysAgo, nowMs, '24h')).assertEqual('Tue');
      expect(formatListTimestamp('zh', sixDaysAgo, nowMs, '12h')).assertEqual('周二');
      // 第 7 天出窗，落到日期档（当年不补年份）。
      expect(formatListTimestamp('en', sevenDaysAgo, nowMs, '24h')).assertEqual('Sep 14');
      expect(formatListTimestamp('zh', sevenDaysAgo, nowMs, '24h')).assertEqual('9月14日');
      expect(formatListTimestamp('en', lastYear, nowMs, '24h')).assertEqual('Jan 15, 2025');
      expect(formatListTimestamp('zh', lastYear, nowMs, '24h')).assertEqual('2025年1月15日');
    });

    it('dayHelpers', 0, () => {
      const morning: number = new Date(2026, 8, 20, 6, 0, 0).getTime();
      const evening: number = new Date(2026, 8, 20, 23, 59, 59).getTime();
      const nextDay: number = new Date(2026, 8, 21, 0, 0, 1).getTime();
      expect(isSameDayParts(datePartsFrom(morning), datePartsFrom(evening))).assertTrue();
      expect(isSameDayParts(datePartsFrom(morning), datePartsFrom(nextDay))).assertFalse();
      expect(daysBetween(morning, nextDay)).assertEqual(1);
      expect(daysBetween(nextDay, morning)).assertEqual(-1);
      expect(startOfDayMs(evening)).assertEqual(new Date(2026, 8, 20).getTime());
    });

    it('ageOf_birthdayNotReachedAndClamp', 0, () => {
      const now: DateParts = parts(2026, 9, 21);
      expect(ageOf(1990, 10, 15, now)).assertEqual(35);
      expect(ageOf(1990, 9, 21, now)).assertEqual(36);
      expect(ageOf(1990, 9, 22, now)).assertEqual(35);
      expect(ageOf(2026, 9, 22, now)).assertEqual(0);
    });

    it('ageLabel_oneAndOtherPluralGears', 0, () => {
      expect(formatAgeLabel('en', 1)).assertEqual('1 year');
      expect(formatAgeLabel('en', 36)).assertEqual('36 years');
      expect(formatAgeLabel('zh', 36)).assertEqual('36 岁');
    });

    it('birthday_shapeAndUnknownYear', 0, () => {
      const now: DateParts = parts(2026, 9, 21);
      expect(formatBirthday('en', 1990, 9, 21, now)).assertEqual('Sep 21, 1990 (36 years)');
      // 中文用全角括号：CLDR zh 的 append 形就是全角，半角夹在中文里是排版缺陷。
      expect(formatBirthday('zh', 1990, 9, 21, now)).assertEqual('1990年9月21日（36 岁）');
      // 刚满一岁：one 档；生日还没到则退到 0 档。
      expect(formatBirthday('en', 2025, 9, 21, now)).assertEqual('Sep 21, 2025 (1 year)');
      expect(formatBirthday('en', 2025, 9, 22, now)).assertEqual('Sep 22, 2025 (0 years)');
      // TDLib 的 year = 0 表示对方没填年份，只给月日。
      expect(formatBirthday('en', 0, 9, 21, now)).assertEqual('Sep 21');
      expect(formatBirthday('zh', 0, 9, 21, now)).assertEqual('9月21日');
    });

    it('outOfRangeMonthFallsBackToNumberInsteadOfThrowing', 0, () => {
      // 服务端数据可能给 month = 0/13；这里必须出串而不是抛错，否则整条气泡没了。
      expect(formatMonthDay('en', parts(2026, 13, 1))).assertEqual('13 1');
      expect(formatMonthDayLong('en', parts(2026, 0, 1))).assertEqual('0 1');
      expect(formatMonthDay('zh', parts(2026, 13, 1))).assertEqual('13月1日');
    });

    it('noCrossLanguageLeak', 0, () => {
      const now: DateParts = datePartsFrom(MON);
      const samples: DateParts[] = [parts(2026, 9, 21), parts(2025, 1, 5), parts(2020, 12, 31)];
      const broken: string[] = [];
      for (let i = 0; i < samples.length; i++) {
        const p: DateParts = samples[i];
        const enOut: string[] = [
          formatMonthDay('en', p), formatMonthDayLong('en', p), formatMonthDayYear('en', p),
          formatDateCompact('en', p, now), formatDateHeader('en', p, now), formatMonthYear('en', p),
          formatDateTimeCompact('en', p, now, '24h'), formatWeekdayShort('en', p.weekday)
        ];
        const zhOut: string[] = [
          formatMonthDay('zh', p), formatMonthDayLong('zh', p), formatMonthDayYear('zh', p),
          formatDateCompact('zh', p, now), formatDateHeader('zh', p, now), formatMonthYear('zh', p),
          formatDateTimeCompact('zh', p, now, '24h'), formatWeekdayShort('zh', p.weekday)
        ];
        for (let j = 0; j < enOut.length; j++) {
          if (enOut[j].indexOf('年') >= 0 || enOut[j].indexOf('月') >= 0 || enOut[j].indexOf('日') >= 0) {
            broken.push(`en=${enOut[j]}`);
          }
        }
        for (let j = 0; j < zhOut.length; j++) {
          if (/[A-Za-z]{3}/.test(zhOut[j])) {
            broken.push(`zh=${zhOut[j]}`);
          }
        }
      }
      expect(broken.join(', ')).assertEqual('');
      // 英文界面不得再出现旧实现的 `dd.MM.yyyy`（设备实测过的缺陷形态）。
      expect(formatDateCompact('en', parts(2025, 1, 5), now).indexOf('.')).assertEqual(-1);
      expect(LANGUAGES.length).assertEqual(2);
    });
  });
}
