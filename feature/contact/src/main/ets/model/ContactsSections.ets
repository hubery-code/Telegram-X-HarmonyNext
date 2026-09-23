/**
 * feature/contact — 联系人分组与索引的纯函数（CONTACT-101）。
 *
 * 规则逐条对齐 Android `ContactsController.sortUsers()`（:906-946）与
 * `tool/Strings.clean()`：
 * - **排序键** = `clean((firstName + ' ' + lastName).trim())` 再小写，即剥掉 ASCII 标点
 *   后再比较（`-Anna` 排在 `Anna` 一侧而不是被符号挤到列表尾部），按 UTF-16 码元序比较；
 *   小写化是本端刻意加的，理由见 `contactSortKey`；
 * - **分组字母** = 全名（**不** clean）首个码点大写；空名 / 首字符是数字 / 首码点是落单
 *   代理对 → `'#'`。非拉丁文字（西里尔、CJK、带变音符的越南语）各自成组，不再一律塌进
 *   `'#'`；
 * - 排序与分组必须出自**同一套**规则，否则同名首字母会被拆成两段，`ForEach` 的 key 会
 *   重复（ArkUI 下表现为条目错乱）。
 *
 * 本文件不得 import `@kit` / `ohos`：reducer 与页面都要复用这些函数，且必须能在纯
 * 单测里跑。
 */

import { ContactsItem, ContactsSection } from '../contract/ContactsUiState';

/** Android `Strings.clean`：剥掉 ASCII 标点（33-47、58-63、91-96、123-126）。 */
export function cleanContactKey(input: string): string {
  let out: string = '';
  for (let i: number = 0; i < input.length; i++) {
    const c: number = input.charCodeAt(i);
    const isPunctuation: boolean =
      (c >= 33 && c <= 47) || (c >= 58 && c <= 63) || (c >= 91 && c <= 96) || (c >= 123 && c <= 126);
    if (!isPunctuation) {
      out += input.charAt(i);
    }
  }
  return out;
}

/**
 * 排序键：剥标点后的全名，**再转小写**。
 *
 * 这里刻意偏离 Android 一处：`TGUser.getSortingKey()` 只 clean、不转大小写，比较走
 * 码元序，于是 `bob` 会排到 `Zoe` 之后，同一个首字母被大小写劈成两段（分组字母是大写，
 * 段又由相邻同字母归出）。分组字母必须随列表单调，故键统一小写化。
 */
export function contactSortKey(item: ContactsItem): string {
  return cleanContactKey(item.displayName.trim()).toLowerCase();
}

/**
 * 稳定排序比较器（Array.prototype.sort 在 ArkTS/ES2019 起是稳定的，等价于 Java
 * Collections.sort 的 TimSort：同键联系人保持 TDLib 回包顺序）。
 */
export function compareContacts(a: ContactsItem, b: ContactsItem): number {
  const ka: string = contactSortKey(a);
  const kb: string = contactSortKey(b);
  if (ka < kb) {
    return -1;
  }
  if (ka > kb) {
    return 1;
  }
  return 0;
}

/**
 * 分组字母：全名首个码点大写；空名、数字开头、落单代理对归 `'#'`。
 * 与 Android 一致：只把 ASCII 数字归 `'#'`（Java 的 Character.isDigit 覆盖 Unicode 数字，
 * 这里按 ASCII 处理，非 ASCII 数字更常见于名字中间而不是开头）。
 */
export function sectionLetterOf(displayName: string): string {
  const name: string = displayName.trim();
  if (name.length === 0) {
    return '#';
  }
  const high: number = name.charCodeAt(0);
  if (high >= 0xD800 && high <= 0xDBFF) {
    // 代理对高项：必须配一个低项才算一个完整码点
    if (name.length < 2) {
      return '#';
    }
    const low: number = name.charCodeAt(1);
    if (low < 0xDC00 || low > 0xDFFF) {
      return '#';
    }
    return name.substring(0, 2).toUpperCase();
  }
  if (high >= 0xDC00 && high <= 0xDFFF) {
    return '#';
  }
  if (high >= 0x30 && high <= 0x39) {
    return '#';
  }
  return name.charAt(0).toUpperCase();
}

/**
 * 按相邻同字母归段（Android 同规则：分组由**已排序**数组的连续段推出）。
 * 返回的每段带 `startIndex`（段首在扁平 items 里的下标），供索引条定位。
 */
export function buildContactsSections(items: ContactsItem[]): ContactsSection[] {
  const sections: ContactsSection[] = [];
  for (let i: number = 0; i < items.length; i++) {
    const letter: string = sectionLetterOf(items[i].displayName);
    const last: ContactsSection | null = sections.length > 0 ? sections[sections.length - 1] : null;
    if (last !== null && last.letter === letter) {
      last.items.push(items[i]);
    } else {
      sections.push(new ContactsSection(letter, [items[i]], i));
    }
  }
  return sections;
}

/**
 * 每个分组在列表里的滚动位移（vp）：前面所有分组的「标题高 + 行高 × 条数 + 组间分隔线」
 * 之和。行高/标题高都是固定值（List 的行不做自适应），所以位移可以纯算出来，
 * 不需要测量真实布局。
 *
 * `groupGap` 是 `List.divider` 在每个 `ListItemGroup` 边界上多占的那一段：实测
 * （模拟器 3.5 密度）单条组间距 94vp = 28 标题 + 64 行 + 2 分隔线，两条组 158vp
 * = 28 + 64×2 + 2 —— 组内相邻行间距是干净的 64vp，分隔线只按**组**计一次。
 * 漏掉这一项会让跳转落点每组累计偏 2vp，越往后偏得越多（Z 段实测偏 56vp）。
 */
export function sectionScrollOffsets(
  sections: ContactsSection[],
  headerHeight: number,
  rowHeight: number,
  groupGap: number
): number[] {
  const offsets: number[] = [];
  let y: number = 0;
  for (let i: number = 0; i < sections.length; i++) {
    offsets.push(y);
    y += headerHeight + sections[i].items.length * rowHeight + groupGap;
  }
  return offsets;
}

/** 当前滚动位移落在哪个分组：最后一个「起点 ≤ offset」的段。 */
export function activeSectionIndex(offsets: number[], yOffset: number): number {
  let active: number = 0;
  for (let i: number = 0; i < offsets.length; i++) {
    if (offsets[i] <= yOffset + 0.5) {
      active = i;
    }
  }
  return active;
}

/** 索引条只在「有多于一个分组」时出现：单字母条既无信息也无法跳转。 */
export function indexBarVisible(sections: ContactsSection[]): boolean {
  return sections.length > 1;
}

/**
 * 拖拽索引条时的一次换算结果：落到的分组下标 + 该字母在索引条里的中心位移。
 * 中心位移用来摆当前段气泡（气泡跟着手指走，而不是跟着列表滚动走）。
 */
export class IndexScrubHit {
  readonly index: number;
  readonly centerY: number;

  constructor(index: number = -1, centerY: number = 0) {
    this.index = index;
    this.centerY = centerY;
  }
}

/**
 * 手指落在索引条的哪个字母上（CONTACT-102 拖拽 scrub）。
 *
 * 索引条是 `Column({justifyContent: Center})` + 每个字母固定 `letterHeight`、无间距，
 * 所以整条的排版是纯几何的，不必测真实布局：
 * - 内容高 `contentHeight = letterCount * letterHeight`；
 * - 上下留白 `topPad = max(0, (barHeight - contentHeight) / 2)`；
 * - 手指 `localY`（组件内坐标，vp）落在 `floor((localY - topPad) / letterHeight)`。
 *
 * 手指拖出索引条上下沿时**夹到首/尾段**而不是取消：Android 的 thumb 同样是拖到底
 * 就停在最后一段，做出「拖出即失效」反而让长列表末尾够不到。
 *
 * `barHeight <= 0`（还没量到）或没有字母时返回 `index = -1`，调用方据此不动状态。
 */
export function indexScrubAt(
  barHeight: number,
  letterCount: number,
  localY: number,
  letterHeight: number
): IndexScrubHit {
  if (barHeight <= 0 || letterCount <= 0 || letterHeight <= 0) {
    return new IndexScrubHit(-1, 0);
  }
  const contentHeight: number = letterCount * letterHeight;
  const topPad: number = barHeight > contentHeight ? (barHeight - contentHeight) / 2 : 0;
  let index: number = Math.floor((localY - topPad) / letterHeight);
  if (index < 0) {
    index = 0;
  }
  if (index > letterCount - 1) {
    index = letterCount - 1;
  }
  return new IndexScrubHit(index, topPad + index * letterHeight + letterHeight / 2);
}
