/**
 * 语言驱动的日期形态（I18N-DATE-101 / FEAT-UI-003）。
 *
 * 这个模块存在的原因：本仓此前有**两套**日期形态并存，而且都不是语言驱动的 ——
 * 会话列表用 `21.09.2026` 加一张写死的英文星期表，聊天页日期头与生日行则无论界面
 * 是什么语言都恒输出 `9月21日`。英文界面上因此直接出现中文日期（设备实测过）。
 *
 * 语义对齐 Android `core/Lang.java`（`getDate` / `timeOrDateShort`）：
 * - **当年不写年份，跨年才补年份**（旧实现是永远带 4 位年份）；
 * - 会话列表档位：当天 → 时间，一周内 → 星期，更早 → 日期；
 * - 聊天页日期头用**长月份名**（`September 21`），列表与条目用**缩写**（`Sep 21`）。
 * 一处刻意的偏差记在 `formatMonthDayYear` 上：Android 跨年走的是 `d MMM ''yy`
 * （两位年），本端输出完整四位年 —— 两位年在 `''yy` 里还带一个转义撇号，
 * 在两种语言里都不是更好的读法，而「是否跨年」这条语义已经保住了。
 *
 * 与 `Lang` 的分工：`Lang` 管**句子里的串**（按 key 取词条），这里管**日期模板的槽位**
 * （月份名、星期名、年月日的排布）。后者是 locale 数据而不是文案，放进词典会让
 * EN/ZH 词条对等检查出现一堆只为拼日期而存在的 key。也因此全仓**只有这个文件**
 * 允许出现月份名/星期名和 `N月M日`、`dd.MM` 这类形态串（守卫 R8 强制）。
 *
 * 全部为纯函数：入参只有语言码与数字，不读时钟、不引 Kit，所以时区与「今天」由调用方
 * 传入（`datePartsFrom` 负责从毫秒取本地字段）。换语言后能重算是调用方的事 ——
 * 页面把响应式语言位当 `lang` 传进来即可（I18N-HOTSWITCH-101 已铺好那条 tick）。
 */

import { SupportedLanguage, HourClock } from './Lang';

const MS_PER_DAY: number = 24 * 60 * 60 * 1000;

/**
 * 英文月份缩写（`MMM`）与长名（`MMMM`），下标即 0-11 月。
 * CLDR en 的 `MMM` 就是这十二个三字母形，`MMMM` 是它们的长形。
 */
const MONTHS_ABBR_EN: string[] = [
  'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'
];
const MONTHS_FULL_EN: string[] = [
  'January', 'February', 'March', 'April', 'May', 'June',
  'July', 'August', 'September', 'October', 'November', 'December'
];
/**
 * CLDR en 的 `ccc`（独立形星期缩写）。会话列表一周内的那一档以前是一张
 * `['Sun','Mon',…]` 的私有表 —— 那是本仓唯一一处「语言固定成英文」的 locale 数据，
 * 现在由这里统一给。
 */
const WEEKDAYS_ABBR_EN: string[] = ['Sun', 'Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat'];
/**
 * CLDR zh-Hans 的 `ccc`：`周日 / 周一 …`。注意 0 号是**周日**，
 * 与 `Date.getDay()` 对齐，不是 ISO 的周一为一周起点。
 */
const WEEKDAYS_ABBR_ZH: string[] = ['周日', '周一', '周二', '周三', '周四', '周五', '周六'];

/**
 * 12 小时制的上下午标记（CLDR 的 `a`，system 时钟显示用的就是这两档）。
 * 中文侧不做「凌晨/中午/傍晚/晚上」的四档细分 —— 那是 CLDR 的 *wide format* 规则，
 * 系统时间与即时通讯里的时刻显示都不用它，跟着它走反而和状态栏对不上。
 */
const DAY_PERIOD_EN: string[] = ['AM', 'PM'];
const DAY_PERIOD_ZH: string[] = ['上午', '下午'];

/**
 * 日期的本地字段。`month` 用 1-12（人读的习惯），`weekday` 用 0-6 且 0 = 周日
 * （与 `Date.getDay()` 一致，避免两套下标在表里错位）。
 */
export class DateParts {
  readonly year: number;
  readonly month: number;
  readonly day: number;
  readonly weekday: number;
  readonly hour: number;
  readonly minute: number;

  constructor(
    year: number, month: number, day: number, weekday: number, hour: number, minute: number
  ) {
    this.year = year;
    this.month = month;
    this.day = day;
    this.weekday = weekday;
    this.hour = hour;
    this.minute = minute;
  }
}

function pad2(value: number): string {
  return value < 10 ? `0${value}` : `${value}`;
}

/** 取本地时区字段的 month(1-12)/weekday(0=周日) 等；`Date` 自己会把入参折算成合法日期，所以这里无需兜底。 */
export function datePartsFrom(ms: number): DateParts {
  const d: Date = new Date(ms);
  return new DateParts(
    d.getFullYear(),
    d.getMonth() + 1,
    d.getDate(),
    d.getDay(),
    d.getHours(),
    d.getMinutes()
  );
}

/** 本地自然日起点（用于「一周内」这类按天而不是按 24 小时的比较，避开 DST）。 */
export function startOfDayMs(ms: number): number {
  const d: Date = new Date(ms);
  return new Date(d.getFullYear(), d.getMonth(), d.getDate()).getTime();
}

/** 两个时刻相差的自然日数（`at` 在过去时为正）。 */
export function daysBetween(atMs: number, nowMs: number): number {
  return Math.round((startOfDayMs(nowMs) - startOfDayMs(atMs)) / MS_PER_DAY);
}

export function isSameDayParts(a: DateParts, b: DateParts): boolean {
  return a.year === b.year && a.month === b.month && a.day === b.day;
}

/**
 * 英文月份缩写（`MMM`）。中文没有月份名（CLDR zh 的 `MMM`/`MMMM` 都是 `N月`），
 * 所以这两张表只在 `lang === 'en'` 的路径上被读到，越界月份夹回数字而不是抛错。
 */
function monthAbbrOf(month: number): string {
  const index: number = month - 1;
  return index >= 0 && index < MONTHS_ABBR_EN.length ? MONTHS_ABBR_EN[index] : `${month}`;
}

function monthFullOf(month: number): string {
  const index: number = month - 1;
  return index >= 0 && index < MONTHS_FULL_EN.length ? MONTHS_FULL_EN[index] : `${month}`;
}

/**
 * 时间。档位由调用方给（`HourClock`，装配层从系统 `i18n.System.is24HourClock()` 取）——
 * 这一档此前是**写死的 24 小时制**：系统设成 12 小时制时，中文界面出 `14:30`、
 * 英文界面也该出 `2:30 PM`，而本端两处都不跟着变。
 * 12 小时制的上下午标记属于 locale 槽位而不是文案（CLDR 的 `a` 形），所以留在本文件。
 */
export function formatTimeOfDay(p: DateParts, lang: SupportedLanguage, clock: HourClock): string {
  if (clock === '24h') {
    return `${pad2(p.hour)}:${pad2(p.minute)}`;
  }
  // h12 规矩：0 点显示 12、12 点显示 12，其余取模。
  const h12: number = p.hour % 12 === 0 ? 12 : p.hour % 12;
  const minute: string = `:${pad2(p.minute)}`;
  if (lang === 'zh') {
    return `${p.hour < 12 ? DAY_PERIOD_ZH[0] : DAY_PERIOD_ZH[1]}${h12}${minute}`;
  }
  return `${h12}${minute} ${p.hour < 12 ? DAY_PERIOD_EN[0] : DAY_PERIOD_EN[1]}`;
}

/** 星期缩写（一周内的会话列表那一档）。 */
export function formatWeekdayShort(lang: SupportedLanguage, weekday: number): string {
  if (lang === 'zh') {
    return weekday >= 0 && weekday < WEEKDAYS_ABBR_ZH.length
      ? WEEKDAYS_ABBR_ZH[weekday]
      : `${weekday}`;
  }
  return weekday >= 0 && weekday < WEEKDAYS_ABBR_EN.length
    ? WEEKDAYS_ABBR_EN[weekday]
    : `${weekday}`;
}

/** `Sep 21` / `9月21日` —— 条目与列表用的短日期，不含年份。 */
export function formatMonthDay(lang: SupportedLanguage, p: DateParts): string {
  if (lang === 'zh') {
    return `${p.month}月${p.day}日`;
  }
  return `${monthAbbrOf(p.month)} ${p.day}`;
}

/** `Sep 21, 2025` / `2025年9月21日` —— 跨年时才用这一档。 */
export function formatMonthDayYear(lang: SupportedLanguage, p: DateParts): string {
  if (lang === 'zh') {
    return `${p.year}年${p.month}月${p.day}日`;
  }
  return `${monthAbbrOf(p.month)} ${p.day}, ${p.year}`;
}

/** `September 21` / `9月21日` —— 聊天页日期头用的长月份名档。 */
export function formatMonthDayLong(lang: SupportedLanguage, p: DateParts): string {
  if (lang === 'zh') {
    return `${p.month}月${p.day}日`;
  }
  return `${monthFullOf(p.month)} ${p.day}`;
}

/**
 * 列表/条目日期：与 `now` 同年就不写年份，跨年才写。
 * 这就是旧实现缺的那条判据（它无条件输出 `dd.MM.yyyy`）。
 */
export function formatDateCompact(lang: SupportedLanguage, p: DateParts, now: DateParts): string {
  return p.year === now.year ? formatMonthDay(lang, p) : formatMonthDayYear(lang, p);
}

/**
 * 聊天页日期头：同年 `September 21`，跨年 `September 21, 2025`。
 * 跨年这一档英文仍用长月份名 —— 日期头是段落级的大字标题，缩写只属于列表/条目。
 */
export function formatDateHeader(lang: SupportedLanguage, p: DateParts, now: DateParts): string {
  if (p.year === now.year) {
    return formatMonthDayLong(lang, p);
  }
  if (lang === 'zh') {
    return formatMonthDayYear(lang, p);
  }
  return `${monthFullOf(p.month)} ${p.day}, ${p.year}`;
}

/**
 * 日期 + 时刻（活跃会话行）：中文 `9月21日 14:30`，英文 `Sep 21 at 14:30`。
 * 英文用介词 `at` 而不是逗号：跨年时日期本身已经带一个逗号
 * （`Sep 21, 2025`），再接 `, 14:30` 就成了三段逗号堆叠。`at` 和「年月日」
 * 一样是 locale 的连接词，不是文案，所以留在本文件（守卫 R8）。
 */
export function formatDateTimeCompact(
  lang: SupportedLanguage, p: DateParts, now: DateParts, clock: HourClock
): string {
  const date: string = formatDateCompact(lang, p, now);
  const time: string = formatTimeOfDay(p, lang, clock);
  return lang === 'zh' ? `${date} ${time}` : `${date} at ${time}`;
}

/** 自然月头（共享内容跨月分段）：`September 2025` / `2025年9月`。 */
export function formatMonthYear(lang: SupportedLanguage, p: DateParts): string {
  if (lang === 'zh') {
    return `${p.year}年${p.month}月`;
  }
  return `${monthFullOf(p.month)} ${p.year}`;
}

/**
 * 生日行：`Sep 21, 1990 (36 years)` / `1990年9月21日（36 岁）`；
 * TDLib 的 `year = 0` 表示对方没填年份，退化成 `Sep 21` / `9月21日`。
 * 括号的半角/全角和「岁」一样属于模板形态而不是文案（CLDR zh 的 append 形就是全角），
 * 所以不建词条 —— 这类形态统一收在本文件（守卫 R8）。
 * 此前 feature/profile 与 feature/self 各写了一份同样的周岁算法，这里是唯一一处。
 */
export function formatBirthday(
  lang: SupportedLanguage, year: number, month: number, day: number, now: DateParts
): string {
  const parts: DateParts = new DateParts(year, month, day, 0, 0, 0);
  if (year <= 0) {
    return formatMonthDay(lang, parts);
  }
  const date: string = formatMonthDayYear(lang, parts);
  const label: string = formatAgeLabel(lang, ageOf(year, month, day, now));
  return lang === 'zh' ? `${date}（${label}）` : `${date} (${label})`;
}

/**
 * 会话列表行的时间戳：当天 → 时刻（按 `clock` 档给 24 或 12 小时制）；一周内 → 星期；
 * 更早 → 按当年/跨年给日期。
 * 档位判据与 Android `Lang.timeOrDateShort` 一致，形态由 `lang` 决定。
 */
export function formatListTimestamp(
  lang: SupportedLanguage, atMs: number, nowMs: number, clock: HourClock
): string {
  const at: DateParts = datePartsFrom(atMs);
  const now: DateParts = datePartsFrom(nowMs);
  if (isSameDayParts(at, now)) {
    return formatTimeOfDay(at, lang, clock);
  }
  const days: number = daysBetween(atMs, nowMs);
  if (days > 0 && days < 7) {
    return formatWeekdayShort(lang, at.weekday);
  }
  return formatDateCompact(lang, at, now);
}

/**
 * 年龄短语：`31 岁` / `31 years` / `1 year`。
 * 放在这里而不是词典里，因为要选的是**单复数档**（英文 one/other 两档），而本仓的
 * `Lang` 没有 CLDR 复数引擎 —— 词条表里放 `{0} year` 和 `{0} years` 两条再由调用方
 * 挑，等于把复数规则散回业务层。中文没有变形，直接 `岁`。
 * 「生日 + 年龄」的拼法（括号形）属于模板而不是文案，所以也收在这里而不是词条。
 */
export function formatAgeLabel(lang: SupportedLanguage, age: number): string {
  if (lang === 'zh') {
    return `${age} 岁`;
  }
  return age === 1 ? `${age} year` : `${age} years`;
}

/**
 * 周岁：只在**知道出生年份**时算，且出生日还没到要减一岁。
 * 与旧实现同判据，收进这里是为了让生日那一行只有一个算法。
 */
export function ageOf(
  birthYear: number, birthMonth: number, birthDay: number, now: DateParts
): number {
  let age: number = now.year - birthYear;
  if (now.month < birthMonth || (now.month === birthMonth && now.day < birthDay)) {
    age = age - 1;
  }
  return age < 0 ? 0 : age;
}
